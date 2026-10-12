# TubeClean

An iPad app for watching YouTube without ads or Shorts. It's for internal family use and isn't distributed.

It's one web view locked to `www.youtube.com`. Google sign-in works, so he stays signed in to his own account. Before each page loads, the app injects a blocking script that:

- strips ad data out of YouTube's responses before the player reads them
- removes Shorts from feeds, search, menus and channel tabs
- sends any Shorts link to the home page
- hides any ad element that still slips through

The script lives in the sibling repo `tubeclean-rules`. A copy is bundled in the app. The app also downloads newer versions from GitHub, so fixing a YouTube change doesn't need a rebuild.

## Layout

| Path | What it is |
|---|---|
| `TubeClean/BrowserController.swift` | The web view, script injection, navigation lock, consent cookie |
| `TubeClean/NavigationPolicy.swift` | Which URLs may load; Shorts → home. Pure, unit-tested |
| `TubeClean/RulesStore.swift` | Bundled, cached and downloaded script. Newest valid version wins |
| `TubeClean/Resources/tubeclean.js` | Bundled copy of `tubeclean-rules/dist/tubeclean.js` |
| `TubeCleanTests/` | Unit tests (navigation policy, rules parsing) |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, not committed |
| `scripts/sync-rules.sh` | Copy the latest built rules into the app |
| `scripts/mac-test.sh` | From the Linux sandbox: rsync to the Mac, run the unit tests on an iPad simulator |
| `scripts/mac-sim.sh` | From the sandbox: build, launch on the simulator at a URL, print the page reports, take a screenshot |

## Build and install on his iPad

You need Xcode 27 and XcodeGen. The copy at `~/.local/xcodegen/bin/xcodegen` on Lee's Mac works.

1. `cd tubeclean && ~/.local/xcodegen/bin/xcodegen generate`
2. `open TubeClean.xcodeproj`
3. Target TubeClean → Signing & Capabilities → choose your Team.
   - Free Apple ID: the install expires after 7 days.
   - Paid developer account: it lasts a year.
4. Plug in the iPad and trust the Mac. The first time, turn on Developer Mode on the iPad: Settings → Privacy & Security → Developer Mode.
5. Choose the iPad as the run destination and press Run (⌘R).
6. In the app, tap **Sign in** and sign in to his Google account.

## Updating the blocking rules

In `tubeclean-rules`:

```
node gen/generate.mjs        # pull the latest uBlock Origin YouTube rules
node build.mjs               # write dist/tubeclean.js with a new version
git commit -am "rules" && git push
```

Every 6 hours the app checks `TCRulesURL` in Info.plist (the raw GitHub URL of `dist/tubeclean.js`). It installs the file only if it is a valid TubeClean rules file with a higher version number. Until the public repo exists, the download fails quietly and the app keeps the bundled copy.

To refresh the bundled copy as well: `scripts/sync-rules.sh`, then rebuild.

## Test hooks (launch arguments)

| Argument | Effect |
|---|---|
| `-TCStartURL <url>` | Open this page instead of the home page |
| `-TCNoRules YES` | Run without the blocking script (for comparison) |
| `-TCEvalJS <base64>` | Debug builds only: run JavaScript once after the first page loads, and log the result |

Logs use subsystem `uk.co.ilmaris.tubeclean`. The blocking script sends a status report (`page: {...}`) every 2 seconds when something changes.

## Known limits

- **It's an arms race.** YouTube changes; uBlock Origin's maintainers respond, usually within days. Regenerating and pushing the rules picks up their fixes.
- **Ads built into the video stream** (server-side ad insertion) can't be removed by any blocker. When that happens, the fallback mutes the ad and skips to its end.
- **H.264 only.** The script hides AV1 and VP9 from YouTube, so it serves H.264. Every iPad decodes H.264 in hardware. The cost is that 1440p and 4K are not offered.
- **The "Shorts" search filter** is matched by its English label. A non-English interface would still show it, but Shorts links still redirect home.
