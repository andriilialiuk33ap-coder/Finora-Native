import Foundation

// Layout snapshots deliberately exclude personal filters and privacy settings.
struct FinamiDashboardLayoutPreset: Codable {
    struct Block: Codable {
        var id: String
        var enabled: Bool
        var size: DashboardSize
        var template: String?
        var accentName: String?
    }
    var blocks: [Block]
    var collapsed: [String]
    static func capture(_ items: [DashboardItem]?, collapsed: [String]?) -> Self {
        let current = DashboardItem.merged(items)
        return .init(blocks: current.map { .init(id: $0.id, enabled: $0.enabled, size: $0.size, template: $0.template, accentName: $0.accentName) }, collapsed: collapsed ?? [])
    }
    func applying(to items: [DashboardItem]?, collapsed currentCollapsed: [String]?) -> (items: [DashboardItem], collapsed: [String]) {
        let current = DashboardItem.merged(items)
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [DashboardItem] = []
        for block in blocks {
            guard var item = byID[block.id], seen.insert(block.id).inserted else { continue }
            item.enabled = block.enabled; item.size = block.size; item.template = block.template; item.accentName = block.accentName
            result.append(item)
        }
        result += current.filter { !seen.contains($0.id) }
        let savedCollapsed = Set(collapsed)
        let oldCollapsed = Set(currentCollapsed ?? [])
        return (result, result.filter { seen.contains($0.id) ? savedCollapsed.contains($0.id) : oldCollapsed.contains($0.id) }.map(\.id))
    }
}
