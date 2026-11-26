import SwiftUI
import WidgetKit

struct FinamiWidgetEntry: TimelineEntry {
    let date: Date
    let summary: FinamiWidgetSnapshot?
}
struct FinamiWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinamiWidgetEntry { .init(date: Date(), summary: nil) }
    func getSnapshot(in context: Context, completion: @escaping (FinamiWidgetEntry) -> Void) { completion(.init(date: Date(), summary: context.isPreview ? nil : FinamiWidgetSnapshot.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FinamiWidgetEntry>) -> Void) {
        let now = Date(), summary = FinamiWidgetSnapshot.read()
        var entries = [FinamiWidgetEntry(date: now, summary: summary)]
        if let summary { entries.append(.init(date: summary.updated.addingTimeInterval(86400), summary: nil)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}
private struct FinamiWidgetView: View {
    let entry: FinamiWidgetEntry
    let kind: String
    private func money(_ value: Int64, _ currency: String) -> String { (Double(value)/100).formatted(.currency(code: currency).locale(Locale(identifier: "uk_UA"))) }
    private var title: String { kind == "balance" ? "Власні кошти" : kind == "payments" ? "Найближчий платіж" : "Швидка витрата" }
    private var icon: String { kind == "balance" ? "wallet.pass" : kind == "payments" ? "calendar" : "plus.circle.fill" }
    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) { content.containerBackground(Color(uiColor: .secondarySystemBackground), for: .widget) }
        else { content.padding().background(Color(uiColor: .secondarySystemBackground)) }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Image(systemName: icon).foregroundStyle(.teal); Spacer(); Text("Finami").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
            Spacer(minLength: 2)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if kind == "balance", let snapshot = entry.summary {
                Text(money(snapshot.ownUAH,"UAH")).font(.title2.bold()).minimumScaleFactor(0.5).lineLimit(1).privacySensitive()
                Text("Видимі включені рахунки · UAH").font(.caption2).foregroundStyle(.secondary)
            } else if kind == "payments", let snapshot = entry.summary {
                if let amount = snapshot.dueAmount, let currency = snapshot.dueCurrency, let date = snapshot.dueDate {
                    Text(money(amount,currency)).font(.title2.bold()).minimumScaleFactor(0.5).lineLimit(1).privacySensitive()
                    Text(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier:"uk_UA")))).font(.caption).privacySensitive()
                } else { Text("Немає платежів").font(.headline) }
            } else { Text(kind == "quick" ? "Додати операцію" : "Відкрити Finami").font(.headline); Text(kind == "quick" ? "Натисни для запису" : "Суми приховано").font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
         .widgetURL(URL(string: "finami-widget://" + kind))
    }
}
struct FinamiBalanceWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "FinamiBalance", provider: FinamiWidgetProvider()) { FinamiWidgetView(entry:$0,kind:"balance") }.configurationDisplayName("Власні кошти").description("Власні кошти в гривні або швидкий доступ до рахунків.").supportedFamilies([.systemSmall,.systemMedium]) }
}
struct FinamiPaymentsWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "FinamiPayments", provider: FinamiWidgetProvider()) { FinamiWidgetView(entry:$0,kind:"payments") }.configurationDisplayName("Найближчий платіж").description("Запланована оплата або перехід у календар.").supportedFamilies([.systemSmall,.systemMedium]) }
}
struct FinamiQuickWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "FinamiQuick", provider: FinamiWidgetProvider()) { FinamiWidgetView(entry:$0,kind:"quick") }.configurationDisplayName("Швидка витрата").description("Відкриває форму нової операції.").supportedFamilies([.systemSmall]) }
}
@main struct FinamiWidgetBundle: WidgetBundle {
    var body: some Widget { FinamiBalanceWidget(); FinamiPaymentsWidget(); FinamiQuickWidget() }
}
