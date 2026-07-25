import Foundation
import Testing

/// Loads, compares, and optionally regenerates golden digest files.
enum GoldenFile {
    /// Goldens live next to the test sources, located relative to this file so
    /// no Xcode resource bundling is needed.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens", isDirectory: true)
    }

    static func url(for fixture: String) -> URL {
        directory.appendingPathComponent("\(fixture).txt")
    }

    /// The working invocation, spelled out once so both user-facing messages below (and
    /// anyone reading them) get instructions that actually reach the test host. Plain
    /// `VIRGO_UPDATE_GOLDENS=1 xcodebuild test …` does not: xcodebuild does not forward
    /// bare shell variables into the process it spawns for the test bundle.
    private static let updateInstructions = """
    Via `xcodebuild test`, set TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1 (xcodebuild only \
    forwards TEST_RUNNER_-prefixed variables into the test host). Via an Xcode scheme's \
    test-action environment variables, the bare VIRGO_UPDATE_GOLDENS=1 works directly.
    """

    /// `xcodebuild test` only forwards `TEST_RUNNER_`-prefixed variables into the spawned
    /// test host (stripping the prefix before exec); an Xcode scheme's test-action
    /// environment injects the bare key directly. Both spellings are accepted so either
    /// invocation style works.
    static var isUpdating: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["VIRGO_UPDATE_GOLDENS"] == "1"
            || environment["TEST_RUNNER_VIRGO_UPDATE_GOLDENS"] == "1"
    }

    static func assertMatches(
        _ actual: String,
        fixture: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let target = url(for: fixture)

        if isUpdating {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try actual.write(to: target, atomically: true, encoding: .utf8)
            Issue.record(
                """
                Golden rewritten (VIRGO_UPDATE_GOLDENS=1): \(target.path)
                Review the diff with `git diff` before committing. This test \
                fails by design so a regeneration run can never be mistaken \
                for a passing run.
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        guard FileManager.default.fileExists(atPath: target.path) else {
            Issue.record(
                """
                Missing golden for "\(fixture)" at \(target.path).
                Create it by running this suite with the update flag set. \(updateInstructions)
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        let expected = try String(contentsOf: target, encoding: .utf8)
        guard actual != expected else { return }
        Issue.record(
            Comment(rawValue: report(actual: actual, expected: expected, fixture: fixture, path: target.path)),
            sourceLocation: sourceLocation
        )
    }

    /// Reports differing-line count, first/last divergence, and a capped
    /// unified-style diff. A boolean mismatch on a several-hundred-line string
    /// is undiagnosable, and these digests are long by design.
    private static func report(
        actual: String,
        expected: String,
        fixture: String,
        path: String
    ) -> String {
        let actualLines = actual.components(separatedBy: "\n")
        let expectedLines = expected.components(separatedBy: "\n")
        let maxCount = max(actualLines.count, expectedLines.count)

        var differing: [Int] = []
        for index in 0..<maxCount
        where actualLines[safeIndex: index] != expectedLines[safeIndex: index] {
            differing.append(index)
        }

        var out = ["Golden mismatch for \"\(fixture)\" (\(path))"]
        if actualLines.count != expectedLines.count {
            out.append(
                "Line count differs: expected \(expectedLines.count), actual \(actualLines.count) "
                + "(a missing line and a moved line are different bugs)"
            )
        }
        out.append(
            "\(differing.count) differing line(s); first at \(differing.first.map { $0 + 1 } ?? 0), "
            + "last at \(differing.last.map { $0 + 1 } ?? 0)"
        )

        let cap = 40
        var emitted = 0
        for index in differing {
            if emitted >= cap {
                out.append("… and \(differing.count - cap) more differing line(s)")
                break
            }
            for context in max(0, index - 2)..<index
            where expectedLines[safeIndex: context] != nil {
                out.append("  \(context + 1)   \(expectedLines[safeIndex: context] ?? "")")
            }
            out.append("  \(index + 1) - \(expectedLines[safeIndex: index] ?? "<absent>")")
            out.append("  \(index + 1) + \(actualLines[safeIndex: index] ?? "<absent>")")
            emitted += 1
        }
        out.append("Regenerate: \(updateInstructions) Then inspect `git diff`.")
        return out.joined(separator: "\n")
    }
}

private extension Array where Element == String {
    subscript(safeIndex index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}
