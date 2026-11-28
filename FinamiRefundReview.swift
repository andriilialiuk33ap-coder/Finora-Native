import SwiftUI
struct FinamiRefundReview:View {
    @EnvironmentObject private var s:Store
    @State private var refundID=""
    @State private var purchaseID=""
    @State private var confirm=false
    private var refunds:[Operation] {s.db.operations.filter{finamiIsRefundCandidate($0)}.sorted{$0.date>$1.date}}
    private var refund:Operation? {refunds.first{$0.id==refundID}}
    private var purchases:[Operation] {guard let r=refund else{return []};return finamiRefundChoices(r,operations:s.db.operations,merchantKey:finamiMerchantKey)}
    var body:some View {List {
        Section("Повернення") {Picker("Операція",selection:$refundID){Text("Обрати").tag("");ForEach(refunds){r in Text(r.date.formatted(date:.abbreviated,time:.omitted)+" · "+s.visibleMoney(r.amount)+" · "+finamiMerchantDisplay(r.note)).tag(r.id)}};Text("Зв’язок змінює категорію та звіт, але не додає кошти повторно. Перевір покупку за випискою.").font(.caption)}
        if let r=refund {Section("Покупка") {
            if let id=r.refundOriginalID {Text("Пов’язано: "+(s.db.operations.first{$0.id==id}?.note ?? "Покупка"));Button("Відв’язати"){s.change{d in if let i=d.operations.firstIndex(where:{$0.id==r.id}){d.operations[i].refundOriginalID=nil}}}}
            else {Picker("Зіставити",selection:$purchaseID){Text("Обрати").tag("");ForEach(purchases){p in Text(p.date.formatted(date:.abbreviated,time:.omitted)+" · "+s.visibleMoney(p.amount)+" · "+p.category).tag(p.id)}};Button("Підтвердити повернення"){confirm=true}.disabled(purchaseID.isEmpty || !purchases.contains{$0.id==purchaseID});if purchases.isEmpty {Text("Не знайдено достатньо схожих покупок. Перевір рахунок та продавця.").font(.caption)}}
        }}
    }.navigationTitle("Повернення покупок").onChange(of:refundID){_ in purchaseID=""}.confirmationDialog("Пов’язати повернення з покупкою?",isPresented:$confirm){Button("Пов’язати"){link()}}}
    private func link(){guard let r=refund,let p=purchases.first(where:{$0.id==purchaseID}) else{return};if s.change({d in guard let i=d.operations.firstIndex(where:{$0.id==r.id}) else{return};d.operations[i].kind = .refund;d.operations[i].category=p.category;d.operations[i].refundOriginalID=p.id;d.operations[i].classificationReviewed=true}){purchaseID=""}}
}
