# Engraved — Virgo Frontend Redesign

**Date:** 2026-06-27
**Status:** Approved design, pending implementation plan
**Scope:** Full app-wide visual language for Virgo (SwiftUI, iPadOS + macOS)

## 1. Overview

Replace Virgo's current dark + purple-gradient UI with **"Engraved"**: an editorial /
sheet-music aesthetic that treats drum notation as the typographic, print craft it is.
This is a *native SwiftUI* redesign — the real app code changes, not a mockup.

The design is a **two-world system** sharing one type system and one accent color:

- **Paper** — warm ivory, ink-on-paper, for browsing/reading screens.
- **Ink (Stage)** — warm near-black for the performance screens (gameplay, metronome).

"Paper for reading, ink for the stage" keeps fast-scrolling gameplay notation readable
and focused while the rest of the app feels like fine print on paper.

## 2. Approved decisions

| Decision | Choice |
|---|---|
| Output | Native SwiftUI (ships in the app) |
| Scope | Full visual language across every screen |
| Aesthetic | Engraved — editorial score (ivory + ink + vermillion) |
| Light/Dark | Paper for browse; inverted Ink for gameplay + metronome stage |
| Difficulty display | Vermillion pip meter + small-caps label (replaces rainbow badges) |
| Rollout | One plan: foundation, then all screens (paper world first, then ink/stage) |
| Tab bar | Native restyle (tint + appearance) first; custom bar only if needed |

## 3. Color tokens

Defined once in `design/Theme.swift`. Hex values are the design intent; minor tuning
during implementation is fine. Delivered to views via an `@Environment(\.theme)` value
(`VirgoTheme`) so shared components adapt to whichever world a screen declares.

### Paper world (Songs, Library, Settings, Profile, Splash)
| Token | Hex | Use |
|---|---|---|
| `paper` | `#F4EFE4` | screen background (warm ivory) |
| `paperRaised` | `#FBF7EE` | subtle raised surface (used sparingly) |
| `ink` | `#1A1714` | primary text |
| `inkMuted` | `#6E665A` | secondary text / metadata |
| `rule` | `#D9D0BF` | hairline dividers / ledger lines |
| `vermillion` | `#C8341F` | accent: active state, primary action, pips |

### Ink / Stage world (Gameplay, Metronome)
| Token | Hex | Use |
|---|---|---|
| `stage` | `#15120D` | background (warm near-black) |
| `stageRaised` | `#211C15` | raised surface / HUD panels |
| `chalk` | `#F4EFE4` | primary notation/text (warm white) |
| `chalkMuted` | `#9A9382` | secondary on stage |
| `gridline` | `#2A2419` | staff/measure gridlines |
| `vermillion` | `#C8341F` | downbeat, judgments, accent |

Surfaces favor **hairline rules + whitespace** over translucent fills and drop shadows.
This intentionally removes the current `Color.white.opacity(0.1)` card pattern.

## 4. Typography

Three bundled OFL faces, registered programmatically at runtime via
`CTFontManagerRegisterFontsForURL` (see `design/FontRegistration.swift`) so the
same code path works on both iOS and macOS without platform-specific Info.plist
keys. The `.ttf` files are added to the target via `Copy Bundle Resources`.
Helpers live in `design/Typography.swift` (e.g. `Font.fraunces(_:)`,
`Font.hanken(_:)`, `Font.plexMono(_:)`).

1. **Fraunces** — high-contrast variable serif. Wordmark, screen titles, song titles.
2. **Hanken Grotesk** — humanist sans. Body, labels, controls (legible when small).
3. **IBM Plex Mono** — all numerals & technical data: BPM, time signature, durations,
   timing-ms, scores. Sells the "score sheet / fine print" feel.

Faces are swappable; the helper API isolates the choice so a later swap is one file.
A Dynamic Type / accessibility scaling pass uses relative font sizing where practical.

## 5. Signature design moves

- **Tempo-mark motif** — `♩ = 120` in Plex Mono recurs as a header device.
- **Difficulty pip meter** — `●●●○○` in vermillion + small-caps label
  (Easy/Normal/Hard/Expert), replacing colored badges. `DifficultyBadge` is reworked
  into `DifficultyPips`; the `difficulty.color`-based badge is retired from the UI.
- **Drawn vermillion underline** under the active title / selected tab, animating in on load.
- **Ledger rows** — the song list renders as ruled ledger lines, not floating cards.
- **Metronome is the one expressive motion** — a pendulum/pulse on the ink stage.
- **Session results as a printed "report card"** — ruled, typeset summary.
- **Staggered fade-up on screen load** (editorial `animation-delay`-style entrance),
  used once per screen, not scattered micro-interactions.

## 6. Code architecture

New `Virgo/design/` group:

- `Theme.swift` — `VirgoTheme` struct holding the active world's tokens + an
  `EnvironmentKey`/`@Environment(\.theme)`. A `.surface(.paper)` / `.surface(.ink)`
  view modifier sets the environment and the background for a screen.
- `Typography.swift` — font registration + `Font` helpers.
- `Spacing.swift` — spacing scale, corner radii, rule weights, baseline constants.
- Reusable components (each its own file, small):
  - `RuleDivider` — hairline rule.
  - `DifficultyPips` — pip meter + small-caps label.
  - `GhostButton` / `VermillionButton` — `ButtonStyle`s (outline + solid primary).
  - `TempoMark` — `♩ = N` device.
  - `LedgerRow` — ruled list-row container.

Fonts: `Virgo/Resources/Fonts/` (added to project + Copy Bundle Resources + Info.plist).

Migration: replace hardcoded `Color.black/white/purple/gray` (~130 call sites) with
theme tokens, screen by screen.

## 7. Per-screen application

**Paper world (first):**
- **MainMenu / Splash** — ivory paper; large Fraunces `VIRGO` wordmark; tempo-mark
  motif; vermillion `START`. Replaces the purple/blue/indigo gradient. Keep
  `logoText`, `subtitleText`, `startButton` identifiers and the debug clear-DB control.
- **Tab shell (`ContentView`)** — restyle tab bar: ink-on-paper, vermillion selection.
  `.tint(.vermillion)` + `UITabBarAppearance`/toolbar background. Keep `appTabShell`
  and per-tab identifiers; SF Symbols retained.
- **Songs / Downloaded / Server (`SongsTabView`, `DownloadedSongsView`, rows)** — ledger
  list with hairline rules, Fraunces titles, Plex Mono BPM/metadata, `DifficultyPips`.
  Search becomes an underlined input; segmented sub-tab restyled. Keep `searchField`,
  `clearSearchButton`, `refreshServerSongsButton`, row/bookmark identifiers.
- **Library, Settings, Profile, Audio/Input/Notation settings** — paper; sectioned like a
  printed form with rules instead of grouped-card fills.

**Ink / Stage world (second):**
- **Metronome** — showpiece: large tempo numeral, pendulum/pulse, vermillion downbeat.
- **Gameplay** — keep high-contrast dark, recolored to `stage`/`chalk`/`vermillion`;
  restyle `GameplayHeaderView`, `GameplayControlsView`, HUD, judgments
  (Perfect/Great/Good/Miss). **No new per-frame work** — reuse cached layout; styling
  only. Keep `gameplayRoot` and all gameplay identifiers.
- **Session results** — printed report-card layout (accuracy, combo, score) in the type system.

## 8. Constraints

- **Accessibility identifiers preserved** — every existing `accessibilityIdentifier`
  stays (UI tests depend on them). New components add identifiers, never remove.
- **SwiftLint size limits** — line 120/150, function 50/100, type 300/600, file 600/1000.
  Component extraction keeps files small.
- **Gameplay performance** — restyling must not introduce per-frame recomputation or
  new `@Published` observation in `GameplayView`'s hierarchy (see CLAUDE.md perf notes).
- **iPad-only iOS family** — no iPhone targeting; layouts assume iPad/macOS.
- **Cross-platform fonts** — registered programmatically via
  `CTFontManagerRegisterFontsForURL` (no Info.plist keys); verify on both build
  destinations.

## 9. Testing & verification

- macOS build + `VirgoTests` stay green (note: one pre-existing flaky SwiftData test is
  red on `main` and is not caused by this work).
- iPad-simulator build compiles.
- Existing UI tests pass unchanged (identifiers preserved).
- Manual/visual check of each screen in both worlds (screenshots on macOS + iPad sim).
- New unit coverage where it's pure logic (e.g. pip count from difficulty).

## 10. Out of scope

- New features or screens; information architecture changes (same 5 tabs, same flows).
- Backend/server, data model, audio engine, input/MIDI logic.
- A full system-appearance light/dark theme (worlds are screen-determined, not OS-driven).
- App icon redesign (can be a later follow-up).

## 11. Risks

- **Native tab-bar restyling** may be constrained on one platform → fall back to a custom
  bar only if the native appearance is inadequate.
- **Custom font loading differences** across iOS/macOS → validate early, before screen work.
- **Color migration breadth** (~130 sites) → do it per screen, building/testing between
  worlds to catch regressions incrementally.
