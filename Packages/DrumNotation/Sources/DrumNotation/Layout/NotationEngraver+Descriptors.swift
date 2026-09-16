import CoreGraphics

// HPA-166 Task 4 — resolved-semantics primitives: articulations, controls,
// tuplets and measure bars. Ports of `NotationLayoutEngine+Controls.swift`,
// `+RhythmRendering.swift` (tuplets) and `NotationLayoutEngine.swift`
// (measure bars) onto the shared formatted columns and final head/rest/
// beam geometry.

extension SheetComposer {
    // MARK: - Articulations

    /// One articulation mark per articulating head, centered on the head's
    /// X and floated `articulationVerticalOffset` above it — the engine's
    /// `buildArticulations`; the mark kind is the resolved
    /// `PercussionArticulation` verbatim.
    func collectArticulations(raw: inout RawGeometry) {
        for head in raw.noteHeads {
            guard let articulation = head.note.articulation else { continue }
            let position = CGPoint(
                x: head.position.x,
                y: head.position.y - style.articulationVerticalOffset
            )
            let metrics = PercussionGlyphMetrics.articulation(
                articulation,
                staffSpace: formatting.staffSpace
            )
            raw.include(metrics.paintedBounds.offsetBy(dx: position.x, dy: position.y))
            raw.articulations.append(EngravedArticulation(
                noteID: head.note.id,
                kind: articulation,
                position: position
            ))
        }
        // Engine ordering: source note ID.
        raw.articulations.sort { $0.noteID < $1.noteID }
    }

    // MARK: - Controls

    /// Control marks at their resolved target staff step on the logical
    /// column X — the engine's `buildStopNotes` with the app-side lane
    /// resolution already folded into `ResolvedControl.targetStaffStep`.
    /// Sorted by absolute tick then ID, matching the engine.
    func collectControls(raw: inout RawGeometry) {
        let measuresByIndex = Dictionary(
            input.measures.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var stamped: [(control: EngravedControl, absoluteTick: Int)] = []
        for control in input.controls {
            guard let resolvedMeasure = measuresByIndex[control.position.measureIndex],
                  let formattedMeasure = formatted.measures.first(where: {
                      $0.index == control.position.measureIndex
                  }),
                  let column = formattedMeasure.columns.first(where: {
                      $0.localTick == control.position.localTick
                  })
            else { continue }
            let position = CGPoint(
                x: column.logicalColumnX,
                y: staffStepY(control.targetStaffStep, rowIndex: formattedMeasure.rowIndex)
                    - style.stopMarkVerticalOffset
            )
            // The cross mark's ink: the mark square plus its stroke width,
            // matching the engine's `RenderedStopNote.paintedBounds`.
            let markExtent = style.stopMarkSize + style.stopMarkStrokeWidth
            raw.include(CGRect(
                x: position.x - markExtent / 2,
                y: position.y - markExtent / 2,
                width: markExtent,
                height: markExtent
            ))
            stamped.append((
                control: EngravedControl(
                    controlID: control.id,
                    kind: control.kind,
                    measureIndex: control.position.measureIndex,
                    rowIndex: formattedMeasure.rowIndex,
                    position: position
                ),
                absoluteTick: resolvedMeasure.startTick + control.position.localTick
            ))
        }
        raw.controls = stamped
            .sorted {
                ($0.absoluteTick, $0.control.controlID) < ($1.absoluteTick, $1.control.controlID)
            }
            .map(\.control)
    }

    // MARK: - Tuplets

    /// Every resolved tuplet over final member geometry — the engine's
    /// `renderedTuplet`: label-only when every member onset is continuously
    /// beamed with no rests, bracket + label otherwise. Input order is
    /// preserved (the resolved groups are already caller-sorted).
    func collectTuplets(
        headsByID: [Int: PendingNoteHead],
        restsByID: [Int: PendingRest],
        raw: inout RawGeometry
    ) {
        let measuresByIndex = Dictionary(
            input.measures.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for group in input.tuplets {
            guard let tuplet = renderedTuplet(
                group,
                headsByID: headsByID,
                restsByID: restsByID,
                measuresByIndex: measuresByIndex,
                raw: raw
            ) else { continue }
            raw.include(tupletPaintedBounds(tuplet))
            raw.tuplets.append(tuplet)
        }
    }

    /// One resolved tuplet group as final geometry — the port of the
    /// engine's `renderedTuplet` verbatim, with member heads ordered by
    /// (absolute tick, tiebreak order, ID) like the engine's note-head list.
    private func renderedTuplet(
        _ group: ResolvedTupletGroup,
        headsByID: [Int: PendingNoteHead],
        restsByID: [Int: PendingRest],
        measuresByIndex: [Int: ResolvedMeasure],
        raw: RawGeometry
    ) -> EngravedTuplet? {
        let memberHeads = group.memberNoteIDs
            .compactMap { headsByID[$0] }
            .sorted { lhs, rhs in
                memberHeadComesBefore(lhs, rhs, measuresByIndex: measuresByIndex)
            }
        let memberRests = group.memberRestIDs.compactMap { restsByID[$0] }
        guard !memberHeads.isEmpty || !memberRests.isEmpty else { return nil }
        let memberBeams = raw.beams.filter { beam in
            beam.noteIDs.filter(Set(memberHeads.map { $0.note.id }).contains).count >= 2
        }
        let beamSpansEntireGroup = memberRests.isEmpty
            && continuousPrimaryBeamCoversEveryOnset(
                memberHeads: memberHeads,
                memberBeams: memberBeams
            )
        let direction = memberHeads.first?.note.stemDirection
            ?? (group.voice == .upper ? .up : .down)
        let memberBounds = memberHeads.map(\.bounds) + memberRests.map(\.bounds)
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
        return EngravedTuplet(
            tupletID: group.id,
            voice: group.voice,
            ratio: group.ratio,
            memberNoteIDs: group.memberNoteIDs,
            memberRestIDs: group.memberRestIDs,
            isBracketVisible: bracketVisible,
            bracketPoints: bracketVisible
                ? tupletBracketPoints(
                    minX: bounds.minX,
                    maxX: bounds.maxX,
                    labelPosition: labelPosition,
                    direction: direction
                ) : [],
            labelPosition: labelPosition,
            rowIndex: memberHeads.first?.rowIndex ?? memberRests[0].rowIndex
        )
    }

    /// The strengthened `beamSpansEntireGroup` arm minus its rest check:
    /// every member onset must hold at least one head inside a SINGLE
    /// level-0 full beam — one continuous primary run. Two disconnected
    /// runs that each beam their own members still earn the bracket.
    /// A run emits exactly one level-0 full segment, so "one beam covers
    /// every onset" is exactly "one run covers them".
    private func continuousPrimaryBeamCoversEveryOnset(
        memberHeads: [PendingNoteHead],
        memberBeams: [EngravedBeam]
    ) -> Bool {
        let onsetHeadIDs = Dictionary(grouping: memberHeads) {
            NotationTickPosition(
                measureIndex: $0.note.position.measureIndex,
                localTick: $0.note.position.localTick
            )
        }.values.map { Set($0.map { $0.note.id }) }
        return memberBeams.contains { beam in
            beam.level == 0 && beam.kind == .full
                && onsetHeadIDs.allSatisfy { !$0.isDisjoint(with: Set(beam.noteIDs)) }
        }
    }

    /// The member-head ordering the engine's sorted note list implies:
    /// absolute tick, then the caller's engraving tiebreak, then ID.
    private func memberHeadComesBefore(
        _ lhs: PendingNoteHead,
        _ rhs: PendingNoteHead,
        measuresByIndex: [Int: ResolvedMeasure]
    ) -> Bool {
        let lhsTick = (measuresByIndex[lhs.note.position.measureIndex]?.startTick ?? 0)
            + lhs.note.position.localTick
        let rhsTick = (measuresByIndex[rhs.note.position.measureIndex]?.startTick ?? 0)
            + rhs.note.position.localTick
        if lhsTick != rhsTick { return lhsTick < rhsTick }
        if lhs.note.tiebreakOrder != rhs.note.tiebreakOrder {
            return lhs.note.tiebreakOrder < rhs.note.tiebreakOrder
        }
        return lhs.note.id < rhs.note.id
    }

    /// The six-point bracket polyline — the engine's `tupletBracketPoints`:
    /// vertical hooks toward the members, a horizontal span broken by the
    /// label gap (`tupletLabelSize.width` plus the dot spacing each side).
    private func tupletBracketPoints(
        minX: CGFloat,
        maxX: CGFloat,
        labelPosition: CGPoint,
        direction: NotationStemDirection
    ) -> [CGPoint] {
        let horizontalY = labelPosition.y
        let hookY = direction == .up
            ? horizontalY + style.tupletHookLength
            : horizontalY - style.tupletHookLength
        let halfGap = style.tupletLabelSize.width / 2 + formatting.rhythmDotSpacing
        return [
            CGPoint(x: minX, y: hookY),
            CGPoint(x: minX, y: horizontalY),
            CGPoint(x: max(minX, labelPosition.x - halfGap), y: horizontalY),
            CGPoint(x: min(maxX, labelPosition.x + halfGap), y: horizontalY),
            CGPoint(x: maxX, y: horizontalY),
            CGPoint(x: maxX, y: hookY)
        ]
    }

    /// The tuplet's ink: bracket polyline bounds unioned with the label
    /// rect, stroked by `tupletLineWidth` — the engine's
    /// `RenderedTuplet.paintedBounds`.
    private func tupletPaintedBounds(_ tuplet: EngravedTuplet) -> CGRect {
        var bounds = tuplet.bracketPoints.isEmpty
            ? CGRect.null
            : tuplet.bracketPoints.dropFirst().reduce(
                CGRect(origin: tuplet.bracketPoints[0], size: .zero)
            ) { $0.union(CGRect(origin: $1, size: .zero)) }
        bounds = bounds.union(CGRect(
            x: tuplet.labelPosition.x - style.tupletLabelSize.width / 2,
            y: tuplet.labelPosition.y - style.tupletLabelSize.height / 2,
            width: style.tupletLabelSize.width,
            height: style.tupletLabelSize.height
        ))
        return bounds.insetBy(dx: -style.tupletLineWidth / 2, dy: -style.tupletLineWidth / 2)
    }

    // MARK: - Row furniture

    /// Every formatted row's furniture in RAW sheet coordinates — the five
    /// staff lines spanning the row's formatted extent, the leading clef
    /// slot, and the meter-signature slot of the row's first measure.
    /// Furniture ink joins `paintedUnion` like every other primitive so the
    /// single normalization moves it too, and the row's own `paintedBounds`
    /// proves containment to consumers.
    func collectRowFurniture(raw: inout RawGeometry) {
        let measuresByIndex = Dictionary(
            input.measures.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for index in Set(formatted.measures.map(\.rowIndex)).sorted() {
            let centerY = staffCenterY(rowIndex: index)
            let staffSpace = formatting.staffSpace
            let staffHeight = 4 * staffSpace
            let staffLineYs = [
                centerY + 2 * staffSpace,
                centerY + staffSpace,
                centerY,
                centerY - staffSpace,
                centerY - 2 * staffSpace
            ]
            // Each furniture descriptor's painted bounds is its reserved
            // slot: the advance the formatter charges every row, spanning
            // the staff height and centered on the descriptor's position.
            let clef = EngravedClef(
                position: CGPoint(x: style.clefWidth / 2, y: centerY),
                paintedBounds: CGRect(
                    x: 0, y: centerY - staffHeight / 2,
                    width: style.clefWidth, height: staffHeight
                )
            )
            let meter = meterSignature(
                rowIndex: index, centerY: centerY,
                staffHeight: staffHeight, measuresByIndex: measuresByIndex
            )
            let furniture = rowPaintedBounds(
                rowIndex: index, staffLineYs: staffLineYs,
                clef: clef, meter: meter
            )
            raw.include(furniture)
            raw.rows.append(EngravedRow(
                index: index,
                staffCenterY: centerY,
                staffLineYs: staffLineYs,
                clef: clef,
                meterSignature: meter,
                paintedBounds: furniture
            ))
        }
    }

    /// The row's meter descriptor: the resolved meter of the row's first
    /// formatted measure, centered in its reserved `meterWidth` slot.
    private func meterSignature(
        rowIndex: Int,
        centerY: CGFloat,
        staffHeight: CGFloat,
        measuresByIndex: [Int: ResolvedMeasure]
    ) -> EngravedMeterSignature {
        let firstMeter = formatted.measures
            .first { $0.rowIndex == rowIndex }
            .flatMap { measuresByIndex[$0.index]?.meter }
            ?? NotationMeter(beats: 4, noteValue: 4)
        return EngravedMeterSignature(
            meter: firstMeter,
            position: CGPoint(x: style.clefWidth + style.meterWidth / 2, y: centerY),
            paintedBounds: CGRect(
                x: style.clefWidth, y: centerY - staffHeight / 2,
                width: style.meterWidth, height: staffHeight
            )
        )
    }

    /// The row's furniture union: each staff line stroked `barLineWidth`
    /// from the sheet edge through the row's last measure edge — the same
    /// span the bars and the app's row painter cover — plus both slots.
    private func rowPaintedBounds(
        rowIndex: Int,
        staffLineYs: [CGFloat],
        clef: EngravedClef,
        meter: EngravedMeterSignature
    ) -> CGRect {
        let rowEnd = formatted.measures
            .filter { $0.rowIndex == rowIndex }
            .map { $0.xOffset + $0.width }
            .max() ?? 0
        return staffLineYs.reduce(
            clef.paintedBounds.union(meter.paintedBounds)
        ) { bounds, lineY in
            bounds.union(CGRect(
                x: 0, y: lineY - style.barLineWidth / 2,
                width: rowEnd, height: style.barLineWidth
            ))
        }
    }

    // MARK: - Measure bars

    /// One bar per formatted measure boundary — the engine's
    /// `buildMeasureBars`: a leading bar only where a measure opens a row,
    /// an end bar on every measure's right edge, and the closing double
    /// bar (`isFinal`) on the last measure's end.
    func collectMeasureBars(raw: inout RawGeometry) {
        let lastMeasureIndex = formatted.measures.last?.index
        for (position, measure) in formatted.measures.enumerated() {
            let isFirstInRow = position == 0
                || formatted.measures[position - 1].rowIndex != measure.rowIndex
            if isFirstInRow {
                appendBar(EngravedMeasureBar(
                    measureIndex: measure.index,
                    rowIndex: measure.rowIndex,
                    x: measure.xOffset,
                    isFinal: false
                ), raw: &raw)
            }
            // Every end bar sits on its own measure boundary (xOffset +
            // width): for same-row neighbors the next measure starts after
            // the spacing gap, so anchoring on its xOffset would draw the
            // bar one gap right of the measure it closes.
            appendBar(EngravedMeasureBar(
                measureIndex: measure.index,
                rowIndex: measure.rowIndex,
                x: measure.xOffset + measure.width,
                isFinal: measure.index == lastMeasureIndex
            ), raw: &raw)
        }
    }

    /// Appends one bar primitive and unions its ink: a normal bar strokes
    /// `barLineWidth` across the staff height at `x`; the final bar is the
    /// thin+thick double bar ending at `x` — the engine's
    /// `RenderedMeasureBar.paintedBounds`.
    private func appendBar(_ bar: EngravedMeasureBar, raw: inout RawGeometry) {
        let centerY = staffCenterY(rowIndex: bar.rowIndex)
        let staffHeight = 4 * formatting.staffSpace
        let bounds: CGRect
        if bar.isFinal {
            let width = style.doubleBarThinWidth
                + style.doubleBarSpacing
                + style.doubleBarThickWidth
            bounds = CGRect(
                x: bar.x - width,
                y: centerY - staffHeight / 2,
                width: width,
                height: staffHeight
            )
        } else {
            bounds = CGRect(
                x: bar.x - style.barLineWidth / 2,
                y: centerY - staffHeight / 2,
                width: style.barLineWidth,
                height: staffHeight
            )
        }
        raw.include(bounds)
        raw.measureBars.append(bar)
    }
}

/// The one package Y translation applied after the painted-bounds pass —
/// module-internal so the only route to a moved primitive is the composer.
extension EngravedArticulation {
    func translated(byY delta: CGFloat) -> EngravedArticulation {
        EngravedArticulation(
            noteID: noteID,
            kind: kind,
            position: CGPoint(x: position.x, y: position.y + delta)
        )
    }
}

extension EngravedControl {
    func translated(byY delta: CGFloat) -> EngravedControl {
        EngravedControl(
            controlID: controlID,
            kind: kind,
            measureIndex: measureIndex,
            rowIndex: rowIndex,
            position: CGPoint(x: position.x, y: position.y + delta)
        )
    }
}

extension EngravedTuplet {
    func translated(byY delta: CGFloat) -> EngravedTuplet {
        EngravedTuplet(
            tupletID: tupletID,
            voice: voice,
            ratio: ratio,
            memberNoteIDs: memberNoteIDs,
            memberRestIDs: memberRestIDs,
            isBracketVisible: isBracketVisible,
            bracketPoints: bracketPoints.map { CGPoint(x: $0.x, y: $0.y + delta) },
            labelPosition: CGPoint(x: labelPosition.x, y: labelPosition.y + delta),
            rowIndex: rowIndex
        )
    }
}

extension EngravedRow {
    /// The row's whole furniture world moves with the single normalization:
    /// center, staff-line Ys, both descriptor slots and the painted union.
    func translated(byY delta: CGFloat) -> EngravedRow {
        EngravedRow(
            index: index,
            staffCenterY: staffCenterY + delta,
            staffLineYs: staffLineYs.map { $0 + delta },
            clef: clef.translated(byY: delta),
            meterSignature: meterSignature.translated(byY: delta),
            paintedBounds: paintedBounds.offsetBy(dx: 0, dy: delta)
        )
    }
}

extension EngravedClef {
    func translated(byY delta: CGFloat) -> EngravedClef {
        EngravedClef(
            position: CGPoint(x: position.x, y: position.y + delta),
            paintedBounds: paintedBounds.offsetBy(dx: 0, dy: delta)
        )
    }
}

extension EngravedMeterSignature {
    func translated(byY delta: CGFloat) -> EngravedMeterSignature {
        EngravedMeterSignature(
            meter: meter,
            position: CGPoint(x: position.x, y: position.y + delta),
            paintedBounds: paintedBounds.offsetBy(dx: 0, dy: delta)
        )
    }
}
