import XCTest

final class FinamiUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--finami-qa", "--finami-qa-reset"]
        app.launch()
        visible(app.tabBars.buttons["Головна"])
    }
    private func visible(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing: \(element)", file: file, line: line)
    }
    private func awaitValue(_ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = NSPredicate(format: "exists == true AND value == %@", value)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: element)], timeout: 15)
        XCTAssertEqual(result, .completed, "Expected \(value), got \(String(describing: element.value))", file: file, line: line)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNextScreensOpen() {
        app.tabBars.buttons["Ще"].tap()
        for (identifier,title) in [("qa.next.review","Перевірка операцій"),("qa.next.insights","Фінансові підсумки"),("qa.next.usdt","Журнал USDT"),("qa.next.partners","Спільні кредитні ліміти")] {
            let item=app.descendants(matching:.any).matching(identifier:identifier).firstMatch
            for _ in 0..<8 {if item.exists && item.isHittable {break};app.swipeUp()}
            visible(item);item.tap();visible(app.navigationBars[title]);capture(identifier)
            app.navigationBars.buttons.firstMatch.tap()
        }
    }
    func testAllFiveTabsOpen() {
        for title in ["Головна", "Операції", "Рахунки", "Звіти", "Ще"] {
            let tab = app.tabBars.buttons[title]; visible(tab); tab.tap()
            visible(app.navigationBars[title]); capture(title)
        }
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
        app.tabBars.buttons["Рахунки"].tap()
        let own = app.buttons["Приховати власний баланс"]; visible(own); own.tap()
        visible(app.buttons["Показати власний баланс"])
        visible(app.buttons["Приховати кредитний баланс"])
        app.buttons["Вигляд балансу"].tap(); app.buttons["Один спільний блок"].tap()
        visible(app.buttons["Показати власний баланс"]); capture("accountPrivacy")
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch(); visible(app.tabBars.buttons["Рахунки"]); app.tabBars.buttons["Рахунки"].tap()
        visible(app.buttons["Показати власний баланс"]); visible(app.buttons["Приховати кредитний баланс"])
    }
    func testRealVisionOCRPopulatesInstallmentFields() {
        app.buttons["Імпорт зі скриншота"].tap()
        let fixture = app.buttons["QA: тестове фото розстрочки"]; visible(fixture); fixture.tap()
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
    func testImportHubOpensAndShowsReview() {
        app.tabBars.buttons["Ще"].tap()
        let hub = app.descendants(matching: .any).matching(identifier: "qa.smart.hub").firstMatch
        for _ in 0..<12 { if hub.exists && hub.isHittable { break }; app.swipeUp() }
        visible(hub); hub.tap()
        visible(app.navigationBars["Імпорт та експорт"])
        visible(app.staticTexts["Скриншоти розстрочок"])
        capture("import-hub")
    }
    func testExportAndRulesScreensOpen() {
        app.tabBars.buttons["Ще"].tap()
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
        app.tabBars.buttons["Ще"].tap()
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
        app.terminate()
        app.launchArguments = ["--finami-qa", "--finami-qa-reset", "--finami-qa-reports-fixture"]
        app.launch()
        visible(app.tabBars.buttons["Звіти"]); app.tabBars.buttons["Звіти"].tap()
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
        visible(app.tabBars.buttons["Звіти"]); app.tabBars.buttons["Звіти"].tap(); openSettings("qa-pumb")
        visible(income); awaitValue(income, "Вимкнено")
        app.navigationBars.buttons["Готово"].tap()
        openSettings("qa-otp"); visible(income); awaitValue(income, "Увімкнено")
        app.navigationBars.buttons["Готово"].tap()
    }

    func testInstallmentPaidFromSelectedAccount() {
        app.terminate()
        app.launchArguments = ["--finami-qa", "--finami-qa-reset", "--finami-qa-payment-fixture"]
        app.launch()
        let more = app.tabBars.buttons["Ще"]; visible(more); more.tap()
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
        let operations=app.tabBars.buttons["Операції"];visible(operations);operations.tap()
        visible(app.staticTexts["QA installment"]);capture("payment-operation-persisted")
    }
    func testExistingOperationLinksToInstallment() {
        app.terminate()
        app.launchArguments = ["--finami-qa", "--finami-qa-reset", "--finami-qa-link-fixture"]
        app.launch()
        let tab = app.tabBars.buttons["Операції"]; visible(tab); tab.tap()
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
    func testLaunchPerformance() {
        app.terminate();app.launchArguments=["--finami-qa"]
        measure(metrics:[XCTApplicationLaunchMetric()]) { app.launch() }
    }

    func testRecurringSuggestionCreatesSubscription() {
        app.terminate(); app.launchArguments = ["--finami-qa", "--finami-qa-reset", "--finami-qa-recurring-fixture"]; app.launch()
        let more = app.tabBars.buttons["Ще"]; visible(more); more.tap()
        let open = app.descendants(matching:.any).matching(identifier:"qa.recurring.open").firstMatch
        visible(open); open.tap()
        visible(app.staticTexts["QA Streaming"])
        let accept = app.buttons["qa.recurring.accept"]; visible(accept); accept.tap()
        let add = app.alerts.buttons["Додати"]; visible(add); add.tap()
        visible(app.staticTexts["qa.recurring.empty"]); capture("recurring-suggestion-accepted")
    }
    func testPaymentCalendarOpensAndChangesMonth() {
        app.tabBars.buttons["Ще"].tap()
        let open = app.descendants(matching:.any).matching(identifier:"qa.calendar.open").firstMatch
        for _ in 0..<12 { if open.exists && open.isHittable { break }; app.swipeUp() }
        visible(open); open.tap()
        visible(app.navigationBars["Календар платежів"])
        let next = app.buttons["Наступний місяць"]; visible(next); next.tap()
        let prev = app.buttons["Попередній місяць"]; visible(prev); prev.tap()
        capture("calendar-month")
    }

}
