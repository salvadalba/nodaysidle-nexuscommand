import Testing
import Foundation
@testable import NexusCommand

@Suite("SystemActionService Tests")
struct SystemActionServiceTests {

    @MainActor
    private func makeSUT() -> SystemActionService {
        SystemActionService()
    }

    // MARK: - Launch App

    @Test("launchApp with valid app returns success")
    @MainActor
    func testLaunchApp() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .launchApp,
            parameters: ["app": "Finder"],
            confidence: 0.9
        )
        let result = try await sut.execute(intent: intent)
        #expect(result.success)
        #expect(result.launchedApp == "Finder")
    }

    @Test("launchApp with non-existent app throws AppNotFound")
    @MainActor
    func testLaunchAppNotFound() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .launchApp,
            parameters: ["app": "NonExistentApp12345"],
            confidence: 0.9
        )
        await #expect(throws: ActionError.self) {
            try await sut.execute(intent: intent)
        }
    }

    // MARK: - Shell Commands

    @Test("Allowlisted command executes successfully")
    @MainActor
    func testAllowlistedCommand() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .runShellCommand,
            parameters: ["command": "open ."],
            confidence: 0.9
        )
        // 'open' is in the allowlist
        let result = try await sut.execute(intent: intent)
        #expect(result.success)
    }

    @Test("Non-allowlisted command throws CommandNotAllowed")
    @MainActor
    func testNonAllowlistedCommand() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .runShellCommand,
            parameters: ["command": "rm -rf /"],
            confidence: 0.9
        )
        await #expect(throws: ActionError.self) {
            try await sut.execute(intent: intent)
        }
    }

    @Test("pbcopy is allowlisted")
    @MainActor
    func testPbcopyAllowed() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .runShellCommand,
            parameters: ["command": "pbpaste"],
            confidence: 0.9
        )
        let result = try await sut.execute(intent: intent)
        #expect(result.success)
    }

    // MARK: - Calculate

    @Test("Calculate evaluates valid expression")
    @MainActor
    func testCalculate() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .calculate,
            parameters: ["expression": "2 + 2"],
            confidence: 0.95
        )
        let result = try await sut.execute(intent: intent)
        #expect(result.success)
        #expect(result.output?.contains("4") == true)
    }

    @Test("Calculate handles multiplication")
    @MainActor
    func testCalculateMultiplication() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .calculate,
            parameters: ["expression": "6 * 7"],
            confidence: 0.95
        )
        let result = try await sut.execute(intent: intent)
        #expect(result.success)
        #expect(result.output?.contains("42") == true)
    }

    // MARK: - System Preferences

    @Test("systemPreference returns success")
    @MainActor
    func testSystemPreference() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .systemPreference,
            parameters: ["pane": "general"],
            confidence: 0.85
        )
        let result = try await sut.execute(intent: intent)
        #expect(result.success)
        #expect(result.openedURL != nil)
    }

    // MARK: - Web Search

    @Test("webSearch returns success with URL")
    @MainActor
    func testWebSearch() async throws {
        let sut = makeSUT()
        let intent = ParsedIntent(
            action: .webSearch,
            parameters: ["query": "swift programming"],
            confidence: 0.85
        )
        let result = try await sut.execute(intent: intent)
        #expect(result.success)
        #expect(result.openedURL != nil)
    }
}
