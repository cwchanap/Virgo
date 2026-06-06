import Testing
@testable import Virgo

@Suite("DifficultyClassifier Tests")
struct DifficultyClassifierTests {
    @Test("Known labels map case-insensitively")
    func testLabels() {
        #expect(DifficultyClassifier.classify(label: "BASIC", level: 0) == .easy)
        #expect(DifficultyClassifier.classify(label: "advanced", level: 0) == .medium)
        #expect(DifficultyClassifier.classify(label: "Extreme", level: 0) == .hard)
        #expect(DifficultyClassifier.classify(label: "MASTER", level: 0) == .expert)
        #expect(DifficultyClassifier.classify(label: "REAL", level: 0) == .expert)
    }

    @Test("Unknown labels fall back to level thresholds")
    func testLevelFallback() {
        #expect(DifficultyClassifier.classify(label: "???", level: 20) == .easy)
        #expect(DifficultyClassifier.classify(label: "???", level: 45) == .medium)
        #expect(DifficultyClassifier.classify(label: "???", level: 65) == .hard)
        #expect(DifficultyClassifier.classify(label: "???", level: 85) == .expert)
    }
}
