import CoreGraphics

// HPA-166 Task 4 — topology-driven stem/beam/flag geometry, a mechanical
// port of `Virgo/layout/NotationLayoutEngine+Beams.swift` onto the shared
// `StemTopology`: same stem representatives, same flat-beam Y stacking, same
// hook endpoints, same unbeamed-stem clearance, same flag origins — driven
// by the one plan the formatter already consumed rather than a second
// grouping pass.

extension SheetComposer {
    /// Bundles the immutable inputs shared across beam-segment rendering so
    /// the ported helpers stay under the parameter-count limit — mirrors
    /// the engine's `RenderedBeamContext`.
    struct BeamRenderContext {
        let group: BeamPrimaryGroup
        let events: [BeamTimelineEvent]
        let stemGroups: [StemGroup]
        let headsByID: [Int: PendingNoteHead]
    }

    /// Stroked-segment ink bounds — the engine's `lineBounds` port shared by
    /// stems, beams and any other stroked primitive.
    func lineBounds(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
    }

    // MARK: - Beams

    /// Assembles every primary group's segments into flat beams — the port
    /// of the engine's `assembleBeams`: one shared base Y per group from
    /// its stem representatives' anchors, then one segment per topology
    /// segment, sorted by the pinned beam comparator.
    func collectBeams(headsByID: [Int: PendingNoteHead], raw: inout RawGeometry) {
        let beams = stemTopology.topology.primaryGroups.flatMap { group -> [EngravedBeam] in
            let representatives = group.eventIndices.compactMap { index in
                stemTopology.stemGroups[index].stemRepresentativeID.flatMap { headsByID[$0] }
            }
            guard let direction = representatives.first?.note.stemDirection else { return [] }
            // Every chord member participating in the run — the far-edge
            // bound the shared base must clear, not just the
            // representatives' own anchors.
            let members = group.eventIndices.flatMap { index in
                stemTopology.stemGroups[index].memberNoteIDs.compactMap { headsByID[$0] }
            }
            let baseY = sharedBeamBaseY(
                members: members,
                representatives: representatives,
                direction: direction
            )
            let context = BeamRenderContext(
                group: group,
                events: stemTopology.events,
                stemGroups: stemTopology.stemGroups,
                headsByID: headsByID
            )
            return group.segments.compactMap { segment in
                renderedBeam(segment: segment, context: context, baseY: baseY)
            }
        }.sorted(by: beamComesBefore)
        for beam in beams {
            raw.include(lineBounds(start: beam.start, end: beam.end, lineWidth: beam.thickness))
        }
        raw.beams.append(contentsOf: beams)
    }

    /// One beam segment at its shared base Y minus its stack-level offset —
    /// the port of the engine's `renderedBeam`. Full segments span first to
    /// last member stem axis; hooks reach toward their neighbor's axis by
    /// the hook length (halved by proximity, per the topology rule).
    private func renderedBeam(
        segment: BeamTopologySegment,
        context: BeamRenderContext,
        baseY: CGFloat
    ) -> EngravedBeam? {
        guard let ownerIndex = segment.eventIndices.first,
              let owner = representative(for: ownerIndex, context: context) else { return nil }

        let start = owner.stemAnchor
        guard let endX = beamEndpoint(
            segment: segment,
            startX: start.x,
            context: context
        ) else { return nil }
        guard endX != start.x else { return nil }

        let direction = context.group.id.stemDirection
        let levelOffset = CGFloat(segment.level) * style.beamLevelSpacing
        let y = direction == .up ? baseY - levelOffset : baseY + levelOffset
        let noteIDs: [Int]
        if segment.kind == .full {
            noteIDs = Array(Set(segment.eventIndices.flatMap {
                context.events[$0].noteIDs
            })).sorted()
        } else {
            noteIDs = context.events[ownerIndex].noteIDs.sorted()
        }

        return EngravedBeam(
            noteIDs: noteIDs,
            direction: direction,
            level: segment.level,
            kind: EngravedBeamKind(segment.kind),
            start: CGPoint(x: start.x, y: y),
            end: CGPoint(x: endX, y: y),
            thickness: style.beamThickness
        )
    }

    /// The horizontal end of one beam segment — the engine's `beamEndpoint`:
    /// full segments end on their last member's stem axis; hooks end at the
    /// hook length toward (or away from) the neighbor axis, halved when the
    /// neighbor sits closer than twice the hook length.
    private func beamEndpoint(
        segment: BeamTopologySegment,
        startX: CGFloat,
        context: BeamRenderContext
    ) -> CGFloat? {
        switch segment.kind {
        case .full:
            guard let lastIndex = segment.eventIndices.last,
                  let last = representative(for: lastIndex, context: context) else { return nil }
            return last.stemAnchor.x
        case .forwardHook, .backwardHook:
            guard let neighborIndex = segment.hookNeighborIndex,
                  let neighbor = representative(for: neighborIndex, context: context)
            else { return nil }
            let neighborX = neighbor.stemAnchor.x
            let length = min(style.beamHookLength, abs(neighborX - startX) / 2)
            guard length > 0 else { return nil }
            return startX + (neighborX > startX ? length : -length)
        }
    }

    /// The stem-side representative head of one timeline event — resolved
    /// through the shared stem group so displaced siblings never move the
    /// axis, matching the engine's `representative(for:headsByID:)`.
    private func representative(
        for eventIndex: Int,
        context: BeamRenderContext
    ) -> PendingNoteHead? {
        context.stemGroups[eventIndex].stemRepresentativeID.flatMap { context.headsByID[$0] }
    }

    /// The shared outermost beam Y of one primary group: every member stem
    /// reaches the same flat beam — the default stem length down/up from
    /// the most extreme representative anchor AND
    /// `minimumStemExtensionPastChord` past the farthest participating
    /// member ink, so a wide chord's far head can never reach the
    /// innermost beam. The anchor term is the engine's `sharedBeamBaseY`;
    /// the member-bound term is the same far-chord-edge rule
    /// `unbeamedStemEndY` applies, minus flag ink (beams replace it).
    private func sharedBeamBaseY(
        members: [PendingNoteHead],
        representatives: [PendingNoteHead],
        direction: NotationStemDirection
    ) -> CGFloat {
        let candidates = representatives.map {
            direction == .up
                ? $0.stemAnchor.y - style.stemLength
                : $0.stemAnchor.y + style.stemLength
        } + members.map {
            direction == .up
                ? $0.bounds.minY - style.minimumStemExtensionPastChord
                : $0.bounds.maxY + style.minimumStemExtensionPastChord
        }
        return direction == .up
            ? candidates.min() ?? 0
            : candidates.max() ?? 0
    }

    /// The pinned beam ordering — the engine's `renderedBeamComesBefore`
    /// with note IDs standing in for the app-only string ID.
    private func beamComesBefore(_ lhs: EngravedBeam, _ rhs: EngravedBeam) -> Bool {
        if lhs.start.y != rhs.start.y { return lhs.start.y < rhs.start.y }
        if lhs.start.x != rhs.start.x { return lhs.start.x < rhs.start.x }
        if lhs.level != rhs.level { return lhs.level < rhs.level }
        return lhs.noteIDs.lexicographicallyPrecedes(rhs.noteIDs)
    }

    // MARK: - Stems

    /// One shared stem per stem group, painted from the stem-side
    /// representative's Bravura anchor to its outermost beam — or the
    /// unbeamed end that clears the far chord edge and any flag ink. The
    /// port of the engine's `buildStems`. Returns the stems keyed by
    /// stem-group index for flag placement.
    func collectStems(
        headsByID: [Int: PendingNoteHead],
        raw: inout RawGeometry
    ) -> [Int: EngravedStem] {
        // Index beams under every member note ID so non-leading notes in a
        // beam run also find their beam geometry (the engine's
        // `beamsByNoteHeadID`).
        var beamsByNoteID: [Int: [EngravedBeam]] = [:]
        for beam in raw.beams {
            for noteID in beam.noteIDs {
                beamsByNoteID[noteID, default: []].append(beam)
            }
        }

        var stemsByGroup: [Int: EngravedStem] = [:]
        for (index, group) in stemTopology.stemGroups.enumerated() {
            let members = group.memberNoteIDs
                .compactMap { headsByID[$0] }
                .filter { $0.note.duration.needsStem && $0.note.isRhythmEngravable }
            guard let representativeID = group.stemRepresentativeID,
                  let representative = headsByID[representativeID],
                  !members.isEmpty else { continue }
            let start = representative.stemAnchor
            let memberIDs = members.map { $0.note.id }
            let candidateBeams = memberIDs.flatMap { beamsByNoteID[$0] ?? [] }
            let outermostBeam = group.key.stemDirection == .up
                ? candidateBeams.min(by: { $0.start.y < $1.start.y })
                : candidateBeams.max(by: { $0.start.y < $1.start.y })
            let endY = outermostBeam
                .flatMap { beamEndY(stemX: start.x, beam: $0) }
                ?? unbeamedStemEndY(members: members, start: start)
            let stem = EngravedStem(
                noteIDs: memberIDs.sorted(),
                direction: group.key.stemDirection,
                start: start,
                end: CGPoint(x: start.x, y: endY)
            )
            raw.include(lineBounds(start: stem.start, end: stem.end, lineWidth: formatting.stemWidth))
            raw.stems.append(stem)
            stemsByGroup[index] = stem
        }
        return stemsByGroup
    }

    /// The beam Y a stem reaches, or nil when the stem axis lies outside
    /// the segment — the engine's `beamEndY` (flat beams: the segment's Y).
    private func beamEndY(stemX: CGFloat, beam: EngravedBeam) -> CGFloat? {
        guard beam.kind != .full || beam.noteIDs.count > 1 else { return nil }
        let startX = beam.start.x, endX = beam.end.x
        guard stemX >= min(startX, endX), stemX <= max(startX, endX) else { return nil }
        guard endX != startX else { return nil }
        // Beams are always horizontal, so no interpolation is needed.
        return beam.start.y
    }

    /// The stem end for a group with no beam reaching it — the engine's
    /// `unbeamedStemEndY`: the effective stem length keeps the flag ink and
    /// the far chord edge `minimumStemExtensionPastChord` clear.
    private func unbeamedStemEndY(members: [PendingNoteHead], start: CGPoint) -> CGFloat {
        guard let direction = members.first?.note.stemDirection else { return start.y }
        let flagInwardExtent = maximumFlagInwardExtent(members: members)
        let effectiveStemLength = max(
            style.stemLength,
            flagInwardExtent + style.minimumStemExtensionPastChord
        )
        switch direction {
        case .up:
            let highestVisibleY = members.map(\.bounds.minY).min() ?? start.y
            return min(
                start.y - effectiveStemLength,
                highestVisibleY - style.minimumStemExtensionPastChord - flagInwardExtent
            )
        case .down:
            let lowestVisibleY = members.map(\.bounds.maxY).max() ?? start.y
            return max(
                start.y + effectiveStemLength,
                lowestVisibleY + style.minimumStemExtensionPastChord + flagInwardExtent
            )
        }
    }

    /// The maximum reach any flagged member's canonical Bravura flag makes
    /// back from the stem attachment toward the noteheads — the port of the
    /// adapter's `maximumFlagInwardExtent`. Zero for unflagged groups.
    private func maximumFlagInwardExtent(members: [PendingNoteHead]) -> CGFloat {
        var extent: CGFloat = 0
        for head in members {
            guard let flagDuration = head.note.duration.flagDuration else { continue }
            let direction = head.note.stemDirection
            let metrics = PercussionGlyphMetrics.flag(
                duration: flagDuration,
                direction: direction,
                staffSpace: formatting.staffSpace
            )
            let relativeBounds = metrics.paintedBounds.offsetBy(
                dx: -metrics.attachmentOffset.x,
                dy: -metrics.attachmentOffset.y
            )
            let inwardExtent: CGFloat
            switch direction {
            case .up:
                inwardExtent = max(0, relativeBounds.maxY)
            case .down:
                inwardExtent = max(0, -relativeBounds.minY)
            }
            extent = max(extent, inwardExtent)
        }
        return extent
    }

    // MARK: - Flags

    /// Paints each stem group's visible flag plan: one canonical flag glyph
    /// for a fully uncovered family, one eighth component per uncovered
    /// level for partial plans — the same single `VisibleFlagPlan` the
    /// formatter already reserved ink for, so painted ink can never exceed
    /// the reservation.
    func collectFlags(stemsByGroup: [Int: EngravedStem], raw: inout RawGeometry) {
        for (index, group) in stemTopology.stemGroups.enumerated() {
            guard let flagRepID = group.flagRepresentativeID,
                  let stem = stemsByGroup[index] else { continue }
            let direction = stem.direction
            let base = flagStemOrigin(for: stem)
            switch stemTopology.flagPlans[index] {
            case .none:
                continue
            case .canonical(let duration):
                appendFlag(EngravedFlag(
                    noteID: flagRepID, stemDirection: direction, duration: duration,
                    flagIndex: 0, origin: base
                ), raw: &raw)
            case .components(let levels):
                for level in levels.sorted() {
                    let yOffset = direction == .up
                        ? CGFloat(level) * style.flagVerticalSpacing
                        : -CGFloat(level) * style.flagVerticalSpacing
                    appendFlag(EngravedFlag(
                        noteID: flagRepID, stemDirection: direction, duration: .eighth,
                        flagIndex: level,
                        origin: CGPoint(x: base.x, y: base.y + yOffset)
                    ), raw: &raw)
                }
            }
        }
    }

    /// The SMuFL flag attachment point for `stem`: flag glyph origins land
    /// on the stem's left edge, level 0 vertically at the stem tip — the
    /// engine's `flagStemOrigin`.
    private func flagStemOrigin(for stem: EngravedStem) -> CGPoint {
        CGPoint(x: stem.start.x - formatting.stemWidth / 2, y: stem.end.y)
    }

    /// Appends one flag primitive and unions its Bravura painted bounds
    /// (glyph bounds offset so the attachment point lands on `origin`).
    private func appendFlag(_ flag: EngravedFlag, raw: inout RawGeometry) {
        let metrics = PercussionGlyphMetrics.flag(
            duration: flag.duration,
            direction: flag.stemDirection,
            staffSpace: formatting.staffSpace
        )
        raw.include(metrics.paintedBounds.offsetBy(
            dx: flag.origin.x - metrics.attachmentOffset.x,
            dy: flag.origin.y - metrics.attachmentOffset.y
        ))
        raw.flags.append(flag)
    }
}

/// The one package Y translation applied after the painted-bounds pass —
/// module-internal so the only route to a moved primitive is the composer.
extension EngravedStem {
    func translated(byY delta: CGFloat) -> EngravedStem {
        EngravedStem(
            noteIDs: noteIDs,
            direction: direction,
            start: CGPoint(x: start.x, y: start.y + delta),
            end: CGPoint(x: end.x, y: end.y + delta)
        )
    }
}

extension EngravedBeam {
    func translated(byY delta: CGFloat) -> EngravedBeam {
        EngravedBeam(
            noteIDs: noteIDs,
            direction: direction,
            level: level,
            kind: kind,
            start: CGPoint(x: start.x, y: start.y + delta),
            end: CGPoint(x: end.x, y: end.y + delta),
            thickness: thickness
        )
    }
}

extension EngravedFlag {
    func translated(byY delta: CGFloat) -> EngravedFlag {
        EngravedFlag(
            noteID: noteID,
            stemDirection: stemDirection,
            duration: duration,
            flagIndex: flagIndex,
            origin: CGPoint(x: origin.x, y: origin.y + delta)
        )
    }
}

extension EngravedBeamKind {
    /// The topology segment kind this engraved segment mirrors.
    init(_ kind: BeamSegmentKind) {
        switch kind {
        case .full: self = .full
        case .forwardHook: self = .forwardHook
        case .backwardHook: self = .backwardHook
        }
    }
}
