#!/bin/sh
# Copy the latest built rules from the sibling tubeclean-rules repo into the
# app bundle resources, so a fresh install works offline.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
src="${RULES_REPO:-$here/../tubeclean-rules}/dist/tubeclean.js"
cp "$src" "$here/TubeClean/Resources/tubeclean.js"
head -1 "$here/TubeClean/Resources/tubeclean.js"
