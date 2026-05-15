# Project State

## Goal
Align Agendum Neo with macOS Tahoe expectations from issue #5 through a focused SwiftUI UI pass.

## Constraints / Non-goals
- Keep changes scoped to issue #5.
- Prefer existing SwiftUI and XcodeGen project patterns.
- Do not merge the PR.
- Avoid broad architecture churn.

## Links
- Issue: https://github.com/danseely/agendum-neo/issues/5
- Apple HIG: https://developer.apple.com/design/human-interface-guidelines
- Apple Materials guidance: https://developer.apple.com/design/human-interface-guidelines/materials
- WWDC25 "Build a SwiftUI app with the new design": https://developer.apple.com/videos/play/wwdc2025/323

## Current State
- Branch: codex/issue-5-tahoe-standards
- Done: Moved top-level namespace and refresh controls into a system toolbar; moved sync/error status into a bottom safe-area bar surface; replaced fixed-width table-like rows with adaptive two-line rows; added standard sign-in unavailable content with a working post-login refresh path; updated XcodeGen deployment metadata to macOS 26.
- In progress: PR publication.
- Blocked: none.

## Decisions
- 2026-05-15: Decision: Use standard SwiftUI toolbar, list, button, picker, link, and content-unavailable components instead of custom Liquid Glass effects. Reason: Apple guidance emphasizes getting the new design automatically from standard controls and avoiding Liquid Glass in the content layer. Impact: Keeps visual alignment practical and low-risk. Plan change: no.
- 2026-05-15: Decision: Update `project.yml` from macOS 15.0 to macOS 26.0. Reason: README and issue target Tahoe/macOS 26, and local Xcode 26.5 validates the SDK target. Impact: The project now requires macOS 26 at build metadata level. Plan change: no.

## Drift
- none

## Validation
- 2026-05-15: `xcodegen generate` succeeded.
- 2026-05-15: `xcodebuild -project AgendumNeo.xcodeproj -scheme AgendumNeo -configuration Debug -destination 'platform=macOS' build` succeeded.
- 2026-05-15: `xcodebuild -project AgendumNeo.xcodeproj -scheme AgendumNeo -destination 'platform=macOS' test` succeeded with 5 Swift Testing tests passing.

## Handoff / Next Actions
1. Push branch `codex/issue-5-tahoe-standards`.
2. Open PR against `main` with `closes #5`.
3. Do not merge unless explicitly asked.
