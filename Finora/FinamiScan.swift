import SwiftUI
import PhotosUI
import Vision
import CryptoKit
import ImageIO
import CoreImage
import UIKit

enum FinamiScanMode: String, CaseIterable, Identifiable {
    case transactions = "Операції", installment = "Розстрочка", balance = "Рахунок"
    var id: String { rawValue }
}
private struct ScanPhoto: Identifiable {
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
private enum ScanFailure: LocalizedError {
    case image, empty
    var errorDescription: String? { self == .image ? "Не вдалося відкрити фото або воно перевищує 25 МБ." : "Текст не знайдено. Спробуй чіткіший скриншот." }
}
private func recognizeScan(_ data: Data, knownDigest: String? = nil, installment: Bool = false, bankHint: String? = nil) throws -> ScanPhoto {
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
    let previewOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600]
    let jpeg = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOptions as CFDictionary).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.7) }
    let digest = knownDigest ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return ScanPhoto(id: digest, lines: lines, image: jpeg, warning: warning, mergedDraft: mergedDraft, bankHint: bankHint, ocrRegions: installment ? regionsFor(recognized) : [])
}
struct FinamiScanView: View {
    @EnvironmentObject private var s: Store
    @State private var mode: FinamiScanMode
    @State private var selections: [PhotosPickerItem] = []
    @State private var photos: [ScanPhoto] = []
    @State private var busy = false
    @State private var singleReview = false
    @State private var errors: [String] = []
    @State private var manualText = ""
    @State private var chosenBank = ""
    init(initialMode: FinamiScanMode = .transactions) { _mode = State(initialValue: initialMode) }
    var body: some View {
        VStack(spacing: 0) {
            scanStatus
            scanList
        }
        .navigationTitle("Finami Scan")
        .navigationDestination(isPresented: $singleReview) {
            if let photo = photos.first { reviewDestination(photo) }
        }
        .onChange(of: selections) { items in
            loadSelections(items)
        }
    }
    private var scanList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "doc.viewfinder").font(.system(size: 36)).foregroundStyle(.purple)
                    Text("Finami Scan").font(.title.bold())
                    Text("Додай скриншот банку. Перевір розпізнані дані перед збереженням.").foregroundStyle(.secondary)
                }.padding(.vertical, 12)
                Picker("Тип імпорту", selection: $mode) { ForEach(FinamiScanMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).disabled(busy)
                if mode == .installment {
                    Picker("Банк для OCR", selection: $chosenBank) {
                        Text("Автоматично").tag("")
                        ForEach(FinamiOCRProfiles.banks, id: \.self) { Text($0).tag($0) }
                    }.disabled(busy)
                    NavigationLink("Вивчені підписи OCR") { FinamiOCRRulesView() }
                }
                PhotosPicker(selection: $selections, maxSelectionCount: 10, matching: .images) { Label("Обрати скриншоти", systemImage: "photo.on.rectangle.angled") }.disabled(busy)
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--finami-qa") {
                    Button("QA: тестове фото розстрочки") { runQAImage() }.disabled(busy).accessibilityIdentifier("qa.scan.fixture.installment")
                    Button("QA: розстрочка у двох колонках") { runQAImage(stacked: true) }.disabled(busy).accessibilityIdentifier("qa.scan.fixture.installment.columns")
                    Button("QA: ПУМБ — нульовий внесок") { runQAImage(pumb: true) }.disabled(busy).accessibilityIdentifier("qa.scan.fixture.pumb.zero")
                }
                #endif
                DisclosureGroup("Резервний імпорт тексту") {
                    Text("Якщо фото не читається, скопіюй текст з фото через Live Text і встав сюди. Перевір дані перед збереженням.").font(.caption)
                    TextEditor(text: $manualText).frame(minHeight: 110).accessibilityLabel("Текст зі скриншота")
                    Button("Розпізнати вставлений текст") {
                        let text = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty, text.count <= 40_000 else { return }
                        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
                        if !photos.contains(where: { $0.id == digest }) { photos.append(ScanPhoto(id: digest, lines: lines, image: nil, bankHint: chosenBank.isEmpty ? nil : chosenBank)) }; manualText = ""
                    }.disabled(busy || manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manualText.count > 40_000)
                }
                if !photos.isEmpty { Button("Очистити список") { photos = []; errors = [] }.disabled(busy) }
            }
            if !photos.isEmpty {
                Section("Перевірити скриншоти") {
                    if mode == .installment && photos.count > 1 {
                        NavigationLink { ScanInstallmentReview(photo: mergedPhoto()) } label: {
                            Label("Об’єднати всі фото одного договору", systemImage: "rectangle.on.rectangle")
                        }.disabled(busy)
                        Text("Об’єднуй тільки фото одного договору. Суперечливі поля залишаться порожніми.").font(.caption)
                    }

                    ForEach(photos) { photo in
                        NavigationLink {
                            reviewDestination(photo)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(photo.bank ?? "Банк не визначено", systemImage: "doc.text.viewfinder")
                                Text("\(photo.lines.count) рядків · \(mode.rawValue)").font(.caption).foregroundStyle(.secondary)
                                if let warning = photo.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
                                Label("Відкрити та перевірити", systemImage: "chevron.right").font(.caption)
                                if s.db.operations.contains(where: { $0.scanFingerprint?.hasPrefix(photo.id + ":") == true }) || s.db.obligations.contains(where: { $0.scanFingerprint == photo.id }) { Text("Раніше імпортовано повністю або частково").font(.caption).foregroundStyle(.orange) }
                            }
                        }.disabled(busy).accessibilityIdentifier("qa.scan.review." + photo.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { photos.removeAll { $0.id == photo.id } } label: { Label("Прибрати фото", systemImage: "trash") }
                        }
                    }
                }
            }
            if !errors.isEmpty { Section("Не вдалося розпізнати") { ForEach(Array(errors.enumerated()), id: \.offset) { entry in Text(entry.element).font(.caption) } } }
            Section("Як це працює") {
                Text("Vision читає текст локально. Не всі банки мають однаковий формат. Нерозпізнані дати, суми та категорії можна ввести вручну. Збереження виконується тільки після підтвердження.")
                Text("Не додавай знімки з PIN, CVV чи повними номерами карток. Збережені вкладення входять до JSON-копії та можуть залишитися у старих резервних копіях.")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func loadSelections(_ items: [PhotosPickerItem]) {
            guard !items.isEmpty, !busy else { return }
            busy = true; errors = []
            Task { @MainActor in
                defer { busy = false; selections = [] }
                for (index, item) in items.enumerated() {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw ScanFailure.image }
                        guard data.count <= 25_000_000 else { throw ScanFailure.image }
                        let known = Set(photos.map(\.id))
                        let isInstallment = mode == .installment
                        let hint: String? = isInstallment && !chosenBank.isEmpty ? chosenBank : nil
                        let photo = try await Task.detached(priority: .userInitiated) { () throws -> ScanPhoto? in
                            let digest = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
                            guard !known.contains(digest) else { return nil }
                            return try recognizeScan(data, knownDigest:digest, installment: isInstallment, bankHint: hint)
                        }.value
                        if let photo, !photos.contains(where: { $0.id == photo.id }) { photos.append(photo) }
                    } catch { errors.append("Фото \(index + 1): \(error.localizedDescription)") }
                }
            }
    }
    // Keep the result of a single import visible even when the list's review
    // section has not been materialized by SwiftUI. Same destination for both
    // entry points; never bypass the actual OCR pipeline or confirmation form.
    @ViewBuilder private var scanStatus: some View {
        if busy {
            ProgressView("Розпізнавання на пристрої…")
                .accessibilityIdentifier("qa.scan.processing")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(.regularMaterial)
        } else if photos.count == 1, let photo = photos.first {
            VStack(alignment: .leading, spacing: 6) {
                Button { singleReview = true } label: {
                    HStack {
                        Image(systemName: "doc.text.viewfinder")
                        Text("Відкрити та перевірити").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("qa.scan.open.single")
                Text("\(photo.lines.count) рядків · \(mode.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
                if let warning = photo.warning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                if !errors.isEmpty { Text("Не всі фото оброблено. Деталі — у списку нижче.").font(.caption).foregroundStyle(.orange) }
            }.padding(.horizontal, 16).padding(.vertical, 8).background(.regularMaterial)
        } else if !errors.isEmpty {
            Label("Не вдалося обробити фото. Перевір повідомлення у списку нижче.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
                .accessibilityIdentifier("qa.scan.failed")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(.regularMaterial)
        } else if photos.count > 1 {
            Text("Оброблено фото: \(photos.count). Перевір їх у списку або об’єднай фото одного договору.")
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(.regularMaterial)
        }
    }
    @ViewBuilder private func reviewDestination(_ photo: ScanPhoto) -> some View {
        if mode == .transactions { ScanTransactionsReview(photo: photo) }
        else if mode == .installment { ScanInstallmentReview(photo: photo) }
        else { ScanBalanceReview(photo: photo) }
    }
    private func mergedPhoto() -> ScanPhoto {
        let merged = finamiMergeInstallments(photos.map { photo in
            let rules = FinamiOCRProfiles.rules(photo.bank)
            return photo.mergedDraft ?? FinamiScanParser.installment(photo.lines.map { FinamiOCRProfiles.rewrite($0, rules: rules) }, regions: photo.ocrRegions)
        })
        let banks = Set(photos.compactMap(\.bank))
        let ids = photos.map(\.id).sorted()
        let id = SHA256.hash(data: Data(ids.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
        return ScanPhoto(id: id, lines: photos.flatMap(\.lines), image: nil, warning: merged.conflicts.isEmpty ? "Перевір, що всі фото належать одному договору." : "Суперечливі поля: " + merged.conflicts.joined(separator: ", "), mergedDraft: merged.draft, sourceIDs: ids, bankHint: banks.count == 1 ? banks.first : nil)
    }
    #if DEBUG && targetEnvironment(simulator)
    private func runQAImage(stacked: Bool = false, pumb: Bool = false) {
        mode = .installment; busy = true; photos = []; errors = []
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: 1000, height: 1250)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            if pumb {
                UIColor.black.setFill(); context.fill(CGRect(origin: .zero, size: size))
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.white]
                let rows: [(String, CGFloat, CGFloat)] = [
                    ("Сплачуйте частинами", 230, 55), ("ПУМБ", 430, 160),
                    ("12 000,00 ₴", 330, 290), ("Оформлено 15.10.2026", 250, 355),
                    ("Внесено 2 з 3 щомісячних платежів", 45, 495),
                    ("Наступний платіж", 45, 650), ("Залишилося", 680, 650),
                    ("0,00 ₴", 45, 705), ("4 000,00 ₴", 680, 705),
                    ("до 15.12.2026", 45, 765), ("до 15.01.2027", 680, 765),
                    ("Внести платіж", 45, 950), ("Сплатити повністю", 600, 950)
                ]
                for (text, x, y) in rows { (text as NSString).draw(at: CGPoint(x:x, y:y), withAttributes:attrs) }
                return
            }
            if stacked {
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black]
                let rows: [(String, CGFloat, CGFloat)] = [
                    ("ПУМБ", 45, 35), ("Назва: Тестовий телефон", 45, 115),
                    ("Загальна сума", 45, 250), ("Залишилось", 550, 250),
                    ("30 000,00 ₴", 45, 310), ("15 000,00 ₴", 550, 310),
                    ("Щомісячний платіж", 45, 500), ("2 500,00 ₴", 45, 560),
                    ("Дата наступного платежу", 45, 750), ("07.12.2026", 45, 810),
                    ("Вносьте платіж до 18:00", 45, 990)
                ]
                for (text, x, y) in rows { (text as NSString).draw(at: CGPoint(x:x, y:y), withAttributes:attrs) }
                return
            }
            let text = ["Тестовий телефон", "Розстрочка на 30 000 ₴", "6 із 12", "Платежів сплачено", "Подивитися графік платежів", "7 грудня", "2 500 ₴", "Наступний платіж"]
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black]
            for (i, line) in text.enumerated() { (line as NSString).draw(at: CGPoint(x: 45, y: 35 + i*125), withAttributes: attrs) }
            ("15 000 ₴" as NSString).draw(at: CGPoint(x: 570, y: 285), withAttributes: attrs)
            ("Залишилось" as NSString).draw(at: CGPoint(x: 570, y: 410), withAttributes: attrs)
        }
        guard let data = image.pngData() else { busy = false; errors = ["QA: не вдалося створити фото"]; return }
        Task { @MainActor in
            defer { busy = false }
            do { photos = [try await Task.detached(priority: .userInitiated) { try recognizeScan(data, installment: true) }.value] }
            catch { errors = [error.localizedDescription] }
        }
    }
    #endif
}
private struct ScanSourceSection: View {
    let photo: ScanPhoto
    @State private var show = false
    var body: some View {
        Section("Джерело") {
            LabeledContent("Банк", value: photo.bank ?? "Не визначено")
            if let warning = photo.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
            DisclosureGroup("Показати текст та скриншот", isExpanded: $show) {
                if let data = photo.image, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                Text(photo.lines.joined(separator: "\n")).font(.caption).textSelection(.enabled)
            }
        }
    }
}
private struct ScanTransactionEdit: Identifiable {
    var id: String
    var note: String
    var amount: String
    var currency: String
    var direction: String
    var date: Date
    var account = ""
    var category = "Без категорії"
    var rate = ""
    var chosen = false
    var dateChecked = false
    var duplicateOverride = false
    init(_ d: ScanLineDraft) {
        id = d.id; note = d.note; amount = d.money.map { amountText(abs($0.minor)) } ?? ""
        currency = d.money?.currency ?? ""
        direction = d.money?.signed == true ? (d.money!.minor < 0 ? Kind.expense.rawValue : Kind.unclassifiedCredit.rawValue) : ""
        date = d.date ?? Date()
    }
    var kind: Kind? { Kind(rawValue: direction) }
    var minor: Int64? { bankMinor(amount).flatMap { $0 > 0 ? $0 : nil } }
    var uah: Int64? {
        guard let m = minor else { return nil }
        if currency == "UAH" { return m }
        if currency == "USD", let r = fxRate(rate) { return fxMinor(m, rate: r) }
        return nil
    }
}
private struct ScanTransactionsReview: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    let photo: ScanPhoto
    @State private var rows: [ScanTransactionEdit]
    @State private var attach = false
    @State private var message = ""
    @State private var commonAccount = ""
    @State private var initialized = false
    private let kinds: [Kind] = [.expense,.income,.receipt,.refund,.creditDraw,.creditRepayment,.creditRepaymentIncoming,.movementIn,.movementOut,.unclassifiedCredit,.unclassifiedDebit]
    init(photo: ScanPhoto) {
        self.photo = photo
        let parsed = FinamiScanParser.transactions(photo.lines)
        _rows = State(initialValue: (parsed.isEmpty ? [ScanLineDraft(id: "manual-0", note: "", money: nil, date: nil)] : parsed).map(ScanTransactionEdit.init))
    }
    private func fingerprint(_ row: ScanTransactionEdit) -> String { photo.id + ":" + row.id }
    private func exact(_ row: ScanTransactionEdit) -> Bool { s.db.operations.contains { $0.scanFingerprint == fingerprint(row) } }
    private func similar(_ row: ScanTransactionEdit) -> Bool {
        guard let m = row.minor, let k = row.kind else { return false }
        let signed = k.incoming ? m : -m
        return s.db.operations.contains { o in
            let native = o.account == row.account ? o.signedNative : (o.kind == .transfer && o.destination == row.account ? o.destinationMinor ?? o.amount : 0)
            let account = o.account == row.account || (o.kind == .transfer && o.destination == row.account) ? row.account : o.account
            return FinamiScanParser.samePayment(account: row.account, signed: signed, date: row.date, otherAccount: account, otherSigned: native, otherDate: o.date)
        } || rows.contains { other in
            other.id != row.id && other.chosen && other.account == row.account && other.minor == m && other.kind?.incoming == k.incoming && Calendar.current.isDate(other.date, inSameDayAs: row.date)
        }
    }
    private func blockers(_ row: ScanTransactionEdit) -> [String] {
        var result: [String] = []
        if !row.dateChecked { result.append("підтвердити дату") }
        if row.kind == nil { result.append("вибрати тип операції") }
        if row.minor == nil { result.append("ввести суму") }
        if row.currency.isEmpty { result.append("вибрати валюту") }
        if row.currency == "USD" && fxRate(row.rate) == nil { result.append("ввести курс USD") }
        if !s.db.accounts.contains(where: { $0.id == row.account && $0.code == row.currency }) { result.append("вибрати рахунок відповідної валюти") }
        if exact(row) { result.append("рядок уже імпортовано") }
        else if similar(row) && !row.duplicateOverride { result.append("перевірити можливий дубль") }
        if result.isEmpty && (row.uah ?? 0) <= 0 { result.append("перевірити суму та валюту") }
        return result
    }
    private func valid(_ row: ScanTransactionEdit) -> Bool { row.chosen && blockers(row).isEmpty }
    private func categories(_ row: ScanTransactionEdit) -> [String] {
        if row.kind == .receipt { return s.db.availableReceiptCategories }
        let incoming = row.kind == .income
        let list = incoming ? s.db.incomeCategories : s.db.expenseCategories
        let hidden = incoming ? s.db.hiddenIncomeCategories : s.db.hiddenExpenseCategories
        return Array(Set(list.filter { !(hidden ?? []).contains($0) } + ["Без категорії", row.category])).sorted()
    }
    var body: some View {
        Form {
            ScanSourceSection(photo: photo)
            Section {
                Text("Вибери операції для імпорту та підтвердь їхні дату, суму, тип і рахунок. Перекази між власними рахунками краще записувати через звичайний редактор переказів.").font(.caption)
                Picker("Рахунок для всіх сум цієї валюти", selection: $commonAccount) { Text("Не застосовувати").tag(""); ForEach(s.db.accounts) { Text($0.name + " · " + $0.code).tag($0.id) } }
                Button("Застосувати рахунок до чернеток") {
                    guard let account = s.db.accounts.first(where: { $0.id == commonAccount }) else { return }
                    for i in rows.indices where rows[i].currency == account.code || rows[i].currency.isEmpty {
                        rows[i].currency = account.code; rows[i].account = account.id; rows[i].duplicateOverride = false
                    }
                }.disabled(commonAccount.isEmpty)
            }
            ForEach($rows) { $row in
                Section {
                    Toggle("Імпортувати цю операцію", isOn: $row.chosen)
                    TextField("Магазин / примітка", text: $row.note)
                    FinamiField("Сума", text: $row.amount, keyboard: .decimalPad)
                    Picker("Валюта", selection: $row.currency) { Text("Вибрати").tag(""); Text("UAH").tag("UAH"); Text("USD").tag("USD") }
                    if row.currency == "USD" { FinamiField("Курс гривні за USD", text: $row.rate, keyboard: .decimalPad) }
                    Picker("Тип", selection: $row.direction) { Text("Вибрати").tag(""); ForEach(kinds) { Text($0.title).tag($0.rawValue) } }
                    Picker("Рахунок", selection: $row.account) {
                        Text("Вибрати").tag("")
                        ForEach(s.db.accounts.filter { $0.code == row.currency }) { Text($0.name).tag($0.id) }
                    }
                    if row.kind?.isReportCategory == true {
                        Picker("Категорія", selection: $row.category) { ForEach(categories(row), id: \.self) { Text($0).tag($0) } }
                        Button("Запропонувати категорію") { if let k = row.kind { row.category = suggestedCategory(row.note, kind: k, database: s.db) } }
                    }
                    DatePicker("Дата і час", selection: $row.date)
                    Toggle("Дата перевірена", isOn: $row.dateChecked)
                    if row.chosen { let pending = blockers(row); if pending.isEmpty { Label("Готово до імпорту", systemImage: "checkmark.circle").foregroundStyle(.green) } else { Text("Потрібно: " + pending.joined(separator: "; ")).font(.caption).foregroundStyle(.orange) } }
                    if exact(row) { Label("Цей рядок уже імпортовано", systemImage: "checkmark.shield").foregroundStyle(.orange) }
                    else if similar(row) {
                        Label("Можливий дубль: така сума й напрям на рахунку в той самий день.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Toggle("Це окрема операція, не дубль", isOn: $row.duplicateOverride)
                    }
                } header: { Text("Операція \((rows.firstIndex { $0.id == row.id } ?? 0) + 1)") }
                .onChange(of: row.currency) { _ in if !s.db.accounts.contains(where: { $0.id == row.account && $0.code == row.currency }) { row.account = "" }; row.duplicateOverride = false }
                .onChange(of: row.account) { _ in row.duplicateOverride = false }
                .onChange(of: row.amount) { _ in row.duplicateOverride = false }
                .onChange(of: row.direction) { _ in row.duplicateOverride = false; if let kind = row.kind, kind.isReportCategory { row.category = suggestedCategory(row.note, kind: kind, database: s.db) } else { row.category = "Без категорії" } }
                .onChange(of: row.date) { _ in row.dateChecked = false; row.duplicateOverride = false }
            }
            Button { rows.append(ScanTransactionEdit(.init(id: UUID().uuidString, note: "", money: nil, date: nil))) } label: { Label("Додати нерозпізнаний рядок", systemImage: "plus.circle") }.disabled(rows.count >= 100)
            Section("Підтвердження") {
                if photo.image != nil { Toggle("Прикріпити скриншот до записів", isOn: $attach) }
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                let chosen = rows.filter(\.chosen)
                if chosen.isEmpty { Text("Увімкни «Імпортувати цю операцію» для потрібних записів.").font(.caption).foregroundStyle(.secondary) }
                else { Text("Готово: \(chosen.filter(valid).count) із \(chosen.count). Виправ позначені поля.").font(.caption).foregroundStyle(.secondary) }
                Button("Імпортувати обрані (\(chosen.count))", action: save).disabled(chosen.isEmpty || chosen.contains { !valid($0) })
                Text("Однакові рядки того самого скриншота повторно не зберігаються. Інший знімок або виписка можуть вимагати ручної звірки.").font(.caption)
            }
        }.navigationTitle("Перевірка операцій").onAppear {
            guard !initialized else { return }; initialized = true
            for i in rows.indices {
                if rows[i].rate.isEmpty { rows[i].rate = s.db.currencyPreferences?.usdRate ?? "" }
                if let kind = rows[i].kind, kind.isReportCategory { rows[i].category = suggestedCategory(rows[i].note, kind: kind, database: s.db) }
                if let bank = photo.bank {
                    let matches = s.db.accounts.filter { ($0.bankName ?? $0.name).localizedCaseInsensitiveContains(bank) && $0.code == rows[i].currency }
                    if matches.count == 1 { rows[i].account = matches[0].id }
                }
            }
        }
    }
    private func save() {
        let chosen = rows.filter(\.chosen)
        guard !chosen.isEmpty, chosen.allSatisfy(valid) else { return }
        let batch = UUID().uuidString
        let operations = chosen.compactMap { row -> Operation? in
            guard let k = row.kind, let n = row.uah, let native = row.minor else { return nil }
            var op = Operation(kind: k, amount: n, date: row.date, category: k.isReportCategory ? row.category : "Без категорії", note: bankRedact(row.note), account: row.account)
            op.sourceMinor = native; op.entryCurrency = row.currency; op.originalCurrency = row.currency; op.originalAmount = native
            op.exchangeRate = row.currency == "USD" ? row.rate : nil; op.captureSource = "Finami Scan"; op.importBatch = batch; op.scanFingerprint = fingerprint(row)
            if attach && photo.image != nil { op.scanImageID = photo.id }
            return op
        }
        guard operations.count == chosen.count else { return }
        if s.change({ d in
            d.operations.append(contentsOf: operations)
            if attach, let image = photo.image { var images = d.scanImages ?? [:]; images[photo.id] = image; d.scanImages = images }
        }) { dismiss() } else { message = "Запис не збережено. Перевір повідомлення про помилку." }
    }
}
private struct ScanInstallmentReview: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    let photo: ScanPhoto
    @State private var name: String
    @State private var total: String
    @State private var remaining: String
    @State private var monthly: String
    @State private var due: Date
    @State private var targetID = ""
    @State private var checked = false
    @State private var dateChecked = false
    @State private var attach = false
    @State private var remind = false
    @State private var lead = 1
    @State private var duplicateOverride = false
    @State private var busy = false
    private let foreign: Bool
    private let recognizedDue: Bool
    private let scanDraft: ScanInstallmentDraft
    @State private var keepSchedule = false
    private var scheduleRows: [FinamiScheduleRow] { finamiScheduleRows(photo.lines) }
    @State private var sourceAssignment = "total"
    @State private var learnLabels = false
    @State private var training: [FinamiOCRField: String] = [:]
    @State private var geometryTraining: [FinamiOCRField: ScanTextRegion] = [:]
    private let positionSuggestions: [FinamiOCRField: Int64]
    init(photo: ScanPhoto) {
        self.photo = photo; let rules = FinamiOCRProfiles.rules(photo.bank); let d = photo.mergedDraft ?? FinamiScanParser.installment(photo.lines.map { FinamiOCRProfiles.rewrite($0, rules: rules) }, regions: photo.ocrRegions)
        scanDraft = d
        positionSuggestions = FinamiOCRLayoutMemory.suggestions(bank: photo.bank, regions: photo.ocrRegions)
        _name = State(initialValue: d.name); _total = State(initialValue: d.total.map(amountText) ?? "")
        _remaining = State(initialValue: d.remaining.map(amountText) ?? ""); _monthly = State(initialValue: d.monthly.map(amountText) ?? "")
        _due = State(initialValue: d.due ?? Date()); foreign = d.foreignCurrency; recognizedDue = d.due != nil
    }
    private var existing: [Obligation] { s.db.obligations.filter { $0.kind == .installment || $0.kind == .owe } }
    private var exact: Bool { existing.contains { o in
        let incoming = Set((photo.sourceIDs ?? []) + [photo.id]); let prior = Set((o.scanSourceIDs ?? []) + [o.scanFingerprint].compactMap { $0 })
        return o.id != targetID && !incoming.isDisjoint(with: prior)
    } }
    private var similar: Bool { existing.contains { o in
        o.id != targetID && (o.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() || (o.target == bankMinor(total) && o.monthly == bankMinor(monthly)))
    } }
    private var reminderDate: Date? { Calendar.current.date(byAdding: .day, value: -lead, to: due).flatMap { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: $0) } }
    private var valid: Bool {
        guard !remind || ((reminderDate ?? .distantPast) > Date() && (bankMinor(remaining) ?? 0) > 0) else { return false }
        guard checked, dateChecked, !foreign, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let t = bankMinor(total), let r = bankMinor(remaining), let m = bankMinor(monthly), FinamiScanParser.validInstallment(total: t, remaining: r, monthly: m),
              targetID.isEmpty || existing.contains(where: { $0.id == targetID }) else { return false }
        return !exact && (!similar || duplicateOverride)
    }
    var body: some View {
        Form {
            ScanSourceSection(photo: photo)
            Section("Новий запис або оновлення") {
                Picker("Запис", selection: $targetID) { Text("Створити розстрочку").tag(""); ForEach(existing) { Text($0.name).tag($0.id) } }
                Text("Оновлення змінює дані договору, але не створює операцію списання. Історія рахунків не змінюється.").font(.caption)
                if exact { Label("Скриншот вже пов’язаний з іншим договором. Вибери його для оновлення.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                else if similar { Toggle("Це інший договір, не дубль", isOn: $duplicateOverride) }
            }
            pumbDetails
            Section("Дані договору · UAH") {
                let filled = [total, remaining, monthly].filter { !$0.isEmpty }.count
                Label("Заповнено сум: \(filled) із 3", systemImage: filled == 3 ? "checkmark.circle" : "exclamationmark.circle").font(.caption).foregroundStyle(filled == 3 ? Color.green : Color.orange)
                FinamiField("Назва", text: $name)
                FinamiField("Загальний кредит", text: $total, keyboard: .decimalPad)
                FinamiField("Поточний залишок", text: $remaining, keyboard: .decimalPad)
                FinamiField("Щомісячний платіж", text: $monthly, keyboard: .decimalPad)
                if let t = bankMinor(total), let r = bankMinor(remaining), t >= r, r >= 0 { LabeledContent("Вже погашено", value: s.visibleMoney(t-r)) }
                DatePicker(scanDraft.pumbParts ? "Наступний ненульовий платіж" : "Наступний платіж", selection: $due)
                Toggle("Дату перевірено", isOn: $dateChecked)
                if foreign { Text("Виявлено іноземну валюту. Модель розстрочок поки підтримує лише гривню; імпорт цього договору заблоковано.").foregroundStyle(.orange) }
                Toggle("Я перевірив усі дані", isOn: $checked)
                if photo.bank != nil && photo.sourceIDs == nil {
                    Toggle("Запам’ятати виправлені підписи та позиції", isOn: $learnLabels)
                    Text("Підписи й позиції запам’ятовуються лише після підтвердження. Позиції працюють на екрані з тією самою структурою. Суми не зберігаються у правилах.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Розпізнано зі скриншота") {
                Text("Заповнено \([name, total, remaining, monthly].filter { !$0.isEmpty }.count) із 4 текстових полів. \(recognizedDue ? "Дату знайдено." : "Дату потрібно вибрати вручну.")").font(.caption)
                if photo.lines.isEmpty { Text("Vision не повернув текст. Спробуй інший скриншот або введи дані вручну.").foregroundStyle(.orange) }
                else {
                    Picker("Куди підставити значення", selection: $sourceAssignment) {
                        Text("Загальний кредит").tag("total"); Text("Поточний залишок").tag("remaining"); Text("Щомісячний платіж").tag("monthly"); Text("Наступна дата").tag("due"); Text("Назва").tag("name")
                    }
                    ForEach(Array((sourceAssignment == "name" ? photo.lines : FinamiScanParser.installmentCandidates(photo.lines)).enumerated()), id: \.offset) { entry in
                        let line = entry.element
                        if sourceAssignment == "name" || (sourceAssignment == "due" ? FinamiScanParser.nextPaymentDate(line) != nil : FinamiScanParser.installmentCandidateAmount(line) != nil) {
                            Button { assign(line) } label: { Label(line, systemImage: "arrow.down.circle").font(.subheadline) }
                        }
                    }
                    Text("Обери поле, потім натисни потрібну суму. Якщо скриншот не містить підпису або решти даних, додай фото з деталями договору. Суми без чіткого підпису не підставляються навмання.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !positionSuggestions.isEmpty {
                Section("Вивчені позиції · перевір перед використанням") {
                    ForEach(FinamiOCRField.allCases, id: \.rawValue) { field in
                        if let value = positionSuggestions[field] {
                            Button { setAmount(value, field: field) } label: { LabeledContent(field.canonical, value: amountText(value)) }
                        }
                    }
                    Text("Підказки з попереднього підтвердженого макета. Не замінюють перевірку даних.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let field = FinamiOCRField(rawValue: sourceAssignment), !photo.ocrRegions.isEmpty, photo.sourceIDs == nil {
                let candidates = photo.ocrRegions.filter { FinamiOCRLayoutMemory.amount($0) != nil }
                if !candidates.isEmpty {
                    Section("Суми на зображенні · " + field.canonical) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { entry in
                            let region = entry.element
                            if let value = FinamiOCRLayoutMemory.amount(region) {
                                Button { setAmount(value, field: field); geometryTraining[field] = region; training.removeValue(forKey: field) } label: {
                                    LabeledContent(amountText(value), value: "x \(Int(region.bounds.midX * 100))% · y \(Int((1 - region.bounds.midY) * 100))%")
                                }
                            }
                        }
                        Text("Обери відповідну суму за позицією на скриншоті. За ввімкненого навчання запам’ятаємо місце лише для такого макета.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !scheduleRows.isEmpty {
                Section("Графік зі скриншота") {
                    ForEach(scheduleRows) { row in LabeledContent(row.date.formatted(date: .abbreviated, time: .omitted), value: s.visibleMoney(row.amount)) }
                    Toggle("Зберегти як довідковий графік", isOn: $keepSchedule)
                    Text("Перевір всі дати та суми. Це знайдені рядки, не підтвердження оплати і не автоматичне списання.").font(.caption)
                }
            }
            Section("Додатково") {
                if photo.image != nil { Toggle("Зберегти скриншот у договорі", isOn: $attach) }
                Toggle("Створити нагадування", isOn: $remind)
                if remind { Picker("Нагадати за", selection: $lead) { Text("У день платежу").tag(0); Text("1 день").tag(1); Text("3 дні").tag(3); Text("7 днів").tag(7) }; Text("Час: 09:00").font(.caption); if (reminderDate ?? .distantPast) <= Date() { Text("Час нагадування минув. Обери інший термін або вимкни нагадування.").foregroundStyle(.orange) } }
                if !targetID.isEmpty { Text("Якщо дата змінилася, одноразові пов’язані нагадування будуть перенесені або вимкнені, якщо вже минули. Повторювані перевір у меню нагадувань.").font(.caption) }
                if !valid {
                    if !checked || !dateChecked { Text("Підтвердь дату та перевірку всіх даних.").font(.caption).foregroundStyle(.orange) }
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("Вкажи назву договору.").font(.caption).foregroundStyle(.orange) }
                    if !FinamiScanParser.validInstallment(total: bankMinor(total) ?? -1, remaining: bankMinor(remaining) ?? -1, monthly: bankMinor(monthly) ?? -1) { Text("Перевір загальний кредит, залишок і щомісячний платіж.").font(.caption).foregroundStyle(.orange) }
                    if similar && !duplicateOverride { Text("Перевір, чи це новий договір, або обери існуючий.").font(.caption).foregroundStyle(.orange) }
                }
                Button(targetID.isEmpty ? "Додати розстрочку" : "Оновити договір") { save() }.disabled(!valid || busy)
            }
        }.navigationTitle("Перевірка розстрочки").onChange(of: targetID) { id in
            duplicateOverride = false; checked = false; dateChecked = false
            if let old = existing.first(where: { $0.id == id }) {
                if name.isEmpty { name = old.name }; if total.isEmpty { total = amountText(old.target) }; if remaining.isEmpty { remaining = amountText(old.remaining) }; if monthly.isEmpty { monthly = amountText(old.monthly) }
            }
        }.onChange(of: due) { _ in dateChecked = false }.onChange(of: name) { _ in checked = false; duplicateOverride = false }.onChange(of: total) { _ in checked = false; duplicateOverride = false }.onChange(of: remaining) { _ in checked = false }.onChange(of: monthly) { _ in checked = false; duplicateOverride = false }
    }
    @ViewBuilder private var pumbDetails: some View {
            if scanDraft.pumbParts {
                Section("ПУМБ · Сплачуйте частинами") {
                    if let paid = scanDraft.paidCount, let count = scanDraft.paymentCount { LabeledContent("Внесено платежів", value: "\(paid) з \(count)") }
                    if let opened = scanDraft.opened { LabeledContent("Оформлено", value: opened.formatted(date: .abbreviated, time: .omitted)) }
                    if let next = scanDraft.nextAmount { LabeledContent("Найближчий внесок банку", value: s.visibleMoney(next)) }
                    if let next = scanDraft.bankNextDue { LabeledContent("Дата найближчого внеску банку", value: next.formatted(date: .abbreviated, time: .omitted)) }
                    if let end = scanDraft.finalDue { LabeledContent("Кінцевий термін", value: end.formatted(date: .abbreviated, time: .omitted)) }
                    if scanDraft.monthlyEstimated { Text("Щомісячний внесок розраховано з суми та кількості платежів; перевір за договором.").font(.caption).foregroundStyle(.orange) }
                    if scanDraft.nextAmount == 0 && (scanDraft.remaining ?? 0) > 0 { Text("Найближчий внесок банку нульовий. Вкажи дату першого ненульового платежу, а не дату нульового внеску.").font(.caption).foregroundStyle(.orange) }
                }
            }
    }
    private func assign(_ line: String) {
        checked = false; duplicateOverride = false
        if sourceAssignment == "name" { name = bankRedact(line); return }
        if sourceAssignment == "due" { if let d = FinamiScanParser.nextPaymentDate(line) { due = d; dateChecked = false }; return }
        guard let amount = FinamiScanParser.installmentCandidateAmount(line) else { return }
        if let field = FinamiOCRField(rawValue: sourceAssignment) { training[field] = line; geometryTraining.removeValue(forKey: field) }
        switch sourceAssignment { case "total": total = amountText(amount); case "remaining": remaining = amountText(amount); case "monthly": monthly = amountText(amount); default: break }
    }
    private func setAmount(_ value: Int64, field: FinamiOCRField) {
        checked = false; duplicateOverride = false
        training.removeValue(forKey: field); geometryTraining.removeValue(forKey: field)
        switch field { case .total: total = amountText(value); case .remaining: remaining = amountText(value); case .monthly: monthly = amountText(value) }
    }
    private func save() {
        guard valid, let t = bankMinor(total), let r = bankMinor(remaining), let m = bankMinor(monthly) else { return }
        busy = true
        let previous = existing.first { $0.id == targetID }
        var o = previous ?? Obligation(kind: .installment)
        o.name = name.trimmingCharacters(in: .whitespacesAndNewlines); o.target = t; o.paid = t-r; o.monthly = m; o.due = due; o.scanFingerprint = photo.id
        if scanDraft.pumbParts, let next = scanDraft.nextAmount, next > 0, due == scanDraft.bankNextDue, next < min(m, r), m - next <= o.paid { o.currentDuePaid = m - next }
        else if scanDraft.pumbParts { o.currentDuePaid = nil }
        o.scanSourceIDs = Array(Set((previous?.scanSourceIDs ?? []) + [previous?.scanFingerprint].compactMap { $0 } + (photo.sourceIDs ?? []) + [photo.id])).sorted()
        if keepSchedule { o.importedSchedule = scheduleRows }
        if attach && photo.image != nil { o.scanImageID = photo.id }
        let oldReminders = (s.db.reminders ?? []).filter { $0.linkedID == o.id }
        var changed: [PersonalReminder] = []
        if let previous = previous, previous.due != due || r == 0 {
            changed = oldReminders.filter { $0.recurrence == .once || r == 0 }.map { old in
                var item = old; item.date = due.addingTimeInterval(old.date.timeIntervalSince(previous.due)); if r == 0 || item.date <= Date() { item.enabled = false }; return item
            }
        }
        if remind && r > 0, let day = Calendar.current.date(byAdding: .day, value: -lead, to: due), let when = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day), when > Date(), !oldReminders.contains(where: { $0.date == when }), !changed.contains(where: { $0.date == when }) {
            changed.append(PersonalReminder(title: o.name, date: when, linkedID: o.id))
        }
        if s.change({ d in
            if let i = d.obligations.firstIndex(where: { $0.id == o.id }) { d.obligations[i] = o } else { d.obligations.append(o) }
            if attach, let image = photo.image { var images = d.scanImages ?? [:]; images[photo.id] = image; d.scanImages = images }
            var reminders = d.reminders ?? []; let ids = Set(changed.map(\.id)); reminders.removeAll { ids.contains($0.id) }; reminders.append(contentsOf: changed); d.reminders = reminders
        }) {
            if learnLabels, photo.sourceIDs == nil, let bank = photo.bank {
                let finalValues: [FinamiOCRField: Int64] = [.total: t, .remaining: r, .monthly: m]
                for (field, raw) in training where FinamiScanParser.installmentCandidateAmount(raw) == finalValues[field] {
                    FinamiOCRProfiles.learn(bank: bank, raw: raw, field: field)
                }
                for (field, region) in geometryTraining where FinamiOCRLayoutMemory.amount(region) == finalValues[field] {
                    FinamiOCRLayoutMemory.learn(bank: bank, regions: photo.ocrRegions, chosen: region, field: field)
                }
            }
            let reminders = changed
            Task { @MainActor in
                for item in reminders {
                    ReminderScheduler.cancel(item)
                    do { try await ReminderScheduler.schedule(item) } catch {
                        s.change { d in if let i = d.reminders?.firstIndex(where: { $0.id == item.id }) { d.reminders?[i].enabled = false } }
                        s.error = "Договір збережено, нагадування не встановлено: " + error.localizedDescription
                    }
                }
                busy = false; dismiss()
            }
        } else { busy = false }
    }
}
struct FinamiScanAttachment: View {
    @EnvironmentObject private var s: Store
    let imageID: String
    @State private var reveal = false
    var body: some View {
        ScrollView {
            if !reveal { Button("Показати конфіденційний скриншот") { reveal = true }.padding() }
            else if let data = s.db.scanImages?[imageID], let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().padding() }
            else { Text("Вкладення недоступне").padding() }
        }.navigationTitle("Скриншот").onDisappear { reveal = false }
    }
}

private struct ScanBalanceReview: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    let photo: ScanPhoto
    @State private var accountID = ""
    @State private var mode = "net"
    @State private var net = ""
    @State private var own = ""
    @State private var used = ""
    @State private var limit = ""
    @State private var changeLimit = false
    @State private var confirmed = false
    private var account: Account? { s.db.accounts.first { $0.id == accountID } }
    private var proposed: Int64? {
        if mode == "net" || account?.isCredit != true { return bankMinor(net) }
        guard let x = bankMinor(own), let y = bankMinor(used) else { return nil }
        return CardPosition.netFrom(own: x, used: y)
    }
    private var opening: Int64? {
        guard let a = account, let value = proposed else { return nil }
        let next = value - (s.nativeBalance(a) - a.opening)
        return abs(next) <= 1_000_000_000_000 ? next : nil
    }
    private var valid: Bool { confirmed && opening != nil && (!changeLimit || (account?.isCredit == true && (bankMinor(limit) ?? -1) >= 0)) }
    var body: some View {
        Form {
            ScanSourceSection(photo: photo)
            Section("Рахунок для звірки") {
                Picker("Рахунок", selection: $accountID) { Text("Вибрати").tag(""); ForEach(s.db.accounts) { Text($0.name + " · " + $0.code).tag($0.id) } }
                if let a = account { LabeledContent("Поточний чистий баланс Finami", value: s.visibleMoney(s.nativeBalance(a), a.code)) }
            }
            if let a = account {
                Section("Фактичні дані банку · \(a.code)") {
                    if a.isCredit { Picker("Тип суми", selection: $mode) { Text("Чистий баланс").tag("net"); Text("Власні кошти / борг").tag("parts") } }
                    if mode == "parts" && a.isCredit {
                        FinamiField("Власні кошти", text: $own, keyboard: .decimalPad)
                        FinamiField("Використано кредиту", text: $used, keyboard: .decimalPad)
                        Text("На одному чистому балансі власні кошти або борг мають бути нульовими.").font(.caption)
                    } else { FinamiField("Чистий баланс (+ кошти / − борг)", text: $net, keyboard: .numbersAndPunctuation) }
                    if a.isCredit { Toggle("Оновити кредитний ліміт", isOn: $changeLimit); if changeLimit { FinamiField("Кредитний ліміт", text: $limit, keyboard: .decimalPad) } }
                    if let value = proposed { LabeledContent("Новий чистий баланс", value: s.visibleMoney(value, a.code)); LabeledContent("Різниця", value: s.visibleMoney(value-s.nativeBalance(a), a.code)) }
                    Text("Невикористаний кредит і загальна доступна сума не є власними коштами. Значення «доступно» не підставляється автоматично.").font(.caption)
                }
                Section {
                    Toggle("Перевірив валюту та актуальність скриншота", isOn: $confirmed)
                    Button("Скоригувати залишок", action: save).disabled(!valid)
                    Text("Це коригування початкового залишку з урахуванням записаної історії. Воно не створює дохід або витрату. Старі скриншоти можуть спотворити актуальний баланс.").font(.caption)
                }
            }
        }.navigationTitle("Звірка зі скриншота")
            .onChange(of: accountID) { _ in
                confirmed = false; changeLimit = false; mode = "net"; net = ""; own = ""; used = ""; limit = ""
                guard let a = account else { return }
                let draft = FinamiScanParser.balance(photo.lines)
                func field(_ m: ScanMoney?) -> String { guard let m = m, m.currency == nil || m.currency == a.code else { return "" }; return amountText(m.minor) }
                net = field(draft.net); own = field(draft.own); used = field(draft.used); limit = field(draft.limit)
                if a.isCredit && net.isEmpty && (!own.isEmpty || !used.isEmpty) { mode = "parts" }
                if !a.isCredit && net.isEmpty { net = own }
            }.onChange(of: mode) { _ in confirmed = false }.onChange(of: net) { _ in confirmed = false }.onChange(of: own) { _ in confirmed = false }.onChange(of: used) { _ in confirmed = false }.onChange(of: limit) { _ in confirmed = false }.onChange(of: changeLimit) { _ in confirmed = false }
    }
    private func save() {
        guard valid, let next = opening, let a = account else { return }
        if s.change({ d in
            guard let i = d.accounts.firstIndex(where: { $0.id == a.id }) else { return }
            d.accounts[i].opening = next
            if changeLimit { d.accounts[i].creditLimit = bankMinor(limit) }
        }) { dismiss() }
    }
}
