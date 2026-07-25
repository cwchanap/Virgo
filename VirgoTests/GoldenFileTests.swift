import Testing
import Foundation
@testable import Virgo

/// Covers `GoldenFile`'s mismatch/diff-report path directly, independent of any fixture.
/// Not exercised by `DrumTabGoldenTests`, whose golden always matches — this suite writes
/// its own probe golden and deliberately compares a mutated string against it so the
/// readable-diff branch (`GoldenFile.report`) actually runs at least once.
///
/// Skipped under golden regeneration: `assertMatches` takes the write branch under
/// `VIRGO_UPDATE_GOLDENS`/`TEST_RUNNER_VIRGO_UPDATE_GOLDENS`, not the mismatch branch this
/// test targets, and its "Golden rewritten" message doesn't contain the mismatch-report
/// substrings below. A regeneration run must end in pass-or-skip, never fail.
@Suite("Golden file mismatch reporting", .serialized)
struct GoldenFileTests {
    private static let fixture = "golden-file-mismatch-probe"
    private static let golden = "alpha\nbeta\ngamma\n"
    private static let mutated = "alpha\nBETA\ngamma\n"

    /// Minimal reference-type box so the `matching` predicate below can hand a value back to
    /// the caller without itself recording anything (see the warning on its use site).
    private final class CapturedReport: @unchecked Sendable {
        var text: String?
    }

    @Test(
        "assertMatches reports a readable diff when the golden differs",
        .disabled(
            if: GoldenFile.isUpdating,
            "golden regeneration takes the write branch, not the mismatch branch this test covers"
        )
    )
    func reportsReadableDiffOnMismatch() throws {
        let target = GoldenFile.url(for: Self.fixture)
        try FileManager.default.createDirectory(
            at: GoldenFile.directory,
            withIntermediateDirectories: true
        )
        try Self.golden.write(to: target, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: target) }

        let captured = CapturedReport()

        // `matching` MUST stay a pure predicate — no #expect/#require inside it. A failing
        // expectation recorded from within `matching`'s call stack re-invokes `matching` on
        // the issue it just recorded, which can fail again and record again: unbounded
        // recursion between this closure and the Testing framework's issue-interception
        // machinery, which crashes the test host with a stack overflow rather than failing
        // the test. Capture the text here and assert on it only after `withKnownIssue`
        // returns, below.
        try withKnownIssue("golden intentionally mismatched to pin the diff-report format") {
            try GoldenFile.assertMatches(Self.mutated, fixture: Self.fixture)
        } matching: { issue in
            captured.text = issue.comments.map(\.rawValue).joined(separator: "\n")
            return true
        }

        let report = try #require(captured.text)
        #expect(report.contains("Golden mismatch for \"\(Self.fixture)\""))
        #expect(report.contains("1 differing line(s); first at 2, last at 2"))
        #expect(report.contains("1   alpha"))
        #expect(report.contains("2 - beta"))
        #expect(report.contains("2 + BETA"))
        #expect(report.contains("TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1"))
        #expect(report.contains("VIRGO_UPDATE_GOLDENS=1"))
    }
}
