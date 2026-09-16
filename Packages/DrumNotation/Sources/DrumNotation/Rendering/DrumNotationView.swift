import SwiftUI

// HPA-166 Task 5 — the single package static view over `EngravedNotation`.
//
// The view consumes only the immutable engraving (which now carries its
// producing `NotationEngravingStyle` for paint-time stroke/sizing metrics),
// the narrow `DrumNotationAppearance`, and the caller's accessibility label
// map. It applies no hidden translation — every primitive paints at its
// final normalized sheet coordinates — observes no gameplay clock, and
// reads no Virgo theme/environment/global layout values. Localized strings
// never touch `ResolvedNotationInput` or `EngravedNotation`; semantic
// primitives resolve them through the one view seam at paint time.

/// The complete static drum-notation sheet: staff lines, measure bars,
/// clef and meter furniture, ledgers, stems, beams, flags, note heads,
/// rests, rhythm dots, articulations, controls and tuplets, framed to the
/// engraving's declared `contentWidth × contentHeight`.
public struct DrumNotationView: View {
    public let layout: EngravedNotation
    public let appearance: DrumNotationAppearance
    public let accessibilityLabels: [NotationSemanticID: String]

    public init(
        layout: EngravedNotation,
        appearance: DrumNotationAppearance = DrumNotationAppearance(),
        accessibilityLabels: [NotationSemanticID: String] = [:]
    ) {
        self.layout = layout
        self.appearance = appearance
        self.accessibilityLabels = accessibilityLabels
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            rowFurnitureLayer
            ledgerLayer
            restsLayer
            beamsLayer
            flagsLayer
            stemsLayer
            noteHeadsLayer
            dotsLayer
            articulationsLayer
            controlsLayer
            tupletsLayer
        }
        .frame(
            width: layout.contentWidth,
            height: layout.contentHeight,
            alignment: .topLeading
        )
    }

    /// The one view-only accessibility seam: every semantic primitive's
    /// VoiceOver copy resolves through this lookup against the caller's
    /// label map. Internal so package tests pin the collision-safe
    /// resolution without exposing a second public surface.
    func accessibilityLabel(for id: NotationSemanticID) -> String? {
        accessibilityLabels[id]
    }
}

private extension DrumNotationView {
    var style: NotationEngravingStyle { layout.style }
    var staffSpace: CGFloat { style.formatting.staffSpace }

    /// Applies the caller's label to one semantic primitive at paint time;
    /// a semantic element without a label hides rather than exposing an
    /// unlabeled VoiceOver node.
    @ViewBuilder
    func labeled<V: View>(_ view: V, as id: NotationSemanticID) -> some View {
        if let label = accessibilityLabel(for: id) {
            view.accessibilityLabel(Text(verbatim: label))
        } else {
            view.accessibilityHidden(true)
        }
    }

    // MARK: - Row furniture (decorative)

    /// Staff lines, measure bars, and the clef/meter descriptors — all
    /// decorative geometry hidden from accessibility.
    var rowFurnitureLayer: some View {
        Group {
            staffLines
            measureBars
            rowDescriptors
        }
        .accessibilityHidden(true)
    }

    /// The five staff lines of every row, spanning the sheet edge through
    /// the row's last formatted measure edge — the same span the engraver
    /// unioned into the row's furniture bounds.
    var staffLines: some View {
        Path { path in
            for row in layout.rows {
                let rowEnd = layout.measures
                    .filter { $0.rowIndex == row.index }
                    .map { $0.xOffset + $0.width }
                    .max() ?? 0
                for lineY in row.staffLineYs {
                    path.move(to: CGPoint(x: 0, y: lineY))
                    path.addLine(to: CGPoint(x: rowEnd, y: lineY))
                }
            }
        }
        .stroke(appearance.staffLines, lineWidth: style.barLineWidth)
    }

    /// One bar per engraved measure boundary: a normal `barLineWidth` bar
    /// at interior boundaries and the thin+spacing+thick double bar on the
    /// last measure — the app's two-tier bar ink.
    var measureBars: some View {
        Group {
            Path { path in
                for bar in layout.measureBars where !bar.isFinal {
                    guard let frame = staffFrame(rowIndex: bar.rowIndex) else { continue }
                    path.addRect(CGRect(
                        x: bar.x - style.barLineWidth / 2,
                        y: frame.minY,
                        width: style.barLineWidth,
                        height: frame.height
                    ))
                }
            }
            .fill(appearance.foreground.opacity(0.8))
            Path { path in
                for bar in layout.measureBars where bar.isFinal {
                    guard let frame = staffFrame(rowIndex: bar.rowIndex) else { continue }
                    let width = style.doubleBarThinWidth
                        + style.doubleBarSpacing
                        + style.doubleBarThickWidth
                    path.addRect(CGRect(
                        x: bar.x - width,
                        y: frame.minY,
                        width: style.doubleBarThinWidth,
                        height: frame.height
                    ))
                    path.addRect(CGRect(
                        x: bar.x - style.doubleBarThickWidth,
                        y: frame.minY,
                        width: style.doubleBarThickWidth,
                        height: frame.height
                    ))
                }
            }
            .fill(appearance.foreground)
        }
    }

    /// The staff's vertical extent on a bar's row: `staffLineYs` is
    /// pitch-ascending (bottom line first), so first→last is the staff height.
    func staffFrame(rowIndex: Int) -> CGRect? {
        guard let row = layout.rows.first(where: { $0.index == rowIndex }),
              let bottom = row.staffLineYs.first,
              let top = row.staffLineYs.last else { return nil }
        return CGRect(x: 0, y: top, width: 0, height: bottom - top)
    }

    /// Per-row clef and meter descriptors at their reserved furniture
    /// positions — the app-shape percussion clef (three 12×8 bars, 4pt
    /// spacing) and the two stacked meter digits.
    var rowDescriptors: some View {
        ForEach(layout.rows, id: \.index) { row in
            Group {
                clefMark(at: row.clef)
                meterDigits(row.meterSignature)
            }
        }
    }

    /// The percussion clef mark: three stacked bars centered on the
    /// descriptor's glyph position — the app's `DrumClefSymbol`
    /// proportions (12×32), uniformly shrunk to fit the reserved slot so a
    /// smaller `clefWidth`/staff height can never paint outside it.
    func clefMark(at clef: EngravedClef) -> some View {
        let slot = clef.paintedBounds
        let scale = min(1, slot.width / 12, slot.height / 32)
        return Path { path in
            for yOffset in [-16.0, -4.0, 8.0] {
                path.addRect(CGRect(
                    x: clef.position.x - 6 * scale,
                    y: clef.position.y + yOffset * scale,
                    width: 12 * scale,
                    height: 8 * scale
                ))
            }
        }
        .fill(appearance.foreground)
    }

    /// The row's meter signature: beats over note value in the app's serif
    /// bold, framed to the descriptor's reserved slot. The font caps at
    /// 18pt and shrinks with the slot so small furniture or wide meters
    /// (e.g. 12/8) stay inside `paintedBounds`.
    func meterDigits(_ signature: EngravedMeterSignature) -> some View {
        let slot = signature.paintedBounds
        return VStack(spacing: 2) {
            Text("\(signature.meter.beats)")
            Text("\(signature.meter.noteValue)")
        }
        .font(.system(
            size: min(18, slot.height * 0.35), weight: .bold, design: .serif
        ))
        .foregroundStyle(appearance.foreground)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .frame(width: slot.width, height: slot.height)
        .clipped()
        .position(x: slot.midX, y: slot.midY)
    }

    // MARK: - Decorative notation geometry

    var ledgerLayer: some View {
        Path { path in
            for line in layout.ledgerLines {
                path.move(to: line.start)
                path.addLine(to: line.end)
            }
        }
        .stroke(appearance.foreground, lineWidth: style.barLineWidth)
        .accessibilityHidden(true)
    }

    var beamsLayer: some View {
        ForEach(layout.beams, id: \.self) { beam in
            Path { path in
                path.move(to: beam.start)
                path.addLine(to: beam.end)
            }
            .stroke(appearance.foreground, lineWidth: beam.thickness)
        }
        .accessibilityHidden(true)
    }

    /// Each visible flag glyph: `origin` is the SMuFL attachment point, so
    /// the glyph view — framed to its painted bounds — positions at
    /// `origin - attachmentOffset`, the same read the composer used to
    /// union flag ink.
    var flagsLayer: some View {
        ForEach(layout.flags, id: \.self) { flag in
            let metrics = PercussionGlyphMetrics.flag(
                duration: flag.duration,
                direction: flag.stemDirection,
                staffSpace: staffSpace
            )
            NotationFlagGlyphView(
                duration: flag.duration,
                direction: flag.stemDirection,
                staffSpace: staffSpace,
                color: appearance.foreground
            )
            .position(
                x: flag.origin.x - metrics.attachmentOffset.x,
                y: flag.origin.y - metrics.attachmentOffset.y
            )
        }
        .accessibilityHidden(true)
    }

    var stemsLayer: some View {
        Path { path in
            for stem in layout.stems {
                path.move(to: stem.start)
                path.addLine(to: stem.end)
            }
        }
        .stroke(appearance.foreground, lineWidth: style.formatting.stemWidth)
        .accessibilityHidden(true)
    }

    var dotsLayer: some View {
        ForEach(layout.rhythmDots, id: \.self) { dot in
            Ellipse()
                .fill(appearance.foreground)
                .frame(width: dot.paintedBounds.width, height: dot.paintedBounds.height)
                .position(dot.position)
        }
        .accessibilityHidden(true)
    }

    var articulationsLayer: some View {
        ForEach(layout.articulations, id: \.self) { articulation in
            PercussionArticulationView(
                articulation: articulation.kind,
                staffSpace: staffSpace,
                color: appearance.foreground
            )
            .position(articulation.position)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Semantic primitives (labeled at paint time)

    var restsLayer: some View {
        ForEach(layout.rests, id: \.restID) { rest in
            labeled(
                NotationRestGlyphView(
                    duration: rest.duration,
                    staffSpace: staffSpace,
                    color: appearance.foreground
                )
                .position(rest.position),
                as: .rest(rest.restID)
            )
        }
    }

    var noteHeadsLayer: some View {
        ForEach(layout.noteHeads, id: \.noteID) { head in
            labeled(
                PercussionNoteheadView(
                    style: head.noteheadStyle,
                    duration: head.duration,
                    staffSpace: staffSpace,
                    color: appearance.foreground
                )
                .position(head.position),
                as: .note(head.noteID)
            )
        }
    }

    /// The stop/choke/damp cross mark at its resolved target — the app's
    /// `NotationStopNoteView` "+" shape, identical for every control kind.
    var controlsLayer: some View {
        ForEach(layout.controls, id: \.controlID) { control in
            labeled(
                Path { path in
                    let half = style.stopMarkSize / 2
                    path.move(to: CGPoint(
                        x: control.position.x - half, y: control.position.y
                    ))
                    path.addLine(to: CGPoint(
                        x: control.position.x + half, y: control.position.y
                    ))
                    path.move(to: CGPoint(
                        x: control.position.x, y: control.position.y - half
                    ))
                    path.addLine(to: CGPoint(
                        x: control.position.x, y: control.position.y + half
                    ))
                }
                .stroke(appearance.foreground, lineWidth: style.stopMarkStrokeWidth),
                as: .control(control.controlID)
            )
        }
    }

    /// One resolved tuplet: the six-point bracket (two strokes around the
    /// label gap) when visible, plus the resolved `ratio.actual` numeral
    /// fitted to the reserved label rect at `labelPosition`.
    var tupletsLayer: some View {
        ForEach(layout.tuplets, id: \.tupletID) { tuplet in
            labeled(
                ZStack {
                    if tuplet.isBracketVisible && tuplet.bracketPoints.count == 6 {
                        Path { path in
                            path.move(to: tuplet.bracketPoints[0])
                            path.addLine(to: tuplet.bracketPoints[1])
                            path.addLine(to: tuplet.bracketPoints[2])
                            path.move(to: tuplet.bracketPoints[3])
                            path.addLine(to: tuplet.bracketPoints[4])
                            path.addLine(to: tuplet.bracketPoints[5])
                        }
                        .stroke(appearance.foreground, lineWidth: style.tupletLineWidth)
                    }
                    // The resolved numeral — `ratio.actual`, not a fixed
                    // "3" — verbatim so digits never localize, fitted to
                    // the reserved label rect with shrink for multi-digit
                    // actuals.
                    Text(verbatim: "\(tuplet.ratio.actual)")
                        .font(.system(
                            size: style.tupletLabelSize.height * 0.8,
                            weight: .bold, design: .serif
                        ))
                        .foregroundStyle(appearance.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(
                            width: style.tupletLabelSize.width,
                            height: style.tupletLabelSize.height
                        )
                        .position(tuplet.labelPosition)
                }
                .accessibilityElement(children: .ignore),
                as: .tuplet(tuplet.tupletID)
            )
        }
    }
}
