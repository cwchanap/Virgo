import Foundation

struct LiveScoreSnapshot: Equatable {
    let score: Int
    let currentCombo: Int
    let maxCombo: Int
    let perfectCount: Int
    let greatCount: Int
    let goodCount: Int
    let missCount: Int
    let hitAccuracy: Double
    let timingQuality: Double
    let averageTimingDeviation: Double?
    let earlyPercentage: Double
    let latePercentage: Double
    let timingTendency: TimingTendency

    static let empty = LiveScoreSnapshot(scoreEngine: ScoreEngine())

    init(scoreEngine: ScoreEngine) {
        self.score = scoreEngine.score
        self.currentCombo = scoreEngine.combo
        self.maxCombo = scoreEngine.maxCombo
        self.perfectCount = scoreEngine.perfectCount
        self.greatCount = scoreEngine.greatCount
        self.goodCount = scoreEngine.goodCount
        self.missCount = scoreEngine.missCount
        self.hitAccuracy = scoreEngine.accuracyPercentage
        self.timingQuality = Self.calculateTimingQuality(
            perfectCount: scoreEngine.perfectCount,
            greatCount: scoreEngine.greatCount,
            goodCount: scoreEngine.goodCount,
            missCount: scoreEngine.missCount
        )
        self.averageTimingDeviation = scoreEngine.averageTimingDeviation
        self.earlyPercentage = scoreEngine.earlyPercentage
        self.latePercentage = scoreEngine.latePercentage
        self.timingTendency = scoreEngine.timingTendency
    }

    var judgedNoteCount: Int {
        perfectCount + greatCount + goodCount + missCount
    }

    var hitAccuracyPercentText: String {
        Self.percentText(hitAccuracy)
    }

    var timingQualityPercentText: String {
        Self.percentText(timingQuality)
    }

    private static func calculateTimingQuality(
        perfectCount: Int,
        greatCount: Int,
        goodCount: Int,
        missCount: Int
    ) -> Double {
        let judgedNotes = perfectCount + greatCount + goodCount + missCount
        guard judgedNotes > 0 else { return 0.0 }

        let weightedHits = Double(perfectCount)
            + Double(greatCount) * TimingAccuracy.great.scoreMultiplier
            + Double(goodCount) * TimingAccuracy.good.scoreMultiplier
        return weightedHits / Double(judgedNotes) * 100.0
    }

    private static func percentText(_ value: Double) -> String {
        let normalizedValue = (value * 1_000_000).rounded() / 1_000_000
        return "\(Int(normalizedValue.rounded()))%"
    }
}
