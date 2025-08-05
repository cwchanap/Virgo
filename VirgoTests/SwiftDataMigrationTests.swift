//
//  SwiftDataMigrationTests.swift
//  VirgoTests
//
//  Created by Claude Code on 4/8/2025.
//

import Testing
import SwiftData
@testable import Virgo

@Suite("SwiftData Migration Tests")
struct SwiftDataMigrationTests {
    
    @Test("Migration plan contains required stages")
    func testMigrationPlanStages() {
        let v1toV2Stages = MigrateV1toV2.stages
        let v2toV21Stages = MigrateV2toV21.stages
        
        #expect(v1toV2Stages.count == 1)
        #expect(v2toV21Stages.count == 1)
        
        #expect(v1toV2Stages.first is MigrateV1toV2Stage.Type)
        #expect(v2toV21Stages.first is MigrateV2toV21Stage.Type)
    }
    
    @Test("Schema versions are properly defined")
    func testSchemaVersions() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(SchemaV21.versionIdentifier == Schema.Version(2, 1, 0))
    }
    
    @Test("Schema V1 contains basic models")
    func testSchemaV1Models() {
        let models = SchemaV1.models
        #expect(models.count == 3)
        
        let modelNames = models.map { String(describing: $0) }
        #expect(modelNames.contains("Song"))
        #expect(modelNames.contains("Chart"))
        #expect(modelNames.contains("Note"))
    }
    
    @Test("Schema V2 adds server models")
    func testSchemaV2Models() {
        let models = SchemaV2.models
        #expect(models.count == 5)
        
        let modelNames = models.map { String(describing: $0) }
        #expect(modelNames.contains("Song"))
        #expect(modelNames.contains("Chart"))
        #expect(modelNames.contains("Note"))
        #expect(modelNames.contains("ServerSong"))
        #expect(modelNames.contains("ServerChart"))
    }
    
    @Test("Schema V21 maintains all models")
    func testSchemaV21Models() {
        let models = SchemaV21.models
        #expect(models.count == 5)
        
        let modelNames = models.map { String(describing: $0) }
        #expect(modelNames.contains("Song"))
        #expect(modelNames.contains("Chart"))
        #expect(modelNames.contains("Note"))
        #expect(modelNames.contains("ServerSong"))
        #expect(modelNames.contains("ServerChart"))
    }
}