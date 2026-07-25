import Testing
import Foundation
@testable import Virgo

/// Covers `GoldenFile`'s mismatch/diff-report path directly, independent of any fixture.
/// Not exercised by `DrumTabGoldenTests`, whose golden always matches — this suite writes
/// its own probe golden and deliberately compares a mutated string against it so the
/// readable-diff branch (`GoldenFile.report`) actually runs at least once.
@Suite("Golden file mismatch reporting", .serialized)
struct GoldenFileTests {
    private static let fixture = "golden-file-mismatch-probe"
    private static let golden = "alpha\nbeta\ngamma\n"
    private static let mutated = "alpha\nBETA\ngamma\n"

    @Test("assertMatches reports a readable diff when the golden differs")
    func reportsReadableDiffOnMismatch() throws {
        let target = GoldenFile.url(for: Self.fixture)
        try FileManager.default.createDirectory(
            at: GoldenFile.directory,
            withIntermediateDirectories: true
        )
        try Self.golden.write(to: target, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: target) }

        try withKnownIssue("golden intentionally mismatched to pin the diff-report format") {
            try GoldenFile.assertMatches(Self.mutated, fixture: Self.fixture)
        } matching: { issue in
            let report = issue.comments.map(\.rawValue).joined(separator: "\n")
            #expect(report.contains("Golden mismatch for \"\(Self.fixture)\""))
            #expect(report.contains("1 differing line(s); first at 2, last at 2"))
            #expect(report.contains("1   alpha"))
            #expect(report.contains("2 - beta"))
            #expect(report.contains("2 + BETA"))
            #expect(report.contains("TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1"))
            #expect(report.contains("VIRGO_UPDATE_GOLDENS=1"))
            return true
        }
    }
}
