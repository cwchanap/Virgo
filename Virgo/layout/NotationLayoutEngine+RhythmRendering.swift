import CoreGraphics

struct NotationLayoutFinalizationInput {
    let tabGrid: TabGrid
    let measures: [RenderedMeasure]
    let noteHeads: [RenderedNoteHead]
    let rests: [RenderedRest]
    let stopNotes: [RenderedStopNote]
    let articulations: [RenderedArticulation]
    let derived: NotationLayoutEngine.BuiltDerivedArtifacts
    let rhythmDots: [RenderedRhythmDot]
    let tuplets: [RenderedTuplet]
    let feelMarks: [RenderedFeelMark]
    let rhythmWarnings: [RenderedRhythmWarning]
    let style: NotationLayoutStyle
}

struct TupletRenderingContext {
    let beams: [RenderedBeam]
    let feel: RhythmicFeel
    let rhythmMeasures: [RhythmMeasure]
    let unsupportedMeasureIndexes: Set<Int>
    let style: NotationLayoutStyle
}

extension NotationLayoutEngine {
    func finalizedLayout(_ input: NotationLayoutFinalizationInput) -> NotationLayout {
        let positionsByID = Dictionary(uniqueKeysWithValues: input.noteHeads.map { ($0.id, $0.position) })
        let idsByTick = Dictionary(grouping: input.noteHeads, by: { $0.timeColumn.absoluteLayoutTick })
            .mapValues { Set($0.map(\.id)) }
        let baseHeight = GameplayLayout.totalHeight(for: input.measures.map {
            GameplayLayout.MeasurePosition(row: $0.row, xOffset: $0.xOffset, measureIndex: $0.measureIndex)
        })
        var layout = NotationLayout(
            tabGrid: input.tabGrid,
            measures: input.measures,
            noteHeadSize: input.style.noteHeadSize,
            noteHeads: input.noteHeads,
            rests: input.rests,
            stopNotes: input.stopNotes,
            articulations: input.articulations,
            stems: input.derived.stems,
            beams: input.derived.beams,
            flags: input.derived.flags,
            ledgerLines: input.derived.ledgerLines,
            measureBars: input.derived.measureBars,
            rhythmDots: input.rhythmDots,
            tuplets: input.tuplets,
            feelMarks: input.feelMarks,
            rhythmWarnings: input.rhythmWarnings,
            noteHeadPositionsByID: positionsByID,
            noteHeadIDsByLayoutTick: idsByTick,
            totalHeight: baseHeight
        )
        layout.paintedBounds = layout.calculatePaintedBounds(style: input.style)
        if !layout.paintedBounds.isNull {
            layout.totalHeight = max(baseHeight, layout.paintedBounds.maxY)
        }
        return layout
    }

    func buildRhythmDots(
        noteHeads: [RenderedNoteHead],
        rests: [RenderedRest],
        unsupportedMeasureIndexes: Set<Int>,
        style: NotationLayoutStyle
    ) -> [RenderedRhythmDot] {
        let noteDots = noteHeads.compactMap { head -> RenderedRhythmDot? in
            guard head.rhythm.dotCount == 1,
                  !unsupportedMeasureIndexes.contains(head.measureIndex),
                  let eventID = head.eventID else { return nil }
            let bounds = head.paintedBounds(style: style)
            return RenderedRhythmDot(
                source: .event(eventID),
                position: CGPoint(
                    x: bounds.maxX + style.rhythmDotSpacing + style.rhythmDotRadius,
                    y: head.position.y
                ),
                rowIndex: head.row
            )
        }
        let restDots = rests.compactMap { rest -> RenderedRhythmDot? in
            guard rest.isPrinted,
                  rest.rhythm.dotCount == 1,
                  !unsupportedMeasureIndexes.contains(rest.measureIndex) else { return nil }
            let bounds = rest.paintedBounds(style: style)
            return RenderedRhythmDot(
                source: .rest(rest.id),
                position: CGPoint(
                    x: bounds.maxX + style.rhythmDotSpacing + style.rhythmDotRadius,
                    y: rest.position.y
                ),
                rowIndex: rest.row
            )
        }
        return noteDots + restDots
    }

    func buildTuplets(
        noteHeads: [RenderedNoteHead],
        rests: [RenderedRest],
        context: TupletRenderingContext
    ) -> [RenderedTuplet] {
        let ids = Set(noteHeads.compactMap(\.tupletID) + rests.compactMap(\.tupletID))
        return ids
            .filter {
                !context.unsupportedMeasureIndexes.contains($0.measureIndex)
                    && !isDeclaredFeelPair(
                        id: $0,
                        feel: context.feel,
                        noteHeads: noteHeads,
                        rests: rests,
                        rhythmMeasures: context.rhythmMeasures
                    )
            }
            .compactMap { id in
                renderedTuplet(
                    id: id,
                    noteHeads: noteHeads,
                    rests: rests,
                    beams: context.beams,
                    style: context.style
                )
            }
            .sorted { lhs, rhs in
                if lhs.id.measureIndex != rhs.id.measureIndex { return lhs.id.measureIndex < rhs.id.measureIndex }
                if lhs.id.startTick != rhs.id.startTick { return lhs.id.startTick < rhs.id.startTick }
                return lhs.id.stableMemberEventID.rawValue < rhs.id.stableMemberEventID.rawValue
            }
    }

    func isDeclaredFeelPair(
        id: RhythmTupletID,
        feel: RhythmicFeel,
        noteHeads: [RenderedNoteHead],
        rests: [RenderedRest],
        rhythmMeasures: [RhythmMeasure]
    ) -> Bool {
        guard feel == .swing || feel == .shuffle,
              rests.allSatisfy({ $0.tupletID != id }),
              id.durationTicks > 0,
              id.durationTicks.isMultiple(of: 3),
              let measure = rhythmMeasures.first(where: { $0.measureIndex == id.measureIndex }),
              let beatGroup = measure.beatGroups.first(where: { $0.groupIndex == id.beatGroupIndex }),
              beatGroup.startTick == id.startTick,
              beatGroup.durationTicks == id.durationTicks else { return false }
        let members = noteHeads.filter { $0.tupletID == id }.sorted {
            $0.rhythmPosition.localTick < $1.rhythmPosition.localTick
        }
        let slot = id.durationTicks / 3
        let membersByOnset = Dictionary(grouping: members, by: { $0.rhythmPosition.localTick })
        let occupiedOnsets = membersByOnset.keys.sorted()
        guard occupiedOnsets == [id.startTick, id.startTick + slot * 2],
              members.allSatisfy({ $0.rhythm.tuplet == TupletRatio(actual: 3, normal: 2) }),
              membersByOnset[id.startTick, default: []].allSatisfy({ $0.rhythmDurationTicks == slot * 2 }),
              membersByOnset[id.startTick + slot * 2, default: []]
                .allSatisfy({ $0.rhythmDurationTicks == slot }) else { return false }
        return true
    }

    func buildFeelMarks(
        feel: RhythmicFeel,
        measures: [RenderedMeasure],
        style: NotationLayoutStyle
    ) -> [RenderedFeelMark] {
        guard feel != .straight,
              let first = measures.min(by: {
                  $0.row == $1.row ? $0.xOffset < $1.xOffset : $0.row < $1.row
              }) else { return [] }
        let staffTop = min(
            GameplayLayout.StaffLinePosition.line1.absoluteY(for: first.row),
            GameplayLayout.StaffLinePosition.line5.absoluteY(for: first.row)
        )
        return [RenderedFeelMark(
            feel: feel,
            position: CGPoint(
                x: first.contentStartX + style.feelMarkSize.width / 2,
                y: staffTop - style.feelMarkVerticalOffset
            ),
            rowIndex: first.row,
            style: style
        )]
    }

    func buildRhythmWarnings(
        rhythmMeasures: [RhythmMeasure],
        renderedMeasures: [RenderedMeasure],
        style: NotationLayoutStyle
    ) -> [RenderedRhythmWarning] {
        let renderedByIndex = Dictionary(uniqueKeysWithValues: renderedMeasures.map { ($0.measureIndex, $0) })
        return rhythmMeasures.compactMap { measure in
            guard case .unsupported(let codes) = measure.engravingSupport,
                  let rendered = renderedByIndex[measure.measureIndex] else { return nil }
            let staffTop = min(
                GameplayLayout.StaffLinePosition.line1.absoluteY(for: rendered.row),
                GameplayLayout.StaffLinePosition.line5.absoluteY(for: rendered.row)
            )
            return RenderedRhythmWarning.measure(
                measureIndex: measure.measureIndex,
                codes: codes,
                position: CGPoint(
                    x: rendered.contentStartX + min(rendered.width, style.warningSize.width) / 2,
                    y: staffTop - style.warningVerticalOffset
                ),
                rowIndex: rendered.row,
                style: style
            )
        }
    }
}

private extension NotationLayoutEngine {
    func renderedTuplet(
        id: RhythmTupletID,
        noteHeads: [RenderedNoteHead],
        rests: [RenderedRest],
        beams: [RenderedBeam],
        style: NotationLayoutStyle
    ) -> RenderedTuplet? {
        let memberHeads = noteHeads.filter { $0.tupletID == id }
        let memberRests = rests.filter { $0.tupletID == id }
        guard let ratio = memberHeads.compactMap(\.rhythm.tuplet).first
                ?? memberRests.compactMap(\.rhythm.tuplet).first,
              !memberHeads.isEmpty || !memberRests.isEmpty else { return nil }
        let memberEventIDs = memberHeads.compactMap(\.eventID).sorted { $0.rawValue < $1.rawValue }
        let memberHeadIDs = Set(memberHeads.map(\.id))
        let memberBeams = beams.filter { beam in
            beam.noteHeadIDs.filter(memberHeadIDs.contains).count >= 2
        }
        let beamedHeadIDs = Set(memberBeams.flatMap(\.noteHeadIDs))
        let headsByOnset = Dictionary(grouping: memberHeads, by: { $0.timeColumn })
        let beamSpansEntireGroup = memberRests.isEmpty
            && !memberBeams.isEmpty
            && headsByOnset.values.allSatisfy { heads in
                heads.contains { beamedHeadIDs.contains($0.id) }
            }
        let direction = memberHeads.first?.stemDirection ?? (id.voice == .upper ? .up : .down)
        let memberBounds = memberHeads.map { $0.paintedBounds(style: style) }
            + memberRests.map { $0.paintedBounds(style: style) }
        guard let firstBounds = memberBounds.first else { return nil }
        let bounds = memberBounds.dropFirst().reduce(firstBounds) { $0.union($1) }
        let bracketVisible = !beamSpansEntireGroup
        let referenceY: CGFloat
        switch direction {
        case .up:
            referenceY = memberBeams.map(\.start.y).min() ?? bounds.minY
        case .down:
            referenceY = memberBeams.map(\.start.y).max() ?? bounds.maxY
        }
        let labelY = direction == .up
            ? referenceY - style.tupletVerticalOffset
            : referenceY + style.tupletVerticalOffset
        let labelPosition = CGPoint(x: bounds.midX, y: labelY)
        return RenderedTuplet(
            id: id,
            voice: id.voice,
            ratio: ratio,
            memberEventIDs: memberEventIDs,
            bracketPoints: bracketVisible
                ? tupletBracketPoints(
                    minX: bounds.minX,
                    maxX: bounds.maxX,
                    labelPosition: labelPosition,
                    direction: direction,
                    style: style
                ) : [],
            isBracketVisible: bracketVisible,
            labelPosition: labelPosition,
            rowIndex: memberHeads.first?.row ?? memberRests[0].row
        )
    }

    func tupletBracketPoints(
        minX: CGFloat,
        maxX: CGFloat,
        labelPosition: CGPoint,
        direction: StemDirection,
        style: NotationLayoutStyle
    ) -> [CGPoint] {
        let horizontalY = labelPosition.y
        let hookY = direction == .up
            ? horizontalY + style.tupletHookLength
            : horizontalY - style.tupletHookLength
        let halfGap = style.tupletLabelSize.width / 2 + style.rhythmDotSpacing
        return [
            CGPoint(x: minX, y: hookY),
            CGPoint(x: minX, y: horizontalY),
            CGPoint(x: max(minX, labelPosition.x - halfGap), y: horizontalY),
            CGPoint(x: min(maxX, labelPosition.x + halfGap), y: horizontalY),
            CGPoint(x: maxX, y: horizontalY),
            CGPoint(x: maxX, y: hookY)
        ]
    }
}
