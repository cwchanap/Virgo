import CoreGraphics
import Foundation

struct BeamBuildResult {
    let events: [BeamTimelineEvent]
    let topology: BeamTopologyResult
    let beams: [RenderedBeam]
}

/// Beam, stem, flag, and ledger line construction extracted from
/// NotationLayoutEngine to keep the main engine file under the SwiftLint
/// type-body limit.
extension NotationLayoutEngine {
    fileprivate struct StemGroupKey: Hashable {
        let timeColumn: NotationTimeColumn
        let row: Int
        let voice: NotationVoice
        let stemDirection: StemDirection
    }

    /// Bundles the immutable inputs shared across beam-segment rendering so
    /// `renderedBeam` stays under SwiftLint's parameter-count limit.
    fileprivate struct RenderedBeamContext {
        let group: BeamPrimaryGroup
        let events: [BeamTimelineEvent]
        let headsByID: [UInt64: RenderedNoteHead]
        let style: NotationLayoutStyle
    }

    // MARK: - Rendering Primitives

    func buildStems(
        noteHeads: [RenderedNoteHead],
        beams: [RenderedBeam],
        style: NotationLayoutStyle
    ) -> [RenderedStem] {
        // Index beams under every noteHeadID so non-leading notes in a beam run
        // can also look up their beam geometry.
        var beamsByNoteHeadID: [UInt64: [RenderedBeam]] = [:]
        for beam in beams {
            for noteHeadID in beam.noteHeadIDs {
                beamsByNoteHeadID[noteHeadID, default: []].append(beam)
            }
        }

        let headsNeedingStems = noteHeads.filter { $0.interval.needsStem }

        let grouped = Dictionary(grouping: headsNeedingStems) { head in
            StemGroupKey(
                timeColumn: head.timeColumn,
                row: head.row,
                voice: head.voice,
                stemDirection: head.stemDirection
            )
        }

        return grouped.compactMap { key, group in
            guard let representative = stemRepresentative(in: group) else {
                Logger.error("Empty stem group for \(key)")
                return nil
            }
            let start = stemAnchor(for: representative, style: style)
            let candidateBeams = group.flatMap { beamsByNoteHeadID[$0.id] ?? [] }
            let outermostBeam = representative.stemDirection == .up
                ? candidateBeams.min(by: { $0.start.y < $1.start.y })
                : candidateBeams.max(by: { $0.start.y < $1.start.y })
            let endY: CGFloat
            if let outermostBeam,
               let beamY = beamEndY(
                   for: representative,
                   beam: outermostBeam,
                   style: style
               ) {
                endY = beamY
            } else {
                endY = unbeamedStemEndY(for: group, start: start, style: style)
            }

            return RenderedStem(
                id: "stem_\(key.timeColumn.absoluteLayoutTick)_r\(key.row)_"
                    + "\(key.voice.rawValue)_\(representative.stemDirection.rawValue)",
                noteHeadIDs: group.map(\.id).sorted(),
                direction: representative.stemDirection,
                start: start,
                end: CGPoint(x: start.x, y: endY)
            )
        }
    }

    /// Computes stem end Y from beam geometry if noteHead is beamed.
    /// Internal because `NotationLayoutDefensiveGuardTests` exercises it
    /// directly; `@testable import` does not expose `fileprivate` members.
    func beamEndY(
        for noteHead: RenderedNoteHead,
        beam: RenderedBeam,
        style: NotationLayoutStyle
    ) -> CGFloat? {
        guard beam.kind != .full || beam.noteHeadIDs.count > 1 else { return nil }

        let startX = beam.start.x, endX = beam.end.x
        let stemX = stemAnchor(for: noteHead, style: style).x

        guard stemX >= min(startX, endX) && stemX <= max(startX, endX) else { return nil }

        guard endX != startX else { return nil }

        // Beams are always horizontal, so no interpolation is needed.
        return beam.start.y
    }

    func buildBeams(
        noteHeads: [RenderedNoteHead],
        tabGrid: TabGrid,
        timeSignature: TimeSignature,
        style: NotationLayoutStyle
    ) -> BeamBuildResult {
        let events = buildTimelineEvents(
            noteHeads: noteHeads,
            ticksPerMeasure: tabGrid.ticksPerMeasure,
            timeSignature: timeSignature
        )
        let topology = NotationBeamTopologyBuilder().build(
            events: events,
            ticksPerMeasure: tabGrid.ticksPerMeasure,
            timeSignature: timeSignature
        )
        let headsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0) })

        let beams = topology.primaryGroups.flatMap { group -> [RenderedBeam] in
            let representatives = group.eventIndices.compactMap { index in
                stemRepresentative(
                    in: events[index].noteHeadIDs.compactMap { headsByID[$0] }
                )
            }
            guard let direction = representatives.first?.stemDirection else { return [] }
            let baseY = sharedBeamBaseY(
                for: representatives,
                direction: direction,
                style: style
            )
            let context = RenderedBeamContext(
                group: group,
                events: events,
                headsByID: headsByID,
                style: style
            )
            return group.segments.compactMap { segment in
                renderedBeam(
                    segment: segment,
                    context: context,
                    baseY: baseY
                )
            }
        }
        .sorted(by: renderedBeamComesBefore)

        return BeamBuildResult(events: events, topology: topology, beams: beams)
    }

    func buildFlags(
        noteHeads: [RenderedNoteHead],
        beamBuild: BeamBuildResult,
        stems: [RenderedStem],
        style: NotationLayoutStyle
    ) -> [RenderedFlag] {
        let headsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0) })
        // Each noteHeadID maps to exactly one stem because buildStems groups
        // by StemGroupKey(timeColumn, row, voice, stemDirection) and every
        // noteHead has exactly one value for each key component. The
        // uniqueKeysWithValues initializer would trap if this invariant broke.
        let stemsByNoteHeadID = Dictionary(
            uniqueKeysWithValues: stems.flatMap { stem in
                stem.noteHeadIDs.map { ($0, stem) }
            }
        )

        return beamBuild.events.enumerated().flatMap { index, event -> [RenderedFlag] in
            guard case let .beamable(requiredLevels, _) = event.role else { return [] }
            let eventHeads = event.noteHeadIDs.compactMap { headsByID[$0] }
            guard let representative = flagRepresentative(in: eventHeads),
            let stem = stemsByNoteHeadID[representative.id] else { return [] }

            let covered = beamBuild.topology.coveredLevelsByEventIndex[index] ?? []
            let flagOrigin = CGPoint(
                x: stem.start.x + GameplayLayout.flagXOffset,
                y: stem.end.y
            )
            return (0..<requiredLevels).compactMap { level in
                guard !covered.contains(level) else { return nil }
                let yOffset = stem.direction == .up
                    ? CGFloat(level) * GameplayLayout.flagVerticalSpacing
                    : -CGFloat(level) * GameplayLayout.flagVerticalSpacing
                return RenderedFlag(
                    id: "flag_\(representative.id)_\(level)",
                    noteHeadID: representative.id,
                    stemDirection: stem.direction,
                    flagIndex: level,
                    origin: CGPoint(x: flagOrigin.x, y: flagOrigin.y + yOffset)
                )
            }
        }
    }

    func buildLedgerLines(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedLedgerLine] {
        noteHeads.flatMap { noteHead in
            ledgerSteps(for: noteHead.staffStep).map { step in
                let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: noteHead.row)
                    + CGFloat(step) * (style.staffLineSpacing / 2)
                let glyphBounds = noteHead.glyph.bounds(
                    centeredAt: noteHead.position,
                    size: style.noteHeadSize
                )

                return RenderedLedgerLine(
                    id: "ledger_\(noteHead.id)_\(step)",
                    row: noteHead.row,
                    start: CGPoint(
                        x: glyphBounds.minX - style.ledgerLineOverhang,
                        y: y
                    ),
                    end: CGPoint(
                        x: glyphBounds.maxX + style.ledgerLineOverhang,
                        y: y
                    )
                )
            }
        }
    }

    // MARK: - Beam Helpers

    func buildTimelineEvents(
        noteHeads: [RenderedNoteHead],
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> [BeamTimelineEvent] {
        Dictionary(grouping: noteHeads) {
            StemGroupKey(
                timeColumn: $0.timeColumn,
                row: $0.row,
                voice: $0.voice,
                stemDirection: $0.stemDirection
            )
        }
        .values
        .compactMap { group in
            // Dictionary(grouping:) never yields an empty group, so
            // flagRepresentative (which delegates to Array.min) is guaranteed
            // to return a non-nil representative here. The guard + assertion
            // catches any future call-site change that breaks this invariant.
            guard let representative = flagRepresentative(in: group) else {
                assertionFailure("Dictionary(grouping:) yielded an empty group")
                return nil
            }
            let maximumLevels = group.map(\.interval.flagCount).max() ?? 0
            let role: BeamTimelineEventRole = maximumLevels == 0
                ? .boundary
                : .beamable(
                    requiredBeamLevels: maximumLevels,
                    durationTicks: durationTicks(
                        for: representative.interval,
                        ticksPerMeasure: ticksPerMeasure,
                        timeSignature: timeSignature
                    )
                )
            return BeamTimelineEvent(
                timeColumn: representative.timeColumn,
                row: representative.row,
                voice: representative.voice,
                stemDirection: representative.stemDirection,
                noteHeadIDs: group.map(\.id).sorted(),
                role: role
            )
        }
        .sorted(by: timelineEventComesBefore)
    }

    func durationTicks(
        for interval: NoteInterval,
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> Int? {
        let denominator: Int
        switch interval {
        case .eighth: denominator = 8
        case .sixteenth: denominator = 16
        case .thirtysecond: denominator = 32
        case .sixtyfourth: denominator = 64
        case .full, .half, .quarter: return nil
        }
        // Subdivision denominators are fractions of a whole note, not of a
        // measure. In simple X/4 meters the measure is shorter than a whole
        // note (e.g. 3/4 spans 3/4 of a whole), so dividing ticksPerMeasure
        // by the denominator under-counts each note's true duration and
        // breaks run adjacency in the topology builder. Convert to
        // whole-note ticks first: a measure holds beatsPerMeasure / noteValue
        // whole notes, so ticksPerWhole = ticksPerMeasure * noteValue /
        // beatsPerMeasure.
        guard timeSignature.beatsPerMeasure > 0,
              (ticksPerMeasure * timeSignature.noteValue)
                .isMultiple(of: timeSignature.beatsPerMeasure) else {
            return nil
        }
        let ticksPerWholeNote = ticksPerMeasure * timeSignature.noteValue / timeSignature.beatsPerMeasure
        guard ticksPerWholeNote > 0, ticksPerWholeNote.isMultiple(of: denominator) else { return nil }
        return ticksPerWholeNote / denominator
    }

    private func timelineEventComesBefore(
        _ lhs: BeamTimelineEvent,
        _ rhs: BeamTimelineEvent
    ) -> Bool {
        if lhs.timeColumn.measureIndex != rhs.timeColumn.measureIndex {
            return lhs.timeColumn.measureIndex < rhs.timeColumn.measureIndex
        }
        if lhs.timeColumn.absoluteLayoutTick != rhs.timeColumn.absoluteLayoutTick {
            return lhs.timeColumn.absoluteLayoutTick < rhs.timeColumn.absoluteLayoutTick
        }
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        if lhs.voice.rawValue != rhs.voice.rawValue {
            return lhs.voice.rawValue < rhs.voice.rawValue
        }
        if lhs.stemDirection.rawValue != rhs.stemDirection.rawValue {
            return lhs.stemDirection.rawValue < rhs.stemDirection.rawValue
        }
        return lhs.noteHeadIDs.lexicographicallyPrecedes(rhs.noteHeadIDs)
    }

    /// Returns the note head that governs beam-level/flag-count decisions for a
    /// chord, picking the head with the most flags (then by catalog order, then
    /// ID for determinism).
    ///
    /// Distinct from ``stemRepresentative(in:)``, which picks the head that
    /// determines stem length and beam endpoint X: `stemRepresentative` filters
    /// to `needsStem` candidates and sorts by vertical position, whereas this
    /// helper keeps every head (including stemless ones, which contribute a
    /// `flagCount` of 0 and so never win) and sorts by flag count. Use this
    /// representative only when computing `requiredBeamLevels` or
    /// `durationTicks` for a beam timeline event.
    private func flagRepresentative(
        in noteHeads: [RenderedNoteHead]
    ) -> RenderedNoteHead? {
        noteHeads.min {
            if $0.interval.flagCount != $1.interval.flagCount {
                return $0.interval.flagCount > $1.interval.flagCount
            }
            if $0.catalogOrder != $1.catalogOrder {
                return $0.catalogOrder < $1.catalogOrder
            }
            return $0.id < $1.id
        }
    }

    private func renderedBeam(
        segment: BeamTopologySegment,
        context: RenderedBeamContext,
        baseY: CGFloat
    ) -> RenderedBeam? {
        guard let ownerIndex = segment.eventIndices.first,
              let owner = representative(
                  for: context.events[ownerIndex],
                  headsByID: context.headsByID
              ) else { return nil }

        let start = stemAnchor(for: owner, style: context.style)
        guard let endpoint = beamEndpoint(
            segment: segment,
            owner: owner,
            ownerIndex: ownerIndex,
            startX: start.x,
            context: context
        ) else { return nil }
        guard endpoint.endX != start.x else { return nil }

        let direction = context.group.id.stemDirection
        let levelOffset = CGFloat(segment.level) * context.style.beamLevelSpacing
        let y = direction == .up ? baseY - levelOffset : baseY + levelOffset
        let noteHeadIDs: [UInt64]
        if segment.kind == .full {
            noteHeadIDs = Array(Set(segment.eventIndices.flatMap {
                context.events[$0].noteHeadIDs
            })).sorted()
        } else {
            noteHeadIDs = context.events[ownerIndex].noteHeadIDs.sorted()
        }

        return RenderedBeam(
            id: renderedBeamID(
                group: context.group,
                segment: segment,
                firstTick: context.events[ownerIndex].timeColumn.absoluteLayoutTick,
                lastTick: context.events[endpoint.terminalIndex].timeColumn.absoluteLayoutTick
            ),
            noteHeadIDs: noteHeadIDs,
            direction: direction,
            level: segment.level,
            kind: segment.kind,
            start: CGPoint(x: start.x, y: y),
            end: CGPoint(x: endpoint.endX, y: y),
            thickness: context.style.beamThickness
        )
    }

    private func beamEndpoint(
        segment: BeamTopologySegment,
        owner: RenderedNoteHead,
        ownerIndex: Int,
        startX: CGFloat,
        context: RenderedBeamContext
    ) -> (endX: CGFloat, terminalIndex: Int)? {
        switch segment.kind {
        case .full:
            guard let lastIndex = segment.eventIndices.last,
                  let last = representative(
                      for: context.events[lastIndex],
                      headsByID: context.headsByID
                  ) else { return nil }
            return (stemAnchor(for: last, style: context.style).x, lastIndex)
        case .forwardHook, .backwardHook:
            guard let neighborIndex = segment.hookNeighborIndex,
                  let neighbor = representative(
                      for: context.events[neighborIndex],
                      headsByID: context.headsByID
                  ) else { return nil }
            let neighborX = stemAnchor(for: neighbor, style: context.style).x
            let length = min(context.style.beamHookLength, abs(neighborX - startX) / 2)
            guard length > 0 else { return nil }
            let endX = startX + (neighborX > startX ? length : -length)
            return (endX, neighborIndex)
        }
    }

    private func representative(
        for event: BeamTimelineEvent,
        headsByID: [UInt64: RenderedNoteHead]
    ) -> RenderedNoteHead? {
        stemRepresentative(in: event.noteHeadIDs.compactMap { headsByID[$0] })
    }

    private func sharedBeamBaseY(
        for representatives: [RenderedNoteHead],
        direction: StemDirection,
        style: NotationLayoutStyle
    ) -> CGFloat {
        let candidates = representatives.map {
            let anchorY = stemAnchor(for: $0, style: style).y
            return direction == .up
                ? anchorY - style.stemLength
                : anchorY + style.stemLength
        }
        return direction == .up
            ? candidates.min() ?? 0
            : candidates.max() ?? 0
    }

    private func renderedBeamID(
        group: BeamPrimaryGroup,
        segment: BeamTopologySegment,
        firstTick: Int,
        lastTick: Int
    ) -> String {
        let id = group.id
        return "beam_m\(id.measureIndex)_r\(id.row)_b\(id.beatGroupIndex)_"
            + "v\(id.voice.rawValue)_d\(id.stemDirection.rawValue)_"
            + "l\(segment.level)_\(segment.kind.rawValue)_\(firstTick)_\(lastTick)"
    }

    private func renderedBeamComesBefore(
        _ lhs: RenderedBeam,
        _ rhs: RenderedBeam
    ) -> Bool {
        if lhs.start.y != rhs.start.y { return lhs.start.y < rhs.start.y }
        if lhs.start.x != rhs.start.x { return lhs.start.x < rhs.start.x }
        if lhs.level != rhs.level { return lhs.level < rhs.level }
        return lhs.id < rhs.id
    }

    func stemAnchor(
        for noteHead: RenderedNoteHead,
        style: NotationLayoutStyle
    ) -> CGPoint {
        let offset = noteHead.glyph.stemAnchorOffset(
            direction: noteHead.stemDirection,
            in: style.noteHeadSize
        )
        return CGPoint(
            x: noteHead.position.x + offset.x,
            y: noteHead.position.y + offset.y
        )
    }

    func glyphBounds(
        for noteHead: RenderedNoteHead,
        style: NotationLayoutStyle
    ) -> CGRect {
        noteHead.glyph.bounds(
            centeredAt: noteHead.position,
            size: style.noteHeadSize
        )
    }

    func stemRepresentative(
        in noteHeads: [RenderedNoteHead]
    ) -> RenderedNoteHead? {
        // Filter to notes that actually need a stem so stemless half/full
        // notes sharing a time column with beamed notes cannot be picked as
        // the beam endpoint representative (which would misalign beam X from
        // stem X). buildStems pre-filters its input, but beam rendering calls
        // this with the full chord, so the filter must live here.
        let candidates = noteHeads.filter { $0.interval.needsStem }
        guard let direction = candidates.first?.stemDirection else {
            return nil
        }
        let ordered = candidates.sorted {
            if $0.position.y != $1.position.y {
                return $0.position.y < $1.position.y
            }
            if $0.catalogOrder != $1.catalogOrder {
                return $0.catalogOrder < $1.catalogOrder
            }
            return $0.id < $1.id
        }
        return direction == .up ? ordered.last : ordered.first
    }

    func unbeamedStemEndY(
        for noteHeads: [RenderedNoteHead],
        start: CGPoint,
        style: NotationLayoutStyle
    ) -> CGFloat {
        guard let direction = noteHeads.first?.stemDirection else {
            return start.y
        }
        switch direction {
        case .up:
            let highestVisibleY = noteHeads.map {
                glyphBounds(for: $0, style: style).minY
            }.min() ?? start.y
            return min(
                start.y - style.stemLength,
                highestVisibleY - style.minimumStemExtensionPastChord
            )
        case .down:
            let lowestVisibleY = noteHeads.map {
                glyphBounds(for: $0, style: style).maxY
            }.max() ?? start.y
            return max(
                start.y + style.stemLength,
                lowestVisibleY + style.minimumStemExtensionPastChord
            )
        }
    }

    func ledgerSteps(for staffStep: Int) -> [Int] {
        if staffStep < Self.topStaffStep {
            return stride(from: Self.topStaffStep - 2, through: staffStep, by: -2).map { $0 }
        }
        if staffStep > Self.bottomStaffStep {
            return stride(from: Self.bottomStaffStep + 2, through: staffStep, by: 2).map { $0 }
        }
        return []
    }
}
