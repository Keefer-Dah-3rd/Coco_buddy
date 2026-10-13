# QA checklist

Manual checks for the things unit tests can't reach: windows, displays, system events and assistive tech. Run them on a Release build (*Product › Scheme › Edit Scheme › Run › Build Configuration › Release*) before recording a demo or tagging a version. The logic underneath (timer maths, planner, parsing, calendar free time, assistant tools) is covered by `cd Packages/BuddyKit && swift test`.

Tick each box as you go. If a check fails, note the macOS version and what you saw.

## First launch

- [ ] Reset first: Settings › *Delete all my data…* › *Delete everything*. The welcome window appears.
- [ ] Welcome step 2: type a task and press Return. It appears under the field and in the Today panel.
- [ ] Welcome step 3: the voice switch, *Set up…* and *Add key…* don't trigger any macOS permission prompt by themselves.
- [ ] Closing the welcome window with the red button doesn't show it again on the next launch.
- [ ] *Start* closes it. Coco barks once and says "All set!".

## Displays

- [ ] Drag Coco to a second display, quit and relaunch. She comes back on that display.
- [ ] Unplug that display while she's on it. She moves to a visible spot on the remaining screen, not off-screen.
- [ ] Change the resolution (System Settings › Displays). She stays fully visible.
- [ ] Open the panel near the edge of a screen. The panel opens on the side with room and doesn't cross onto the other display.
- [ ] Move the Dock to the side or the bottom, and turn auto-hide on and off. Coco never sits under the Dock.

## Spaces and full screen

- [ ] Switch Spaces (⌃→). Coco is on every Space, in the same place.
- [ ] Put an app in full screen. Coco is visible over it (unless *Keep above other windows* is off), and the panel opens over it.
- [ ] Mission Control (F3). Coco doesn't appear as a window to pick.
- [ ] ⌘Tab. Desktop Buddy isn't in the app switcher; the panel never steals focus from the app you're typing in.

## Sleep and wake

- [ ] Start a 25-minute focus session and close the lid for 30+ minutes. On wake, the session shows as finished (once). The Focus tab asks whether the task got done, and doesn't tick it by itself.
- [ ] Pause a session, sleep for 5 minutes, wake. It's still paused with the same time left.
- [ ] Sleep mid-chat while a reply is streaming. On wake, the chat shows an error or the finished reply, never a spinner forever. *New chat* works.
- [ ] Sleep with the mic open. On wake, the mic is closed and nothing half-heard was added.

## Date change

- [ ] Leave the app running past midnight, or set the clock forward a day. *Today* updates without relaunching: the done count resets, *Up next* changes, the schedule strip shows the new day.
- [ ] A today-only task left unfinished yesterday shows *Carry over* / *Let go*.
- [ ] Meeting reminders still fire for the new day's meetings.
- [ ] Coco greets once on the new day.

## Offline and failures

- [ ] Turn Wi-Fi off and open the panel. The calendar strip says it's offline; the tasks and the focus timer work normally.
- [ ] Ask the chat something while offline. A clear error appears instead of a spinner, and sending again works once you're back online.
- [ ] Turn Wi-Fi back on. The calendar catches up on its next refresh (every 10 minutes, and on wake or a new day).
- [ ] In Connections, paste an invalid Claude key. It's rejected with a reason and nothing is saved.
- [ ] Revoke the app's access at myaccount.google.com › Security › Third-party access. Connections then shows *Reconnect*; nothing crashes.

## Calendar: week, availability and changes

- [ ] Today › calendar › **Week**: the strip shows this week with today marked. Click another day, drag across the strip (past the edge keeps going into the next week), and use ←/→, ⇧←/⇧→ and T. The day list updates at once for loaded weeks and shows *Loading…* for new ones.
- [ ] A day with back-to-back meetings shows no open time between them; a day with nothing shows "Nothing scheduled — open …".
- [ ] An all-day event sits at the top; an event that runs past midnight shows on both days with ← / →.
- [ ] A repeating event shows the repeat mark on each occurrence.
- [ ] Chat: "What does my week look like?", "Am I free Thursday afternoon?", "Which day is lightest?" — the chat says it looked at the calendar, and the answers match the week browser.
- [ ] Chat: "Find a 30-minute opening Thursday" — every suggestion is genuinely open in the browser.
- [ ] Chat: "Schedule a design review next Tuesday at 2" — a card shows the date, time and any clash. *Not now* changes nothing. *Add*: the first time, Google's sheet asks to allow changes; afterwards the event appears in Google Calendar and on that day in the browser, and the chat is told.
- [ ] Ask to move it to Wednesday, then to delete it. Each time a card asks first; the event keeps its id (no duplicate) and Google Calendar matches.
- [ ] Ask to delete a meeting someone else organised: Coco says she can't.
- [ ] Add an event in Google Calendar on the web, reopen the panel a few minutes later: it appears.
- [ ] Decline Google's permission sheet: the card says nothing changed.
- [ ] Settings › Your day: change the workday start/end; open time and Coco's suggestions follow.

## Global shortcut

- [ ] ⌃⌥C from another app opens the panel; pressing it again closes the panel.
- [ ] Hide Coco from the menu, press ⌃⌥C. She reappears with the panel open.
- [ ] Settings: switch the shortcut off. ⌃⌥C does nothing. Switch it on again; it works.
- [ ] Give ⌃⌥C to another app (e.g. a Shortcuts keyboard shortcut) and relaunch Desktop Buddy. Settings explains the shortcut is taken.

## Calling Coco (hold Right ⌥, click)

- [ ] Hold Right ⌥: the circle appears under the cursor right away and her eyes follow it. Let go: it disappears. Left ⌥ does nothing.
- [ ] Click while holding: the app underneath gets no click. She spots the place, play-bows, dashes there and sits facing you.
- [ ] Click on the menu bar or Dock: she stops at the nearest spot where she's fully visible, and the marker shows that spot.
- [ ] Click again mid-run: she curves to the new spot without stopping. Call her again while she's braking: she sets straight off.
- [ ] Grab her mid-run: she stops where she is. Her speech bubble hides while she runs and comes back when she arrives.
- [ ] Two displays: call her across to the other one.
- [ ] Reduce Motion on: she fades out and back in at the spot.
- [ ] Settings: switch "Call Coco over" off; Right ⌥ does nothing.

## Keyboard

- [ ] Open the panel, type a task, press Return. Press ↓ to enter the list.
- [ ] ↑/↓ move the selection (a bar on the left of the row). ↑ from the first row returns to the add field.
- [ ] Space ticks or unticks. Return edits. ⌫ deletes, offers *Undo*, and selects the next task. F starts focus on the selected task.
- [ ] ⌘1 / ⌘2 / ⌘3 switch tabs. Esc closes the panel. ⌘L talks. ⌘. stops a reply.
- [ ] Settings and Welcome: Tab moves through every control. Return triggers *Next* / *Start*.

## VoiceOver (⌘F5)

- [ ] Coco on the desktop is announced as "Coco, your desktop corgi", a button, with her current state. VO-Space opens the panel.
- [ ] Task rows read the title, priority, due date and estimate. A selected row is announced as selected.
- [ ] Segmented controls (Presence, During focus, reminders) read each option in normal case and mark the selected one.
- [ ] Settings toggles are read once, with their label. Focus steppers read "Focus length, 25 minutes".
- [ ] Section titles in Settings and the step titles in Welcome are headings (VO-⌘H jumps between them).
- [ ] The decorative Coco in the welcome window is skipped. Each shortcut row reads as one phrase, e.g. "Open Coco from any app: Control Option C".

## Appearance and motion

- [ ] Switch Light/Dark while the panel, Settings and Welcome are open. Everything recolours; no unreadable text.
- [ ] Turn on Reduce Motion (Accessibility › Display). No hops or squash; state changes still show.
- [ ] Turn on Increase Contrast. Borders and text remain visible.
- [ ] Turn on Low Power Mode. Idle animation slows; nothing breaks.

## Sound and voice

- [ ] Tick a task outside focus: one bark. During focus: a soft pop, no bark.
- [ ] Settings › *Barks* off: no barks, other sounds remain. *Mute all sounds*: silence, including her voice.
- [ ] Voice on: lines are spoken and her mouth moves with them. She never hears herself while the mic is open.

## Energy

Quit any Xcode-launched copy first so only one Coco is running.

- [ ] Launch the Release build, leave it idle with the panel closed for 2 minutes, then sample for 30 s:

  ```bash
  top -l 7 -s 5 -stats pid,command,cpu,mem | grep DesktopBuddy
  ```

  Expect about 1% CPU or less, and under 60 MB.
- [ ] Cover Coco with a full-screen window. CPU drops to near 0%.
- [ ] Hide Coco. CPU drops to near 0%.

## Privacy

- [ ] After *Delete all my data*: the task list is empty, Connections shows nothing connected, and Keychain Access has no `com.keefer.DesktopBuddy` items.
- [ ] Use the chat without asking about your day. No *Looked at your tasks and calendar* marker appears.
