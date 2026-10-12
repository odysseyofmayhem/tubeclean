#!/bin/sh
# Run from the sandbox: copy the repo to Lee's Mac, generate the Xcode
# project and run the unit tests on an iPad simulator.
#   scripts/mac-test.sh [extra xcodebuild action, default: test]
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
mac=${MAC_HOST:-lees-mac}
dest=${MAC_DIR:-Projects/Ilmaris/tubeclean-build}
action=${1:-test}
rsync -a --delete --exclude .git --exclude build -e 'ssh -o BatchMode=yes' "$here/" "$mac:$dest/"
ssh -o BatchMode=yes "$mac" "cd $dest && ~/.local/xcodegen/bin/xcodegen generate -q && \
  xcodebuild -project TubeClean.xcodeproj -scheme TubeClean \
    -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
    -derivedDataPath build/dd $action 2>&1 | \
  grep -E 'error:|warning:|Test Case .*(passed|failed)|Executed|BUILD|TEST ' | grep -v 'appintentsmetadataprocessor' | head -80"
