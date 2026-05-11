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
}
