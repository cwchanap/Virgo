import CoreGraphics
import DrumNotation

/// One resolved flag paint operation, shared by production rendering and the
/// raster probe. Pure data: paint consumers never search sibling flags.
struct FlagPaintCommand: Identifiable, Equatable {
    let id: String
    let center: CGPoint
    let duration: NotationDuration
    let direction: NotationStemDirection
    let staffSpace: CGFloat
    let paintedBounds: CGRect
}

/// The single pure app-to-package mapping seam between Virgo's DTX/notation
/// domain and the `DrumNotation` package. Takes values in, returns values out:
/// no view construction, no rendering, no mutation of layout outputs.
enum VirgoNotationAdapter {
    static func noteheadStyle(for noteType: NoteType) -> PercussionNoteheadStyle {
        switch noteType {
        case .bass, .snare, .highTom, .midTom, .lowTom:
            return .normal
        case .hiHat, .hiHatPedal, .openHiHat, .crash, .ride, .china, .splash:
            return .x
        case .cowbell:
            return .diamond
        }
    }

    static func duration(for interval: NoteInterval) -> NotationDuration {
        switch interval {
        case .full:
            return .whole
        case .half:
            return .half
        case .quarter:
            return .quarter
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtysecond:
            return .thirtySecond
        case .sixtyfourth:
            return .sixtyFourth
        }
    }

    static func stemDirection(_ direction: StemDirection) -> NotationStemDirection {
        switch direction {
        case .up:
            return .up
        case .down:
            return .down
        }
    }

    static func restDuration(_ duration: NotationRestDuration) -> NotationDuration? {
        switch duration {
        case .fullMeasure:
            return .whole
        case .half:
            return .half
        case .quarter:
            return .quarter
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtySecond:
            return .thirtySecond
        case .sixtyFourth:
            return .sixtyFourth
        case .indeterminate:
            return nil
        }
    }

    static func staffSpace(for style: NotationLayoutStyle) -> CGFloat {
        style.staffLineSpacing
    }

    /// Resolves `RenderedFlag`s into package-backed paint commands.
    ///
    /// Policy per head: expected uncovered levels are `0..<head.interval.flagCount`.
    /// When the actual uncovered levels exactly equal that set, emit one command
    /// from level 0 at the head's canonical duration and suppress sibling levels;
    /// otherwise emit one `.eighth` command per existing flag, preserving each
    /// origin. Output order always follows the input `flags` order.
    static func flagPaintCommands(
        flags: [RenderedFlag],
        heads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [FlagPaintCommand] {
        let headsByID = Dictionary(heads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var suppressedFlagIDs = Set<String>()
        var canonicalByFlagID: [String: FlagPaintCommand] = [:]

        for (headID, headFlags) in Dictionary(grouping: flags, by: \.noteHeadID) {
            guard let head = headsByID[headID],
                let levelZero = headFlags.first(where: { $0.flagIndex == 0 }),
                Set(headFlags.map(\.flagIndex)) == Set(0..<head.interval.flagCount)
            else { continue }

            for flag in headFlags where flag.flagIndex != 0 {
                suppressedFlagIDs.insert(flag.id)
            }
            canonicalByFlagID[levelZero.id] = makeCommand(
                id: levelZero.id,
                origin: levelZero.origin,
                duration: duration(for: head.interval),
                direction: stemDirection(levelZero.stemDirection),
                style: style
            )
        }

        return flags.compactMap { flag in
            if let canonical = canonicalByFlagID[flag.id] {
                return canonical
            }
            guard !suppressedFlagIDs.contains(flag.id) else { return nil }
            return makeCommand(
                id: flag.id,
                origin: flag.origin,
                duration: .eighth,
                direction: stemDirection(flag.stemDirection),
                style: style
            )
        }
    }

    /// Effective minimum stem length for one unbeamed stem group: the maximum
    /// canonical-flag clearance required by any flagged member, or the default
    /// `style.stemLength` when no member carries a flag (full/half/quarter).
    /// Task 6's `unbeamedStemEndY` passes the heads sharing that stem; the
    /// result replaces the bare `style.stemLength` in its extent arithmetic.
    /// Pure data only: never changes beam grouping or `buildFlags` output.
    static func minimumUnbeamedStemLength(
        heads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> CGFloat {
        var required = style.stemLength
        for head in heads where head.interval.flagCount > 0 {
            let direction = stemDirection(head.stemDirection)
            let metrics = PercussionGlyphMetrics.flag(
                duration: duration(for: head.interval),
                direction: direction,
                staffSpace: staffSpace(for: style)
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
            required = max(required, inwardExtent + style.minimumStemExtensionPastChord)
        }
        return required
    }

    private static func makeCommand(
        id: String,
        origin: CGPoint,
        duration: NotationDuration,
        direction: NotationStemDirection,
        style: NotationLayoutStyle
    ) -> FlagPaintCommand {
        let staffSpace = staffSpace(for: style)
        let metrics = PercussionGlyphMetrics.flag(
            duration: duration,
            direction: direction,
            staffSpace: staffSpace
        )
        let center = CGPoint(
            x: origin.x - metrics.attachmentOffset.x,
            y: origin.y - metrics.attachmentOffset.y
        )
        return FlagPaintCommand(
            id: id,
            center: center,
            duration: duration,
            direction: direction,
            staffSpace: staffSpace,
            paintedBounds: metrics.paintedBounds.offsetBy(dx: center.x, dy: center.y)
        )
    }
}
