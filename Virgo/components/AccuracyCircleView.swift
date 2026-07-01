//
//  AccuracyCircleView.swift
//  Virgo
//
//  Circular progress ring showing session accuracy percentage.
//

import SwiftUI

struct AccuracyCircleView: View {
    let percentage: Double  // 0.0–100.0

    @State private var animatedFraction: Double = 0.0

    /// Stroke color chosen from accuracy tiers so the ring reflects performance
    /// at a glance instead of always using the vermillion accent.
    private var ringColor: Color {
        if percentage >= 85 {
            return Palette.chalk       // high accuracy → bright
        } else if percentage >= 60 {
            return Palette.vermillion  // mid accuracy → accent
        } else {
            return Palette.chalkMuted  // low accuracy → muted
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Palette.chalkMuted.opacity(0.3), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: animatedFraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: animatedFraction)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f%%", percentage))
                        .font(.plexMono(20, weight: .bold))
                        .foregroundColor(Palette.chalk)
                    Text("Accuracy")
                        .font(.plexMono(9, weight: .medium))
                        .tracking(1)
                        .foregroundColor(Palette.chalkMuted)
                }
            }
            .frame(width: 120, height: 120)
        }
        .onAppear {
            animatedFraction = min(percentage / 100.0, 1.0)
        }
    }
}

#Preview {
    HStack(spacing: 32) {
        AccuracyCircleView(percentage: 95.0)
        AccuracyCircleView(percentage: 72.5)
        AccuracyCircleView(percentage: 40.0)
    }
    .padding()
    .background(Palette.stage)
}
