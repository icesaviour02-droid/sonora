import XCTest

/// Exercises real touch gestures against the same native queue used by the app.
final class MusicInteractionTests: XCTestCase {
    func testPlayerModesMenusAndReturnToMiniPlayer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sonora-review-url", "sonora://review?id=jfKfPfyJRdk&title=Sonora%20Player%20Interaction&artist=Sonora%20Artist&mode=artwork"]
        app.launch()
        XCTAssertTrue(app.buttons["player-queue"].waitForExistence(timeout: 30))
        app.buttons["player-queue"].tap()
        XCTAssertTrue(app.buttons["queue-add-songs"].waitForExistence(timeout: 8))
        app.buttons["player-lyrics"].tap()
        XCTAssertTrue(app.buttons["player-return-artwork"].waitForExistence(timeout: 8))
        app.buttons["player-return-artwork"].tap()
        app.buttons["player-more"].tap()
        XCTAssertTrue(app.buttons["Add to Queue"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["Add to Queue"].firstMatch.tap()
        app.buttons["player-dismiss"].tap()
        XCTAssertTrue(app.buttons["mini-player-open"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["mini-player-open"].label.contains("Sonora Artist"))
        app.buttons["mini-player-open"].tap()
        XCTAssertTrue(app.buttons["player-queue"].waitForExistence(timeout: 8))
    }

    func testLocalPlaylistRenameThroughItsMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sonora-review-url", "sonora://localplaylistreview"]
        app.launch()
        XCTAssertTrue(app.buttons["playlist-more"].waitForExistence(timeout: 30))
        app.buttons["playlist-more"].tap()
        XCTAssertTrue(app.buttons["Rename Playlist"].waitForExistence(timeout: 5))
        app.buttons["Rename Playlist"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let value = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText("Sonora Touch Playlist")
        app.alerts.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sonora Touch Playlist"].firstMatch.waitForExistence(timeout: 10))
    }

    func testDownloadedCategoriesUseSavedMusic() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sonora-review-url", "sonora://downloadsreview"]
        app.launch()
        XCTAssertTrue(app.buttons["download-songs"].waitForExistence(timeout: 30))
        app.buttons["download-songs"].tap()
        XCTAssertTrue(app.staticTexts["Sonora Review Tone"].firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["download-albums"].tap()
        XCTAssertTrue(app.staticTexts["Sonora Review Album"].firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["download-playlists"].tap()
        XCTAssertTrue(app.staticTexts["Sonora Saved Playlist"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Sonora Saved Playlist"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sonora Review Tone"].firstMatch.waitForExistence(timeout: 10))
    }

    func testQueueReorderSwipeAddAndClear() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sonora-review-url", "sonora://queuereview?id=jfKfPfyJRdk&title=Sonora%20Queue%20Interaction&artist=Sonora"]
        app.launch()
        XCTAssertTrue(app.buttons["queue-add-songs"].waitForExistence(timeout: 30))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-row-"))
        XCTAssertEqual(rows.count, 2)
        let firstID = rows.element(boundBy: 0).identifier
        let secondID = rows.element(boundBy: 1).identifier
        let firstCell = app.cells.containing(.button, identifier: firstID).firstMatch
        let secondCell = app.cells.containing(.button, identifier: secondID).firstMatch
        XCTAssertTrue(firstCell.exists && secondCell.exists)
        firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: secondCell.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.8)))
        let moved = NSPredicate { _, _ in
            app.buttons[secondID].exists && app.buttons[firstID].exists &&
            app.buttons[secondID].frame.minY < app.buttons[firstID].frame.minY
        }
        expectation(for: moved, evaluatedWith: app)
        waitForExpectations(timeout: 8)
        app.buttons[firstID].swipeLeft()
        let remove = app.buttons["Remove from Queue"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        waitForQueueCount(1, rows: rows)
        app.buttons["queue-add-songs"].tap()
        XCTAssertTrue(app.buttons["queue-picker-confirm"].waitForExistence(timeout: 5))
        let choices = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-picker-song-"))
        let visibleChoice = NSPredicate { _, _ in choices.allElementsBoundByIndex.contains { $0.isHittable } }
        expectation(for: visibleChoice, evaluatedWith: app)
        waitForExpectations(timeout: 8)
        guard let choice = choices.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("The Add Songs sheet has no hittable song row")
            return
        }
        choice.tap()
        XCTAssertTrue(app.buttons["queue-picker-confirm"].isEnabled)
        app.buttons["queue-picker-confirm"].tap()
        XCTAssertTrue(app.buttons["queue-clear"].waitForExistence(timeout: 5))
        waitForQueueCount(2, rows: rows)
        app.buttons["queue-clear"].tap()
        waitForQueueCount(0, rows: rows)
    }

    /// Native list removal/insertion completes asynchronously; assert the resulting row count.
    private func waitForQueueCount(_ count: Int, rows: XCUIElementQuery) {
        expectation(for: NSPredicate { _, _ in rows.count == count }, evaluatedWith: rows)
        waitForExpectations(timeout: 8)
    }
}
