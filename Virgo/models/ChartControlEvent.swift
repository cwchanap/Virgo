import Foundation
import SwiftData

enum NotationControlEventKind: String, Codable, CaseIterable, Hashable {
    case stop
    case choke
    case damp
}

@Model
final class ChartControlEvent {
    var kind: NotationControlEventKind
    var measureNumber: Int
    var measureOffset: Double
    var chart: Chart?
    var originKind: NoteOriginKind = NoteOriginKind.manual
    var sourceLaneID: String?
    var sourceNoteID: String?
    var sourceGridPosition: Int?
    var sourceGridSize: Int?
    var normalizedMeasureIndex: Int?
    var normalizedAbsoluteTick: Int?
    var normalizedTickWithinMeasure: Int?
    var normalizedTicksPerMeasure: Int?
    var targetLaneID: String?

    init(
        kind: NotationControlEventKind,
        measureNumber: Int,
        measureOffset: Double,
        chart: Chart? = nil,
        originKind: NoteOriginKind = .manual,
        sourceLaneID: String? = nil,
        sourceNoteID: String? = nil,
        sourceGridPosition: Int? = nil,
        sourceGridSize: Int? = nil,
        normalizedMeasureIndex: Int? = nil,
        normalizedAbsoluteTick: Int? = nil,
        normalizedTickWithinMeasure: Int? = nil,
        normalizedTicksPerMeasure: Int? = nil,
        targetLaneID: String? = nil
    ) {
        self.kind = kind
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
        self.chart = chart
        self.originKind = originKind
        self.sourceLaneID = sourceLaneID
        self.sourceNoteID = sourceNoteID
        self.sourceGridPosition = sourceGridPosition
        self.sourceGridSize = sourceGridSize
        self.normalizedMeasureIndex = normalizedMeasureIndex
        self.normalizedAbsoluteTick = normalizedAbsoluteTick
        self.normalizedTickWithinMeasure = normalizedTickWithinMeasure
        self.normalizedTicksPerMeasure = normalizedTicksPerMeasure
        self.targetLaneID = targetLaneID
    }
}

struct NotationControlEvent: Hashable {
    let kind: NotationControlEventKind
    let measureNumber: Int
    let measureOffset: Double
    let originKind: NoteOriginKind
    let sourceLaneID: String?
    let sourceNoteID: String?
    let sourceGridPosition: Int?
    let sourceGridSize: Int?
    let normalizedMeasureIndex: Int?
    let normalizedAbsoluteTick: Int?
    let normalizedTickWithinMeasure: Int?
    let normalizedTicksPerMeasure: Int?
    let targetLaneID: String?

    init(_ event: ChartControlEvent) {
        kind = event.kind
        measureNumber = event.measureNumber
        measureOffset = event.measureOffset
        originKind = event.originKind
        sourceLaneID = event.sourceLaneID
        sourceNoteID = event.sourceNoteID
        sourceGridPosition = event.sourceGridPosition
        sourceGridSize = event.sourceGridSize
        normalizedMeasureIndex = event.normalizedMeasureIndex
        normalizedAbsoluteTick = event.normalizedAbsoluteTick
        normalizedTickWithinMeasure = event.normalizedTickWithinMeasure
        normalizedTicksPerMeasure = event.normalizedTicksPerMeasure
        targetLaneID = event.targetLaneID
    }
}
