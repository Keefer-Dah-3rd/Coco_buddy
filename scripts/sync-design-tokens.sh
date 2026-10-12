#!/bin/bash
# Brings a Figma token export into the app and shows what it changed on screen.
#
#   scripts/sync-design-tokens.sh path/to/coco-tokens.json
#
# 1. Renders "before" snapshots from the current code.
# 2. Applies the export to design/tokens.json and regenerates
#    DesktopBuddy/Generated/DesignTokens.generated.swift (validated; nothing is written if it's invalid).
# 3. Rebuilds, renders "after" snapshots and pixel-diffs them → build/design-sync/diff/*.png.
# 4. Runs the token tests, the Figma map check and the package tests.
#
# It never commits. Review the diff images and `git diff`, then commit — or `git checkout design DesktopBuddy/Generated`.
# The export comes from the Coco Tokens Figma plugin (design/figma/plugin) or Claude via the Figma MCP.
set -euo pipefail

cd "$(dirname "$0")/.."
EXPORT="${1:?usage: scripts/sync-design-tokens.sh path/to/coco-tokens.json}"
OUT=build/design-sync
APP="$OUT/derived/Build/Products/Debug/DesktopBuddy.app/Contents/MacOS/DesktopBuddy"

build_and_render() {
  # An unsandboxed, ad-hoc signed Debug build — only for rendering snapshots.
  if ! xcodebuild -project DesktopBuddy.xcodeproj -scheme DesktopBuddy -configuration Debug \
      -derivedDataPath "$OUT/derived" ENABLE_APP_SANDBOX=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
      build >"$OUT/build.log" 2>&1; then
    grep -E "error:" "$OUT/build.log" | head -20
    echo "Build failed — see $OUT/build.log" >&2
    exit 1
  fi
  rm -rf "$1"
  "$APP" --snapshots "$1" >/dev/null 2>&1
}

mkdir -p "$OUT"
echo "▸ Checking the export…"
python3 -I scripts/tokens/apply_figma_export.py "$EXPORT" --dry-run | tee "$OUT/changes.txt"
if grep -q "^No token changes" "$OUT/changes.txt"; then
  exit 0
fi

echo "▸ Rendering “before” snapshots…"
build_and_render "$OUT/before"

echo "▸ Applying the export…"
python3 -I scripts/tokens/apply_figma_export.py "$EXPORT"

echo "▸ Rebuilding and rendering “after” snapshots…"
build_and_render "$OUT/after"

echo "▸ Visual diff (red = changed pixels) → $OUT/diff"
swiftc -O scripts/visual-diff.swift -o "$OUT/visual-diff" 2>/dev/null
"$OUT/visual-diff" "$OUT/before" "$OUT/after" "$OUT/diff" || true
echo "  (connections-connected and panel-connected also differ between any two runs: they show the clock.)"

echo "▸ Tests…"
python3 -m unittest discover -s scripts/tokens -q
python3 -I scripts/tokens/check_figma_map.py
python3 -I scripts/tokens/build_plugin.py --check
(cd Packages/BuddyKit && swift test 2>&1 | grep -E "Test run|error" | tail -1)

echo "▸ Done. Review $OUT/diff and \`git diff design DesktopBuddy/Generated\`, then commit."
