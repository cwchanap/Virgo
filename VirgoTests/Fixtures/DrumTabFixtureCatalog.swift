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

    /// Fixture 6: open (18), closed (11), and pedal (1B) hi-hat must stay three
    /// distinct mappings rather than collapsing to one rendering. Note this is
    /// not distinguishable via (drumType, glyph) alone: open and closed hi-hat
    /// share `gameplayInstrument == .hiHat` (`DrumNotationCatalogTests` locks
    /// this equivalence directly), and all three share `glyph == .cross` in
    /// `DrumNotationCatalog.definitions` -- the articulation is carried purely
    /// by `variant` (`.openHiHat` / `.closedHiHat` / `.pedalHiHat`). The gate
    /// below checks (glyph, variant) pairs, not (drumType, glyph), so it
    /// actually fails if open/closed/pedal collapse to the same variant.
    /// No trailing sentinel measure: both gates read note-head glyph/variant,
    /// which are recorded regardless of the final measure's (always
    /// unsupported) engraving support -- see `sixteenthRun`'s doc comment.
    static let hiHatOpenClosedPedal = DrumTabFixture(
        name: "hihat-open-closed-pedal",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "18", at: [0], total: 4),
            DrumTabFixture.line(measure: 1, lane: "11", at: [1], total: 4),
            DrumTabFixture.line(measure: 1, lane: "1B", at: [2], total: 4)
        ])
    )

    /// Fixture 7: lane 1C (left bass) must actually reach the layout as a
    /// playable kick head, alongside a normal 13 kick, rather than being
    /// dropped by a `compactMap` along the import/layout path (HPA-139). Two
    /// kicks on different lanes at different ticks so a dropped 1C leaves an
    /// unambiguous count mismatch rather than an accidental match against the
    /// surviving 13 note. No trailing sentinel measure: the gate reads note
    /// head presence/lane/drumType, not beams, flags, or inferred duration.
    static let leftBass1C = DrumTabFixture(
        name: "left-bass-1c",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "13", at: [0], total: 4),
            DrumTabFixture.line(measure: 1, lane: "1C", at: [2], total: 4)
        ])
    )

    /// Fixture 8: stop (21), choke (22), and damp (23) control chips over a
    /// crash/hi-hat pattern. `controlBlock` is separable so the harness can
    /// render with and without it — proving control events do not feed rest
    /// inference (HPA-143), which a single render cannot demonstrate.
    ///
    /// Measure 1's crash (0, 2) and hi-hat (1, 3) chips fill all four upper-
    /// voice ticks, so the measure's only rest is the *unconditional*
    /// full-measure rest `NotationRestTopologyBuilder` emits for the (empty)
    /// lower voice -- that lower-voice rest is exactly what the differential
    /// needs: it disappears if a control chip is ever mistaken for a
    /// lower-voice onset. But `NotationLayoutEngine.layout(...)` drops
    /// *every* rest from a chart's true final measure once that measure
    /// resolves `.unsupported(...)`, via
    /// `snapshot.rests.filter { !unsupportedMeasureIndexes.contains(...) }`
    /// (`NotationLayoutEngine.swift:106-113`; see `sixteenthRun`'s doc
    /// comment on the terminal-measure trap, confirmed empirically against
    /// `same-time-trio`'s golden, which shows zero rest lines survive for
    /// its own final measure despite real gaps in its lower voice). Without
    /// a sentinel, measure 1 IS that final measure, its rest is stripped,
    /// and the only rests left in the digest are from the always-empty,
    /// control-free measure 0 lead-in -- a differential that would still
    /// read "non-empty" but could never actually detect a control-to-rest
    /// leak in measure 1.
    ///
    /// The measure-2 sentinel (a single hi-hat note, same *upper* voice as
    /// the content) fixes this by giving measure 1's last upper-voice onset
    /// (hi-hat, tick 3) a same-voice follower. Duration inference chases the
    /// next onset in the *same voice* only, scanning across measures
    /// (`VisualDurationLookup.candidates`, grouping by voice and mapping
    /// each tick to its next same-voice tick at `VisualDurationLookup.swift:
    /// 60-69`); with no follower at all, that onset falls through to the
    /// unconditional indeterminate fallback (`NotationRhythmAnalyzer.swift:
    /// 283-293`) and drags measure 1 unsupported. With the sentinel, that
    /// last onset gets an exact one-tick same-voice candidate and resolves
    /// `.supported` like its neighbors, so measure 1 keeps its own rest;
    /// measure 2 becomes the new (untested) unsupported terminal measure
    /// instead.
    static let stopChokeDamp = DrumTabFixture(
        name: "stop-choke-damp",
        dtx: chart([
            "#VIRGO_CONTROL: 1",
            DrumTabFixture.line(measure: 1, lane: "16", at: [0, 2], total: 4),
            DrumTabFixture.line(measure: 1, lane: "11", at: [1, 3], total: 4),
            DrumTabFixture.line(measure: 2, lane: "11", at: [0], total: 1)
        ]),
        controlBlock: [
            DrumTabFixture.line(measure: 1, lane: "21", positions: [0: "16"], total: 4),
            DrumTabFixture.line(measure: 1, lane: "22", positions: [2: "16"], total: 4),
            DrumTabFixture.line(measure: 1, lane: "23", positions: [3: "11"], total: 4)
        ].joined(separator: "\n")
    )

    /// Every fixture, for parameterized invariant tests
    /// (`DrumTabRegressionInvariantTests`).
    static let all: [DrumTabFixture] = [
        sameTimeTrio, sixteenthRun, mixedEighthSixteenth, sparseHiResLane,
        tripletGrid, hiHatOpenClosedPedal, leftBass1C, stopChokeDamp,
        voiceRests, multiRowStableWidths, isolatedFlaggedNotes
    ]
}
