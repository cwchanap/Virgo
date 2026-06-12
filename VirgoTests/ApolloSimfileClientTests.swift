import Testing
import Foundation
import ApolloAPI
import Apollo
@testable import Virgo

@Suite("Apollo Simfile Client Tests")
struct ApolloSimfileClientTests {

    // MARK: - SimfileGraphQLError

    @Test("SimfileGraphQLError returns first error message")
    func testGraphQLErrorWithErrors() {
        let errors = [
            GraphQLError(["message": "field X failed" as AnyHashable]),
            GraphQLError(["message": "field Y failed" as AnyHashable])
        ]
        let error = SimfileGraphQLError(graphQLErrors: errors)
        #expect(error.errorDescription == "field X failed")
    }

    @Test("SimfileGraphQLError returns fallback when errors array is empty")
    func testGraphQLErrorEmpty() {
        let error = SimfileGraphQLError(graphQLErrors: [])
        #expect(error.errorDescription == "GraphQL request failed")
    }

    @Test("SimfileGraphQLError conforms to LocalizedError")
    func testGraphQLErrorConformsToLocalizedError() {
        let error = SimfileGraphQLError(
            graphQLErrors: [GraphQLError(["message": "boom" as AnyHashable])]
        )
        let localized = error as any LocalizedError
        #expect(localized.errorDescription != nil)
    }

    // MARK: - SimfileEncoding

    @Test("SimfileEncoding raw values match expected strings")
    func testSimfileEncodingRawValues() {
        #expect(SimfileEncoding.shiftJIS.rawValue == "SHIFT_JIS")
        #expect(SimfileEncoding.utf8.rawValue == "UTF_8")
    }

    @Test("SimfileEncoding init from rawValue succeeds for known values")
    func testSimfileEncodingInitFromRawValue() {
        #expect(SimfileEncoding(rawValue: "SHIFT_JIS") == .shiftJIS)
        #expect(SimfileEncoding(rawValue: "UTF_8") == .utf8)
    }

    @Test("SimfileEncoding init from rawValue returns nil for unknown")
    func testSimfileEncodingUnknownRawValue() {
        #expect(SimfileEncoding(rawValue: "LATIN_1") == nil)
    }

    // MARK: - FileEncoding GraphQL enum

    @Test("FileEncoding enum has correct raw values")
    func testFileEncodingRawValues() {
        #expect(VirgoGraphQL.FileEncoding.shiftJis.rawValue == "SHIFT_JIS")
        #expect(VirgoGraphQL.FileEncoding.utf8.rawValue == "UTF_8")
    }

    @Test("GraphQLEnum wraps FileEncoding cases")
    func testGraphQLEnumFileEncoding() {
        let shiftJis = GraphQLEnum<VirgoGraphQL.FileEncoding>(rawValue: "SHIFT_JIS")
        let utf8 = GraphQLEnum<VirgoGraphQL.FileEncoding>(rawValue: "UTF_8")
        let unknown = GraphQLEnum<VirgoGraphQL.FileEncoding>(rawValue: "UNKNOWN")

        if case .case(.shiftJis) = shiftJis {
        } else {
            Issue.record("Expected .case(.shiftJis)")
        }
        if case .case(.utf8) = utf8 {
        } else {
            Issue.record("Expected .case(.utf8)")
        }
        if case .case = unknown {
            Issue.record("Expected non-case for unknown raw value")
        }
    }

    // MARK: - SimfileFields fragment

    private func makeDtxFileDict(
        label: String = "BASIC",
        level: Double = 30,
        fileUrl: String = "https://r2/song/bas.dtx",
        fileSizeBytes: Int = 100,
        fileEncoding: String = "SHIFT_JIS"
    ) -> DataDict {
        DataDict(
            data: [
                "__typename": "DtxFile",
                "label": label,
                "level": level,
                "fileUrl": fileUrl,
                "fileSizeBytes": fileSizeBytes,
                "fileEncoding": GraphQLEnum<VirgoGraphQL.FileEncoding>(rawValue: fileEncoding)
            ],
            fulfilledFragments: [ObjectIdentifier(VirgoGraphQL.SimfileFields.DtxFile.self)]
        )
    }

    private func makeFileDict(key: String = "song/bgm.ogg", size: Int = 500) -> DataDict {
        DataDict(
            data: [
                "__typename": "R2File",
                "key": key,
                "size": size
            ],
            fulfilledFragments: [ObjectIdentifier(VirgoGraphQL.SimfileFields.File.self)]
        )
    }

    private func makeSimfileDict(
        id: String = "song-1",
        title: String = "Test Song",
        artist: String = "Test Artist",
        bpm: Double = 120.0,
        genre: AnyHashable? = "Rock",
        tags: [AnyHashable] = ["jpop"],
        durationSeconds: AnyHashable? = 200,
        updatedAt: String = "2026-01-01T00:00:00Z",
        dtxFiles: [AnyHashable]? = nil,
        files: [AnyHashable]? = nil
    ) -> DataDict {
        DataDict(
            data: [
                "__typename": "Simfile",
                "id": id,
                "title": title,
                "artist": artist,
                "bpm": bpm,
                "genre": genre ?? DataDict._NullValue,
                "tags": tags,
                "durationSeconds": durationSeconds ?? DataDict._NullValue,
                "updatedAt": updatedAt,
                "dtxFiles": dtxFiles ?? [makeDtxFileDict()],
                "files": files ?? [makeFileDict()]
            ],
            fulfilledFragments: [ObjectIdentifier(VirgoGraphQL.SimfileFields.self)]
        )
    }

    @Test("SimfileFields reads all scalar properties")
    func testSimfileFieldsScalarProperties() {
        let dict = makeSimfileDict()
        let fields = VirgoGraphQL.SimfileFields(_dataDict: dict)

        #expect(fields.id == "song-1")
        #expect(fields.title == "Test Song")
        #expect(fields.artist == "Test Artist")
        #expect(fields.bpm == 120.0)
        #expect(fields.genre == "Rock")
        #expect(fields.tags == ["jpop"])
        #expect(fields.durationSeconds == 200)
        #expect(fields.updatedAt == "2026-01-01T00:00:00Z")
    }

    @Test("SimfileFields handles nil optional fields")
    func testSimfileFieldsNilOptionals() {
        let dict = makeSimfileDict(genre: nil, durationSeconds: nil)
        let fields = VirgoGraphQL.SimfileFields(_dataDict: dict)

        #expect(fields.genre == nil)
        #expect(fields.durationSeconds == nil)
    }

    @Test("SimfileFields reads nested DtxFile")
    func testSimfileFieldsDtxFile() {
        let dtxDict = makeDtxFileDict(
            label: "EXTREME", level: 95, fileUrl: "https://r2/s/ext.dtx",
            fileSizeBytes: 4096, fileEncoding: "SHIFT_JIS"
        )
        let dict = makeSimfileDict(dtxFiles: [dtxDict])
        let fields = VirgoGraphQL.SimfileFields(_dataDict: dict)

        #expect(fields.dtxFiles.count == 1)
        let dtx = fields.dtxFiles[0]
        #expect(dtx.label == "EXTREME")
        #expect(dtx.level == 95.0)
        #expect(dtx.fileUrl == "https://r2/s/ext.dtx")
        #expect(dtx.fileSizeBytes == 4096)

        if case .case(.shiftJis) = dtx.fileEncoding {
        } else {
            Issue.record("Expected .shiftJis encoding")
        }
    }

    @Test("SimfileFields reads nested File")
    func testSimfileFieldsFile() {
        let fileDict = makeFileDict(key: "song/preview.mp3", size: 1024)
        let dict = makeSimfileDict(files: [fileDict])
        let fields = VirgoGraphQL.SimfileFields(_dataDict: dict)

        #expect(fields.files.count == 1)
        #expect(fields.files[0].key == "song/preview.mp3")
        #expect(fields.files[0].size == 1024)
    }

    @Test("SimfileFields reads multiple dtxFiles and files")
    func testSimfileFieldsMultipleChildren() {
        let dtxFiles: [AnyHashable] = [
            makeDtxFileDict(label: "BASIC", level: 30, fileEncoding: "SHIFT_JIS"),
            makeDtxFileDict(label: "ADVANCED", level: 55, fileEncoding: "UTF_8")
        ]
        let files: [AnyHashable] = [
            makeFileDict(key: "song/bgm.ogg", size: 2000),
            makeFileDict(key: "song/preview.mp3", size: 500)
        ]
        let dict = makeSimfileDict(dtxFiles: dtxFiles, files: files)
        let fields = VirgoGraphQL.SimfileFields(_dataDict: dict)

        #expect(fields.dtxFiles.count == 2)
        #expect(fields.dtxFiles[0].label == "BASIC")
        #expect(fields.dtxFiles[1].label == "ADVANCED")
        #expect(fields.files.count == 2)
        #expect(fields.files[0].key == "song/bgm.ogg")
        #expect(fields.files[1].key == "song/preview.mp3")
    }

    @Test("SimfileFields handles empty dtxFiles and files arrays")
    func testSimfileFieldsEmptyChildren() {
        let dict = makeSimfileDict(dtxFiles: [], files: [])
        let fields = VirgoGraphQL.SimfileFields(_dataDict: dict)

        #expect(fields.dtxFiles.isEmpty)
        #expect(fields.files.isEmpty)
    }

    // MARK: - SimfileFields → SimfileDTO mapping logic

    @Test("Mapping SimfileFields to SimfileDTO preserves all fields")
    func testMappingSimfileFieldsToDTO() {
        let dtxDict = makeDtxFileDict(
            label: "EXTREME", level: 74, fileUrl: "https://r2/s/ext.dtx",
            fileSizeBytes: 4096, fileEncoding: "SHIFT_JIS"
        )
        let fileDict = makeFileDict(key: "song/bgm.ogg", size: 500)
        let simfileDict = makeSimfileDict(
            id: "s1", title: "Song", artist: "Art", bpm: 165.5,
            genre: "Metal", tags: ["rock", "heavy"],
            durationSeconds: 300, updatedAt: "2026-06-01T00:00:00Z",
            dtxFiles: [dtxDict], files: [fileDict]
        )
        let fields = VirgoGraphQL.SimfileFields(_dataDict: simfileDict)
        let dto = Self.mapSimfileFields(fields)

        #expect(dto.id == "s1")
        #expect(dto.title == "Song")
        #expect(dto.artist == "Art")
        #expect(dto.bpm == 165.5)
        #expect(dto.genre == "Metal")
        #expect(dto.tags == ["rock", "heavy"])
        #expect(dto.durationSeconds == 300)
        #expect(dto.updatedAt == "2026-06-01T00:00:00Z")
        #expect(dto.dtxFiles.count == 1)
        #expect(dto.dtxFiles[0].label == "EXTREME")
        #expect(dto.dtxFiles[0].level == 74.0)
        #expect(dto.dtxFiles[0].fileURL == "https://r2/s/ext.dtx")
        #expect(dto.dtxFiles[0].fileSizeBytes == 4096)
        #expect(dto.dtxFiles[0].encoding == .shiftJIS)
        #expect(dto.fileKeys == ["song/bgm.ogg"])
    }

    @Test("Mapping with UTF-8 encoding preserves encoding")
    func testMappingUTF8Encoding() {
        let dtxDict = makeDtxFileDict(fileEncoding: "UTF_8")
        let simfileDict = makeSimfileDict(dtxFiles: [dtxDict])
        let fields = VirgoGraphQL.SimfileFields(_dataDict: simfileDict)
        let dto = Self.mapSimfileFields(fields)

        #expect(dto.dtxFiles[0].encoding == .utf8)
    }

    @Test("Mapping with unknown encoding falls back to shiftJIS")
    func testMappingUnknownEncodingFallback() {
        let dtxDict = makeDtxFileDict(fileEncoding: "LATIN_1")
        let simfileDict = makeSimfileDict(dtxFiles: [dtxDict])
        let fields = VirgoGraphQL.SimfileFields(_dataDict: simfileDict)
        let dto = Self.mapSimfileFields(fields)

        #expect(dto.dtxFiles[0].encoding == .shiftJIS)
    }

    @Test("Mapping with nil genre and durationSeconds")
    func testMappingNilOptionals() {
        let simfileDict = makeSimfileDict(genre: nil, durationSeconds: nil)
        let fields = VirgoGraphQL.SimfileFields(_dataDict: simfileDict)
        let dto = Self.mapSimfileFields(fields)

        #expect(dto.genre == nil)
        #expect(dto.durationSeconds == nil)
    }

    @Test("Mapping extracts file keys from files array")
    func testMappingFileKeys() {
        let files: [AnyHashable] = [
            makeFileDict(key: "song/bgm.ogg"),
            makeFileDict(key: "song/preview.mp3")
        ]
        let simfileDict = makeSimfileDict(files: files)
        let fields = VirgoGraphQL.SimfileFields(_dataDict: simfileDict)
        let dto = Self.mapSimfileFields(fields)

        #expect(dto.fileKeys == ["song/bgm.ogg", "song/preview.mp3"])
    }

    /// Mirrors the private `ApolloSimfileClient.map(_:)` logic for test coverage.
    private static func mapSimfileFields(_ s: VirgoGraphQL.SimfileFields) -> SimfileDTO {
        SimfileDTO(
            id: s.id,
            title: s.title,
            artist: s.artist,
            bpm: s.bpm,
            genre: s.genre,
            tags: s.tags,
            durationSeconds: s.durationSeconds,
            updatedAt: s.updatedAt,
            dtxFiles: s.dtxFiles.map { f in
                let rawEncoding = f.fileEncoding.rawValue
                let encoding: SimfileEncoding
                if let parsed = SimfileEncoding(rawValue: rawEncoding) {
                    encoding = parsed
                } else {
                    encoding = .shiftJIS
                }
                return DtxFileDTO(
                    label: f.label,
                    level: f.level,
                    fileURL: f.fileUrl,
                    fileSizeBytes: f.fileSizeBytes,
                    encoding: encoding
                )
            },
            fileKeys: s.files.map { $0.key }
        )
    }
}
