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

    /// Fixture 2: a full 4/4 sixteenth run on closed hi-hat.
    /// Must beam as four beat-scoped groups, not one full-measure beam.
    ///
    /// Content lives in DTX measure 0 (not 1) with a one-note sentinel in
    /// measure 1. `NotationRhythmAnalyzer` cannot infer a duration for the
    /// last DTX onset in a voice (no following onset anywhere in the chart),
    /// so a chart's true final measure always resolves
    /// `.unsupported(indeterminateTerminalDuration)` — which suppresses
    /// every beam and flag in that measure, not just the one note. Putting
    /// the content in measure 0 gives its last note a follower (the
    /// sentinel), so measure 0 resolves `.supported`; the sentinel's own
    /// measure 1 becomes the new (untested) unsupported terminal measure.
    /// This also avoids the empty lead-in rest measure that content-in-1
    /// would add ahead of it (see `sameTimeTrio`'s golden), so the layout
    /// is exactly the two measures under test.
    static let sixteenthRun = DrumTabFixture(
        name: "sixteenth-run-4-4",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "11", at: Array(0..<16), total: 16),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1)
        ])
    )

    /// Fixture 3: each beat is an eighth plus two sixteenths (positions 0, 2, 3
    /// of the beat), forcing a primary beam plus a partial secondary beam.
    /// Same trailing-sentinel-measure structure as `sixteenthRun`, and for the
    /// same reason: measure 0 holds the content so its last onset has a
    /// follower and resolves `.supported`.
    static let mixedEighthSixteenth = DrumTabFixture(
        name: "mixed-eighth-sixteenth",
        dtx: chart([
            DrumTabFixture.line(
                measure: 0,
                lane: "11",
                at: (0..<4).flatMap { beat in [0, 2, 3].map { beat * 4 + $0 } },
                total: 16
            ),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1)
        ])
    )

    /// Fixture 11: one lone sixteenth (hi-hat) and one lone eighth (kick),
    /// each the only beamable note in its beat group, so each must render a
    /// flag rather than a zero-length beam. Added because fixtures 1–10 could
    /// all be satisfied by a renderer emitting zero flags: fixture 1 is
    /// quarters, fixture 2's sixteenths are fully beamed, fixture 3 beams
    /// within the beat.
    ///
    /// Both lone notes live in measure 0, on two different lanes/voices
    /// (hi-hat = upper, kick = lower), followed by a one-note-per-voice
    /// sentinel in measure 1. This is deliberate, not incidental: engraving
    /// support is scoped per DTX measure (see `sixteenthRun`'s doc comment on
    /// why a chart's true final measure always suppresses its own
    /// beams/flags), but *duration inference* for a "terminal" onset is
    /// scoped per voice and chases the next onset in that same voice,
    /// wherever it is. Two lone notes in the SAME voice, each needing to be
    /// the first onset of a fresh "early note, then evenly-spaced quarters"
    /// chain, cannot both live in one chart: the second one's incoming chain
    /// would need to land exactly on its early tick, which — one tick or two
    /// early — never lines up with the evenly-spaced quarters arriving from
    /// upstream (an earlier version of this fixture tried `0, 4, 10, 12` in a
    /// second same-voice measure; positions 4 and 10 are 6 ticks apart, which
    /// has no exact `NoteInterval` that also fits its own beat boundary, so
    /// that note resolves indeterminate and drags the whole measure
    /// unsupported). Two different voices sidestep this entirely: each gets
    /// its own independent "first onset of the chart" freedom.
    ///
    /// Hi-hat: notes at 3, 4, 8, 12 — position 3 is alone in beat 0 and one
    /// sixteenth (1 tick) from the next hi-hat note (position 4), so it is a
    /// lone flagged sixteenth. Positions 4, 8, 12 each sit at the start of
    /// their own beat, evenly 4 ticks (one quarter) apart, so each resolves
    /// as an ordinary supported quarter note, ending with a clean quarter-tick
    /// gap into measure 1's hi-hat sentinel.
    ///
    /// Kick: notes at 2, 4, 8, 12 — position 2 is alone in beat 0 and one
    /// eighth (2 ticks) from the next kick note (position 4), so it is a lone
    /// flagged eighth. Positions 4, 8, 12 mirror the hi-hat's quarter chain
    /// independently, ending with a clean quarter-tick gap into measure 1's
    /// kick sentinel.
    static let isolatedFlaggedNotes = DrumTabFixture(
        name: "isolated-flagged-notes",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "11", at: [3, 4, 8, 12], total: 16),
            DrumTabFixture.line(measure: 0, lane: "13", at: [2, 4, 8, 12], total: 16),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1),
            DrumTabFixture.line(measure: 1, lane: "13", at: [0], total: 1)
        ])
    )
}
