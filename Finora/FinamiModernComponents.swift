import SwiftUI

struct FinamiPaymentGlyph: View {
    @EnvironmentObject private var s: Store
    var icon: String
    var tint: Color = .indigo
    var side: CGFloat = 42
    var body: some View {
        let black = s.db.preferences?.modernPaymentIcons != "color"
        RoundedRectangle(cornerRadius:12)
            .fill(black ? Color(red:0.035,green:0.035,blue:0.045) : tint.opacity(0.13))
            .overlay { Image(systemName:icon).font(.system(size:side*0.43,weight:.semibold)).foregroundStyle(black ? Color(red:0.88,green:0.73,blue:0.44) : tint) }
            .overlay { RoundedRectangle(cornerRadius:12).strokeBorder(black ? Color(red:0.82,green:0.66,blue:0.34).opacity(0.22) : tint.opacity(0.14),lineWidth:1) }
            .frame(width:side,height:side).accessibilityHidden(true)
    }
}
// Shared presentation for every calendar/payment list. Contract total is not the unpaid balance.
struct FinamiModernPaymentRow: View {
    @EnvironmentObject private var s: Store
    @Environment(\.finamiMask) private var blockMask
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var name: String
    var kind: String
    var date: Date
    var currency: String
    var due: Int64
    var total: Int64? = nil
    var monthly: Int64? = nil
    var remaining: Int64? = nil
    var status: String = "Очікує оплати"
    var showDate = true
    var showImage = true
    var showRemaining = false
    var masked = false
    private var hidden: Bool { masked || blockMask || s.privateAmounts }
    private var prefs: AppearancePreferences { s.db.preferences ?? .init() }
    private func value(_ amount:Int64)->String { hidden ? "••••" : s.visibleMoney(amount,currency) }
    private var glyph: String { kind == "Підписка" ? "repeat" : kind == "Розстрочка" ? "creditcard.fill" : "calendar.badge.clock" }
    private var labels: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(name).font(.subheadline.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
            if showDate { Text(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier:"uk_UA")))).font(.caption).foregroundStyle(.secondary) }
            if prefs.modernPaymentTotal != false, let total { Text("Загальна сума · " + value(total)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            if (showRemaining || prefs.modernPaymentRemaining == true), let remaining { Text("Залишок · " + value(remaining)).font(.caption).foregroundStyle(.secondary) }
            Text(status).font(.caption2.weight(.medium)).foregroundStyle(status == "Прострочено" ? Color.orange : Color.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var amounts: some View {
        VStack(alignment:.trailing,spacing:4) {
            if status != "Сплачено", prefs.modernPaymentMonthly != false, let monthly, monthly > 0 {
                Text("Щомісячний платіж").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text(value(monthly)).font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize(horizontal:false,vertical:true)
                if monthly != due { Text("До сплати · " + value(due)).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text(status == "Сплачено" ? "Сплачено" : "До сплати").font(.caption2).foregroundStyle(.secondary)
                Text(value(due)).font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    var body: some View {
        HStack(alignment:.top,spacing:10) {
            if showImage { FinamiPaymentGlyph(icon:glyph) }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:8) { labels; amounts.frame(maxWidth:.infinity,alignment:.trailing) }
            } else {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.top,spacing:8) { labels; amounts.frame(maxWidth:128,alignment:.trailing) }
                    VStack(alignment:.leading,spacing:8) { labels; amounts.frame(maxWidth:.infinity,alignment:.trailing) }
                }
            }
        }.padding(.vertical,6).frame(minHeight:44).contentShape(Rectangle())
    }
}
