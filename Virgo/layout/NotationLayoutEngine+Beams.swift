import CoreGraphics
import Foundation

/// Beam, stem, flag, and ledger line construction extracted from
/// NotationLayoutEngine to keep the main engine file under the SwiftLint
/// type-body limit.
extension NotationLayoutEngine {
    fileprivate struct StemGroupKey: Hashable {
        let timeColumn: NotationTimeColumn
        let row: Int
        let voice: NotationVoice
    }

    fileprivate struct BeamGroupKey: Hashable {
        let measureIndex: Int
        let row: Int
        let voice: NotationVoice
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
                voice: head.voice
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
    func beamEndY(
        for noteHead: RenderedNoteHead,
        beam: RenderedBeam,
        style: NotationLayoutStyle
    ) -> CGFloat? {
        // Only extend to beam if beam has multiple note heads.
        guard beam.noteHeadIDs.count > 1 else { return nil }

        let startX = beam.start.x, endX = beam.end.x
        let stemX = stemAnchor(for: noteHead, style: style).x

        guard stemX >= min(startX, endX) && stemX <= max(startX, endX) else { return nil }

        guard endX != startX else { return nil }

        // Beams are always horizontal (start.y == end.y, see sharedBeamY in
        // beams(for:chordLookup:style:)), so no interpolation is needed.
        return beam.start.y
    }

    func buildBeams(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedBeam] {
        let chordByStemGroupKey = Dictionary(
            grouping: noteHeads.filter { $0.interval.needsStem }
        ) {
            StemGroupKey(
                timeColumn: $0.timeColumn,
                row: $0.row,
                voice: $0.voice
            )
        }

        let groupedHeads = Dictionary(grouping: noteHeads) {
            BeamGroupKey(
                measureIndex: $0.measureIndex,
                row: $0.row,
                voice: $0.voice
            )
        }

        return groupedHeads.values
            .flatMap { heads in
                beamRuns(from: Array(heads)).flatMap { run in
                    beams(for: run, chordLookup: chordByStemGroupKey, style: style)
                }
            }
            .sorted {
                if $0.start.y != $1.start.y {
                    return $0.start.y < $1.start.y
                }
                if $0.start.x != $1.start.x {
                    return $0.start.x < $1.start.x
                }
                return $0.level < $1.level
            }
    }

    func buildFlags(
        noteHeads: [RenderedNoteHead],
        beams: [RenderedBeam],
        stems: [RenderedStem],
        style: NotationLayoutStyle
    ) -> [RenderedFlag] {
        var coveredLevelsByNoteHead: [UInt64: Int] = [:]
        for beam in beams {
            for noteHeadID in beam.noteHeadIDs {
                let current = coveredLevelsByNoteHead[noteHeadID] ?? 0
                coveredLevelsByNoteHead[noteHeadID] = max(current, beam.level + 1)
            }
        }

        var stemByNoteHeadID: [UInt64: RenderedStem] = [:]
        for stem in stems {
            for noteHeadID in stem.noteHeadIDs {
                stemByNoteHeadID[noteHeadID] = stem
            }
        }

        let flaggedHeads = noteHeads.filter { $0.interval.needsFlag }
        var bestByKey: [StemGroupKey: RenderedNoteHead] = [:]
        for head in flaggedHeads {
            let key = StemGroupKey(
                timeColumn: head.timeColumn,
                row: head.row,
                voice: head.voice
            )
            if let existing = bestByKey[key],
               existing.interval.flagCount >= head.interval.flagCount {
                continue
            }
            bestByKey[key] = head
        }
        let representatives = Set(bestByKey.values.map(\.id))

        return flaggedHeads
            .filter { representatives.contains($0.id) }
            .flatMap { noteHead -> [RenderedFlag] in
                let coveredLevels = coveredLevelsByNoteHead[noteHead.id] ?? 0
                let totalFlags = noteHead.interval.flagCount
                guard coveredLevels < totalFlags else { return [] }
                guard let stem = stemByNoteHeadID[noteHead.id] else {
                    Logger.error("Missing rendered stem for flagged head \(noteHead.id)")
                    return []
                }
                let flagOrigin = CGPoint(
                    x: stem.start.x + GameplayLayout.flagXOffset,
                    y: stem.end.y
                )

                return (coveredLevels..<totalFlags).map { flagIndex in
                    let flagLevel = flagIndex - coveredLevels
                    let yMultiplier = coveredLevels == 0
                        ? CGFloat(flagLevel)
                        : CGFloat(flagLevel + 1)
                    let yOffset = stem.direction == .up
                        ? yMultiplier * GameplayLayout.flagVerticalSpacing
                        : -yMultiplier * GameplayLayout.flagVerticalSpacing

                    return RenderedFlag(
                        id: "flag_\(noteHead.id)_\(flagIndex)",
                        noteHeadID: noteHead.id,
                        stemDirection: stem.direction,
                        flagIndex: flagIndex,
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

    func beamRuns(from noteHeads: [RenderedNoteHead]) -> [[RenderedNoteHead]] {
        let sortedHeads = noteHeads.sorted {
            if abs($0.timePosition - $1.timePosition) > BeamGroupingConstants.comparisonTolerance {
                return $0.timePosition < $1.timePosition
            }
            return $0.id < $1.id
        }
        var runs: [[RenderedNoteHead]] = []
        var currentRun: [RenderedNoteHead] = []

        for noteHead in sortedHeads {
            guard noteHead.interval.needsFlag else {
                if currentRun.count >= 2 {
                    runs.append(currentRun)
                }
                currentRun = []
                continue
            }

            if let previousHead = currentRun.last {
                let timeDifference = abs(noteHead.timePosition - previousHead.timePosition)
                if timeDifference <= BeamGroupingConstants.maxConsecutiveInterval
                    + BeamGroupingConstants.comparisonTolerance {
                    currentRun.append(noteHead)
                } else {
                    if currentRun.count >= 2 {
                        runs.append(currentRun)
                    }
                    currentRun = [noteHead]
                }
            } else {
                currentRun = [noteHead]
            }
        }

        if currentRun.count >= 2 {
            runs.append(currentRun)
        }

        return runs
    }

    fileprivate func beams(
        for noteHeads: [RenderedNoteHead],
        chordLookup: [StemGroupKey: [RenderedNoteHead]],
        style: NotationLayoutStyle
    ) -> [RenderedBeam] {
        let maxFlagCount = noteHeads.map(\.interval.flagCount).max() ?? 0

        return (0..<maxFlagCount).flatMap { level in
            beamSegments(for: noteHeads, level: level).compactMap { levelHeads in
                guard let firstHead = levelHeads.first,
                      let lastHead = levelHeads.last,
                      levelHeads.count >= 2 else {
                    return nil
                }

                let firstColumn = firstHead.timeColumn
                let lastColumn = lastHead.timeColumn
                guard firstColumn != lastColumn else {
                    return nil
                }
                let firstKey = StemGroupKey(
                    timeColumn: firstColumn,
                    row: firstHead.row,
                    voice: firstHead.voice
                )
                let lastKey = StemGroupKey(
                    timeColumn: lastColumn,
                    row: lastHead.row,
                    voice: lastHead.voice
                )
                let firstChord = chordLookup[firstKey] ?? {
                    Logger.warning("Beam chordLookup miss for firstKey \(firstKey); using singleton fallback")
                    return [firstHead]
                }()
                let lastChord = chordLookup[lastKey] ?? {
                    Logger.warning("Beam chordLookup miss for lastKey \(lastKey); using singleton fallback")
                    return [lastHead]
                }()
                guard let firstRepresentative = stemRepresentative(in: firstChord),
                      let lastRepresentative = stemRepresentative(in: lastChord) else {
                    return nil
                }
                let sharedY = sharedBeamY(for: noteHeads, level: level, style: style)
                let start = CGPoint(
                    x: stemAnchor(for: firstRepresentative, style: style).x,
                    y: sharedY
                )
                let end = CGPoint(
                    x: stemAnchor(for: lastRepresentative, style: style).x,
                    y: sharedY
                )
                guard abs(end.x - start.x) > BeamGroupingConstants.comparisonTolerance else {
                    return nil
                }

                return RenderedBeam(
                    id: "beam_\(firstHead.measureIndex)_\(firstHead.row)_\(firstHead.voice.rawValue)_"
                        + "\(firstHead.stemDirection.rawValue)_\(level)_\(firstHead.id)_\(lastHead.id)",
                    noteHeadIDs: levelHeads.map(\.id),
                    direction: firstHead.stemDirection,
                    level: level,
                    start: start,
                    end: end,
                    thickness: style.beamThickness
                )
            }
        }
    }

    func sharedBeamY(
        for noteHeads: [RenderedNoteHead],
        level: Int,
        style: NotationLayoutStyle
    ) -> CGFloat {
        let direction = noteHeads.first?.stemDirection ?? .up
        let levelOffset = CGFloat(level) * style.beamLevelSpacing
        let candidates = noteHeads.map { head -> CGFloat in
            switch direction {
            case .up: return head.position.y - style.stemLength - levelOffset
            case .down: return head.position.y + style.stemLength + levelOffset
            }
        }
        switch direction {
        case .up: return candidates.min() ?? 0
        case .down: return candidates.max() ?? 0
        }
    }

    func beamSegments(
        for noteHeads: [RenderedNoteHead],
        level: Int
    ) -> [[RenderedNoteHead]] {
        var segments: [[RenderedNoteHead]] = []
        var currentSegment: [RenderedNoteHead] = []

        for noteHead in noteHeads {
            if noteHead.interval.flagCount > level {
                currentSegment.append(noteHead)
            } else {
                if currentSegment.count >= 2 {
                    segments.append(currentSegment)
                }
                currentSegment = []
            }
        }

        if currentSegment.count >= 2 {
            segments.append(currentSegment)
        }

        return segments
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
        guard let direction = noteHeads.first?.stemDirection else {
            return nil
        }
        let ordered = noteHeads.sorted {
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
