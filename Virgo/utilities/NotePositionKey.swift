//
//  NotePositionKey.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import Foundation

/// A key for uniquely identifying note positions in musical notation
struct NotePositionKey: Hashable, Equatable {
    let measureNumber: Int
    let measureOffset: Double
    
    /// Measure offset converted to milliseconds for precision
    var measureOffsetInMilliseconds: Int {
        return Int(measureOffset * 1000.0)
    }
    
    init(measureNumber: Int, measureOffset: Double) {
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(measureNumber)
        hasher.combine(measureOffsetInMilliseconds)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: NotePositionKey, rhs: NotePositionKey) -> Bool {
        return lhs.measureNumber == rhs.measureNumber &&
               lhs.measureOffsetInMilliseconds == rhs.measureOffsetInMilliseconds
    }
}
