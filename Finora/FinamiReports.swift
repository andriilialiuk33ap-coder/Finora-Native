import SwiftUI

struct Reports: View {
    @EnvironmentObject var s: Store
    @State private var date = Date()
    @State private var settings = false
    @State private var accountSettings: FinamiAccountReportSelection?
    private var prefs: AppearancePreferences { s.db.preferences ?? .init() }
    private var annual: Bool { prefs.reportsPeriod != "month" }
    private var selectedAccount: String { s.db.accounts.contains(where: { $0.id == prefs.reportsAccount }) ? (prefs.reportsAccount ?? "all") : "all" }
    private var showIncome: Bool { prefs.reportsShowIncome != false }
    private var reportStyle: String { prefs.designReportStyle("flow") }
    private var chartsAllowed: Bool { !s.privateAmounts && prefs.noCharts == false && !s.db.accounts.contains { $0.hideAmounts == true && (selectedAccount == "all" || selectedAccount == $0.id) } }
    private func binding<T>(_ key: WritableKeyPath<AppearancePreferences, T?>, _ fallback: T) -> Binding<T> {
        Binding(get: { (s.db.preferences ?? .init())[keyPath: key] ?? fallback }, set: { value in s.changeAppearance { p in p[keyPath: key] = value } })
    }
    private func hidden(_ id: String) -> Binding<Bool> {
        Binding(get: { s.privateAmounts || s.db.preferences?.reportsHiddenSections?.contains(id) == true }, set: { hide in
            guard !s.privateAmounts else { return }
            s.changeAppearance { p in var values = Set(p.reportsHiddenSections ?? []); if hide { values.insert(id) } else { values.remove(id) }; p.reportsHiddenSections = values.sorted() }
        })
    }
    private func panelTitle(_ date: Date) -> String {
        annual ? date.formatted(.dateTime.year().locale(Locale(identifier: "uk_UA"))) : date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "uk_UA"))).capitalized
    }
    private func shift(_ value: Int) {
        if let next = Calendar.current.date(byAdding: annual ? .year : .month, value: value, to: date) { date = next }
    }
    var body: some View {
        let snapshot = s.reportSnapshot(date: date, annual: annual, account: selectedAccount == "all" ? nil : selectedAccount)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: (s.db.preferences ?? .init()).finamiSpacing) {
                controls
                ForEach(prefs.designOrderedReportBlocks, id: \.self) { key in
                    reportBlock(key, snapshot)
                }
            }.padding()
        }.background(finamiScreenBackground(s.db.preferences)).navigationTitle("Звіти")
        .toolbar {
            Button { s.changeAppearance { p in p.hideAmounts = !(p.hideAmounts ?? false) } } label: { Image(systemName: s.privateAmounts ? "eye.slash" : "eye") }.accessibilityLabel("Приховати або показати всі суми")
            Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Налаштування звітів")
        }.sheet(isPresented: $settings) { NavigationStack { reportSettings } }
        .sheet(item: $accountSettings) { selection in
            NavigationStack { FinamiAccountReportSettings(account: selection.id) }
        }
    }
    @ViewBuilder private func reportBlock(_ key: String, _ snapshot: FinamiReportSnapshot) -> some View {
        switch key {
        case "flow": flow(snapshot)
        case "comparison": if prefs.reportsShowComparison != false { comparison(snapshot) }
        case "chart":
            if prefs.reportsShowChart != false && chartsAllowed && (prefs.designChart("periods") != "None" || annual) {
                FinamiReportPanel(title: annual ? "Динаміка року" : "Динаміка місяця", icon: "chart.bar.xaxis", tint: .blue, hidden: hidden("chart")) {
                    if prefs.designChart("periods") == "None" { AnnualCashFlowChart(points: chartPoints(snapshot)) }
                    else { FinamiDesignPeriodChart(snapshot: snapshot, style: prefs.designChart("periods"), showIncome: showIncome) }
                }
            }
        case "categories": if prefs.reportsShowCategories != false { categories(snapshot) }
        case "accounts": if prefs.reportsShowAccounts != false { accounts(snapshot) }
        case "months": if prefs.reportsShowMonths != false { timeline(snapshot) }
        case "review": if prefs.reportsShowReview != false { review(snapshot) }
        default: EmptyView()
        }
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
            if showIncome && chartsAllowed && prefs.designChart("flow") == "Cash Flow Waterfall" { FinamiDesignWaterfall(totals: x.totals) }
            if showIncome { FinamiMetric(title: "Чистий потік", value: s.visibleMoney(x.totals.net), tint: x.totals.net >= 0 ? .green : .orange) }
            if showIncome { metric("Доходи", x.totals.income, .green, "arrow.down.left") }
            if prefs.reportsShowIncoming == false { Button("Показати надходження") { s.changeAppearance { $0.reportsShowIncoming = true } }.font(.caption) }
            if !showIncome { Button("Показати доходи") { s.changeAppearance { $0.reportsShowIncome = true } }.font(.caption) }
            if prefs.reportsShowIncoming != false { metric("Усі надходження", x.totals.incoming, .blue, "arrow.down.circle"); Text("Включно з поповненнями, переказами, поверненнями та кредитними надходженнями. Не є чистим доходом.").font(.caption).foregroundStyle(.secondary) }
            metric("Чисті витрати", x.totals.expense, .orange, "arrow.up.right")
            if x.totals.refunds != 0 { metric("Повернення покупок", x.totals.refunds, .blue, "arrow.uturn.backward") }
            movementLines(x.totals)
            Text("Операцій за період: \(x.totals.count)").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, _ value: Int64, _ tint: Color, _ icon: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if reportStyle != "minimalReports" { FinamiIconTile(icon: icon, tint: tint, side: reportStyle == "bankingPremium" ? 44 : 34) }
            FinamiMetric(title: title, value: s.visibleMoney(value), tint: tint)
        }.padding(reportStyle == "minimalReports" ? 4 : 10).background(tint.opacity(reportStyle == "bankingPremium" ? 0.13 : reportStyle == "minimalReports" ? 0 : 0.07), in: RoundedRectangle(cornerRadius: 14))
    }
    private func comparison(_ x: FinamiReportSnapshot) -> some View {
        let elapsed = prefs.reportsCompareElapsed != false
        let comparable = s.reportComparison(current: x.interval, previous: x.previousInterval, account: selectedAccount == "all" ? nil : selectedAccount, elapsed: elapsed)
        return FinamiReportPanel(title: "Порівняння періодів", icon: "arrow.left.arrow.right", tint: .indigo, hidden: hidden("comparison")) {
            Picker("Порівнювати", selection: binding(\.reportsCompareElapsed, true)) { Text("Однакові дні").tag(true); Text("Цілі періоди").tag(false) }.pickerStyle(.segmented)
            Text("Зіставлення з періодом: " + panelTitle(x.previousInterval.start)).font(.caption).foregroundStyle(.secondary)
            comparisonLine("Витрати", current: comparable.current.expense, previous: comparable.previous.expense)
            if showIncome { comparisonLine("Доходи", current: comparable.current.income, previous: comparable.previous.income); comparisonLine("Чистий потік", current: comparable.current.net, previous: comparable.previous.net) }
            if prefs.reportsShowIncoming != false { comparisonLine("Усі надходження", current: comparable.current.incoming, previous: comparable.previous.incoming) }
            Text(elapsed ? "Для незавершеного періоду зіставляється однакова кількість календарних днів (не довше попереднього періоду)." : "Порівнюються цілі календарні періоди.").font(.caption).foregroundStyle(.secondary)
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
            if chartsAllowed && prefs.designChart("categories") != "None" { FinamiDesignCategoryChart(values: x.categories, style: prefs.designChart("categories")) }
            if prefs.designReportStyle("categories") == "financePro", chartsAllowed, prefs.designChart("categories") == "None" { FinamiDesignCategoryChart(values: x.categories, style: "Donut") }
            if prefs.designReportStyle("categories") == "smartInsights", chartsAllowed, let first = rows.first, first.value > 0 { Text("Найбільша категорія: " + first.key).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
            if prefs.designReportStyle("categories") == "analyticsBento" {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))]) {
                    ForEach(Array(rows.prefix(limit).enumerated()), id: \.element.key) { _, row in
                        categoryLink(row.key, amount: row.value, snapshot: x).padding(8).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                ForEach(Array(rows.prefix(limit).enumerated()), id: \.element.key) { _, row in
                    categoryLink(row.key, amount: row.value, snapshot: x)
                }
            }
            if rows.count > limit { reportRow("Інші категорії", amount: rows.dropFirst(limit).reduce(0) { $0 + $1.value }, icon: "ellipsis", tint: .secondary) }
            Text("Повернення зменшують витрати відповідної категорії.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func categoryLink(_ category: String, amount: Int64, snapshot: FinamiReportSnapshot) -> some View {
        NavigationLink {
            FinamiReportCategoryOperations(category: category, interval: snapshot.interval, account: selectedAccount == "all" ? nil : selectedAccount)
        } label: { reportRow(category, amount: amount, icon: finamiOperationIcon(Operation(kind: .expense, category: category)), tint: .orange) }.buttonStyle(.plain)
    }
    private func movementLine(_ title: String, _ amount: Int64, tint: Color = .secondary, masked: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(masked ? "••••" : s.visibleMoney(amount)).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(tint)
        }
    }
    @ViewBuilder private func movementLines(_ t: FinamiReportTotals, masked: Bool = false) -> some View {
        if t.transfersIn != 0 { movementLine("Вхідні перекази / поповнення", t.transfersIn, tint: .blue, masked: masked) }
        if t.transfersOut != 0 { movementLine("Вихідні перекази / зняття", t.transfersOut, masked: masked) }
        if t.creditDraw != 0 { movementLine("Отримано кредиту", t.creditDraw, masked: masked) }
        if t.creditTopUp != 0 { movementLine("Поповнення кредитки", t.creditTopUp, masked: masked) }
        if t.creditRepayment != 0 { movementLine("Погашення кредиту", t.creditRepayment, masked: masked) }
        if t.unclassifiedIn != 0 { movementLine("Неуточнені надходження", t.unclassifiedIn, tint: .orange, masked: masked) }
        if t.unclassifiedOut != 0 { movementLine("Неуточнені списання", t.unclassifiedOut, tint: .orange, masked: masked) }
    }
    private func accounts(_ x: FinamiReportSnapshot) -> some View {
        let ids = x.accounts.keys.sorted { a,b in
            let l = x.accounts[a]?.expense ?? 0, r = x.accounts[b]?.expense ?? 0; return l == r ? a < b : l > r
        }
        return FinamiReportPanel(title: "За рахунками", icon: "creditcard.fill", tint: .blue, hidden: hidden("accounts")) {
            if ids.isEmpty { Text("Немає руху коштів за рахунками").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(ids, id: \.self) { id in
                if let t = x.accounts[id] {
                    let masked = s.db.accounts.first(where: { $0.id == id })?.hideAmounts == true
                    let fields = FinamiAccountReportField.selected(account: id, preferences: prefs.reportsAccountFields)
                        .filter { $0.isVisible(in: t, showIncome: showIncome) }
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Label(s.accountName(id), systemImage: "wallet.pass").font(.headline)
                            Spacer(minLength: 4)
                            Button { accountSettings = FinamiAccountReportSelection(id: id) } label: {
                                Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Показники звіту: \(s.accountName(id))")
                                .accessibilityIdentifier("qa.report.account.settings.\(id)")
                        }
                        if fields.isEmpty {
                            Text("Немає вибраних показників з даними").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(fields) { field in
                            if field == .review {
                                NavigationLink {
                                    FinamiReportReviewList(ids: x.reviewIDs, account: id, maskAmounts: masked)
                                } label: {
                                    Label("Уточнити операції (\(t.review))", systemImage: "checklist").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                                }.accessibilityIdentifier("qa.report.account.row.\(id).review")
                            } else if let amount = field.amount(t) {
                                movementLine(field.title, amount, tint: accountFieldTint(field, amount: amount), masked: masked)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier("qa.report.account.row.\(id).\(field.rawValue)")
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Повернення вже відняті від чистих витрат. Перекази, кредити й неуточнені рухи показано окремо; вони не є доходом.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func accountFieldTint(_ field: FinamiAccountReportField, amount: Int64) -> Color {
        switch field {
        case .income: return .green
        case .expense, .unclassifiedIn, .unclassifiedOut: return .orange
        case .refunds, .transfersIn: return .blue
        case .net: return amount >= 0 ? .green : .orange
        default: return .secondary
        }
    }
    private func timeline(_ x: FinamiReportSnapshot) -> some View {
        FinamiReportPanel(title: annual ? "За місяцями" : "За днями", icon: "calendar", tint: .purple, hidden: hidden("months")) {
            if x.periods.isEmpty { Text("Немає записів за період").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(x.periods.keys.sorted(by: >), id: \.self) { day in
                if let t = x.periods[day] {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(annual ? day.formatted(.dateTime.month(.wide).locale(Locale(identifier: "uk_UA"))).capitalized : day.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA")))).font(.subheadline.weight(.semibold))
                        Text("Чисті витрати: " + s.visibleMoney(t.expense)).font(.subheadline)
                        if showIncome { Text("Доходи: " + s.visibleMoney(t.income)).font(.subheadline).foregroundStyle(.green) }
                        movementLines(t)
                        if showIncome { movementLine("Чистий потік", t.net, tint: t.net >= 0 ? .green : .orange) }
                        Text("\(t.count) операцій").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    private func review(_ x: FinamiReportSnapshot) -> some View {
        FinamiReportPanel(title: "Якість обліку", icon: "checkmark.shield", tint: .teal, hidden: hidden("review")) {
            Text(x.totals.review == 0 ? "Немає операцій, що потребують уточнення" : "Потребують уточнення: \(x.totals.review)").font(.subheadline)
            if x.totals.review > 0 {
                NavigationLink { FinamiReportReviewList(ids: x.reviewIDs, account: nil, maskAmounts: false) } label: {
                    Label("Переглянути та уточнити", systemImage: "checklist").frame(minHeight: 44)
                }
            }
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
            Section("Дизайн блоків") {
                FinamiComponentStylePicker(component: "reports", title: "Загальний стиль")
                ForEach(prefs.designOrderedReportBlocks, id: \.self) { key in
                    VStack(alignment: .leading) {
                        Text(FinamiDesignPolicy.reportBlockTitle(key)).font(.headline)
                        Picker("Стиль", selection: Binding(get: { prefs.designReportBlockStyles?[key] ?? "" }, set: { v in s.changeAppearance { $0.setDesignReportStyle(v.isEmpty ? nil : v, block: key) } })) {
                            Text("Загальний").tag("")
                            ForEach(FinamiDesignPolicy.componentOptions["reports"] ?? [], id: \.self) { Text(FinamiDesignPolicy.styleTitle($0)).tag($0) }
                        }
                        Picker("Розмір", selection: Binding(get: { prefs.designSize(for: "report." + key) }, set: { v in s.changeAppearance { $0.setDesignSize(v, for: "report." + key) } })) { ForEach(FinamiDesignPolicy.componentSizes,id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    }
                }.onMove { from,to in var order = prefs.designOrderedReportBlocks; order.move(fromOffsets: from,toOffset:to); s.changeAppearance { $0.designReportOrder = order } }
                EditButton()
            }
            Section("Показники") {
                Toggle("Доходи та чистий потік", isOn: binding(\.reportsShowIncome, true))
                Toggle("Усі надходження", isOn: binding(\.reportsShowIncoming, true))
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
                Button("Скинути приховування окремих блоків") { s.changeAppearance { p in p.reportsHiddenSections = [] } }
            }
        }.navigationTitle("Налаштування звітів").toolbar { Button("Готово") { settings = false } }
    }
}

private struct FinamiAccountReportSelection: Identifiable { let id: String }

private struct FinamiAccountReportSettings: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    let account: String
    @State private var saveFailed = false
    private var chosen: [FinamiAccountReportField] {
        FinamiAccountReportField.selected(account: account, preferences: s.db.preferences?.reportsAccountFields)
    }
    private func save(_ fields: [FinamiAccountReportField]) {
        saveFailed = !s.changeAppearance { p in p.reportsAccountFields = FinamiAccountReportField.updating(p.reportsAccountFields, account: account, fields: fields) }
    }
    private func toggle(_ field: FinamiAccountReportField) {
        var values = chosen
        if values.contains(field) { values.removeAll { $0 == field } }
        else { values.append(field) }
        save(values)
    }
    var body: some View {
        Form {
            Section {
                Button("Компактний: витрати й доходи") { save(FinamiAccountReportField.compact) }
                    .accessibilityIdentifier("qa.report.fields.compact")
                Button("Показати всі показники") { save(FinamiAccountReportField.allCases) }
                    .accessibilityIdentifier("qa.report.fields.all")
            } header: { Text("Швидке налаштування") }
            Section {
                ForEach(FinamiAccountReportField.allCases) { field in
                    let enabled = chosen.contains(field)
                    Button { toggle(field) } label: {
                        HStack {
                            Text(field.title).foregroundStyle(Color.primary)
                            Spacer(minLength: 8)
                            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                                .font(.title3)
                                .accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(field.title)
                        .accessibilityValue(enabled ? "Увімкнено" : "Вимкнено")
                        .accessibilityIdentifier("qa.report.fields.toggle.\(field.rawValue)")
                }
                if saveFailed { Text("Не вдалося зберегти зміни. Попередній вибір залишено.").foregroundStyle(.orange) }
            } header: { Text("Показувати в картці") } footer: {
                Text("Зміни діють лише для цього рахунку й зберігаються автоматично. Нульові додаткові рухи не відображаються. Глобальне приховування доходів має пріоритет. Підсумки, баланс та операції не змінюються.")
            }
        }
        .navigationTitle(s.accountName(account))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}

// Live list of the selected report's unresolved entries, without changing balances.
private struct FinamiReportReviewList: View {
    @EnvironmentObject private var s: Store
    let ids: [String]
    let account: String?
    let maskAmounts: Bool
    @State private var edited: Operation?
    private var entries: [Operation] {
        let selected = Set(ids)
        return s.db.operations.filter { selected.contains($0.id) && $0.kind.needsReview && (account == nil || $0.account == account) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            Section { Text("Оберіть операцію та уточніть її тип. Дохід — лише справжнє надходження, а не переказ власних коштів або кредит.").font(.caption) }
            Section {
                if entries.isEmpty { Text("Усі операції уточнено").foregroundStyle(.secondary) }
                ForEach(entries) { o in
                    Button { edited = o } label: {
                        OperationRow(o: o).environment(\.finamiMask, maskAmounts || s.db.accounts.first(where: { $0.id == o.account })?.hideAmounts == true)
                    }.buttonStyle(.plain)
                }
            }
        }.navigationTitle("Уточнення операцій")
            .sheet(item: $edited) { OpEditor(original: $0) }
    }
}

private struct FinamiReportCategoryOperations: View {
    @EnvironmentObject private var s: Store
    let category: String
    let interval: DateInterval
    let account: String?
    @State private var selected: Operation?
    private var operations: [Operation] {
        s.db.operations.filter { o in
            o.date >= interval.start && o.date < interval.end && o.expenseValue != 0 && o.expenseGroup == category && (account == nil || o.account == account || (o.kind == .transfer && o.destination == account))
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        List(operations) { o in Button { selected = o } label: { OperationRow(o: o) }.buttonStyle(.plain) }.navigationTitle(category).sheet(item: $selected) { OpEditor(original: $0) }
    }
}
