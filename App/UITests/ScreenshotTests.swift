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
        app.launchArguments += ["-UseEmulators"]
        app.launch()
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

        log.tap()
        XCTAssertTrue(app.staticTexts["You"].waitForExistence(timeout: 10), "logged beer row missing")
        snap("04-home-beer")

        app.tabBars.buttons["Mates"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        snap("05-friends")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
        snap("06-settings")

        app.tabBars.buttons["Beers"].tap()
        app.buttons["home.camera"].tap()
        sleep(2) // camera permission / unavailable state on the simulator
        snap("07-camera")
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
