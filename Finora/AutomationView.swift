import SwiftUI
import UIKit

struct CapturePreferences: Codable {
    var walletAuto = false
    var messageAuto = false
}

@MainActor extension Store {
    func captureRepeat(_ e: CapturedPayment) -> Bool {
        captureRepeatedMessage(e,handled:db.captureMessageFingerprints ?? [])
    }
    func captureMatch(_ e: CapturedPayment) -> Bool {
        if captureRepeat(e) {return true}
        return db.operations.contains { o in
            capturePossibleDuplicate(e,otherAccount:o.account,otherCurrency:o.entryCurrency ?? "UAH",otherAmount:o.sourceMinor ?? o.amount,otherIncoming:o.kind.incoming,otherDate:o.date,otherSource:o.captureSource,isBank:o.sourceBank != nil)
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
        do {
            let dir=try (inbox ?? CaptureInbox.folder())
            let all=try CaptureInbox.read(in:dir)
            let handled=Set(db.captureHandled ?? [])
            var pending=[CapturedPayment]()
            for e in all {
                if handled.contains(e.id) || db.operations.contains(where:{$0.id==e.id}) {
                    try CaptureInbox.remove(e,in:dir);continue
                }
                let p=db.capturePreferences ?? .init()
                let enabled=e.source=="Apple Pay" ? p.walletAuto:p.messageAuto
                if auto && enabled && e.currency == "UAH" && e.clearPurchase && !e.incoming && !captureMatch(e), let o=capturedOperation(e,kind:.expense) {
                    if finishCapture(e,operation:o,inbox:dir) {continue}
                }
                pending.append(e)
            }
            if capturePending != pending {capturePending=pending}
            if captureWarning != nil {captureWarning=nil}
        } catch {captureWarning=error.localizedDescription}
    }
    @discardableResult func finishCapture(_ e: CapturedPayment, operation: Operation?, allowSeparatePayment: Bool = false, inbox: URL? = nil) -> Bool {
        // Recheck at commit, not just when a review screen was opened.
        if operation != nil && !allowSeparatePayment && captureMatch(e) {
            captureWarning="Можливий дублікат. Підтвердьте, що це окрема покупка."
            return false
        }
        guard change({d in
            if !(d.captureHandled ?? []).contains(e.id) {
                if let operation, !d.operations.contains(where:{$0.id==e.id}) {d.operations.append(operation)}
                var handled=d.captureHandled ?? [];handled.append(e.id);d.captureHandled=handled
                d.captureMessageFingerprints=captureRememberMessage(e,handled:d.captureMessageFingerprints ?? [])
            }
        }) else {return false}
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
    @State private var review: CapturedPayment?
    @State private var sample="Оплата 125,50 UAH; Магазин: ATБ; Баланс 1000 UAH"
    @State private var testResult=""
    @AppStorage("finami.lastShortcutCheck") private var lastShortcutCheck: Double = 0
    @AppStorage("finami.lastWalletCapture") private var lastWalletCapture: Double = 0
    @AppStorage("finami.lastBankNotification") private var lastBankNotification: Double = 0
    @State private var openFailed = false
    @State private var checkTime: Double = 0
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
            setupSection
            connectionSection
            autoSection
            inboxSection
            guideSection
            testSection
        }.navigationTitle("Автоматизація")
            .onAppear {if account.isEmpty {account=s.db.accounts.first(where:{$0.id != cash})?.id ?? s.db.accounts.first?.id ?? ""};s.refreshCaptures()}
            .sheet(item:$review){CaptureReview(event:$0)}
            .alert("Не вдалося відкрити Команди", isPresented: $openFailed) { Button("OK", role: .cancel) {} } message: { Text("Відкрий системний застосунок Команди вручну.") }
    }
    private var setupSection: some View {
        Section("1. Виберіть картку") {
            Picker("Рахунок",selection:$account) {
                Text("Вибрати").tag("")
                ForEach(s.db.accounts){a in Text(a.name+" · "+a.code).tag(a.id)}
            }
            if let chosen {
                LabeledContent("Валюта",value:chosen.code)
                Button {UIPasteboard.general.string=chosen.id;copied=true} label:{Label(copied ? "Код скопійовано":"Копіювати код рахунку",systemImage:"doc.on.doc")}
                Text(chosen.id).font(.caption2.monospaced()).textSelection(.enabled)
            }
            Text("Спочатку створіть рахунок у вкладці Рахунки. Для кожної картки налаштуйте окрему автоматизацію. Код рахунку — внутрішній ID, не номер картки.").font(.caption)
            Button { if let chosen { UIPasteboard.general.string = chosen.id; copied = true }; launchShortcuts() } label: { Label("Копіювати код і відкрити Команди", systemImage: "bolt.fill") }.disabled(chosen == nil)
            Text("Це відкриває Команди, але не створює автоматизацію. Тригер та його параметри потрібно один раз налаштувати вручну.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of:account){_ in copied=false}
    }
    private var connectionSection: some View {
        Section("Перевірка зв’язку Apple Pay") {
            LabeledContent("Тест дії Команд", value: stamp(lastShortcutCheck))
            LabeledContent("Останній прийом Apple Pay", value: stamp(lastWalletCapture))
            LabeledContent("Останнє повідомлення банку", value: stamp(lastBankNotification))
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
            Text("Спочатку обидва вимкнені. Перевірте одну реальну покупку, потім увімкніть потрібний режим. Події обробляються при відкритті Finami (після розблокування), а не в момент оплати. Невідомий магазин отримує категорію «Без категорії». Повторні повідомлення ніколи не додаються автоматично, навіть після перезапуску. Схожі платежі, доларові суми та неоднозначні рухи залишаються на перевірку. Не вмикайте одночасно кілька джерел для однієї картки без звірки.").font(.caption)
        }
    }
    private var inboxSection: some View {
        Section("3. Вхідні операції (\(s.capturePending.count))") {
            Button("Оновити чергу") {s.refreshCaptures()}
            if let warning=s.captureWarning {Text(warning).foregroundStyle(.orange)}
            if s.capturePending.isEmpty {Text("Немає нових операцій").foregroundStyle(.secondary)}
            ForEach(s.capturePending){e in
                Button {review=e} label:{
                    VStack(alignment:.leading,spacing:5){
                        Text(e.merchant.isEmpty ? e.source:e.merchant).foregroundStyle(.primary).font(.headline)
                        Text(s.visibleMoney(e.minor,e.currency)).font(.title3.bold())
                        Text(s.accountName(e.account)+" · "+e.date.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                        if s.captureMatch(e) {Label(s.captureRepeat(e) ? "Повтор повідомлення" : "Можливий дублікат",systemImage:"exclamationmark.triangle").foregroundStyle(.orange).font(.caption)}
                    }
                }
            }
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
    @State private var confirm=false
    @State private var discard=false
    @State private var separatePayment=false
    private var allowed: [Kind] {Kind.allCases.filter{$0 != .transfer && $0.incoming==event.incoming}}
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Джерело",value:event.source)
                LabeledContent("Рахунок",value:s.accountName(event.account))
                LabeledContent("Сума",value:s.visibleMoney(event.minor,event.currency))
                LabeledContent("Дата",value:event.date.formatted(date:.abbreviated,time:.shortened))
                if !event.merchant.isEmpty {LabeledContent("Продавець",value:event.merchant)}
                Picker("Тип",selection:$kind){ForEach(allowed){k in Text(k.title).tag(k)}}
                if s.captureMatch(event) {
                    Text(s.captureRepeat(event) ? "Такий самий текст повідомлення вже оброблено. Повтор не змінить баланс автоматично." : "Схожа операція вже є. Якщо це та сама покупка, відхиліть подію.").foregroundStyle(.orange)
                    Toggle("Це інша, окрема покупка",isOn:$separatePayment)
                }
                if let o=s.capturedOperation(event,kind:kind) {
                    LabeledContent("Категорія",value:o.category)
                    if let rate=o.exchangeRate {LabeledContent("Курс UAH/USD (поточний)",value:rate);LabeledContent("Еквівалент",value:s.visibleMoney(o.amount));Text("Після збереження можна виправити курс у редакторі операції.").font(.caption)}
                }
                else {Text("Рахунок видалено, валюта не збігається або немає курсу. Перевірте рахунок і курс. За потреби внесіть платіж вручну.").foregroundStyle(.orange)}
                Button("Зберегти операцію"){confirm=true}.disabled(s.capturedOperation(event,kind:kind)==nil || (s.captureMatch(event) && !separatePayment))
                Button("Відхилити подію",role:.destructive){discard=true}
            }.navigationTitle("Перевірка платежу").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Закрити"){dismiss()}}}
                .onAppear{kind=event.incoming ? .unclassifiedCredit : event.clearPurchase ? .expense:.unclassifiedDebit}
                .confirmationDialog("Зберегти платіж?",isPresented:$confirm){Button("Зберегти"){if let o=s.capturedOperation(event,kind:kind),s.finishCapture(event,operation:o,allowSeparatePayment:separatePayment){dismiss()}}}
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
            if title.contains("Apple Pay") || title.contains("Сповіщення банку") { Picker("Рахунок Finami",selection:$accountID){Text("Вибрати рахунок").tag("");ForEach(s.db.accounts){a in Text(a.name+" · "+a.code).tag(a.id)}};Button { UIPasteboard.general.string=accountID;if let url=URL(string:"shortcuts://") {openURL(url)} } label:{Label("Копіювати код і відкрити Команди",systemImage:"bolt.fill")}.buttonStyle(.borderedProminent).disabled(accountID.isEmpty);Text("Код рахунку скопіюється. У Командах додай потрібний системний тригер. Ця кнопка відкриває Команди, а не імпортує готовий шаблон.").font(.caption).foregroundStyle(.secondary) }
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
        "Відкрийте Команди (Shortcuts) → Автоматизація → +. Знайдіть Транзакція (Transaction) або Wallet. Тригер доступний на підтримуваних iOS 17 і новіших.",
        "Виберіть лише потрібну картку в When I tap / Коли торкаюся. Категорії та продавці — усі. Виберіть Run Immediately / Запускати негайно, якщо доступно.",
        "Натисніть Далі → Нова порожня автоматизація → Додати дію. Знайдіть Finami: Apple Pay (пошук Finami). Якщо дія не відображається, відкрийте Finami після встановлення, закрийте й знову відкрийте Команди. Спробуйте запустити Finami: перевірка зв’язку; це безпечний тест, не покупка.",
        "У Amount / Сума вставте змінну Shortcut Input / Вхідні дані команди. Торкніться змінної ще раз і виберіть властивість Amount, а не весь об’єкт. Merchant / Продавець — та сама змінна, властивість Merchant. Якщо поле продавця недоступне, введіть Apple Pay.",
        "У Account code вставте скопійований код. У Currency впишіть UAH або USD відповідно до фактичної валюти суми. Для оплати в іншій валюті залиште автоматичне збереження вимкненим і звіряйте суму списання з банком. Не підставляйте курс навмання.",
        "Збережіть автоматизацію. При наступній звичайній покупці відкрийте Finami → Ще → Автоматизація → Вхідні операції. Звірте суму та картку. Після успішного тесту за бажанням увімкніть Apple Pay без підтвердження.",
        "Повторіть для кожної картки. Wallet-тригер не гарантує облік онлайн-покупок, фізичних карток, Apple Watch або завершення банківського списання. Звіряйте з випискою; помилкову подію відхиліть або виправте операцію."]
    static let messages=[
        "У банку увімкніть саме SMS про проведені операції, якщо банк пропонує їх. Не використовуйте SMS з кодами безпеки. Застосунок не читає історію SMS.",
        "У Finami → Ще → Автоматизація виберіть картку, скопіюйте її код. Спочатку перевірте знеособлений приклад повідомлення в тесті розпізнавання.",
        "Команди → Автоматизація → + → Повідомлення (Message). Вкажіть справжнього відправника банківських SMS, а також фільтр тексту для покупок або останніх цифр потрібної картки. Не обирайте всі повідомлення. Увімкніть негайний запуск, якщо доступний.",
        "Нова порожня автоматизація → Додати дію → Finami: Bank message. У Message text передайте Shortcut Input → Content / Текст. У Account code вставте код відповідної картки. Збережіть.",
        "При наступному SMS відкрийте Finami → Автоматизація → Вхідні операції. Спочатку звірте вручну. Якщо формат стабільно розпізнається, увімкніть Однозначні покупки з SMS.",
        "Приклад: Оплата 125,50 UAH; Магазин: ATБ; Баланс 1000 UAH. Розпізнається сума оплати, а не баланс. Якщо є кілька сум, незрозуміла валюта, OTP або відмова — дія не запише транзакцію. Внесіть підтверджений платіж вручну або імпортуйте виписку.",
        "Для різних карток використовуйте різні фільтри. SMS можуть бути платними або недоступними у вашому банку. Перекази, поповнення й погашення підтверджуйте окремо."]
    static let notifications=[
        "На iOS 27 відкрийте Команди, створіть нову команду та в редакторі виберіть розділ Автоматизація → Сповіщення (Notification). На старіших iOS використовуйте SMS, Wallet або виписки.",
        "Виберіть тільки застосунок потрібного банку. За можливості встановіть фільтр на проведені покупки й конкретну картку, а не всі сповіщення.",
        "Додайте дію Finami: сповіщення банку. У Текст сповіщення виберіть змінну Сповіщення та її текст/тіло (Body). Якщо сума у заголовку чи підзаголовку, об’єднайте лише потрібні поля через дію Текст. У Код рахунку Finami вставте скопійований код. Не передавайте OTP чи повідомлення безпеки.",
        "Увімкніть автоматизацію в редакторі команди. За можливості вимкніть підтвердження перед запуском. Перевірте наступну реальну оплату у вхідних Finami та час останнього повідомлення. Не вмикайте одночасно два джерела для тієї ж картки без звірки. Готове посилання на імпорт команди ще не опубліковано."]
    static let banks=[
        "ПУМБ: Wallet або SMS/сповіщення, якщо доступні; для звірки використовуйте PDF-виписку. Кредитний ліміт задайте в картці, не як дохід.",
        "А-БАНК: Wallet або SMS/сповіщення, якщо доступні; PDF із MCC для точнішої категоризації.",
        "monobank: у Банки та імпорт можна підключити персональний API для ручного оновлення. Не дублюйте автоматичний облік через Wallet без перевірки.",
        "ОТП: Wallet або SMS/сповіщення, якщо доступні; підтримується XLSX-виписка.",
        "Приват24: Wallet або SMS/сповіщення, якщо доступні. Для окремого парсера виписки ще потрібен шаблон.",
        "Під час імпорту банк може показати іншу суму або дату. Можливі дублікати з автоматизації позначаються та не вибираються автоматично. Якщо це той самий платіж — залиште один запис і звірте його з банком. Якщо окремий — оберіть його вручну.",
        "Вимкнення: Команди → Автоматизація → виберіть створене правило → вимкніть або видаліть. В Finami також можна вимкнути автоматичне збереження; тоді події лишатимуться у вхідних. Для ручного введення використовуйте Додати операцію."]
}
