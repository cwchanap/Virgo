//
//  RhythmMetadataPersistenceTests.swift
//  VirgoTests
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Rhythm metadata persistence", .serialized)
@MainActor
struct RhythmMetadataPersistenceTests {
    @Test("on-disk charts retain missing, valid, corrupt, and unsupported metadata states")
    func onDiskTriStatePersistence() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("rhythm-metadata.sqlite")
        let validMetadata = try ChartRhythmMetadata(
            version: 1,
            timeSignature: .fourFour,
            feel: .straight,
            measureLengthOverrides: [],
            bgmStartAnchor: nil,
            timingStatus: .valid,
            diagnostics: []
        )

        do {
            let container = try TestModelContainerFactory.makePersistentContainer(at: storeURL)
            let context = container.mainContext
            let missing = Chart(difficulty: .easy)
            let valid = Chart(difficulty: .medium)
            let corrupt = Chart(difficulty: .hard)
            let unsupported = Chart(difficulty: .expert)
            try valid.setRhythmMetadata(validMetadata)
            corrupt.rhythmMetadataData = Data("corrupt".utf8)
            unsupported.rhythmMetadataData = unsupportedVersionData()

            [missing, valid, corrupt, unsupported].forEach(context.insert)
            try context.save()
        }

        let reopened = try TestModelContainerFactory.makePersistentContainer(at: storeURL)
        let charts = try reopened.mainContext.fetch(FetchDescriptor<Chart>())
        let byDifficulty = Dictionary(uniqueKeysWithValues: charts.map { ($0.difficulty, $0) })

        #expect(byDifficulty[.easy]?.rhythmMetadataState == .missing)
        #expect(byDifficulty[.medium]?.rhythmMetadataState == .valid(validMetadata))
        #expect(byDifficulty[.hard]?.rhythmMetadataState == .invalid(.inconsistentPersistedTiming))
        #expect(byDifficulty[.expert]?.rhythmMetadataState == .invalid(.unsupportedMetadataVersion))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-rhythm-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func unsupportedVersionData() -> Data {
        Data(
            """
            {"version":2,"timeSignature":"4/4","feel":"straight","measureLengthOverrides":[],
            "timingStatus":"valid","diagnostics":[]}
            """.utf8
        )
    }
}
