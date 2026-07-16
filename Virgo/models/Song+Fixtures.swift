//
//  Song+Fixtures.swift
//  Virgo
//
//  Fixture/sample-data helpers extracted from DrumTrack.swift to keep the
//  core model file under SwiftLint's file-length limit.
//

import Foundation

extension Song {
    static var sampleData: [Song] {
        let song1 = Song(
            title: "Thunder Beat",
            artist: "Rock Masters",
            bpm: 140.0,
            duration: "3:45",
            genre: "Rock",
            timeSignature: .fourFour
        )
        let song2 = Song(
            title: "Blast Beat Fury",
            artist: "Metal Gods",
            bpm: 180.0,
            duration: "4:20",
            genre: "Metal",
            timeSignature: .fourFour
        )
        let song3 = Song(
            title: "Jazz Groove",
            artist: "Smooth Collective",
            bpm: 120.0,
            duration: "5:30",
            genre: "Jazz",
            timeSignature: .fourFour
        )
        let song4 = Song(
            title: "Electronic Pulse",
            artist: "Digital Beats",
            bpm: 128.0,
            duration: "3:15",
            genre: "Electronic",
            timeSignature: .fourFour
        )
        let song5 = Song(
            title: "Latin Rhythm",
            artist: "Salsa Kings",
            bpm: 95.0,
            duration: "4:00",
            genre: "Latin",
            timeSignature: .fourFour
        )

        let song6 = Song(
            title: "Progressive Complex",
            artist: "Time Masters",
            bpm: 160.0,
            duration: "6:45",
            genre: "Progressive",
            timeSignature: .fiveFour
        )
        let song7 = Song(
            title: "Hip Hop Foundation",
            artist: "Beat Makers",
            bpm: 85.0,
            duration: "3:30",
            genre: "Hip Hop",
            timeSignature: .fourFour
        )
        // Create charts for each song with different difficulties
        let chart1Easy = Chart(difficulty: .easy)
        let chart1Medium = Chart(difficulty: .medium)
        song1.charts = [chart1Easy, chart1Medium]
        let chart2Hard = Chart(difficulty: .hard)
        let chart2Expert = Chart(difficulty: .expert)
        song2.charts = [chart2Hard, chart2Expert]
        let chart3Easy = Chart(difficulty: .easy)
        let chart3Medium = Chart(difficulty: .medium)
        let chart3Hard = Chart(difficulty: .hard)
        song3.charts = [chart3Easy, chart3Medium, chart3Hard]
        let chart4Medium = Chart(difficulty: .medium)
        song4.charts = [chart4Medium]

        let chart5Easy = Chart(difficulty: .easy)
        let chart5Medium = Chart(difficulty: .medium)
        song5.charts = [chart5Easy, chart5Medium]

        let chart6Expert = Chart(difficulty: .expert)
        song6.charts = [chart6Expert]

        let chart7Easy = Chart(difficulty: .easy)
        song7.charts = [chart7Easy]

        chart1Easy.notes = Self.thunderBeatVerificationNotes()
        chart1Medium.notes = Self.thunderBeatVerificationNotes(includeFills: true)

        return [song1, song2, song3, song4, song5, song6, song7]
    }

    static func fixtureCopy(from template: Song, genre: String? = nil, isServerImported: Bool? = nil) -> Song {
        let song = Song(
            title: template.title,
            artist: template.artist,
            bpm: template.bpm,
            duration: template.duration,
            genre: genre ?? template.genre,
            timeSignature: template.timeSignature,
            isPlaying: template.isPlaying,
            playCount: template.playCount,
            isSaved: template.isSaved,
            isServerImported: isServerImported ?? template.isServerImported,
            serverSongId: template.serverSongId,
            bgmFilePath: template.bgmFilePath,
            previewFilePath: template.previewFilePath,
            bgmStartOffsetSeconds: template.bgmStartOffsetSeconds
        )
        song.charts = template.charts.map { templateChart in
            let chart = Chart(
                difficulty: templateChart.difficulty,
                level: templateChart.level,
                timeSignature: templateChart.timeSignature,
                song: song
            )
            chart.notes = copiedNotes(from: templateChart, into: chart)
            chart.controlEvents = copiedControlEvents(from: templateChart, into: chart)
            return chart
        }
        return song
    }

    private static func copiedNotes(from templateChart: Chart, into chart: Chart) -> [Note] {
        templateChart.safeNotes.map { templateNote in
            Note(
                interval: templateNote.interval,
                noteType: templateNote.noteType,
                measureNumber: templateNote.measureNumber,
                measureOffset: templateNote.measureOffset,
                chart: chart,
                originKind: templateNote.originKind,
                sourceLaneID: templateNote.sourceLaneID,
                sourceNoteID: templateNote.sourceNoteID,
                sourceGridPosition: templateNote.sourceGridPosition,
                sourceGridSize: templateNote.sourceGridSize,
                normalizedMeasureIndex: templateNote.normalizedMeasureIndex,
                normalizedAbsoluteTick: templateNote.normalizedAbsoluteTick,
                normalizedTickWithinMeasure: templateNote.normalizedTickWithinMeasure,
                normalizedTicksPerMeasure: templateNote.normalizedTicksPerMeasure,
                notationVoiceCandidate: templateNote.notationVoiceCandidate,
                visualDurationCandidate: templateNote.visualDurationCandidate,
                articulationCandidate: templateNote.articulationCandidate
            )
        }
    }

    private static func copiedControlEvents(from templateChart: Chart, into chart: Chart) -> [ChartControlEvent] {
        templateChart.safeControlEvents.map { templateControl in
            ChartControlEvent(
                kind: templateControl.kind,
                measureNumber: templateControl.measureNumber,
                measureOffset: templateControl.measureOffset,
                chart: chart,
                originKind: templateControl.originKind,
                sourceLaneID: templateControl.sourceLaneID,
                sourceNoteID: templateControl.sourceNoteID,
                sourceGridPosition: templateControl.sourceGridPosition,
                sourceGridSize: templateControl.sourceGridSize,
                normalizedMeasureIndex: templateControl.normalizedMeasureIndex,
                normalizedAbsoluteTick: templateControl.normalizedAbsoluteTick,
                normalizedTickWithinMeasure: templateControl.normalizedTickWithinMeasure,
                normalizedTicksPerMeasure: templateControl.normalizedTicksPerMeasure,
                targetLaneID: templateControl.targetLaneID
            )
        }
    }

    private static func thunderBeatVerificationNotes(includeFills: Bool = false) -> [Note] {
        var notes: [Note] = []

        func add(_ interval: NoteInterval, _ noteType: NoteType, _ measureNumber: Int, _ measureOffset: Double) {
            notes.append(
                Note(
                    interval: interval,
                    noteType: noteType,
                    measureNumber: measureNumber,
                    measureOffset: measureOffset
                )
            )
        }

        for measureNumber in 1...4 {
            stride(from: 0.0, through: 0.875, by: 0.125).forEach {
                add(.eighth, .hiHat, measureNumber, $0)
            }
            add(.quarter, .bass, measureNumber, 0.0)
            add(.quarter, .snare, measureNumber, 0.5)
            add(.quarter, .bass, measureNumber, 0.75)
        }

        add(.quarter, .crash, 1, 0.0)

        if includeFills {
            add(.eighth, .highTom, 4, 0.625)
            add(.eighth, .midTom, 4, 0.75)
            add(.eighth, .lowTom, 4, 0.875)
        }

        return notes
    }
}

// MARK: - Legacy DrumTrack fixture

extension DrumTrack {
    static var sampleData: [DrumTrack] {
        Song.sampleData.flatMap { song in
            song.charts.map { chart in
                DrumTrack(chart: chart)
            }
        }
    }
}
