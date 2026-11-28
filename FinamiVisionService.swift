import SwiftUI
import PhotosUI
import Vision
import CryptoKit
import ImageIO
import CoreImage
import UIKit

struct ScanPhoto: Identifiable {
    let id: String
    let lines: [String]
    let image: Data?
    var warning: String? = nil
    var mergedDraft: ScanInstallmentDraft? = nil
    var sourceIDs: [String]? = nil
    var bankHint: String? = nil
    var ocrRegions: [ScanTextRegion] = []
    var bank: String? { FinamiScanParser.bank(lines.joined(separator: "\n")) ?? (mergedDraft?.pumbParts == true ? "ПУМБ" : bankHint) }
}
enum ScanFailure: LocalizedError {
    case image, empty
    var errorDescription: String? { self == .image ? "Не вдалося відкрити фото або воно перевищує 25 МБ." : "Текст не знайдено. Спробуй чіткіший скриншот." }
}
func recognizeScan(_ data: Data, knownDigest: String? = nil, installment: Bool = false, bankHint: String? = nil) throws -> ScanPhoto {
    guard data.count <= 25_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ScanFailure.image }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3000]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ScanFailure.image }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if installment {
        request.minimumTextHeight = 0.006
        request.customWords = ["розстрочка", "залишилось", "залишок", "щомісячний", "платіж", "погашення", "грн", "ПУМБ", "Сплачуйте частинами", "Внесено", "Залишилося", "Оформлено"]
    }
    let available = (try? request.supportedRecognitionLanguages()) ?? []
    let preferred = ["uk-UA", "en-US", "ru-RU"].filter { available.contains($0) }
    if !preferred.isEmpty { request.recognitionLanguages = preferred }
    var warning: String? = nil
    var recognized = request
    do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch {
        let retry = VNRecognizeTextRequest()
        retry.recognitionLevel = .accurate
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([retry]); recognized = retry }
        catch { warning = "Vision не зміг розпізнати текст: " + error.localizedDescription }
    }
    if (recognized.results ?? []).isEmpty {
        let retry = VNRecognizeTextRequest(); retry.recognitionLevel = .accurate; retry.usesLanguageCorrection = false
        if (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([retry])) != nil, !(retry.results ?? []).isEmpty { recognized = retry; warning = nil }
    }
    // Preserve horizontal reading order in both Vision passes. The second pass
    // disables language correction only when the installment fields are incomplete.
    func rows(_ request: VNRecognizeTextRequest) -> [String] {
        let observations = (request.results ?? []).compactMap { o -> (CGRect, String)? in
            guard let text = o.topCandidates(1).first?.string else { return nil }
            return (o.boundingBox, text)
        }.sorted { $0.0.midY > $1.0.midY }
        var groups: [[(CGRect, String)]] = []
        for observation in observations {
            if let first = groups.last?.first, abs(first.0.midY - observation.0.midY) < min(first.0.height, observation.0.height) * 0.45 {
                groups[groups.count - 1].append(observation)
            } else { groups.append([observation]) }
        }
        return groups.map { $0.sorted { $0.0.minX < $1.0.minX }.map { $0.1 }.joined(separator: " ") }
    }
    func regionsFor(_ request: VNRecognizeTextRequest) -> [ScanTextRegion] {
        (request.results ?? []).flatMap { observation -> [ScanTextRegion] in
            guard let candidate = observation.topCandidates(1).first else { return [] }
            let ranges = FinamiScanParser.installmentSubregionRanges(candidate.string)
            let parts = ranges.compactMap { range -> ScanTextRegion? in
                guard let box = try? candidate.boundingBox(for: range) else { return nil }
                return ScanTextRegion(text: String(candidate.string[range]), bounds: box.boundingBox)
            }
            if !ranges.isEmpty && parts.count == ranges.count { return parts }
            return [ScanTextRegion(text: candidate.string, bounds: observation.boundingBox)]
        }
    }
    func installmentDraft(_ request: VNRecognizeTextRequest, lines: [String]) -> ScanInstallmentDraft {
        let regions = regionsFor(request)
        let bank = FinamiScanParser.bank(lines.joined(separator: "\n")) ?? bankHint
        let rules = FinamiOCRProfiles.rules(bank)
        let normalized = lines.map { FinamiOCRProfiles.rewrite($0, rules: rules) }
        let normalizedRegions = regions.map { ScanTextRegion(text: FinamiOCRProfiles.rewrite($0.text, rules: rules), bounds: $0.bounds) }
        return FinamiScanParser.installment(normalized, regions: normalizedRegions)
    }
    var lines = rows(recognized)
    var collectedRegions = installment ? regionsFor(recognized) : []
    var seenRegionTexts = Set(collectedRegions.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    var mergedDraft: ScanInstallmentDraft?
    if installment {
        var drafts = [installmentDraft(recognized, lines: lines)]
        func incomplete(_ d: ScanInstallmentDraft) -> Bool { d.total == nil || d.remaining == nil || d.monthly == nil || d.due == nil }
        func appendPass(_ cg: CGImage, correction: Bool) {
            let alternate = VNRecognizeTextRequest()
            alternate.recognitionLevel = .accurate
            alternate.usesLanguageCorrection = correction
            alternate.minimumTextHeight = 0.004
            if !preferred.isEmpty { alternate.recognitionLanguages = preferred }
            if (try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([alternate])) != nil {
                let extra = rows(alternate)
                if !extra.isEmpty {
                    let extraRegions = regionsFor(alternate)
                    for region in extraRegions {
                        let key = region.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if !key.isEmpty && seenRegionTexts.insert(key).inserted {
                            collectedRegions.append(region)
                        }
                    }
                    drafts.append(installmentDraft(alternate, lines: extra))
                    var seen = Set(lines)
                    lines += extra.filter { seen.insert($0).inserted }
                }
            }
        }
        if incomplete(drafts[0]) { appendPass(image, correction: false) }
        if incomplete(finamiMergeInstallments(drafts).draft) {
            // Bounded grayscale contrast pass, preserving the original orientation.
            let enhanced = CIImage(cgImage: image).applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0, "inputContrast": 1.35])
            let context = CIContext(options: [.cacheIntermediates: false])
            if let cg = context.createCGImage(enhanced, from: enhanced.extent) { appendPass(cg, correction: false) }
        }
        let structured = drafts.filter { $0.pumbParts }
        let merged = finamiMergeInstallments(structured.isEmpty ? drafts : structured)
        mergedDraft = merged.draft
        if !merged.conflicts.isEmpty { warning = "OCR: суперечливі поля залишено для перевірки: " + merged.conflicts.joined(separator: ", ") }
        if let detected = FinamiScanParser.bank(lines.joined(separator: "\n")), let bankHint, detected != bankHint {
            warning = (warning.map { $0 + " · " } ?? "") + "Знайдено інший банк: " + detected + ". Перевір договір."
        }
    }
    if lines.isEmpty && warning == nil { warning = "Текст не знайдено. Можна заповнити чернетку вручну." }
    let previewOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200]
    let jpeg = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOptions as CFDictionary).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.7) }
    let digest = knownDigest ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return ScanPhoto(id: digest, lines: lines, image: jpeg, warning: warning, mergedDraft: mergedDraft, bankHint: bankHint, ocrRegions: collectedRegions)
}
