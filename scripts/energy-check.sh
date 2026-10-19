#!/bin/bash
# Measures Desktop Buddy's CPU, idle wake-ups and memory in a few scenarios, using a Release
# build under its own identity and its own home folder, so it never touches the real app's
# settings or data and doesn't hand over to a copy that's already running.
#
#   xcodebuild -project DesktopBuddy.xcodeproj -scheme DesktopBuddy -configuration Release \
#     -derivedDataPath build/energy build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
#     ENABLE_APP_SANDBOX=NO PRODUCT_BUNDLE_IDENTIFIER=com.keefer.DesktopBuddy.energy
#   scripts/energy-check.sh build/energy/Build/Products/Release/DesktopBuddy.app hidden idle panel focus
#
# Each scenario settles for 15 s, then CPU time is measured over 30 s (`ps` time, not the
# smoothed %CPU). Don't use the Mac while it runs: moving the mouse near Coco makes her look
# at it, and the last column says how long the Mac had no input when the window ended.
set -u
APP="$1/Contents/MacOS/DesktopBuddy"; shift
D=com.keefer.DesktopBuddy.energy
cpu() { ps -o time= -p "$1" | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
hid() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
for SCENARIO in "$@"; do
  HOMEDIR=$(mktemp -d)
  mkdir -p "$HOMEDIR/Library/Preferences" "$HOMEDIR/Library/Application Support/DesktopBuddy"
  export CFFIXED_USER_HOME="$HOMEDIR"
  defaults write $D buddy.onboardingCompleted -bool YES
  defaults write $D buddy.lastGreetingDay "$(date +%Y-%m-%d)"
  defaults write $D buddy.chatter -bool NO
  [ "$SCENARIO" = hidden ] && defaults write $D buddy.visible -bool NO
  if [ "$SCENARIO" = focus ]; then
    printf '{"duration":1500,"focusStreak":0,"phase":"focus","status":{"running":{"endsAt":"%s"}}}' \
      "$(date -u -v+25M +%Y-%m-%dT%H:%M:%SZ)" > "$HOMEDIR/Library/Application Support/DesktopBuddy/focus.json"
  fi
  "$APP" >/dev/null 2>&1 & PID=$!
  sleep 6
  # A second copy hands over to the first, which opens its panel (see SingleInstance).
  [ "$SCENARIO" = panel ] && "$APP" >/dev/null 2>&1
  sleep 9
  T0=$(cpu $PID); sleep 30; T1=$(cpu $PID); IDLE=$(hid)
  WAKE=$(top -l 2 -s 5 -pid $PID -stats pid,idlew | tail -1 | awk '{print $2}')
  RSS=$(ps -o rss= -p $PID)
  echo "$SCENARIO: $(echo "scale=2; ($T1-$T0)*100/30" | bc)% of one core, ${WAKE} idle wake-ups per 5 s, $((RSS/1024)) MB, no input for ${IDLE}s"
  kill $PID; wait $PID 2>/dev/null
  rm -rf "$HOMEDIR"
done
