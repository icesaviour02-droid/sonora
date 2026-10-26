import XCTest

/// Exercises real touch gestures against the same native queue used by the app.
final class MusicInteractionTests: XCTestCase {
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
        let grip = app.descendants(matching: .any).matching(identifier: firstID.replacingOccurrences(of: "queue-row-", with: "queue-grip-")).firstMatch
        XCTAssertTrue(grip.exists)
        grip.press(forDuration: 1, thenDragTo: secondCell.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)))
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
        XCTAssertEqual(rows.count, 1)
        app.buttons["queue-add-songs"].tap()
        XCTAssertTrue(app.buttons["queue-picker-confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.buttons["queue-picker-confirm"].isEnabled)
        app.buttons["queue-picker-confirm"].tap()
        XCTAssertTrue(app.buttons["queue-clear"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        app.buttons["queue-clear"].tap()
        XCTAssertEqual(rows.count, 0)
    }
}
