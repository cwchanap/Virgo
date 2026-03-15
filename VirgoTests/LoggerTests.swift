import Testing
import Foundation
@testable import Virgo

@Suite("Logger Tests")
struct LoggerTests {
    private struct TestError: LocalizedError {
        var errorDescription: String? { "Logger test failure" }
    }

    private struct EmptyError: LocalizedError {
        var errorDescription: String? { "" }
    }

    @Test("Logger convenience methods accept messages and errors")
    func testLoggerConvenienceMethods() {
        Logger.database("Saving test data")
        Logger.databaseError(TestError())
        Logger.audioPlayback("Preview started")
        Logger.userAction("Tapped test button")
        Logger.debug("Debug message")
        Logger.info("Info message")
        Logger.warning("Warning message")
        Logger.error("Error message")
        Logger.critical("Critical message")
    }

    @Test("Logger methods accept empty strings without crashing")
    func testLoggerAcceptsEmptyMessages() {
        Logger.database("")
        Logger.audioPlayback("")
        Logger.userAction("")
        Logger.debug("")
        Logger.info("")
        Logger.warning("")
        Logger.error("")
        Logger.critical("")
    }

    @Test("Logger methods accept long messages without crashing")
    func testLoggerAcceptsLongMessages() {
        let longMessage = String(repeating: "x", count: 10_000)
        Logger.database(longMessage)
        Logger.audioPlayback(longMessage)
        Logger.info(longMessage)
        Logger.warning(longMessage)
        Logger.error(longMessage)
    }

    @Test("Logger.databaseError handles errors with empty descriptions")
    func testLoggerDatabaseErrorWithEmptyDescription() {
        Logger.databaseError(EmptyError())
    }

    @Test("Logger static category instances are non-nil os.Logger objects")
    func testLoggerCategoriesExist() {
        // Verifies the static loggers are initialized without error
        _ = Logger.general
        _ = Logger.database
        _ = Logger.audio
        _ = Logger.ui
        _ = Logger.network
    }

    @Test("Logger convenience methods accept special characters")
    func testLoggerAcceptsSpecialCharacters() {
        Logger.info("Special chars: \n\t\r\"'\\")
        Logger.info("Unicode: 🥁 ♩ ♪ ♫ ♬")
        Logger.error("Error with newline\nSecond line")
    }
}

@Suite("LaunchArguments Tests")
struct LaunchArgumentsTests {
    @Test("LaunchArguments constants have expected values")
    func testLaunchArgumentsValues() {
        #expect(LaunchArguments.uiTesting == "-UITesting")
        #expect(LaunchArguments.resetState == "-ResetState")
        #expect(LaunchArguments.skipSeed == "-SkipSeed")
    }

    @Test("LaunchArguments constants are unique")
    func testLaunchArgumentsAreUnique() {
        let args = [LaunchArguments.uiTesting, LaunchArguments.resetState, LaunchArguments.skipSeed]
        let uniqueArgs = Set(args)
        #expect(args.count == uniqueArgs.count)
    }

    @Test("LaunchArguments constants start with dash prefix")
    func testLaunchArgumentsHaveDashPrefix() {
        #expect(LaunchArguments.uiTesting.hasPrefix("-"))
        #expect(LaunchArguments.resetState.hasPrefix("-"))
        #expect(LaunchArguments.skipSeed.hasPrefix("-"))
    }

    @Test("LaunchArguments constants are non-empty")
    func testLaunchArgumentsAreNonEmpty() {
        #expect(!LaunchArguments.uiTesting.isEmpty)
        #expect(!LaunchArguments.resetState.isEmpty)
        #expect(!LaunchArguments.skipSeed.isEmpty)
    }
}

@Suite("TestEnvironment Tests")
struct TestEnvironmentTests {
    @Test("TestEnvironment.isRunningTests is true during unit test execution")
    func testIsRunningTestsIsTrueDuringTests() {
        // When unit tests execute, TestEnvironment should detect the test runner
        #expect(TestEnvironment.isRunningTests == true)
    }
}
