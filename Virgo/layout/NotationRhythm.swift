struct TupletRatio: Hashable, Sendable {
    let actual: Int
    let normal: Int
}

struct NotationRhythm: Hashable, Sendable {
    let baseInterval: NoteInterval
    let dotCount: Int
    let tuplet: TupletRatio?
    let support: RhythmSemanticSupport

    init(
        baseInterval: NoteInterval,
        dotCount: Int = 0,
        tuplet: TupletRatio? = nil,
        support: RhythmSemanticSupport = .supported
    ) {
        self.baseInterval = baseInterval
        self.dotCount = dotCount
        self.tuplet = tuplet
        self.support = support
    }
}

struct RhythmTupletID: Hashable, Sendable {
    let measureIndex: Int
    let voice: NotationVoice
    let beatGroupIndex: Int
    let startTick: Int
    let durationTicks: Int
    let stableMemberEventID: RhythmEventID

    init(
        measureIndex: Int,
        voice: NotationVoice,
        beatGroupIndex: Int,
        startTick: Int,
        durationTicks: Int,
        stableMemberEventID: RhythmEventID = RhythmEventID(rawValue: -1)
    ) {
        self.measureIndex = measureIndex
        self.voice = voice
        self.beatGroupIndex = beatGroupIndex
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.stableMemberEventID = stableMemberEventID
    }
}

enum TupletBracketVisibility: Hashable, Sendable {
    case shown
    case suppressedForFeel
}

struct RhythmAnalysisEvent: Hashable, Sendable {
    let eventID: RhythmEventID
    let origin: ResolvedRhythmEventOrigin
    let position: RhythmEventPosition
    let voice: NotationVoice
    let storedInterval: NoteInterval
    let visualDurationCandidate: NoteInterval?
}

struct AnalyzedRhythmNote: Hashable, Sendable {
    let eventID: RhythmEventID
    let position: RhythmEventPosition
    let voice: NotationVoice
    let beatGroupIndex: Int
    let durationTicks: Int
    let rhythm: NotationRhythm
    let tupletID: RhythmTupletID?
}

struct AnalyzedRhythmRest: Hashable, Sendable {
    let measureIndex: Int
    let voice: NotationVoice
    let startTick: Int
    let durationTicks: Int
    let rhythm: NotationRhythm
    let tupletID: RhythmTupletID?
    let visibility: NotationRestVisibility
}

struct AnalyzedRhythmTuplet: Hashable, Sendable {
    let id: RhythmTupletID
    let ratio: TupletRatio
    let bracketVisibility: TupletBracketVisibility
}

struct RhythmMeasureWarning: Hashable, Sendable {
    let measureIndex: Int
    let codes: Set<RhythmDiagnosticCode>
}

struct NotationRhythmAnalysis: Hashable, Sendable {
    let notes: [AnalyzedRhythmNote]
    let rests: [AnalyzedRhythmRest]
    let tuplets: [AnalyzedRhythmTuplet]
    let warnings: [RhythmMeasureWarning]

    static let empty = NotationRhythmAnalysis(notes: [], rests: [], tuplets: [], warnings: [])
}
