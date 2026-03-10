import Testing
import Foundation
@testable import Virgo

@Suite("Logger Tests")
struct LoggerTests {
    private struct TestError: LocalizedError {
        var errorDescription: String? { "Logger test failure" }
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
}
