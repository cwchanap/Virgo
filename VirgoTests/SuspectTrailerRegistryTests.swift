import Foundation
import Testing

/// Consistency check between `# SUSPECT: HPA-<id>` trailers in golden files
/// and the hand-maintained `openSuspectTickets` set below.
///
/// `GoldenFile.regenerated` carries existing `#`-prefixed annotation lines
/// forward when a golden is re-recorded, and `GoldenFile.stripComments`
/// hides them from the golden diff. That pair is deliberate — it prevents
/// a regeneration from silently *deleting* a SUSPECT trailer.
///
/// What this suite checks: that the trailers present in the goldens and the
/// `openSuspectTickets` set agree. It catches the two operators getting out
/// of sync — a trailer added without an entry in the set, or an entry in the
/// set with no trailer pinning it.
///
/// What this suite does **not** check: whether a listed ticket is actually
/// still open in Linear. Both representations live in this branch and are
/// maintained by hand, so a ticket that is resolved in Linear but whose
/// trailer and registry entry are both left in place will pass both
/// directions of this check. Closing that gap requires validating against
/// Linear (a CI step or a checked-in status file from a Linear-sync step),
/// which is out of scope for this suite.
///
/// When a ticket is resolved:
/// 1. Re-record the affected golden(s).
/// 2. Delete the `# SUSPECT:` trailer from the golden file(s).
/// 3. Remove the id from `openSuspectTickets` below.
/// Steps 2 and 3 must happen together; this suite exists to flag it when
/// they do not.
@Suite("Suspect trailer registry", .serialized)
struct SuspectTrailerRegistryTests {
    /// Tickets pinned by a `# SUSPECT:` trailer in one or more golden files.
    /// Hand-maintained — kept in sync with the trailers by the tests below.
    /// When a ticket is resolved, remove it here AND delete the trailer from
    /// the golden(s) in the same change.
    private static let openSuspectTickets: Set<String> = [
        "HPA-145",
        "HPA-419"
    ]

    @Test("every SUSPECT trailer is listed in openSuspectTickets")
    func suspectTrailersReferenceOpenTickets() throws {
        let suspectIDs = try Self.suspectIDsInGoldens()
        #expect(!suspectIDs.isEmpty, Comment(rawValue: Self.noTrailersFoundMessage))
        let stale = suspectIDs.subtracting(Self.openSuspectTickets)
        #expect(stale.isEmpty, Comment(rawValue: Self.staleTrailerMessage(stale)))
    }

    @Test("every openSuspectTickets entry has at least one SUSPECT trailer")
    func openTicketsHaveTrailers() throws {
        let suspectIDs = try Self.suspectIDsInGoldens()
        let orphaned = Self.openSuspectTickets.subtracting(suspectIDs)
        #expect(orphaned.isEmpty, Comment(rawValue: Self.orphanedTicketMessage(orphaned)))
    }

    private static let noTrailersFoundMessage = """
    No `# SUSPECT:` trailers found in any golden. Either all pinned defects \
    are fixed (remove the openSuspectTickets entries and consider retiring \
    this test), or the trailer convention was lost.
    """

    private static func staleTrailerMessage(_ stale: Set<String>) -> String {
        """
        Goldens carry `# SUSPECT:` trailers for tickets not in \
        openSuspectTickets: \(stale.sorted()). Add the id to \
        openSuspectTickets, or, if the ticket was resolved, re-record the \
        golden and delete the trailer.
        """
    }

    private static func orphanedTicketMessage(_ orphaned: Set<String>) -> String {
        """
        openSuspectTickets lists \(orphaned.sorted()) but no golden carries \
        a `# SUSPECT:` trailer for them. Either the trailer was deleted \
        prematurely (re-add it), or the entry should be removed from \
        openSuspectTickets.
        """
    }

    /// Scans every `.txt` golden for `# SUSPECT: HPA-<id>` lines and returns
    /// the set of unique ticket ids. Uses `GoldenFile.directory` so the
    /// lookup stays in sync with the rest of the golden infrastructure.
    ///
    /// The regex anchors to `^`/`$` so a trailer cannot hide mid-line, and
    /// uses `[ \t]` rather than `\s` so the match cannot span newlines. Any
    /// line containing `# SUSPECT:` that does not conform to
    /// `# SUSPECT: HPA-<id>[ <description>]` is recorded as malformed.
    /// Captured ids are uppercased before insertion so case-insensitive
    /// matching cannot desync the set comparison against
    /// `openSuspectTickets`.
    private static func suspectIDsInGoldens() throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"^[ \t]*# SUSPECT:[ \t]+(HPA-\d+)(?:[ \t].*)?$"#,
            options: [.caseInsensitive]
        )
        var ids = Set<String>()
        var malformed: [String] = []
        let directory = GoldenFile.directory
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("Could not enumerate golden directory at \(directory.path)")
            return ids
        }
        for case let url as URL in enumerator where url.pathExtension == "txt" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine).trimmingCharacters(in: .init(charactersIn: "\r"))
                guard line.range(of: "# SUSPECT:", options: .caseInsensitive) != nil else { continue }
                let range = NSRange(line.startIndex..., in: line)
                if let match = pattern.firstMatch(in: line, range: range),
                   let idRange = Range(match.range(at: 1), in: line) {
                    ids.insert(line[idRange].uppercased())
                } else {
                    malformed.append("\(url.lastPathComponent): \(line)")
                }
            }
        }
        if !malformed.isEmpty {
            Issue.record("Malformed `# SUSPECT:` trailer(s):\n\(malformed.joined(separator: "\n"))")
        }
        return ids
    }
}
