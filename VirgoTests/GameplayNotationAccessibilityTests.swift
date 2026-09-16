//
//  GameplayNotationAccessibilityTests.swift
//  VirgoTests
//
//  VoiceOver label coverage for the app-owned presentation boundary
//  (HPA-166 Task 7 review): every label the package `DrumNotationView`
//  resolves per `NotationSemanticID` is built by `GameplayNotationPreparer`
//  from explicit localized mappings — no raw English rawValues cross into
//  the strings VoiceOver speaks.
//

import Testing
import Foundation
import DrumNotation
@testable import Virgo

@Suite("Gameplay notation accessibility labels", .serialized)
@MainActor
struct GameplayNotationAccessibilityTests {
    private let support = NotationSnapshotTestSupport()

    @Test("rest labels carry the localized voice and duration names")
    func restLabelsCarryLocalizedVoiceAndDuration() throws {
        let (engraved, presentation) = try support.requireReady(support.prepare(
            rests: [
                RhythmLayoutRest(
                    position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                    durationTicks: 240,
                    voice: .upper,
                    rhythm: NotationRhythm(baseInterval: .quarter),
                    visibility: .printed,
                    tupletID: nil
                ),
                RhythmLayoutRest(
                    position: RhythmEventPosition(measureIndex: 0, localTick: 480, absoluteTick: 480),
                    durationTicks: 480,
                    voice: .lower,
                    rhythm: NotationRhythm(baseInterval: .half),
                    visibility: .printed,
                    tupletID: nil
                )
            ]
        ))

        let labelsByRestID = Dictionary(
            uniqueKeysWithValues: engraved.rests.map { ($0.restID, presentation.accessibilityLabels[.rest($0.restID)]) }
        )
        let upperRest = try #require(engraved.rests.first { $0.voice == .upper })
        let lowerRest = try #require(engraved.rests.first { $0.voice == .lower })

        #expect(labelsByRestID[upperRest.restID] == "Upper voice quarter rest")
        #expect(labelsByRestID[lowerRest.restID] == "Lower voice half rest")
        // Every engraved rest must resolve a label — an unmapped duration or
        // voice would leave a nil entry here.
        #expect(labelsByRestID.values.allSatisfy { $0 != nil })
    }

    @Test("full-measure rest label uses the localized full-measure wording")
    func fullMeasureRestLabelUsesFullMeasureWording() throws {
        let (engraved, presentation) = try support.requireReady(support.prepare(
            rests: [
                RhythmLayoutRest(
                    position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                    durationTicks: 960,
                    voice: .upper,
                    rhythm: NotationRhythm(baseInterval: .full),
                    visibility: .printed,
                    tupletID: nil
                )
            ]
        ))

        let rest = try #require(engraved.rests.first)
        #expect(presentation.accessibilityLabels[.rest(rest.restID)] == "Upper voice full-measure rest")
    }

    @Test("tuplet labels carry the localized voice and ratio wording")
    func tupletLabelsCarryLocalizedVoiceAndRatio() throws {
        let (engraved, presentation) = try support.requireReady(
            tripletPreparation(voice: .upper)
        )

        let tuplet = try #require(engraved.tuplets.first)
        #expect(tuplet.ratio.actual == 3 && tuplet.ratio.normal == 2)
        #expect(
            presentation.accessibilityLabels[.tuplet(tuplet.tupletID)]
                == "Upper voice tuplet, 3 in the time of 2"
        )
    }

    @Test("lower-voice tuplet labels use the lower voice name")
    func lowerVoiceTupletLabelUsesLowerVoiceName() throws {
        let (engraved, presentation) = try support.requireReady(
            tripletPreparation(voice: .lower)
        )

        let tuplet = try #require(engraved.tuplets.first)
        #expect(tuplet.voice == .lower)
        #expect(
            presentation.accessibilityLabels[.tuplet(tuplet.tupletID)]
                == "Lower voice tuplet, 3 in the time of 2"
        )
    }

    @Test("control labels carry the localized kind and target instrument names")
    func controlLabelsCarryLocalizedKindAndTarget() throws {
        let (engraved, presentation) = try support.requireReady(support.prepare(
            controls: [
                NotationControlEvent(ChartControlEvent(
                    kind: .choke,
                    measureNumber: 1,
                    measureOffset: 0,
                    targetLaneID: "1A"
                )),
                NotationControlEvent(ChartControlEvent(
                    kind: .stop,
                    measureNumber: 1,
                    measureOffset: 0.5,
                    targetLaneID: "11"
                ))
            ]
        ))

        let labels = engraved.controls.compactMap { presentation.accessibilityLabels[.control($0.controlID)] }
        // "1A" resolves to the crash lane, "11" to the hi-hat lane — both
        // names route through the explicit localized note-type mapping.
        #expect(labels == ["Choke Crash", "Stop Hi-Hat"])
    }

    @Test("note labels come from the explicit localized note-type mapping")
    func noteLabelsUseExplicitNoteTypeMapping() throws {
        let (engraved, presentation) = try support.requireReady(support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.5),
            Note(interval: .quarter, noteType: .cowbell, measureNumber: 1, measureOffset: 0.75)
        ]))

        let labels = Set(engraved.noteHeads.compactMap {
            presentation.accessibilityLabels[.note($0.noteID)]
        })
        #expect(labels == ["Snare", "Bass", "Cowbell"])
    }

    @Test("distinct accessibility label maps do not change engraving equality")
    func distinctLabelMapsDoNotChangeEngravingEquality() async throws {
        try await TestSetup.withTestSetup {
            let (engraved, presentation) = try support.requireReady(support.prepare(notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
            ]))
            let alternatePresentation = GameplayNotationPresentation(
                annotations: presentation.annotations,
                accessibilityLabels: [.note(9_999): "Alternate probe label"]
            )

            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium)
            )
            viewModel.installPreparedNotation(.ready(engraved, presentation))
            let firstEngraving = viewModel.cachedEngravedNotation

            // Reinstalling the same engraving under a different label map is
            // a presentation-only change: the installed `EngravedNotation`
            // stays equal — labels are app-owned and never enter package
            // geometry or its Equatable contract.
            viewModel.installPreparedNotation(.ready(engraved, alternatePresentation))

            #expect(viewModel.cachedEngravedNotation == firstEngraving)
            #expect(
                viewModel.notationPresentation?.accessibilityLabels
                    == alternatePresentation.accessibilityLabels
            )
            #expect(viewModel.notationPresentation?.accessibilityLabels != presentation.accessibilityLabels)
        }
    }

    /// Three eighth-note triplet members in one beat group, prepared through
    /// the production route. `Note` can't carry tuplet metadata, so the
    /// snapshot is built from `RhythmLayoutNote`s directly — the resolved
    /// group carries `ratio 3:2` under the requested voice.
    private func tripletPreparation(voice: NotationVoice) -> GameplayNotationPreparedState {
        guard let snapshot = tripletSnapshot(voice: voice) else {
            Issue.record("Triplet snapshot construction failed")
            return .failed(GameplayNotationPreparationFailure(detail: "snapshot construction failed"))
        }
        return GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        ))
    }

    private func tripletSnapshot(voice: NotationVoice) -> RhythmLayoutSnapshot? {
        let ticksPerWholeNote = 960
        let tripletSpanTicks = ticksPerWholeNote / 4 // one beat
        let memberTicks = tripletSpanTicks / 3
        let tupletID = RhythmTupletID(
            measureIndex: 0,
            voice: voice,
            beatGroupIndex: 0,
            startTick: 0,
            durationTicks: tripletSpanTicks
        )
        let ratio = TupletRatio(actual: 3, normal: 2)
        let noteType: NoteType = voice == .lower ? .bass : .snare
        let notes = (0..<3).map { member in
            RhythmLayoutNote(
                eventID: RhythmEventID(rawValue: member + 1),
                sourceLaneID: nil,
                sourceChipID: nil,
                noteType: noteType,
                position: RhythmEventPosition(
                    measureIndex: 0,
                    localTick: member * memberTicks,
                    absoluteTick: member * memberTicks
                ),
                durationTicks: memberTicks,
                rhythm: NotationRhythm(baseInterval: .eighth, tuplet: ratio),
                tupletID: tupletID
            )
        }
        let measure = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: ticksPerWholeNote,
            timeSignature: .fourFour,
            beatGroups: RhythmBeatGroupBuilder.groups(
                timeSignature: .fourFour,
                durationTicks: ticksPerWholeNote,
                ticksPerWholeNote: ticksPerWholeNote
            ),
            engravingSupport: .supported
        )
        return try? RhythmLayoutSnapshot(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: [measure],
            notes: notes,
            controls: [],
            rests: [],
            feel: .straight
        )
    }
}
