import XCTest

final class TidyMobileUITests: XCTestCase {
    func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--tidy-preview"]
        app.launch()
        return app
    }
    func testRewriteReviewAndCopy() {
        let app = launchPreview()
        XCTAssertTrue(app.staticTexts["previewNotice"].waitForExistence(timeout: 5))
        app.buttons["Rewrite"].tap()
        XCTAssertTrue(app.buttons["copyResult"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Original"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "running like 15 mins late")).firstMatch.exists)
        app.segmentedControls.buttons["Changes"].tap()
        XCTAssertTrue(app.staticTexts["changesText"].exists)
        app.segmentedControls.buttons["Final"].tap()
        XCTAssertTrue(app.textViews["finalEditor"].exists)
        let statusFrame = app.staticTexts["rewriteStatus"].frame
        XCTAssertLessThanOrEqual(statusFrame.maxY, app.buttons["copyResult"].frame.minY, "Status must not overlap Copy at any text size")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Tidy iPhone Final"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["copyResult"].tap()
        XCTAssertTrue(app.staticTexts["rewriteStatus"].label.hasPrefix("Copied"))
        XCTAssertLessThanOrEqual(app.staticTexts["rewriteStatus"].frame.maxY, app.buttons["copyResult"].frame.minY)
        let copiedShot = XCTAttachment(screenshot: app.screenshot()); copiedShot.name = "Copied status"; copiedShot.lifetime = .keepAlways; add(copiedShot)
        app.buttons["Share result"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
    }
    func testCancelAndRetry() {
        let app = launchPreview()
        app.buttons["Rewrite"].tap()
        app.buttons["Cancel rewrite"].tap()
        XCTAssertTrue(app.staticTexts["Cancelled · draft kept"].exists)
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.buttons["copyResult"].waitForExistence(timeout: 10))
    }
    func testCompletedSampleCanBeSharedBackToTidy() {
        verifySampleRoundTrip(shorter: false)
    }
    func testShorterSampleCanBeSharedBackToTidy() {
        verifySampleRoundTrip(shorter: true)
    }
    private func verifySampleRoundTrip(shorter: Bool) {
        let app = launchPreview()
        if shorter { app.buttons["Shorter"].tap() }
        app.buttons["Rewrite"].tap()
        XCTAssertTrue(app.buttons["copyResult"].waitForExistence(timeout: 10))
        let expected = app.textViews["finalEditor"].value as? String
        XCTAssertNotNil(expected)
        app.buttons["Share result"].tap()
        XCTAssertTrue(app.cells["Tidy"].waitForExistence(timeout: 5))
        app.cells["Tidy"].tap()
        XCTAssertTrue(app.buttons["extensionRewrite"].waitForExistence(timeout: 10))
        app.buttons["extensionRewrite"].tap()
        // Match the extension explicitly; the completed host may remain behind it.
        let editor = app.textViews["extensionFinalEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, expected)
        XCTAssertFalse(app.staticTexts["rewriteError"].exists)
        app.buttons["Done"].firstMatch.tap()
    }
    func testMissingKeyRoutesToSetup() {
        let app = XCUIApplication(); app.launchArguments = ["--tidy-live"]; app.launch()
        app.buttons["Set up Tidy"].tap()
        XCTAssertTrue(app.buttons["Add API key"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["copyResult"].exists)
    }
    func testEditingFinalClearsCopiedStatus() {
        let app = launchPreview()
        app.buttons["Rewrite"].tap()
        XCTAssertTrue(app.buttons["copyResult"].waitForExistence(timeout: 10))
        app.buttons["copyResult"].tap()
        app.textViews["finalEditor"].tap()
        app.textViews["finalEditor"].typeText(" Thanks.")
        XCTAssertFalse(app.staticTexts["Copied · ready to paste"].exists)
    }
    func testDisablingPreviewDiscardsRecordedResult() {
        let app = launchPreview()
        app.buttons["Rewrite"].tap()
        XCTAssertTrue(app.buttons["copyResult"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Exit sample"].isHittable)
        app.buttons["Exit sample"].tap()
        XCTAssertTrue(app.buttons["Set up Tidy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["copyResult"].exists)
        XCTAssertFalse(app.staticTexts["previewNotice"].exists)
        XCTAssertEqual(app.textViews["originalEditor"].value as? String, "")
    }
    func testSettingsMakesSetupAndSampleVisible() {
        let app = launchPreview()
        app.buttons["Settings"].tap()
        let form = app.descendants(matching: .any).matching(identifier: "settingsForm").firstMatch
        XCTAssertTrue(app.buttons["Add API key"].waitForExistence(timeout: 5))
        XCTAssertTrue(form.buttons["Exit sample"].isHittable)
        XCTAssertTrue(form.buttons["Manage modes"].isHittable)
        XCTAssertFalse(form.buttons["Clean up"].exists)
        let settingsShot = XCTAttachment(screenshot: app.screenshot()); settingsShot.name = "Setup and sample visible"; settingsShot.lifetime = .keepAlways; add(settingsShot)
        app.buttons["Add API key"].tap()
        XCTAssertTrue(app.secureTextFields["Anthropic API key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect to Anthropic"].exists)
        XCTAssertFalse(app.buttons["Connect to Anthropic"].isEnabled)
        let connectionShot = XCTAttachment(screenshot: app.screenshot()); connectionShot.name = "Connect Tidy"; connectionShot.lifetime = .keepAlways; add(connectionShot)
    }
    func testConnectionKeepsActionAboveKeyboard() {
        let app = XCUIApplication(); app.launchArguments = ["--tidy-live"]; app.launch()
        app.buttons["Set up Tidy"].tap()
        for _ in 0..<4 where !app.buttons["Add API key"].isHittable { app.swipeUp() }
        app.buttons["Add API key"].tap()
        let field = app.secureTextFields["Anthropic API key"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<4 where !field.isHittable { app.swipeUp() }
        field.tap(); field.typeText("not-a-real-key")
        let connect = app.buttons["Connect to Anthropic"]
        XCTAssertTrue(connect.isEnabled)
        XCTAssertTrue(connect.isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(connect.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Connection with keyboard"; shot.lifetime = .keepAlways; add(shot)
        // Never submit: this test checks layout without making a provider request.
        app.buttons["Close"].tap()
    }
    func testActualShareExtension() {
        let app = launchPreview()
        app.swipeUp()
        app.buttons["shareSample"].tap()
        let tidy = app.cells["Tidy"]
        XCTAssertTrue(tidy.waitForExistence(timeout: 5), app.debugDescription)
        tidy.tap()
        let rewrite = app.buttons["extensionRewrite"]
        XCTAssertTrue(rewrite.waitForExistence(timeout: 10), app.debugDescription)
        rewrite.tap()
        XCTAssertTrue(app.buttons["copyResult"].waitForExistence(timeout: 10), app.debugDescription)
        app.segmentedControls.buttons["Changes"].tap()
        XCTAssertTrue(app.staticTexts["changesText"].exists)
        let changesShot = XCTAttachment(screenshot: app.screenshot()); changesShot.name = "Share extension Changes"; changesShot.lifetime = .keepAlways; add(changesShot)
        app.segmentedControls.buttons["Final"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Actual Share extension"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["copyResult"].tap()
        XCTAssertTrue(app.staticTexts["Copied · ready to paste"].exists)
        app.buttons["Share result"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
        let closeButtons = app.buttons.matching(identifier: "header.closeButton")
        XCTAssertGreaterThanOrEqual(closeButtons.count, 2, "Result sharing presents a second activity sheet")
        closeButtons.element(boundBy: closeButtons.count - 1).tap()
        app.buttons["Done"].firstMatch.tap()
    }
    func testCustomModePersistsAndAppearsInExtension() {
        let app = launchPreview()
        let name = "Phone " + String(UUID().uuidString.prefix(6))
        app.buttons["Settings"].tap()
        app.buttons["Manage modes"].tap()
        for _ in 0..<4 where !app.buttons["Add mode"].isHittable { app.swipeUp() }
        app.buttons["Add mode"].tap()
        app.textFields["Name"].tap(); app.textFields["Name"].typeText(name)
        app.textViews["Mode instructions"].tap(); app.textViews["Mode instructions"].typeText("Fix spelling only. Preserve every fact.")
        app.buttons["Save"].tap()
        app.navigationBars["Modes"].buttons["Settings"].tap()
        app.buttons["Done"].firstMatch.tap()
        app.terminate(); app.launch()
        app.swipeUp()
        app.buttons["shareSample"].tap()
        XCTAssertTrue(app.cells["Tidy"].waitForExistence(timeout: 5))
        app.cells["Tidy"].tap()
        XCTAssertTrue(app.buttons["extensionRewrite"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: name).count, 2, "Mode is present in both host app and extension")
        app.buttons["Done"].firstMatch.tap()
    }
}
