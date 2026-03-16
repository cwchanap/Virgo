//
//  DTXServerTypesTests.swift
//  VirgoTests
//
//  Unit tests for the non-Codable DTX server-side types:
//  DTXServerFile, DTXServerSongData, DTXServerChartData,
//  DTXChartMetadata, and DTXServerMetadata.
//
//  These are plain Swift structs used as intermediate data containers
//  when mapping server responses to local models.
//

import Testing
@testable import Virgo

@Suite("DTXServerFile Tests")
struct DTXServerFileTests {

    @Test("DTXServerFile stores filename and size")
    func testInitialization() {
        let file = DTXServerFile(filename: "song.dtx", size: 8192)
        #expect(file.filename == "song.dtx")
        #expect(file.size == 8192)
    }

    @Test("DTXServerFile with zero size is valid")
    func testZeroSize() {
        let file = DTXServerFile(filename: "empty.dtx", size: 0)
        #expect(file.size == 0)
        #expect(file.filename == "empty.dtx")
    }

    @Test("DTXServerFile with large size stores correctly")
    func testLargeSize() {
        let file = DTXServerFile(filename: "large.dtx", size: Int.max)
        #expect(file.size == Int.max)
    }

    @Test("DTXServerFile with empty filename is valid")
    func testEmptyFilename() {
        let file = DTXServerFile(filename: "", size: 100)
        #expect(file.filename == "")
    }

    @Test("DTXServerFile with special characters in filename")
    func testSpecialCharactersInFilename() {
        let file = DTXServerFile(filename: "ドラム曲.dtx", size: 512)
        #expect(file.filename == "ドラム曲.dtx")
        #expect(file.size == 512)
    }
}

@Suite("DTXChartMetadata Tests")
struct DTXChartMetadataTests {

    @Test("DTXChartMetadata stores all optional properties")
    func testFullInitialization() {
        let meta = DTXChartMetadata(
            title: "Hard Track",
            artist: "Metal Band",
            bpm: 180.0,
            level: 85
        )
        #expect(meta.title == "Hard Track")
        #expect(meta.artist == "Metal Band")
        #expect(meta.bpm == 180.0)
        #expect(meta.level == 85)
    }

    @Test("DTXChartMetadata allows all nil optionals")
    func testAllNilOptionals() {
        let meta = DTXChartMetadata(title: nil, artist: nil, bpm: nil, level: nil)
        #expect(meta.title == nil)
        #expect(meta.artist == nil)
        #expect(meta.bpm == nil)
        #expect(meta.level == nil)
    }

    @Test("DTXChartMetadata allows mixed nil and non-nil values")
    func testMixedNilValues() {
        let meta = DTXChartMetadata(title: "Only Title", artist: nil, bpm: 120.0, level: nil)
        #expect(meta.title == "Only Title")
        #expect(meta.artist == nil)
        #expect(meta.bpm == 120.0)
        #expect(meta.level == nil)
    }

    @Test("DTXChartMetadata level can be 0")
    func testZeroLevel() {
        let meta = DTXChartMetadata(title: nil, artist: nil, bpm: nil, level: 0)
        #expect(meta.level == 0)
    }

    @Test("DTXChartMetadata bpm can be fractional")
    func testFractionalBPM() {
        let meta = DTXChartMetadata(title: nil, artist: nil, bpm: 128.5, level: nil)
        #expect(meta.bpm == 128.5)
    }
}

@Suite("DTXServerChartData Tests")
struct DTXServerChartDataTests {

    @Test("DTXServerChartData stores all required properties")
    func testFullInitialization() {
        let meta = DTXChartMetadata(title: "T", artist: "A", bpm: 140.0, level: 70)
        let chartData = DTXServerChartData(
            difficulty: "hard",
            difficultyLabel: "EXTREME",
            level: 74,
            filename: "ext.dtx",
            size: 2048,
            metadata: meta
        )
        #expect(chartData.difficulty == "hard")
        #expect(chartData.difficultyLabel == "EXTREME")
        #expect(chartData.level == 74)
        #expect(chartData.filename == "ext.dtx")
        #expect(chartData.size == 2048)
        #expect(chartData.metadata?.title == "T")
    }

    @Test("DTXServerChartData allows nil metadata")
    func testNilMetadata() {
        let chartData = DTXServerChartData(
            difficulty: "easy",
            difficultyLabel: "BASIC",
            level: 30,
            filename: "bas.dtx",
            size: 512,
            metadata: nil
        )
        #expect(chartData.metadata == nil)
        #expect(chartData.difficulty == "easy")
    }

    @Test("DTXServerChartData with level 0 is valid")
    func testZeroLevel() {
        let chartData = DTXServerChartData(
            difficulty: "easy",
            difficultyLabel: "BASIC",
            level: 0,
            filename: "test.dtx",
            size: 100,
            metadata: nil
        )
        #expect(chartData.level == 0)
    }

    @Test("DTXServerChartData difficulty strings are stored verbatim")
    func testDifficultyStringsVerbatim() {
        let difficulties = ["easy", "medium", "hard", "expert", "master", "CUSTOM"]
        for diff in difficulties {
            let data = DTXServerChartData(
                difficulty: diff,
                difficultyLabel: diff.uppercased(),
                level: 50,
                filename: "f.dtx",
                size: 1,
                metadata: nil
            )
            #expect(data.difficulty == diff)
            #expect(data.difficultyLabel == diff.uppercased())
        }
    }
}

@Suite("DTXServerSongData Tests")
struct DTXServerSongDataTests {

    private func makeChart(_ diff: String = "easy") -> DTXServerChartData {
        DTXServerChartData(
            difficulty: diff, difficultyLabel: diff.uppercased(),
            level: 30, filename: "f.dtx", size: 100, metadata: nil
        )
    }

    @Test("DTXServerSongData stores all required properties")
    func testFullInitialization() {
        let charts = [makeChart("easy"), makeChart("hard")]
        let song = DTXServerSongData(
            songId: "song-001",
            title: "Test Song",
            artist: "Test Artist",
            bpm: 140.0,
            charts: charts
        )
        #expect(song.songId == "song-001")
        #expect(song.title == "Test Song")
        #expect(song.artist == "Test Artist")
        #expect(song.bpm == 140.0)
        #expect(song.charts.count == 2)
    }

    @Test("DTXServerSongData with nil optional fields")
    func testNilOptionalFields() {
        let song = DTXServerSongData(
            songId: "min",
            title: "Minimal",
            artist: nil,
            bpm: nil,
            charts: []
        )
        #expect(song.artist == nil)
        #expect(song.bpm == nil)
        #expect(song.charts.isEmpty)
    }

    @Test("DTXServerSongData with empty charts array")
    func testEmptyCharts() {
        let song = DTXServerSongData(
            songId: "no-charts",
            title: "No Charts",
            artist: nil,
            bpm: 120.0,
            charts: []
        )
        #expect(song.charts.isEmpty)
    }

    @Test("DTXServerSongData charts are accessible by index")
    func testChartAccess() {
        let easy = makeChart("easy")
        let hard = makeChart("hard")
        let song = DTXServerSongData(
            songId: "s",
            title: "T",
            artist: nil,
            bpm: nil,
            charts: [easy, hard]
        )
        #expect(song.charts[0].difficulty == "easy")
        #expect(song.charts[1].difficulty == "hard")
    }

    @Test("DTXServerSongData bpm can be fractional")
    func testFractionalBPM() {
        let song = DTXServerSongData(
            songId: "s",
            title: "T",
            artist: nil,
            bpm: 128.5,
            charts: []
        )
        #expect(song.bpm == 128.5)
    }
}

@Suite("DTXServerMetadata Tests")
struct DTXServerMetadataTests {

    @Test("DTXServerMetadata stores all properties")
    func testFullInitialization() {
        let meta = DTXServerMetadata(
            filename: "track.dtx",
            title: "Track Title",
            artist: "Track Artist",
            bpm: 150.0,
            level: 80
        )
        #expect(meta.filename == "track.dtx")
        #expect(meta.title == "Track Title")
        #expect(meta.artist == "Track Artist")
        #expect(meta.bpm == 150.0)
        #expect(meta.level == 80)
    }

    @Test("DTXServerMetadata allows nil optional fields")
    func testNilOptionals() {
        let meta = DTXServerMetadata(
            filename: "nodata.dtx",
            title: nil,
            artist: nil,
            bpm: nil,
            level: nil
        )
        #expect(meta.filename == "nodata.dtx")
        #expect(meta.title == nil)
        #expect(meta.artist == nil)
        #expect(meta.bpm == nil)
        #expect(meta.level == nil)
    }

    @Test("DTXServerMetadata filename is always non-optional")
    func testFilenameAlwaysPresent() {
        let filenames = ["song.dtx", "", "path/to/file.dtx", "曲.dtx"]
        for name in filenames {
            let meta = DTXServerMetadata(filename: name, title: nil, artist: nil, bpm: nil, level: nil)
            #expect(meta.filename == name)
        }
    }

    @Test("DTXServerMetadata bpm can represent any positive tempo")
    func testBPMValues() {
        let bpmValues: [Double] = [20.0, 60.0, 120.0, 200.0, 300.0, 600.0]
        for bpm in bpmValues {
            let meta = DTXServerMetadata(filename: "f.dtx", title: nil, artist: nil, bpm: bpm, level: nil)
            #expect(meta.bpm == bpm)
        }
    }
}
