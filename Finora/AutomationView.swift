import SwiftUI
import UIKit
import AppIntents
import UserNotifications

struct CapturePreferences: Codable {
    var walletAuto = false
    var messageAuto = false
    var notifySaved: Bool? = nil
    var walletBindings: [String:String]? = nil
}

@MainActor extension Store {
    func routedCapture(_ e: CapturedPayment) -> CapturedPayment {
        var event = finamiWalletAccount(e, bindings: db.capturePreferences?.walletBindings ?? [:])
        let accounts = db.accounts.map { a in FinamiCaptureAccount(id: a.id, currency: a.code, suffix: a.lastFour, bank: finamiBankHint((a.bankName ?? "") + " " + a.name)) }
        event.account = finamiCaptureRoute(event, accounts: accounts) ?? ""
        return event
    }
    func captureRepeat(_ e: CapturedPayment) -> Bool {
        captureRepeatedMessage(e,handled:db.captureMessageFingerprints ?? [])
    }
    func captureMatch(_ e: CapturedPayment) -> Bool {
        captureMatch(e, in: db)
    }
    private func captureMatch(_ e: CapturedPayment, in database: Database) -> Bool {
        if captureRepeatedMessage(e, handled: database.captureMessageFingerprints ?? []) { return true }
        let paid = Set((database.paidRecords ?? []).compactMap(\.operationID))
        return database.operations.contains { o in
            finamiCaptureAccountConflict(e, otherAccount:o.account, otherCurrency:o.entryCurrency ?? "UAH", otherAmount:o.sourceMinor ?? o.amount, otherIncoming:o.kind.incoming, otherDate:o.date, otherSource:o.captureSource, otherMerchant:o.note) || capturePossibleDuplicate(e,otherAccount:o.account,otherCurrency:o.entryCurrency ?? "UAH",otherAmount:o.sourceMinor ?? o.amount,otherIncoming:o.kind.incoming,otherDate:o.date,otherSource:o.captureSource,isBank:o.sourceBank != nil || o.bankKey != nil || paid.contains(o.id))
        }
    }
    func capturedOperation(_ e: CapturedPayment, kind: Kind) -> Operation? {
        guard let a=db.accounts.first(where:{$0.id==e.account && $0.code==e.currency}), kind != .transfer, kind.incoming==e.incoming else {return nil}
        let rate = a.code == "USD" ? currentRate : nil
        let total: Int64
        if a.code == "USD" {guard let rate, let value=fxMinor(e.minor,rate:rate),value>0 else{return nil};total=value}
        else {total=e.minor}
        let category = kind.isReportCategory ? suggestedCategory(e.merchant,kind:kind,database:db) : "Без категорії"
        var o=Operation(id:e.id,kind:kind,amount:total,date:e.date,category:category,note:e.merchant.isEmpty ? e.source:e.merchant,account:a.id)
        o.sourceMinor=e.minor; o.entryCurrency=a.code; o.originalAmount=e.minor; o.originalCurrency=a.code; o.exchangeRate=rate.map(fxString); o.captureSource=e.source
        return o
    }
    func refreshCaptures(auto: Bool = true, inbox: URL? = nil) {
        guard storageHealthy, !loading else { return }
        do {
            let dir = try (inbox ?? CaptureInbox.folder())
            let scan = try CaptureInbox.scan(in: dir)
            var warnings: [String] = []
            if scan.unreadable > 0 { warnings.append("Не вдалося прочитати файли черги: \(scan.unreadable). Збережено для повторної спроби.") }
            let handled = Set(db.captureHandled ?? [])
            let existing = Set(db.operations.map(\.id))
            var staged = db
            var accepted: [CapturedPayment] = []
            var pending: [CapturedPayment] = []
            func remove(_ e: CapturedPayment) {
                do { try CaptureInbox.remove(e, in: dir) }
                catch { warnings.append("Не вдалося очистити оброблений запис черги. Буде повторено.") }
            }
            for original in scan.events {
                let e = routedCapture(original)
                if handled.contains(e.id) || existing.contains(e.id) { remove(e); continue }
                let p = db.capturePreferences ?? .init()
                let enabled = e.source == "Apple Pay" ? p.walletAuto : p.messageAuto
                if auto && enabled && e.currency == "UAH" && e.clearPurchase && !e.incoming && !captureMatch(e, in: staged), let o = capturedOperation(e, kind: .expense) {
                    Self.recordCapture(e, operation: o, learn: false, in: &staged)
                    accepted.append(e)
                } else { pending.append(e) }
            }
            if !accepted.isEmpty {
                // Store.change retains all existing validation, snapshots and atomic persistence.
                if change({ $0 = staged }) { for e in accepted { remove(e) } }
                else {
                    pending.append(contentsOf: accepted)
                    warnings.append("Пакет не збережено. Операції залишилися у черзі.")
                }
            }
            pending.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            if capturePending != pending { capturePending = pending }
            let warning = warnings.isEmpty ? nil : Array(Set(warnings)).sorted().joined(separator: "\n")
            if captureWarning != warning { captureWarning = warning }
        } catch {
            if captureWarning != error.localizedDescription { captureWarning = error.localizedDescription }
        }
    }
    private static func recordCapture(_ e: CapturedPayment, operation: Operation?, learn: Bool, in d: inout Database) {
        guard !(d.captureHandled ?? []).contains(e.id) else { return }
        if let operation, !d.operations.contains(where: { $0.id == e.id }) {
            d.operations.append(operation)
            if learn && (operation.kind == .expense || operation.kind == .income || operation.kind == .receipt) && operation.category != "Без категорії" && !e.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var rules = d.merchantRules ?? [:]; finamiRememberMerchant(e.merchant, kind: operation.kind, category: operation.category, rules: &rules); d.merchantRules = rules
            }
            if let available = e.reportedAvailable, d.accounts.contains(where: { $0.id == operation.account && $0.code == e.currency }) {
                var observations = d.balanceObservations ?? [:]
                if observations[operation.account].map({ $0.date <= e.date }) ?? true { observations[operation.account] = FinamiBalanceObservation(accountID: operation.account, date: e.date, available: available, currency: e.currency) }
                d.balanceObservations = observations
            }
        }
        var handled = d.captureHandled ?? []; handled.append(e.id); d.captureHandled = handled
        d.captureMessageFingerprints = captureRememberMessage(e, handled: d.captureMessageFingerprints ?? [])
    }
    @discardableResult func finishCapture(_ e: CapturedPayment, operation: Operation?, allowSeparatePayment: Bool = false, learnMerchantCategory: Bool = false, inbox: URL? = nil) -> Bool {
        // Recheck at commit, not just when a review screen was opened.
        if operation != nil && !allowSeparatePayment && captureMatch(e) {
            captureWarning="Можливий дублікат. Підтвердьте, що це окрема покупка."
            return false
        }
        guard change({ d in Self.recordCapture(e, operation: operation, learn: learnMerchantCategory, in: &d) }) else { return false }
        do {try CaptureInbox.remove(e,in:inbox ?? CaptureInbox.folder())} catch {captureWarning=error.localizedDescription}
        capturePending.removeAll{$0.id==e.id}
        return true
    }
}

struct AutomationCenter: View {
    @EnvironmentObject var s: Store
    @Environment(\.openURL) var openURL
    @State private var account=""
    @State private var copied=false
    @State private var sample="Оплата 125,50 UAH; Магазин: ATБ; Баланс 1000 UAH"
    @State private var testResult=""
    @AppStorage("finami.lastShortcutCheck") private var lastShortcutCheck: Double = 0
    @AppStorage("finami.lastWalletCapture") private var lastWalletCapture: Double = 0
    @AppStorage("finami.lastWalletAttempt") private var lastWalletAttempt: Double = 0
    @AppStorage("finami.lastWalletStatus") private var lastWalletStatus = ""
    @State private var walletKey = ""
    @State private var walletBindingMessage = ""
    @AppStorage("finami.lastBankNotification") private var lastBankNotification: Double = 0
    @AppStorage("finami.lastNotificationAttempt") private var lastNotificationAttempt: Double = 0
    @AppStorage("finami.lastNotificationStatus") private var lastNotificationStatus = ""
    @State private var openFailed = false
    @State private var checkTime: Double = 0
    @AppStorage("finami.lastBackgroundCapture") private var lastBackgroundCapture: Double = 0
    @AppStorage("finami.backgroundCaptureSchedule") private var backgroundSchedule = ""
    @AppStorage("finami.notificationShortcutLink") private var notificationShortcutLink = ""
    @AppStorage("finami.walletShortcutLink") private var walletShortcutLink = ""
    @State private var templateEditor = false
    private func importShortcut(_ link: String) {
        guard let url = finamiSharedShortcutURL(link) else { templateEditor = true; return }
        openURL(url) { accepted in if !accepted { openFailed = true } }
    }
    private func launchShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        openURL(url) { accepted in if !accepted { openFailed = true } }
    }
    private func stamp(_ value: Double) -> String { value > 0 ? Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .shortened) : "Ще не зафіксовано" }
    private var chosen: Account? {s.db.accounts.first{$0.id==account}}
    private func setting(_ key: WritableKeyPath<CapturePreferences,Bool>) -> Binding<Bool> {
        Binding(get:{(s.db.capturePreferences ?? .init())[keyPath:key]},set:{v in
            if s.change({d in var p=d.capturePreferences ?? .init();p[keyPath:key]=v;d.capturePreferences=p}) {s.refreshCaptures()}
        })
    }
    var body: some View {
        List {
            templateSection
            setupSection
            walletBindingSection
            connectionSection
            autoSection
            guideSection
            testSection
        }.navigationTitle("Автоматизація")
            .onAppear {if account.isEmpty {account=s.db.accounts.first(where:{$0.id != cash})?.id ?? s.db.accounts.first?.id ?? ""};s.refreshCaptures()}
            .alert("Не вдалося відкрити Команди", isPresented: $openFailed) { Button("OK", role: .cancel) {} } message: { Text("Відкрий системний застосунок Команди вручну.") }
    }
    private var walletBindingSection: some View {
        Section("Apple Pay · універсальна команда") {
            Text("Стара дія Apple Pay з кодом рахунку залишається робочою. Для нової дії «Apple Pay · прив’язка картки» передай унікальний ключ картки з транзакції, якщо Команди його надають. Однакові назви не підходять; використовуй окремі команди або власні унікальні ключі. Не вводь повний номер картки.").font(.caption)
            TextField("Унікальний ключ картки", text: $walletKey).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Прив’язати до вибраного рахунку") {
                guard let key = finamiWalletAliasKey(walletKey), let chosen else {return}
                var prefs = s.db.capturePreferences ?? .init()
                var bindings = prefs.walletBindings ?? [:]
                guard bindings[key] == nil || bindings[key] == chosen.id else {
                    walletBindingMessage = "Ключ уже належить іншому рахунку. Видали стару прив’язку або обери інший ключ."; return
                }
                bindings[key] = chosen.id; prefs.walletBindings = bindings
                if s.change({$0.capturePreferences = prefs}) { walletKey = ""; walletBindingMessage = "Прив’язку збережено"; s.refreshCaptures() }
            }.disabled(chosen == nil || finamiWalletAliasKey(walletKey) == nil)
            if !walletBindingMessage.isEmpty { Text(walletBindingMessage).font(.caption) }
            ForEach(s.db.accounts) { a in
                let count = (s.db.capturePreferences?.walletBindings ?? [:]).values.filter { $0 == a.id }.count
                if count > 0 {
                    HStack { Text(a.name); Spacer(); Text("\(count)").foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            s.change { d in var prefs = d.capturePreferences ?? .init(); prefs.walletBindings = (prefs.walletBindings ?? [:]).filter { $0.value != a.id }; d.capturePreferences = prefs }
                            s.refreshCaptures(auto: false)
                        } label: { Image(systemName: "trash").accessibilityLabel("Видалити прив’язки рахунку") }.buttonStyle(.borderless)
                    }
                }
            }
            Text("Ключ зберігається як хеш; невідома картка потрапляє у Вхідні без автоматичного запису. Для двох однакових назв Wallet рекомендовано окремі команди з кодами рахунків.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var setupSection: some View {
        Section("Рахунок та ручне налаштування (за потреби)") {
            Picker("Рахунок",selection:$account) {
                Text("Вибрати").tag("")
                ForEach(s.db.accounts){a in Text(a.name+" · "+a.code).tag(a.id)}
            }
            if let chosen {
                LabeledContent("Валюта",value:chosen.code)
                Button {UIPasteboard.general.string=chosen.id;copied=true} label:{Label(copied ? "Код скопійовано":"Копіювати код рахунку",systemImage:"doc.on.doc")}
                Text(chosen.id).font(.caption2.monospaced()).textSelection(.enabled)
            }
            Text("Для сповіщень можна вказати auto та назву банку в дії Finami. Заповни останні 4 цифри картки в Рахунках; неоднозначні збіги залишаться у вхідних.").font(.caption)
            Text("Спочатку створіть рахунок у вкладці Рахунки. Для кожної картки налаштуйте окрему автоматизацію. Код рахунку — внутрішній ID, не номер картки.").font(.caption)
            Button { if let chosen { UIPasteboard.general.string = chosen.id; copied = true }; launchShortcuts() } label: { Label("Відкрити Команди для налаштування", systemImage: "bolt.fill") }.disabled(chosen == nil)
            Text("Шукай готові дії в Команди → Програми → Finami. Ця кнопка не встановлює персональну автоматизацію. Тригер та його параметри потрібно один раз налаштувати вручну.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of:account){_ in copied=false}
    }
    private var templateSection: some View {
        Section("Додати в Команди") {
            Label("Витрати зі сповіщень банку", systemImage: "bell.badge")
            Text("ПУМБ, ОТП, Приват24 · обери банк у системній автоматизації. Формат ПУМБ перевірено на текстових прикладах; ОТП і Приват потребують зразків.").font(.caption)
            Button { importShortcut(finamiBankShortcutURL(notificationShortcutLink)?.absoluteString ?? "") } label: {
                Label("Додати в Команди · сповіщення", systemImage: "plus.circle.fill")
            }.buttonStyle(.borderless).accessibilityIdentifier("qa.automation.import.bank")
            Button { importShortcut(walletShortcutLink) } label: {
                Label(finamiSharedShortcutURL(walletShortcutLink) == nil ? "Налаштувати шаблон · Apple Pay" : "Додати в Команди · Apple Pay", systemImage: "plus.circle.fill")
            }.buttonStyle(.borderless).accessibilityIdentifier("qa.automation.import.wallet")
            Text("1. Імпортуй шаблон. 2. Підтвердь банк і тригер у Командах. 3. Перевір отримання реальної операції. Рахунок auto використовує банк і маску картки. Не додавай ту саму команду повторно.").font(.caption)
            if finamiSharedShortcutURL(walletShortcutLink) == nil {
                Text("Для Apple Pay окремого імпортованого шаблону ще немає. Скористайся готовою дією Finami нижче або додай власне посилання.").font(.caption).foregroundStyle(.secondary)
            }
            ShortcutsLink()
            Button { templateEditor = true } label: { Label("Посилання на власні шаблони", systemImage: "link") }.buttonStyle(.borderless)
        }.sheet(isPresented: $templateEditor) {
            NavigationStack {
                Form {
                    Section("Експортовані команди Finami") {
                        TextField("Сповіщення банку · iCloud URL", text: $notificationShortcutLink).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        if !notificationShortcutLink.isEmpty && finamiSharedShortcutURL(notificationShortcutLink) == nil { Text("Некоректне власне посилання. Використовується стандартний шаблон Finami.").foregroundStyle(.orange) }
                        if notificationShortcutLink.isEmpty { Text("Використовується стандартний шаблон Finami.").font(.caption).foregroundStyle(.secondary) }
                        Button("Відновити стандартний шаблон сповіщень") { notificationShortcutLink = "" }
                        TextField("Apple Pay · iCloud URL", text: $walletShortcutLink).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        if !walletShortcutLink.isEmpty && finamiSharedShortcutURL(walletShortcutLink) == nil { Text("Некоректне посилання iCloud").foregroundStyle(.orange) }
                        Text("Створи команду з дією Finami, потім у Командах → Поділитися → Копіювати посилання iCloud. Не використовуй шаблон іншого застосунку: він викликає чужу дію.").font(.caption)
                    }
                    Section("Перший запуск") { ShortcutsLink(); Text("Налаштуй тригер, передай текст сповіщення або параметри Apple Pay, вибери рахунок та увімкни автоматизацію. Перевірка зв’язку не підтверджує встановлення тригера.").font(.caption) }
                }.navigationTitle("Шаблони команд").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { templateEditor = false } } }
            }
        }
    }
    @ViewBuilder private var connectionSection: some View {
        Section("Швидкий доступ до планування") {
            Text("У Командах створи дію «Відкрити URL» з адресою finami-widget://planning. Вона відкриває прогноз після розблокування Finami.").font(.caption)
            Button("Копіювати адресу") {UIPasteboard.general.string="finami-widget://planning"}
        }
        Section("Перевірка зв’язку та сповіщень") {
            LabeledContent("Тест дії Команд", value: stamp(lastShortcutCheck))
            LabeledContent("Останній прийом Apple Pay", value: stamp(lastWalletCapture))
            LabeledContent("Останній виклик Apple Pay", value: stamp(lastWalletAttempt))
            Text(FinamiNotificationStatus.display(lastWalletStatus)).font(.caption)
            LabeledContent("Очікують перевірки", value: String(s.capturePending.count))
            LabeledContent("Остання фонова обробка", value: stamp(lastBackgroundCapture))
            if !backgroundSchedule.isEmpty { Text(backgroundSchedule == "requested" ? "Фонове оновлення запитано. Час запуску визначає iOS." : "Фонове оновлення недоступне або запит відхилено. Черга збережена.").font(.caption).foregroundStyle(.secondary) }
            Button("Запросити фонове оновлення") { FinamiCaptureBackground.schedule() }
            LabeledContent("Остання прийнята операція банку", value: stamp(lastBankNotification))
            LabeledContent("Останній виклик сповіщення", value: stamp(lastNotificationAttempt))
            Text(FinamiNotificationStatus.display(lastNotificationStatus)).font(.caption).accessibilityIdentifier("qa.automation.notificationStatus")
            Text("Ручний запуск ▶ без справжнього сповіщення не створює операцію. Неплатіжні повідомлення пропускаються без діалогів; тут видно причину. Якщо немає типу операції, передай заголовок окремо. Для auto вкажи банк і маску картки.").font(.caption)
            Button { launchShortcuts() } label: { Label("Відкрити Команди для тесту", systemImage: "checkmark.shield") }
            Text("У Командах знайди Finami → Перевірка зв’язку і запусти її. Повернись сюди: час тесту має оновитися. Цей тест не додає витрату і не підтверджує роботу Wallet-тригера.").font(.caption)
            Button("Перевірити локальний обробник") {
                do { _ = try captureWallet(amount: 1.25, merchant: "Test", account: account, currency: chosen?.code ?? "UAH"); checkTime = Date().timeIntervalSince1970 }
                catch { testResult = error.localizedDescription }
            }.disabled(chosen == nil)
            if checkTime > 0 { Text("Локальний тест: " + stamp(checkTime) + " · без запису").font(.caption).foregroundStyle(.secondary) }
            Text("Після налаштування тригера перевір наступний реальний платіж у Вхідних операціях. Відсутність часу не доводить, що автоматизації немає; Finami не може читати список системних автоматизацій.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var autoSection: some View {
        Section("2. Автоматичне збереження") {
            Toggle("Apple Pay без підтвердження",isOn:setting(\.walletAuto))
            Toggle("Однозначні покупки з SMS / сповіщень",isOn:setting(\.messageAuto))
            Toggle("Сповіщати про збережені операції", isOn: Binding(get: { s.db.capturePreferences?.notifySaved ?? false }, set: { value in
                s.change { d in var p = d.capturePreferences ?? .init(); p.notifySaved = value; d.capturePreferences = p }
                if value { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound]) } }
            }))
            Text("Спочатку обидва вимкнені. Перевірте одну реальну покупку, потім увімкніть потрібний режим. Події зберігаються Командами без відкриття Finami. Обробка виконується при доступному фоновому запуску iOS або при наступному відкритті після розблокування. Невідомий магазин отримує категорію «Без категорії». Повторні повідомлення ніколи не додаються автоматично, навіть після перезапуску. Схожі платежі, доларові суми та неоднозначні рухи залишаються на перевірку. Не вмикайте одночасно кілька джерел для однієї картки без звірки.").font(.caption)
        }
    }
    private var guideSection: some View {
        Section("Покрокові інструкції") {
            NavigationLink {AutomationGuide(title:"Apple Pay / Wallet",steps:AutomationGuide.wallet)} label:{IzanamiLabel(title:"Apple Pay — налаштувати",icon:"wallet.pass.fill",color:.blue)}
            NavigationLink {AutomationGuide(title:"SMS / повідомлення",steps:AutomationGuide.messages)} label:{IzanamiLabel(title:"Фізична картка та SMS",icon:"message.fill",color:.green)}
            NavigationLink {AutomationGuide(title:"Сповіщення банку",steps:AutomationGuide.notifications)} label:{IzanamiLabel(title:"Сповіщення (якщо підтримує iOS)",icon:"bell.badge.fill",color:.orange)}
            NavigationLink {AutomationGuide(title:"Банки та звірка",steps:AutomationGuide.banks)} label:{IzanamiLabel(title:"Інші оплати та виписки",icon:"building.columns.fill",color:.purple)}
            Link("Офіційна довідка Apple про Wallet",destination:URL(string:"https://support.apple.com/en-euro/guide/shortcuts/apd65c67538a/ios")!)
        }
    }
    private var testSection: some View {
        Section("Тест розпізнавання без запису") {
            Button("Перевірити формат ПУМБ") {
                testResult = finamiNotificationSelfTest() ? "Тест пройдено: 20,00 ₴, покупка, банк і маска визначені. Баланс не змінено." : "Тест не пройдено. Баланс не змінено."
            }.accessibilityIdentifier("qa.automation.testPUMB")
            TextField("Знеособлений приклад SMS",text:$sample,axis:.vertical)
            Button("Перевірити текст") {
                do {let e=try captureMessage(sample,account:account);testResult=currencyMoney(e.minor,e.currency)+" · "+(e.incoming ? "Зарахування":"Списання")+" · "+(e.clearPurchase ? "Покупка":"Потрібна перевірка")}
                catch {testResult=error.localizedDescription}
            }.disabled(account.isEmpty)
            if !testResult.isEmpty {Text(testResult).font(.caption)}
            Text("Тест нічого не записує. Не вводьте PIN, CVV, пароль або код підтвердження.").font(.caption)
        }
    }
}

struct CaptureReview: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) var dismiss
    let event: CapturedPayment
    @State private var kind: Kind = .expense
    @State private var accountID = ""
    @State private var category = ""
    @State private var remember = true
    private var selectedEvent: CapturedPayment { var e = event; e.account = accountID; return e }
    private var categories: [String] { kind == .receipt ? s.db.availableReceiptCategories : kind == .income ? s.db.incomeCategories : s.db.expenseCategories }
    @State private var receiptTreatment: FinamiReceiptTreatment = .pending
    @State private var confirm=false
    @State private var discard=false
    @State private var separatePayment=false
    private var allowed: [Kind] {Kind.allCases.filter{$0 != .transfer && $0.incoming==event.incoming}}
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Джерело",value:event.source)
                Picker("Рахунок", selection: $accountID) { Text("Обери рахунок").tag(""); ForEach(s.db.accounts.filter { $0.code == event.currency }) { Text($0.name).tag($0.id) } }
                if accountID.isEmpty { Text("Рахунок не визначено однозначно. Вибери його вручну.").foregroundStyle(.orange) }
                LabeledContent("Сума",value:s.visibleMoney(event.minor,event.currency))
                LabeledContent("Дата",value:event.date.formatted(date:.abbreviated,time:.shortened))
                if let available = event.reportedAvailable { LabeledContent("Доступно за даними банку", value: s.visibleMoney(available, event.currency)); Text("Це довідкова сума, а не витрата.").font(.caption) }
                if !event.merchant.isEmpty {LabeledContent("Продавець",value:event.merchant)}
                if event.incoming && event.incomeHint == true { Text("Явний тип доходу розпізнано. Підтвердьте, що це не переказ власних коштів.").font(.caption).foregroundStyle(.secondary) }
                Picker("Тип",selection:$kind){ForEach(allowed){k in Text(k.title).tag(k)}}
                if s.captureMatch(selectedEvent) {
                    Text(s.captureRepeat(event) ? "Такий самий текст повідомлення вже оброблено. Повтор не змінить баланс автоматично." : "Схожа операція вже є. Якщо це та сама покупка, відхиліть подію.").foregroundStyle(.orange)
                    Toggle("Це інша, окрема покупка",isOn:$separatePayment)
                }
                if let o=s.capturedOperation(selectedEvent,kind:kind) {
                    if kind.isReportCategory {
                        Picker("Категорія", selection: $category) { Text("Автоматично: " + o.category).tag(""); ForEach(categories, id: \.self) { Text($0).tag($0) } }
                        if !event.merchant.isEmpty { Toggle("Запам’ятати категорію продавця", isOn: $remember) }
                    }
                    if kind == .receipt { Picker("У звітах", selection: $receiptTreatment) { ForEach(FinamiReceiptTreatment.unlinkedChoices) { Text($0.title).tag($0) } } }
                    if let rate=o.exchangeRate {LabeledContent("Курс UAH/USD (поточний)",value:rate);LabeledContent("Еквівалент",value:s.visibleMoney(o.amount));Text("Після збереження можна виправити курс у редакторі операції.").font(.caption)}
                }
                else {Text("Рахунок видалено, валюта не збігається або немає курсу. Перевірте рахунок і курс. За потреби внесіть платіж вручну.").foregroundStyle(.orange)}
                Button("Зберегти операцію"){confirm=true}.disabled(s.capturedOperation(selectedEvent,kind:kind)==nil || (s.captureMatch(selectedEvent) && !separatePayment))
                Button("Відхилити подію",role:.destructive){discard=true}
            }.navigationTitle("Перевірка платежу").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Закрити"){dismiss()}}}
                .onAppear{kind=event.incoming ? (event.incomeHint == true ? .income : .unclassifiedCredit) : event.clearPurchase ? .expense:.unclassifiedDebit; accountID=event.account}.onChange(of: kind) { _ in category=""; receiptTreatment = .pending }.onChange(of: category) { value in if kind == .receipt { receiptTreatment = FinamiReceiptTreatment.suggestion(value) } }.onChange(of: accountID) { _ in separatePayment=false }
                .confirmationDialog("Зберегти платіж?",isPresented:$confirm){Button("Зберегти"){if var o=s.capturedOperation(selectedEvent,kind:kind) { if kind.isReportCategory && categories.contains(category) { o.category=category }; if kind == .receipt { o.receiptTreatment = receiptTreatment }; if s.finishCapture(selectedEvent,operation:o,allowSeparatePayment:separatePayment,learnMerchantCategory:remember && !category.isEmpty && category != "Без категорії") { dismiss() } }}}
                .confirmationDialog("Відхилити без запису?",isPresented:$discard){Button("Відхилити",role:.destructive){if s.finishCapture(event,operation:nil){dismiss()}}}
        }
    }
}

struct AutomationGuide: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var s:Store
    @State private var accountID=""
    let title: String
    let steps: [String]
    var body: some View {
        ScrollView {VStack(alignment:.leading,spacing:20){
            if title.contains("Apple Pay") || title.contains("Сповіщення банку") { Picker("Рахунок Finami",selection:$accountID){Text("Вибрати рахунок").tag("");ForEach(s.db.accounts){a in Text(a.name+" · "+a.code).tag(a.id)}};Button { UIPasteboard.general.string=accountID;if let url=URL(string:"shortcuts://") {openURL(url)} } label:{Label("Відкрити Команди для налаштування",systemImage:"bolt.fill")}.buttonStyle(.borderedProminent).disabled(accountID.isEmpty);Text("Код рахунку скопіюється. У Командах додай потрібний системний тригер. Ця кнопка відкриває Команди, а не імпортує готовий шаблон.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(steps.enumerated()),id:\.offset){entry in
                HStack(alignment:.top,spacing:14){
                    Text(String(entry.offset+1)).font(.headline).foregroundStyle(.white).frame(width:36,height:36).background(finoraAccent,in:Circle())
                    Text(entry.element).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                }
            }
        }.padding()}.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    static let wallet=[
        "У Finami → Рахунки створіть картку, перевірте валюту та кредитний ліміт. У Ще → Автоматизація виберіть цю картку і скопіюйте її код.",
        "Відкрийте Команди. У новому редакторі додайте тригер «Коли торкають картку»; у старішому — Автоматизація → + → Транзакція. Шукайте Wallet або Гаманець. Доступність залежить від iOS.",
        "Виберіть лише потрібну картку в When I tap / Коли торкаюся. Категорії та продавці — усі. Виберіть Run Immediately / Запускати негайно, якщо доступно.",
        "Натисніть Далі → Нова порожня автоматизація → Додати дію. Знайдіть Finami: Apple Pay (пошук Finami). Якщо дія не відображається, відкрийте Finami після встановлення, закрийте й знову відкрийте Команди. Спробуйте запустити Finami: перевірка зв’язку; це безпечний тест, не покупка.",
        "У Amount / Сума вставте змінну Shortcut Input / Вхідні дані команди. Торкніться змінної ще раз і виберіть властивість Amount, а не весь об’єкт. Merchant / Продавець — та сама змінна, властивість Merchant. Якщо поле продавця недоступне, введіть Apple Pay.",
        "У Account code вставте скопійований код. У Currency впишіть UAH або USD відповідно до фактичної валюти суми. Для оплати в іншій валюті залиште автоматичне збереження вимкненим і звіряйте суму списання з банком. Не підставляйте курс навмання.",
        "Збережіть автоматизацію. При наступній звичайній покупці відкрийте Finami → Операції → Вхідні операції. Звірте суму та картку. Після успішного тесту за бажанням увімкніть Apple Pay без підтвердження.",
        "Повторіть для кожної картки. Wallet-тригер не гарантує облік онлайн-покупок, фізичних карток, Apple Watch або завершення банківського списання. Звіряйте з випискою; помилкову подію відхиліть або виправте операцію."]
    static let messages=[
        "У банку увімкніть саме SMS про проведені операції, якщо банк пропонує їх. Не використовуйте SMS з кодами безпеки. Застосунок не читає історію SMS.",
        "У Finami → Ще → Автоматизація виберіть картку, скопіюйте її код. Спочатку перевірте знеособлений приклад повідомлення в тесті розпізнавання.",
        "Команди → Автоматизація → + → Повідомлення (Message). Вкажіть справжнього відправника банківських SMS, а також фільтр тексту для покупок або останніх цифр потрібної картки. Не обирайте всі повідомлення. Увімкніть негайний запуск, якщо доступний.",
        "Нова порожня автоматизація → Додати дію → Finami: Bank message. У Message text передайте Shortcut Input → Content / Текст. У Account code вставте код відповідної картки. Збережіть.",
        "При наступному SMS відкрийте Finami → Операції → Вхідні операції. Спочатку звірте вручну. Якщо формат стабільно розпізнається, увімкніть Однозначні покупки з SMS.",
        "Приклад: Оплата 125,50 UAH; Магазин: ATБ; Баланс 1000 UAH. Розпізнається сума оплати, а не баланс. Якщо є кілька сум, незрозуміла валюта, OTP або відмова — дія не запише транзакцію. Внесіть підтверджений платіж вручну або імпортуйте виписку.",
        "Для різних карток використовуйте різні фільтри. SMS можуть бути платними або недоступними у вашому банку. Перекази, поповнення й погашення підтверджуйте окремо."]
    static let notifications=[
        "На iOS 27 відкрийте Команди, створіть нову команду та в редакторі виберіть розділ Автоматизація → Сповіщення (Notification). На старіших iOS використовуйте SMS, Wallet або виписки.",
        "Виберіть тільки застосунок потрібного банку. Заповніть фільтр Назва містить Купівля (якщо банк використовує цей заголовок) або видаліть порожній фільтр. Для інших типів операцій використайте окреме правило; коди безпеки не передавайте.",
        "Додайте дію Finami: сповіщення банку. У Текст сповіщення виберіть змінну Сповіщення та її текст/тіло (Body). Якщо банк передає тип операції окремо (наприклад, Купівля), розгорніть дію та передайте властивість Title в Заголовок сповіщення. Якщо сума у підзаголовку, об’єднайте потрібні поля через дію Текст. У Код рахунку Finami вставте скопійований код. Не передавайте OTP чи повідомлення безпеки.",
        "Увімкніть автоматизацію в редакторі команди. За можливості вимкніть підтвердження перед запуском. Перевірте наступну реальну оплату у вхідних Finami та час останнього повідомлення. Не вмикайте одночасно два джерела для тієї ж картки без звірки. Готові дії доступні через Програми → Finami після реєстрації iOS. Щоб отримати імпортований шаблон, збережіть створену команду через Поділитися → Копіювати посилання iCloud."]
    static let banks=[
        "ПУМБ: Wallet або SMS/сповіщення, якщо доступні; для звірки використовуйте PDF-виписку. Кредитний ліміт задайте в картці, не як дохід.",
        "А-БАНК: Wallet або SMS/сповіщення, якщо доступні; PDF із MCC для точнішої категоризації.",
        "monobank: у Банки та імпорт можна підключити персональний API для ручного оновлення. Не дублюйте автоматичний облік через Wallet без перевірки.",
        "ОТП: Wallet або SMS/сповіщення, якщо доступні; підтримується XLSX-виписка.",
        "Приват24: Wallet або SMS/сповіщення, якщо доступні. PDF виписку можна перевірити через імпорт банків.",
        "Під час імпорту банк може показати іншу суму або дату. Можливі дублікати з автоматизації позначаються та не вибираються автоматично. Якщо це той самий платіж — залиште один запис і звірте його з банком. Якщо окремий — оберіть його вручну.",
        "Вимкнення: Команди → Автоматизація → виберіть створене правило → вимкніть або видаліть. В Finami також можна вимкнути автоматичне збереження; тоді події лишатимуться у вхідних. Для ручного введення використовуйте Додати операцію."]
}
