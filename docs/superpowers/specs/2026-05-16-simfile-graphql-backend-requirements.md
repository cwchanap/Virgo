# Simfile GraphQL — Client Integration Spec

**Author:** Virgo client team
**Date:** 2026-05-16 (revised 2026-06-05 to match the delivered backend schema)
**Audience:** Virgo client engineers integrating against the delivered GraphQL backend
**Status:** Approved design — ready for implementation planning

> **Revision note.** This document started as a *requirements* doc describing what the
> client wanted from a not-yet-built GraphQL service. The backend now exists and its
> schema is checked in at `Virgo/schema.graphql`. This revision reframes the document
> as a **client integration spec**: it describes how the Virgo client consumes the
> *delivered* schema, the mappings and client-side derivations required to bridge the
> gap between that schema and the client's existing models, and the implementation
> approach. Where the delivered schema differs from the original wishlist, the schema
> wins.

## 1. Context

Virgo is a SwiftUI drum-notation/practice app (iOS 18.5+, macOS 14.0+). Today it talks
to a small standalone FastAPI server (`server/main.py`) over REST that lists DTX drum
charts and serves chart/BGM/preview files for download. That server is being retired.
Its responsibilities now live in an existing backend exposed as **GraphQL**, whose
schema is `Virgo/schema.graphql`.

This document describes **how the client reads from and downloads via** that GraphQL
API. It does not describe server-side ingestion, parsing, or storage.

## 2. Goals & non-goals

### Goals
- Browse a catalog of **published** drum simfiles and their DTX charts.
- Download the chart file (`.dtx`), full BGM audio (`.ogg`), and short preview clip
  (`.mp3`) for any simfile.
- Support paginated listing and substring search as the catalog grows.
- Consume richer metadata than the raw DTX files provide (genre, tags, duration,
  per-file encoding).
- Cache the catalog in SwiftData; refresh it **only on explicit user action** (a manual
  "re-fetch" control), never automatically.

### Non-goals (v1)
- **Auth.** No sign-in, `me`, magic-link, or `scope: MINE`. The client queries
  `scope: PUBLISHED` anonymously. (The backend supports auth; the client ignores it.)
- **Mutations** of any kind (`createSimfile`, `updateSimfile`, `deleteSimfile`,
  `upsertUserProfile`, `generateMagicLink`).
- `videoPreviewUrl`, `displayId`, `nextDisplayId`, `hasUploadedFiles`, `userId`,
  `isPublished` (implied by the PUBLISHED scope), `R2File.uploaded`.
- Ratings, comments, leaderboards, social features, real-time subscriptions.
- Backwards compatibility with the legacy REST endpoints (`/dtx/list`,
  `/dtx/metadata/{filename}`, `/dtx/download/...`). Those client code paths are removed.

## 3. Transport, auth & configuration

- **Transport:** HTTPS, single GraphQL endpoint (`POST <graphql-endpoint>`).
- **Auth:** None. Every query sends `scope: PUBLISHED`. No tokens, no headers.
- **GraphQL client:** **Apollo iOS** via Swift Package Manager, with code generation
  run against `Virgo/schema.graphql`. Generated operation/types live in a dedicated
  source folder.
- **Configuration (two values, both `UserDefaults`-backed, set later via env/config):**
  - **GraphQL endpoint URL** — replaces the current `DTXServerURL` default
    (`http://127.0.0.1:8001`). Same override/validation/reset semantics as today.
  - **R2 bucket base URL** — public base used to assemble audio URLs (Section 5).

## 4. File delivery contract

Binary files (DTX charts, BGM, preview audio) live in **Cloudflare R2** and are served
as **plain public URLs** — *not* signed, *not* expiring. The GraphQL API does not stream
binary data; the client downloads files directly with `URLSession`.

- **Chart `.dtx`:** the URL is provided by the schema as `DtxFile.fileUrl` (public).
  Download it directly. If a chart's file is unavailable, the field surfaces as a
  GraphQL field error on that path (Section 8) and the client skips that chart while
  still rendering the rest of the simfile.
- **BGM `.ogg` / preview `.mp3`:** the schema has **no** dedicated BGM/preview URL
  fields the client uses. The client **assembles** these URLs from the configured R2
  base and the simfile id (Section 5). Because URLs are public and stable, no TTL or
  cache-control coordination is required.

## 5. Audio URL assembly & availability

The schema's `downloadUrl`, `previewUrl`, and `videoPreviewUrl` fields are **not used**
in v1. Instead:

- **BGM:** `{R2_base}/{id}/bgm.ogg`
- **Preview:** `{R2_base}/{id}/preview.mp3`

where `id` is `Simfile.id` and `R2_base` is the configured R2 bucket base URL.

**Availability detection.** Rather than blindly requesting (and 404-ing on) missing
files, the client inspects `Simfile.files: [R2File!]!`:

- `hasBGM` ← `files` contains a key matching `bgm.ogg` (suffix match, tolerant of an
  `{id}/` prefix).
- `hasPreview` ← `files` contains a key matching `preview.mp3`.
- `R2File.size` provides the download size for progress UX when present.

This maps onto the existing `ServerSong.hasBGM` / `hasPreview` flags, which previously
were optimistically assumed `true`.

## 6. Delivered schema (reference)

The authoritative schema is `Virgo/schema.graphql`. The types and fields the client
consumes:

```graphql
type Simfile {
  id: ID!
  title: String!
  artist: String!            # non-null in schema; defaults applied server-side
  bpm: Float!                # tempo (Double precision)
  genre: String              # nullable; client falls back to "DTX Import"
  tags: [String!]!           # may be empty
  durationSeconds: Int       # nullable; client keeps its estimate when null
  dtxFiles: [DtxFile!]!      # one entry per difficulty/chart
  files: [R2File!]!          # R2 object listing; used for audio availability + sizes
  updatedAt: String!         # ISO-8601 string (no DateTime scalar)
  # consumed indirectly / ignored in v1:
  # downloadUrl, previewUrl, videoPreviewUrl, createdAt, publishDate,
  # displayId, isPublished, hasUploadedFiles, userId
}

type DtxFile {
  label: String!             # original label, e.g. "BASIC", "ADVANCED", "EXTREME", "MASTER", "REAL"
  level: Float!              # numeric level (scale TBD — see Open Questions)
  fileUrl: String!           # public R2 URL for the .dtx chart file
  fileSizeBytes: Int!
  fileEncoding: FileEncoding!  # how the client decodes the .dtx text
}

type R2File {
  key: String!
  size: Int!
  uploaded: String!          # ignored by client
}

enum FileEncoding { SHIFT_JIS  UTF_8 }

type SimfileConnection {
  count: Int!                # total matches after filters
  data: [Simfile!]!
}

enum SimfileScope { MINE  PUBLISHED }   # client always sends PUBLISHED
```

Notable differences from the original wishlist, all resolved in favor of the schema:

- `Song` → **`Simfile`**; `Chart` → **`DtxFile`** (embedded value, **no `id`**).
- **No `Difficulty` enum.** Backend exposes only `label: String!` + `level: Float!`;
  the client derives its 4-bucket difficulty (Section 7).
- `DtxFile.level` is **`Float!`** (was `Int!` in the wishlist).
- **Dates are `String!`** ISO-8601 (no custom `DateTime` scalar).
- **Page-based pagination** (`page`/`pageSize`, returns `count` + `data`) — *not* Relay
  cursors. No `updatedSince`, no sort enum, no genre/bpm/difficulty filters.
- **`fileEncoding` is provided** — the client stops hard-coding Shift-JIS. ✅

## 7. Difficulty derivation (client-side)

The app UI groups charts by a canonical 4-bucket enum
`Difficulty { easy, medium, hard, expert }` (`Virgo/constants/Drum.swift`). The backend
no longer supplies this, so a `DifficultyClassifier` derives it from `DtxFile`:

1. **Label match** (case-insensitive), the primary signal:
   - `BASIC` → `easy`
   - `ADVANCED` → `medium`
   - `EXTREME` → `hard`
   - `MASTER`, `REAL` → `expert`
2. **Level fallback** for unrecognized labels: bucket by `level` thresholds. Exact
   thresholds depend on the level scale (Open Question 1); the classifier centralizes
   this so the thresholds live in one tested place.

`DtxFile.level` (Float) is rounded to `Int` for the existing `ServerChart.level` field
and difficulty-badge display.

## 8. Queries

The client uses two read operations against the delivered `Query` type.

### 8.1 `simfile(id: ID!): Simfile`
Refresh a single entry (e.g. after opening detail or completing a download) without
re-fetching the list. Returns `null` if not found — not an error.

### 8.2 `simfiles(scope: PUBLISHED, page, pageSize, search): SimfileConnection!`
Powers the browse screen (`ServerSongsView`) and future search UI.

- `scope: PUBLISHED` always.
- `search: String` — optional substring query (server-defined matching).
- `page` / `pageSize` — 1-based paging. `pageSize` default per schema (20); the client
  may request a larger page (Open Question 2). `count` gives the total for paging math.

### Caching & refresh strategy

The client keeps a persistent `ServerSong` SwiftData cache across launches. **There is no
automatic refresh.** The catalog only changes via:

1. A **manual "re-fetch simfiles" control** in `ServerSongsView` (the sole way to pull
   new catalog data), and
2. **User-initiated deletion** of a downloaded song.

The manual re-fetch refreshes **catalog metadata only** — it never downloads binary
files. Binaries (`.dtx`/`.ogg`/`.mp3`) are still fetched per-song when the user taps
download, exactly as today, and a song's files are downloaded at most once.

**Re-fetch algorithm.** Page-walk the full `PUBLISHED` list to obtain the complete
current set of `Simfile.id`s (`count` bounds the walk), then diff against the cache by id:

- **New ids** → insert metadata for new simfiles (`ServerSong` + `ServerChart`).
- **Existing ids (still on server)** → **left untouched.** No metadata overwrite, no
  binary re-download. (Server-side updates are not detectable in v1 — see below.)
- **Stale ids (cached but absent from server)** → **pruned**, including downloaded ones:
  delete the `ServerSong`/`ServerChart` records and clean up any local binary files for
  that id.

**Why no update detection.** `Simfile.updatedAt` is available but the client has no
trigger to act on it (no background refresh, and existing entries are intentionally not
re-fetched). It is stored on `ServerSong.lastUpdated` for forward compatibility; a future
revision could compare it to detect and refresh changed entries. v1 does not.

## 9. Errors

Standard GraphQL `errors[]` with `extensions.code`. The client maps these to its
existing `errorMessage` surface:

| `extensions.code` | Meaning | Client behavior |
| --- | --- | --- |
| `INVALID_INPUT` | malformed/out-of-range args | logged; treated as a bug |
| `RATE_LIMITED` | too many requests | backoff + retry once |
| `INTERNAL` | unexpected server error | generic error, allow retry |

"Not found" is not an error: `simfile(id)` returns `null`; an empty `simfiles`
connection is valid. A field-level error on `DtxFile.fileUrl` causes the client to skip
that chart while rendering the rest of the simfile.

## 10. Architecture & implementation approach

**Adapter approach:** keep the existing SwiftData models, the `ServerSongService` public
facade, and `ServerSongsView` unchanged; replace the REST internals with a GraphQL stack
behind a mapping layer. This keeps the blast radius small and preserves most existing
service/cache tests.

New/changed components:

- **`SimfileGraphQLClient`** (protocol-backed, mirroring the `DTXAPIClient` pattern):
  wraps Apollo; exposes `simfiles(page:pageSize:search:)` and `simfile(id:)`; always
  injects `scope: PUBLISHED`; reads the GraphQL endpoint from config.
- **`SimfileMapper`**: converts generated `Simfile`/`DtxFile`/`R2File` types into
  `ServerSong`/`ServerChart`, applying difficulty derivation (Section 7), audio URL
  assembly + availability (Section 5), ISO date parsing for `updatedAt`, genre/duration
  fallbacks, and `level` Float→Int rounding.
- **Apollo iOS** added via SPM; codegen configured against `Virgo/schema.graphql` with
  generated sources in a dedicated folder.
- **`ServerSongCache` / `ServerSongDownloader`** rewired to the GraphQL client + mapper.
  Chart download uses `DtxFile.fileUrl`; BGM/preview use assembled R2 URLs.
- **`DTXAPIClient`**: REST list/metadata/download paths and the `DTXAPITypes` tied to
  them are removed (or reduced to a thin `URLSession` download helper if still needed).
- **Config:** add the R2 bucket base URL setting alongside the renamed GraphQL endpoint
  setting.

### Field consumption map (traceability)

| Schema field | Client model field | Used in |
| --- | --- | --- |
| `Simfile.id` | `ServerSong.songId` | cache key; R2 path segment |
| `Simfile.title` | `ServerSong.title` / `Song.title` | list, detail, gameplay header |
| `Simfile.artist` | `ServerSong.artist` / `Song.artist` | list, detail |
| `Simfile.bpm` | `ServerSong.bpm` / `Song.bpm` | metronome, gameplay |
| `Simfile.genre` | `Song.genre` (`"DTX Import"` if null) | list filter, library grouping |
| `Simfile.durationSeconds` | `Song.duration` (`mm:ss`; estimate if null) | list, detail |
| `Simfile.updatedAt` | `ServerSong.lastUpdated` (ISO parse) | stored for forward-compat; not acted on in v1 |
| `Simfile.files[]` | `ServerSong.hasBGM` / `hasPreview` + sizes | download UX |
| assembled `{R2}/{id}/bgm.ogg` | downloaded → `Song.bgmFilePath` | BGM in gameplay |
| assembled `{R2}/{id}/preview.mp3` | downloaded → `Song.previewFilePath` | preview clip |
| `DtxFile.label` | `ServerChart.difficultyLabel` | display label |
| derived | `ServerChart.difficulty` / `Chart.difficulty` | badge, chart selection |
| `DtxFile.level` | `ServerChart.level` (Int) | level number |
| `DtxFile.fileUrl` | chart download → `DTXFileParser` | note parsing |
| `DtxFile.fileSizeBytes` | `ServerChart.size` | download progress |
| `DtxFile.fileEncoding` | DTX text decoding | replaces hard-coded Shift-JIS |

## 11. Non-functional requirements

- **Latency target:** P95 < 300 ms for `simfile`/`simfiles` queries.
- **Catalog size:** hundreds in v1, low thousands within a year.
- **Offline:** degrades gracefully — shows the cached `ServerSong` set.
- **Schema evolution:** additive changes preferred; Apollo codegen tolerates unknown
  fields. Re-run codegen when the schema updates.

## 12. Open questions

1. **`DtxFile.level` scale.** Is `level` on a `0–9.99` scale (e.g. `8.7`) or a `0–100`
   scale (e.g. `87`)? Needed for correct level display and the difficulty-classifier
   level fallback.
2. **Max `pageSize`.** What page size does the backend honor for `simfiles` (schema
   default is 20)? Affects refresh page-walk efficiency.
3. **`R2File.key` shape.** Does `key` include an `{id}/` prefix (e.g. `{id}/bgm.ogg`) or
   bare filenames? Affects the suffix-match logic for availability detection.
4. **R2 bucket base URL & GraphQL endpoint** for dev / staging / prod.
