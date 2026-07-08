status: DONE_WITH_CONCERNS

changed_files:
- Virgo/layout/NotationLayout.swift
- Virgo/layout/NotationLayoutEngine.swift
- VirgoTests/NotationLayoutEngineTests.swift

commits:
- `44520ad` - Add fixed tab grid to notation layout

tests_run:
- `rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/NotationLayoutEngineTests -parallel-testing-enabled NO test`
  - red phase: failed at compile time with repeated `Value of type 'NotationLayout' has no member 'tabGrid'` errors, as expected after the test-first change
- `rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/NotationLayoutEngineTests -parallel-testing-enabled NO test`
  - green phase: build and test session reached `IDETestOperationsObserverDebug: Testing started completed`, but the RTK/xcodebuild wrapper did not return a finalized pass/fail status
- `rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/NotationLayoutEngineTests -parallel-testing-enabled NO -resultBundlePath /private/tmp/virgo-notation-layout-tests-2.xcresult test`
  - verification retry: test session again reached completion, but the process did not finalize a readable xcresult bundle before hanging

self_review_notes:
- Added `TabGrid` to the layout model with the fallback 960-tick grid and deterministic beat-to-tick mapping from the task brief.
- Replaced adaptive measure width and beat-gap note placement in `NotationLayoutEngine` with a fixed-width grid built from normalized note metadata when available and rounded fallback ticks otherwise.
- Kept scope within the owned files only; no `GameplayViewModel` files were changed.
- Updated `NotationLayoutEngineTests` to cover fixed-grid width, normalized metadata, beat boundary mapping, and legacy assertions that now need to reference `layout.tabGrid.measureWidth`.

concerns:
- Focused xcodebuild verification is incomplete: on this machine the RTK-wrapped `xcodebuild test` command reaches test-session completion but then hangs instead of returning a final test summary or finalized xcresult bundle.
