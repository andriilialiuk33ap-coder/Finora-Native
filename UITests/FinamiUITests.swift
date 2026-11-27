import XCTest

final class FinamiUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--finami-qa", "--finami-qa-reset"]
        let fixtures = ["testHomeReviewOpensMatchingOperations":"--finami-qa-home-review-fixture",
                        "testAllUpcomingPaymentsAndArchive":"--finami-qa-upcoming-fixture",
                        "testAccountReportFieldsIndependentAndPersist":"--finami-qa-reports-fixture",
                        "testCompactAccountGridAlignmentAndDetails":"--finami-qa-design-fixture",
                        "testBalanceReconciliationPersists":"--finami-qa-design-fixture",
                        "testInstallmentPaidFromSelectedAccount":"--finami-qa-payment-fixture",
                        "testInstallmentCollapsePersists":"--finami-qa-payment-fixture",
                        "testExistingOperationLinksToInstallment":"--finami-qa-link-fixture",
                        "testRecurringSuggestionCreatesSubscription":"--finami-qa-recurring-fixture"]
        if let fixture = fixtures.first(where: { name.contains($0.key) })?.value { app.launchArguments.append(fixture) }
        app.launch()
        visible(tabButton("Головна"))
    }
    private func tabButton(_ name: String) -> XCUIElement {
        let names = ["Головна", "Операції", "Рахунки", "Звіти", "Ще"]
        guard let index = names.firstIndex(of: name) else { return app.buttons[name] }
        return app.buttons["qa.tab.\(index)"]
    }
    private func visible(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing: \(element)", file: file, line: line)
    }
    private func awaitValue(_ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        // On a busy CI runner a single accessibility snapshot can take over 15 seconds.
        // Poll the actual value; do not equate a waiter's timeout with an incorrect value.
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        var observed: String?
        repeat {
            if element.exists {
                observed = element.value as? String
                if observed == value { return }
            }
            if ProcessInfo.processInfo.systemUptime < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        } while ProcessInfo.processInfo.systemUptime < deadline
        XCTFail("Expected \(value), got \(String(describing: observed))", file: file, line: line)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHomeQuickActionsOpenEditor() {
        for kind in ["expense", "income", "transfer"] {
            let tile = app.buttons["qa.home.quick." + kind]
            for _ in 0..<5 { if tile.exists && tile.isHittable { break }; app.swipeUp() }
            visible(tile)
            XCTAssertTrue(tile.isHittable)
            tile.tap()
            visible(app.navigationBars["Операція"])
            let cancel = app.buttons["Скасувати"].firstMatch
            visible(cancel); cancel.tap()
        }
    }
    // Use short, scoped gestures and search in both directions. A return from a
    // destination can leave a menu row just above or below the viewport.
    private func revealNextMenuItem(_ item: XCUIElement, in menu: XCUIElement) {
        func ready() -> Bool { item.exists && item.isHittable }
        func step(up: Bool) {
            let start = menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.72 : 0.32))
            let end = menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.32 : 0.72))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        // Try the direction indicated by the accessibility frame before scanning.
        if item.exists && !ready() {
            let frame = item.frame
            if !frame.isEmpty && !frame.isInfinite {
                step(up: frame.midY > menu.frame.midY)
            }
        }
        for up in [false, true, false] {
            for _ in 0..<12 {
                if ready() { return }
                step(up: up)
            }
        }
        if !ready() {
            capture("next-menu-missing-" + item.identifier)
            let details = XCTAttachment(string: app.debugDescription)
            details.name = "next-menu-accessibility-tree"
            details.lifetime = .keepAlways
            add(details)
        }
        XCTAssertTrue(ready(), "Menu item not reachable: \(item)")
    }
    func testNextScreensOpen() {
        tabButton("Ще").tap()
        let root = app.navigationBars["Ще"]
        for (identifier,title) in [("qa.next.review","Перевірка операцій"),("qa.next.insights","Фінансові підсумки"),("qa.next.usdt","Журнал USDT")] {
            visible(root)
            // Some iOS accessibility snapshots omit a ScrollView's custom identifier.
            // The verified root has a single scrolling menu, so keep a structural fallback.
            let identifiedMenu = app.scrollViews["qa.more.scroll"]
            let menu = identifiedMenu.exists ? identifiedMenu : app.scrollViews.firstMatch
            visible(menu)
            let item = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            revealNextMenuItem(item, in: menu)
            item.tap()
            let destination = app.navigationBars[title]
            visible(destination); capture(identifier)
            let back = destination.buttons.firstMatch
            visible(back); back.tap()
            visible(root); visible(menu)
        }
    }
    func testCompactAccountGridAlignmentAndDetails() {
        visible(tabButton("Рахунки"));tabButton("Рахунки").tap()
        let credit=app.buttons["qa.account.compact.qa-design-credit"]
        let debit=app.buttons["qa.account.compact.qa-design-debit"]
        for _ in 0..<10 { if credit.exists && credit.isHittable && debit.exists && debit.isHittable { break }; app.swipeUp() }
        visible(credit);visible(debit)
        XCTAssertEqual(credit.frame.minY,debit.frame.minY,accuracy:2)
        XCTAssertEqual(credit.frame.height,debit.frame.height,accuracy:2)
        capture("design-grid-aligned")
        credit.tap();visible(app.navigationBars["Деталі рахунку"])
        app.navigationBars.buttons["Готово"].tap()
        let layout=app.segmentedControls["qa.account.layout"]
        for _ in 0..<8 { if layout.exists && layout.isHittable { break }; app.swipeDown() }
        visible(layout);layout.buttons["Список"].tap()
        visible(credit);visible(debit)
        XCTAssertEqual(credit.frame.minX,debit.frame.minX,accuracy:2)
        XCTAssertGreaterThan(debit.frame.minY,credit.frame.minY)
        capture("design-list")
    }
    func testAlternateHomeCanBeEnabledAndRestored() {
        let summary = app.staticTexts["qa.home.simple.summary"]
        XCTAssertFalse(summary.exists)
        func selectLayout(_ title: String) {
            tabButton("Ще").tap()
            let design = app.descendants(matching:.any).matching(identifier:"qa.quick.design").firstMatch
            for _ in 0..<8 { if design.exists && design.isHittable { break }; app.swipeDown() }
            visible(design); design.tap()
            let picker = app.segmentedControls["qa.home.layout"]
            visible(picker); visible(picker.buttons[title]); picker.buttons[title].tap()
            app.navigationBars.buttons.firstMatch.tap()
            tabButton("Головна").tap()
        }
        selectLayout("Спрощена")
        visible(summary)
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch()
        tabButton("Головна").tap(); visible(summary)
        selectLayout("Поточна")
        let gone = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: summary)], timeout: 30)
        XCTAssertEqual(gone, .completed)
    }
    func testAllFiveTabsOpen() {
        for title in ["Головна", "Операції", "Рахунки", "Звіти", "Ще"] {
            let tab = tabButton(title); visible(tab); tab.tap()
            visible(app.navigationBars[title]); capture(title)
        }
    }
    func testCollapsedDashboardPreviewPersistsAndRespectsPrivacy() {
        let open = app.buttons["Згорнути Найближчі платежі"]
        for _ in 0..<8 { if open.exists && open.isHittable { break }; app.swipeUp() }
        visible(open); open.tap()
        let collapsed = app.buttons["qa.dashboard.collapsed.obligations"]
        visible(collapsed)
        XCTAssertEqual(collapsed.value as? String,"Немає активних платежів")
        XCTAssertGreaterThanOrEqual(collapsed.frame.height,44)
        app.buttons["Приховати або показати суми"].tap()
        awaitValue(collapsed,"Суми приховано")
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch()
        for _ in 0..<8 { if collapsed.exists && collapsed.isHittable { break }; app.swipeUp() }
        visible(collapsed); awaitValue(collapsed,"Суми приховано")
        capture("collapsed-dashboard-privacy")
        collapsed.tap();visible(open)
    }
    func testDashboardSizeChangesAndPersists() {
        let tile = app.descendants(matching: .any).matching(identifier: "qa.dashboard.tile.ownFunds").firstMatch
        visible(tile)
        let largeHeight = tile.frame.height
        func changeSize(_ value: String) {
            app.buttons["Налаштувати блоки"].tap()
            let picker = app.segmentedControls["qa.dashboard.size.ownFunds"]
            for _ in 0..<16 { if picker.exists && picker.isHittable { break }; app.swipeUp() }
            visible(picker); let button = picker.buttons[value]; visible(button); button.tap()
            app.navigationBars.buttons["Готово"].tap()
            visible(tile)
        }
        changeSize("Компактний"); let small = tile.frame.height; capture("small")
        changeSize("Середній"); let medium = tile.frame.height; capture("medium")
        XCTAssertLessThan(small, medium); XCTAssertLessThan(medium, largeHeight)
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch(); visible(tile)
        XCTAssertEqual(tile.frame.height, medium, accuracy: 2)
    }
    func testIndependentAccountPrivacyAndLayout() {
        tabButton("Рахунки").tap()
        let own = app.buttons["Приховати власний баланс"]; visible(own); own.tap()
        visible(app.buttons["Показати власний баланс"])
        visible(app.buttons["Приховати кредитний баланс"])
        app.buttons["Вигляд балансу"].tap(); app.buttons["Один спільний блок"].tap()
        visible(app.buttons["Показати власний баланс"]); capture("accountPrivacy")
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch(); visible(tabButton("Рахунки")); tabButton("Рахунки").tap()
        visible(app.buttons["Показати власний баланс"]); visible(app.buttons["Приховати кредитний баланс"])
    }
    func testRealVisionOCRPopulatesInstallmentFields() {
        let scan = app.buttons["qa.home.scan"]
        visible(scan); XCTAssertTrue(scan.isHittable, "Home scan button must not be covered by navigation")
        scan.tap(); visible(app.navigationBars["Finami Scan"])
        let fixture = app.buttons["qa.scan.fixture.installment"]
        for _ in 0..<8 { if fixture.exists && fixture.isHittable { break }; app.swipeUp() }
        visible(fixture); XCTAssertTrue(fixture.isHittable); fixture.tap()
        let review = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "qa.scan.review.")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 45)); review.tap()
        visible(app.navigationBars["Перевірка розстрочки"])
        let fields = [("Загальний кредит", "30000.00"), ("Поточний залишок", "15000.00"), ("Щомісячний платіж", "2500.00")]
        for (label, expected) in fields {
            let field = app.textFields[label]
            for _ in 0..<15 { if field.exists && field.isHittable { break }; app.swipeUp() }
            visible(field); XCTAssertEqual(field.value as? String, expected)
        }
        capture("ocr-populated")
    }
    func testAllUpcomingPaymentsAndArchive() {
        let all = app.descendants(matching: .any).matching(identifier: "qa.upcoming.all.all").firstMatch
        for _ in 0..<10 { if all.exists && all.isHittable { break }; app.swipeUp() }
        visible(all); all.tap(); visible(app.navigationBars["Усі платежі"])
        let sixth = app.buttons["qa.upcoming.row.qa-upcoming-6"]
        for _ in 0..<8 { if sixth.exists && sixth.isHittable { break }; app.swipeUp() }
        visible(sixth); sixth.swipeLeft()
        let remove = app.buttons["Видалити"]; visible(remove); remove.tap()
        let confirm = app.buttons["Видалити в архів"]; visible(confirm); confirm.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sixth)], timeout: 8), .completed)
        visible(app.staticTexts["Усього: 5"])
        capture("upcoming-all-and-archive")
    }
    func testHomeReviewOpensMatchingOperations() {
        let open = app.descendants(matching: .any).matching(identifier: "qa.dashboard.review.open").firstMatch
        visible(open); XCTAssertEqual(open.value as? String, "2"); open.tap()
        visible(app.navigationBars["Уточнення операцій"])
        let credit = app.buttons["qa.review.operation.qa-review-in"]
        let debit = app.buttons["qa.review.operation.qa-review-out"]
        visible(credit); visible(debit)
        XCTAssertFalse(app.buttons["qa.review.operation.qa-reviewed"].exists)
        XCTAssertFalse(app.buttons["qa.review.operation.qa-review-previous"].exists)
        credit.tap(); visible(app.navigationBars["Операція"])
        capture("home-review-editor")
    }
    func testImportHubOpensAndShowsReview() {
        tabButton("Ще").tap()
        let hub = app.descendants(matching: .any).matching(identifier: "qa.smart.hub").firstMatch
        for _ in 0..<12 { if hub.exists && hub.isHittable { break }; app.swipeUp() }
        visible(hub); hub.tap()
        visible(app.navigationBars["Імпорт та експорт"])
        visible(app.staticTexts["Скриншоти розстрочок"])
        capture("import-hub")
    }
    func testExportAndRulesScreensOpen() {
        tabButton("Ще").tap()
        let hub = app.descendants(matching:.any).matching(identifier:"qa.smart.hub").firstMatch
        for _ in 0..<12 { if hub.exists && hub.isHittable { break }; app.swipeUp() }
        visible(hub);hub.tap();visible(app.navigationBars["Імпорт та експорт"])
        let export = app.staticTexts["PDF, Excel, CSV, календар"].firstMatch
        for _ in 0..<10 { if export.exists && export.isHittable { break }; app.swipeUp() }
        visible(export);export.tap();visible(app.navigationBars["Експорт звітів"])
        visible(app.staticTexts["Показувати суми"]);capture("export-privacy")
        app.navigationBars.buttons.firstMatch.tap()
        let rules=app.staticTexts["Правила категоризації"].firstMatch
        for _ in 0..<10 { if rules.exists && rules.isHittable { break }; app.swipeUp() }
        visible(rules);rules.tap();visible(app.navigationBars["Правила категорій"])
        let install=app.buttons["Додати погоджений набір категорій і правил"]
        visible(install);install.tap();capture("category-rules")
    }
    func testDiagnosticsRunsLocalParser() {
        tabButton("Ще").tap()
        let diagnostics = app.descendants(matching: .any).matching(identifier: "qa.smart.diagnostics").firstMatch
        for _ in 0..<12 { if diagnostics.exists && diagnostics.isHittable { break }; app.swipeUp() }
        visible(diagnostics); diagnostics.tap()
        visible(app.navigationBars["Діагностика"])
        let test = app.buttons["qa.diagnostics.run"]
        for _ in 0..<12 { if test.exists && test.isHittable { break }; app.swipeUp() }
        visible(test)
        let status = app.staticTexts["qa.diagnostics.parser"]
        visible(status); XCTAssertEqual(status.label, "Парсер: Не перевірено")
        test.tap()
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Парсер: Тест пройдено"), object: status)], timeout: 15)
        XCTAssertEqual(result, .completed, "Parser result: \(status.label)")
        capture("diagnostics")
    }
    func testAccountReportFieldsIndependentAndPersist() {
        visible(tabButton("Звіти")); tabButton("Звіти").tap()
        func openSettings(_ account: String) {
            let button = app.buttons["qa.report.account.settings." + account]
            for _ in 0..<16 { if button.exists && button.isHittable { break }; app.swipeUp() }
            visible(button); button.tap()
        }
        openSettings("qa-pumb")
        let compact = app.buttons["qa.report.fields.compact"]
        visible(compact); compact.tap()
        let income = app.buttons["qa.report.fields.toggle.income"]
        visible(income); awaitValue(income, "Увімкнено")
        income.tap(); awaitValue(income, "Вимкнено")
        income.tap(); awaitValue(income, "Увімкнено")
        income.tap(); awaitValue(income, "Вимкнено")
        app.navigationBars.buttons["Готово"].tap()
        let expense = app.descendants(matching: .any).matching(identifier: "qa.report.account.row.qa-pumb.expense").firstMatch
        visible(expense)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "qa.report.account.row.qa-pumb.income").firstMatch.exists)
        capture("compact-account-report")
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch()
        visible(tabButton("Звіти")); tabButton("Звіти").tap(); openSettings("qa-pumb")
        visible(income); awaitValue(income, "Вимкнено")
        app.navigationBars.buttons["Готово"].tap()
        openSettings("qa-otp"); visible(income); awaitValue(income, "Увімкнено")
        app.navigationBars.buttons["Готово"].tap()
    }

    func testInstallmentCollapsePersists() {
        func openInstallments() {
            tabButton("Ще").tap()
            let installment = app.staticTexts["Розстрочка"]
            for _ in 0..<12 { if installment.exists && installment.isHittable { break }; app.swipeUp() }
            visible(installment); installment.tap()
        }
        openInstallments()
        let toggle = app.buttons["qa.installment.collapse.qa-loan"]
        visible(toggle); XCTAssertEqual(toggle.label, "Згорнути розстрочку")
        toggle.tap(); XCTAssertEqual(toggle.label, "Розгорнути розстрочку")
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch()
        openInstallments(); visible(toggle); XCTAssertEqual(toggle.label, "Розгорнути розстрочку")
        toggle.tap(); XCTAssertEqual(toggle.label, "Згорнути розстрочку")
    }
    func testInstallmentPaidFromSelectedAccount() {
        let more = tabButton("Ще"); visible(more); more.tap()
        let installment = app.staticTexts["Розстрочка"]
        for _ in 0..<12 { if installment.exists && installment.isHittable {break};app.swipeUp() }
        visible(installment); installment.tap()
        let loan = app.staticTexts["QA installment"]; visible(loan);loan.tap()
        let pay = app.buttons["qa.payment.pay"];visible(pay);pay.tap()
        visible(app.navigationBars["Записати оплату"])
        let account = app.descendants(matching:.any).matching(identifier:"qa.payment.account").firstMatch
        visible(account);account.tap();let card=app.buttons["QA Card"];visible(card);card.tap()
        let mode = app.descendants(matching:.any).matching(identifier:"qa.payment.mode").firstMatch
        visible(mode);mode.tap();let new=app.buttons["Створити списання"];visible(new);new.tap()
        let confirm=app.buttons["qa.payment.confirm"]
        for _ in 0..<8 { if confirm.exists && confirm.isHittable {break};app.swipeUp() }
        visible(confirm);XCTAssertTrue(confirm.isEnabled);confirm.tap()
        visible(app.navigationBars["Розстрочка"])
        capture("payment-saved")
        app.terminate();app.launchArguments=["--finami-qa"];app.launch()
        let operations=tabButton("Операції");visible(operations);operations.tap()
        visible(app.staticTexts["QA installment"]);capture("payment-operation-persisted")
    }
    func testExistingOperationLinksToInstallment() {
        let tab = tabButton("Операції"); visible(tab); tab.tap()
        let debit = app.staticTexts["QA existing debit"]; visible(debit); debit.tap()
        let picker = app.descendants(matching: .any).matching(identifier: "qa.operation.payment").firstMatch
        for _ in 0..<8 { if picker.exists && picker.isHittable { break }; app.swipeUp() }
        visible(picker); picker.tap()
        let loan = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "QA installment")).firstMatch
        visible(loan); loan.tap()
        let save = app.navigationBars.buttons["Зберегти"]; visible(save); XCTAssertTrue(save.isEnabled); save.tap()
        visible(debit); XCTAssertEqual(app.staticTexts.matching(identifier: "QA existing debit").count, 1)
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch()
        visible(tab); tab.tap(); visible(debit); debit.tap()
        let linked = app.descendants(matching: .any).matching(identifier: "qa.operation.linked").firstMatch
        for _ in 0..<8 { if linked.exists && linked.isHittable { break }; app.swipeUp() }
        visible(linked); capture("operation-linked-persisted")
    }
    func testGlobalSearchOpensReconciliation() {
        tabButton("Ще").tap()
        let link = app.descendants(matching:.any).matching(identifier:"qa.search.open").firstMatch
        visible(link); link.tap()
        visible(app.navigationBars["Пошук Finami"])
        let field = app.searchFields.firstMatch
        visible(field); field.tap(); field.typeText("balance")
        let result = app.descendants(matching:.any).matching(identifier:"qa.search.reconcile").firstMatch
        visible(result); result.tap()
        visible(app.navigationBars["Звірити баланс"])
        capture("search-reconciliation")
    }
    func testCategoryIconAndNamePersist() {
        tabButton("Ще").tap()
        let categories = app.descendants(matching:.any).matching(identifier:"qa.quick.categories").firstMatch
        visible(categories); categories.tap()
        let add = app.buttons["qa.category.add"]; visible(add); add.tap()
        let name = app.textFields["Іконка та назва"]; visible(name); name.tap(); name.typeText("QA Fitness")
        let icons = app.descendants(matching:.any).matching(identifier:"qa.category.icons").firstMatch
        visible(icons); icons.tap(); visible(app.navigationBars["Іконки категорій"])
        let search = app.searchFields.firstMatch; visible(search); search.tap(); search.typeText("sport")
        let icon = app.buttons["💪"]
        for _ in 0..<8 { if icon.exists && icon.isHittable { break }; app.swipeUp() }
        visible(icon); icon.tap(); visible(app.buttons["Зберегти"]); app.buttons["Зберегти"].tap()
        let category = app.staticTexts["💪 QA Fitness"]
        for _ in 0..<14 { if category.exists && category.isHittable { break }; app.swipeUp() }
        visible(category)
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch()
        visible(tabButton("Ще")); tabButton("Ще").tap(); visible(categories); categories.tap()
        for _ in 0..<14 { if category.exists && category.isHittable { break }; app.swipeUp() }
        visible(category); capture("category-persisted")
    }
    func testBalanceReconciliationPersists() {
        func openCreditReconciliation() {
            tabButton("Ще").tap()
            let quick = app.descendants(matching: .any).matching(identifier: "qa.quick.reconcile").firstMatch
            for _ in 0..<8 { if quick.exists && quick.isHittable { break }; app.swipeDown() }
            visible(quick); quick.tap(); visible(app.navigationBars["Звірити баланс"])
            let picker = app.descendants(matching: .any).matching(identifier: "qa.reconcile.account").firstMatch
            visible(picker); picker.tap()
            let card = app.buttons["QA Credit Card"]; visible(card); card.tap()
        }
        func assertBalanceField(_ id: String, _ amount: Double, file: StaticString = #filePath, line: UInt = #line) {
            let field = app.descendants(matching: .any).matching(identifier: id).firstMatch
            for _ in 0..<8 { if field.exists { break }; app.swipeUp() }
            visible(field, file: file, line: line)
            let expected = amount.formatted(.currency(code: "UAH").locale(Locale(identifier: "uk_UA")))
            awaitValue(field, expected, file: file, line: line)
        }
        openCreditReconciliation()
        let used = app.textFields["Використано кредиту, UAH"]
        for _ in 0..<8 { if used.exists && used.isHittable { break }; app.swipeUp() }
        visible(used); used.tap(); used.typeText("250")
        let save = app.buttons["qa.reconcile.save"]
        for _ in 0..<10 { if save.exists && save.isHittable { break }; app.swipeUp() }
        visible(save); save.tap()
        let confirm = app.buttons["Застосувати"]; visible(confirm); confirm.tap()
        // This is a non-interactive status. Do not use isHittable or scroll it away.
        let saved = app.staticTexts["qa.reconcile.saved"]
        visible(saved)
        XCTAssertEqual(saved.label, "Контрольний баланс збережено")
        capture("reconciliation-write-confirmed")
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch()
        visible(tabButton("Ще")); openCreditReconciliation()
        // Verify the actual reloaded financial values independently of the account-card style.
        assertBalanceField("qa.reconcile.currentNet", -250)
        assertBalanceField("qa.reconcile.currentAvailable", 750)
        assertBalanceField("qa.reconcile.persistedNet", -250)
        capture("reconciled-credit-persisted")
        // Keep the original integration check as well: the persisted grid must
        // expose the same value without changing the saved account mode or layout.
        tabButton("Рахунки").tap()
        visible(app.navigationBars["Рахунки"])
        let credit = app.descendants(matching: .any).matching(identifier: "qa.account.compact.qa-design-credit").firstMatch
        for _ in 0..<10 { if credit.exists && credit.isHittable { break }; app.swipeUp() }
        visible(credit); XCTAssertTrue(credit.isHittable)
        let expected = (750.0).formatted(.currency(code: "UAH").locale(Locale(identifier: "uk_UA")))
        XCTAssertEqual(credit.value as? String, expected, "Account card must display the reloaded available credit")
        capture("reconciled-credit-card-persisted")
    }
    func testLaunchPerformance() {
        app.terminate();app.launchArguments=["--finami-qa"]
        measure(metrics:[XCTApplicationLaunchMetric()]) { app.launch() }
    }

    func testRecurringSuggestionCreatesSubscription() {
        let more = tabButton("Ще"); visible(more); more.tap()
        let open = app.descendants(matching:.any).matching(identifier:"qa.recurring.open").firstMatch
        visible(open); open.tap()
        visible(app.staticTexts["QA Streaming"])
        let accept = app.buttons["qa.recurring.accept"]; visible(accept); accept.tap()
        let add = app.alerts.buttons["Додати"]; visible(add); add.tap()
        visible(app.staticTexts["qa.recurring.empty"]); capture("recurring-suggestion-accepted")
    }
    func testPaymentCalendarOpensAndChangesMonth() {
        tabButton("Ще").tap()
        let open = app.descendants(matching:.any).matching(identifier:"qa.calendar.open").firstMatch
        for _ in 0..<12 { if open.exists && open.isHittable { break }; app.swipeUp() }
        visible(open); open.tap()
        visible(app.navigationBars["Календар платежів"])
        let next = app.buttons["Наступний місяць"]; visible(next); next.tap()
        let prev = app.buttons["Попередній місяць"]; visible(prev); prev.tap()
        capture("calendar-month")
    }

}
