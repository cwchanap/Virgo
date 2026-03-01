//
//  TimingDeviationView.swift
//  Virgo
//
//  Shows average timing deviation and early/late tendency.
//

import SwiftUI

struct TimingDeviationView: View {
    let averageDeviation: Double?
    let earlyPercentage: Double
    let latePercentage: Double
    let tendency: TimingTendency

    var body: some View {
        VStack(spacing: 10) {
            Text("Timing")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let avg = averageDeviation {
                HStack(spacing: 8) {
                    // Direction arrow
                    Image(systemName: tendency == .early ? "arrow.left" : tendency == .late ? "arrow.right" : "minus")
                        .foregroundColor(tendencyColor)
                        .font(.caption.weight(.bold))

                    Text(String(format: "%+.1f ms", avg))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(.white)

                    Text(tendencyLabel)
                        .font(.caption)
                        .foregroundColor(tendencyColor)
                }

                // Early / Late split bar
                GeometryReader { geo in
                    let earlyWidth = (geo.size.width * CGFloat(max(0, earlyPercentage / 100.0))).rounded(.down)
                    let lateWidth = (geo.size.width * CGFloat(max(0, latePercentage / 100.0))).rounded(.down)
                    let neutralWidth = max(0, geo.size.width - earlyWidth - lateWidth)
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: earlyWidth)
                        Rectangle()
                            .fill(Color.orange.opacity(0.7))
                            .frame(width: lateWidth)
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: neutralWidth)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 8)

                HStack {
                    Label(String(format: "Early %.0f%%", earlyPercentage), systemImage: "arrow.left")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Spacer()
                    Label(String(format: "Late %.0f%%", latePercentage), systemImage: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            } else {
                Text("No timing data")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var tendencyColor: Color {
        switch tendency {
        case .early: return .blue
        case .late:  return .orange
        case .balanced: return .green
        }
    }

    private var tendencyLabel: String {
        switch tendency {
        case .early:    return "Tends Early"
        case .late:     return "Tends Late"
        case .balanced: return "Balanced"
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        TimingDeviationView(averageDeviation: -12.5, earlyPercentage: 65, latePercentage: 35, tendency: .early)
        TimingDeviationView(averageDeviation: 8.0, earlyPercentage: 30, latePercentage: 70, tendency: .late)
        TimingDeviationView(averageDeviation: 2.0, earlyPercentage: 48, latePercentage: 52, tendency: .balanced)
        TimingDeviationView(averageDeviation: nil, earlyPercentage: 0, latePercentage: 0, tendency: .balanced)
    }
    .padding()
    .background(Color.black)
}
