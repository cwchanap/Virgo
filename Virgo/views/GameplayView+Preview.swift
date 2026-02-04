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
    GameplayView(
        chart: Song.sampleData.first!.charts.first!,
        metronome: MetronomeEngine(),
        practiceSettings: practiceSettings
    )
    .environmentObject(practiceSettings)
}
#endif
