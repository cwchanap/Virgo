import SwiftUI

enum DifficultyPipScale {
    static let total = 5
    static func filled(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: return 2
        case .medium: return 3
        case .hard: return 4
        case .expert: return 5
        }
    }
}

/// Vermillion pip meter + small-caps label. Replaces the colored DifficultyBadge.
struct DifficultyPips: View {
    let difficulty: Difficulty
    var showLabel: Bool = true
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 2) {
                ForEach(0..<DifficultyPipScale.total, id: \.self) { index in
                    Circle()
                        .fill(index < DifficultyPipScale.filled(for: difficulty) ? theme.accent : theme.rule)
                        .frame(width: 5, height: 5)
                }
            }
            if showLabel {
                Text(difficulty.rawValue.uppercased())
                    .font(.plexMono(10, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(theme.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(difficulty.rawValue) difficulty")
    }
}
