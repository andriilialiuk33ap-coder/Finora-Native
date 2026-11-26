import Foundation

// Appearance writes never modify the ledger file. A generation prevents a stale
// settings file from overriding a restored or newly committed database.
struct FinamiAppearanceSidecar<Preferences: Codable>: Codable {
    let revision: String
    let preferences: Preferences
    static func resolve(base: Preferences?, revision: String?, data: Data?) throws -> Preferences? {
        guard let revision, let data else { return base }
        let sidecar = try JSONDecoder().decode(Self.self, from: data)
        return sidecar.revision == revision ? sidecar.preferences : base
    }
}
