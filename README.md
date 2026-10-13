# TubeClean

An iPad app for watching YouTube without ads or Shorts. It is for family use only and is not distributed.

The app is a single web view locked to YouTube's desktop site (`www.youtube.com`). Google sign-in works, so the child stays signed in to his own account. Before each page loads, the app injects a blocking script. The script:

- strips ad data out of YouTube's responses before the player reads them
- removes Shorts from feeds, search, menus and channel tabs, and sends any Shorts link to the home page
- hides any ad element that still slips through
- mutes any ad that still plays and presses Skip

The blocking script is built in the sibling repo [`tubeclean-rules`](../tubeclean-rules). The app ships with a copy of it, and checks GitHub for a newer version every 6 hours. A YouTube change can therefore be fixed without rebuilding the app.

## Requirements

| Tool | Version | Notes |
|---|---|---|
| macOS | 26 or later | Xcode 27 needs it |
| Xcode | 27 | Includes the iPadOS 26 and 27 SDKs and simulators |
| XcodeGen | 2.46 or later | `brew install xcodegen`, or the [release zip](https://github.com/yonaskolb/XcodeGen/releases) |
| Apple account | Free or paid | Only needed to install on a real iPad (see below) |

The app runs on **iPadOS 26.0 and later**.

## Build on macOS

The Xcode project is generated from `project.yml` and is not committed. Generate it after every pull, or whenever you add or remove a file:

```sh
cd tubeclean
xcodegen generate
open TubeClean.xcodeproj
```

### Run in the simulator

1. In Xcode, choose an iPad simulator as the run destination, for example **iPad Air 11-inch (M4)**.
2. Press **⌘R**.

You don't need a signing team for the simulator. Sound plays through the Mac's speakers, so quit Simulator when you're done.

### Run the unit tests

In Xcode press **⌘U**, or from Terminal:

```sh
xcodebuild -project TubeClean.xcodeproj -scheme TubeClean \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' test
```

### Install on a real iPad

1. Connect the iPad by cable and tap **Trust** on the iPad.
2. First time only: on the iPad, turn on **Settings → Privacy & Security → Developer Mode** and restart it.
3. In Xcode, select the **TubeClean** target, then **Signing & Capabilities**, and choose your **Team**.
4. Choose the iPad as the run destination and press **⌘R**.
5. If the app won't open, trust the developer on the iPad: **Settings → General → VPN & Device Management**.
6. In the app, tap **Sign in** and sign in to the child's Google account.

A Team chosen in Xcode is lost the next time you run `xcodegen generate`. To keep it, set `DEVELOPMENT_TEAM` in `project.yml`.

How long an install lasts depends on the account:

| Account | The app keeps opening for | Device limit |
|---|---|---|
| Free Apple ID (Personal Team) | 7 days, then reinstall from Xcode | 3 devices |
| Apple Developer Program (paid) | 1 year | 100 iPads a year |

## Update the bundled blocking script

The app ships with a copy of the blocking script at `TubeClean/Resources/tubeclean.js`. To refresh it after rebuilding `tubeclean-rules` (both repos must sit side by side):

```sh
scripts/sync-rules.sh      # copies ../tubeclean-rules/dist/tubeclean.js into the app
```

Then rebuild. Installed apps also download new versions themselves from `TCRulesURL` in `Info.plist`. Until the public `tubeclean-rules` repo exists, that download fails quietly and the app uses its bundled copy.

## Layout

| Path | What it is |
|---|---|
| `project.yml` | XcodeGen spec: targets, iPadOS 26 minimum, bundle ID `uk.co.ilmaris.tubeclean`, signing team |
| `TubeClean/TubeCleanApp.swift` | App entry point: the web view with the splash screen on top |
| `TubeClean/BrowserController.swift` | The web view: script injection, navigation lock, consent cookie, full screen, crash recovery |
| `TubeClean/NavigationPolicy.swift` | Which URLs may load; Shorts and the mobile site are redirected. Pure and unit-tested |
| `TubeClean/RulesStore.swift` | Chooses between the bundled, cached and downloaded blocking script. The newest valid version wins |
| `TubeClean/SplashView.swift` | Logo and spinner until YouTube's first page shows; "Try again" if YouTube can't be reached |
| `TubeClean/Resources/tubeclean.js` | Bundled copy of `tubeclean-rules/dist/tubeclean.js` |
| `TubeClean/Assets.xcassets` | App icon and splash logo |
| `TubeCleanTests/` | Unit tests for the navigation policy and the script header check |
| `scripts/sync-rules.sh` | Copies the latest built blocking script into the app |
| `scripts/mac-test.sh`, `scripts/mac-sim.sh` | Used by the Linux build server to drive this Mac over SSH. Not needed on the Mac itself |

## Debugging

**Logs:** Xcode's console (⇧⌘Y), or Console.app filtered to subsystem `uk.co.ilmaris.tubeclean`. The blocking script reports what it removed as `page: {...}` lines.

**Inspect the page:** in Safari on the Mac, open **Develop → (simulator or iPad) → YouTube**. This works in debug builds only.

**Launch arguments** (debug builds only; set them in Xcode under Product → Scheme → Edit Scheme → Run → Arguments):

| Argument | Effect |
|---|---|
| `-TCStartURL <url>` | Open this page instead of the home page |
| `-TCNoRules YES` | Run without the blocking script, to compare |
| `-TCMuted YES` | Mute all video and audio |
| `-TCEvalJS <base64>` | Run JavaScript once after the first page loads, and log the result |

## Known limits

- **It's an arms race.** YouTube changes; uBlock Origin's maintainers usually respond within days. Rebuilding `tubeclean-rules` picks up their fixes.
- **Ads built into the video stream** (server-side insertion) can't be removed. The fallback mutes them and presses Skip.
- **H.264 only, up to 1080p.** The script asks YouTube for H.264, which every iPad decodes in hardware. AV1 also stalls in the simulator.
- **The "Shorts" search filter** is matched by its English label. In another language it stays visible, but Shorts links still go to the home page.
