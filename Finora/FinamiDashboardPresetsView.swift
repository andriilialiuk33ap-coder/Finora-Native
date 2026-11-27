import SwiftUI

struct FinamiDashboardPresetsView: View {
    @EnvironmentObject private var s: Store
    @State private var name = ""
    @State private var pending: String?
    @State private var preview: FinamiDashboardLayoutPreset?
    private var presets: [String: Data] { s.db.preferences?.dashboardLayoutPresets ?? [:] }
    var body: some View {
        List {
            Section("Зберегти поточну конфігурацію") {
                TextField("Назва", text: $name)
                Button("Зберегти") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Зберігаються порядок, видимість, розміри, оформлення і згортання блоків. Приховані суми, фільтри категорій та фінансові дані не змінюються.").font(.caption)
            }
            Section("Мої конфігурації") {
                if presets.isEmpty { Text("Ще немає конфігурацій").foregroundStyle(.secondary) }
                ForEach(presets.keys.sorted(), id: \.self) { key in
                    Button {
                        guard let data = presets[key], let decoded = try? JSONDecoder().decode(FinamiDashboardLayoutPreset.self, from: data) else { s.error = "Конфігурація не читається."; return }
                        pending = key; preview = decoded
                    } label: { Label(key, systemImage: "square.grid.2x2") }
                    .swipeActions(allowsFullSwipe: false) { Button("Видалити", role: .destructive) { s.changeAppearance { $0.dashboardLayoutPresets?.removeValue(forKey: key) } } }
                }
            }
            if let preview, let pending {
                Section("Перегляд: " + pending) {
                    ForEach(preview.applying(to: s.db.dashboard, collapsed: s.db.preferences?.collapsedDashboard).items.filter(\.enabled)) { item in
                        HStack { Label(item.kind.title, systemImage: item.kind.icon); Spacer(); Text(item.size.rawValue).font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("Застосувати конфігурацію") {
                        let result = preview.applying(to: s.db.dashboard, collapsed: s.db.preferences?.collapsedDashboard)
                        if s.change({ d in d.dashboard = result.items; var p = d.preferences ?? .init(); p.collapsedDashboard = result.collapsed; d.preferences = p }) { self.preview = nil; self.pending = nil }
                    }
                    Button("Скасувати") { self.preview = nil; self.pending = nil }
                }
            }
        }.navigationTitle("Конфігурації головної")
    }
    private func save() {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard presets[key] == nil else { s.error = "Така назва вже є. Обери іншу або видали стару конфігурацію."; return }
        let layout = FinamiDashboardLayoutPreset.capture(s.db.dashboard, collapsed: s.db.preferences?.collapsedDashboard)
        guard let data = try? JSONEncoder().encode(layout) else { s.error = "Не вдалося підготувати конфігурацію."; return }
        if s.changeAppearance({ p in var all = p.dashboardLayoutPresets ?? [:]; all[key] = data; p.dashboardLayoutPresets = all }) { name = "" }
    }
}
