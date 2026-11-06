#!/bin/bash
# Builds a Release copy of Desktop Buddy and puts it in /Applications, so Coco opens from
# Spotlight, Launchpad or the Dock without Xcode. Rerun it after changing the code to update
# the installed copy; it doesn't change anything Xcode builds.
#
#   scripts/install-app.sh
#
# It's signed with the same team and bundle identifier as the Xcode build, so both copies
# share one set of tasks, settings and sign-ins. Only one Coco runs at a time: running from
# Xcode quits the installed copy, and opening the installed copy while the Xcode one is up
# just brings that one forward.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=/Applications/Coco.app
BUILT=build/install/Build/Products/Release/Coco.app
OLD=/Applications/DesktopBuddy.app   # what this script installed before the app was named Coco

if pgrep -f "^($DEST/Contents/MacOS/Coco|$OLD/Contents/MacOS/DesktopBuddy)" >/dev/null; then
    echo "The installed Coco is running. Quit it first (right-click Coco → Quit), then rerun." >&2
    exit 1
fi

if pgrep -f "xcodebuild.*-derivedDataPath build/install" >/dev/null; then
    echo "An install is already building. Wait for it to finish (it can take a few minutes)." >&2
    exit 1
fi

echo "Building Release…"
xcodebuild -project DesktopBuddy.xcodeproj -scheme DesktopBuddy -configuration Release \
    -derivedDataPath build/install -quiet build

codesign --verify --strict "$BUILT"
rm -rf "$DEST" "$OLD"
ditto "$BUILT" "$DEST"
# ditto keeps the bundle's old date, and the Dock keys a pinned tile's cached icon on it —
# a fresh date makes the Dock pick up a changed app icon.
touch "$DEST"
echo "Installed $DEST — open it with Spotlight (\"Coco\") or from Launchpad."
