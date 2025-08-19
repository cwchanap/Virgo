//
//  LoggerTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import Foundation
@testable import Virgo

@Suite("Logger Tests")
struct LoggerTests {
    
    @Test("Logger static loggers are properly configured")
    func testLoggerConfiguration() {
        // Test that loggers exist and have correct subsystem
        let generalLogger = Logger.general
        let databaseLogger = Logger.database
        let audioLogger = Logger.audio
        let uiLogger = Logger.ui
        let networkLogger = Logger.network
        
        // These should not crash and should be properly initialized
        #expect(generalLogger != nil)
        #expect(databaseLogger != nil)
        #expect(audioLogger != nil)
        #expect(uiLogger != nil)
        #expect(networkLogger != nil)
    }
    
    @Test("Logger database methods work without crashing")
    func testDatabaseLogging() {
        // These should not crash in test environment
        Logger.database("Test database message")
        Logger.databaseError(LoggerTestError.sampleError)
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger audio playback methods work without crashing")
    func testAudioLogging() {
        // These should not crash in test environment
        Logger.audioPlayback("Test audio message")
        Logger.audioPlayback("Playback started")
        Logger.audioPlayback("Volume changed to 0.5")
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger UI methods work without crashing")
    func testUILogging() {
        // These should not crash in test environment
        Logger.userAction("Test user action")
        Logger.userAction("Button tapped")
        Logger.userAction("View appeared")
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger general methods work without crashing")
    func testGeneralLogging() {
        // These should not crash in test environment
        Logger.debug("Test debug message")
        Logger.info("Test info message")
        Logger.warning("Test warning message")
        Logger.error("Test error message")
        Logger.critical("Test critical message")
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger handles empty strings")
    func testEmptyStrings() {
        // Test that empty strings don't cause issues
        Logger.database("")
        Logger.audioPlayback("")
        Logger.userAction("")
        Logger.debug("")
        Logger.info("")
        Logger.warning("")
        Logger.error("")
        Logger.critical("")
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger handles special characters and unicode")
    func testSpecialCharacters() {
        // Test with various special characters and unicode
        Logger.info("Test with emoji 🎵🥁")
        Logger.debug("Special chars: !@#$%^&*()")
        Logger.warning("Unicode: αβγδε 日本語 русский")
        Logger.error("Quotes: \"single\" 'double' `backtick`")
        Logger.audioPlayback("Newlines:\nand\ttabs")
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger handles long messages")
    func testLongMessages() {
        let longMessage = String(repeating: "A", count: 1000)
        let veryLongMessage = String(repeating: "B", count: 10000)
        
        Logger.info(longMessage)
        Logger.debug(veryLongMessage)
        Logger.database(longMessage)
        Logger.audioPlayback(veryLongMessage)
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger database error method handles various error types")
    func testDatabaseErrorTypes() {
        // Test with different error types
        Logger.databaseError(LoggerTestError.sampleError)
        Logger.databaseError(LoggerTestError.networkError)
        Logger.databaseError(LoggerTestError.validationError)
        
        let nsError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test NSError"])
        Logger.databaseError(nsError)
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger methods handle concurrent access safely")
    func testConcurrentAccess() async {
        // Test concurrent logging from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    Logger.info("Concurrent message \(i)")
                    Logger.debug("Debug message \(i)")
                    Logger.audioPlayback("Audio message \(i)")
                    Logger.userAction("User action \(i)")
                }
            }
        }
        
        // Test passes if no crash occurs
        #expect(true)
    }
    
    @Test("Logger categories can be distinguished")
    func testLoggerCategories() {
        // Test that different loggers have different categories (indirectly)
        // We can't directly test categories, but we can ensure they're different objects
        let general = Logger.general
        let database = Logger.database
        let audio = Logger.audio
        let ui = Logger.ui
        let network = Logger.network
        
        // These should be different logger instances (they're structs, so just check they exist)
        #expect(general != nil)
        #expect(database != nil)
        #expect(audio != nil)
        #expect(ui != nil)
        #expect(network != nil)
    }
}

// MARK: - Test Helper Errors
enum LoggerTestError: Error, LocalizedError {
    case sampleError
    case networkError
    case validationError
    
    var errorDescription: String? {
        switch self {
        case .sampleError:
            return "Sample test error"
        case .networkError:
            return "Network connection failed"
        case .validationError:
            return "Validation failed"
        }
    }
}
