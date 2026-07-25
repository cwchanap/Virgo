import Foundation
@testable import Virgo

/// One drum-tab regression fixture: a small DTX chart plus the metadata the
/// harness needs to render it deterministically.
struct DrumTabFixture {
    let name: String
    let dtx: String
    let minimumMeasureCount: Int
    /// Control-lane chip lines, kept separate so fixture 8 can be rendered with
    /// and without them to prove control events do not feed rest inference.
    let controlBlock: String?

    init(
        name: String,
        dtx: String,
        minimumMeasureCount: Int = 1,
        controlBlock: String? = nil
    ) {
        self.name = name
        self.dtx = dtx
        self.minimumMeasureCount = minimumMeasureCount
        self.controlBlock = controlBlock
    }

    /// Full DTX text, optionally including the control block.
    func source(includeControls: Bool) -> String {
        guard includeControls, let controlBlock else { return dtx }
        return dtx + "\n" + controlBlock
    }

    /// Builds a DTX chip line. Positions not listed are empty (`00`).
    ///
    /// Generated rather than hand-typed because high-resolution fixtures need
    /// 64-position (128-character) lines where a miscount is invisible.
    static func line(
        measure: Int,
        lane: String,
        positions: [Int: String],
        total: Int
    ) -> String {
        let chips = (0..<total)
            .map { positions[$0] ?? "00" }
            .joined()
        let measureField = String(format: "%03d", measure)
        return "#\(measureField)\(lane): \(chips)"
    }

    /// Convenience for lines where every filled position uses the same note ID.
    static func line(
        measure: Int,
        lane: String,
        at positions: [Int],
        total: Int,
        noteID: String = "01"
    ) -> String {
        line(
            measure: measure,
            lane: lane,
            positions: Dictionary(uniqueKeysWithValues: positions.map { ($0, noteID) }),
            total: total
        )
    }
}
