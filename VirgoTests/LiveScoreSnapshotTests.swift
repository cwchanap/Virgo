import Testing
@testable import Virgo

@Suite("LiveScoreSnapshot Tests")
struct LiveScoreSnapshotTests {
    @Test("empty snapshot returns zeroed display stats")
    func emptySnapshotReturnsZeroes() {
        let snapshot = LiveScoreSnapshot(scoreEngine: ScoreEngine())

        #expect(snapshot.score == 0)
        #expect(snapshot.currentCombo == 0)
        #expect(snapshot.maxCombo == 0)
        #expect(snapshot.judgedNoteCount == 0)
        #expect(snapshot.hitAccuracy == 0.0)
        #expect(snapshot.timingQuality == 0.0)
        #expect(snapshot.hitAccuracyPercentText == "0%")
        #expect(snapshot.timingQualityPercentText == "0%")
    }

    @Test("snapshot exposes score combo and counts from ScoreEngine")
    func snapshotExposesScoreComboAndCounts() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        engine.processHit(accuracy: .great, timingError: 20.0)
        engine.processHit(accuracy: .good, timingError: 50.0)
        engine.processHit(accuracy: .miss)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        #expect(snapshot.score == engine.score)
        #expect(snapshot.currentCombo == engine.combo)
        #expect(snapshot.maxCombo == engine.maxCombo)
        #expect(snapshot.perfectCount == 1)
        #expect(snapshot.greatCount == 1)
        #expect(snapshot.goodCount == 1)
        #expect(snapshot.missCount == 1)
        #expect(snapshot.judgedNoteCount == 4)
    }

    @Test("hit accuracy counts non-miss hits over all judged notes")
    func hitAccuracyUsesNonMissOverJudgedNotes() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .good)
        engine.processHit(accuracy: .miss)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        #expect(abs(snapshot.hitAccuracy - 75.0) < 0.001)
        #expect(snapshot.hitAccuracyPercentText == "75%")
    }

    @Test("timing quality uses weighted perfect great good and miss values")
    func timingQualityUsesWeightedCounts() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .good)
        engine.processHit(accuracy: .miss)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        // (1.0 + 0.8 + 0.5 + 0.0) / 4 * 100 = 57.5
        #expect(abs(snapshot.timingQuality - 57.5) < 0.001)
        #expect(snapshot.timingQualityPercentText == "58%")
    }

    @Test("snapshot carries timing deviation fields")
    func snapshotCarriesTimingFields() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -20.0)
        engine.processHit(accuracy: .great, timingError: 10.0)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        #expect(snapshot.averageTimingDeviation != nil)
        #expect(snapshot.earlyPercentage == engine.earlyPercentage)
        #expect(snapshot.latePercentage == engine.latePercentage)
        #expect(snapshot.timingTendency == engine.timingTendency)
    }
}
