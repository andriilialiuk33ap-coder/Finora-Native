import XCTest

final class FinamiUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--finami-qa", "--finami-qa-reset"]
        app.launch()
    }
    private func visible(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing: \(element)", file: file, line: line)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
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
        app.terminate(); app.launchArguments = ["--finami-qa"]; app.launch(); app.tabBars.buttons["Рахунки"].tap()
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
        visible(app.navigationBars["Центр імпорту"])
        visible(app.staticTexts["Скриншоти розстрочок"])
        capture("import-hub")
    }
    func testDiagnosticsRunsLocalParser() {
        app.tabBars.buttons["Ще"].tap()
        let diagnostics = app.descendants(matching: .any).matching(identifier: "qa.smart.diagnostics").firstMatch
        for _ in 0..<12 { if diagnostics.exists && diagnostics.isHittable { break }; app.swipeUp() }
        visible(diagnostics); diagnostics.tap()
        visible(app.navigationBars["Діагностика"])
        let test = app.buttons["Перевірити зараз"]
        for _ in 0..<12 { if test.exists && test.isHittable { break }; app.swipeUp() }
        visible(test); test.tap(); visible(app.staticTexts["Тест пройдено"])
        capture("diagnostics")
    }
}
