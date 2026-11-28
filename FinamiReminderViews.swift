import SwiftUI
import UserNotifications

@MainActor enum ReminderScheduler {
    static func cancel(_ r: PersonalReminder) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [r.requestID]); UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [r.requestID]) }
    static func schedule(_ r: PersonalReminder) async throws {
        let center = UNUserNotificationCenter.current()
        if !r.enabled { cancel(r); return }
        guard try await center.requestAuthorization(options: [.alert,.sound,.badge]) else { throw ReminderFailure.denied }
        guard r.recurrence != .once || r.date > Date() else { throw ReminderFailure.past }
        let cal = Calendar.current
        let fields: Set<Calendar.Component>
        switch r.recurrence { case .once: fields = [.year,.month,.day,.hour,.minute]; case .daily: fields = [.hour,.minute]; case .weekly: fields = [.weekday,.hour,.minute]; case .monthly: fields = [.day,.hour,.minute]; case .yearly: fields = [.month,.day,.hour,.minute] }
        // A calendar recurrence starts at its next matching occurrence, not necessarily at the selected future date.
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents(fields, from: r.date), repeats: r.recurrence != .once)
        guard trigger.nextTriggerDate() != nil else { throw ReminderFailure.past }
        let c = UNMutableNotificationContent(); c.title = "Finami · Нагадування"; c.body = r.hideDetails ? "Відкрий застосунок, щоб переглянути платіж." : r.title; c.sound = .default
        try await center.add(UNNotificationRequest(identifier: r.requestID, content: c, trigger: trigger))
    }
    enum ReminderFailure: LocalizedError { case denied,past; var errorDescription: String? { self == .denied ? "Дозволь сповіщення Finami в налаштуваннях iPhone." : "Вибери майбутню дату й час." } }
}
struct ReminderList: View {
    @EnvironmentObject var s: Store
    var body: some View {
        List {
            ForEach((s.db.reminders ?? []).sorted{$0.date < $1.date}) { r in
                NavigationLink { ReminderEditor(original: r) } label: { VStack(alignment: .leading) { IzanamiLabel(title: r.title, icon: r.enabled ? "bell.fill" : "bell.slash", color: .red); Text(r.date.formatted(date:.abbreviated,time:.shortened) + " · " + r.recurrence.rawValue).font(.caption).foregroundStyle(.secondary) } }
            }.onDelete { offsets in let sorted = (s.db.reminders ?? []).sorted{$0.date < $1.date}; let selected = offsets.map{sorted[$0]}; if s.change({d in d.reminders = (d.reminders ?? []).filter{r in !selected.contains{$0.id == r.id}} }) { selected.forEach{ReminderScheduler.cancel($0)} } }
            NavigationLink { ReminderEditor(original: PersonalReminder(date: Date().addingTimeInterval(3600))) } label: { Label("Нове нагадування", systemImage: "plus.circle.fill") }
            Text("Нагадування локальні. Після відновлення бази на іншому пристрої відкрий та збережи їх повторно.").font(.caption)
        }.navigationTitle("Нагадування")
    }
}
struct ReminderEditor: View {
    @EnvironmentObject var s: Store; @Environment(\.dismiss) var dismiss
    @State var r: PersonalReminder; @State private var busy = false
    init(original: PersonalReminder) { _r = State(initialValue: original) }
    var body: some View {
        Form {
            TextField("Назва", text: $r.title)
            Toggle("Увімкнено", isOn: $r.enabled)
            DatePicker("Дата та час", selection: $r.date, displayedComponents: [.date,.hourAndMinute])
            Picker("Повторення", selection: $r.recurrence) { ForEach(ReminderRepeat.allCases, id: \.self){Text($0.rawValue).tag($0)} }
            if r.recurrence != .once { Text("Повторення починається з найближчого відповідного дня й часу; для конкретної майбутньої дати обери «Один раз».").font(.caption) }
            Toggle("Приховувати деталі", isOn: $r.hideDetails)
            Button("Зберегти нагадування") {
                busy = true
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        try await ReminderScheduler.schedule(r)
                        if s.change({d in var all = d.reminders ?? []; all.removeAll{$0.id == r.id}; all.append(r); d.reminders = all}) { dismiss() } else { ReminderScheduler.cancel(r) }
                    } catch { s.error = error.localizedDescription }
                }
            }.disabled(busy || r.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }.navigationTitle("Нагадування")
    }
}
