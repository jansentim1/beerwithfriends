import XCTest

/// Walks every screen against the Firebase emulators and saves a PNG per screen
/// into $SCREENSHOT_DIR (passed as TEST_RUNNER_SCREENSHOT_DIR to xcodebuild).
/// Appearance (light/dark) is set on the simulator by the workflow; the suffix
/// comes from $SCREENSHOT_SUFFIX.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UseEmulators", "-UITestLogWithoutPhoto"]
        if name.contains("Populated") { app.launchArguments += ["-UITestAccount", "tim"] }
        app.launch()
    }

    /// Seeded account (tools/rig/seed.mjs): a mate with a photo drink and a
    /// place, groups with counts. Covers the screens the fresh-account
    /// walkthrough cannot: populated feed, map pins, groups, detail, username sheet.
    func testPopulated() throws {
        let testSignIn = app.buttons["signin.test"]
        XCTAssertTrue(testSignIn.waitForExistence(timeout: 10))
        testSignIn.tap()
        let log = app.buttons["home.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 20), "home did not appear for the seeded account")
        XCTAssertTrue(app.staticTexts["joost"].waitForExistence(timeout: 15), "mate's drinks missing")
        snap("08-home-populated")

        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        sleep(3) // map tiles + pin framing
        snap("08b-map-pins")

        app.tabBars.buttons["Groups"].tap()
        XCTAssertTrue(app.staticTexts["De Kroeg"].waitForExistence(timeout: 10), "groups missing")
        snap("08c-groups-populated")
        app.staticTexts["De Kroeg"].firstMatch.tap()
        sleep(2)
        snap("08d-group-detail")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown() }

        app.tabBars.buttons["Settings"].tap()
        let username = app.buttons["settings.changeUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        sleep(1)
        snap("08e-username-sheet")
    }

    override func tearDown() {
        // Whatever is on screen when a step fails is the most useful evidence.
        snap("99-final-state")
    }

    func testWalkthrough() throws {
        snap("01-signin")

        let testSignIn = app.buttons["signin.test"]
        XCTAssertTrue(testSignIn.waitForExistence(timeout: 10), "emulator sign-in button missing")
        testSignIn.tap()

        let field = app.textFields["onboarding.username"]
        let appeared = field.waitForExistence(timeout: 20)
        if !appeared { snap("01b-after-signin-tap") }
        XCTAssertTrue(appeared, "username screen did not appear")
        field.tap()
        field.typeText("tim\(Int.random(in: 1000...9999))")
        let claim = app.buttons["onboarding.claim"]
        XCTAssertTrue(wait(until: { claim.isEnabled }, timeout: 10), "username never became available")
        snap("02-username")
        claim.tap()

        let log = app.buttons["home.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 20), "home screen did not appear")
        snap("03-home-empty")

        // Tapping a glass pours it and opens the camera (a photo is mandatory).
        // With -UITestLogWithoutPhoto, Cancel logs the drink anyway (simulator has
        // no camera).
        log.tap()
        sleep(2) // pour + camera permission / unavailable state on the simulator
        snap("07-camera")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "camera did not open after the pour")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["You"].waitForExistence(timeout: 10), "logged beer row missing")
        snap("04-home-beer")

        app.tabBars.buttons["Mates"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        snap("05-friends")

        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        snap("05b-map")

        app.tabBars.buttons["Groups"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        snap("05c-groups")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        snap("06-settings")
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        sleep(1) // let animations settle
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = env["SCREENSHOT_DIR"] else { return }
        let suffix = env["SCREENSHOT_SUFFIX"] ?? ""
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: url)
    }

    private func wait(until condition: @escaping () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }
}
