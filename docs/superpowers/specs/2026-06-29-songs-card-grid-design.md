# Songs Tab Card-Grid Layout — Design

**Date:** 2026-06-29
**Status:** Approved (design); spec under review
**Branch context:** Builds on the `redesign/engraved-ui` (Engraved) design system — `@Environment(\.theme)`, `Palette`, `AppType`, `Spacing`/`Radius`, `TempoMark`, `DifficultyPips`, `LedgerRow`, `GhostButtonStyle`, `.surface(.paper)`.

## Goal

On wide widths (full-screen iPad, macOS), render **both** Songs sub-tabs (Downloaded + Server) as a card grid instead of a vertical row list. On narrow widths (iPad Split View / Slide Over), keep today's compact rows. Tapping a Downloaded card opens a difficulty-picker sheet that launches gameplay; Server cards keep their download/state actions inline.

## Architecture

Each sub-tab content view (`DownloadedSongsView`, `ServerSongsView`) becomes a thin **layout dispatcher**: it measures the available content width and renders either the existing row `List` (narrow) or a new `LazyVGrid` of cards (wide). The two layouts share the same inputs and the same per-song async relationship loading. No change to `ContentView`'s call sites or the `SongsTabView` public surface.

The wide/narrow decision is a **pure, testable function of width** — not device type and not `horizontalSizeClass` (the latter is unreliable/absent on macOS, and width is what correctly distinguishes iPad multitasking widths).

## Global Constraints

- iPad-only for the iOS family (`TARGETED_DEVICE_FAMILY = 2`); macOS 14+ and iPadOS. No iPhone assumptions.
- Swift Testing only in `VirgoTests` (`import Testing`, `#expect`, `@Suite`) — never XCTest.
- Never edit `Virgo.xcodeproj/project.pbxproj`; Xcode 16 file-system-synchronized groups pick up new/deleted files automatically.
- All new UI reads `@Environment(\.theme)` and uses existing design tokens (`Palette`/`AppType`/`Spacing`/`Radius`) — no raw `Color.white/.black/.gray/.purple`, no rainbow difficulty colors (difficulty = `DifficultyPips`).
- Preserve every existing accessibility identifier that backs current behavior; add parallel identifiers for the new card path.
- SwiftData relationships (`song.charts`, `chart.notes`) must be loaded via the async `.loadSongRelationships(for:)` caching pattern — never faulted synchronously during view construction.
- Disable parallel testing for any `xcodebuild test` run (`-parallel-testing-enabled NO`).

## Responsive Switch

A pure enum encodes the decision and the column layout so it can be unit-tested without rendering:

```swift
enum SongsLayoutMode: Equatable {
    case rows
    case grid

    /// Grid when the content has room for a multi-column card layout.
    static let gridMinWidth: CGFloat = 700

    static func forWidth(_ width: CGFloat) -> SongsLayoutMode {
        width >= gridMinWidth ? .grid : .rows
    }
}
```

- Grid columns are adaptive: `LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: Spacing.md)], spacing: Spacing.md)`. This yields ~2 columns at 700pt and 3–4 on full iPad/macOS, with no manual column math.
- Width is read with a **wrapping `GeometryReader`** in each dispatcher (`GeometryReader { proxy in layout(for: .forWidth(proxy.size.width)) }`). This is safe here because every branch the dispatcher returns fills the offered size — the `List` and the grid's `ScrollView` are both greedy, and the empty/loading states are explicitly `.frame(maxWidth: .infinity, maxHeight: .infinity)` — so the top-leading pinning that collapses a content-hugging `VStack` (the start-screen regression) cannot occur. This also yields the correct mode on the first layout pass, avoiding a rows→grid flash. (An earlier draft of this spec proposed a `.background(GeometryReader)` preference-key reader writing into `@State private var contentWidth`; the wrapping approach was adopted during planning/implementation because it is simpler and flash-free. This bullet reflects the implemented design.)
- The grid is wrapped in a `ScrollView`; the row path keeps its existing `List`.

## Components

### `SongCard` (Downloaded) — new, `Virgo/components/SongCard.swift`
Typographic card; no artwork exists in the model.

- Surface: `theme.raised` fill, `Radius` corner radius, 1pt `theme.rule` border.
- Content (vertical):
  - Title — `AppType.headline` (Fraunces), `theme.primary`, `lineLimit(1)`.
  - Artist — `.subheadline`, `theme.secondary`, `lineLimit(1)`.
  - A line with `TempoMark(bpm: song.bpm)` and genre (`.plexMono`, `theme.secondary`).
  - `DifficultyPips` row over `availableDifficulties` (`showLabel: false`).
  - Footer icon row: play/preview toggle (`play.circle.fill`/`pause.circle.fill`), bookmark (`bookmark`/`bookmark.fill`), a `"\(chartCount) charts"` hint, and Delete (or a `Deleting…` `ProgressView`).
- Interaction: the card body **excluding** the footer buttons is a tap target that sets the grid's `selectedSongForPicker`. Footer buttons call `onPlayTap` / `onSaveTap` / `onDelete` and do not open the picker.
- Async data via `.loadSongRelationships(for: song)` exactly like `DownloadedSongRowWithDelete` (chartCount, measureCount unused-on-card may be omitted, availableDifficulties).
- Accessibility: container id `downloadedSongCard-<stableID>` (stable id via `PersistentIdentifierPersistenceKey.canonicalKey`, mirroring `DownloadedSongsView.rowViewID`); reuse `downloadedSongBookmarkButton` / `downloadedSongDeleteButton` on the footer buttons; add `downloadedSongCardOpenButton` for the open-picker tap if a dedicated button is needed.

### `ServerSongCard` — new, `Virgo/components/ServerSongCard.swift`
Card form of `ServerSongRow` with identical data and the same status logic.

- Same surface treatment as `SongCard`.
- Content: title, `by <artist>`, BPM + level(s) label, difficulty chips (the existing wrapping/`ScrollView` chip row), total file size.
- Status section: reuse the existing three states — `Download` button (`GhostButtonStyle`), `Downloading…` indicator, and the downloaded ✓ indicator with Charts/BGM/Preview sub-rows. Same `isLoading` / `onDownload` inputs as `ServerSongRow`.
- Accessibility: reuse the Download button's behavior; add container id `serverSongCard-<songId>`.

### `DifficultyPickerSheet` — new, `Virgo/views/subviews/DifficultyPickerSheet.swift`
A `.sheet` content view presented from the Downloaded grid.

- Loads the selected song's charts via `.loadSongRelationships(for: song)` (authoritative source for the selectable charts), filtered with `SongRelationshipLoader.isModelAvailable`.
- Body: a title (e.g. song title + "Choose difficulty") over `.surface(.paper)`, then the **existing** `DifficultyExpansionView(charts:onChartSelect:)` unchanged.
- On chart select: dismiss the sheet, then call the grid's `onChartSelect(chart)` (the existing closure → `openGameplay` → full-screen `GameplayView`). Order: dismiss first so gameplay is not presented under a sheet.
- Reuses `DifficultyExpansionView`'s existing `chartDifficulty<rawValue>` identifiers; no new picker UI.

### Grids
`SongCardGrid` (Downloaded) and `ServerSongCardGrid` (Server) — may live inside `DownloadedSongsView.swift` / `ServerSongsView.swift` or as separate files. Each owns its `LazyVGrid` + `ScrollView`; the Downloaded grid owns `@State selectedSongForPicker: Song?` and the `.sheet(item:)` presenting `DifficultyPickerSheet`. Empty-state and loading views are shared with the row path (same copy/identifiers, including `DownloadedSongsView.emptyStateViewID`).

## Data Flow

1. `SongsTabView` (unchanged) → `DownloadedSongsView` / `ServerSongsView` with today's inputs.
2. Dispatcher reads `contentWidth` → `SongsLayoutMode.forWidth` → rows (`List`) or grid (`LazyVGrid`).
3. Downloaded grid: tap card → `selectedSongForPicker = song` → `.sheet(item:)` shows `DifficultyPickerSheet` → user picks a chart → sheet dismisses → `onChartSelect(chart)` → `openGameplay` swaps content to `GameplayView`.
4. Footer/inline actions (`onPlayTap`, `onSaveTap`, `onDelete`, server `onDownload`) reuse the existing closures verbatim.
5. `expandedSongId` continues to drive the narrow-row inline expansion; the grid path does not use it.

## Error Handling

- No new error surfaces. Server download/refresh errors keep flowing through `serverSongService.errorMessage` and the existing alert in `SongsTabView`.
- Empty state (no downloaded songs / no server songs / refreshing) renders the same messaging in both layouts.
- A song with zero available charts: its card still renders; opening the picker shows an empty `DifficultyExpansionView` (no charts to select) — acceptable and matches today's expand behavior.

## Accessibility

- Narrow (rows): identifiers unchanged (`downloaded-song-row-<id>`, `downloadedSongExpandButton`, `downloadedSongBookmarkButton`, `downloadedSongDeleteButton`, `searchField`, etc.).
- Wide (grid): new `downloadedSongCard-<id>` / `serverSongCard-<songId>`; reuse bookmark/delete/download identifiers so action assertions hold across layouts; picker reuses `chartDifficulty<rawValue>`.

## Testing

- **Unit (Swift Testing):** `SongsLayoutModeTests` — `forWidth(699) == .rows`, `forWidth(700) == .grid`, `forWidth(0) == .rows`, plus boundary values. If column count becomes a computed helper rather than `.adaptive`, test it too.
- **UI tests (`ui-tests.yml`, macOS, wide → grid):** the existing tests drive the row layout; on a wide macOS window they will now hit the grid. Update them to:
  - exercise the card → `DifficultyPickerSheet` → chart-select → gameplay path on wide widths, and
  - keep row-path coverage for narrow widths (drive via a narrow window/size if feasible, otherwise assert the row components still compile and the shared empty-state/search identifiers resolve).
  This is an explicit task, not an afterthought; it is the main breakage risk.

## Files

- **New:** `Virgo/layout/SongsLayoutMode.swift`, `Virgo/components/SongCard.swift`, `Virgo/components/ServerSongCard.swift`, `Virgo/views/subviews/DifficultyPickerSheet.swift` (grids inline in the `*View` files or as their own files).
- **Modify:** `Virgo/views/DownloadedSongsView.swift`, `Virgo/views/ServerSongsView.swift`, the macOS UI tests in `VirgoUITests`.
- **Test:** `VirgoTests/SongsLayoutModeTests.swift`.

## Out of Scope (YAGNI)

- No cover-art / image loading (not in the data model).
- No high-score badges on cards (not shown today).
- No change to gameplay, metronome, scoring, server download internals, or `ContentView` navigation.
- No merging/removing the Downloaded/Server sub-tab segmented control.
- No new difficulty-picker UI beyond reusing `DifficultyExpansionView`.
