import SwiftUI

struct FinamiOCRRulesView: View {
    @AppStorage(FinamiOCRProfiles.storageKey) private var data: Data = Data()
    private var rules: [String: [String: FinamiOCRField]] {
        (try? JSONDecoder().decode([String: [String: FinamiOCRField]].self, from: data)) ?? [:]
    }
    @AppStorage(FinamiOCRLayoutMemory.storageKey) private var layouts: Data = Data()
    @State private var reset = false
    var body: some View {
        List {
            ForEach(FinamiOCRProfiles.banks, id: \.self) { bank in
                Section(bank) {
                    let entries = rules[bank] ?? [:]
                    if entries.isEmpty { Text("Немає вивчених правил").font(.caption).foregroundStyle(.secondary) }
                    ForEach(entries.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading) { Text(key); Text(entries[key]?.canonical ?? "").font(.caption).foregroundStyle(.secondary) }
                            .swipeActions { Button(role: .destructive) { remove(bank, key) } label: { Label("Видалити", systemImage: "trash") } }
                    }
                }
            }
            Section("Позиції полів") {
                Text("Вивчені макети: \(FinamiOCRLayoutMemory.read().count)")
                Text("Позиції пропонуються лише при збігу підписів і структури екрана.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("Очистити вивчені правила", role: .destructive) { reset = true }.disabled(rules.isEmpty && layouts.isEmpty) }
        }.navigationTitle("Навчання OCR").confirmationDialog("Очистити лише вивчені підписи?", isPresented: $reset) {
            Button("Очистити", role: .destructive) { data = Data(); layouts = Data() }
            Button("Скасувати", role: .cancel) {}
        } message: { Text("Договори та фінансові дані залишаться без змін.") }
    }
    private func remove(_ bank: String, _ key: String) {
        var updated = rules; updated[bank]?.removeValue(forKey: key)
        if updated[bank]?.isEmpty == true { updated.removeValue(forKey: bank) }
        if let encoded = try? JSONEncoder().encode(updated) { data = encoded }
    }
}
