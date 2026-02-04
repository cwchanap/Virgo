//
//  GameplayView+Preview.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

#if DEBUG
#Preview {
    GameplayView(
        chart: Song.sampleData.first!.charts.first!,
        metronome: MetronomeEngine(),
        practiceSettings: PracticeSettingsService()
    )
    .environmentObject(PracticeSettingsService())
}
#endif
