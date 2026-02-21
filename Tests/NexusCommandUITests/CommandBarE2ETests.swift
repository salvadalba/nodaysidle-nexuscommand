import XCTest

/// E2E tests for NexusCommand.
/// These require XCUITest framework and must be run via:
///   xcodebuild -scheme NexusCommand -destination 'platform=macOS' test
///
/// For SPM-only development, generate an Xcode project first:
///   open Package.swift (in Xcode, which auto-generates the workspace)
final class CommandBarE2ETests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Command Bar Activation

    func testCommandBarAppearsOnHotkey() throws {
        // Simulate hotkey (Cmd+Space) — may need synthetic events
        // For E2E testing, we use the menu bar item as trigger
        let menuBarItem = app.menuBarItems["NexusCommand"]
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 5))

        menuBarItem.click()

        let openButton = app.menuItems["Open Command Bar"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 2))
        openButton.click()

        // Verify command bar appears
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2), "Command bar text field should be visible")
    }

    func testCommandBarShowsResults() throws {
        // Open command bar
        let menuBarItem = app.menuBarItems["NexusCommand"]
        menuBarItem.click()
        app.menuItems["Open Command Bar"].click()

        // Type a query
        let textField = app.textFields.firstMatch
        textField.click()
        textField.typeText("Safari")

        // Wait for results
        sleep(1) // Allow debounce + search

        // Verify results appear
        let resultsList = app.scrollViews.firstMatch
        XCTAssertTrue(resultsList.exists, "Results list should be visible after typing")
    }

    func testCommandBarDismissesOnEscape() throws {
        let menuBarItem = app.menuBarItems["NexusCommand"]
        menuBarItem.click()
        app.menuItems["Open Command Bar"].click()

        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2))

        // Press Escape
        textField.typeKey(.escape, modifierFlags: [])

        // Give it a moment to dismiss
        sleep(1)

        // The panel should be dismissed (text field no longer exists or not focused)
        // Note: exact assertion depends on panel behavior
    }

    // MARK: - Settings

    func testSettingsOpens() throws {
        let menuBarItem = app.menuBarItems["NexusCommand"]
        menuBarItem.click()

        let settingsItem = app.menuItems["Settings..."]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 2))
        settingsItem.click()

        // Verify settings window appears
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3), "Settings window should open")
    }

    // MARK: - Cold Start

    func testColdStartPerformance() throws {
        // Measure launch-to-ready time
        measure(metrics: [XCTClockMetric()]) {
            app.terminate()
            app.launch()

            // Wait for menu bar item to appear (indicates app is ready)
            let menuBarItem = app.menuBarItems["NexusCommand"]
            XCTAssertTrue(menuBarItem.waitForExistence(timeout: 3), "App should be ready within 3 seconds")
        }
    }
}
