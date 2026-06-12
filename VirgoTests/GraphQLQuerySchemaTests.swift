import Testing
import Foundation
import ApolloAPI
import Apollo
@testable import Virgo

@Suite("GraphQL Query & Schema Tests")
struct GraphQLQuerySchemaTests {

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

    // MARK: - SimfilesQuery

    @Test("SimfilesQuery stores variables correctly with null search")
    func testSimfilesQueryVariablesNullSearch() {
        let query = VirgoGraphQL.SimfilesQuery(page: 1, pageSize: 10, search: .null)

        #expect(query.page == 1)
        #expect(query.pageSize == 10)
        #expect(query.search == .null)

        let vars = query.__variables
        #expect(vars?["page"] as? Int == 1)
        #expect(vars?["pageSize"] as? Int == 10)
    }

    @Test("SimfilesQuery stores variables correctly with search string")
    func testSimfilesQueryVariablesWithSearch() {
        let query = VirgoGraphQL.SimfilesQuery(page: 2, pageSize: 20, search: .some("drums"))

        #expect(query.page == 2)
        #expect(query.pageSize == 20)

        if case .some(let value) = query.search {
            #expect(value == "drums")
        } else {
            Issue.record("Expected .some(\"drums\")")
        }
    }

    @Test("SimfilesQuery.Data parses simfile connection")
    func testSimfilesQueryData() {
        let dtxDict = makeDtxFileDict()
        let fileDict = makeFileDict()

        let datumDict = DataDict(
            data: [
                "__typename": "Simfile",
                "id": "song-1",
                "title": "Test",
                "artist": "Art",
                "bpm": 120.0,
                "genre": DataDict._NullValue,
                "tags": [] as [AnyHashable],
                "durationSeconds": DataDict._NullValue,
                "updatedAt": "2026-01-01T00:00:00Z",
                "dtxFiles": [dtxDict] as [AnyHashable],
                "files": [fileDict] as [AnyHashable]
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfilesQuery.Data.Simfiles.Datum.self),
                ObjectIdentifier(VirgoGraphQL.SimfileFields.self)
            ]
        )

        let connectionDict = DataDict(
            data: [
                "__typename": "SimfileConnection",
                "count": 1,
                "data": [datumDict] as [AnyHashable]
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfilesQuery.Data.Simfiles.self)
            ]
        )

        let dataDict = DataDict(
            data: [
                "__typename": "Query",
                "simfiles": connectionDict
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfilesQuery.Data.self)
            ]
        )

        let data = VirgoGraphQL.SimfilesQuery.Data(_dataDict: dataDict)
        #expect(data.simfiles.count == 1)
        #expect(data.simfiles.data.count == 1)
        #expect(data.simfiles.data[0].id == "song-1")
        #expect(data.simfiles.data[0].title == "Test")
    }

    @Test("SimfilesQuery.Data handles empty results")
    func testSimfilesQueryDataEmpty() {
        let connectionDict = DataDict(
            data: [
                "__typename": "SimfileConnection",
                "count": 0,
                "data": [] as [AnyHashable]
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfilesQuery.Data.Simfiles.self)
            ]
        )

        let dataDict = DataDict(
            data: [
                "__typename": "Query",
                "simfiles": connectionDict
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfilesQuery.Data.self)
            ]
        )

        let data = VirgoGraphQL.SimfilesQuery.Data(_dataDict: dataDict)
        #expect(data.simfiles.data.isEmpty)
    }

    // MARK: - SimfileQuery

    @Test("SimfileQuery stores id variable")
    func testSimfileQueryVariables() {
        let query = VirgoGraphQL.SimfileQuery(id: "abc-123")
        #expect(query.id == "abc-123")
        #expect(query.__variables?["id"] as? String == "abc-123")
    }

    @Test("SimfileQuery.Data parses simfile when present")
    func testSimfileQueryDataPresent() {
        let dtxDict = makeDtxFileDict()
        let fileDict = makeFileDict()

        let simfileDict = DataDict(
            data: [
                "__typename": "Simfile",
                "id": "song-42",
                "title": "Found",
                "artist": "Band",
                "bpm": 140.0,
                "genre": "Pop" as AnyHashable,
                "tags": ["fun"] as [AnyHashable],
                "durationSeconds": 180 as AnyHashable,
                "updatedAt": "2026-03-15T00:00:00Z",
                "dtxFiles": [dtxDict] as [AnyHashable],
                "files": [fileDict] as [AnyHashable]
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfileQuery.Data.Simfile.self),
                ObjectIdentifier(VirgoGraphQL.SimfileFields.self)
            ]
        )

        let dataDict = DataDict(
            data: [
                "__typename": "Query",
                "simfile": simfileDict
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfileQuery.Data.self)
            ]
        )

        let data = VirgoGraphQL.SimfileQuery.Data(_dataDict: dataDict)
        #expect(data.simfile != nil)
        #expect(data.simfile?.id == "song-42")
        #expect(data.simfile?.title == "Found")
        #expect(data.simfile?.bpm == 140.0)
    }

    @Test("SimfileQuery.Data handles nil simfile")
    func testSimfileQueryDataNil() {
        let dataDict = DataDict(
            data: [
                "__typename": "Query",
                "simfile": DataDict._NullValue
            ],
            fulfilledFragments: [
                ObjectIdentifier(VirgoGraphQL.SimfileQuery.Data.self)
            ]
        )

        let data = VirgoGraphQL.SimfileQuery.Data(_dataDict: dataDict)
        #expect(data.simfile == nil)
    }

    // MARK: - SchemaMetadata

    @Test("SchemaMetadata resolves known typenames")
    func testSchemaMetadataKnownTypes() {
        #expect(VirgoGraphQL.SchemaMetadata.objectType(forTypename: "Simfile") != nil)
        #expect(VirgoGraphQL.SchemaMetadata.objectType(forTypename: "DtxFile") != nil)
        #expect(VirgoGraphQL.SchemaMetadata.objectType(forTypename: "Query") != nil)
        #expect(VirgoGraphQL.SchemaMetadata.objectType(forTypename: "R2File") != nil)
        #expect(VirgoGraphQL.SchemaMetadata.objectType(forTypename: "SimfileConnection") != nil)
    }

    @Test("SchemaMetadata returns nil for unknown typename")
    func testSchemaMetadataUnknownType() {
        #expect(VirgoGraphQL.SchemaMetadata.objectType(forTypename: "Unknown") == nil)
        #expect(VirgoGraphQL.SchemaMetadata.objectType(forTypename: "NotExist") == nil)
    }

    // MARK: - SchemaConfiguration

    @Test("SchemaConfiguration cacheKeyInfo returns nil by default")
    func testSchemaConfigurationCacheKeyInfo() {
        let transformer = TestObjectDataTransformer()
        let objectData = ObjectData(_transformer: transformer, _rawData: [:])
        let result = SchemaConfiguration.cacheKeyInfo(
            for: VirgoGraphQL.Objects.Simfile,
            object: objectData
        )
        #expect(result == nil)
    }

    // MARK: - Objects typenames

    @Test("Objects have correct typenames")
    func testObjectTypenames() {
        #expect(VirgoGraphQL.Objects.Simfile.typename == "Simfile")
        #expect(VirgoGraphQL.Objects.DtxFile.typename == "DtxFile")
        #expect(VirgoGraphQL.Objects.Query.typename == "Query")
        #expect(VirgoGraphQL.Objects.R2File.typename == "R2File")
        #expect(VirgoGraphQL.Objects.SimfileConnection.typename == "SimfileConnection")
    }

    // MARK: - DTO value types

    @Test("SimfileDTO equality works")
    func testSimfileDTOEquality() {
        let dto1 = SimfileDTO(
            id: "1", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
            durationSeconds: nil, updatedAt: "2026-01-01T00:00:00Z",
            dtxFiles: [], fileKeys: []
        )
        let dto2 = SimfileDTO(
            id: "1", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
            durationSeconds: nil, updatedAt: "2026-01-01T00:00:00Z",
            dtxFiles: [], fileKeys: []
        )
        #expect(dto1 == dto2)
    }

    @Test("SimfilePage equality works")
    func testSimfilePageEquality() {
        let page1 = SimfilePage(simfiles: [], totalCount: 0)
        let page2 = SimfilePage(simfiles: [], totalCount: 0)
        #expect(page1 == page2)
    }

    @Test("DtxFileDTO equality works")
    func testDtxFileDTOEquality() {
        let d1 = DtxFileDTO(label: "B", level: 1, fileURL: "u", fileSizeBytes: 10, encoding: .shiftJIS)
        let d2 = DtxFileDTO(label: "B", level: 1, fileURL: "u", fileSizeBytes: 10, encoding: .shiftJIS)
        #expect(d1 == d2)
    }
}

private struct TestObjectDataTransformer: _ObjectData_Transformer {
    func transform(_ value: AnyHashable) -> (any ScalarType)? { nil }
    func transform(_ value: AnyHashable) -> ObjectData? { nil }
    func transform(_ value: AnyHashable) -> ListData? { nil }
}
