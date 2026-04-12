# MIDI Input for Real Drum Gameplay Design

**Date:** 2026-04-12  
**Status:** Approved for planning  
**Platforms:** iOS first, with existing macOS behavior preserved unless implementation work naturally improves both

## 1. Problem Statement

Virgo already has a basic MIDI path inside `InputManager`, but it is not yet a complete real-drum gameplay workflow. The current implementation:

- connects to all MIDI sources automatically
- uses a static global MIDI mapping
- exposes no source selection UI
- exposes no live MIDI learn flow
- exposes no player-facing diagnostics
- processes only the first packet in a MIDI packet list

That is enough for rudimentary MIDI note input, but not enough for dependable e-drum gameplay on iOS.

## 2. Goals

The first version of this feature should provide a complete **iOS-first MIDI gameplay workflow** for electronic drum kits:

1. Let the player choose the MIDI source used for gameplay.
2. Let the player map incoming MIDI notes to Virgo drum lanes through a live learn flow.
3. Show live diagnostics for device connection state and incoming note data.
4. Route mapped MIDI hits into the existing gameplay scoring pipeline.
5. Preserve **minimal-latency, latency-prioritized** input detection during active gameplay.
6. Support pad hits plus hi-hat pedal behavior.

## 3. Explicit Product Decisions

These choices were confirmed during brainstorming and should be treated as design constraints for planning:

| Topic | Decision |
|---|---|
| Scope | Full MIDI gameplay workflow: device selection, live mapping capture, diagnostics |
| Platform priority | iOS first |
| Mapping persistence | One global MIDI mapping shared across devices |
| Hi-hat scoring | Open and closed hi-hat chart notes both score from the hi-hat pad lane; pedal hits only score `hiHatPedal` notes |
| Disconnect behavior | If the selected source disconnects during gameplay, auto-pause immediately and show a reconnect message |
| Diagnostics depth | Show connected sources plus live note / velocity / channel readout and mapping preview |
| Performance rule | MIDI input detection latency should be kept minimal and always prioritized |

## 4. Existing Architecture to Preserve

The design should preserve the shape of the current gameplay input path:

```text
GameplayViewModel
  -> InputManager
      -> InputTimingMatcher
          -> NoteMatchResult
              -> GameplayViewModel.recordHit(result:)
```

`GameplayViewModel`, `GameplayInputHandler`, scoring, and timing matching already work together. The design should extend that pipeline rather than replace it.

## 5. Proposed Architecture

### 5.1 `InputManager` remains the public facade

`InputManager` should stay the gameplay-facing API used by `GameplayViewModel`. It remains responsible for:

- starting and stopping active listening for a gameplay session
- holding the current timing matcher
- converting keyboard or MIDI events into `InputHit`
- producing `NoteMatchResult`
- notifying the existing delegate

This keeps the gameplay integration stable while allowing the MIDI internals to be refactored into focused collaborators.

### 5.2 New MIDI-focused collaborators

The MIDI workflow should be decomposed into the following focused units:

| Component | Purpose |
|---|---|
| `MIDIDeviceRegistry` | Discover CoreMIDI sources, track connection changes, expose the selected gameplay source, and publish the source list for settings/diagnostics |
| `MIDIEventRouter` | Receive CoreMIDI packet lists, iterate all packets/events, filter to the selected source, decode note/channel/velocity, and forward normalized MIDI note events |
| `MIDILearnSession` | Manage “next valid hit wins” learn mode when the user assigns a MIDI note to a Virgo drum lane |
| `MIDIDiagnosticsStore` | Hold player-facing diagnostics state such as source names, selected source, last note, velocity, channel, and mapping preview |
| `InputSettingsManager` additions | Persist selected source identity plus the existing global MIDI mapping |

### 5.3 Architectural rule: latency-first split path

The design must explicitly separate MIDI processing into two paths:

1. **Realtime gameplay path**  
   Source filter -> event decode -> mapping lookup -> `InputHit` -> timing match -> gameplay delegate callback
2. **Async diagnostics path**  
   Mirror already-processed events into diagnostics state for UI visibility

This rule exists so diagnostics, UI refreshes, and verbose logging cannot delay scoring-critical input processing.

## 6. Runtime Workflow

### 6.1 Settings workflow

The MIDI area in `InputSettingsView` should evolve from a read-only mapping display into a full workflow:

- show the list of connected MIDI sources
- allow the user to choose the source used for gameplay on iOS
- show current global MIDI note mappings for each `DrumType`
- provide **Learn**, **Replace**, and **Clear** actions per drum lane
- show a live diagnostics panel with the most recent note / velocity / channel and the mapped drum result

The diagnostics panel should be driven by the same MIDI event pipeline even when gameplay is not currently active, so the player can verify device connection and note traffic from Settings before starting a song.

Until the user has explicitly selected a gameplay source, the MIDI settings UI should show an unselected state. Virgo should not silently auto-select a source on the player's behalf for iOS MIDI gameplay.

### 6.2 Gameplay workflow

During gameplay:

1. `InputManager.startListening(songStartTime:)` arms the selected source for scoring.
2. `MIDIEventRouter` receives incoming packets and processes **all** events, not just the first packet.
3. Matching note-on events are filtered to the selected source.
4. The global MIDI mapping converts the note to a `DrumType`.
5. `InputManager` creates an `InputHit`.
6. `InputTimingMatcher` produces a `NoteMatchResult`.
7. Existing delegate flow forwards the result into `GameplayViewModel.recordHit(result:)`.

### 6.3 Hi-hat behavior

The first version should use the simpler, already-approved hi-hat model:

- `openHiHat` and `hiHat` chart notes both score from the `hiHat` input lane
- `hiHatPedal` chart notes score only from the `hiHatPedal` input lane

This preserves compatibility with the current chart model and avoids requiring a more advanced pedal-state scoring model in v1.

## 7. Latency and Performance Requirements

Low-latency input is not just a non-functional preference; it is a core design requirement.

### 7.1 Hot path rules

The realtime gameplay path should:

- stay entirely in memory during active gameplay
- avoid `UserDefaults` access during hit processing
- avoid diagnostics dependencies
- avoid unnecessary thread hops before scoring-critical work completes
- avoid verbose per-hit work on the hot path

### 7.2 Timebase rule

The MIDI path should prefer the MIDI event timebase, or a monotonic fallback, for hit timing. The design should avoid using a UI-oriented path for timestamp acquisition if that would add jitter or delay.

### 7.3 Selected-source priority

Only the selected gameplay source should participate in scoring while a session is active. This keeps the gameplay path deterministic and avoids extra routing work from unrelated connected devices.

## 8. Error Handling and Operational Behavior

### 8.1 Session start

If the selected source is unavailable when the player attempts to start an **iOS MIDI gameplay session**, Virgo should show a reconnect/select-source prompt rather than silently starting a run with dead MIDI input. This behavior must not regress existing non-MIDI gameplay entry paths, including keyboard-first macOS flows.

### 8.2 Mid-session disconnect

If the selected source disconnects during active gameplay:

- gameplay auto-pauses immediately
- further miss processing is frozen
- the user sees a reconnect message
- the user can resume after the source becomes available again

This protects scoring correctness and avoids a cascade of unavoidable misses.

### 8.3 Learn mode behavior

`MIDILearnSession` should:

- accept only the first valid note-on from the selected source
- ignore note-off and unsupported MIDI messages
- time out cleanly if no valid note arrives
- surface the result clearly in the UI

If a learned MIDI note was already mapped to another drum lane, the new assignment wins and the old mapping is cleared explicitly so the resulting global mapping stays unambiguous.

### 8.4 Diagnostics behavior

Diagnostics are informational, not authoritative for scoring. If diagnostics UI updates lag or the settings screen is not visible, gameplay MIDI scoring must remain unaffected.

## 9. Persistence

`InputSettingsManager` should remain the owner of user input preferences. For this feature, it should persist:

- the global MIDI note -> `DrumType` mapping
- the preferred/selected MIDI source identity for gameplay selection, using a stable CoreMIDI source identifier shape suitable for reconnecting the same source across launches

Persistence should remain outside the scoring hot path. `InputManager` should work from an in-memory snapshot during active gameplay and reload only when configuration changes.

## 10. UI Surfaces Affected

The design directly affects these surfaces:

| Surface | Role |
|---|---|
| `InputSettingsView` | Source selection, live learn actions, mapping display, diagnostics panel |
| `MappingSections` | Replace read-only MIDI rows with actionable mapping controls |
| `InputManager` | Preserve gameplay-facing API while delegating MIDI responsibilities |
| `GameplayViewModel` | Handle selected-source disconnect by auto-pausing and preserving timing correctness |

## 11. Expected Code Organization

The implementation plan should bias toward existing repository patterns:

- keep a public facade with focused helpers, similar to other coordinator/facade structures in the codebase
- place gameplay/MIDI support types under `Virgo/utilities/`
- avoid growing `InputManager.swift` into a monolith
- preserve existing delegate and gameplay contracts whenever possible

Likely new or reshaped files:

- `Virgo/utilities/InputManager.swift` (facade + orchestration updates)
- `Virgo/utilities/MIDIDeviceRegistry.swift`
- `Virgo/utilities/MIDIEventRouter.swift`
- `Virgo/utilities/MIDILearnSession.swift`
- `Virgo/utilities/MIDIDiagnosticsStore.swift`
- `Virgo/utilities/InputSettingsManager.swift`
- `Virgo/views/InputSettingsView.swift`
- `Virgo/views/subviews/MappingSections.swift`

## 12. Testing Strategy

The design should be validated primarily with deterministic fake MIDI events rather than hardware-dependent tests.

### 12.1 Unit tests

Add focused tests for:

- source discovery and source selection behavior
- selected-source filtering
- multi-packet / multi-event MIDI decoding
- learn-mode capture and timeout behavior
- mapping conflict replacement
- diagnostics state updates

### 12.2 Integration tests

Add integration coverage for:

- `InputManager` routing selected-source MIDI hits into `InputTimingMatcher`
- processing every incoming MIDI event in a packet list
- disconnect-driven auto-pause and resume safety in `GameplayViewModel`

### 12.3 UI tests / rendering coverage

Add SwiftUI coverage for:

- source picker states
- learn-mode UI states
- mapping conflict messaging
- diagnostics panel states

The testing approach should follow existing repo patterns and avoid requiring a physical MIDI device in CI.

## 13. Out of Scope for This Version

To keep the planning scope focused, the following are intentionally out of scope unless the implementation plan shows they are already required by the approved design:

- per-device mapping profiles
- advanced open/closed hi-hat scoring based on pedal-state interpretation
- automatic fallback to any available MIDI source during gameplay
- deep troubleshooting logs or exportable raw event traces
- broad cross-platform parity work beyond what naturally falls out of the iOS-first implementation

## 14. Planning Readiness

This spec is ready for implementation planning. It is focused on a single feature area, preserves the current gameplay scoring architecture, and captures the approved product decisions needed to create a concrete implementation plan.
