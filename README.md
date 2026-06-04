<a href="https://github.com/danseely/agendum-neo/releases/latest"><img src="Resources/AppIcon-1024.png" width="160" align="left" alt="Agendum Neo app icon"/></a>

### Agendum Neo

A small native macOS app that surfaces your GitHub inbox

[Download the latest release](https://github.com/danseely/agendum-neo/releases/latest)

<br clear="left"/>

---

It pulls together your open PRs — both those you authored (with their current review state) and those where your review has been requested — alongside any issues assigned to you, scoped to the GitHub namespace (your user or one of your orgs) you pick from the toolbar. State syncs every 5 minutes.

Authentication piggybacks on the local [`gh` CLI](https://cli.github.com/) — there's no separate login. The app shells out to `gh auth token` to fetch the active token without disturbing `gh`'s active account.

![Screenshot of Agendum Neo showing the three inbox sections — authored PRs, review requests, and assigned issues — with color-coded status pills](Resources/screenshot.png)

## Install

Agendum Neo is distributed as an unsigned, un-notarized app, so macOS Gatekeeper blocks it on first launch. The steps below clear that block once; after that it opens normally.

1. Download the latest `.dmg` from the [releases page](https://github.com/danseely/agendum-neo/releases/latest).
2. Open the DMG and drag **Agendum Neo** into your **Applications** folder.
3. Launch it once (double-click). On macOS 26 (Tahoe) you'll get a dialog saying *“Apple could not verify ‘Agendum Neo’ is free of malware…”* — click **Done**. (Tahoe no longer offers a right-click → **Open** bypass; you have to go through Settings.)
4. Open **System Settings → Privacy & Security** and scroll down to the **Security** section. You'll see a line noting that *“Agendum Neo” was blocked to protect your Mac.* Click **Open Anyway**.
5. Authenticate with Touch ID or your password, then click **Open Anyway** in the confirmation dialog.

The app now opens like any other; you won't have to repeat this.

If you'd rather do it from the terminal, strip the quarantine flag and launch directly:

```sh
xattr -dr com.apple.quarantine "/Applications/Agendum Neo.app"
open "/Applications/Agendum Neo.app"
```

Agendum Neo authenticates through the [`gh` CLI](https://cli.github.com/), so install and sign in to `gh` before first run — see [Requirements](#requirements).

## Requirements

- macOS 26 (Tahoe)
- [`gh`](https://cli.github.com/) ≥ 2.40 authenticated to at least one account with `repo` and `read:org` scopes
- Xcode 26 — only needed if you're building from source

## Build & run

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open AgendumNeo.xcodeproj
```

Or build from the command line:

```sh
xcodebuild -project AgendumNeo.xcodeproj -scheme AgendumNeo -configuration Debug \
  -destination 'platform=macOS' build
```

## Project layout

```
AgendumNeo/
  AgendumNeoApp.swift     # @main, WindowGroup + MenuBarExtra scenes
  AppModel.swift          # @MainActor @Observable app state
  SyncEngine.swift        # 5-minute poll loop
  GitHub/                 # gh CLI shell-out + GraphQL client + models
  Views/                  # SwiftUI views
  Assets.xcassets/
AgendumNeoTests/          # Swift Testing unit tests
project.yml               # XcodeGen project definition
```

## Distribution

GitHub Actions runs build + tests on every push.

To cut a release, trigger the **Release** workflow manually with a tag (e.g. `v0.1.0`); it builds the Release configuration, packages the app into a DMG, and attaches the DMG to a new GitHub release.
