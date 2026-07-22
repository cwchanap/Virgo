//
//  DrumBeat.swift
//  Virgo
//
//  Time-indexed grouping of simultaneous drum hits, used by GameplayViewModel
//  for input-timing logic and beat ↔ note-head mapping.
//

struct DrumBeat {
    let id: UInt64
    let drums: [DrumType]
    let timePosition: Double
    let interval: NoteInterval
    let rhythmEventID: RhythmEventID?
    let rhythmPosition: RhythmEventPosition?

    init(
        id: UInt64,
        drums: [DrumType],
        timePosition: Double,
        interval: NoteInterval,
        rhythmEventID: RhythmEventID? = nil,
        rhythmPosition: RhythmEventPosition? = nil
    ) {
        self.id = id
        self.drums = drums
        self.timePosition = timePosition
        self.interval = interval
        self.rhythmEventID = rhythmEventID
        self.rhythmPosition = rhythmPosition
    }
}
