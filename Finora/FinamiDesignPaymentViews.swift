import SwiftUI
import UIKit

struct FinamiDesignSizePicker: View {
    @EnvironmentObject private var s: Store
    var component: String
    var body: some View {
        Picker("Розмір · " + FinamiDesignPolicy.componentTitle(component), selection: Binding(get: { (s.db.preferences ?? .init()).designSize(for: component) }, set: { v in s.changeAppearance { $0.setDesignSize(v, for: component) } })) {
            ForEach(FinamiDesignPolicy.componentSizes, id: \.self) { Text($0).tag($0) }
        }
    }
}
struct FinamiInstallmentDesign: View {
    @EnvironmentObject private var s: Store
    @Environment(\.finamiMask) private var masked
    var obligation: Obligation
    private func visible(_ amount: Int64) -> String { masked ? "••••" : s.visibleMoney(amount) }
    var body: some View {
        let p = s.db.preferences ?? .init()
        let pro = p.designStyle(for: "installments") == "timelineProgressPro"
        let compact = p.designSize(for: "installments") == "S"
        VStack(alignment: .leading, spacing: compact ? 4 : 9) {
            if let progress = FinamiDesignPolicy.fraction(obligation.paid, obligation.target, masked: s.privateAmounts || masked) {
                HStack(spacing: 10) {
                    if pro && !compact {
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                            Circle().trim(from: 0, to: CGFloat(progress)).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                            Text(progress.formatted(.percent.precision(.fractionLength(0)))).font(.caption2.bold())
                        }.frame(width: 52, height: 52)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress).tint(.accentColor)
                        if let schedule = obligation.importedSchedule, !schedule.isEmpty, !compact {
                            let rows = Array(schedule.sorted { $0.date < $1.date }.prefix(24))
                            HStack(spacing: 2) { ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                let matched = (s.db.paidRecords ?? []).contains { $0.paymentID == obligation.id && $0.amount >= row.amount && Calendar.current.isDate($0.scheduledDate, inSameDayAs: row.date) }
                                Capsule().fill(matched ? Color.green : Color.secondary.opacity(0.25)).frame(height: 5)
                            } }
                            Text("Імпортований графік · підтверджені оплати зеленим").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !compact {
                LabeledContent("Щомісяця", value: visible(obligation.monthly)).font(.caption)
                LabeledContent("Наступний платіж", value: visible(obligation.nextCharge)).font(.caption)
            }
            if obligation.remaining > 0 && Calendar.current.startOfDay(for: obligation.due) < Calendar.current.startOfDay(for: Date()) { Text("Прострочено").font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct FinamiUpcomingDesign: View {
    @EnvironmentObject private var s: Store
    @Environment(\.finamiMask) private var masked
    var item: DashboardItem
    var open: (FinamiPayment) -> Void
    private var p: AppearancePreferences { s.db.preferences ?? .init() }
    private var size: DashboardSize { switch p.componentSizes?["upcoming"] { case "S": return .small; case "M": return .medium; case "L": return .large; default: return item.size } }
    private func amount(_ v: Int64, _ c: String) -> String { masked ? "••••" : s.visibleMoney(v,c) }
    var body: some View {
        let style = p.designStyle(for: "upcoming") ?? "original"
        let count = size == .small || style == "original" ? 1 : max(1, min(10, p.designUpcomingCount ?? 3))
        let payments = Array(s.upcomingPayments.prefix(count))
        VStack(alignment: .leading, spacing: 10) {
            if payments.isEmpty { Text("Немає запланованих платежів").font(.caption).foregroundStyle(.secondary) }
            if style == "bankingPro" && size != .small && p.designShowsUpcoming("month") && p.designShowsUpcoming("amount") {
                ForEach(["UAH", "USD"], id: \.self) { code in LabeledContent("До кінця місяця · " + code, value: (p.designHiddenSubscriptions ?? []).isEmpty ? amount(s.scheduledThisMonth(currency: code), code) : "••••").font(.caption) }
            }
            ForEach(payments) { payment in
                Button { open(payment) } label: {
                    if (style == "original" || (style == "paymentFocus" && payment.id == payments.first?.id)) && p.designUpcomingFields == nil && item.showPaymentNames != false && !(p.designHiddenSubscriptions ?? []).contains(payment.id) {
                        FinamiPaymentCard(payment: payment, showRemaining: item.showPaymentRemaining ?? true, showDate: item.showPaymentDate ?? true, showImage: item.showPaymentImage ?? true, dashboardSize: size)
                    } else {
                        HStack(alignment: .center, spacing: 8) {
                            if p.designShowsUpcoming("date") && item.showPaymentDate != false && style == "paymentTimeline" { VStack { Text(payment.date.formatted(.dateTime.day())).font(.title3.bold()); Text(payment.date.formatted(.dateTime.month(.abbreviated))).font(.caption2) }.frame(minWidth: 38) }
                            else if p.designShowsUpcoming("image") && item.showPaymentImage != false {
                                if let data = s.db.paymentPhotos?[payment.id], let image = FinamiImageCache.shared.image(data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 36,height: 36).clipShape(RoundedRectangle(cornerRadius: 8)) }
                                else { FinamiPaymentGlyph(icon: payment.subscription ? "repeat" : "creditcard.fill", side: 36) }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                if p.designShowsUpcoming("name") && item.showPaymentNames != false { Text(payment.name).font(.subheadline.bold()) }
                                if p.designShowsUpcoming("kind") { Text(payment.kind).font(.caption) }
                                if p.designShowsUpcoming("date") && style != "paymentTimeline" && item.showPaymentDate != false { Text(payment.date.formatted(date: .abbreviated,time: .omitted)).font(.caption) }
                                if p.designShowsUpcoming("overdue") && payment.overdue { Text("Прострочено").font(.caption2).foregroundStyle(.orange) }
                                if p.designShowsUpcoming("days") && !payment.overdue { Text("Днів: " + String(max(0,Calendar.current.dateComponents([.day],from: Calendar.current.startOfDay(for: Date()),to: Calendar.current.startOfDay(for: payment.date)).day ?? 0))).font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 2)
                            if p.designShowsUpcoming("amount") { Text((p.designHiddenSubscriptions ?? []).contains(payment.id) ? "••••" : amount(payment.amount,payment.currency)).font(style == "paymentFocus" && payment.id == payments.first?.id ? .title3.bold() : .subheadline.bold()).monospacedDigit() }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(style == "paymentFocus" && payment.id == payments.first?.id ? 14 : 8).background(Color.accentColor.opacity(style == "paymentFocus" && payment.id == payments.first?.id ? 0.13 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}
struct FinamiSubscriptionDesign: View {
    @EnvironmentObject private var s: Store
    var record: SubscriptionRecord
    var collapsed: Bool
    private var p: AppearancePreferences { s.db.preferences ?? .init() }
    private var masked: Bool { s.privateAmounts || (p.designHiddenSubscriptions ?? []).contains(record.id) }
    private func money(_ v: Int64) -> String { masked ? "••••" : s.visibleMoney(v,record.currency) }
    private var brand: (String, Color) {
        let n = record.name.lowercased()
        if n.contains("netflix") { return ("N", .red) }; if n.contains("youtube") { return ("▶", .red) }; if n.contains("spotify") { return ("≋", .green) }; if n.contains("icloud") { return ("☁", .blue) }; return ("", .purple)
    }
    var body: some View {
        let style = p.designStyle(for: "subscriptions") ?? "original"
        let compact = style == "compactList" || p.designSize(for: "subscriptions") == "S"
        let tint = finamiDesignAccent(p.designSubscriptionColors?[record.id]) ?? brand.1
        let custom = p.designSubscriptionIcons?[record.id] ?? "auto"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let data = s.db.paymentPhotos?[record.id], let image = FinamiImageCache.shared.image(data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 34,height: 34).clipShape(RoundedRectangle(cornerRadius: 8)) }
                else if custom != "auto" { FinamiIconTile(icon: custom, tint: tint, side: compact ? 30 : 40) }
                else if !brand.0.isEmpty { Text(brand.0).font(.title2.bold()).foregroundStyle(tint).frame(width: compact ? 30 : 40, height: compact ? 30 : 40).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)) }
                else { FinamiIconTile(icon: "repeat", tint: tint, side: compact ? 30 : 40) }
                VStack(alignment: .leading) { Text(record.name).font(.subheadline.bold()); if !collapsed { Text(record.active ? record.next.formatted(date:.abbreviated,time:.omitted) : "Призупинено").font(.caption) } }
                Spacer(minLength: 4)
                Text(money(record.amount)).font(.subheadline.bold()).monospacedDigit()
            }
            if !collapsed && !compact {
                Text(record.period.rawValue + (record.automatic ? " · Автосписання" : "")).font(.caption).foregroundStyle(.secondary)
                if style == "premiumCards" || style == "subscriptionPro" {
                    LabeledContent("Місячна оцінка", value: money(FinamiDesignPolicy.safeMinor(Double(record.amount)*FinamiDesignPolicy.annualFactor(record.period.rawValue)/12))).font(.caption)
                    LabeledContent("Річна оцінка", value: money(FinamiDesignPolicy.safeMinor(Double(record.amount)*FinamiDesignPolicy.annualFactor(record.period.rawValue)))).font(.caption)
                }
                if style == "billingCycle" && record.active, let start = Calendar.current.date(byAdding: record.period.component, value: -record.period.step, to: record.next), record.next > start {
                    ProgressView(value: max(0,min(1,Date().timeIntervalSince(start)/record.next.timeIntervalSince(start)))).tint(tint)
                    Text("Днів до оплати: " + String(max(0,Calendar.current.dateComponents([.day],from: Calendar.current.startOfDay(for: Date()),to: Calendar.current.startOfDay(for: record.next)).day ?? 0))).font(.caption)
                }
                if p.designSize(for: "subscriptions") == "L" || style == "subscriptionPro" { Text("Записів історії: \(record.payments.count)").font(.caption) }
            }
        }.padding(style == "premiumCards" ? 10 : 2).background(style == "premiumCards" ? tint.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FinamiDesignKeyboard: View {
    @Binding var amount: String
    var haptics: Bool = true
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
            ForEach(["1","2","3","4","5","6","7","8","9",",","0","⌫"], id: \.self) { key in
                Button { if haptics { UISelectionFeedbackGenerator().selectionChanged() }; if key == "⌫" { if !amount.isEmpty { amount.removeLast() } } else if key == "," { if !amount.contains(",") && !amount.contains(".") { amount += amount.isEmpty ? "0," : "," } } else if amount.count < 18 { amount += key } } label: {
                    Text(key).font(.title3.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44).background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }
}
