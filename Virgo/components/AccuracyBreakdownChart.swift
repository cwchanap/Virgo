//
//  AccuracyBreakdownChart.swift
//  Virgo
//
//  Bar chart showing Perfect / Great / Good / Miss note distribution.
//

import Charts
import SwiftUI

struct AccuracyBreakdownChart: View {
    let perfectCount: Int
    let greatCount: Int
    let goodCount: Int
    let missCount: Int

    private struct TierData: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
    }

    private var data: [TierData] {
        [
            TierData(label: "Perfect", count: perfectCount, color: .cyan),
            TierData(label: "Great",   count: greatCount,   color: .green),
            TierData(label: "Good",    count: goodCount,    color: .yellow),
            TierData(label: "Miss",    count: missCount,    color: .red)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hit Breakdown")
                .font(.caption)
                .foregroundColor(.gray)

            Chart(data) { tier in
                BarMark(
                    x: .value("Tier", tier.label),
                    y: .value("Count", tier.count)
                )
                .foregroundStyle(tier.color)
                .annotation(position: .top, alignment: .center) {
                    Text("\(tier.count)")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 100)
        }
    }
}

#Preview {
    AccuracyBreakdownChart(perfectCount: 15, greatCount: 8, goodCount: 3, missCount: 2)
        .padding()
        .background(Color.black)
}
