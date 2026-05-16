# AGENTS.md

Guidance for AI assistants working in this repo. The README covers what the app does and how to install it — this file covers the things you need to know to make changes without breaking conventions.

## Pull main before starting work

Always `git pull` (or rebase your branch on the latest `origin/main`) before starting a task. The release workflow auto-versions and ships from `main`, so stale local state can produce confusing pulls mid-work and PRs against an out-of-date base.

## Build & test

```sh
xcodegen generate
xcodebuild -project AgendumNeo.xcodeproj -scheme AgendumNeo \
  -configuration Debug -destination 'platform=macOS' build
xcodebuild -project AgendumNeo.xcodeproj -scheme AgendumNeo \
  -destination 'platform=macOS' test
```

Run `xcodegen generate` after editing `project.yml` or after pulling.

## XcodeGen is the source of truth

`AgendumNeo.xcodeproj` is gitignored and regenerated from `project.yml`. Never hand-edit the `.xcodeproj`; edit `project.yml` and re-run `xcodegen generate`. New source files under `AgendumNeo/` are picked up automatically by the path-based source group — you usually don't need to touch `project.yml` just to add a file.

## Swift 6, strict concurrency complete

`SWIFT_STRICT_CONCURRENCY: complete` is on. New types that cross actor boundaries must be `Sendable`. UI/state types are `@MainActor` — `AppModel` and `SyncEngine` both are. Don't sprinkle `nonisolated(unsafe)` to silence the compiler; fix the data flow.

## Tests use Swift Testing, not XCTest

`AgendumNeoTests/` uses `@Suite` / `@Test` / `#expect` from the `Testing` module. Don't reintroduce XCTest.

## Auth piggybacks on `gh`

There is no in-app auth UI. `GHCLI.swift` shells out to `gh auth status` and `gh auth token`. To exercise auth paths locally you need a working `gh` install authenticated to at least one account.

## Demo mode for UI work

Launch with `--demo` (`CommandLine.arguments`) to skip the network and use `DemoData`. Use this when iterating on views so you aren't dependent on live `gh` state. Set in Xcode scheme arguments, or pass via `open -a "Agendum Neo" --args --demo` on a release build.

## Architecture in one paragraph

`AgendumNeoApp` declares a `WindowGroup` and a `MenuBarExtra`, both rendering `RootView` against a shared `@Observable AppModel`. `AppModel.bootstrap()` loads namespaces from `gh`, picks an active one (persisted in `UserDefaults`), and hands it to `SyncEngine`, which polls every 5 minutes via `GitHubClient` (GraphQL over the `gh`-issued token). All UI state lives on `AppModel`; views are stateless apart from local `@State` like list selection.

## Known drift: macOS 15 deployment target vs Tahoe SDK

`project.yml` pins `MACOSX_DEPLOYMENT_TARGET: 15.0` even though the README says macOS 26 and releases are built on `macos-26` with the Tahoe SDK. This is intentional — bumping the deployment target broke CI on the macOS 15 runner. See `docs/project-state.md` for the full history. Don't "fix" this without checking whether CI has moved.

## CI gating

CI runs on every push and PR. Main is unprotected, so it's on us — wait for CI green before merging. Prefer `gh pr checks <N> --watch && gh pr merge <N> --squash` over `--auto`.

## Commit style

Always use Conventional Commits: `<type>[(scope)][!]: <subject>` (e.g. `fix: clamp window resize to visible frame`). Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `style`, `ci`, `build`, `revert`. Use `!:` or a `BREAKING CHANGE:` footer for breaking changes.

This is load-bearing: the release workflow derives the next semver bump from commit types (`feat` → minor, `fix` → patch, breaking → major). A commit landing on main with a non-conforming subject won't bump the version correctly.

## Linking PRs to issues

When a PR addresses an issue, link it in the PR body using GitHub's closing keywords so the issue auto-closes on merge:

- `Closes #X` — the PR fully resolves the issue (default for issue-driven work)
- `Refs #X` — related but doesn't fully close (e.g. partial work, follow-up needed)

Put the keyword on its own line in the PR description, not just in the title.
