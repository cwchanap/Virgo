//
//  MeasureUtils.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import Foundation

struct MeasureUtils {
    /// Converts zero-based index to one-based measure number
    static func toOneBasedNumber(_ zeroBasedIndex: Int) -> Int {
        return zeroBasedIndex + 1
    }
    
    /// Converts one-based measure number to zero-based index
    static func toZeroBasedIndex(_ oneBasedNumber: Int) -> Int {
        return oneBasedNumber - 1
    }
    
    /// Calculates time position from measure number and offset
    /// - Parameters:
    ///   - measureNumber: One-based measure number (1, 2, 3, etc.)
    ///   - measureOffset: Offset within measure (0.0 to 1.0)
    /// - Returns: Absolute time position
    static func timePosition(measureNumber: Int, measureOffset: Double) -> Double {
        let measureIndex = toZeroBasedIndex(measureNumber)
        return Double(measureIndex) + measureOffset
    }
    
    /// Extracts measure index from time position
    /// - Parameter timePosition: Absolute time position
    /// - Returns: Zero-based measure index
    static func measureIndex(from timePosition: Double) -> Int {
        return Int(timePosition)
    }
}
