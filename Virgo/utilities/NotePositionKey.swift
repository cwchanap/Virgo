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

    /// Returns a canonical key where `measureOffset >= 1.0` is rolled into the next measure.
    ///
    /// A note at `(measureNumber: 1, measureOffset: 1.0)` and another at
    /// `(measureNumber: 2, measureOffset: 0.0)` represent the same musical instant.
    /// Both normalize to `(measureNumber: 2, measureOffset: 0.0)`.
    func normalized() -> NotePositionKey {
        guard measureOffset >= 1.0 else { return self }
        let timePosition = Double(measureNumber - 1) + measureOffset
        let normalizedIndex = Int(timePosition)
        let normalizedOffset = timePosition - Double(normalizedIndex)
        return NotePositionKey(
            measureNumber: MeasureUtils.toOneBasedNumber(normalizedIndex),
            measureOffset: normalizedOffset
        )
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
