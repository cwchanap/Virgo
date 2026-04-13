import Foundation
import Combine

struct MIDIDiagnosticSnapshot: Equatable {
    let sourceID: String
    let sourceDisplayName: String
    let channel: UInt8
    let note: UInt8
    let velocity: UInt8
    let mappedDrumType: DrumType?
}

@MainActor
final class MIDIDiagnosticsStore: ObservableObject {
    @Published private(set) var lastEvent: MIDIDiagnosticSnapshot?

    func record(event: MIDINoteEvent, mappedDrumType: DrumType?, sourceDisplayName: String) {
        lastEvent = MIDIDiagnosticSnapshot(
            sourceID: event.sourceID,
            sourceDisplayName: sourceDisplayName,
            channel: event.channel,
            note: event.note,
            velocity: event.velocity,
            mappedDrumType: mappedDrumType
        )
    }
}
