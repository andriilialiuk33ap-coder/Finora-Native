import Foundation

struct FinamiWidgetSnapshot: Codable, Equatable {
    static let group = "group.ua.finora.personal"
    static let filename = "finami-widget-summary.json"
    let ownUAH: Int64
    let dueAmount: Int64?
    let dueCurrency: String?
    let dueDate: Date?
    let updated: Date
    var schemaVersion: Int? = 1
    static func url() -> URL? {
        #if os(iOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent(filename)
        #else
        return nil
        #endif
    }
    static func read(now: Date = Date()) -> Self? {
        guard let url = url(), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_384, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data,now:now)
    }
    static func decode(_ data: Data, now: Date) -> Self? {
        guard data.count <= 16_384, let snapshot = try? JSONDecoder().decode(Self.self, from: data), now.timeIntervalSince(snapshot.updated) >= -60, now.timeIntervalSince(snapshot.updated) < 86400, snapshot.ownUAH >= 0, (snapshot.schemaVersion ?? 1) == 1 else { return nil }
        if let amount = snapshot.dueAmount {
            guard amount > 0, let code = snapshot.dueCurrency, ["UAH","USD"].contains(code), snapshot.dueDate != nil else { return nil }
        } else if snapshot.dueDate != nil || snapshot.dueCurrency != nil { return nil }
        return snapshot
    }
}

/// Hide the complete next-payment payload when the user hides that subscription.
enum FinamiWidgetPrivacyPolicy {
    static func showsPayment(subscription: Bool, id: String, hiddenSubscriptions: [String]) -> Bool {
        !subscription || !hiddenSubscriptions.contains(id)
    }
}
