import SwiftUI

struct FinamiBalanceView: View {
    @EnvironmentObject private var s:Store
    @State private var mode:String
    init(initialMode:String="move", accountID:String="") { _mode=State(initialValue:initialMode); _destination=State(initialValue:accountID) }
    @State private var destination:String
    @State private var batch=""
    @State private var transferID=""
    @State private var selected=Set<String>()
    @State private var confirm=false
    @State private var confirmedVersion:UInt64? = nil
    @State private var anchorDate=Date()
    @State private var anchorText=""
    @State private var anchorKind="net"
    @State private var ownText="0"
    @State private var usedText=""
    @State private var acceptEstimate=false
    @State private var availableText=""
    @State private var redundantAdjustment=""
    private var protected:Set<String> {Set((s.db.paidRecords ?? []).compactMap(\.operationID) + (s.db.exchangeDiary ?? []).flatMap{$0.linkedReceiptIDs ?? []} + s.db.operations.compactMap(\.refundOriginalID))}
    private var banks:[Account] {s.db.accounts.filter{$0.code=="UAH"}}
    private var transfers:[Operation] {s.db.operations.filter{o in o.kind == .transfer && o.groupedBankParts==nil && o.bankKey==nil && o.destinationBankKey==nil && s.db.accounts.first(where:{$0.id==o.account})?.code=="USD" && s.db.accounts.first(where:{$0.id==o.destination})?.code=="UAH" && !protected.contains(o.id)}.sorted{$0.date>$1.date}}
    private var transfer:Operation? {transfers.first{$0.id==transferID}}
    private var batches:[String] {Array(Set(s.db.operations.compactMap(\.importBatch))).sorted()}
    private var candidates:[Operation] {
        if mode=="group",let t=transfer {
            return s.db.operations.filter{o in finamiGroupedConversion(transfer:t,rows:[o],accounts:s.db.accounts,protected:protected) != nil}.sorted{$0.date<$1.date}
        }
        if mode=="move",!batch.isEmpty {return s.db.operations.filter{$0.importBatch==batch && $0.kind != .transfer && $0.bankKey != nil && !protected.contains($0.id)}.sorted{$0.date<$1.date}}
        return []
    }
    private var proposal:[Operation]? {
        let rows=s.db.operations.filter{selected.contains($0.id)}
        if mode=="group",let t=transfer,rows.count==selected.count,let grouped=finamiGroupedConversion(transfer:t,rows:rows,accounts:s.db.accounts,protected:protected) {
            var removed=selected
            if !redundantAdjustment.isEmpty {
                guard let adjustment=s.db.operations.first(where:{$0.id==redundantAdjustment}),finamiRedundantFXAdjustment(adjustment,original:t,grouped:grouped,protected:protected) else{return nil}
                removed.insert(adjustment.id)
            }
            return s.db.operations.filter{!removed.contains($0.id)}.map{$0.id==t.id ? grouped:$0}
        }
        if mode=="move",let a=banks.first(where:{$0.id==destination}) {return finamiMoveStatementRows(s.db.operations,ids:selected,to:a,accounts:s.db.accounts,protected:protected)}
        return nil
    }
    private var groupDraft:Operation? {guard let t=transfer else{return nil};return finamiGroupedConversion(transfer:t,rows:s.db.operations.filter{selected.contains($0.id)},accounts:s.db.accounts,protected:protected)}
    private var adjustmentCandidates:[Operation] {guard let t=transfer,let g=groupDraft else{return []};return s.db.operations.filter{finamiRedundantFXAdjustment($0,original:t,grouped:g,protected:protected)}}
    private var groupSuggestion:[Operation] {
        guard let t=transfer,let g=finamiGroupedConversion(transfer:t,rows:candidates,accounts:s.db.accounts,protected:protected) else{return []}
        let expected=t.destinationMinor ?? t.amount
        let difference=abs(expected-g.amount)
        return difference<=max(100,expected/100) ? candidates:[]
    }
    private var anchorAccount:Account? {banks.first{$0.id==destination}}
    private var anchorNet:Int64? {
        guard let a=anchorAccount else{return nil}
        if anchorKind=="components",a.isCredit,let own=bankMinor(ownText),let used=bankMinor(usedText) {return CardPosition.netFrom(own:own,used:used)}
        if anchorKind=="estimate" {guard acceptEstimate,let amount=bankMinor(availableText) else{return nil};return finamiEstimatedNetFromAvailable(amount,limit:a.limit)}
        guard anchorKind=="net" else{return nil};return bankMinor(anchorText)
    }
    private var proposedOpening:Int64? {guard let a=anchorAccount,let n=anchorNet,anchorDate<=Date() else{return nil};return finamiOpeningForAnchor(account:a,operations:s.db.operations,net:n,at:anchorDate)}
    var body:some View {
        List {
            Section("Майстер звірки") {
                Picker("Завдання",selection:$mode){Text("Перенести імпортовані записи").tag("move");Text("Об’єднати валютний переказ").tag("group");Text("Баланс на дату").tag("anchor")}
                Text("Зміни лише після підтвердження. Не використовуй доступний кредит як чистий баланс.").font(.caption)
                NavigationLink("Новий обмін USD → UAH з комісією"){FinamiFXEditor()}
                NavigationLink("Звірка повернень покупок"){FinamiRefundReview()}
            }
            if mode=="group" {groupSection} else {destinationSection}
            if mode=="move" {batchSection}
            if mode=="anchor" {anchorSection} else {selectionSection;previewSection}
            if let data=s.db.reconciliationUndo,let undo=try? JSONDecoder().decode(FinamiBalanceUndo.self,from:data),undo.restore(current:s.db.operations) != nil {
                Section("Скасування") {Button("Скасувати останню звірку",role:.destructive){undoLast()};Text("Доступно, доки історія операцій не змінилася.").font(.caption)}
            }
        }.navigationTitle(mode == "anchor" ? "Звірити баланс" : "Розумна звірка")
        .onAppear { if mode=="anchor",anchorAccount?.isCredit == true,anchorText.isEmpty,usedText.isEmpty { anchorKind="components" } }
        .onChange(of:mode){_ in selected=[];destination=""}
        .onChange(of:batch){_ in selected=[]}
        .onChange(of:destination){_ in anchorText="";availableText="";ownText="0";usedText="";anchorKind=anchorAccount?.isCredit == true ? "components" : "net";acceptEstimate=false}
        .onChange(of:anchorKind){_ in acceptEstimate=false}
        .onChange(of:transferID){_ in selected=[];redundantAdjustment=""}
        .onChange(of:selected){_ in redundantAdjustment=""}
        .confirmationDialog("Підтвердити зміни фінансової бази?",isPresented:$confirm){Button("Застосувати"){apply()}}
    }
    private var groupSection:some View {Section("Валютний переказ") {
        Picker("Переказ USD → UAH",selection:$transferID){Text("Обрати").tag("");ForEach(transfers){o in Text(o.date.formatted(date:.abbreviated,time:.shortened)+" · "+s.visibleMoney(o.sourceMinor ?? 0,"USD")).tag(o.id)}}
        if let t=transfer {Text("Призначення: "+s.accountName(t.destination));Text("Вибери лише банківські зарахування, які дійсно є частинами цього обміну, навіть якщо вони помилково на іншому рахунку. Усі ключі залишаться у переказі. Окремі комісії не видаляються автоматично.").font(.caption)}
    }}
    private var destinationSection:some View {Section("Рахунок") {Picker("Рахунок",selection:$destination){Text("Обрати").tag("");ForEach(banks){a in Text(a.name).tag(a.id)}}.accessibilityIdentifier("qa.reconcile.account")}}
    private var batchSection:some View {Section("Пакет імпорту") {Picker("Виписка",selection:$batch){Text("Обрати").tag("");ForEach(batches,id:\.self){id in Text(batchLabel(id)).tag(id)}};Text("Вибирай тільки рядки, належність яких підтверджена випискою. Пов’язані з платежами операції захищені.").font(.caption)}}
    private func batchLabel(_ id:String)->String {let rows=s.db.operations.filter{$0.importBatch==id};return (rows.map(\.date).min()?.formatted(date:.abbreviated,time:.omitted) ?? "Виписка")+" · \(rows.count) оп. · "+String(id.prefix(4))}
    private var selectionSection:some View {Section("Операції · \(selected.count)") {
        if mode=="move" {Button("Вибрати всі з пакета"){selected=Set(candidates.map(\.id))}}
        if mode=="group",!groupSuggestion.isEmpty {Button("Запропонована група · \(groupSuggestion.count) рядків"){selected=Set(groupSuggestion.map(\.id))};Text("Суми близькі до ручного переказу. Перевір усі зарахування перед підтвердженням.").font(.caption)}
        Button("Очистити вибір"){selected=[]}
        ForEach(candidates){o in Toggle(isOn:Binding(get:{selected.contains(o.id)},set:{if $0 {selected.insert(o.id)}else{selected.remove(o.id)}})){VStack(alignment:.leading){Text(o.note.isEmpty ? o.kind.title:finamiMerchantDisplay(o.note));Text(s.accountName(o.account)+" · "+o.date.formatted(date:.abbreviated,time:.shortened)+" · "+s.visibleMoney(o.signedNative)).font(.caption)}}}
    }}
    @ViewBuilder private var previewSection:some View {if let p=proposal {Section("Баланси до → після") {
        let old=FinamiLedgerIndex(operations:s.db.operations),new=FinamiLedgerIndex(operations:p)
        ForEach(s.db.accounts.filter{old.balance($0) != new.balance($0)}) {a in VStack(alignment:.leading){Text(a.name);Text(s.visibleMoney(old.balance(a),a.code)+" → "+s.visibleMoney(new.balance(a),a.code)).font(.caption)}}
        if mode=="group",let t=transfer,let grouped=p.first(where:{$0.id==t.id}) {
            LabeledContent("Фактичне зарахування",value:s.visibleMoney(grouped.destinationMinor ?? grouped.amount))
            if !adjustmentCandidates.isEmpty {
                Picker("Ручна різниця курсу",selection:$redundantAdjustment){Text("Залишити всі комісії").tag("");ForEach(adjustmentCandidates){o in Text("Вже враховано: "+s.visibleMoney(o.amount)+" · "+o.note).tag(o.id)}}
                Text("Вилучай ручну різницю лише якщо це та сама різниця, вже врахована у фактичному зарахуванні, а не окрема комісія біржі.").font(.caption)
            }
        }
        Button("Підтвердити звірку"){confirmedVersion=s.databaseVersion;confirm=true}
    }}}
    private var anchorSection:some View {Section("Контрольний баланс на дату") {
        DatePicker("Дата і час",selection:$anchorDate,in:...Date())
        if let a=anchorAccount {
            LabeledContent("Поточний чистий баланс Finami",value:a.hideAmounts == true ? "••••":s.visibleMoney(s.nativeBalance(a),a.code))
            if a.isCredit {
                LabeledContent("Кредитний ліміт",value:a.hideAmounts == true ? "••••":s.visibleMoney(a.limit,a.code))
                LabeledContent("Доступний кредит Finami",value:a.hideAmounts == true ? "••••":s.visibleMoney(s.unusedCredit(a),a.code))
            }
            Picker("Тип банківських даних",selection:$anchorKind) {
                Text("Чистий обліковий баланс").tag("net")
                if a.isCredit {Text("Власні кошти та використано").tag("components")}
                Text("Оцінка з доступних коштів").tag("estimate")
            }
            if anchorKind=="components" {
                FinamiField("Власні кошти, UAH",text:$ownText,keyboard:.decimalPad)
                FinamiField("Використано кредиту, UAH",text:$usedText,keyboard:.decimalPad)
            } else if anchorKind=="net" {FinamiField("Чистий залишок, UAH (борг зі знаком −)",text:$anchorText,keyboard:.numbersAndPunctuation)}
            FinamiField(anchorKind=="estimate" ? "Доступно в банку, UAH":"Доступно в банку (необов’язково)",text:$availableText,keyboard:.decimalPad)
            if anchorKind=="estimate" {
                Text("Доступні кошти можуть відрізнятися через холди. Це оцінка, не підтверджений обліковий баланс. Нуль доступного не визначає чистий борг.").font(.caption).foregroundStyle(.orange)
                Toggle("Приймаю оцінку як контрольну точку",isOn:$acceptEstimate)
            }
            if let net=anchorNet,let n=proposedOpening {
                let position=CardPosition(net:net,limit:a.limit)
                let historical=FinamiLedgerIndex(operations:s.historyForAccount(a.id),accounts:[a]).balanceAt(a,date:anchorDate)
                LabeledContent("Finami на вибрану дату",value:a.hideAmounts == true ? "••••":s.visibleMoney(historical))
                LabeledContent("Різниця (банк − Finami)",value:a.hideAmounts == true ? "••••":s.visibleMoney(net-historical))
                LabeledContent("Контрольний чистий баланс",value:a.hideAmounts == true ? "••••":s.visibleMoney(net))
                if a.isCredit {LabeledContent("Використано",value:a.hideAmounts == true ? "••••":s.visibleMoney(position.used));LabeledContent("Невикористаний ліміт",value:a.hideAmounts == true ? "••••":s.visibleMoney(position.unused))}
                if let available=bankMinor(availableText),available>=0 {LabeledContent("Різниця з доступним банку",value:a.hideAmounts == true ? "••••":s.visibleMoney(available-position.available))}
                LabeledContent("Нова база балансу",value:a.hideAmounts == true ? "••••":s.visibleMoney(n))
                Text("Підтверди після перевірки виписки. Історія залишається; операції після цієї дати змінюють баланс. Операції до контрольної дати не змінюють поточний баланс. Це не дохід і не витрата.").font(.caption)
                Button("Зберегти контрольний баланс"){confirmedVersion=s.databaseVersion;confirm=true}.accessibilityIdentifier("qa.reconcile.save")
            }
        }
    }}
    private func apply(){
        guard confirmedVersion==s.databaseVersion else {s.error="Дані змінилися. Перевір та підтвердь звірку повторно.";return}
        if mode=="anchor",let a=anchorAccount,let n=proposedOpening,let net=anchorNet {s.change{d in guard let i=d.accounts.firstIndex(where:{$0.id==a.id}) else{return};d.accounts[i].opening=n;d.accounts[i].reconciliationDate=anchorDate;d.accounts[i].reconciliationNet=net;d.accounts[i].reconciliationEstimated=(anchorKind=="estimate")
            if let available=bankMinor(availableText),available>=0 {var values=d.balanceObservations ?? [:];if values[a.id].map({$0.date<=anchorDate}) ?? true {values[a.id]=FinamiBalanceObservation(accountID:a.id,date:anchorDate,available:available,currency:a.code)};d.balanceObservations=values}
        };return}
        guard let p=proposal,let data=try? JSONEncoder().encode(FinamiBalanceUndo(before:s.db.operations,after:p)) else{return}
        if s.change({$0.operations=p;$0.reconciliationUndo=data}) {selected=[];transferID=""}
    }
    private func undoLast(){guard let data=s.db.reconciliationUndo,let undo=try? JSONDecoder().decode(FinamiBalanceUndo.self,from:data),let restored=undo.restore(current:s.db.operations) else{return};s.change{$0.operations=restored;$0.reconciliationUndo=nil}}
}

struct FinamiFXEditor:View {
    @EnvironmentObject private var s:Store
    @Environment(\.dismiss) private var dismiss
    @State private var source=""
    @State private var destination=""
    @State private var gross=""
    @State private var fee="0"
    @State private var feeMode="fixed"
    @State private var received=""
    @State private var date=Date()
    private var amounts:FinamiFXAmounts? {
        guard let g=bankMinor(gross),let r=bankMinor(received),let entered=bankMinor(fee) else{return nil}
        var f=entered
        if feeMode=="percent" {guard entered>=0,entered<10000 else{return nil};var value=Decimal(g)*Decimal(entered)/10000;var rounded=Decimal();NSDecimalRound(&rounded,&value,0,.plain);f=NSDecimalNumber(decimal:rounded).int64Value}
        return FinamiFXAmounts(grossUSD:g,feeUSD:f,receivedUAH:r)
    }
    private var draft:[Operation]? {guard let a=s.db.accounts.first(where:{$0.id==source}),let b=s.db.accounts.first(where:{$0.id==destination}) else{return nil};return amounts?.operations(source:a,destination:b,date:date)}
    var body:some View {Form {
        Section("Рахунки") {Picker("Звідки USD",selection:$source){Text("Обрати").tag("");ForEach(s.db.accounts.filter{$0.code=="USD"}){Text($0.name).tag($0.id)}};Picker("Куди UAH",selection:$destination){Text("Обрати").tag("");ForEach(s.db.accounts.filter{$0.code=="UAH"}){Text($0.name).tag($0.id)}};DatePicker("Дата і час",selection:$date,in:...Date())}
        Section("Суми") {FinamiField("Віддано USD разом з комісією",text:$gross,keyboard:.decimalPad);Picker("Тип комісії",selection:$feeMode){Text("USD").tag("fixed");Text("Відсоток").tag("percent")};FinamiField(feeMode=="fixed" ? "Комісія USD":"Комісія, %",text:$fee,keyboard:.decimalPad);FinamiField("Фактично отримано UAH",text:$received,keyboard:.decimalPad);if let a=amounts {LabeledContent("Комісія",value:s.visibleMoney(a.feeUSD,"USD"));LabeledContent("Чистий обмін",value:s.visibleMoney(a.netUSD,"USD"));LabeledContent("Фактичний курс",value:fxString(a.rate))}}
        Section {Text("Створює внутрішній переказ та, за потреби, окрему витрату комісії. Не створює зарплату повторно. Для вже імпортованих надходжень використовуй групову звірку.").font(.caption);Button("Записати обмін"){guard let d=draft else{return};if s.change({$0.operations.append(contentsOf:d)}){dismiss()}}.disabled(draft==nil)}
    }.navigationTitle("Обмін валют")}
}
