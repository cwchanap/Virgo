import CoreGraphics
import DrumNotation
import Foundation

/// The app's notation style input (HPA-166 Task 7): the only remaining
/// app-owned style surface. `VirgoNotationProjection.engravingStyle(for:)`
/// maps it into the package `NotationEngravingStyle`; feel/warning
/// annotation sizing reads it directly. All package geometry metrics are
/// owned by the package — nothing here positions primitives anymore.
struct NotationLayoutStyle: Equatable, Sendable {
    let rowWidth: CGFloat
    let staffLineSpacing: CGFloat
    let stemLength: CGFloat
    let minimumStemExtensionPastChord: CGFloat
    let beamThickness: CGFloat
    let beamLevelSpacing: CGFloat
    let beamHookLength: CGFloat
    let ledgerLineOverhang: CGFloat
    let upperVoiceRestOffset: CGFloat
    let lowerVoiceRestOffset: CGFloat
    let stopMarkSize: CGFloat
    let stopMarkStrokeWidth: CGFloat
    let stopMarkVerticalOffset: CGFloat
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

    static let gameplayDefault = NotationLayoutStyle(
        rowWidth: GameplayLayout.maxRowWidth,
        staffLineSpacing: GameplayLayout.staffLineSpacing,
        stemLength: GameplayLayout.stemHeight,
        minimumStemExtensionPastChord: GameplayLayout.staffLineSpacing / 2,
        beamThickness: 4,
        beamLevelSpacing: GameplayLayout.beamLevelSpacing,
        beamHookLength: 12,
        ledgerLineOverhang: 6,
        upperVoiceRestOffset: -GameplayLayout.staffLineSpacing,
        lowerVoiceRestOffset: GameplayLayout.staffLineSpacing,
        stopMarkSize: 14,
        stopMarkStrokeWidth: 2,
        stopMarkVerticalOffset: 18,
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
            rowWidth: newRowWidth,
            staffLineSpacing: staffLineSpacing,
            stemLength: stemLength,
            minimumStemExtensionPastChord: minimumStemExtensionPastChord,
            beamThickness: beamThickness,
            beamLevelSpacing: beamLevelSpacing,
            beamHookLength: beamHookLength,
            ledgerLineOverhang: ledgerLineOverhang,
            upperVoiceRestOffset: upperVoiceRestOffset,
            lowerVoiceRestOffset: lowerVoiceRestOffset,
            stopMarkSize: stopMarkSize,
            stopMarkStrokeWidth: stopMarkStrokeWidth,
            stopMarkVerticalOffset: stopMarkVerticalOffset,
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
