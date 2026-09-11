import Testing
import DrumNotation

@Test("public DrumNotation module imports without Virgo")
func packageImports() {
    #expect(NotationDuration.quarter.rawValue == "quarter")
}
