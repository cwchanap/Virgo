import Foundation

/// Derives the app's canonical 4-bucket `Difficulty` from the backend's
/// free-form `label` plus numeric `level` (the backend has no Difficulty enum).
enum DifficultyClassifier {
    /// `level` is on the 0–100 scale (e.g. 36, 60, 74, 87) per the spec sample data.
    /// If the backend turns out to use a 0–9.99 scale, multiply by 10 before calling.
    static func classify(label: String, level: Int) -> Difficulty {
        switch label.uppercased() {
        case "BASIC": return .easy
        case "ADVANCED": return .medium
        case "EXTREME": return .hard
        case "MASTER", "REAL": return .expert
        default: return classifyByLevel(level)
        }
    }

    // Level thresholds on the 0–100 scale, derived from DTX spec sample data distribution:
    // easy = 0–34, medium = 35–54, hard = 55–74, expert = 75–100.
    private static func classifyByLevel(_ level: Int) -> Difficulty {
        switch level {
        case ..<35: return .easy
        case 35..<55: return .medium
        case 55..<75: return .hard
        default: return .expert
        }
    }
}
