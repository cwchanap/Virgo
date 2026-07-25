import Testing
import Foundation
@testable import Virgo

@Suite("Drum tab golden digests", .serialized)
@MainActor
struct DrumTabGoldenTests {
    @Test("same-time-trio matches its golden digest")
    func sameTimeTrio() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sameTimeTrio)
        #expect(result.layout.noteHeads.count == 6)
        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: DrumTabFixtureCatalog.sameTimeTrio.name
        )
    }
}
