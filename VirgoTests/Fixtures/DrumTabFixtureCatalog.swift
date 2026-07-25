import Foundation
@testable import Virgo

/// Fixtures covering drum mapping, beaming, and flags.
/// Grid-resolution, rest, and wrapping fixtures live in
/// `DrumTabFixtureCatalog+Rhythm.swift` to stay under SwiftLint's file limit.
enum DrumTabFixtureCatalog {
    private static let header = """
    #TITLE: Virgo Drum Tab Fixture
    #ARTIST: Virgo Fixtures
    #BPM: 120
    #DLEVEL: 50
    """

    static func chart(_ lines: [String]) -> String {
        ([header] + lines).joined(separator: "\n")
    }

    /// Fixture 1: kick + snare + closed hi-hat struck together on beats 1 and 3.
    /// All three heads must land on one x column (HPA-141).
    static let sameTimeTrio = DrumTabFixture(
        name: "same-time-trio",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "13", at: [0, 2], total: 4),
            DrumTabFixture.line(measure: 1, lane: "12", at: [0, 2], total: 4),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0, 2], total: 4)
        ])
    )
}
