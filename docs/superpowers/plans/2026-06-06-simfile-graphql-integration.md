# Simfile GraphQL Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the retiring REST DTX server integration with the delivered GraphQL backend (`Virgo/schema.graphql`), keeping the existing SwiftData models, `ServerSongService` facade, and views, behind a new Apollo-based client + mapping layer.

**Architecture:** Apollo iOS (SPM + committed generated code) is isolated behind a `SimfileFetching` protocol that returns plain client DTOs. A pure `SimfileMapper` + `DifficultyClassifier` convert DTOs into the existing `ServerSong`/`ServerChart` models. Catalog refresh becomes a manual, additive-with-prune page-walk. Chart files download from `DtxFile.fileUrl`; BGM/preview from client-assembled public R2 URLs whose availability is read from `Simfile.files[]`.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, Apollo iOS, Swift Testing (`import Testing`), Xcode 16.4 (objectVersion 77, file-system-synchronized groups — new files under `Virgo/` and `VirgoTests/` are auto-included in their targets).

**Spec:** `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`

---

## Conventions for every task

- Build/test with the macOS destination (sufficient per `CLAUDE.md`):
  ```bash
  xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
    -configuration Debug -only-testing:VirgoTests \
    ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath ./DerivedData 2>&1 | tail -40
  ```
  Run a single suite with `-only-testing:VirgoTests/<SuiteName>`.
- `swiftlint lint` must stay clean (line ≤120 warn/150 err; func body ≤50/100; type body ≤300/600; file ≤600/1000).
- A "pre-existing flaky SwiftData test crash" exists on `main` (`\Chart.difficulty` detached) — a red *full* run that matches that known crash is not your regression. Verify your *new* suites pass in isolation.
- Commit after each task with the shown message.

---

## File Structure

**New files (under `Virgo/`, auto-included):**
- `Virgo/GraphQL/Operations/SimfileFields.graphql` — shared fragment
- `Virgo/GraphQL/Operations/SimfilesQuery.graphql`
- `Virgo/GraphQL/Operations/SimfileQuery.graphql`
- `Virgo/GraphQL/Generated/**` — Apollo-generated Swift (committed)
- `apollo-codegen-config.json` — repo root, codegen config
- `Virgo/utilities/SimfileDTO.swift` — DTOs + `SimfileFetching` protocol
- `Virgo/utilities/ApolloSimfileClient.swift` — Apollo adapter (only file importing `Apollo`)
- `Virgo/utilities/ServerConfig.swift` — endpoint + R2 base URL config
- `Virgo/utilities/DifficultyClassifier.swift` — label/level → `Difficulty`
- `Virgo/utilities/SimfileMapper.swift` — DTO → `ServerSong`/`ServerChart`

**Modified files:**
- `Virgo/models/DrumTrack.swift` — add fields to `ServerChart` and `ServerSong`
- `Virgo/utilities/ServerSongCache.swift` — manual additive+prune refresh
- `Virgo/utilities/ServerSongFileManager.swift` — delete-by-songId helpers
- `Virgo/utilities/ServerSongStatusManager.swift` — prune local data for an id
- `Virgo/utilities/ServerSongDownloader.swift` — fileUrl + assembled audio
- `Virgo/utilities/DTXAPIClient.swift` / `DTXAPITypes.swift` — drop REST list/metadata
- `Virgo/utilities/ServerSongService.swift` — manual `refreshCatalog()`
- `Virgo/views/SongsTabView.swift` — manual re-fetch button copy
- `Virgo.xcodeproj/project.pbxproj` — Apollo SPM package reference

**New test files (under `VirgoTests/`, auto-included):**
- `VirgoTests/DifficultyClassifierTests.swift`
- `VirgoTests/ServerConfigTests.swift`
- `VirgoTests/SimfileMapperTests.swift`
- `VirgoTests/MockSimfileFetcher.swift` (shared test helper)
- updates to `ServerSongCacheTests.swift`, `ServerSongDownloaderTests.swift`, and removal of REST-only assertions in `DTXAPIClient*`/`DTXServerTypesTests`/`DTXAPITypesTests`.

---

## Task 1: Add Apollo iOS dependency + codegen scaffolding

This is a bootstrap task. It has no unit test; its verification is "the project builds and generated types exist". Generated code is committed so CI needs no codegen step.

**Files:**
- Create: `apollo-codegen-config.json`
- Create: `Virgo/GraphQL/Operations/SimfileFields.graphql`
- Create: `Virgo/GraphQL/Operations/SimfilesQuery.graphql`
- Create: `Virgo/GraphQL/Operations/SimfileQuery.graphql`
- Create: `Virgo/GraphQL/Generated/**` (output of codegen)
- Modify: `Virgo.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the Apollo package to the Virgo app target.**

Preferred (reliable) path — Xcode UI: File ▸ Add Package Dependencies… ▸ `https://github.com/apollographql/apollo-ios` ▸ Dependency Rule "Up to Next Major" from `1.15.0` ▸ add product **`Apollo`** to the **Virgo** target only (not the test targets). This writes the `XCRemoteSwiftPackageReference`, `packageReferences`, and `packageProductDependencies` entries into `project.pbxproj`.

CLI-only alternative (if no Xcode UI): add to `project.pbxproj` a `packageReferences` array on the PBXProject and a `Apollo` entry in the Virgo target's `packageProductDependencies` (currently empty at the two `packageProductDependencies = ( );` sites for the Virgo target). Because hand-editing objectVersion-77 pbxproj is error-prone, prefer the UI path and only fall back here if necessary.

- [ ] **Step 2: Create the GraphQL operation documents.**

`Virgo/GraphQL/Operations/SimfileFields.graphql`:
```graphql
fragment SimfileFields on Simfile {
  id
  title
  artist
  bpm
  genre
  tags
  durationSeconds
  updatedAt
  dtxFiles {
    label
    level
    fileUrl
    fileSizeBytes
    fileEncoding
  }
  files {
    key
    size
  }
}
```

`Virgo/GraphQL/Operations/SimfilesQuery.graphql`:
```graphql
query Simfiles($page: Int!, $pageSize: Int!, $search: String) {
  simfiles(scope: PUBLISHED, page: $page, pageSize: $pageSize, search: $search) {
    count
    data {
      ...SimfileFields
    }
  }
}
```

`Virgo/GraphQL/Operations/SimfileQuery.graphql`:
```graphql
query Simfile($id: ID!) {
  simfile(id: $id) {
    ...SimfileFields
  }
}
```

- [ ] **Step 3: Create the codegen config.** `apollo-codegen-config.json` at repo root:
```json
{
  "schemaNamespace": "VirgoGraphQL",
  "input": {
    "operationSearchPaths": ["Virgo/GraphQL/Operations/**/*.graphql"],
    "schemaSearchPaths": ["Virgo/schema.graphql"]
  },
  "output": {
    "testMocks": { "none": {} },
    "schemaTypes": {
      "path": "Virgo/GraphQL/Generated",
      "moduleType": { "embeddedInTarget": { "name": "Virgo", "accessModifier": "internal" } }
    },
    "operations": { "inSchemaModule": {} }
  },
  "options": {
    "additionalInflectionRules": [],
    "deprecatedEnumCases": "include",
    "schemaDocumentation": "exclude",
    "warningsOnDeprecatedUsage": "include"
  }
}
```

- [ ] **Step 4: Generate the code.** From repo root:
```bash
# Resolve the package so the CLI is available, then generate.
xcodebuild -resolvePackageDependencies -project Virgo.xcodeproj -scheme Virgo
DERIVED=$(ls -d ~/Library/Developer/Xcode/DerivedData/Virgo-* 2>/dev/null | head -1)
"$DERIVED"/SourcePackages/artifacts/apollo-ios/apollo-ios-cli/bin/apollo-ios-cli generate \
  --path apollo-codegen-config.json
```
If the CLI path differs, locate it with `find ~/Library/Developer/Xcode/DerivedData -name apollo-ios-cli -type f`. Expected: files appear under `Virgo/GraphQL/Generated/` (e.g. `Schema/`, `Operations/SimfilesQuery.graphql.swift`, `Operations/SimfileQuery.graphql.swift`).

- [ ] **Step 5: Build to verify the generated types compile and are in the target.**

Run: `xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. The types `SimfilesQuery`, `SimfileQuery`, and `VirgoGraphQL` namespace now exist.

- [ ] **Step 6: Commit.**
```bash
git add apollo-codegen-config.json Virgo/GraphQL Virgo.xcodeproj/project.pbxproj Virgo.xcodeproj/project.xcworkspace
git commit -m "feat: add Apollo iOS dependency and generated simfile operations"
```

---

## Task 2: Extend ServerChart and ServerSong models

Add the fields the GraphQL mapping needs: per-chart public file URL + encoding, and song-level genre/duration. All additions are optional or defaulted so SwiftData migrates additively.

**Files:**
- Modify: `Virgo/models/DrumTrack.swift:182-206` (ServerChart), `:208-284` (ServerSong)
- Test: `VirgoTests/ServerChartModelTests.swift`, `VirgoTests/ServerSongModelTests.swift`

- [ ] **Step 1: Write failing tests for the new fields.**

Append to `VirgoTests/ServerChartModelTests.swift` (inside the existing `@Suite` struct):
```swift
@Test("ServerChart stores fileURL and encoding")
func testServerChartFileURLAndEncoding() async throws {
    let chart = ServerChart(
        difficulty: "hard",
        difficultyLabel: "EXTREME",
        level: 74,
        filename: "ext.dtx",
        size: 1234,
        fileURL: "https://r2.example/song/ext.dtx",
        fileEncoding: "SHIFT_JIS"
    )
    #expect(chart.fileURL == "https://r2.example/song/ext.dtx")
    #expect(chart.fileEncoding == "SHIFT_JIS")
}
```
Append to `VirgoTests/ServerSongModelTests.swift`:
```swift
@Test("ServerSong stores genre and durationSeconds")
func testServerSongGenreAndDuration() async throws {
    let song = ServerSong(
        songId: "s1", title: "T", artist: "A", bpm: 120,
        genre: "Rock", durationSeconds: 210
    )
    #expect(song.genre == "Rock")
    #expect(song.durationSeconds == 210)
}
```

- [ ] **Step 2: Run tests, verify they fail to compile.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerChartModelTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — `extra arguments 'fileURL', 'fileEncoding'`.

- [ ] **Step 3: Add fields to `ServerChart`.** Replace the `ServerChart` body (`Virgo/models/DrumTrack.swift:183-205`):
```swift
final class ServerChart {
    var difficulty: String  // "easy", "medium", "hard", "expert"
    var difficultyLabel: String  // "BASIC", "ADVANCED", "EXTREME", "MASTER"
    var level: Int  // Numeric difficulty level (rounded from the GraphQL Float)
    var filename: String  // Original DTX file name / label-derived name
    var size: Int
    var fileURL: String = ""  // Public R2 URL for the .dtx file (DtxFile.fileUrl)
    var fileEncoding: String = "SHIFT_JIS"  // "SHIFT_JIS" | "UTF_8" (DtxFile.fileEncoding)
    var serverSong: ServerSong?

    init(
        difficulty: String,
        difficultyLabel: String,
        level: Int,
        filename: String,
        size: Int,
        fileURL: String = "",
        fileEncoding: String = "SHIFT_JIS",
        serverSong: ServerSong? = nil
    ) {
        self.difficulty = difficulty
        self.difficultyLabel = difficultyLabel
        self.level = level
        self.filename = filename
        self.size = size
        self.fileURL = fileURL
        self.fileEncoding = fileEncoding
        self.serverSong = serverSong
    }
}
```

- [ ] **Step 4: Add fields to `ServerSong`.** In `ServerSong` (`Virgo/models/DrumTrack.swift:208-284`) add stored properties after `var bpm: Double` and parameters to the designated initializer:
```swift
    var genre: String?            // server-curated; nil -> client falls back to "DTX Import"
    var durationSeconds: Int?     // accurate duration if known
```
Update the designated `init(...)` signature to add `genre: String? = nil, durationSeconds: Int? = nil` (place them right after `bpm: Double`) and assign `self.genre = genre` and `self.durationSeconds = durationSeconds` in the body. Leave the legacy `convenience init(filename:...)` calling the designated init unchanged (it omits the new params, which default to nil).

- [ ] **Step 5: Run the two suites, verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerChartModelTests -only-testing:VirgoTests/ServerSongModelTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: both suites pass.

- [ ] **Step 6: Commit.**
```bash
git add Virgo/models/DrumTrack.swift VirgoTests/ServerChartModelTests.swift VirgoTests/ServerSongModelTests.swift
git commit -m "feat: add fileURL/encoding to ServerChart and genre/duration to ServerSong"
```

---

## Task 3: Client DTOs + SimfileFetching protocol

Plain value types that decouple all downstream code from Apollo's generated types.

**Files:**
- Create: `Virgo/utilities/SimfileDTO.swift`
- Test: `VirgoTests/SimfileMapperTests.swift` (compile-only usage here; full tests in Task 7)

- [ ] **Step 1: Create the DTOs and protocol.** `Virgo/utilities/SimfileDTO.swift`:
```swift
import Foundation

/// File text encoding as reported by the backend (`DtxFile.fileEncoding`).
enum SimfileEncoding: String, Equatable {
    case shiftJIS = "SHIFT_JIS"
    case utf8 = "UTF_8"
}

/// One difficulty chart within a simfile (`DtxFile`).
struct DtxFileDTO: Equatable {
    let label: String        // e.g. "BASIC", "EXTREME"
    let level: Double        // GraphQL Float! (scale TBD — see spec open question)
    let fileURL: String      // public R2 URL
    let fileSizeBytes: Int
    let encoding: SimfileEncoding
}

/// A catalog simfile (`Simfile`), reduced to the fields the client consumes.
struct SimfileDTO: Equatable {
    let id: String
    let title: String
    let artist: String
    let bpm: Double
    let genre: String?
    let tags: [String]
    let durationSeconds: Int?
    let updatedAt: String        // ISO-8601 string
    let dtxFiles: [DtxFileDTO]
    let fileKeys: [String]       // `Simfile.files[].key`, for audio availability
}

/// One page of catalog results (`SimfileConnection`).
struct SimfilePage: Equatable {
    let simfiles: [SimfileDTO]
    let totalCount: Int
}

/// Read-only access to the simfile catalog. Apollo lives behind this seam.
protocol SimfileFetching {
    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage
    func fetchSimfile(id: String) async throws -> SimfileDTO?
}
```

- [ ] **Step 2: Build to verify it compiles.**

Run: `xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**
```bash
git add Virgo/utilities/SimfileDTO.swift
git commit -m "feat: add simfile DTOs and SimfileFetching protocol"
```

---

## Task 4: ApolloSimfileClient (generated types → DTOs)

The only file that imports `Apollo`. Wraps `ApolloClient.fetch` in async/throws and maps generated types to DTOs.

**Files:**
- Create: `Virgo/utilities/ApolloSimfileClient.swift`

- [ ] **Step 1: Implement the client.** `Virgo/utilities/ApolloSimfileClient.swift`:
```swift
import Foundation
import Apollo

/// Apollo-backed implementation of `SimfileFetching`.
/// This is the only type that depends on the generated GraphQL code.
final class ApolloSimfileClient: SimfileFetching {
    private let apollo: ApolloClient

    init(endpointURL: URL) {
        self.apollo = ApolloClient(url: endpointURL)
    }

    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        let query = SimfilesQuery(
            page: page,
            pageSize: pageSize,
            search: search.map { GraphQLNullable.some($0) } ?? .null
        )
        let data = try await fetch(query)
        let connection = data.simfiles
        let dtos = connection.data.map { Self.map($0.fragments.simfileFields) }
        return SimfilePage(simfiles: dtos, totalCount: connection.count)
    }

    func fetchSimfile(id: String) async throws -> SimfileDTO? {
        let data = try await fetch(SimfileQuery(id: id))
        return data.simfile.map { Self.map($0.fragments.simfileFields) }
    }

    // MARK: - Apollo bridging

    private func fetch<Q: GraphQLQuery>(_ query: Q) async throws -> Q.Data {
        try await withCheckedThrowingContinuation { continuation in
            apollo.fetch(query: query, cachePolicy: .fetchIgnoringCacheCompletely) { result in
                switch result {
                case .success(let response):
                    if let errors = response.errors, !errors.isEmpty {
                        continuation.resume(throwing: SimfileGraphQLError(graphQLErrors: errors))
                    } else if let data = response.data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: SimfileGraphQLError(graphQLErrors: []))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Generated -> DTO mapping

    private static func map(_ s: SimfileFields) -> SimfileDTO {
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
                DtxFileDTO(
                    label: f.label,
                    level: f.level,
                    fileURL: f.fileUrl,
                    fileSizeBytes: f.fileSizeBytes,
                    encoding: SimfileEncoding(rawValue: f.fileEncoding.rawValue) ?? .shiftJIS
                )
            },
            fileKeys: s.files.map { $0.key }
        )
    }
}

/// Wraps backend GraphQL `errors[]` for surfacing to the user.
struct SimfileGraphQLError: LocalizedError {
    let graphQLErrors: [GraphQLError]
    var errorDescription: String? {
        if let first = graphQLErrors.first { return first.message }
        return "GraphQL request failed"
    }
}
```

> Note: exact generated accessor names (`s.dtxFiles`, `f.fileUrl`, `.fragments.simfileFields`, `f.fileEncoding.rawValue`) come from Task 1's output. If codegen names differ, adjust these references — the DTO shape is the contract that must not change.

- [ ] **Step 2: Build to verify.**

Run: `xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. If accessor mismatches appear, fix per the note above, then rebuild.

- [ ] **Step 3: Commit.**
```bash
git add Virgo/utilities/ApolloSimfileClient.swift
git commit -m "feat: add ApolloSimfileClient mapping generated types to DTOs"
```

---

## Task 5: ServerConfig (GraphQL endpoint + R2 base URL)

Centralizes the two configurable URLs in `UserDefaults`, mirroring `DTXAPIClient`'s override/validate/reset semantics.

**Files:**
- Create: `Virgo/utilities/ServerConfig.swift`
- Test: `VirgoTests/ServerConfigTests.swift`

- [ ] **Step 1: Write failing tests.** `VirgoTests/ServerConfigTests.swift`:
```swift
import Testing
import Foundation
@testable import Virgo

@Suite("ServerConfig Tests")
struct ServerConfigTests {
    private func makeConfig(_ name: String) -> (ServerConfig, UserDefaults) {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: name)
        return (ServerConfig(userDefaults: defaults), defaults)
    }

    @Test("Defaults to local endpoint and empty R2 base")
    func testDefaults() {
        let (config, _) = makeConfig("config.defaults")
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
        #expect(config.r2BaseURL == nil)
    }

    @Test("Stores and trims overrides")
    func testOverrides() {
        let (config, _) = makeConfig("config.override")
        config.setGraphQLEndpoint("https://api.example.com/graphql/")
        config.setR2BaseURL("https://r2.example.com/bucket/")
        #expect(config.graphQLEndpoint == URL(string: "https://api.example.com/graphql"))
        #expect(config.r2BaseURL == URL(string: "https://r2.example.com/bucket"))
    }

    @Test("Rejects non-http schemes and falls back")
    func testInvalidScheme() {
        let (config, _) = makeConfig("config.invalid")
        config.setGraphQLEndpoint("ftp://nope")
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
    }
}
```

- [ ] **Step 2: Run, verify fail (no such type).**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerConfigTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — `cannot find 'ServerConfig'`.

- [ ] **Step 3: Implement `ServerConfig`.** `Virgo/utilities/ServerConfig.swift`:
```swift
import Foundation

/// Configurable backend URLs, persisted in UserDefaults.
/// - GraphQL endpoint replaces the legacy `DTXServerURL` default.
/// - R2 base URL is used to assemble public audio URLs.
final class ServerConfig {
    static let graphQLEndpointKey = "GraphQLEndpointURL"
    static let r2BaseURLKey = "R2BaseURL"
    private static let defaultEndpoint = "http://127.0.0.1:8001/graphql"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var graphQLEndpoint: URL {
        let raw = userDefaults.string(forKey: Self.graphQLEndpointKey) ?? Self.defaultEndpoint
        return URL(string: raw) ?? URL(string: Self.defaultEndpoint)!
    }

    var r2BaseURL: URL? {
        guard let raw = userDefaults.string(forKey: Self.r2BaseURLKey), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    func setGraphQLEndpoint(_ value: String) {
        guard let normalized = Self.normalized(value) else {
            userDefaults.removeObject(forKey: Self.graphQLEndpointKey)
            return
        }
        userDefaults.set(normalized, forKey: Self.graphQLEndpointKey)
    }

    func setR2BaseURL(_ value: String) {
        guard let normalized = Self.normalized(value) else {
            userDefaults.removeObject(forKey: Self.r2BaseURLKey)
            return
        }
        userDefaults.set(normalized, forKey: Self.r2BaseURLKey)
    }

    /// Validate http/https + host, drop a single trailing slash.
    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        if trimmed.hasSuffix("/") && !trimmed.hasSuffix("//") {
            return String(trimmed.dropLast())
        }
        return trimmed
    }
}
```

- [ ] **Step 4: Run, verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerConfigTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: 3 tests pass.

- [ ] **Step 5: Commit.**
```bash
git add Virgo/utilities/ServerConfig.swift VirgoTests/ServerConfigTests.swift
git commit -m "feat: add ServerConfig for GraphQL endpoint and R2 base URL"
```

---

## Task 6: DifficultyClassifier

Pure mapping from `(label, level)` to the canonical 4-bucket `Difficulty`.

**Files:**
- Create: `Virgo/utilities/DifficultyClassifier.swift`
- Test: `VirgoTests/DifficultyClassifierTests.swift`

- [ ] **Step 1: Write failing tests.** `VirgoTests/DifficultyClassifierTests.swift`:
```swift
import Testing
@testable import Virgo

@Suite("DifficultyClassifier Tests")
struct DifficultyClassifierTests {
    @Test("Known labels map case-insensitively")
    func testLabels() {
        #expect(DifficultyClassifier.classify(label: "BASIC", level: 0) == .easy)
        #expect(DifficultyClassifier.classify(label: "advanced", level: 0) == .medium)
        #expect(DifficultyClassifier.classify(label: "Extreme", level: 0) == .hard)
        #expect(DifficultyClassifier.classify(label: "MASTER", level: 0) == .expert)
        #expect(DifficultyClassifier.classify(label: "REAL", level: 0) == .expert)
    }

    @Test("Unknown labels fall back to level thresholds")
    func testLevelFallback() {
        #expect(DifficultyClassifier.classify(label: "???", level: 20) == .easy)
        #expect(DifficultyClassifier.classify(label: "???", level: 45) == .medium)
        #expect(DifficultyClassifier.classify(label: "???", level: 65) == .hard)
        #expect(DifficultyClassifier.classify(label: "???", level: 85) == .expert)
    }
}
```

- [ ] **Step 2: Run, verify fail.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/DifficultyClassifierTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — `cannot find 'DifficultyClassifier'`.

- [ ] **Step 3: Implement.** `Virgo/utilities/DifficultyClassifier.swift`:
```swift
import Foundation

/// Derives the app's canonical 4-bucket `Difficulty` from the backend's
/// free-form `label` plus numeric `level` (the backend has no Difficulty enum).
enum DifficultyClassifier {
    /// `level` is on the 0–100 scale (e.g. 36, 60, 74, 87) per the spec sample data.
    /// If the backend turns out to use a 0–9.99 scale, multiply by 10 before calling.
    static func classify(label: String, level: Int) -> Difficulty {
        switch label.uppercased() {
        case "BASIC": return .easy
        case "ADVANCED": return .medium
        case "EXTREME": return .hard
        case "MASTER", "REAL": return .expert
        default: return classifyByLevel(level)
        }
    }

    private static func classifyByLevel(_ level: Int) -> Difficulty {
        switch level {
        case ..<35: return .easy
        case 35..<55: return .medium
        case 55..<75: return .hard
        default: return .expert
        }
    }
}
```

- [ ] **Step 4: Run, verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/DifficultyClassifierTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: 2 tests pass.

- [ ] **Step 5: Commit.**
```bash
git add Virgo/utilities/DifficultyClassifier.swift VirgoTests/DifficultyClassifierTests.swift
git commit -m "feat: add DifficultyClassifier for label/level to Difficulty bucket"
```

---

## Task 7: SimfileMapper (DTO → ServerSong/ServerChart)

Pure conversion. Applies difficulty derivation, level rounding, genre/duration carry-over, ISO date parsing, audio availability from `fileKeys`. Also exposes the audio-URL assembly used later by the downloader.

**Files:**
- Create: `Virgo/utilities/SimfileMapper.swift`
- Test: `VirgoTests/SimfileMapperTests.swift`

- [ ] **Step 1: Write failing tests.** `VirgoTests/SimfileMapperTests.swift`:
```swift
import Testing
import Foundation
@testable import Virgo

@Suite("SimfileMapper Tests")
struct SimfileMapperTests {
    private func sampleDTO(fileKeys: [String]) -> SimfileDTO {
        SimfileDTO(
            id: "song-1", title: "Title", artist: "Artist", bpm: 165.55,
            genre: nil, tags: ["jrock"], durationSeconds: 200,
            updatedAt: "2026-06-01T12:00:00Z",
            dtxFiles: [
                DtxFileDTO(label: "EXTREME", level: 74.0,
                           fileURL: "https://r2/song-1/ext.dtx",
                           fileSizeBytes: 4096, encoding: .shiftJIS)
            ],
            fileKeys: fileKeys
        )
    }

    @Test("Maps core fields, derives difficulty, rounds level")
    func testCoreMapping() {
        let song = SimfileMapper.makeServerSong(from: sampleDTO(fileKeys: []))
        #expect(song.songId == "song-1")
        #expect(song.bpm == 165.55)
        #expect(song.genre == nil) // nil here; downloader applies "DTX Import" fallback
        #expect(song.durationSeconds == 200)
        #expect(song.charts.count == 1)
        #expect(song.charts[0].difficulty == "Hard")     // EXTREME -> .hard rawValue
        #expect(song.charts[0].level == 74)
        #expect(song.charts[0].fileURL == "https://r2/song-1/ext.dtx")
        #expect(song.charts[0].fileEncoding == "SHIFT_JIS")
    }

    @Test("Audio availability comes from file keys (suffix match)")
    func testAudioAvailability() {
        let withBoth = SimfileMapper.makeServerSong(
            from: sampleDTO(fileKeys: ["song-1/bgm.ogg", "song-1/preview.mp3"]))
        #expect(withBoth.hasBGM == true)
        #expect(withBoth.hasPreview == true)

        let withNone = SimfileMapper.makeServerSong(from: sampleDTO(fileKeys: ["song-1/ext.dtx"]))
        #expect(withNone.hasBGM == false)
        #expect(withNone.hasPreview == false)
    }

    @Test("Assembles audio URLs from R2 base + id")
    func testAudioURLAssembly() {
        let base = URL(string: "https://r2.example/bucket")!
        #expect(SimfileMapper.bgmURL(base: base, songId: "song-1")
                == URL(string: "https://r2.example/bucket/song-1/bgm.ogg"))
        #expect(SimfileMapper.previewURL(base: base, songId: "song-1")
                == URL(string: "https://r2.example/bucket/song-1/preview.mp3"))
    }
}
```

- [ ] **Step 2: Run, verify fail.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/SimfileMapperTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — `cannot find 'SimfileMapper'`.

- [ ] **Step 3: Implement.** `Virgo/utilities/SimfileMapper.swift`:
```swift
import Foundation

/// Pure conversion from catalog DTOs to SwiftData models, plus audio URL helpers.
enum SimfileMapper {
    static func makeServerSong(from dto: SimfileDTO) -> ServerSong {
        let charts = dto.dtxFiles.map { makeServerChart(from: $0) }
        let song = ServerSong(
            songId: dto.id,
            title: dto.title,
            artist: dto.artist,
            bpm: dto.bpm,
            genre: dto.genre,
            durationSeconds: dto.durationSeconds,
            charts: charts,
            isDownloaded: false,
            hasBGM: hasFile(named: "bgm.ogg", in: dto.fileKeys),
            hasPreview: hasFile(named: "preview.mp3", in: dto.fileKeys)
        )
        song.lastUpdated = parseDate(dto.updatedAt)
        return song
    }

    static func makeServerChart(from dto: DtxFileDTO) -> ServerChart {
        let level = Int(dto.level.rounded())
        let difficulty = DifficultyClassifier.classify(label: dto.label, level: level)
        return ServerChart(
            difficulty: difficulty.rawValue.lowercased(),
            difficultyLabel: dto.label,
            level: level,
            filename: dto.label,
            size: dto.fileSizeBytes,
            fileURL: dto.fileURL,
            fileEncoding: dto.encoding.rawValue
        )
    }

    static func bgmURL(base: URL, songId: String) -> URL {
        base.appendingPathComponent(songId).appendingPathComponent("bgm.ogg")
    }

    static func previewURL(base: URL, songId: String) -> URL {
        base.appendingPathComponent(songId).appendingPathComponent("preview.mp3")
    }

    // MARK: - Helpers

    private static func hasFile(named name: String, in keys: [String]) -> Bool {
        keys.contains { $0.hasSuffix(name) }
    }

    private static func parseDate(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date()
    }
}
```

> Note: `ServerSong`'s designated init must accept `genre`/`durationSeconds` immediately after `bpm` (Task 2). The `ServerChart(difficulty:)` first param expects the lowercased bucket string ("easy"/"medium"/"hard"/"expert"), matching the existing `mapServerDifficultyToApp` consumer.

- [ ] **Step 4: Run, verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/SimfileMapperTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: 3 tests pass.

- [ ] **Step 5: Commit.**
```bash
git add Virgo/utilities/SimfileMapper.swift VirgoTests/SimfileMapperTests.swift
git commit -m "feat: add SimfileMapper for DTO to SwiftData conversion + audio URLs"
```

---

## Task 8: Shared MockSimfileFetcher test helper

A reusable in-memory `SimfileFetching` for cache/refresh tests.

**Files:**
- Create: `VirgoTests/MockSimfileFetcher.swift`

- [ ] **Step 1: Implement the mock.** `VirgoTests/MockSimfileFetcher.swift`:
```swift
import Foundation
@testable import Virgo

/// In-memory `SimfileFetching` that paginates a fixed list. Thread-safe enough
/// for serialized test suites.
final class MockSimfileFetcher: SimfileFetching, @unchecked Sendable {
    var all: [SimfileDTO]
    var error: Error?
    private(set) var fetchSimfilesCallCount = 0

    init(all: [SimfileDTO] = []) { self.all = all }

    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        fetchSimfilesCallCount += 1
        if let error { throw error }
        let start = max(0, (page - 1) * pageSize)
        guard start < all.count else { return SimfilePage(simfiles: [], totalCount: all.count) }
        let end = min(start + pageSize, all.count)
        return SimfilePage(simfiles: Array(all[start..<end]), totalCount: all.count)
    }

    func fetchSimfile(id: String) async throws -> SimfileDTO? {
        if let error { throw error }
        return all.first { $0.id == id }
    }
}

extension SimfileDTO {
    /// Convenience builder for tests.
    static func stub(id: String, title: String = "T", fileKeys: [String] = []) -> SimfileDTO {
        SimfileDTO(
            id: id, title: title, artist: "A", bpm: 120, genre: nil, tags: [],
            durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
            dtxFiles: [DtxFileDTO(label: "BASIC", level: 30, fileURL: "https://r2/\(id)/bas.dtx",
                                  fileSizeBytes: 100, encoding: .shiftJIS)],
            fileKeys: fileKeys
        )
    }
}
```

- [ ] **Step 2: Build the test target to verify it compiles.**

Run: `xcodebuild build-for-testing -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -10`
Expected: build succeeds.

- [ ] **Step 3: Commit.**
```bash
git add VirgoTests/MockSimfileFetcher.swift
git commit -m "test: add MockSimfileFetcher and SimfileDTO stub helper"
```

---

## Task 9: Rewrite ServerSongCache — manual additive refresh + prune-stale

Replace the REST-based `refreshServerSongs`/auto-stale logic with: page-walk the GraphQL catalog, insert new ids, leave existing ids untouched, prune ids no longer present (including local files via the status manager).

**Files:**
- Modify: `Virgo/utilities/ServerSongCache.swift`
- Test: `VirgoTests/ServerSongCacheTests.swift`

- [ ] **Step 1: Write failing tests** for the new behavior. Add a focused suite `VirgoTests/ServerSongCatalogRefreshTests.swift` (keeps the heavy REST mock suite separate; that suite is trimmed in Task 12):
```swift
import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSong Catalog Refresh Tests", .serialized)
@MainActor
struct ServerSongCatalogRefreshTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([ServerSong.self, ServerChart.self, Song.self, Chart.self, Note.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("Inserts new simfiles on refresh")
    func testInsertsNew() async throws {
        let context = try makeContext()
        let fetcher = MockSimfileFetcher(all: [.stub(id: "a"), .stub(id: "b")])
        let cache = ServerSongCache(fetcher: fetcher, pageSize: 1)

        try await cache.refreshCatalog(modelContext: context)

        let songs = try context.fetch(FetchDescriptor<ServerSong>())
        #expect(Set(songs.map(\.songId)) == ["a", "b"])
        #expect(fetcher.fetchSimfilesCallCount >= 2) // paged at size 1
    }

    @Test("Leaves existing ids untouched and prunes stale ids")
    func testAdditiveAndPrune() async throws {
        let context = try makeContext()
        // Seed an existing entry "a" (downloaded) and a stale "z".
        let existing = ServerSong(songId: "a", title: "OLD", artist: "A", bpm: 120, isDownloaded: true)
        let stale = ServerSong(songId: "z", title: "Z", artist: "A", bpm: 120)
        context.insert(existing); context.insert(stale)
        try context.save()

        let fetcher = MockSimfileFetcher(all: [.stub(id: "a", title: "NEW"), .stub(id: "b")])
        let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
        try await cache.refreshCatalog(modelContext: context)

        let songs = try context.fetch(FetchDescriptor<ServerSong>())
        let byId = Dictionary(uniqueKeysWithValues: songs.map { ($0.songId, $0) })
        #expect(Set(byId.keys) == ["a", "b"])            // z pruned, b added
        #expect(byId["a"]?.title == "OLD")               // existing NOT overwritten
        #expect(byId["a"]?.isDownloaded == true)
    }
}
```

- [ ] **Step 2: Run, verify fail.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongCatalogRefreshTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — `ServerSongCache` has no `init(fetcher:pageSize:)` / `refreshCatalog`.

- [ ] **Step 3: Rewrite `ServerSongCache`.** Replace the whole file `Virgo/utilities/ServerSongCache.swift`:
```swift
import Foundation
import SwiftData

/// Loads and refreshes the cached server-song catalog from the GraphQL backend.
/// Refresh is manual and additive: new ids are inserted, existing ids are left
/// untouched, and ids absent from the server are pruned (with local files).
@MainActor
class ServerSongCache {
    private let fetcher: SimfileFetching
    private let statusManager: ServerSongStatusManager
    private let pageSize: Int
    private let saveContext: (ModelContext) throws -> Void

    init(
        fetcher: SimfileFetching,
        statusManager: ServerSongStatusManager = ServerSongStatusManager(),
        pageSize: Int = 50,
        saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.fetcher = fetcher
        self.statusManager = statusManager
        self.pageSize = pageSize
        self.saveContext = saveContext
    }

    /// Load the cached catalog. No network — refresh is explicit (see `refreshCatalog`).
    func loadServerSongs(modelContext: ModelContext) async throws -> [ServerSong] {
        let descriptor = FetchDescriptor<ServerSong>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Manual catalog refresh: page-walk PUBLISHED, insert new, prune stale.
    func refreshCatalog(modelContext: ModelContext) async throws {
        let serverDTOs = try await fetchAllPages()
        let serverIds = Set(serverDTOs.map(\.id))

        let existing = try modelContext.fetch(FetchDescriptor<ServerSong>())
        let existingIds = Set(existing.map(\.songId))

        // Prune ids no longer on the server (delete record + local files).
        for song in existing where !serverIds.contains(song.songId) {
            await statusManager.pruneCachedSong(song, modelContext: modelContext)
        }

        // Insert only new ids; never overwrite existing entries.
        for dto in serverDTOs where !existingIds.contains(dto.id) {
            let song = SimfileMapper.makeServerSong(from: dto)
            modelContext.insert(song)
            for chart in song.charts { modelContext.insert(chart) }
        }

        try saveContext(modelContext)
        await statusManager.refreshDownloadStatus(modelContext: modelContext)
    }

    private func fetchAllPages() async throws -> [SimfileDTO] {
        var results: [SimfileDTO] = []
        var page = 1
        while true {
            let pageResult = try await fetcher.fetchSimfiles(page: page, pageSize: pageSize, search: nil)
            results.append(contentsOf: pageResult.simfiles)
            if results.count >= pageResult.totalCount || pageResult.simfiles.isEmpty { break }
            page += 1
        }
        return results
    }
}
```

- [ ] **Step 4: Run the new suite, verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongCatalogRefreshTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: 2 tests pass. (The project may not yet build because `pruneCachedSong` is added in Task 10 and `ServerSongService`/`ServerSongDownloader` still reference the old API — implement Task 10 next; if the build fails on `pruneCachedSong`, that is expected and resolved there.)

> To keep each task green, Task 9 and Task 10 are tightly coupled. If executing strictly green-between-tasks, add a temporary stub `func pruneCachedSong(...)` in Task 9 Step 3 and replace it in Task 10. Otherwise proceed directly to Task 10 and run both suites at Task 10 Step 4.

- [ ] **Step 5: Commit.**
```bash
git add Virgo/utilities/ServerSongCache.swift VirgoTests/ServerSongCatalogRefreshTests.swift
git commit -m "feat: manual additive+prune catalog refresh via GraphQL fetcher"
```

---

## Task 10: Prune local data for a cached song

Add `pruneCachedSong` to `ServerSongStatusManager` (delete the `ServerSong`/`ServerChart` records and any downloaded `Song` + BGM/preview files for that id) and a delete-by-songId helper on `ServerSongFileManager`.

**Files:**
- Modify: `Virgo/utilities/ServerSongFileManager.swift`
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Test: `VirgoTests/ServerSongFileManagerTests.swift`, `VirgoTests/ServerSongStatusManagerTests.swift`

- [ ] **Step 1: Write failing test for file deletion by songId.** Append to `VirgoTests/ServerSongFileManagerTests.swift`:
```swift
@Test("Deletes BGM and preview by songId")
func testDeleteBySongId() throws {
    let manager = ServerSongFileManager()
    let bgm = try manager.saveBGMFile(Data([1, 2, 3]), for: "del-test")
    let preview = try manager.savePreviewFile(Data([4, 5, 6]), for: "del-test")
    #expect(FileManager.default.fileExists(atPath: bgm))
    #expect(FileManager.default.fileExists(atPath: preview))

    manager.deleteFiles(forSongId: "del-test")

    #expect(!FileManager.default.fileExists(atPath: bgm))
    #expect(!FileManager.default.fileExists(atPath: preview))
}
```

- [ ] **Step 2: Run, verify fail.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongFileManagerTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — no `deleteFiles(forSongId:)`.

- [ ] **Step 3: Add `deleteFiles(forSongId:)`.** Append to `ServerSongFileManager` (before the closing brace):
```swift
    /// Delete BGM and preview files saved under this songId, if present.
    func deleteFiles(forSongId songId: String) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let bgm = documents.appendingPathComponent("BGM").appendingPathComponent("\(songId).ogg")
        let preview = documents.appendingPathComponent("Preview").appendingPathComponent("\(songId).mp3")
        try? FileManager.default.removeItem(at: bgm)
        try? FileManager.default.removeItem(at: preview)
    }
```

- [ ] **Step 4: Add `pruneCachedSong` to `ServerSongStatusManager`.** Append inside the class (before the private helpers):
```swift
    /// Remove a cached server song that is no longer on the server: delete any
    /// downloaded local Song + files for the same title/artist, then delete the
    /// ServerSong/ServerChart records and the by-songId audio files.
    @MainActor
    func pruneCachedSong(_ serverSong: ServerSong, modelContext: ModelContext) async {
        let songId = serverSong.songId
        if serverSong.isDownloaded {
            _ = await deleteDownloadedSong(serverSong, modelContext: modelContext)
        }
        modelContext.delete(serverSong)
        try? saveContext(modelContext)
        fileManager.deleteFiles(forSongId: songId)
    }
```

- [ ] **Step 5: Write a prune test.** Append to `VirgoTests/ServerSongStatusManagerTests.swift` (use the suite's existing in-memory context helper; if none, create a context as in Task 9 Step 1):
```swift
@Test("pruneCachedSong removes the ServerSong record")
@MainActor
func testPruneRemovesRecord() async throws {
    let schema = Schema([ServerSong.self, ServerChart.self, Song.self, Chart.self, Note.self])
    let container = try ModelContainer(
        for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    let context = ModelContext(container)
    let song = ServerSong(songId: "prune-me", title: "P", artist: "A", bpm: 120)
    context.insert(song); try context.save()

    await ServerSongStatusManager().pruneCachedSong(song, modelContext: context)

    let remaining = try context.fetch(FetchDescriptor<ServerSong>())
    #expect(remaining.isEmpty)
}
```

- [ ] **Step 6: Run both suites (and the Task 9 suite), verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongFileManagerTests -only-testing:VirgoTests/ServerSongStatusManagerTests -only-testing:VirgoTests/ServerSongCatalogRefreshTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: all pass.

- [ ] **Step 7: Commit.**
```bash
git add Virgo/utilities/ServerSongFileManager.swift Virgo/utilities/ServerSongStatusManager.swift VirgoTests/ServerSongFileManagerTests.swift VirgoTests/ServerSongStatusManagerTests.swift
git commit -m "feat: prune cached song records and local files on stale refresh"
```

---

## Task 11: Rewrite ServerSongDownloader — fileUrl + assembled audio

Download charts from `ServerChart.fileURL` (direct public URL), decode using `ServerChart.fileEncoding`, set genre/duration from `ServerSong`, and download BGM/preview from assembled R2 URLs gated by `hasBGM`/`hasPreview`.

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `Virgo/utilities/DTXAPIClient.swift` (keep only generic `downloadData(from:)`; see Task 12 for full REST removal)
- Test: `VirgoTests/ServerSongDownloaderTests.swift`

- [ ] **Step 1: Write a failing test for encoding-aware decode.** Add `VirgoTests/ServerSongDownloaderDecodeTests.swift`:
```swift
import Testing
import Foundation
@testable import Virgo

@Suite("ServerSongDownloader Decode Tests")
struct ServerSongDownloaderDecodeTests {
    @Test("Decodes chart bytes per declared encoding")
    func testDecode() {
        let utf8 = "#TITLE: x".data(using: .utf8)!
        #expect(ServerSongDownloader.decode(utf8, encoding: "UTF_8") == "#TITLE: x")
        let sjis = "あ".data(using: .shiftJIS)!
        #expect(ServerSongDownloader.decode(sjis, encoding: "SHIFT_JIS") == "あ")
    }
}
```

- [ ] **Step 2: Run, verify fail.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongDownloaderDecodeTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — no `decode(_:encoding:)`.

- [ ] **Step 3: Rewrite the downloader.** Replace `Virgo/utilities/ServerSongDownloader.swift`:
```swift
import Foundation
import SwiftData

/// Downloads and imports a server song's charts and optional audio.
class ServerSongDownloader {
    private let downloader: FileDownloading
    private let fileManager: ServerSongFileManager
    private let config: ServerConfig

    init(
        downloader: FileDownloading = DTXAPIClient(),
        fileManager: ServerSongFileManager = ServerSongFileManager(),
        config: ServerConfig = ServerConfig()
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
        self.config = config
    }

    @MainActor
    func downloadAndImportSong(_ serverSong: ServerSong, container: ModelContainer) async -> (Bool, String?) {
        let context = ModelContext(container)
        do {
            if try songAlreadyExists(serverSong, in: context) {
                return (false, "Song already exists in database")
            }
            let song = createSong(from: serverSong)
            try await processCharts(for: song, from: serverSong, in: context)
            await downloadOptionalFiles(for: song, serverSong: serverSong)
            context.insert(song)
            try context.save()
            return (true, nil)
        } catch {
            return (false, "Import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Decoding (testable)

    static func decode(_ data: Data, encoding: String) -> String? {
        let enc: String.Encoding = (encoding == "UTF_8") ? .utf8 : .shiftJIS
        return String(data: data, encoding: enc) ?? String(data: data, encoding: .utf8)
    }

    // MARK: - Private

    @MainActor
    private func songAlreadyExists(_ serverSong: ServerSong, in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<Song>())
        return existing.contains {
            $0.title.lowercased() == serverSong.title.lowercased() &&
            $0.artist.lowercased() == serverSong.artist.lowercased()
        }
    }

    private func createSong(from serverSong: ServerSong) -> Song {
        Song(
            title: serverSong.title,
            artist: serverSong.artist,
            bpm: serverSong.bpm,
            duration: serverSong.durationSeconds.map(Self.formatDuration) ?? "3:30",
            genre: serverSong.genre ?? "DTX Import",
            timeSignature: .fourFour
        )
    }

    @MainActor
    private func processCharts(for song: Song, from serverSong: ServerSong, in context: ModelContext) async throws {
        for (index, serverChart) in serverSong.charts.enumerated() {
            if index > 0 { try await Task.sleep(nanoseconds: 100_000_000) }
            try await processChart(serverChart, for: song, in: context)
        }
    }

    @MainActor
    private func processChart(_ serverChart: ServerChart, for song: Song, in context: ModelContext) async throws {
        guard let url = URL(string: serverChart.fileURL) else { return }
        let data = try await downloader.downloadData(from: url)
        guard let content = Self.decode(data, encoding: serverChart.fileEncoding) else {
            Logger.debug("Failed to decode \(serverChart.filename) with \(serverChart.fileEncoding)")
            return
        }
        let chartData = try DTXFileParser.parseChartMetadata(from: content)
        if song.charts.isEmpty {
            if chartData.bpm.isFinite && chartData.bpm > 0 { song.bpm = chartData.bpm }
            if serverChart.serverSong?.durationSeconds == nil {
                song.duration = Self.formatDuration(Int(calculateDuration(from: chartData.notes)))
            }
        }
        let difficulty = mapServerDifficultyToApp(serverChart.difficulty)
        let chart = Chart(difficulty: difficulty, level: serverChart.level, song: song)
        chartData.toNotes(for: chart).forEach { chart.notes.append($0) }
        context.insert(chart)
    }

    @MainActor
    private func downloadOptionalFiles(for song: Song, serverSong: ServerSong) async {
        guard let base = config.r2BaseURL else {
            Logger.database("No R2 base URL configured; skipping audio for \(song.title)")
            return
        }
        if serverSong.hasBGM {
            await download(SimfileMapper.bgmURL(base: base, songId: serverSong.songId), kind: .bgm,
                           songId: serverSong.songId, song: song)
        }
        if serverSong.hasPreview {
            await download(SimfileMapper.previewURL(base: base, songId: serverSong.songId), kind: .preview,
                           songId: serverSong.songId, song: song)
        }
    }

    private enum AudioKind { case bgm, preview }

    @MainActor
    private func download(_ url: URL, kind: AudioKind, songId: String, song: Song) async {
        do {
            let data = try await downloader.downloadData(from: url)
            switch kind {
            case .bgm: song.bgmFilePath = try fileManager.saveBGMFile(data, for: songId)
            case .preview: song.previewFilePath = try fileManager.savePreviewFile(data, for: songId)
            }
        } catch {
            Logger.database("Failed to download \(kind) for \(song.title): \(error.localizedDescription)")
        }
    }

    private func mapServerDifficultyToApp(_ s: String) -> Difficulty {
        switch s.lowercased() {
        case "easy": return .easy
        case "medium": return .medium
        case "hard": return .hard
        case "expert": return .expert
        default: return .medium
        }
    }

    private func calculateDuration(from notes: [DTXNote]) -> TimeInterval {
        guard !notes.isEmpty else { return 60.0 }
        let maxMeasure = notes.reduce(Int.min) { max($0, $1.measureNumber) }
        return Double(maxMeasure + 1) / 30.0 * 60.0
    }

    private static func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
```

- [ ] **Step 4: Introduce the `FileDownloading` seam on `DTXAPIClient`.** Add to `Virgo/utilities/DTXAPITypes.swift` (top, after the error enum):
```swift
/// Minimal file download seam used by the downloader (mockable in tests).
protocol FileDownloading {
    func downloadData(from url: URL) async throws -> Data
}
```
`DTXAPIClient` already implements `downloadData(from:)` (via `DTXNetworking`). Add conformance: change the class declaration extension `extension DTXAPIClient: DTXNetworking {` to also declare `FileDownloading` by adding `extension DTXAPIClient: FileDownloading {}` at the end of `DTXAPIClient.swift` (the method signature already matches).

- [ ] **Step 5: Run decode test + build, verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongDownloaderDecodeTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: test passes. (Existing `ServerSongDownloaderTests` that referenced the old `apiClient:` init will be updated/removed in Task 12.)

- [ ] **Step 6: Commit.**
```bash
git add Virgo/utilities/ServerSongDownloader.swift Virgo/utilities/DTXAPITypes.swift Virgo/utilities/DTXAPIClient.swift VirgoTests/ServerSongDownloaderDecodeTests.swift
git commit -m "feat: download charts via fileUrl and audio via assembled R2 URLs"
```

---

## Task 12: Remove legacy REST endpoints and update dependent tests

Strip the DTX list/metadata REST surface now that GraphQL drives the catalog. Keep only the generic `downloadData(from:)`/networking used by the downloader.

**Files:**
- Modify: `Virgo/utilities/DTXAPIClient.swift`, `Virgo/utilities/DTXAPITypes.swift`
- Modify/trim: `VirgoTests/DTXAPIClientTests.swift`, `DTXAPIClientNetworkingTests.swift`, `DTXAPIClientURLTests.swift`, `DTXServerTypesTests.swift`, `DTXAPITypesTests.swift`, `ServerSongCacheTests.swift`, `ServerSongDownloaderTests.swift`, `ServerSongServiceTests.swift`

- [ ] **Step 1: Remove the REST protocols and implementations.** In `DTXAPIClient.swift` delete the `DTXFileOperations` and `DTXDownloadOperations` protocol conformances and their extension bodies (the `listDTXFiles`, `listDTXSongs`, `getDTXMetadata`, `downloadDTXFile`, `downloadBGMFile`, `downloadPreviewFile`, `downloadChartFile` methods, plus the now-unused `makeSafeURL` helper if nothing else uses it). Keep: `DTXNetworking` (`performRequest`, `downloadData`), `DTXConfiguration` (or simplify), and the new `FileDownloading` conformance. In `DTXAPITypes.swift` delete the now-unused request/response types: `DTXServerFile`, `DTXServerSongData`, `DTXServerChartData`, `DTXChartMetadata`, `DTXServerMetadata`, `DTXSongInfo`, `DTXChartInfo`, `DTXFileInfo`, `DTXListResponse`, `DTXMetadataInfo`, `DTXMetadataResponse`. Keep `DTXAPIError`, the `DTXNetworking` protocol, and `FileDownloading`.

- [ ] **Step 2: Delete/trim the now-invalid tests.** Remove test files/cases that exercise the deleted REST API and types:
  - Delete `VirgoTests/DTXServerTypesTests.swift` and `VirgoTests/DTXAPITypesTests.swift` if they only test removed types (check first; keep any case covering `DTXAPIError`).
  - In `DTXAPIClientTests.swift`, `DTXAPIClientNetworkingTests.swift`, `DTXAPIClientURLTests.swift`: remove cases calling `listDTXFiles/listDTXSongs/getDTXMetadata/downloadDTXFile/downloadBGMFile/downloadPreviewFile/downloadChartFile`; keep cases for `downloadData`, init, and config.
  - Replace the old `ServerSongCacheTests.swift` REST-mock suite: delete it (its behavior is now covered by `ServerSongCatalogRefreshTests`).
  - In `ServerSongDownloaderTests.swift`: replace constructions using `ServerSongDownloader(apiClient:)` with `ServerSongDownloader(downloader:fileManager:config:)` using a mock `FileDownloading`. Minimal mock:
    ```swift
    final class MockFileDownloader: FileDownloading, @unchecked Sendable {
        var dataByURL: [String: Data] = [:]
        var error: Error?
        func downloadData(from url: URL) async throws -> Data {
            if let error { throw error }
            return dataByURL[url.absoluteString] ?? Data()
        }
    }
    ```
  - In `ServerSongServiceTests.swift`: update any `ServerSongCache(apiClient:)` / `cache.refreshServerSongs(...)` usage to the new `ServerSongCache(fetcher:...)` / `refreshCatalog(...)` API (Task 13 updates the service itself).

- [ ] **Step 3: Build for testing, fix any remaining references.**

Run: `xcodebuild build-for-testing -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -30`
Expected: build succeeds. Resolve any leftover compile errors pointing at removed symbols.

- [ ] **Step 4: Commit.**
```bash
git add -A
git commit -m "refactor: remove legacy DTX REST endpoints and update tests"
```

---

## Task 13: ServerSongService manual refresh + UI/app wiring

Switch the facade to the new cache API, expose a single manual `refreshCatalog()`, build the Apollo client from `ServerConfig`, and update the button.

**Files:**
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/views/SongsTabView.swift`
- Modify: `Virgo/views/ContentView.swift` (if init needs the config)
- Test: `VirgoTests/ServerSongServiceTests.swift`

- [ ] **Step 1: Write a failing service test** driving refresh through a mock fetcher. Add to `ServerSongServiceTests.swift`:
```swift
@Test("refreshCatalog populates cache from fetcher")
@MainActor
func testServiceRefreshCatalog() async throws {
    let schema = Schema([ServerSong.self, ServerChart.self, Song.self, Chart.self, Note.self])
    let container = try ModelContainer(
        for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    let fetcher = MockSimfileFetcher(all: [.stub(id: "x"), .stub(id: "y")])
    let service = ServerSongService(cache: ServerSongCache(fetcher: fetcher, pageSize: 50))
    service.setModelContext(ModelContext(container))

    await service.refreshCatalog()

    let songs = await service.loadServerSongs()
    #expect(Set(songs.map(\.songId)) == ["x", "y"])
}
```

- [ ] **Step 2: Run, verify fail.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongServiceTests/testServiceRefreshCatalog ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: compile failure — no `refreshCatalog`, and `ServerSongService(cache:)` signature changed.

- [ ] **Step 3: Update `ServerSongService`.** Change the init and refresh methods in `Virgo/utilities/ServerSongService.swift`:
  - Replace the stored `cache`/`downloader`/`statusManager` defaults so the default `init()` builds an Apollo-backed cache:
    ```swift
    init(
        config: ServerConfig = ServerConfig(),
        cache: ServerSongCache? = nil,
        downloader: ServerSongDownloader = ServerSongDownloader(),
        statusManager: ServerSongStatusManager = ServerSongStatusManager(),
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.downloader = downloader
        self.statusManager = statusManager
        self.saveModelContext = saveModelContext
        self.cache = cache ?? ServerSongCache(
            fetcher: ApolloSimfileClient(endpointURL: config.graphQLEndpoint),
            statusManager: statusManager,
            saveContext: saveModelContext
        )
    }
    ```
  - Replace `refreshServerSongs()`/`forceRefreshServerSongs()`/`private refreshServerSongs(forceClear:)` with a single:
    ```swift
    func refreshCatalog() async {
        guard let modelContext else { return }
        isRefreshing = true
        errorMessage = nil
        do {
            try await cache.refreshCatalog(modelContext: modelContext)
        } catch {
            errorMessage = "Failed to refresh server songs: \(error.localizedDescription)"
            Logger.debug("Failed to refresh catalog: \(error)")
        }
        isRefreshing = false
    }
    ```
  - Keep `loadServerSongs()`, `downloadAndImportSong`, `deleteDownloadedSong`, `deleteLocalSong`, helpers unchanged (they already use `cache`/`statusManager`).

- [ ] **Step 4: Update the button** in `Virgo/views/SongsTabView.swift`: replace both `await serverSongService.refreshServerSongs()` (line ~79) and the long-press `await serverSongService.forceRefreshServerSongs()` (line ~98) with `await serverSongService.refreshCatalog()` (remove the `.onLongPressGesture { ... }` block — there is no separate force-refresh anymore). Update the empty-state copy in `ServerSongsView.swift` if desired ("Tap the refresh button to load songs from the server" still applies).

- [ ] **Step 5: Run service test + build app, verify pass.**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/ServerSongServiceTests ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData 2>&1 | tail -20`
Expected: suite passes. Then `xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build 2>&1 | tail -10` → `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit.**
```bash
git add Virgo/utilities/ServerSongService.swift Virgo/views/SongsTabView.swift Virgo/views/ServerSongsView.swift VirgoTests/ServerSongServiceTests.swift
git commit -m "feat: manual refreshCatalog facade + Apollo wiring + button update"
```

---

## Task 14: Full verification

**Files:** none (verification only)

- [ ] **Step 1: SwiftLint clean.**

Run: `swiftlint lint 2>&1 | tail -20`
Expected: no violations (fix any line-length/size violations introduced).

- [ ] **Step 2: Full unit test run.**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -derivedDataPath ./DerivedData 2>&1 | tail -40
```
Expected: all suites pass except the known pre-existing `\Chart.difficulty` flaky crash documented in MEMORY. Confirm every new suite (DifficultyClassifier, ServerConfig, SimfileMapper, ServerSongCatalogRefresh, ServerSongDownloaderDecode, ServerSongService) is green.

- [ ] **Step 3: macOS build of the app target.**

Run: `xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Final commit (if any lint fixes).**
```bash
git add -A
git commit -m "chore: lint and verification fixes for simfile GraphQL integration"
```

---

## Self-Review

**Spec coverage:**
- §3 Apollo client + endpoint config → Tasks 1, 4, 5, 13. Anonymous `scope: PUBLISHED` baked into `SimfilesQuery.graphql` (Task 1). ✅
- §4/§5 public (unsigned) URLs; chart via `fileUrl`; BGM/preview assembled `{R2}/{id}/...`; availability from `files[]` → Tasks 7, 11. ✅
- §6 schema field consumption (genre/duration/updatedAt/tags/encoding) → DTOs (Task 3), model fields (Task 2), mapper (Task 7). Note: `tags` is carried in the DTO but not yet persisted on `ServerSong` (no consumer in v1 UI) — acceptable per YAGNI; flagged here. 
- §7 difficulty derivation → Task 6, used in Task 7. ✅
- §8 two queries + page-walk → Tasks 1, 4, 9. ✅
- §8 caching: manual refresh, additive, never overwrite existing, prune-all-stale incl. local files → Tasks 9, 10, 13. ✅
- §9 errors surfaced via `errorMessage` → `SimfileGraphQLError` (Task 4) + service catch (Task 13). ✅
- §10 adapter architecture, REST removal → Tasks 3–13, 12. ✅

**Placeholder scan:** No "TBD/TODO" in steps. The two coupled tasks (9/10) call this out explicitly with a stub fallback. The `level` scale assumption (0–100) is stated in `DifficultyClassifier` with adjustment guidance, tracking spec Open Question 1.

**Type consistency:** `SimfileFetching` (Tasks 3/4/8/9/13), `SimfileDTO`/`DtxFileDTO`/`SimfilePage` (Tasks 3/4/7/8), `ServerSongCache(fetcher:statusManager:pageSize:saveContext:)` + `refreshCatalog` (Tasks 9/13), `pruneCachedSong` (Tasks 9/10), `FileDownloading.downloadData(from:)` (Tasks 11/12), `ServerConfig.graphQLEndpoint`/`r2BaseURL` (Tasks 5/13), `ServerSong` init with `genre`/`durationSeconds` (Tasks 2/7), `SimfileMapper.makeServerSong/bgmURL/previewURL` (Tasks 7/11) — all consistent.

**Known risk:** Task 1 (Apollo SPM + codegen) is environment-dependent and the only task without a unit test; verify generated accessor names and adjust Task 4 mapping if they differ. Everything downstream is insulated by the DTO seam.
