# Songs Tab Card-Grid Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render both Songs sub-tabs (Downloaded + Server) as a card grid on wide widths (full-screen iPad / macOS) and keep today's compact rows when narrow, with Downloaded cards opening a difficulty-picker sheet that launches gameplay.

**Architecture:** Each sub-tab content view (`DownloadedSongsView`, `ServerSongsView`) becomes a thin dispatcher that picks `.grid` or `.rows` from the available width via the pure `SongsLayoutMode` enum, measured with a wrapping `GeometryReader` (safe here because both the `List` and the grid's `ScrollView` fill the offered space — unlike a content-hugging `VStack`). The grid reuses the existing async SwiftData relationship loading and the existing `DifficultyExpansionView` (inside a sheet for Downloaded). No `ContentView` or `SongsTabView` signature changes.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (unit), XCUITest (UI). Engraved design system: `@Environment(\.theme)`, `Palette`, `AppType`, `Spacing`/`Radius`/`RuleWeight`, `TempoMark`, `DifficultyPips`, `RuleDivider`, `LedgerRow`, `GhostButtonStyle`.

## Global Constraints

- iPad-only for the iOS family (`TARGETED_DEVICE_FAMILY = 2`); macOS 14+ and iPadOS. No iPhone destinations/assumptions.
- Unit tests use **Swift Testing** only (`import Testing`, `#expect`, `@Suite`) — never XCTest in `VirgoTests`. UI tests in `VirgoUITests` use XCUITest (existing convention).
- **Never** edit `Virgo.xcodeproj/project.pbxproj`; Xcode 16 file-system-synchronized groups pick up new/deleted files automatically.
- New UI reads `@Environment(\.theme)` and uses design tokens only. No raw `Color.white/.black/.gray/.purple`; no rainbow difficulty colors (difficulty = `DifficultyPips`).
- Preserve existing accessibility identifiers that back current behavior; add the new ones named in this plan verbatim.
- Load SwiftData relationships via `.loadSongRelationships(for:)` — never fault `song.charts`/`chart.notes` synchronously during view construction.
- Build/lint/test results are authoritative; ignore stale SourceKit "cannot find type" diagnostics (a known same-module index artifact on this branch).
- Verification runs sequentially; never share `-derivedDataPath` across concurrent `xcodebuild`. Tests run with `-parallel-testing-enabled NO`.
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013d9nW77M3PamgkL7GnWCyd
  ```

## Reference Signatures (already in the codebase — consume, don't redefine)

- `SongRelationshipData { let chartCount: Int; let measureCount: Int; let charts: [Chart]; let availableDifficulties: [Difficulty] }`
- `extension View { func loadSongRelationships(for song: Song, onDataLoaded: @escaping (SongRelationshipData) -> Void) -> some View }`
- `SongRelationshipLoader.isModelAvailable(_ chart: Chart) -> Bool` / `isModelAvailable(_ song: Song) -> Bool`
- `DifficultyPips(difficulty: Difficulty, showLabel: Bool = true)`
- `TempoMark(bpm: Int)` — note `Song.bpm` is `Double`, so pass `Int(song.bpm)`.
- `RuleDivider()`, `LedgerRow { content }`, `GhostButtonStyle()`
- `DifficultyExpansionView(charts: [Chart], onChartSelect: (Chart) -> Void)` — renders the "Select Difficulty" header and `ChartSelectionCard`s with identifiers `chartDifficulty<rawValue>` / `chartScores<rawValue>`. **Reuse unchanged.**
- `PersistentIdentifierPersistenceKey.canonicalKey(for: PersistentIdentifier, logPrefix: String) -> String` (used by `DownloadedSongsView.rowViewID`).
- Tokens: `Spacing.{xs=4,sm=8,md=16,lg=24,xl=40}`, `Radius.{sm=6,md=12}`, `RuleWeight.hairline=1`, `AppType.{headline,title,...}`.
- `Song`: `title`, `artist`, `bpm: Double`, `genre`, `duration`, `timeSignature`, `isSaved`, `isServerImported`, `previewFilePath`, `persistentModelID`.
- `ServerSong`: `songId`, `title`, `artist`, `bpm: Double`, `charts` (each `.level`, `.size`, `.difficultyLabel`), `isDownloaded`, `hasBGM`, `bgmDownloaded`, `hasPreview`, `previewDownloaded`.
- `ServerSongService`: `isDeleting(_:)`, `deleteLocalSong(_:) async -> Bool`, `isDownloading(_:)`, `downloadAndImportSong(_:) async`.

---

### Task 1: Responsive layout primitive (`SongsLayoutMode`) + unit tests

**Files:**
- Create: `Virgo/layout/SongsResponsiveLayout.swift`
- Test: `VirgoTests/SongsLayoutModeTests.swift`

**Interfaces:**
- Produces: `enum SongsLayoutMode { case rows, grid; static let gridMinWidth: CGFloat; static func forWidth(_ width: CGFloat) -> SongsLayoutMode }` and `enum SongsGrid { static let columns: [GridItem] }`.

- [ ] **Step 1: Write the failing test**

`VirgoTests/SongsLayoutModeTests.swift`:
```swift
import Testing
import Foundation
@testable import Virgo

@Suite("SongsLayoutMode")
struct SongsLayoutModeTests {
    @Test("width below threshold uses rows")
    func narrowUsesRows() {
        #expect(SongsLayoutMode.forWidth(699) == .rows)
    }

    @Test("width at threshold uses grid")
    func thresholdUsesGrid() {
        #expect(SongsLayoutMode.forWidth(SongsLayoutMode.gridMinWidth) == .grid)
        #expect(SongsLayoutMode.forWidth(700) == .grid)
    }

    @Test("wide width uses grid")
    func wideUsesGrid() {
        #expect(SongsLayoutMode.forWidth(1366) == .grid)
    }

    @Test("zero width falls back to rows")
    func zeroUsesRows() {
        #expect(SongsLayoutMode.forWidth(0) == .rows)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/SongsLayoutMode -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: FAIL to compile — "Cannot find 'SongsLayoutMode' in scope".

- [ ] **Step 3: Write the implementation**

`Virgo/layout/SongsResponsiveLayout.swift`:
```swift
//
//  SongsResponsiveLayout.swift
//  Virgo
//
//  Responsive layout decision for the Songs tab: a multi-column card grid on
//  wide widths, compact rows when narrow. The mode is a pure function of the
//  available content width so it can be unit-tested without rendering.
//

import SwiftUI

enum SongsLayoutMode: Equatable {
    case rows
    case grid

    /// Minimum content width that warrants a multi-column card grid. Below this
    /// (e.g. iPad Split View / Slide Over) the compact row list is used.
    static let gridMinWidth: CGFloat = 700

    static func forWidth(_ width: CGFloat) -> SongsLayoutMode {
        width >= gridMinWidth ? .grid : .rows
    }
}

enum SongsGrid {
    /// Adaptive columns: ~2 at 700pt, 3-4 on full iPad/macOS. No manual math.
    static let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: Spacing.md)
    ]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command. Expected: TEST SUCCEEDED, 4 tests in the `SongsLayoutMode` suite passing.

- [ ] **Step 5: Commit**

```bash
git add Virgo/layout/SongsResponsiveLayout.swift VirgoTests/SongsLayoutModeTests.swift
git commit -m "feat(songs): add SongsLayoutMode responsive primitive"
# (append the standard trailers)
```

---

### Task 2: `SongCard` — Downloaded card cell

**Files:**
- Create: `Virgo/components/SongCard.swift`

**Interfaces:**
- Consumes: `SongRelationshipData`, `loadSongRelationships`, `DifficultyPips`, `TempoMark`, `RuleDivider`, `PersistentIdentifierPersistenceKey`, tokens.
- Produces: `SongCard(song:isPlaying:isDeleting:onOpen:onPlayTap:onSaveTap:onDelete:)` and `static func cardViewID(for: Song) -> String` (returns `"downloadedSongCard-<stableID>"`).

- [ ] **Step 1: Write the implementation**

There is no pure logic to unit-test here (it is a SwiftUI view); verification is a successful build plus the in-file `#Preview`. `Virgo/components/SongCard.swift`:
```swift
//
//  SongCard.swift
//  Virgo
//
//  Downloaded-song card for the wide-width grid layout. Tapping the info area
//  opens the difficulty picker; footer buttons handle play/save/delete inline.
//

import SwiftUI
import SwiftData

struct SongCard: View {
    let song: Song
    let isPlaying: Bool
    let isDeleting: Bool
    let onOpen: () -> Void
    let onPlayTap: () -> Void
    let onSaveTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    @State private var chartCount: Int = 0
    @State private var availableDifficulties: [Difficulty] = []

    static func cardViewID(for song: Song) -> String {
        let stableSongID = PersistentIdentifierPersistenceKey.canonicalKey(
            for: song.persistentModelID,
            logPrefix: "SongCard"
        )
        return "downloadedSongCard-\(stableSongID)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            infoButton
            RuleDivider()
            footer
        }
        .padding(Spacing.md)
        .background(isPlaying ? theme.accent.opacity(0.12) : theme.raised)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(theme.rule, lineWidth: RuleWeight.hairline)
        )
        .loadSongRelationships(for: song) { data in
            chartCount = data.chartCount
            availableDifficulties = data.availableDifficulties
        }
        .accessibilityIdentifier(Self.cardViewID(for: song))
    }

    private var infoButton: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(song.title)
                    .font(AppType.headline)
                    .foregroundColor(theme.primary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(theme.secondary)
                    .lineLimit(1)
                HStack(spacing: Spacing.sm) {
                    TempoMark(bpm: Int(song.bpm))
                    Text(song.genre)
                        .font(.plexMono(11))
                        .foregroundColor(theme.secondary)
                        .lineLimit(1)
                }
                difficultyPipsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("downloadedSongCardOpenButton")
        .accessibilityLabel("Open \(song.title)")
    }

    private var difficultyPipsRow: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(availableDifficulties, id: \.self) { difficulty in
                DifficultyPips(difficulty: difficulty, showLabel: false)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onPlayTap) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isPlaying ? theme.accent : theme.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(action: onSaveTap) {
                Image(systemName: song.isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(song.isSaved ? theme.accent : theme.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(song.isSaved ? "Remove bookmark" : "Save song")
            .accessibilityIdentifier("downloadedSongBookmarkButton")
            .accessibilityValue(song.isSaved ? "Saved" : "Not saved")

            Text("\(chartCount) charts")
                .font(.caption2)
                .foregroundColor(theme.secondary)

            Spacer()

            deleteControl
        }
    }

    @ViewBuilder
    private var deleteControl: some View {
        if isDeleting {
            HStack(spacing: Spacing.sm) {
                ProgressView().scaleEffect(0.8)
                Text("Deleting...")
                    .font(.caption)
                    .foregroundColor(theme.secondary)
            }
        } else {
            Button("Delete", action: onDelete)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(theme.accent)
                .accessibilityIdentifier("downloadedSongDeleteButton")
        }
    }
}
```

- [ ] **Step 2: Verify the build (macOS + iPad sim)**

Run sequentially:
```bash
swiftlint lint
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
```
Expected: SwiftLint no new violations; both builds BUILD SUCCEEDED. (The M5 iPad sim is installed; the M4 named in CLAUDE.md is not.)

- [ ] **Step 3: Commit**

```bash
git add Virgo/components/SongCard.swift
git commit -m "feat(songs): add SongCard downloaded grid cell"
# (trailers)
```

---

### Task 3: `DifficultyPickerSheet`

**Files:**
- Create: `Virgo/views/subviews/DifficultyPickerSheet.swift`

**Interfaces:**
- Consumes: `DifficultyExpansionView`, `loadSongRelationships`, `SongRelationshipLoader.isModelAvailable`, `GhostButtonStyle`, `.surface(.paper)`.
- Produces: `DifficultyPickerSheet(song:onChartSelect:onDismiss:)`.

- [ ] **Step 1: Write the implementation**

`Virgo/views/subviews/DifficultyPickerSheet.swift`:
```swift
//
//  DifficultyPickerSheet.swift
//  Virgo
//
//  Sheet for picking a difficulty (chart) for a downloaded song in the grid
//  layout. Reuses DifficultyExpansionView. Charts load asynchronously to avoid
//  synchronous SwiftData faulting.
//

import SwiftUI
import SwiftData

struct DifficultyPickerSheet: View {
    let song: Song
    let onChartSelect: (Chart) -> Void
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @State private var charts: [Chart] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            ScrollView {
                DifficultyExpansionView(charts: displayCharts) { chart in
                    onDismiss()
                    onChartSelect(chart)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .surface(.paper)
        .loadSongRelationships(for: song) { data in
            charts = data.charts
        }
    }

    private var displayCharts: [Chart] {
        charts.filter { SongRelationshipLoader.isModelAvailable($0) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(song.title)
                    .font(AppType.title)
                    .foregroundColor(theme.primary)
                    .lineLimit(1)
                Text("Choose difficulty")
                    .font(.plexMono(12))
                    .foregroundColor(theme.secondary)
            }
            Spacer()
            Button("Done", action: onDismiss)
                .buttonStyle(GhostButtonStyle())
                .accessibilityIdentifier("difficultyPickerDoneButton")
        }
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
swiftlint lint
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```
Expected: no new lint violations; BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Virgo/views/subviews/DifficultyPickerSheet.swift
git commit -m "feat(songs): add DifficultyPickerSheet for grid chart selection"
# (trailers)
```

---

### Task 4: Downloaded dispatcher + grid

**Files:**
- Modify: `Virgo/views/DownloadedSongsView.swift` (the `DownloadedSongsView` struct only; leave `DownloadedSongRowWithDelete` unchanged)

**Interfaces:**
- Consumes: `SongsLayoutMode`, `SongsGrid.columns`, `SongCard`, `DifficultyPickerSheet`.
- Produces: no new external interface; `DownloadedSongsView`'s init signature is unchanged.

- [ ] **Step 1: Replace the `DownloadedSongsView` `body` and add grid members**

In `Virgo/views/DownloadedSongsView.swift`, add a sheet-target type and state property to `DownloadedSongsView` (place the `@State` next to the other stored properties, after line 31's `let onSaveTap`):
```swift
    // Sheet target for the grid's difficulty picker. Identifiable wrapper keeps
    // `.sheet(item:)` independent of Song's own Identifiable conformance.
    private struct PickerTarget: Identifiable {
        let song: Song
        var id: PersistentIdentifier { song.persistentModelID }
    }
    @State private var pickerTarget: PickerTarget?
```

Replace the entire current `var body: some View { List { ... } ... }` (lines 54-103) with:
```swift
    var body: some View {
        GeometryReader { proxy in
            layout(for: SongsLayoutMode.forWidth(proxy.size.width))
        }
        .sheet(item: $pickerTarget) { target in
            DifficultyPickerSheet(
                song: target.song,
                onChartSelect: onChartSelect,
                onDismiss: { pickerTarget = nil }
            )
        }
    }

    @ViewBuilder
    private func layout(for mode: SongsLayoutMode) -> some View {
        switch mode {
        case .grid: downloadedGrid
        case .rows: downloadedList
        }
    }

    private var downloadedList: some View {
        List {
            if !downloadedSongs.isEmpty {
                ForEach(downloadedSongs, id: \.id) { song in
                    DownloadedSongRowWithDelete(
                        song: song,
                        isPlaying: isPlaying(song),
                        isExpanded: expandedSongId == song.persistentModelID,
                        isDeleting: serverSongService.isDeleting(song),
                        expandedSongId: $expandedSongId,
                        onChartSelect: onChartSelect,
                        onPlayTap: { onPlayTap(song) },
                        onSaveTap: { onSaveTap(song) },
                        onDelete: { deleteSong(song) }
                    )
                    .accessibilityIdentifier(Self.rowViewID(for: song))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                emptyState
                    .listRowBackground(Color.clear)
                    .id(Self.emptyStateViewID)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var downloadedGrid: some View {
        Group {
            if downloadedSongs.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(Self.emptyStateViewID)
            } else {
                ScrollView {
                    LazyVGrid(columns: SongsGrid.columns, spacing: Spacing.md) {
                        ForEach(downloadedSongs, id: \.id) { song in
                            SongCard(
                                song: song,
                                isPlaying: isPlaying(song),
                                isDeleting: serverSongService.isDeleting(song),
                                onOpen: { pickerTarget = PickerTarget(song: song) },
                                onPlayTap: { onPlayTap(song) },
                                onSaveTap: { onSaveTap(song) },
                                onDelete: { deleteSong(song) }
                            )
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 50))
                .foregroundColor(theme.secondary)

            Text("No Downloaded Songs")
                .font(.title2)
                .foregroundColor(theme.primary)

            Text("Download songs from the Server tab to see them here")
                .font(.body)
                .foregroundColor(theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func deleteSong(_ song: Song) {
        Task {
            let success = await serverSongService.deleteLocalSong(song)
            Logger.debug("Delete downloaded song result: \(success)")
        }
    }
```

Notes for the implementer:
- This extracts the inline delete closure into `deleteSong(_:)` so the row and grid share it (DRY); behavior is identical to the original closure.
- The empty-state copy and `emptyStateViewID` are preserved verbatim so existing empty-state UI tests still pass in both layouts.
- `expandedSongId` is still consumed by the row path; the grid path uses `pickerTarget` instead. Do not remove the `expandedSongId` binding.

- [ ] **Step 2: Verify build + existing unit suite**

```bash
swiftlint lint
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/SongsLayoutMode -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: no new lint violations; both builds BUILD SUCCEEDED; SongsLayoutMode suite still green.

- [ ] **Step 3: Commit**

```bash
git add Virgo/views/DownloadedSongsView.swift
git commit -m "feat(songs): card grid for downloaded songs on wide widths"
# (trailers)
```

---

### Task 5: `ServerSongCard` + Server dispatcher (with shared info/status extraction)

**Files:**
- Create: `Virgo/components/ServerSongCard.swift`
- Modify: `Virgo/components/ServerSongRow.swift` (extract shared subviews; keep its row container)
- Modify: `Virgo/views/ServerSongsView.swift` (dispatcher)

**Interfaces:**
- Produces: `ServerSongInfoView(serverSong:)`, `ServerSongStatusView(serverSong:isLoading:onDownload:)`, `ServerSongCard(serverSong:isLoading:onDownload:)`.
- Consumes: `SongsLayoutMode`, `SongsGrid.columns`.

- [ ] **Step 1: Extract shared views from `ServerSongRow.swift`**

Replace the contents of `Virgo/components/ServerSongRow.swift` with the row reduced to a container plus two reusable views (the info and status bodies are moved verbatim from the current implementation, only their enclosing type changes):
```swift
//
//  ServerSongRow.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftUI
import SwiftData

// MARK: - Server Song Row (narrow layout)
struct ServerSongRow: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void

    var body: some View {
        LedgerRow {
            HStack {
                ServerSongInfoView(serverSong: serverSong)
                Spacer()
                ServerSongStatusView(
                    serverSong: serverSong,
                    isLoading: isLoading,
                    onDownload: onDownload
                )
            }
        }
    }
}

// MARK: - Shared Info Section
struct ServerSongInfoView: View {
    let serverSong: ServerSong
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(serverSong.title)
                .font(AppType.headline)
                .foregroundColor(theme.primary)
                .lineLimit(1)
            Text("by \(serverSong.artist)")
                .font(.subheadline)
                .foregroundColor(theme.secondary)
                .lineLimit(1)
            metadataRow
            difficultyChips
        }
    }

    private var metadataRow: some View {
        HStack {
            let bpmText = serverSong.bpm.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", serverSong.bpm)
                : String(format: "%.2f", serverSong.bpm)
            Label("\(bpmText) BPM", systemImage: "metronome")
                .font(.plexMono(11))
                .foregroundColor(theme.secondary)
            levelLabel
            Spacer()
            let totalSize = serverSong.charts.reduce(0) { $0 + $1.size }
            Text(formatFileSize(totalSize))
                .font(.plexMono(11))
                .foregroundColor(theme.secondary)
        }
    }

    @ViewBuilder
    private var levelLabel: some View {
        if serverSong.charts.count > 1 {
            let levels = serverSong.charts.map { String($0.level) }.joined(separator: ", ")
            Label("Levels \(levels)", systemImage: "chart.bar")
                .font(.plexMono(11))
                .foregroundColor(theme.secondary)
        } else if let chart = serverSong.charts.first {
            Label("Level \(chart.level)", systemImage: "chart.bar")
                .font(.plexMono(11))
                .foregroundColor(theme.secondary)
        }
    }

    @ViewBuilder
    private var difficultyChips: some View {
        if serverSong.charts.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(serverSong.charts.indices, id: \.self) { index in
                        let chart = serverSong.charts[index]
                        Text("\(chart.difficultyLabel) (\(chart.level))")
                            .font(.plexMono(10, weight: .medium))
                            .tracking(1)
                            .foregroundColor(theme.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.rule, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Shared Status Section
struct ServerSongStatusView: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        if serverSong.isDownloaded {
            downloadedIndicator
        } else if isLoading {
            loadingIndicator
        } else {
            Button("Download") { onDownload() }
                .buttonStyle(GhostButtonStyle())
                .controlSize(.small)
                .disabled(isLoading)
        }
    }

    private var downloadedIndicator: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(theme.accent)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(theme.accent)
                    Text("Charts")
                        .font(.caption2)
                        .foregroundColor(theme.accent)
                }
                if serverSong.hasBGM {
                    HStack(spacing: 4) {
                        Image(systemName: serverSong.bgmDownloaded ?
                              "waveform" : "waveform.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundColor(serverSong.bgmDownloaded ? theme.accent : theme.secondary)
                        Text("BGM")
                            .font(.caption2)
                            .foregroundColor(serverSong.bgmDownloaded ? theme.accent : theme.secondary)
                    }
                }
                if serverSong.hasPreview {
                    HStack(spacing: 4) {
                        Image(systemName: serverSong.previewDownloaded ?
                              "play.circle" : "play.circle.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundColor(serverSong.previewDownloaded ? theme.accent : theme.secondary)
                        Text("Preview")
                            .font(.caption2)
                            .foregroundColor(serverSong.previewDownloaded ? theme.accent : theme.secondary)
                    }
                }
            }
        }
    }

    private var loadingIndicator: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Downloading...")
                    .font(.caption)
                    .foregroundColor(theme.secondary)
            }
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(theme.secondary)
                    Text("Chart files")
                        .font(.caption2)
                        .foregroundColor(theme.secondary)
                }
                if serverSong.hasBGM {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                        Text("Background music")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                    }
                }
                if serverSong.hasPreview {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                        Text("Preview audio")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                    }
                }
            }
        }
    }
}
```
This is a pure refactor — `ServerSongRow`'s rendered output is unchanged; the info and status bodies are identical to the originals, just relocated into `ServerSongInfoView` / `ServerSongStatusView`. `ServerSongStatusView.body` uses an implicit-`if` `some View` body (no explicit `@ViewBuilder` needed; the `if/else if/else` is allowed in a `body`).

- [ ] **Step 2: Create `ServerSongCard.swift`**

`Virgo/components/ServerSongCard.swift`:
```swift
//
//  ServerSongCard.swift
//  Virgo
//
//  Server-song card for the wide-width grid layout. Reuses ServerSongInfoView
//  and ServerSongStatusView so the card and row stay in sync.
//

import SwiftUI
import SwiftData

struct ServerSongCard: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ServerSongInfoView(serverSong: serverSong)
            RuleDivider()
            HStack {
                Spacer()
                ServerSongStatusView(
                    serverSong: serverSong,
                    isLoading: isLoading,
                    onDownload: onDownload
                )
            }
        }
        .padding(Spacing.md)
        .background(theme.raised)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(theme.rule, lineWidth: RuleWeight.hairline)
        )
        .accessibilityIdentifier("serverSongCard-\(serverSong.songId)")
    }
}
```

- [ ] **Step 3: Add the dispatcher to `ServerSongsView.swift`**

Replace the `var body: some View { List { ... } ... }` (lines 17-65) of `ServerSongsView` with:
```swift
    var body: some View {
        GeometryReader { proxy in
            layout(for: SongsLayoutMode.forWidth(proxy.size.width))
        }
    }

    @ViewBuilder
    private func layout(for mode: SongsLayoutMode) -> some View {
        switch mode {
        case .grid: serverGrid
        case .rows: serverList
        }
    }

    private var serverList: some View {
        List {
            if !serverSongs.isEmpty {
                ForEach(serverSongs, id: \.songId) { serverSong in
                    ServerSongRow(
                        serverSong: serverSong,
                        isLoading: serverSongService.isDownloading(serverSong),
                        onDownload: { downloadSong(serverSong) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else if serverSongService.isRefreshing {
                loadingRow.listRowBackground(Color.clear)
            } else {
                emptyState.listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var serverGrid: some View {
        Group {
            if serverSongs.isEmpty {
                (serverSongService.isRefreshing ? AnyView(loadingRow) : AnyView(emptyState))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: SongsGrid.columns, spacing: Spacing.md) {
                        ForEach(serverSongs, id: \.songId) { serverSong in
                            ServerSongCard(
                                serverSong: serverSong,
                                isLoading: serverSongService.isDownloading(serverSong),
                                onDownload: { downloadSong(serverSong) }
                            )
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            ProgressView().scaleEffect(0.8)
            Text("Loading server songs...")
                .foregroundColor(theme.secondary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 50))
                .foregroundColor(theme.secondary)
            Text("No Server Songs")
                .font(.title2)
                .foregroundColor(theme.primary)
            Text("Tap the refresh button to load songs from the server")
                .font(.body)
                .foregroundColor(theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func downloadSong(_ serverSong: ServerSong) {
        Task {
            await serverSongService.downloadAndImportSong(serverSong)
        }
    }
```
Empty-state and loading copy are preserved verbatim from the original so server UI tests still pass.

- [ ] **Step 4: Verify build (macOS + iPad sim)**

```bash
swiftlint lint
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
```
Expected: no new lint violations; both builds BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Virgo/components/ServerSongRow.swift Virgo/components/ServerSongCard.swift Virgo/views/ServerSongsView.swift
git commit -m "feat(songs): card grid for server songs on wide widths"
# (trailers)
```

---

### Task 6: Update UI tests for the grid path (macOS)

**Files:**
- Modify: `VirgoUITests/UITestHelpers+SongRow.swift` (make `expandSongRow` open the grid card)
- Modify: `VirgoUITests/SongsTabUITests.swift` (`testDownloadedSongExpansion`, `testDownloadedSongsExposeStableRowAccessibilityIdentifier`)

**Background:** `ui-tests.yml` runs on macOS, whose window is wide → the new grid renders (not rows). The difficulty picker sheet reuses `DifficultyExpansionView`, so the "Select Difficulty" header and `chartDifficulty<X>` / `chartScores<X>` identifiers are unchanged — only the *trigger* changes (tap the card's open button instead of a "N charts" expand button), and the row container identifier becomes the card identifier.

- [ ] **Step 1: Update `expandSongRow` to drive the card → picker sheet**

Replace the body of `expandSongRow(containing:in:timeout:file:line:)` (after the title-existence guard, lines 53-77) with logic that prefers the grid card's open button and falls back to the row expand button:
```swift
        // Wide layouts (macOS / full-screen iPad) render a card grid: tap the
        // card's open button. Narrow layouts render rows with a "N charts"
        // expand button. Try the card path first, then fall back to rows.
        let openCardButton = app.buttons
            .matching(NSPredicate(format: "label == %@", "Open \(songTitle)"))
            .firstMatch
        if openCardButton.waitForExistence(timeout: 3) {
            openCardButton.tap()
        } else {
            let nonZeroChartCount = NSPredicate(format: "label MATCHES[c] %@", ".*[1-9][0-9]* charts.*")
            let expandButton = app.buttons.matching(nonZeroChartCount).firstMatch
            guard expandButton.waitForExistence(timeout: timeout) else {
                XCTFail(
                    "Expected card open button or expand button for song \"\(songTitle)\"",
                    file: file,
                    line: line
                )
                throw UITestFailure.elementNotFound("open/expand control for \(songTitle)")
            }
            expandButton.tap()
        }

        XCTAssertTrue(
            waitForStaticText(containing: "Select Difficulty", in: app, timeout: timeout),
            "Difficulty selector should appear after opening \(songTitle)",
            file: file, line: line
        )
```

- [ ] **Step 2: Rewrite `testDownloadedSongExpansion` for the sheet**

Replace the `testDownloadedSongExpansion()` body (lines 168-194) with a version that opens the card and dismisses the picker sheet (there is no inline collapse in the grid):
```swift
    @MainActor
    func testDownloadedSongExpansion() throws {
        try tapStartButton()

        XCTAssertTrue(switchToDownloadedTab(app: app))

        guard hasDownloadedSongs(app: app) else { return }

        // Open the first card's picker (card path) or the first row (row path).
        let openButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Open ")
        ).firstMatch
        if openButton.waitForExistence(timeout: 5) {
            openButton.tap()
        } else {
            let chartIndicator = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'charts'")
            ).firstMatch
            guard chartIndicator.waitForExistence(timeout: 5) else { return }
            chartIndicator.tap()
        }

        // The difficulty selector appears (same DifficultyExpansionView in both).
        XCTAssertTrue(waitForStaticText(containing: "Select Difficulty", in: app, timeout: 5))
        let difficultyButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "chartDifficulty")
        ).firstMatch
        XCTAssertTrue(difficultyButton.waitForExistence(timeout: 3))

        // Dismiss the picker sheet if present (grid path); harmless if absent.
        let done = app.buttons["difficultyPickerDoneButton"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 3), "Picker sheet should dismiss on Done")
        }
    }
```

- [ ] **Step 3: Generalize the stable-identifier regression test**

In `testDownloadedSongsExposeStableRowAccessibilityIdentifier`, replace the `rowIdentifierPredicate` (line 136) so it accepts either layout's stable identifier:
```swift
        let rowIdentifierPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
            "downloaded-song-row-",
            "downloadedSongCard-"
        )
```
Leave the rest of the test (the `hasDownloadedSongs` guard and the `firstMatch.waitForExistence` assertion) unchanged; update the failure message to mention both prefixes.

- [ ] **Step 4: Run the affected UI tests on macOS**

UI tests are heavy; run just the affected class (sequential, no shared derived-data contention):
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoUITests/SongsTabUITests -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: TEST SUCCEEDED.

`ServerSongsUITests` needs **no changes**: it only asserts the refresh button (`refreshServerSongsButton`), the empty-state copy ("No Server Songs" / "Tap the refresh button…"), the "songs available" count, the `searchField`/`clearSearchButton`, and sub-tab switching — all of which live in `SongsTabView` or the preserved empty-state copy and are independent of the row-vs-card layout. Run it once to confirm it stays green:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoUITests/ServerSongsUITests -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

- [ ] **Step 5: Commit**

```bash
git add VirgoUITests/UITestHelpers+SongRow.swift VirgoUITests/SongsTabUITests.swift
git commit -m "test(songs): drive card grid + difficulty picker in UI tests"
# (trailers)
```

---

## Notes for the Executor

- After all tasks: run the full unit suite once on macOS (`-only-testing:VirgoTests`, `-parallel-testing-enabled NO`). Expect the pre-existing flaky `\Chart.difficulty`-detached SwiftData test may be red on `main` too — it is not a regression from this work.
- This branch (`redesign/engraved-ui`) is where the work lands per the user's instruction — do not branch off.
- The `GeometryReader`-wrapping width measurement is deliberate and safe: `List`/`ScrollView` fill the offered size, so there is no content-hugging collapse (the bug that affected the splash screen, which wrapped a `VStack`).
