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

    private var color: Color {
        switch percentage {
        case 90...: return .green
        case 75...: return .yellow
        case 50...: return .orange
        default:    return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: animatedFraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: animatedFraction)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f%%", percentage))
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(.white)
                    Text("Accuracy")
                        .font(.caption2)
                        .foregroundColor(.gray)
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
    .background(Color.black)
}
