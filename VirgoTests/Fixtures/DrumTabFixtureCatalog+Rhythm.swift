import Foundation
@testable import Virgo

/// Grid-resolution, rest, and row-wrapping fixtures. Split from
/// `DrumTabFixtureCatalog.swift` to stay under SwiftLint's 600-line limit.
extension DrumTabFixtureCatalog {
    /// Fixture 4: a 64-position grid carrying only two chips. Grid resolution is
    /// timing data, not note duration — these must not become 64th notes.
    ///
    /// Content lives in DTX measure 0 (not 1) to avoid the empty lead-in
    /// measure that content-in-1 would add ahead of it (see `sixteenthRun`'s
    /// doc comment); `result.layout.measures.first` would otherwise be that
    /// lead-in, not the measure under test.
    ///
    /// A one-note sentinel in measure 1 gives the tick-33 chip a same-voice
    /// follower. Measure 0 intentionally remains unsupported: 33/64 snaps to
    /// `.half`, while the tick-33 chip's remaining 31/64 span is neither a
    /// binary nor dotted duration. HPA-419 changes only the sentinel measure,
    /// whose single onset now resolves to an exact full-measure remainder.
    /// The content heads' positions and `.half` candidates remain the fixture's
    /// timing-resolution gate.
    static let sparseHiResLane = DrumTabFixture(
        name: "sparse-hi-res-lane",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "11", at: [0, 33], total: 64),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1)
        ])
    )

    /// Fixture 9: hi-hat (upper voice) and kick (lower voice) sound together
    /// in the SAME measure, each with its own leading rest of a different
    /// length, proving per-voice rest topology is computed independently
    /// even when both voices are active at once (not just "one voice active,
    /// one voice fully silent" -- see below for why that weaker shape was
    /// rejected).
    ///
    /// Hi-hat plays beats 2-4 (`at: [1, 2, 3]`) and kick plays beats 3-4
    /// (`at: [2, 3]`). `NotationRestTopologyBuilder.appendExactVoice`
    /// computes each voice's leading gap independently: hi-hat rests beat 1,
    /// while kick rests beats 1-2. The two voices' rest sets therefore differ
    /// in count and total ticks, so using one voice's onsets for the other
    /// would fail the gates below. The retained measure-1 sentinels provide
    /// explicit cross-measure evidence for measure 0; HPA-419 also lets both
    /// sentinel notes resolve as exact full-measure terminal durations.
    static let voiceRests = DrumTabFixture(
        name: "voice-rests",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "11", at: [1, 2, 3], total: 4),
            DrumTabFixture.line(measure: 0, lane: "13", at: [2, 3], total: 4),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1),
            DrumTabFixture.line(measure: 1, lane: "13", at: [0], total: 1)
        ])
    )

    /// Fixture 10: eight measures alternating dense (sixteenths) and sparse
    /// (one chip), which wraps to at least two rows at the locked 900pt row
    /// width. Serves as the subject of a follow-up task's spacing
    /// invariants: the same tick delta must produce the same x delta in a
    /// sparse and a dense measure.
    ///
    /// Content lives in DTX measures 0-7 (not 1-8) for the same reason as
    /// `sparseHiResLane`: content starting at measure 1 adds an empty
    /// lead-in measure 0 ahead of it (see `sixteenthRun`'s doc comment and
    /// `same-time-trio`'s golden), which would make this fixture actually
    /// materialize 9 layout measures, not the 8 asserted below.
    ///
    /// No sentinel is added here. This fixture's own gates (measure count,
    /// row-wrap count) are unaffected by engraving support: measure count
    /// and row assignment come from `TabGrid`/measure-width layout, which is
    /// pure geometry over tick positions, not from
    /// `NotationRhythmAnalyzer`'s duration inference.
    ///
    /// HPA-419 makes every measure in this fixture supported: each sparse
    /// onset uses its exact full-measure same-voice candidate, while the final
    /// dense measure resolves its last sixteenth from the terminal remainder.
    /// The fixture therefore exercises both sparse full-note engraving and
    /// dense stems/beams without a trailing sentinel.
    /// `minimumMeasureCount` is deliberately left at its default (1): DTX
    /// measures 0-7 already materialize 8 layout measures on their own, and
    /// padding to a floor of 8 would let a regression that drops trailing
    /// measures get silently topped back up to 8, defeating the
    /// `measures.count == 8` gate below.
    static let multiRowStableWidths = DrumTabFixture(
        name: "multi-row-stable-widths",
        dtx: chart((0...7).map { measure in
            measure.isMultiple(of: 2)
                ? DrumTabFixture.line(measure: measure, lane: "11", at: [0], total: 16)
                : DrumTabFixture.line(measure: measure, lane: "11", at: Array(0..<16), total: 16)
        })
    )

    /// Fixture 5: a 12-position (non-power-of-two) grid on one voice — four
    /// groups of eighth-note triplets (4 beats * 3 subdivisions). Grid
    /// resolution must not silently degrade a triplet chart to quarter notes
    /// or any other value that happens not to be `.unsupported`.
    ///
    /// Content lives in DTX measure 0 (not 1), with a one-note sentinel in
    /// measure 1 -- same shape as `sixteenthRun`. Content-in-1 would add an
    /// empty lead-in measure 0 ahead of it (see `sixteenthRun`'s doc comment
    /// and `same-time-trio`'s golden), which would make
    /// `snapshot.measures.first { $0.measureIndex == 0 }` resolve to that
    /// empty lead-in instead of the triplet measure under test.
    ///
    /// Measure 1 is a differential control, not a workaround for measure 0.
    /// Deleting it does not change the triplet content: measure 0 resolves
    /// `unsupported[incompleteTuplet,indeterminateTerminalDuration]` either
    /// way, because `resolveStream` scopes its `dtxOnsets` set to a single
    /// beat-group stream (`NotationRhythmAnalyzer.swift:208-210`), so the
    /// last onset of every triplet group reaches `terminalDTXResolution`
    /// regardless of what follows the measure.
    ///
    /// It earns its place by holding one plain full-measure note that must
    /// resolve `.supported`, proving `.incompleteTuplet` is caused by the
    /// 12-position content rather than stamped on every measure. The test
    /// pins both its presence and support state.
    ///
    /// The measure cannot currently be rescued into `.supported` at all.
    /// With a 12-position line and a 1-position control note, the resolved
    /// `ticksPerWholeNote` is 12 (`RhythmTimelineBuilder
    /// .resolvedTicksPerWholeNote`, `RhythmTimelineBuilder.swift:290-326` --
    /// LCM of the 4/4 meter factor (4) and the grid factor from a
    /// 12-position line (12) is 12). A regular (non-tuplet) eighth note
    /// needs `ticksPerWholeNote` to be a multiple of 8
    /// (`NotationRhythmAnalyzer.durationTicks(for:ticksPerWholeNote:)`,
    /// `NotationRhythmAnalyzer.swift:681-694`), so no eighth exists here
    /// even though `.quarter`/.half/.full do (3/6/12 ticks).
    ///
    /// `recognizeTuplets` (`NotationRhythmAnalyzer.swift:298-359`) then
    /// fails on both of its routes, which is why no candidate ever forms:
    /// - The eight onsets that have a following onset within their own
    ///   beat-group stream go through
    ///   `tripletBaseInterval(performedTicks:ticksPerWholeNote:)`
    ///   (`:669-673`), which needs `performedTicks * 3` to be even to land
    ///   back on an integer eighth. Each performed triplet-eighth is 1 tick
    ///   and `1 * 3 == 3` is odd, so it returns `nil`.
    /// - The four group-terminal onsets skip that parity check entirely --
    ///   `tripletBaseInterval(for:ticksPerWholeNote:)` (`:653-667`) returns
    ///   `visualDurationCandidate` directly when `hasFollowingDTXOnset` is
    ///   false (`:660`) -- but die one step later in
    ///   `tripletPerformedDuration` (`:640-651`), which also needs
    ///   `durationTicks(for:ticksPerWholeNote:)` to be non-nil. At
    ///   `ticksPerWholeNote == 12` that succeeds only for `.quarter`,
    ///   `.half`, and `.full` (divisors 4/2/1 divide 12). The candidate here
    ///   is `.sixteenth` -- `VisualDurationLookup.closestInterval` maps a
    ///   1-tick span to measure fraction 1/12 ~= 0.083, nearer `.sixteenth`
    ///   (0.0625) than `.eighth` (0.125) -- and 16 does not divide 12
    ///   (`:692`). So these onsets never enter `performedByIndex` and never
    ///   produce a slot to test.
    ///
    /// This is HPA-145, tracked via the golden's `# SUSPECT:` trailer: this
    /// fixture pins the documented fallback, not engraved triplets.
    static let tripletGrid = DrumTabFixture(
        name: "triplet-grid",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "11", at: Array(0..<12), total: 12),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1)
        ])
    )
}
