import Testing
import CoreGraphics
@testable import Virgo

/// HPA-163 rendered-hook preservation gate.
///
/// None of the eleven catalog fixtures produces a beam hook (every committed
/// golden beam line is `kind=full`), so this suite synthesizes a layout that
/// does: a 16th–8th–16th run inside one 4/4 beat group forms one primary run
/// whose level-1 segments are a forward hook (first 16th) and a backward hook
/// (last 16th). It rebuilds the engine's own `BeamBuildResult` from the
/// composed heads and compares topology `BeamTopologySegment`s of kind
/// `.forwardHook`/`.backwardHook` (joined by primary group + level + kind,
/// with the owner event's head IDs as the join key) against the rendered
/// `RenderedBeam`s, asserting every topology hook produces exactly one
/// non-zero-length rendered hook.
///
/// This protects the case where new notehead anchor X values make
/// `beamEndpoint`'s hook length (`min(beamHookLength, |neighborX - startX| / 2)`)
/// collapse to zero and silently drop a topology-requested hook: the topology
/// segment would survive while the rendered beam disappears. Topology is
/// invariant under HPA-163; rendering geometry must keep up with it.
@Suite("Beam hook preservation")
struct BeamHookPreservationTests {
    @Test("every topology hook renders as exactly one non-zero hook")
    func topologyHooksRenderNonZero() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let engine = NotationLayoutEngine()
        let support = NotationSnapshotTestSupport()
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 3.0 / 16.0)
        ]
        let snapshot: RhythmLayoutSnapshot
        let prepared: LegacyPreparedNotation
        do {
            snapshot = try support.snapshot(notes: notes)
            prepared = legacyPreparedNotation(GameplayNotationPreparationRequest(
                snapshot: snapshot,
                minimumMeasureCount: 1,
                style: style,
                notePositionOverrides: [:]
            ))
        } catch {
            Issue.record("Snapshot construction failed: \(error)")
            return
        }
        let layout = prepared.layout
        let expandedMeasures = engine.expandedRhythmMeasures(snapshot, minimumMeasureCount: 1)
        // The reproduction is faithful: same heads, same expanded rhythm
        // measures, and same style as the composition's internal rebuild, so
        // the rendered beams must be identical.
        let beamBuild = engine.buildBeams(
            noteHeads: layout.noteHeads,
            measures: expandedMeasures,
            style: style
        )

        #expect(beamBuild.beams == layout.beams)

        let hooks = beamBuild.topology.primaryGroups.flatMap { group in
            group.segments
                .filter { $0.kind == .forwardHook || $0.kind == .backwardHook }
                .map { (groupID: group.id, segment: $0) }
        }
        // Guard against the synthetic fixture silently producing no hooks and
        // the loop below passing vacuously.
        #expect(hooks.contains { $0.segment.kind == .forwardHook })
        #expect(hooks.contains { $0.segment.kind == .backwardHook })

        for hook in hooks {
            let ownerIDs = Set(beamBuild.events[hook.segment.eventIndices[0]].noteHeadIDs)
            let rendered = beamBuild.beams.filter { beam in
                beam.level == hook.segment.level
                    && beam.kind == hook.segment.kind
                    && Set(beam.noteHeadIDs) == ownerIDs
            }
            #expect(
                rendered.count == 1,
                Comment(rawValue: "topology \(hook.segment.kind.rawValue) at level \(hook.segment.level) "
                    + "in group \(hook.groupID) produced \(rendered.count) rendered hooks")
            )
            for beam in rendered {
                #expect(
                    abs(beam.end.x - beam.start.x) > 0,
                    Comment(rawValue: "rendered \(beam.kind.rawValue) hook \(beam.id) has zero length")
                )
            }
        }

        // No stray or duplicated rendered hooks beyond the topology's own.
        let renderedHookCount = beamBuild.beams.filter {
            $0.kind == .forwardHook || $0.kind == .backwardHook
        }.count
        #expect(renderedHookCount == hooks.count)
    }
}
