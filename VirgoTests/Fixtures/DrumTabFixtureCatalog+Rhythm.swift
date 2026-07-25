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
    /// follower. It does not change which measure engraving support lands
    /// on: the tick-0 chip's own inferred candidate (`.half`, from its
    /// distance to tick 33 — the closest of the seven supported fractions to
    /// 33/64 ≈ 0.516) already cannot fit inside its own beat group (a
    /// quarter-note-wide window, `RhythmBeatGroupBuilder.standardBeatGroupDuration`
    /// for 4/4), so `NotationRhythmAnalyzer.terminalDTXResolution`
    /// (`NotationRhythmAnalyzer.swift:248-294`) marks it indeterminate
    /// regardless of the sentinel, and that alone drags measure 0 to
    /// `.unsupported` (`NotationRhythmAnalyzer.swift:537-564`, whole-measure,
    /// not per-note). The sentinel exists only so the tick-33 chip's own
    /// `interval` also reflects a real distance-derived classification
    /// (`.half`, same as tick-0's) instead of the arbitrary `.quarter`
    /// terminal-fallback default it would otherwise get — both notes'
    /// `interval` values are then genuinely spacing-derived, not
    /// coincidentally non-64th because the fallback constant happens not to
    /// be `.sixtyfourth`.
    ///
    /// This does not weaken the gates: `noteHeads`, `timeColumn`, and
    /// `interval` (`RenderedNoteHead.interval` / `note.rhythm.baseInterval`,
    /// `NotationRhythmAnalyzer.swift:556-559` preserves `baseInterval` when a
    /// measure is marked unsupported, only wrapping `support`) are untouched
    /// by unsupported-measure filtering — only rests/flags/beams are
    /// (`NotationLayoutEngine.swift:106-113,199-200` and beam construction).
    static let sparseHiResLane = DrumTabFixture(
        name: "sparse-hi-res-lane",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "11", at: [0, 33], total: 64),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1)
        ])
    )

    /// Fixture 9: hi-hat (upper voice) and kick (lower voice) each need an
    /// independently-computed printed rest, proving rests are not shared or
    /// conflated across voices.
    ///
    /// The brief's original shape packed both voices into one measure
    /// (hi-hat beats 1-2, kick beats 3-4). Kick's own half of that shape is
    /// fine in isolation -- a leading rest (beats 1-2) before content that
    /// reaches the measure's last beat, the same safe, established
    /// last-beat-plus-next-measure-sentinel shape `sixteenthRun` and
    /// `stopChokeDamp` already use. Hi-hat's half is not: its last onset
    /// (beat 2) is followed by an in-measure rest (beats 3-4) that does NOT
    /// reach the measure's end, and no same-voice follower can be placed
    /// close enough to rescue it without colliding with kick's own beats
    /// 3-4 content. `NotationRhythmAnalyzer.terminalDTXResolution` only
    /// accepts a "terminal in its own beat group" onset (no later onset of
    /// the same voice within that one beat group -- `resolveStream`,
    /// `NotationRhythmAnalyzer.swift:203-246`) when its inferred duration
    /// fits inside the REMAINDER of that same beat group
    /// (`boundary = min(beatGroup.endTick, measure.durationTicks)`,
    /// `NotationRhythmAnalyzer.swift:254`). A beat group is always exactly
    /// one quarter note wide in 4/4
    /// (`RhythmBeatGroupBuilder.standardBeatGroupDuration`), so this only
    /// succeeds when the next same-voice onset is exactly one quarter later
    /// (i.e. no rest at all) or when the onset is the last beat of its own
    /// measure and picks up a same-voice sentinel exactly one quarter into
    /// the next measure -- hi-hat's beat-2 onset satisfies neither. And
    /// because a single indeterminate onset poisons the WHOLE measure,
    /// regardless of any other onset's own validity
    /// (`NotationRhythmAnalyzer.applyConservativeFallback`,
    /// `NotationRhythmAnalyzer.swift:537-564`), hi-hat's one unrescuable
    /// onset is enough to drag kick's otherwise-fine half down too. Once a
    /// measure is unsupported, `NotationRestTopologyBuilder.appendExactGap`
    /// only emits `.hiddenSpacing`/`.indeterminate` gaps, never `.printed`
    /// ones (`NotationRestTopology.swift:672-693`). So the brief's shape
    /// would always end up with zero printed rests for either voice.
    ///
    /// This fixture instead gives each voice its OWN measure where it is the
    /// only active voice, ending on beats 3-4 (the safe, established
    /// last-beats-plus-next-measure-sentinel shape used by `sixteenthRun`
    /// and `stopChokeDamp`): a full run of beats-3-4 content always resolves
    /// `.supported` (each onset is either immediately followed by the next
    /// same-voice onset one tick later, or is the true last beat of the
    /// measure and picks up its own sentinel one tick into the next
    /// measure). With one voice `.supported` and the other voice completely
    /// silent for that whole measure,
    /// `NotationRestTopologyBuilder.buildExact`'s automatic full-measure rest
    /// for the silent voice (`NotationRestTopology.swift:550-563`) is
    /// unconditionally `.printed` when the OTHER voice is non-empty (upper:
    /// always `.printed` when empty; lower: `.printed` whenever upper is
    /// non-empty, `.hiddenDuplicate` only when both are empty). Measure 0
    /// (kick active, hi-hat silent) prints hi-hat's (upper) rest; measure 2
    /// (hi-hat active, kick silent) prints kick's (lower) rest. Measures 1
    /// and 3 are pure one-note sentinels (grid 1) that rescue measure 0's
    /// and measure 2's own last onsets respectively, exactly like
    /// `sixteenthRun`'s trailing sentinel; measure 3's own onset is in turn
    /// the chart's true final onset and predictably resolves
    /// `.unsupported(indeterminateTerminalDuration)`, which is fine because
    /// nothing under test lives there.
    static let voiceRests = DrumTabFixture(
        name: "voice-rests",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "13", at: [2, 3], total: 4),
            DrumTabFixture.line(measure: 1, lane: "13", at: [0], total: 1),
            DrumTabFixture.line(measure: 2, lane: "11", at: [2, 3], total: 4),
            DrumTabFixture.line(measure: 3, lane: "11", at: [0], total: 1)
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
    /// Empirically (verified against this fixture's own golden), every
    /// sparse measure resolves `.unsupported(indeterminateTerminalDuration)`
    /// -- not just the true final measure (7): a sparse measure's one onset
    /// is terminal in its own beat group, and its only candidate follower is
    /// a full measure away (the next measure's first onset), which can never
    /// fit inside a quarter-note-wide beat-group boundary (the same
    /// mechanism documented on `voiceRests`). Every dense measure except the
    /// true final one (7) resolves `.supported`, because its sixteenths
    /// chain adjacently all the way through. So this fixture, as built,
    /// contains zero *supported* sparse measures. A future spacing-invariant
    /// test that only compares note X-positions across a sparse/dense pair
    /// can safely use any pair, including measure 7 -- `TabGrid.xPosition`
    /// reads tick position only and is untouched by engraving support. One
    /// that also needs beam data for the SPARSE side of the pair cannot get
    /// it from this fixture at all without adding its own sentinel.
    static let multiRowStableWidths = DrumTabFixture(
        name: "multi-row-stable-widths",
        dtx: chart((0...7).map { measure in
            measure.isMultiple(of: 2)
                ? DrumTabFixture.line(measure: measure, lane: "11", at: [0], total: 16)
                : DrumTabFixture.line(measure: measure, lane: "11", at: Array(0..<16), total: 16)
        }),
        minimumMeasureCount: 8
    )
}
