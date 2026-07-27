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

    /// Fixture 9: hi-hat (upper voice) and kick (lower voice) sound together
    /// in the SAME measure, each with its own leading rest of a different
    /// length, proving per-voice rest topology is computed independently
    /// even when both voices are active at once (not just "one voice active,
    /// one voice fully silent" -- see below for why that weaker shape was
    /// rejected).
    ///
    /// An onset resolves `.supported` when
    /// `localTick + durationTicks(closestInterval(gap)) <= min(beatGroup
    /// .endTick, measure.durationTicks)` (`NotationRhythmAnalyzer
    /// .terminalDTXResolution`, `NotationRhythmAnalyzer.swift:248-294`,
    /// boundary at `:254`) whenever it has no later onset of the same voice
    /// within its own beat group (`resolveStream`,
    /// `NotationRhythmAnalyzer.swift:203-246`). `closestInterval` picks the
    /// nearest of the seven supported fractions to the raw gap
    /// (`VisualDurationLookup.closestInterval`), so this can succeed even
    /// when the gap is not literally one quarter note -- e.g. a 5-tick gap
    /// out of 16 snaps DOWN to `.quarter` (4 ticks), not up to some
    /// unsupported "5/16" interval, and that snapped-down duration is what
    /// has to fit the boundary. A beat group is always exactly one quarter
    /// note wide in 4/4 (`RhythmBeatGroupBuilder.standardBeatGroupDuration`),
    /// so in practice this only leaves room for the next same-voice onset to
    /// be at most one quarter-note's worth of ticks later.
    ///
    /// The brief's original shape packed both voices into one measure
    /// (hi-hat beats 1-2, kick beats 3-4). Kick's half is fine in isolation
    /// -- a leading rest (beats 1-2) before content that reaches the
    /// measure's last beat, the same safe, established
    /// last-beat-plus-next-measure-sentinel shape `sixteenthRun` and
    /// `stopChokeDamp` already use. Hi-hat's half is not: its last onset
    /// (beat 2) is followed by an in-measure rest (beats 3-4) that does NOT
    /// reach the measure's end, so its only candidate gap (to a same-voice
    /// onset at least two beats later) snaps to `.half` (2 ticks), and
    /// `1 (localTick) + 2 (duration) = 3 > 2 (its own beat group's
    /// boundary)` -- it does not fit, no matter where a same-voice sentinel
    /// is placed, because nothing can shrink hi-hat's own gap to fit inside
    /// one beat group once kick occupies beats 3-4. Because a single
    /// indeterminate onset poisons the WHOLE measure regardless of any
    /// other onset's own validity (`NotationRhythmAnalyzer
    /// .applyConservativeFallback`, `NotationRhythmAnalyzer.swift:537-564`),
    /// hi-hat's one unrescuable onset drags kick's otherwise-fine half down
    /// too, and once a measure is unsupported,
    /// `NotationRestTopologyBuilder.appendExactGap` only emits
    /// `.hiddenSpacing`/`.indeterminate` gaps, never `.printed` ones
    /// (`NotationRestTopology.swift:672-693`). So the brief's exact shape
    /// would always end up with zero printed rests for either voice.
    ///
    /// This fixture keeps both voices in one measure but starts each one on
    /// a DIFFERENT beat, so each voice's own onset-to-onset gaps stay
    /// within one beat group the whole way through (never needing a gap
    /// longer than one quarter note): hi-hat plays beats 2-4
    /// (`at: [1, 2, 3]`) and kick plays beats 3-4 (`at: [2, 3]`). Every
    /// onset is either immediately followed by the next same-voice onset
    /// one tick later, or is the true last beat of the measure and picks up
    /// its own same-voice sentinel one tick into measure 1 -- both voices'
    /// sentinels live there together, at tick 0, on their own lanes. That
    /// keeps measure 0 fully `.supported` with both voices sounding, so
    /// `NotationRestTopologyBuilder.appendExactVoice`
    /// (`NotationRestTopology.swift:564-567`, gated per-voice by the
    /// `$0.voice == voice` filter at `:567`) computes each voice's own
    /// leading rest independently: hi-hat rests only beat 1 (one printed
    /// quarter rest, tick 0), kick rests beats 1-2 (two printed quarter
    /// rests, ticks 0 and 1 -- rests are computed per beat group and never
    /// merged across a beat-group boundary, per `appendExactVoice`'s
    /// `for group in measure.beatGroups` loop, `NotationRestTopology.swift:
    /// 626-658`, so a two-beat-wide leading gap is two one-beat rest events,
    /// not one half-note rest). The two voices' rest sets differ in both
    /// count and total ticks, so a regression that computed one voice's
    /// gaps from the other voice's onsets (e.g. dropping the `voice ==`
    /// filter above) would make them match and fail the gates below.
    /// Measure 1 (both sentinels, no further followers) predictably
    /// resolves `.unsupported(indeterminateTerminalDuration)`, same as
    /// every other chart's true final measure in this catalog -- nothing
    /// under test lives there.
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
    /// The sentinel does NOT change this fixture's verdict today, and the
    /// doc comment says so on purpose. Measured directly by deleting the
    /// sentinel line and re-recording: measure 0 resolves
    /// `unsupported[incompleteTuplet,indeterminateTerminalDuration]` either
    /// way. Do not cite it as protection against the terminal-measure trap
    /// the way `sixteenthRun` and `stopChokeDamp` legitimately do -- at this
    /// grid the indeterminate code has a different cause (see below).
    ///
    /// It is kept because it is load-bearing for the *future*: when HPA-145
    /// is fixed and `recognizeTuplets` can form a candidate here, measure 0
    /// still has to avoid being the chart's terminal measure or it would
    /// stay `.unsupported` for the unrelated reason and this fixture could
    /// never reach its `.supported` branch — the branch that asserts
    /// triplets actually engrave. The test pins the sentinel (note count 13
    /// and a required `measureIndex == 1`) so it cannot be quietly dropped.
    ///
    /// The measure cannot currently be rescued into `.supported` at all:
    /// with only a
    /// 12-position line and a 1-position sentinel in the chart, the resolved
    /// `ticksPerWholeNote` is 12 (`RhythmTimelineBuilder
    /// .resolvedTicksPerWholeNote`, `RhythmTimelineBuilder.swift:290-326` --
    /// LCM of the 4/4 meter factor (4) and the grid factor from a
    /// 12-position line (12) is 12). A regular (non-tuplet) eighth note
    /// needs `ticksPerWholeNote` to be a multiple of 8
    /// (`NotationRhythmAnalyzer.durationTicks(for:ticksPerWholeNote:)`,
    /// `NotationRhythmAnalyzer.swift:681-694`), and the triplet-to-base
    /// conversion in `tripletBaseInterval(performedTicks:ticksPerWholeNote:)`
    /// (`NotationRhythmAnalyzer.swift:669-673`) requires
    /// `performedTicks * 3` to be even to land back on that integer eighth.
    /// At `ticksPerWholeNote == 12`, each performed triplet-eighth is 1
    /// tick, and `1 * 3 == 3` is odd, so that conversion always returns
    /// `nil` -- `recognizeTuplets` (`NotationRhythmAnalyzer.swift:298-359`)
    /// can never form a candidate here, independent of the sentinel. This
    /// is HPA-145, tracked via the golden's `# SUSPECT:` trailer: this
    /// fixture pins the documented fallback, not engraved triplets.
    static let tripletGrid = DrumTabFixture(
        name: "triplet-grid",
        dtx: chart([
            DrumTabFixture.line(measure: 0, lane: "11", at: Array(0..<12), total: 12),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1)
        ])
    )
}
