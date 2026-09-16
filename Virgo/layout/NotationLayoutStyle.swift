import CoreGraphics
import DrumNotation
import Foundation

/// The app's notation style input (HPA-166 Task 7): the only remaining
/// app-owned style surface. `VirgoNotationProjection.engravingStyle(for:)`
/// maps it into the package `NotationEngravingStyle`; feel/warning
/// annotation sizing reads it directly. All package geometry metrics are
/// owned by the package — nothing here positions primitives anymore.
struct NotationLayoutStyle: Equatable, Sendable {
    let minimumNoteColumnGap: CGFloat
    let minimumQuarterBeatGap: CGFloat
    let rowWidth: CGFloat
    let staffLineSpacing: CGFloat
    let noteHeadWidth: CGFloat
    let noteHeadHeight: CGFloat
    let stemLength: CGFloat
    let stemWidth: CGFloat
    let minimumStemExtensionPastChord: CGFloat
    let beamThickness: CGFloat
    let beamLevelSpacing: CGFloat
    let beamHookLength: CGFloat
    let ledgerLineOverhang: CGFloat
    let restSymbolWidth: CGFloat
    let restSymbolHeight: CGFloat
    let fullMeasureRestWidth: CGFloat
    let fullMeasureRestHeight: CGFloat
    let upperVoiceRestOffset: CGFloat
    let lowerVoiceRestOffset: CGFloat
    let stopMarkSize: CGFloat
    let stopMarkStrokeWidth: CGFloat
    let stopMarkVerticalOffset: CGFloat
    let articulationDiameter: CGFloat
    let articulationStrokeWidth: CGFloat
    let articulationVerticalOffset: CGFloat
    let rhythmDotRadius: CGFloat
    let rhythmDotSpacing: CGFloat
    let tupletLineWidth: CGFloat
    let tupletLabelSize: CGSize
    let tupletVerticalOffset: CGFloat
    let tupletHookLength: CGFloat
    let feelMarkSize: CGSize
    let feelMarkVerticalOffset: CGFloat
    let warningSize: CGSize
    let warningVerticalOffset: CGFloat

    var noteHeadSize: CGSize {
        CGSize(width: noteHeadWidth, height: noteHeadHeight)
    }

    static let gameplayDefault = NotationLayoutStyle(
        minimumNoteColumnGap: 28,
        minimumQuarterBeatGap: GameplayLayout.uniformSpacing,
        rowWidth: GameplayLayout.maxRowWidth,
        staffLineSpacing: GameplayLayout.staffLineSpacing,
        noteHeadWidth: GameplayLayout.beatColumnWidth,
        noteHeadHeight: GameplayLayout.drumSymbolFontSize,
        stemLength: GameplayLayout.stemHeight,
        stemWidth: GameplayLayout.stemWidth,
        minimumStemExtensionPastChord: GameplayLayout.staffLineSpacing / 2,
        beamThickness: 4,
        beamLevelSpacing: GameplayLayout.beamLevelSpacing,
        beamHookLength: 12,
        ledgerLineOverhang: 6,
        restSymbolWidth: 18,
        restSymbolHeight: 28,
        fullMeasureRestWidth: 18,
        fullMeasureRestHeight: 5,
        upperVoiceRestOffset: -GameplayLayout.staffLineSpacing,
        lowerVoiceRestOffset: GameplayLayout.staffLineSpacing,
        stopMarkSize: 14,
        stopMarkStrokeWidth: 2,
        stopMarkVerticalOffset: 18,
        articulationDiameter: 10,
        articulationStrokeWidth: 1.5,
        // pictOpen half (11.44) + noteheadXBlack half (10) + 2pt gap at staffSpace 20.
        articulationVerticalOffset: 24,
        rhythmDotRadius: 2.5,
        rhythmDotSpacing: 4,
        tupletLineWidth: 1.5,
        tupletLabelSize: CGSize(width: 14, height: 16),
        tupletVerticalOffset: 10,
        tupletHookLength: 6,
        feelMarkSize: CGSize(width: 72, height: 22),
        feelMarkVerticalOffset: 30,
        warningSize: CGSize(width: 180, height: 22),
        warningVerticalOffset: 56
    )

    func with(rowWidth newRowWidth: CGFloat) -> NotationLayoutStyle {
        NotationLayoutStyle(
            minimumNoteColumnGap: minimumNoteColumnGap,
            minimumQuarterBeatGap: minimumQuarterBeatGap,
            rowWidth: newRowWidth,
            staffLineSpacing: staffLineSpacing,
            noteHeadWidth: noteHeadWidth,
            noteHeadHeight: noteHeadHeight,
            stemLength: stemLength,
            stemWidth: stemWidth,
            minimumStemExtensionPastChord: minimumStemExtensionPastChord,
            beamThickness: beamThickness,
            beamLevelSpacing: beamLevelSpacing,
            beamHookLength: beamHookLength,
            ledgerLineOverhang: ledgerLineOverhang,
            restSymbolWidth: restSymbolWidth,
            restSymbolHeight: restSymbolHeight,
            fullMeasureRestWidth: fullMeasureRestWidth,
            fullMeasureRestHeight: fullMeasureRestHeight,
            upperVoiceRestOffset: upperVoiceRestOffset,
            lowerVoiceRestOffset: lowerVoiceRestOffset,
            stopMarkSize: stopMarkSize,
            stopMarkStrokeWidth: stopMarkStrokeWidth,
            stopMarkVerticalOffset: stopMarkVerticalOffset,
            articulationDiameter: articulationDiameter,
            articulationStrokeWidth: articulationStrokeWidth,
            articulationVerticalOffset: articulationVerticalOffset,
            rhythmDotRadius: rhythmDotRadius,
            rhythmDotSpacing: rhythmDotSpacing,
            tupletLineWidth: tupletLineWidth,
            tupletLabelSize: tupletLabelSize,
            tupletVerticalOffset: tupletVerticalOffset,
            tupletHookLength: tupletHookLength,
            feelMarkSize: feelMarkSize,
            feelMarkVerticalOffset: feelMarkVerticalOffset,
            warningSize: warningSize,
            warningVerticalOffset: warningVerticalOffset
        )
    }
}
