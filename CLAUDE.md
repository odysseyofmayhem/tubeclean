# CLAUDE.md: TubeClean (iPad app)

Read this before changing anything in this repo. `README.md` has the full build steps.

## What this is

A family-only iPad app: one `WKWebView` showing YouTube's desktop site with no ads and no Shorts, for one child, signed in to his Google account. It is not on the App Store and never will be. Keep it small: no settings screens, no accounts and no analytics unless Lee asks.

The ad and Shorts blocking lives in a JavaScript file built by the sibling repo `../tubeclean-rules`. This repo only injects it, ships a copy of it, and refreshes it.

## Build on macOS with Xcode

You need Xcode 27, XcodeGen and macOS 26 or later. The app runs on iPadOS 26.0 and later.

```sh
xcodegen generate                 # creates TubeClean.xcodeproj from project.yml
open TubeClean.xcodeproj          # then ⌘R on an iPad simulator
xcodebuild -project TubeClean.xcodeproj -scheme TubeClean \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' test
```

- **`project.yml` is the source of truth.** Never commit `TubeClean.xcodeproj`, because it's generated and gitignored. Make settings changes (deployment target, team, bundle ID, new files) in `project.yml`, then regenerate.
- **The signing team goes in `project.yml`** as `DEVELOPMENT_TEAM`. A team picked in Xcode's UI is lost on the next regenerate.
- **The simulator needs no signing.** A real iPad needs a team, plus Developer Mode on the iPad.

## How it fits together

| File | Responsibility |
|---|---|
| `NavigationPolicy.swift` | **The security boundary.** Decides every main-frame and sub-frame URL: YouTube is allowed, Google sign-in is allowed only on an exact host list, everything else is blocked, and Shorts and `m.youtube.com` are redirected. Pure and fully unit-tested |
| `BrowserController.swift` | Builds the web view and injects the script at document start in the page world, with a guard so it runs only on `*.youtube.com`. Also: consent cookie, full screen, splash state, crash recovery, debug hooks |
| `RulesStore.swift` | Bundled, cached and downloaded script. Newest valid version wins. Parses the header `/* tubeclean-rules version=yyyyMMddHHmm */` strictly and rejects versions more than a day in the future |
| `SplashView.swift` | Covers the white page until YouTube first draws something |

## Rules for changes

- **Every navigation change needs a unit test** in `TubeCleanTests`. The allowlist is what keeps a child inside YouTube, so add a test for every host or path you allow or block.
- **Never widen Google access with a pattern.** List exact hosts. A pattern once let in `accounts.google.co.de`, which Google doesn't own.
- **Keep test hooks behind `#if DEBUG`:** `TCStartURL`, `TCNoRules`, `TCMuted`, `TCEvalJS`, and `isInspectable`.
- **Don't reload the page when new rules arrive.** They apply on the next page load, so a video he is watching isn't interrupted.
- **The web view is sized by frame in `WKWebViewContainer.layoutSubviews`, not with constraints.** Element full screen moves the web view to another window and back, and constraints don't survive that. Constraints gave a black screen in full screen and a white page afterwards.
- **Stay on the desktop site.** YouTube's own script moves touch devices to `m.youtube.com`, where the uBlock part of the rules doesn't run. `NavigationPolicy` sends it back with `app=desktop`.

## Testing checklist

1. `xcodebuild ... test`: all tests pass.
2. Simulator: home, search, a watch page, full screen in and out, and a Shorts link (should go home).
3. Signed in on a real iPad, when the change touches sign-in or playback.

## Pitfalls

- **Simulator sound** plays through the Mac's speakers. Use `-TCMuted YES` for automated runs, and shut the simulator down afterwards.
- **AV1 stalls in the simulator.** The blocking script asks YouTube for H.264 instead. A missing script therefore shows up as videos that never start in the simulator.
- **Free Apple accounts:** installs expire after 7 days and the account allows only 3 devices. "Maximum number of registered iPad devices" means that account is full; switch the team in `project.yml`.
