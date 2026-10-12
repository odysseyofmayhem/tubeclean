#!/bin/sh
# Run from the sandbox: build the app for the iPad simulator on Lee's Mac,
# launch it on a page, wait, then print the app's page reports and save a
# screenshot to build/sim-<n>.png on the Mac (copied back to ./build/).
#   scripts/mac-sim.sh <url> [seconds]
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
mac=${MAC_HOST:-lees-mac}
dest=${MAC_DIR:-Projects/Ilmaris/tubeclean-build}
url=${1:-https://www.youtube.com/}
secs=${2:-25}
EXTRA=${3:-}
sim='iPad Air 11-inch (M4)'
rsync -a --delete --exclude .git --exclude build -e 'ssh -o BatchMode=yes' "$here/" "$mac:$dest/"
ssh -o BatchMode=yes "$mac" "set -e; cd $dest && ~/.local/xcodegen/bin/xcodegen generate -q
xcodebuild -project TubeClean.xcodeproj -scheme TubeClean -destination 'platform=iOS Simulator,name=$sim' \
  -derivedDataPath build/dd build 2>&1 | grep -E 'error:|BUILD' || true
app=build/dd/Build/Products/Debug-iphonesimulator/TubeClean.app
xcrun simctl boot '$sim' 2>/dev/null || true
xcrun simctl bootstatus '$sim' -b >/dev/null
xcrun simctl install '$sim' \$app
xcrun simctl terminate '$sim' uk.co.ilmaris.tubeclean 2>/dev/null || true
start=\$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl launch '$sim' uk.co.ilmaris.tubeclean -TCStartURL '$url' $EXTRA >/dev/null
sleep $secs
n=\$(date +%s); xcrun simctl io '$sim' screenshot build/sim-\$n.png >/dev/null 2>&1; echo shot build/sim-\$n.png
xcrun simctl spawn '$sim' log show --info --debug --style compact --start \"\$start\" \
  --predicate 'subsystem == \"uk.co.ilmaris.tubeclean\"' 2>/dev/null | grep -v '^Timestamp' | cut -c 1-400 | tail -40"
mkdir -p "$here/build"
rsync -a -e 'ssh -o BatchMode=yes' "$mac:$dest/build/sim-*.png" "$here/build/" 2>/dev/null || true
