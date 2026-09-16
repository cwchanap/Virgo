import CoreGraphics
import DrumNotation

/// One resolved flag paint operation. Pure data: paint consumers never
/// search sibling flags.
struct FlagPaintCommand: Identifiable, Equatable {
    let id: String
    let center: CGPoint
    let duration: NotationFlagDuration
    let direction: NotationStemDirection
    let staffSpace: CGFloat
    let paintedBounds: CGRect
}

/// The single pure app-to-package mapping seam between Virgo's DTX/notation
/// domain and the `DrumNotation` package. Takes values in, returns values out:
/// no view construction, no rendering, no mutation of layout outputs (HPA-166
/// Task 7). The pre-format projection lives in ``VirgoNotationProjection``.
///
/// The flag/stem-geometry helpers below (`flagPaintCommands`,
/// `noteheadMetrics`, `maximumFlagInwardExtent`, `minimumUnbeamedStemLength`)
/// belong to the restored, disconnected legacy `Rendered*` model — production
/// rendering reads the package `EngravedNotation` instead. Task 8 deletes
/// them with the legacy model.
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

    /// The flag duration for `interval`, or nil for intervals that never carry
    /// a flag (full/half/quarter). Legacy-model helper.
    static func flagDuration(for interval: NoteInterval) -> NotationFlagDuration? {
        switch interval {
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtysecond:
            return .thirtySecond
        case .sixtyfourth:
            return .sixtyFourth
        case .full, .half, .quarter:
            return nil
        }
    }

    static func articulation(for kind: RenderedArticulationKind) -> PercussionArticulation {
        switch kind {
        case .openHiHat:
            return .open
        }
    }

    static func staffSpace(for style: NotationLayoutStyle) -> CGFloat {
        style.staffLineSpacing
    }

    /// The single package-metrics lookup for one rendered head: painted bounds
    /// and stem anchor offset in head-local coordinates (Y-down, centered on
    /// ``RenderedNoteHead.position``). Callers translate by `head.position`.
    static func noteheadMetrics(
        for head: RenderedNoteHead,
        style: NotationLayoutStyle
    ) -> NoteheadMetrics {
        PercussionGlyphMetrics.notehead(
            style: noteheadStyle(for: head.noteType),
            duration: duration(for: head.interval),
            stemDirection: stemDirection(head.stemDirection),
            staffSpace: staffSpace(for: style)
        )
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
                let canonicalDuration = flagDuration(for: head.interval),
                Set(headFlags.map(\.flagIndex)) == Set(0..<head.interval.flagCount)
            else { continue }

            for flag in headFlags where flag.flagIndex != 0 {
                suppressedFlagIDs.insert(flag.id)
            }
            canonicalByFlagID[levelZero.id] = makeCommand(
                id: levelZero.id,
                origin: levelZero.origin,
                duration: canonicalDuration,
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

    /// The maximum distance any flagged member's canonical Bravura flag
    /// reaches back from the stem attachment point toward the noteheads,
    /// measured along the stem. Zero when no member carries a flag
    /// (full/half/quarter). Pure package metrics; no layout policy.
    static func maximumFlagInwardExtent(
        heads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> CGFloat {
        var extent: CGFloat = 0
        for head in heads {
            guard let flagDuration = flagDuration(for: head.interval) else { continue }
            let direction = stemDirection(head.stemDirection)
            let metrics = PercussionGlyphMetrics.flag(
                duration: flagDuration,
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
            extent = max(extent, inwardExtent)
        }
        return extent
    }

    /// Effective minimum stem length for one unbeamed stem group: the maximum
    /// canonical-flag clearance required by any flagged member, or the default
    /// `style.stemLength` when no member carries a flag (full/half/quarter).
    /// The legacy `unbeamedStemEndY` passes the heads sharing that stem; the
    /// result replaces the bare `style.stemLength` in its extent arithmetic.
    /// Pure data only: never changes beam grouping or `buildFlags` output.
    static func minimumUnbeamedStemLength(
        heads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> CGFloat {
        max(
            style.stemLength,
            maximumFlagInwardExtent(heads: heads, style: style)
                + style.minimumStemExtensionPastChord
        )
    }

    private static func makeCommand(
        id: String,
        origin: CGPoint,
        duration: NotationFlagDuration,
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
