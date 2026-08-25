import XCTest

/// Choreographed walk through the app used to record motion videos in the simulator.
/// Skipped unless RA_MOTION_DEMO=1 (run with `TEST_RUNNER_RA_MOTION_DEMO=1 xcodebuild test ...`).
final class MotionDemoTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RA_MOTION_DEMO"] == "1", "motion demo only")
        continueAfterFailure = true
    }

    func testMotionDemo() {
        let app = XCUIApplication()
        app.launch()
        let title = app.staticTexts["Temporada"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        pause(1.5)

        // 1) Zoom into the detail from "Sigue viendo".
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster-continue-'")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        poster.tap()
        pause(2.0)

        // 2) Favorite bounce, episode stepper (numeric roll + haptic), status morph.
        let favorite = app.buttons["detail.favorite"].firstMatch
        if favorite.waitForExistence(timeout: 8) {
            favorite.tap(); pause(0.9); favorite.tap(); pause(0.9)
        }
        let plus = app.buttons["detail.episode.plus"].firstMatch
        if plus.exists {
            plus.tap(); pause(0.7); plus.tap(); pause(0.9)
        }
        let minus = app.buttons["detail.episode.minus"].firstMatch
        if minus.exists {
            minus.tap(); pause(0.7); minus.tap(); pause(0.9)
        }
        let pending = app.buttons["detail.status.pending"].firstMatch
        if pending.exists {
            pending.tap(); pause(1.4)
        }
        let watching = app.buttons["detail.status.watching"].firstMatch
        if watching.exists {
            watching.tap(); pause(1.4)
        }

        // 3) Scroll: tab bar minimizes, accessory goes inline; then back up.
        app.swipeUp(); pause(1.2)
        app.swipeUp(); pause(1.2)
        app.swipeDown(); pause(0.8)
        app.swipeDown(); pause(1.2)

        // 4) Back (zoom out).
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists {
            back.tap()
        } else {
            app.swipeRight()
        }
        pause(1.8)

        // 5) Top: glass chips switching prominence.
        app.tabBars.buttons["Top"].firstMatch.tap(); pause(1.5)
        for id in ["top.filter.airing", "top.filter.bypopularity", "top.filter.score"] {
            let chip = app.buttons[id].firstMatch
            if chip.waitForExistence(timeout: 3) {
                chip.tap(); pause(1.1)
            }
        }

        // 6) Mi lista: segments and the +1 in the bottom accessory.
        app.tabBars.buttons["Mi lista"].firstMatch.tap(); pause(1.5)
        for segment in ["Favoritos", "Vistos", "Viendo"] {
            let button = app.buttons[segment].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap(); pause(1.0)
            }
        }
        let increment = app.buttons["nowWatching.increment"].firstMatch
        if increment.waitForExistence(timeout: 3) {
            increment.tap(); pause(0.8); increment.tap(); pause(1.2)
        }

        // 7) Search tab (search role) and back home.
        app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1).tap(); pause(1.5)
        app.tabBars.buttons.element(boundBy: 0).tap(); pause(1.5)
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }
}

/// Short choreography for slow-motion recordings (UIAnimationDragCoefficient set on the simulator).
final class MotionZoomTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RA_MOTION_DEMO"] == "1", "motion demo only")
        continueAfterFailure = true
    }

    func testZoomAndMorph() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Inicio"].firstMatch.waitForExistence(timeout: 15))
        pause(3.0)
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster-continue-'")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        poster.tap()
        pause(5.0)
        app.buttons["detail.status.pending"].firstMatch.tap()
        pause(4.0)
        app.buttons["detail.status.watching"].firstMatch.tap()
        pause(4.0)
        app.buttons["detail.favorite"].firstMatch.tap()
        pause(3.0)
        app.swipeUp()
        pause(4.0)
        app.swipeDown()
        pause(4.0)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(5.0)
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }
}

/// Opens the detail, the trailer sheet and the episode picker (screenshots are taken from the shell).
final class TrailerTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RA_MOTION_DEMO"] == "1", "motion demo only")
        continueAfterFailure = true
    }

    func testTrailerAndEpisodePicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-ra-open", "recanime://anime/52991"]
        app.launch()
        let trailer = app.buttons["detail.trailer"].firstMatch
        XCTAssertTrue(trailer.waitForExistence(timeout: 20))
        pause(2)
        trailer.tap()
        pause(7)
        app.buttons["Listo"].firstMatch.tap()
        pause(2)
        let pick = app.buttons["detail.episode.pick"].firstMatch
        if pick.waitForExistence(timeout: 5) {
            pick.tap()
            pause(5)
            app.buttons["Cancelar"].firstMatch.tap()
        }
        pause(2)
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }
}
