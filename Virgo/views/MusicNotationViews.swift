//
//  MusicNotationViews.swift
//  Virgo
//
//  Created by Chan Wai Chan on 12/7/2025.
//

import SwiftUI

// MARK: - Drum Clef Symbol
struct DrumClefSymbol: View {
    var body: some View {
        VStack(spacing: 4) {
            // Top rectangle
            Rectangle()
                .frame(width: 12, height: 8)
            
            // Middle rectangle
            Rectangle()
                .frame(width: 12, height: 8)
            
            // Bottom rectangle
            Rectangle()
                .frame(width: 12, height: 8)
        }
        .frame(width: 12, height: 32)
    }
}

// MARK: - Time Signature Symbol
struct TimeSignatureSymbol: View {
    let timeSignature: TimeSignature
    
    var body: some View {
        VStack(spacing: 2) {
            // Top number (beats per measure)
            Text("\(timeSignature.beatsPerMeasure)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(.white)
            
            // Bottom number (note value)
            Text("\(timeSignature.noteValue)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(.white)
        }
        .frame(width: 25, height: 50)
    }
}
