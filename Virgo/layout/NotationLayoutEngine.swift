import CoreGraphics
import Foundation

/// Core layout engine - handles measure construction and note head placement.
// swiftlint:disable:next type_body_length
struct NotationLayoutEngine {
    private static let columnResolution = 960.0
    private static let topStaffStep = -8
    private static let bottomStaffStep = 0

    private struct VoiceCollisionColumn: Hashable {
        let measureIndex: Int
        let quantizedColumn: Int
    }
    private struct NoteHeadDraft {
        let noteHead: RenderedNoteHead
        let collisionColumn: VoiceCollisionColumn
    }

    struct BeamGroupKey: Hashable {
        let measureIndex: Int
        let row: Int
        let voice: NotationVoice
        let stemDirection: StemDirection
    }

    func layout(input: NotationLayoutInput) -> NotationLayout {
        let sortedNotes = input.notes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
            < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }
        let maxNormalizedMeasureIndex = sortedNotes.map { note in
            MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
                measureNumber: note.measureNumber, measureOffset: note.measureOffset
            ))
        }.max() ?? 0
        let totalMeasures = max(input.minimumMeasureCount, maxNormalizedMeasureIndex + 1, 1)
        let tabGrid = buildTabGrid(notes: sortedNotes, input: input)
        let measures = buildMeasures(totalMeasures: totalMeasures, tabGrid: tabGrid, input: input)
        let noteHeads = buildNoteHeads(notes: sortedNotes, measures: measures, tabGrid: tabGrid, input: input)
        let beams = buildBeams(noteHeads: noteHeads, style: input.style)
        let stems = buildStems(noteHeads: noteHeads, beams: beams, style: input.style)
        let flags = buildFlags(noteHeads: noteHeads, beams: beams, stems: stems, style: input.style)
        let ledgerLines = buildLedgerLines(noteHeads: noteHeads, style: input.style)
        let measureBars = buildMeasureBars(measures: measures)
        let noteHeadPositionsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0.position) })
        let noteHeadIDsByTimePosition = Dictionary(
            grouping: noteHeads,
            by: { NotationLayout.timePositionKey($0.timePosition) }
        ).mapValues { Set($0.map(\.id)) }
        let totalHeight = GameplayLayout.totalHeight(
            for: measures.map {
                GameplayLayout.MeasurePosition(row: $0.row, xOffset: $0.xOffset, measureIndex: $0.measureIndex)
            }
        )

        return NotationLayout(
            tabGrid: tabGrid,
            measures: measures,
            noteHeads: noteHeads,
            stems: stems,
            beams: beams,
            flags: flags,
            ledgerLines: ledgerLines,
            measureBars: measureBars,
            noteHeadPositionsByID: noteHeadPositionsByID,
            noteHeadIDsByTimePosition: noteHeadIDsByTimePosition,
            totalHeight: totalHeight
        )
    }

    // MARK: - Tab Grid

    private func buildTabGrid(notes: [Note], input: NotationLayoutInput) -> TabGrid {
        let ticksPerMeasure = resolvedTicksPerMeasure(for: notes)
        let requiredGap = requiredGridColumnGap(notes: notes, input: input)
        let baselineGap = max(ticksPerMeasure / 16, 1)
        let occupiedTicks = Set(notes.map { tickWithinMeasure(for: $0, ticksPerMeasure: ticksPerMeasure) })
        let actualSmallestGap = smallestPositiveGap(in: occupiedTicks.sorted())
        let spacingTickGap = min(actualSmallestGap ?? baselineGap, baselineGap)
        let tickWidth = requiredGap / CGFloat(max(spacingTickGap, 1))
        let leftPadding = GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
        let measureWidth = GameplayLayout.barLineWidth + leftPadding + CGFloat(ticksPerMeasure) * tickWidth

        return TabGrid(
            ticksPerMeasure: ticksPerMeasure,
            tickWidth: tickWidth,
            leftPadding: leftPadding,
            measureWidth: measureWidth
        )
    }

    private func resolvedTicksPerMeasure(for notes: [Note]) -> Int {
        let values = Set(notes.compactMap { note -> Int? in
            guard let ticks = note.normalizedTicksPerMeasure, ticks > 0 else { return nil }
            return ticks
        })

        guard !values.isEmpty else { return TabGrid.fallbackTicksPerMeasure }

        return values.sorted().reduce(1) { partial, value in
            guard let next = leastCommonMultiple(partial, value), next <= TabGrid.fallbackTicksPerMeasure * 64 else {
                return TabGrid.fallbackTicksPerMeasure
            }
            return next
        }
    }

    private func leastCommonMultiple(_ lhs: Int, _ rhs: Int) -> Int? {
        guard lhs > 0, rhs > 0 else { return nil }
        let divisor = greatestCommonDivisor(lhs, rhs)
        let divided = lhs / divisor
        guard divided <= Int.max / rhs else { return nil }
        return divided * rhs
    }

    private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            let next = a % b
            a = b
            b = next
        }
        return abs(a)
    }

    private func requiredGridColumnGap(notes: [Note], input: NotationLayoutInput) -> CGFloat {
        let hasCollision = notes.contains { note in
            let measure = normalizedMeasureIndex(for: note)
            return containsCrossVoiceCollision(measureIndex: measure, notes: notes)
        }

        return hasCollision
            ? input.style.minimumNoteColumnGap + 2 * input.style.voiceCollisionOffset
            : input.style.minimumNoteColumnGap
    }

    private func smallestPositiveGap(in ticks: [Int]) -> Int? {
        guard ticks.count > 1 else { return nil }
        return zip(ticks.dropFirst(), ticks)
            .map { $0.0 - $0.1 }
            .filter { $0 > 0 }
            .min()
    }

    // MARK: - Measure Building

    private func buildMeasures(
        totalMeasures: Int,
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> [RenderedMeasure] {
        var result: [RenderedMeasure] = []
        var currentRow = 0
        var currentX = GameplayLayout.leftMargin

        for measureIndex in 0..<totalMeasures {
            if currentX + tabGrid.measureWidth > input.style.rowWidth, measureIndex > 0 {
                currentRow += 1
                currentX = GameplayLayout.leftMargin
            }
            result.append(
                RenderedMeasure(
                    id: measureIndex, measureIndex: measureIndex,
                    row: currentRow, xOffset: currentX, width: tabGrid.measureWidth
                )
            )
            currentX += tabGrid.measureWidth + GameplayLayout.measureSpacing
        }

        return result
    }

    func containsCrossVoiceCollision(measureIndex: Int, notes: [Note]) -> Bool {
        Dictionary(
            grouping: notes.filter { normalizedMeasureIndex(for: $0) == measureIndex },
            by: { quantizedColumn(for: normalizedOffset(for: $0)) }
        )
        .values
        .contains { columnNotes in
            let voices = Set(columnNotes.compactMap { note -> NotationVoice? in
                guard let drumType = DrumType.from(noteType: note.noteType) else {
                    return nil
                }
                return NotationVoice.voice(for: drumType)
            })

            return voices.count > 1
        }
    }

    // MARK: - Note Head Building

    private func buildNoteHeads(
        notes: [Note],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> [RenderedNoteHead] {
        var nextID: UInt64 = 0
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        var drafts: [NoteHeadDraft] = []

        for note in notes {
            guard let drumType = DrumType.from(noteType: note.noteType) else { continue }
            let timePos = MeasureUtils.timePosition(
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset
            )
            let normalizedMeasureIndex = MeasureUtils.measureIndex(from: timePos)
            let normalizedOffset = timePos - Double(normalizedMeasureIndex)
            guard let measure = measuresByIndex[normalizedMeasureIndex] else { continue }
            let tickIndex = tickWithinMeasure(for: note, ticksPerMeasure: tabGrid.ticksPerMeasure)
            let x = tabGrid.xPosition(in: measure, tickIndex: tickIndex)
            let resolvedPosition = notePosition(for: drumType, overrides: input.notePositionOverrides)
            let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                + resolvedPosition.yOffset
            let voice = NotationVoice.voice(for: drumType)
            let direction = stemDirection(for: resolvedPosition, voice: voice)
            nextID += 1
            drafts.append(
                NoteHeadDraft(
                    noteHead: RenderedNoteHead(
                        id: nextID - 1,
                        sourceNoteID: ObjectIdentifier(note),
                        drumType: drumType,
                        voice: voice,
                        timePosition: timePos,
                        measureIndex: normalizedMeasureIndex,
                        row: measure.row,
                        position: CGPoint(x: x, y: y),
                        staffStep: staffStep(for: resolvedPosition),
                        stemDirection: direction,
                        interval: note.interval
                    ),
                    collisionColumn: VoiceCollisionColumn(
                        measureIndex: normalizedMeasureIndex,
                        quantizedColumn: quantizedColumn(for: normalizedOffset)
                    )
                )
            )
        }

        return applyVoiceCollisionOffsets(to: drafts, style: input.style)
    }

    private func applyVoiceCollisionOffsets(
        to drafts: [NoteHeadDraft],
        style: NotationLayoutStyle
    ) -> [RenderedNoteHead] {
        let collisionColumns = Set(
            Dictionary(grouping: drafts, by: \.collisionColumn).compactMap { column, drafts in
                Set(drafts.map(\.noteHead.voice)).count > 1 ? column : nil
            }
        )

        let offsetHeads = drafts.map { draft -> RenderedNoteHead in
            let noteHead = draft.noteHead
            guard collisionColumns.contains(draft.collisionColumn) else {
                return noteHead
            }

            let xOffset = noteHead.voice == .upper
                ? style.voiceCollisionOffset
                : -style.voiceCollisionOffset
            return RenderedNoteHead(
                id: noteHead.id,
                sourceNoteID: noteHead.sourceNoteID,
                drumType: noteHead.drumType,
                voice: noteHead.voice,
                timePosition: noteHead.timePosition,
                measureIndex: noteHead.measureIndex,
                row: noteHead.row,
                position: CGPoint(
                    x: noteHead.position.x + xOffset,
                    y: noteHead.position.y
                ),
                staffStep: noteHead.staffStep,
                stemDirection: noteHead.stemDirection,
                interval: noteHead.interval
            )
        }

        let unified = applyChordDirectionUnification(to: offsetHeads)
        return applyBeamRunDirectionUnification(to: unified)
    }

    /// Unifies stemDirection for each same-voice chord (notes that share x, row,
    /// measureIndex, and voice). Without this, a chord with notes whose individual
    /// default directions disagree (e.g. crash on aboveLine5 → .down + snare on
    /// line3 → .up, both upper voice) would be split into two stems on opposite
    /// sides of the column. The chord adopts the direction of the notehead
    /// farthest from the middle staff line, matching standard engraving practice.
    private func applyChordDirectionUnification(
        to noteHeads: [RenderedNoteHead]
    ) -> [RenderedNoteHead] {
        struct ChordKey: Hashable {
            let x: Int
            let row: Int
            let measureIndex: Int
            let voice: NotationVoice
        }
        let middleStaffStep = -4  // line3 is at yOffset -40 → staffStep -4
        let groups = Dictionary(grouping: noteHeads) { head in
            ChordKey(
                x: Int((head.position.x * 1000).rounded()),
                row: head.row,
                measureIndex: head.measureIndex,
                voice: head.voice
            )
        }
        var unifiedDirectionByID: [UInt64: StemDirection] = [:]
        for (_, chord) in groups where chord.count > 1 {
            // Only consider heads that actually need stems when choosing direction.
            // Stemless heads (full/half notes) would never render a stem, so they
            // must not drive the unified direction for stemmed notes.
            let stemmed = chord.filter { $0.interval.needsStem }
            guard Set(stemmed.map(\.stemDirection)).count > 1 else { continue }
            let farthest = stemmed.max {
                let dist0 = abs($0.staffStep - middleStaffStep)
                let dist1 = abs($1.staffStep - middleStaffStep)
                if dist0 != dist1 { return dist0 < dist1 }
                // Tie-break: prefer higher staffStep (closer to top of staff)
                return $0.staffStep < $1.staffStep
            }
            guard let direction = farthest?.stemDirection else { continue }
            // Only apply unified direction to heads that actually render stems.
            for head in stemmed {
                unifiedDirectionByID[head.id] = direction
            }
        }

        return noteHeads.map { head in
            guard let newDirection = unifiedDirectionByID[head.id],
                  newDirection != head.stemDirection else {
                return head
            }
            return RenderedNoteHead(
                id: head.id,
                sourceNoteID: head.sourceNoteID,
                drumType: head.drumType,
                voice: head.voice,
                timePosition: head.timePosition,
                measureIndex: head.measureIndex,
                row: head.row,
                position: head.position,
                staffStep: head.staffStep,
                stemDirection: newDirection,
                interval: head.interval
            )
        }
    }

    /// Unifies stem direction across each beam run (same voice, measure, row)
    /// so that chord direction unification does not split adjacent beamable
    /// notes into separate groups. For example, a crash+snare chord at offset 0
    /// whose direction is unified to `.down` followed by a solo snare at offset
    /// 0.125 (natural `.up`) would otherwise be keyed into different beam
    /// groups and render as isolated flags instead of a connected beam.
    private func applyBeamRunDirectionUnification(
        to noteHeads: [RenderedNoteHead]
    ) -> [RenderedNoteHead] {
        struct RunGroupKey: Hashable {
            let measureIndex: Int
            let row: Int
            let voice: NotationVoice
        }

        let grouped = Dictionary(grouping: noteHeads) { head in
            RunGroupKey(measureIndex: head.measureIndex, row: head.row, voice: head.voice)
        }

        var directionOverrides: [UInt64: StemDirection] = [:]
        let middleStaffStep = -4

        for (_, heads) in grouped {
            let beamableHeads = heads.filter { $0.interval.needsFlag }
            let runs = beamRuns(from: beamableHeads)

            for run in runs where run.count >= 2 {
                let directions = Set(run.map(\.stemDirection))
                guard directions.count > 1 else { continue }

                // Pick the direction of the note farthest from the middle
                // staff line, matching the chord-unification heuristic.
                let farthest = run.max {
                    let dist0 = abs($0.staffStep - middleStaffStep)
                    let dist1 = abs($1.staffStep - middleStaffStep)
                    if dist0 != dist1 { return dist0 < dist1 }
                    return $0.staffStep < $1.staffStep
                }
                guard let unifiedDir = farthest?.stemDirection else { continue }

                for head in run {
                    directionOverrides[head.id] = unifiedDir
                }
            }
        }

        return noteHeads.map { head in
            guard let newDir = directionOverrides[head.id],
                  newDir != head.stemDirection else {
                return head
            }
            return RenderedNoteHead(
                id: head.id,
                sourceNoteID: head.sourceNoteID,
                drumType: head.drumType,
                voice: head.voice,
                timePosition: head.timePosition,
                measureIndex: head.measureIndex,
                row: head.row,
                position: head.position,
                staffStep: head.staffStep,
                stemDirection: newDir,
                interval: head.interval
            )
        }
    }

    // MARK: - Helpers

    private func tickWithinMeasure(for note: Note, ticksPerMeasure: Int) -> Int {
        if let sourceTick = note.normalizedTickWithinMeasure,
           let sourceTicksPerMeasure = note.normalizedTicksPerMeasure,
           sourceTick >= 0,
           sourceTicksPerMeasure > 0,
           sourceTick <= sourceTicksPerMeasure,
           ticksPerMeasure.isMultiple(of: sourceTicksPerMeasure) {
            return min(sourceTick * (ticksPerMeasure / sourceTicksPerMeasure), ticksPerMeasure)
        }

        let offset = normalizedOffset(for: note)
        return min(max(Int((offset * Double(ticksPerMeasure)).rounded()), 0), ticksPerMeasure)
    }

    private func normalizedMeasureIndex(for note: Note) -> Int {
        MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        ))
    }

    private func normalizedOffset(for note: Note) -> Double {
        let timePos = MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        )
        return timePos - Double(MeasureUtils.measureIndex(from: timePos))
    }

    private func quantizedColumn(for measureOffset: Double) -> Int {
        Int((measureOffset * Self.columnResolution).rounded())
    }

    private func staffStep(for position: GameplayLayout.NotePosition) -> Int {
        Int((position.yOffset / (GameplayLayout.staffLineSpacing / 2)).rounded())
    }

    private func notePosition(
        for drumType: DrumType,
        overrides: [DrumType: GameplayLayout.NotePosition]
    ) -> GameplayLayout.NotePosition {
        overrides[drumType] ?? drumType.notePosition
    }

    private func stemDirection(
        for position: GameplayLayout.NotePosition,
        voice: NotationVoice
    ) -> StemDirection {
        guard voice == .upper else { return .down }

        switch position {
        case .aboveLine9, .aboveLine8, .aboveLine7, .aboveLine6, .aboveLine5, .line5:
            return .down
        case .spaceBetween4And5, .line4, .spaceBetween3And4, .line3,
             .spaceBetween2And3, .line2, .spaceBetween1And2, .line1,
             .spaceBetweenLine1AndBelow, .belowLine1, .belowLine2,
             .belowLine3, .belowLine4, .belowLine5, .belowLine6:
            return .up
        }
    }

    // MARK: - Rendering Primitives (delegated to fileprivate extension)

    private func buildStems(
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

        // Group note heads that share the same x, voice, and stem direction
        // (i.e., chord tones) so they share a single stem instead of overlapping.
        struct StemGroupKey: Hashable {
            let x: Int // Rounded to avoid floating-point drift
            let row: Int
            let measureIndex: Int
            let voice: NotationVoice
            let direction: StemDirection
        }

        let grouped = Dictionary(grouping: headsNeedingStems) { head in
            StemGroupKey(
                x: Int((head.position.x * 1000).rounded()),
                row: head.row,
                measureIndex: head.measureIndex,
                voice: head.voice,
                direction: head.stemDirection
            )
        }

        return grouped.compactMap { key, group in
            let allIDs = group.map(\.id)

            let representative: RenderedNoteHead
            switch key.direction {
            case .up:
                guard let r = group.max(by: { $0.position.y < $1.position.y }) else {
                    Logger.error("Stem grouping empty for key \(key) — skipping"); return nil
                }
                representative = r
            case .down:
                guard let r = group.min(by: { $0.position.y < $1.position.y }) else {
                    Logger.error("Stem grouping empty for key \(key) — skipping"); return nil
                }
                representative = r
            }

            let start = stemStart(for: representative, style: style)

            let candidateBeams = group.flatMap { head in
                beamsByNoteHeadID[head.id] ?? []
            }
            let outermostBeam = key.direction == .up
                ? candidateBeams.min(by: { $0.start.y < $1.start.y })
                : candidateBeams.max(by: { $0.start.y < $1.start.y })

            if let beam = outermostBeam,
               let beamY = beamEndY(for: representative, beam: beam, style: style) {
                return RenderedStem(
                    id: "stem_group_\(key.x)_r\(key.row)_m\(key.measureIndex)_\(key.voice.rawValue)_\(key.direction.rawValue)",
                    noteHeadIDs: allIDs,
                    direction: key.direction,
                    start: start,
                    end: CGPoint(x: start.x, y: beamY)
                )
            }
            // Not beamed — use fixed stem length from the representative head.
            let endY: CGFloat = switch key.direction {
            case .up: start.y - style.stemLength
            case .down: start.y + style.stemLength
            }

            return RenderedStem(
                id: "stem_group_\(key.x)_r\(key.row)_m\(key.measureIndex)_\(key.voice.rawValue)_\(key.direction.rawValue)",
                noteHeadIDs: allIDs,
                direction: key.direction,
                start: start,
                end: CGPoint(x: start.x, y: endY)
            )
        }
    }

    /// Computes stem end Y from beam geometry if noteHead is beamed.
    private func beamEndY(
        for noteHead: RenderedNoteHead,
        beam: RenderedBeam,
        style: NotationLayoutStyle
    ) -> Double? {
        // Only extend to beam if beam has multiple note heads.
        guard beam.noteHeadIDs.count > 1 else { return nil }

        let startX = beam.start.x, endX = beam.end.x
        let stemX = stemStart(for: noteHead, style: style).x

        guard stemX >= min(startX, endX) && stemX <= max(startX, endX) else { return nil }

        guard endX != startX else { return nil }

        let t = (stemX - startX) / (endX - startX)
        let beamY = beam.start.y + t * (beam.end.y - beam.start.y)

        // For upward stems, beam is above notehead so stem extends to beam Y.
        // For downward stems, beam is below notehead so stem extends to beam Y.
        return beamY
    }

    private func buildBeams(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedBeam] {
        let groupedHeads = Dictionary(grouping: noteHeads) {
            BeamGroupKey(
                measureIndex: $0.measureIndex,
                row: $0.row,
                voice: $0.voice,
                stemDirection: $0.stemDirection
            )
        }

        return groupedHeads.values
            .flatMap { heads in
                beamRuns(from: Array(heads)).flatMap { run in
                    beams(for: run, style: style)
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

    private func buildFlags(
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

        // Index stems by noteHeadID so flags can look up the beam-adjusted
        // stem end Y instead of assuming a fixed stem length.
        var stemEndByNoteHeadID: [UInt64: CGFloat] = [:]
        for stem in stems {
            for noteHeadID in stem.noteHeadIDs {
                stemEndByNoteHeadID[noteHeadID] = stem.end.y
            }
        }

        // Deduplicate: chord notes sharing a stem (same x, row, measure, voice,
        // direction) must emit flags only once from the representative head that
        // needs the most flags.  Without this, unified mixed-direction chords
        // would draw overlapping flags for every note head on the shared stem.
        struct FlagGroupKey: Hashable {
            let x: Int
            let row: Int
            let measureIndex: Int
            let voice: NotationVoice
            let direction: StemDirection
        }
        var flaggedHeads = noteHeads.filter { $0.interval.needsFlag }
        // Pick one representative per stem group — the one with the most total flags.
        var bestByKey: [FlagGroupKey: RenderedNoteHead] = [:]
        for head in flaggedHeads {
            let key = FlagGroupKey(
                x: Int((head.position.x * 1000).rounded()),
                row: head.row,
                measureIndex: head.measureIndex,
                voice: head.voice,
                direction: head.stemDirection
            )
            let existing = bestByKey[key]
            if existing == nil || head.interval.flagCount > existing!.interval.flagCount {
                bestByKey[key] = head
            }
        }
        let representatives = Set(bestByKey.values.map(\.id))

        return flaggedHeads
            .filter { representatives.contains($0.id) }
            .flatMap { noteHead -> [RenderedFlag] in
                let coveredLevels = coveredLevelsByNoteHead[noteHead.id] ?? 0
                let totalFlags = noteHead.interval.flagCount
                guard coveredLevels < totalFlags else { return [] }

                let stemBottom = stemStart(for: noteHead, style: style)

                // Use beam-adjusted stem end when available; fall back to
                // default stem length for unbeamed notes.
                let stemEndY: CGFloat
                if let adjustedEndY = stemEndByNoteHeadID[noteHead.id] {
                    stemEndY = adjustedEndY
                } else {
                    stemEndY = noteHead.stemDirection == .up
                        ? stemBottom.y - style.stemLength
                        : stemBottom.y + style.stemLength
                }

                let flagOrigin = CGPoint(
                    x: stemBottom.x + GameplayLayout.flagXOffset,
                    y: stemEndY
                )

                return (coveredLevels..<totalFlags).map { flagIndex in
                    let flagLevel = flagIndex - coveredLevels
                    // Unbeamed notes: first flag at stem tip (offset 0).
                    // Beamed notes: remaining flags offset from beam level.
                    let yMultiplier: CGFloat
                    if coveredLevels == 0 {
                        yMultiplier = CGFloat(flagLevel)
                    } else {
                        yMultiplier = CGFloat(flagLevel + 1)
                    }
                    // Flags stack toward the note head: positive-y (downward) for
                    // up-stem, negative-y (upward) for down-stem.
                    let yOffset = noteHead.stemDirection == .up
                        ? yMultiplier * GameplayLayout.flagVerticalSpacing
                        : -yMultiplier * GameplayLayout.flagVerticalSpacing

                    return RenderedFlag(
                        id: "flag_\(noteHead.id)_\(flagIndex)",
                        noteHeadID: noteHead.id,
                        stemDirection: noteHead.stemDirection,
                        flagIndex: flagIndex,
                        origin: CGPoint(x: flagOrigin.x, y: flagOrigin.y + yOffset)
                    )
                }
            }
    }

    private func buildLedgerLines(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedLedgerLine] {
        noteHeads.flatMap { noteHead in
            ledgerSteps(for: noteHead.staffStep).map { step in
                let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: noteHead.row)
                    + CGFloat(step) * (style.staffLineSpacing / 2)
                let overhang = style.noteHeadWidth / 2 + style.ledgerLineOverhang

                return RenderedLedgerLine(
                    id: "ledger_\(noteHead.id)_\(step)",
                    row: noteHead.row,
                    start: CGPoint(x: noteHead.position.x - overhang, y: y),
                    end: CGPoint(x: noteHead.position.x + overhang, y: y)
                )
            }
        }
    }

    func buildMeasureBars(measures: [RenderedMeasure]) -> [RenderedMeasureBar] {
        var bars: [RenderedMeasureBar] = []

        for (index, measure) in measures.enumerated() {
            let isFirstInRow = index == 0 || measures[index - 1].row != measure.row
            let isLastOverall = measure.measureIndex == measures.last?.measureIndex

            if isFirstInRow {
                bars.append(RenderedMeasureBar(
                    id: "bar_\(measure.measureIndex)",
                    row: measure.row,
                    x: measure.xOffset,
                    isFinal: false
                ))
            }

            let nextOnSameRow = measures.count > index + 1
                && measures[index + 1].row == measure.row
            let endX: CGFloat
            if nextOnSameRow {
                endX = measures[index + 1].xOffset
            } else {
                endX = measure.xOffset + measure.width
            }

            bars.append(RenderedMeasureBar(
                id: "bar_\(measure.measureIndex)_end",
                row: measure.row,
                x: endX,
                isFinal: isLastOverall
            ))
        }

        return bars
    }

    // MARK: - Beam Helpers

    private func beamRuns(from noteHeads: [RenderedNoteHead]) -> [[RenderedNoteHead]] {
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

    private func beams(
        for noteHeads: [RenderedNoteHead],
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

                // Horizontal beam: choose the extremum stem-tip Y across the
                // full run (not just this level's subset) so all beam levels
                // stack consistently outward from the same reference point.
                // Using only levelHeads could place a secondary beam between
                // the primary beam and the noteheads when the subset has
                // different pitch extremes.
                let sharedY = sharedBeamY(for: noteHeads, level: level, style: style)
                let startX = stemStart(for: firstHead, style: style).x
                let endX = stemStart(for: lastHead, style: style).x
                let start = CGPoint(x: startX, y: sharedY)
                let end = CGPoint(x: endX, y: sharedY)
                guard hasPositiveBeamSpan(from: firstHead, to: lastHead, start: start, end: end) else {
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

    private func sharedBeamY(
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

    private func beamSegments(
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

    private func hasPositiveBeamSpan(
        from firstHead: RenderedNoteHead,
        to lastHead: RenderedNoteHead,
        start: CGPoint,
        end: CGPoint
    ) -> Bool {
        abs(lastHead.timePosition - firstHead.timePosition) > BeamGroupingConstants.comparisonTolerance
            && abs(end.x - start.x) > BeamGroupingConstants.comparisonTolerance
    }

    private func stemStart(
        for noteHead: RenderedNoteHead,
        style: NotationLayoutStyle
    ) -> CGPoint {
        let xOffset = switch noteHead.stemDirection {
        case .up:
            style.stemXInset
        case .down:
            -style.stemXInset
        }

        return CGPoint(x: noteHead.position.x + xOffset, y: noteHead.position.y)
    }

    private func ledgerSteps(for staffStep: Int) -> [Int] {
        if staffStep < Self.topStaffStep {
            return stride(from: Self.topStaffStep - 2, through: staffStep, by: -2).map { $0 }
        }
        if staffStep > Self.bottomStaffStep {
            return stride(from: Self.bottomStaffStep + 2, through: staffStep, by: 2).map { $0 }
        }
        return []
    }
}
