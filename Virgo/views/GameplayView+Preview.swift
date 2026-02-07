//
//  GameplayView+Preview.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

#if DEBUG
#Preview {
    let practiceSettings = PracticeSettingsService()
    let metronome = MetronomeEngine()
    GameplayView(
        chart: Song.sampleData.first!.charts.first!
    )
    .environmentObject(practiceSettings)
    .environmentObject(metronome)
}
#endif
