import CoreGraphics
import SwiftUI
import Testing
@testable import DrumNotation

/// HPA-166 Task 5 — the static `DrumNotationView` over `EngravedNotation`:
/// the collision-safe semantic accessibility key, the narrow view
/// appearance, the single paint-time label seam, and the raster/bounds
/// probes that prove painted ink lands inside the engraving's final
/// `paintedBounds` with no hidden translation. `@testable` reaches only
/// the view's internal label seam; construction and raster coverage use
/// the ordinary public surface.
@Suite("Notation semantic IDs")
struct NotationSemanticIDTests {
    @Test("note/rest/control/tuplet namespaces never collide on the same integer")
    func namespacesDoNotCollide() {
        #expect(NotationSemanticID.note(7) != .rest(7))
        #expect(NotationSemanticID.note(7) != .control(7))
        #expect(NotationSemanticID.note(7) != .tuplet(7))
        #expect(NotationSemanticID.rest(7) != .control(7))
        #expect(NotationSemanticID.rest(7) != .tuplet(7))
        #expect(NotationSemanticID.control(7) != .tuplet(7))
    }

    @Test("one label map keeps all four namespaces distinct")
    func labelMapKeepsNamespacesDistinct() {
        var labels: [NotationSemanticID: String] = [:]
        labels[.note(7)] = "note"
        labels[.rest(7)] = "rest"
        labels[.control(7)] = "control"
        labels[.tuplet(7)] = "tuplet"

        #expect(labels.count == 4)
        #expect(labels[.note(7)] == "note")
        #expect(labels[.rest(7)] == "rest")
        #expect(labels[.control(7)] == "control")
        #expect(labels[.tuplet(7)] == "tuplet")
    }
}

@Suite("DrumNotationView construction and appearance")
struct DrumNotationViewConstructionTests {
    private let style = NotationEngravingStyle()

    private func layout() throws -> EngravedNotation {
        try NotationEngraver.engrave(Fixtures.document(), style: style)
    }

    @Test("view constructs from an engraving with default appearance and labels")
    func viewConstructs() throws {
        let layout = try layout()
        _ = DrumNotationView(layout: layout, accessibilityLabels: [:])
        _ = DrumNotationView(
            layout: layout,
            appearance: DrumNotationAppearance(foreground: .white),
            accessibilityLabels: [.note(42): "Snare"]
        )
    }

    @Test("the engraving result carries the producing style for view paint metrics")
    func layoutCarriesStyle() throws {
        let custom = NotationEngravingStyle(stopMarkSize: 22)
        let layout = try NotationEngraver.engrave(Fixtures.document(), style: custom)
        #expect(layout.style == custom)
    }
}

@Suite("DrumNotationView accessibility seam")
struct DrumNotationViewAccessibilityTests {
    @Test("semantic IDs resolve caller labels through the one view seam")
    func seamResolvesLabels() throws {
        let layout = try NotationEngraver.engrave(
            Fixtures.document(),
            style: NotationEngravingStyle()
        )
        let view = DrumNotationView(
            layout: layout,
            accessibilityLabels: [
                .note(42): "Snare",
                .rest(7): "Quarter rest"
            ]
        )

        #expect(view.accessibilityLabel(for: .note(42)) == "Snare")
        #expect(view.accessibilityLabel(for: .rest(7)) == "Quarter rest")
        // Same integer in another namespace must not bleed a label across.
        #expect(view.accessibilityLabel(for: .rest(42)) == nil)
        #expect(view.accessibilityLabel(for: .note(7)) == nil)
        #expect(view.accessibilityLabel(for: .control(9)) == nil)
        #expect(view.accessibilityLabel(for: .tuplet(1)) == nil)
    }
}

/// A rasterized view as premultiplied-last RGBA bytes — the package-local
/// ink probe. No Virgo test helper crosses the package boundary.
private struct RasterProbe {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    static let bytesPerPixel = 4
    static let inkAlpha: UInt8 = 20

    var totalInk: Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where isInked(x: x, y: y) {
                count += 1
            }
        }
        return count
    }

    func isInked(x: Int, y: Int) -> Bool {
        bytes[(y * width + x) * Self.bytesPerPixel + 3] > Self.inkAlpha
    }

    /// Inked pixels whose centers fall inside `rect` (1pt == 1px at scale 1).
    func inkCount(in rect: CGRect) -> Int {
        var count = 0
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        for y in minY..<maxY {
            for x in minX..<maxX where isInked(x: x, y: y) {
                count += 1
            }
        }
        return count
    }

    /// The rect's alpha bytes in row order — the differential probe that
    /// compares one painted region across two rasterized views.
    func alphaBytes(in rect: CGRect) -> [UInt8] {
        var output: [UInt8] = []
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        for y in minY..<maxY {
            for x in minX..<maxX {
                output.append(bytes[(y * width + x) * Self.bytesPerPixel + 3])
            }
        }
        return output
    }

    /// Inked pixels whose centers fall outside `rect` — the containment probe.
    func inkOutside(_ rect: CGRect) -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where isInked(x: x, y: y) {
                if !rect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                    count += 1
                }
            }
        }
        return count
    }
}

@MainActor
private func rasterize<V: View>(_ view: V, size: CGSize) throws -> RasterProbe {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 1
    let cgImage = try #require(renderer.cgImage)
    let width = cgImage.width
    let height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height * RasterProbe.bytesPerPixel)
    let context = try #require(CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * RasterProbe.bytesPerPixel,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return RasterProbe(bytes: bytes, width: width, height: height)
}

@Suite("DrumNotationView raster bounds")
struct DrumNotationViewRasterTests {
    private let style = NotationEngravingStyle()

    /// A lone eighth note: unbeamed stem + one canonical isolated flag.
    private func flaggedEighthInput() throws -> ResolvedNotationInput {
        try Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 3,
                    duration: .eighth
                )
            ],
            rests: [], controls: []
        )
    }

    /// Two adjacent eighths in one beat group: a level-0 beam, no flags.
    private func beamedRunInput() throws -> ResolvedNotationInput {
        try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .eighth),
                Fixtures.makeNote(id: 2, localTick: 240, staffStep: 3, duration: .eighth)
            ],
            rests: [], controls: []
        )
    }

    /// A five-member quarter tuplet — unbeamable, so bracket + numeral
    /// paint. `ratio` is a parameter so one fixture engraves two numerals
    /// over identical member geometry for the differential probe.
    /// `ResolvedTupletRatio` deliberately validates positivity only — the
    /// same members may carry either declared ratio.
    private func quintupletInput(actual: Int, normal: Int) throws -> ResolvedNotationInput {
        try Fixtures.document(
            notes: [0, 384, 768, 1152, 1536].enumerated().map { index, tick in
                Fixtures.makeNote(
                    id: index + 1, localTick: tick, staffStep: 3,
                    duration: .quarter, durationTicks: 384
                )
            },
            rests: [], controls: [],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: .upper,
                    ratio: ResolvedTupletRatio(actual: actual, normal: normal),
                    memberNoteIDs: [1, 2, 3, 4, 5], memberRestIDs: []
                )
            ]
        )
    }

    /// One stemless whole note (no stem/flag/beam reaching above the
    /// staff) under a wide meter — isolates the furniture slots so clef
    /// and meter overflow would escape the global painted bounds.
    private func smallFurnitureInput() throws -> ResolvedNotationInput {
        try Fixtures.document(
            measures: [
                Fixtures.measure(meter: NotationMeter(beats: 12, noteValue: 8))
            ],
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .whole)
            ],
            rests: [], controls: []
        )
    }

    /// A quarter-note triplet (never beamed → bracket + label) plus a stop control.
    private func controlTupletInput() throws -> ResolvedNotationInput {
        try Fixtures.document(
            notes: [0, 320, 640].enumerated().map { index, tick in
                Fixtures.makeNote(
                    id: index + 1, localTick: tick, staffStep: 3,
                    duration: .quarter, durationTicks: 320
                )
            },
            rests: [],
            controls: [
                ResolvedControl(
                    id: 9,
                    position: NotationTickPosition(measureIndex: 0, localTick: 960),
                    kind: .stop,
                    targetStaffStep: 0
                )
            ],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [1, 2, 3], memberRestIDs: []
                )
            ]
        )
    }

    /// Rasterizes the view at the engraving's declared content size and
    /// asserts every inked pixel lands inside the final painted bounds —
    /// the no-hidden-translation gate. Returns the raster for per-primitive
    /// spot checks.
    @MainActor
    private func probe(_ layout: EngravedNotation) throws -> RasterProbe {
        let raster = try rasterize(
            DrumNotationView(layout: layout, accessibilityLabels: [:]),
            size: CGSize(width: layout.contentWidth, height: layout.contentHeight)
        )
        #expect(raster.totalInk > 0)
        // Antialiasing can feather a stroke ~1pt past its nominal bounds.
        #expect(raster.inkOutside(layout.paintedBounds.insetBy(dx: -1.5, dy: -1.5)) == 0)
        return raster
    }

    @Test("notehead + isolated flag paint inside final bounds")
    @MainActor
    func flaggedNotePaintsInsideBounds() async throws {
        let layout = try NotationEngraver.engrave(flaggedEighthInput(), style: style)
        #expect(layout.flags.count == 1)
        #expect(layout.beams.isEmpty)
        let raster = try probe(layout)

        let head = try #require(layout.noteHeads.first)
        #expect(raster.inkCount(in: head.paintedBounds) > 0)

        let flag = try #require(layout.flags.first)
        let metrics = PercussionGlyphMetrics.flag(
            duration: flag.duration,
            direction: flag.stemDirection,
            staffSpace: style.formatting.staffSpace
        )
        let flagBounds = metrics.paintedBounds.offsetBy(
            dx: flag.origin.x - metrics.attachmentOffset.x,
            dy: flag.origin.y - metrics.attachmentOffset.y
        )
        #expect(raster.inkCount(in: flagBounds) > 0)
        #expect(layout.stems.isEmpty == false)
    }

    @Test("beamed run paints inside final bounds")
    @MainActor
    func beamedRunPaintsInsideBounds() async throws {
        let layout = try NotationEngraver.engrave(beamedRunInput(), style: style)
        #expect(layout.beams.isEmpty == false)
        #expect(layout.flags.isEmpty)
        let raster = try probe(layout)

        let beam = try #require(layout.beams.first)
        let beamBounds = CGRect(
            x: min(beam.start.x, beam.end.x),
            y: min(beam.start.y, beam.end.y) - beam.thickness / 2,
            width: abs(beam.end.x - beam.start.x),
            height: beam.thickness
        )
        #expect(raster.inkCount(in: beamBounds) > 0)
        for head in layout.noteHeads {
            #expect(raster.inkCount(in: head.paintedBounds) > 0)
        }
    }

    @Test("control + bracketed tuplet paint inside final bounds")
    @MainActor
    func controlAndTupletPaintInsideBounds() async throws {
        let layout = try NotationEngraver.engrave(controlTupletInput(), style: style)
        let raster = try probe(layout)

        let control = try #require(layout.controls.first)
        let markExtent = style.stopMarkSize + style.stopMarkStrokeWidth
        let markBounds = CGRect(
            x: control.position.x - markExtent / 2,
            y: control.position.y - markExtent / 2,
            width: markExtent,
            height: markExtent
        )
        #expect(raster.inkCount(in: markBounds) > 0)

        let tuplet = try #require(layout.tuplets.first)
        #expect(tuplet.isBracketVisible)
        #expect(tuplet.bracketPoints.count == 6)
        let labelRect = CGRect(
            x: tuplet.labelPosition.x - style.tupletLabelSize.width / 2,
            y: tuplet.labelPosition.y - style.tupletLabelSize.height / 2,
            width: style.tupletLabelSize.width,
            height: style.tupletLabelSize.height
        )
        #expect(raster.inkCount(in: labelRect) > 0)
    }

    @Test("the tuplet numeral paints ratio.actual, not a fixed three")
    @MainActor
    func tupletNumeralFollowsRatio() async throws {
        // Identical members under two declared ratios give identical label
        // geometry (`labelPosition` reads member bounds, never the ratio),
        // so the label rect's alpha bytes isolate the painted numeral.
        let fiveFour = try NotationEngraver.engrave(
            quintupletInput(actual: 5, normal: 4), style: style
        )
        let control = try NotationEngraver.engrave(
            quintupletInput(actual: 3, normal: 2), style: style
        )
        let tuplet5 = try #require(fiveFour.tuplets.first)
        let tuplet3 = try #require(control.tuplets.first)
        #expect(tuplet5.ratio.actual == 5)
        #expect(tuplet5.isBracketVisible && tuplet3.isBracketVisible)
        #expect(tuplet5.labelPosition == tuplet3.labelPosition)

        let size = CGSize(
            width: fiveFour.contentWidth, height: fiveFour.contentHeight
        )
        let raster5 = try rasterize(
            DrumNotationView(layout: fiveFour, accessibilityLabels: [:]), size: size
        )
        let raster3 = try rasterize(
            DrumNotationView(layout: control, accessibilityLabels: [:]), size: size
        )
        let labelRect = CGRect(
            x: tuplet5.labelPosition.x - style.tupletLabelSize.width / 2,
            y: tuplet5.labelPosition.y - style.tupletLabelSize.height / 2,
            width: style.tupletLabelSize.width,
            height: style.tupletLabelSize.height
        )
        #expect(raster5.inkCount(in: labelRect) > 0)
        #expect(raster3.inkCount(in: labelRect) > 0)
        #expect(raster5.alphaBytes(in: labelRect) != raster3.alphaBytes(in: labelRect))
    }

    @Test("multi-digit and long numerals stay inside the reserved label rect")
    @MainActor
    func longTupletNumeralFitsLabelRect() async throws {
        // `ratio.actual` is an arbitrary positive Int. "12" covers real
        // multi-digit tuplets; "123456789" overflows the old 0.5
        // minimumScaleFactor floor outright. Either way the whole numeral
        // must render inside the reserved `tupletLabelSize` rect.
        for actual in [12, 123_456_789] {
            let layout = try NotationEngraver.engrave(
                quintupletInput(actual: actual, normal: 4), style: style
            )
            let tuplet = try #require(layout.tuplets.first)
            let labelRect = CGRect(
                x: tuplet.labelPosition.x - style.tupletLabelSize.width / 2,
                y: tuplet.labelPosition.y - style.tupletLabelSize.height / 2,
                width: style.tupletLabelSize.width,
                height: style.tupletLabelSize.height
            )
            let raster = try rasterize(
                DrumNotationView(layout: layout, accessibilityLabels: [:]),
                size: CGSize(
                    width: layout.contentWidth, height: layout.contentHeight
                )
            )
            #expect(raster.inkCount(in: labelRect) > 0)
            // Probe strips just past the label rect's left/right edges,
            // restricted to the label's center band: inside the bracket
            // gap (bracket ink stops halfGap = labelW/2 + dotSpacing past
            // the center), away from staff lines (labelY sits mid-band
            // between them) and member stems (member columns are well
            // outside the strip). Only numeral ink spilling the reserved
            // rect horizontally can land here.
            let stripHeight: CGFloat = 3
            for side: CGFloat in [-1, 1] {
                let strip = CGRect(
                    x: side < 0
                        ? labelRect.minX - 2.5
                        : labelRect.maxX + 1.25,
                    y: tuplet.labelPosition.y - stripHeight / 2,
                    width: 1.25,
                    height: stripHeight
                )
                #expect(
                    raster.inkCount(in: strip) == 0,
                    "numeral spills the label rect (actual=\(actual), side=\(side))"
                )
            }
        }
    }

    @Test("the measured numeral path fits the reserved label size for any digit count")
    func tupletNumeralPathFitsLabelSize() {
        // The fit contract directly: `boundingBox` is control-point bounds
        // (⊇ ink), so if it fits the label size the painted numeral provably
        // stays inside — for single digits, real multi-digit tuplets, and
        // absurdly long positive ratios alike.
        let size = CGSize(width: 14, height: 16)
        for actual in [3, 12, 123_456_789] {
            let bounds = BravuraFont.tupletNumeralPath(
                actual: actual, fitting: size
            ).boundingBox
            #expect(bounds.width <= size.width + 0.01)
            #expect(bounds.height <= size.height + 0.01)
            #expect(bounds.width > 0 && bounds.height > 0)
        }
    }

    @Test("clef + meter painters stay inside small slots with a wide meter")
    @MainActor
    func furniturePaintsInsideSmallSlots() async throws {
        // staffSpace 6 → 24pt staff; clef slot 8×24, meter slot 10×24 under
        // a 12/8 signature. A stemless whole note keeps all other ink below
        // the staff top, so fixed-size furniture overflow escapes the union.
        let smallStyle = NotationEngravingStyle(
            formatting: NotationFormattingStyle(staffSpace: 6),
            clefWidth: 8,
            meterWidth: 10
        )
        let layout = try NotationEngraver.engrave(
            smallFurnitureInput(), style: smallStyle
        )
        let raster = try probe(layout)

        let row = try #require(layout.rows.first)
        #expect(raster.inkCount(in: row.clef.paintedBounds) > 0)
        #expect(raster.inkCount(in: row.meterSignature.paintedBounds) > 0)
    }
}
