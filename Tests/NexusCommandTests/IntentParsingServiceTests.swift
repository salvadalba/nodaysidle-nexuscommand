import Testing
import Foundation
@testable import NexusCommand

@Suite("IntentParsingService Tests")
struct IntentParsingServiceTests {

    @MainActor
    private func makeSUT() async -> IntentParsingService {
        let service = IntentParsingService()
        await service.warmup()
        return service
    }

    // MARK: - Action Classification

    @Test("Parses 'open Safari' as launchApp")
    @MainActor
    func testLaunchApp() async throws {
        let sut = await makeSUT()
        let chain = try await sut.parse(query: "open Safari")
        #expect(chain.intents.count == 1)
        #expect(chain.primaryIntent?.action == .launchApp)
        #expect(chain.primaryIntent?.parameters["app"] == "Safari")
    }

    @Test("Parses 'find readme.md' as openFile")
    @MainActor
    func testOpenFile() async throws {
        let sut = await makeSUT()
        let chain = try await sut.parse(query: "find readme.md")
        #expect(chain.intents.count == 1)
        #expect(chain.primaryIntent?.action == .openFile)
        #expect(chain.primaryIntent?.parameters["query"] == "readme.md")
    }

    @Test("Parses 'run ls' as runShellCommand")
    @MainActor
    func testRunShellCommand() async throws {
        let sut = await makeSUT()
        let chain = try await sut.parse(query: "run ls")
        #expect(chain.intents.count == 1)
        #expect(chain.primaryIntent?.action == .runShellCommand)
        #expect(chain.primaryIntent?.parameters["command"] == "ls")
    }

    @Test("Parses 'settings bluetooth' as systemPreference")
    @MainActor
    func testSystemPreference() async throws {
        let sut = await makeSUT()
        let chain = try await sut.parse(query: "settings bluetooth")
        #expect(chain.intents.count == 1)
        #expect(chain.primaryIntent?.action == .systemPreference)
    }

    @Test("Parses 'search swift tutorials' as webSearch")
    @MainActor
    func testWebSearch() async throws {
        let sut = await makeSUT()
        let chain = try await sut.parse(query: "search swift tutorials")
        #expect(chain.intents.count == 1)
        #expect(chain.primaryIntent?.action == .webSearch)
        #expect(chain.primaryIntent?.parameters["query"] == "swift tutorials")
    }

    @Test("Parses '2+2' as calculate")
    @MainActor
    func testCalculate() async throws {
        let sut = await makeSUT()
        let chain = try await sut.parse(query: "2+2")
        #expect(chain.intents.count == 1)
        #expect(chain.primaryIntent?.action == .calculate)
        #expect(chain.primaryIntent?.parameters["expression"] == "2+2")
    }

    // MARK: - Compound Queries

    @Test("Compound query produces multi-intent chain")
    @MainActor
    func testCompoundQuery() async throws {
        let sut = await makeSUT()
        let chain = try await sut.parse(query: "open Terminal and run pwd")
        #expect(chain.intents.count == 2)
        #expect(chain.intents[0].action == .launchApp)
        #expect(chain.intents[1].action == .runShellCommand)
    }

    // MARK: - Error Handling

    @Test("Empty input throws EmptyQuery")
    @MainActor
    func testEmptyQuery() async throws {
        let sut = await makeSUT()
        await #expect(throws: IntentError.emptyQuery) {
            try await sut.parse(query: "")
        }
    }

    @Test("Whitespace-only input throws EmptyQuery")
    @MainActor
    func testWhitespaceQuery() async throws {
        let sut = await makeSUT()
        await #expect(throws: IntentError.emptyQuery) {
            try await sut.parse(query: "   ")
        }
    }

    @Test("Model not loaded throws ModelNotLoaded")
    @MainActor
    func testModelNotLoaded() async throws {
        let sut = IntentParsingService() // No warmup
        await #expect(throws: IntentError.modelNotLoaded) {
            try await sut.parse(query: "test")
        }
    }

    // MARK: - Caching

    @Test("Repeated queries return cached results")
    @MainActor
    func testCaching() async throws {
        let sut = await makeSUT()
        let first = try await sut.parse(query: "open Safari")
        let second = try await sut.parse(query: "open Safari")
        #expect(first == second)
    }
}
