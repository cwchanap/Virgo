import CoreGraphics
import Testing
@testable import Virgo

private final class ReferenceIdentityProbe {}

@Suite("Gameplay Notation Preparation")
struct GameplayNotationPreparationTests {
    @Test("request and prepared state are Sendable values")
    func requestAndPreparedStateAreSendableValues() {
        requireSendable(GameplayNotationPreparationRequest.self)
        requireSendable(GameplayNotationPreparedState.self)
    }

    @Test("timeline with no notes preserves printable renderable content")
    func timelineWithNoNotesPreservesPrintableRenderableContent() throws {
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0, startTick: 0, durationTicks: 960)],
            rests: [RhythmLayoutRest(
                position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                durationTicks: 960,
                voice: .upper,
                rhythm: NotationRhythm(baseInterval: .full),
                visibility: .printed,
                tupletID: nil
            )]
        )
        let request = GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        )

        let prepared = GameplayNotationPreparer.prepare(request)

        let (engraved, _) = try NotationSnapshotTestSupport().requireReady(prepared)
        #expect(engraved.noteHeads.isEmpty)
        // A rest-only sheet is printable (`.ready`) but not playable — the
        // legacy hasPlayable/hasRenderable split now lives on the installed
        // engraving's content.
        #expect(!engraved.rests.isEmpty)
    }

    @Test("request and result expose no model identity fields")
    func requestAndResultExposeNoModelIdentityFields() throws {
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0, startTick: 0, durationTicks: 960)]
        )
        let request = GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        )
        let prepared = GameplayNotationPreparer.prepare(request)

        let requestIdentityFindings = reflectedIdentityFindings(in: request)
        let resultIdentityFindings = reflectedIdentityFindings(in: prepared)
        #expect(requestIdentityFindings.isEmpty, "request findings: \(requestIdentityFindings)")
        #expect(resultIdentityFindings.isEmpty, "result findings: \(resultIdentityFindings)")

        let objectIdentityProbe: Any = ["renamedPayload": ObjectIdentifier(ReferenceIdentityProbe())]
        let referenceModelProbe: Any = ["renamedPayload": ReferenceIdentityProbe()]
        #expect(!reflectedIdentityFindings(in: objectIdentityProbe).isEmpty)
        #expect(!reflectedIdentityFindings(in: referenceModelProbe).isEmpty)
    }

    @Test("expanded measures extend from the last resolved measure with cumulative ticks")
    func expandedMeasuresExtendResolvedMeasures() throws {
        // A short pickup measure: expansion reuses its signature/support while
        // appended measures get the nominal (full-meter) duration.
        let pickup = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 720,
            timeSignature: .fourFour,
            beatGroups: (0..<3).map {
                RhythmBeatGroup(
                    groupIndex: $0,
                    startTick: $0 * 240,
                    durationTicks: 240,
                    isResidual: false
                )
            },
            engravingSupport: .supported
        )
        // One printable note in the pickup measure so preparation is `.ready`.
        let note = RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: 1),
            sourceLaneID: "12",
            sourceChipID: nil,
            noteType: .snare,
            position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
            durationTicks: 240,
            rhythm: NotationRhythm(baseInterval: .quarter),
            tupletID: nil
        )
        let snapshot = try makeSnapshot(measures: [pickup], notes: [note])

        let expanded = GameplayNotationPreparer.expandedRhythmMeasures(
            snapshot,
            minimumMeasureCount: 3
        )

        #expect(expanded.map(\.measureIndex) == [0, 1, 2])
        #expect(expanded.map(\.startTick) == [0, 720, 1_680])
        #expect(expanded.map(\.durationTicks) == [720, 960, 960])
        #expect(expanded.allSatisfy { $0.timeSignature == .fourFour })
        #expect(expanded.allSatisfy { $0.engravingSupport == .supported })
        // Trailing empty measures survive preparation end-to-end.
        let request = GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 3,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        )
        let (engraved, _) = try NotationSnapshotTestSupport().requireReady(
            GameplayNotationPreparer.prepare(request)
        )
        #expect(engraved.measures.map(\.index) == [0, 1, 2])
    }

    @Test("renderable measure bound reuses the shared rhythm limit")
    func renderableMeasureBoundReusesRhythmLimit() {
        #expect(GameplayNotationPreparer.maximumRenderableMeasureCount == RhythmLimits.maximumMeasureCount)
    }

    @Test("row-width style copy preserves every other metric")
    func rowWidthStyleCopyPreservesMetrics() {
        let style = NotationLayoutStyle.gameplayDefault
        let resized = style.with(rowWidth: 2_000)

        #expect(resized.rowWidth == 2_000)
        #expect(resized != style)
        // The memberwise copy must carry every non-width metric verbatim —
        // compare all stored children except `rowWidth` so a dropped field
        // cannot slip through a hand-maintained assertion list.
        let original = Dictionary(
            uniqueKeysWithValues: Mirror(reflecting: style).children.map { ($0.label ?? "", "\($0.value)") }
        )
        let copy = Dictionary(
            uniqueKeysWithValues: Mirror(reflecting: resized).children.map { ($0.label ?? "", "\($0.value)") }
        )
        #expect(original.keys == copy.keys)
        for label in original.keys where label != "rowWidth" {
            #expect(original[label] == copy[label], "metric \(label) changed under with(rowWidth:)")
        }
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    private func reflectedIdentityFindings(in value: Any) -> [String] {
        var findings: [String] = []
        collectReflectedIdentityFindings(in: value, path: "root", findings: &findings)
        return findings
    }

    private func collectReflectedIdentityFindings(
        in value: Any,
        path: String,
        findings: inout [String]
    ) {
        if value is ObjectIdentifier {
            findings.append("\(path): ObjectIdentifier")
            return
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .class {
            findings.append("\(path): \(String(reflecting: type(of: value)))")
            return
        }

        for (index, child) in mirror.children.enumerated() {
            let childName = child.label ?? "[\(index)]"
            collectReflectedIdentityFindings(
                in: child.value,
                path: "\(path).\(childName)",
                findings: &findings
            )
        }
    }

    private func makeSnapshot(
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote] = [],
        rests: [RhythmLayoutRest] = []
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: measures,
            notes: notes,
            controls: [],
            rests: rests,
            feel: .straight
        )
    }

    private func makeMeasure(index: Int, startTick: Int, durationTicks: Int) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: durationTicks,
            timeSignature: .fourFour,
            beatGroups: [RhythmBeatGroup(
                groupIndex: 0,
                startTick: 0,
                durationTicks: durationTicks,
                isResidual: false
            )],
            engravingSupport: .supported
        )
    }
}
