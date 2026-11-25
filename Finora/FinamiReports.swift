import SwiftUI

struct Reports: View {
    @EnvironmentObject var s: Store
    @State private var date = Date()
    @State private var settings = false
    private var prefs: AppearancePreferences { s.db.preferences ?? .init() }
    private var annual: Bool { prefs.reportsPeriod != "month" }
    private var selectedAccount: String { s.db.accounts.contains(where: { $0.id == prefs.reportsAccount }) ? (prefs.reportsAccount ?? "all") : "all" }
    private var showIncome: Bool { prefs.reportsShowIncome != false }
    private func binding<T>(_ key: WritableKeyPath<AppearancePreferences, T?>, _ fallback: T) -> Binding<T> {
        Binding(get: { (s.db.preferences ?? .init())[keyPath: key] ?? fallback }, set: { value in s.change { d in var p = d.preferences ?? .init(); p[keyPath: key] = value; d.preferences = p } })
    }
    private func hidden(_ id: String) -> Binding<Bool> {
        Binding(get: { s.privateAmounts || s.db.preferences?.reportsHiddenSections?.contains(id) == true }, set: { hide in
            guard !s.privateAmounts else { return }
            s.change { d in var p = d.preferences ?? .init(); var values = Set(p.reportsHiddenSections ?? []); if hide { values.insert(id) } else { values.remove(id) }; p.reportsHiddenSections = values.sorted(); d.preferences = p }
        })
    }
    private func panelTitle(_ date: Date) -> String {
        annual ? date.formatted(.dateTime.year().locale(Locale(identifier: "uk_UA"))) : date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "uk_UA"))).capitalized
    }
    private func shift(_ value: Int) {
        if let next = Calendar.current.date(byAdding: annual ? .year : .month, value: value, to: date) { date = next }
    }
    var body: some View {
        let snapshot = FinamiReportSnapshot(operations: s.db.operations, date: date, annual: annual, account: selectedAccount == "all" ? nil : selectedAccount)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                controls
                flow(snapshot)
                if prefs.reportsShowComparison != false { comparison(snapshot) }
                if annual && prefs.reportsShowChart != false && prefs.noCharts == false {
                    FinamiReportPanel(title: "Динаміка року", icon: "chart.bar.xaxis", tint: .blue, hidden: hidden("chart")) { AnnualCashFlowChart(points: chartPoints(snapshot)) }
                }
                if prefs.reportsShowCategories != false { categories(snapshot) }
                if prefs.reportsShowAccounts != false { accounts(snapshot) }
                if prefs.reportsShowMonths != false { timeline(snapshot) }
                if prefs.reportsShowReview != false { review(snapshot) }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Звіти")
        .toolbar {
            Button { s.change { d in var p = d.preferences ?? .init(); p.hideAmounts = !(p.hideAmounts ?? false); d.preferences = p } } label: { Image(systemName: s.privateAmounts ? "eye.slash" : "eye") }.accessibilityLabel("Приховати або показати всі суми")
            Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Налаштування звітів")
        }.sheet(isPresented: $settings) { NavigationStack { reportSettings } }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Період", selection: binding(\.reportsPeriod, "year")) { Text("Місяць").tag("month"); Text("Рік").tag("year") }.pickerStyle(.segmented)
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Попередній період")
                Spacer(minLength: 2); Text(panelTitle(date)).font(.title2.bold()).multilineTextAlignment(.center); Spacer(minLength: 2)
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Наступний період")
            }.buttonStyle(.plain)
            HStack {
                Picker("Рахунок", selection: Binding(get: { selectedAccount }, set: { binding(\.reportsAccount, "all").wrappedValue = $0 })) {
                    Text("Усі рахунки").tag("all")
                    ForEach(finamiOrderedAccounts(s.db.accounts)) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
                Spacer(minLength: 4)
                Button("Поточний період") { date = Date() }.font(.caption.weight(.medium))
            }
            Text("Суми в гривні за курсом, збереженим в операції. Перекази й основна сума кредиту не є доходами чи витратами.").font(.caption).foregroundStyle(.secondary)
        }.padding(14).modifier(FinamiCardStyle(tint: .teal))
    }
    private func flow(_ x: FinamiReportSnapshot) -> some View {
        FinamiReportPanel(title: "Підсумок", icon: "wallet.pass.fill", tint: .teal, hidden: hidden("flow")) {
            if showIncome { FinamiMetric(title: "Чистий потік", value: s.visibleMoney(x.totals.net), tint: x.totals.net >= 0 ? .green : .orange) }
            if showIncome { metric("Доходи", x.totals.income, .green, "arrow.down.left") }
            metric("Чисті витрати", x.totals.expense, .orange, "arrow.up.right")
            if x.totals.refunds != 0 { metric("Повернення покупок", x.totals.refunds, .blue, "arrow.uturn.backward") }
            Text("Операцій за період: \(x.totals.count)").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, _ value: Int64, _ tint: Color, _ icon: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FinamiIconTile(icon: icon, tint: tint, side: 34)
            FinamiMetric(title: title, value: s.visibleMoney(value), tint: tint)
        }.padding(10).background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
    private func comparison(_ x: FinamiReportSnapshot) -> some View {
        FinamiReportPanel(title: "Порівняння періодів", icon: "arrow.left.arrow.right", tint: .indigo, hidden: hidden("comparison")) {
            Text("Зіставлення з періодом: " + panelTitle(x.previousInterval.start)).font(.caption).foregroundStyle(.secondary)
            comparisonLine("Витрати", current: x.totals.expense, previous: x.previous.expense)
            if showIncome { comparisonLine("Доходи", current: x.totals.income, previous: x.previous.income); comparisonLine("Чистий потік", current: x.totals.net, previous: x.previous.net) }
            Text("Порівнюються цілі календарні періоди, навіть якщо поточний ще не завершився.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func comparisonLine(_ title: String, current: Int64, previous: Int64) -> some View {
        let difference = current - previous
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(s.visibleMoney(current)).font(.title3.bold()).monospacedDigit()
            Text("Було: " + s.visibleMoney(previous)).font(.caption).foregroundStyle(.secondary)
            Text("Зміна: " + (difference > 0 ? "+" : "") + s.visibleMoney(difference)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if previous > 0 && current >= 0 {
                let percent = Double(difference) / Double(previous)
                Text(percent.formatted(.percent.precision(.fractionLength(1))) + " відносно попереднього періоду").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(11).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
    private func categories(_ x: FinamiReportSnapshot) -> some View {
        FinamiReportPanel(title: "Категорії витрат", icon: "tag.fill", tint: .orange, hidden: hidden("categories")) {
            let rows = x.sortedCategories
            let limit = max(1, min(prefs.reportsCategoryLimit ?? 10, 100))
            if rows.isEmpty { Text("Немає витрат за період").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(rows.prefix(limit).enumerated()), id: \.element.key) { _, row in
                reportRow(row.key, amount: row.value, icon: finamiOperationIcon(Operation(kind: .expense, category: row.key)), tint: .orange)
            }
            if rows.count > limit { reportRow("Інші категорії", amount: rows.dropFirst(limit).reduce(0) { $0 + $1.value }, icon: "ellipsis", tint: .secondary) }
            Text("Повернення зменшують витрати відповідної категорії.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func accounts(_ x: FinamiReportSnapshot) -> some View {
        let ids = x.accounts.keys.filter { id in let t = x.accounts[id] ?? .init(); return t.expense != 0 || (showIncome && t.income != 0) }.sorted { a,b in
            let l = x.accounts[a]?.expense ?? 0, r = x.accounts[b]?.expense ?? 0; return l == r ? a < b : l > r
        }
        return FinamiReportPanel(title: "За рахунками", icon: "creditcard.fill", tint: .blue, hidden: hidden("accounts")) {
            if ids.isEmpty { Text("Немає доходів або витрат за рахунками").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(ids, id: \.self) { id in
                if let t = x.accounts[id] {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(s.accountName(id), systemImage: "wallet.pass").font(.subheadline.weight(.semibold))
                        Text("Витрати: " + s.visibleMoney(t.expense)).font(.subheadline)
                        if showIncome { Text("Доходи: " + s.visibleMoney(t.income)).font(.subheadline).foregroundStyle(.green) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    private func timeline(_ x: FinamiReportSnapshot) -> some View {
        FinamiReportPanel(title: annual ? "За місяцями" : "За днями", icon: "calendar", tint: .purple, hidden: hidden("months")) {
            if x.periods.isEmpty { Text("Немає записів за період").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(x.periods.keys.sorted(by: >), id: \.self) { day in
                if let t = x.periods[day] {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(annual ? day.formatted(.dateTime.month(.wide).locale(Locale(identifier: "uk_UA"))).capitalized : day.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA")))).font(.subheadline.weight(.semibold))
                        Text("Витрати: " + s.visibleMoney(t.expense)).font(.subheadline)
                        if showIncome { Text("Доходи: " + s.visibleMoney(t.income)).font(.subheadline).foregroundStyle(.green) }
                        Text("\(t.count) операцій").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    private func review(_ x: FinamiReportSnapshot) -> some View {
        FinamiReportPanel(title: "Якість обліку", icon: "checkmark.shield", tint: .teal, hidden: hidden("review")) {
            Text(x.totals.review == 0 ? "Немає операцій, що потребують уточнення" : "Потребують уточнення: \(x.totals.review)").font(.subheadline)
            Text("Неуточнені рухи не враховуються в доходах і витратах, крім підтверджених окремих комісій.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func reportRow(_ title: String, amount: Int64, icon: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FinamiIconTile(icon: icon, tint: tint, side: 36)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.medium)); Text(s.visibleMoney(amount)).font(.headline).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 4)
    }
    private func chartPoints(_ x: FinamiReportSnapshot) -> [CashFlowPoint] {
        (0..<12).flatMap { offset -> [CashFlowPoint] in
            guard let month = Calendar.current.date(byAdding: .month, value: offset, to: x.interval.start) else { return [] }
            let t = x.periods[month] ?? .init()
            let expense = CashFlowPoint(month: month, series: "Витрати", amount: Double(t.expense) / 100)
            return showIncome ? [CashFlowPoint(month: month, series: "Доходи", amount: Double(t.income) / 100), expense] : [expense]
        }
    }
    private var reportSettings: some View {
        Form {
            Section("Показники") {
                Toggle("Доходи та чистий потік", isOn: binding(\.reportsShowIncome, true))
                Toggle("Порівняння періодів", isOn: binding(\.reportsShowComparison, true))
                Toggle("Категорії витрат", isOn: binding(\.reportsShowCategories, true))
                Toggle("За рахунками", isOn: binding(\.reportsShowAccounts, true))
                Toggle("За місяцями / днями", isOn: binding(\.reportsShowMonths, true))
                Toggle("Якість обліку", isOn: binding(\.reportsShowReview, true))
                Toggle("Річна діаграма", isOn: binding(\.reportsShowChart, true))
                Text("Діаграма доступна лише коли глобальний режим без діаграм вимкнений.").font(.caption)
            }
            Section("Категорії") { Picker("Показати", selection: binding(\.reportsCategoryLimit, 10)) { Text("Топ 5").tag(5); Text("Топ 10").tag(10); Text("Топ 20").tag(20); Text("До 100").tag(100) } }
            Section("Приватність") {
                Toggle("Приховати всі суми", isOn: binding(\.hideAmounts, false))
                Button("Скинути приховування окремих блоків") { s.change { d in var p = d.preferences ?? .init(); p.reportsHiddenSections = []; d.preferences = p } }
            }
        }.navigationTitle("Налаштування звітів").toolbar { Button("Готово") { settings = false } }
    }
}
