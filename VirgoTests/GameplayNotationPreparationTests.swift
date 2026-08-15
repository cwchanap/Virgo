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

        #expect(prepared.layout.noteHeads.isEmpty)
        #expect(!prepared.layout.hasPlayableContent)
        #expect(prepared.layout.hasRenderableContent)
        #expect(prepared.layout.rests.contains { $0.isPrinted })
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
