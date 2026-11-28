import Foundation

// Local identifiers; display only, never used to route money or classify a transfer.
enum FinamiBrand: String, CaseIterable, Identifiable {
    case pumb, mono, privat, abank, spotify, netflix, silpo, atb, youtube, icloud
    var id: String { rawValue }
    var name: String {
        switch self {
        case .pumb: return "ПУМБ"
        case .mono: return "Monobank"
        case .privat: return "ПриватБанк"
        case .abank: return "А-Банк"
        case .spotify: return "Spotify"
        case .netflix: return "Netflix"
        case .silpo: return "Сільпо"
        case .atb: return "АТБ"
        case .youtube: return "YouTube"
        case .icloud: return "iCloud"
        }
    }
    var isBank: Bool { [.pumb, .mono, .privat, .abank].contains(self) }
    private var aliases: [String] {
        switch self {
        case .pumb: return ["пумб", "pumb", "fuib"]
        case .mono: return ["monobank", "монобанк", "mono", "моно"]
        case .privat: return ["приватбанк", "приват банк", "privatbank", "privat bank", "приват24", "privat24", "приват"]
        case .abank: return ["а банк", "а банку", "абанк", "a bank", "abank", "àbank"]
        case .spotify: return ["spotify", "спотіфай"]
        case .netflix: return ["netflix", "нетфлікс"]
        case .silpo: return ["silpo", "сільпо", "silpo food"]
        case .atb: return ["atb", "атб"]
        case .youtube: return ["youtube", "ютуб"]
        case .icloud: return ["icloud", "айклауд"]
        }
    }
    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func match(_ value: String, banksOnly: Bool = false, merchantsOnly: Bool = false) -> FinamiBrand? {
        let text = " " + normalized(value) + " "
        let matches = allCases.filter { brand in
            (!banksOnly || brand.isBank) && (!merchantsOnly || !brand.isBank) && brand.aliases.contains { text.contains(" " + normalized($0) + " ") }
        }
        return matches.count == 1 ? matches.first : nil
    }
}
