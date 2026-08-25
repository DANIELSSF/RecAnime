import XCTest

/// Writes PNG screenshots of key screens to `RA_SHOT_DIR` (host path; the simulator runner can write there).
/// Skipped unless RA_SHOTS=1: `TEST_RUNNER_RA_SHOTS=1 TEST_RUNNER_RA_SHOT_DIR=/path xcodebuild test ...`.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RA_SHOTS"] == "1", "screenshots only")
        continueAfterFailure = true
    }

    func testTabs() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Top"].firstMatch.tap()
        pause(4)
        shot("top")
        let chip = app.buttons["top.filter.score"].firstMatch
        NSLog("RA_SHOT top chip exists=%d hittable=%d frame=%@", chip.exists, chip.isHittable, NSCoder.string(for: chip.frame))
        let first = app.staticTexts["1"].firstMatch
        NSLog("RA_SHOT top first rank exists=%d frame=%@", first.exists, NSCoder.string(for: first.frame))
        app.tabBars.buttons["Mi lista"].firstMatch.tap()
        pause(3)
        shot("library")
        app.tabBars.buttons["Descubrir"].firstMatch.tap()
        pause(4)
        shot("discover")
        let genre = app.buttons["discover.genre.1"].firstMatch
        if genre.waitForExistence(timeout: 5) {
            genre.tap()
            pause(5)
            shot("discover-action")
        }
        let sort = app.buttons["discover.sort"].firstMatch
        if sort.exists {
            sort.tap()
            pause(1)
            shot("discover-sort")
            app.buttons["Populares"].firstMatch.tap()
            pause(5)
            shot("discover-popular")
        }
    }

    func testProgressSheet() {
        let app = XCUIApplication()
        app.launchArguments += ["-ra-open", ProcessInfo.processInfo.environment["RA_SHOT_ANIME"] ?? "recanime://anime/31964"]
        app.launch()
        let button = app.buttons["detail.franchise.markThrough"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        app.swipeUp()
        pause(1)
        shot("detail-franchise")
        button.tap()
        pause(2)
        shot("progress-sheet")
        let row = app.buttons["progress.row.3"].firstMatch
        if row.waitForExistence(timeout: 3) {
            row.tap()
            pause(1)
            shot("progress-sheet-selected")
        }
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["RA_SHOT_DIR"] else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
