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

## Fetch (hold Right ⌘, click)

- [ ] Hold Right ⌘: after a moment a tennis ball appears under the cursor; let go and it's gone. Quick ⌘C / ⌘V presses never show it. Left ⌘ does nothing.
- [ ] Click while holding: the app underneath gets no click. The ball arcs from beside Coco, spinning, bounces lower each time and rolls to a stop where you clicked (or a little past).
- [ ] She looks at the ball, then sets off before it hits the ground, and gets there as it settles.
- [ ] She slows, lowers her head, and the ball is in her mouth at that moment — no gap, no jump.
- [ ] She turns round, runs back carrying it, faces you, drops it at her paws and sits back down exactly where she started.
- [ ] Throw toward the menu bar, the Dock, or off the screen: the throw is shortened so she can reach it.
- [ ] Throw so the ball lands right next to her: she still picks it up and brings it back.
- [ ] Mid-game, hold Right ⌘ or Right ⌥: nothing appears; one game at a time.
- [ ] Grab her mid-run: she stops, and the ball ends up on the floor (by her, if she was carrying it).
- [ ] Throw while she's running somewhere you called her: she stops and plays fetch from there.
- [ ] Settings: switch "Play fetch" off; Right ⌘ does nothing.

## Treats (hold Right ⇧, click)

- [ ] Hold Right ⇧ a moment: she sits up and begs, front paws raised and pawing, eyes on the treat under your cursor. Typing capitals never sets it off; left ⇧ does nothing. Let go without clicking: she settles back down.
- [ ] Click: the app underneath gets no click. The treat flips through a low arc, bounces once and skids a little.
- [ ] She follows it with her eyes, sets off before it lands, slows, puts her head down and the treat vanishes exactly as she bites.
- [ ] A few chomps, a lick of the lips, then a crouch, a jump straight up with sparkles, a soft landing, a wag, and she sits — in the same spot.
- [ ] During a treat, Right ⌘ / Right ⌥ / Right ⇧ do nothing; during fetch, Right ⇧ does nothing (no begging).
- [ ] Grab her before she eats it: the treat is left lying where it landed (it fades after a while).
- [ ] Settings: switch "Give her a treat" off; Right ⇧ does nothing.

## Personality and chatter

- [ ] Give her a treat: once she sits back down, she says a treat line ("Mm. Crunchy. Ten out of ten."). A second treat within 10 minutes gets an "another one?" line.
- [ ] Play fetch: when she drops the ball she says a fetch line; a second round gets an "again?" line.
- [ ] Open her panel after a few quiet minutes: the header says a hello ("Hi hi hi. What are we doing?"). Open it again straight away: the line doesn't change.
- [ ] Leave her alone in Interactive presence for about 30 minutes: one short comment at most. Nothing during a focus session, a break, a calendar meeting, or while you're away.
- [ ] Settings: switch off "Coco chats now and then"; she stays quiet unless something happens.
- [ ] Chat: run a few of the example conversations in docs/PERSONALITY.md. Serious messages get calm replies with no jokes; planning questions get the answer first.

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

## Apple Calendar and one schedule

- [ ] Fresh install (or reset with `tccutil reset Calendar com.keefer.DesktopBuddy`): launching never asks for calendar access. Connections › Apple Calendar › **Connect**: macOS asks once, naming Desktop Buddy and the reason.
- [ ] Choose **Don't Allow**: the card says access is off and how to turn it on; Google Calendar, tasks and the chat keep working; the chat says it can't see Apple Calendar rather than guessing.
- [ ] Allow it in System Settings › Privacy & Security › Calendars, then **Check again**: Connected, today's count and your calendars with switches (birthdays and holidays off).
- [ ] With your Google account in Calendar.app too: every Google meeting shows **once** on the Today card and in the week, and the day's count matches Google Calendar. Hover a row: the tooltip lists both calendars.
- [ ] An event only in iCloud shows with a small "Apple · Home" label; it counts for open time and reminders.
- [ ] Two different meetings at different times on the same day, two overlapping meetings, and a repeating meeting all show as separate rows (each occurrence on its own day).
- [ ] An all-day event across two days shows on both and not the third; a late event running past midnight shows on both days with ← / →.
- [ ] Add, move and delete an event in Calendar.app: Coco's card updates within a second or two, without reopening anything.
- [ ] Turn off a calendar's switch in Connections: its events disappear; on again, they return.
- [ ] Chat: "What's on my calendar today?", "What do I have coming up?", "What's my next meeting?", "Am I free this afternoon?", "When is my next meeting with <someone invited to an Apple event>?" and "How much free time do I have between meetings?" — answers match the Today card, with no meeting counted twice.
- [ ] Chat: ask to move or delete an Apple-only event: Coco says it's read-only here and to change it in Calendar. Ask to move a meeting that's in both: the card changes the Google event (and says so if the Apple copy is a separate copy that won't follow).
- [ ] Revoke access in System Settings while Coco runs: Apple events disappear and the card shows the access-off state; Google events stay.
- [ ] *Stop using Apple Calendar*: Apple events disappear; System Settings still shows access granted.
- [ ] A day with no events: "No meetings today — wide open." After the last meeting: "That's all for today — no more meetings." *Coming up* lists the next days with "Tomorrow", a weekday or a date.

## Partiful invites (chat)

- [ ] Paste a public Partiful link (partiful.com/e/…): the chat shows "Read the Partiful invite …" and Coco gives the title, day, time and place — no invented details.
- [ ] Ask "add this to my calendar": a card appears with the right local time and "From Partiful"; nothing is created until you click Add. After Add, the calendar card jumps to that day and the event is there, with the invite link in its description.
- [ ] Paste the same link again and ask to add it: Coco says it's already on your calendar; no second card or event.
- [ ] An event in another time zone (e.g. a Los Angeles party from New York): Coco gives both times; the card shows your local time.
- [ ] An invite with no end time: Coco asks how long to block before proposing.
- [ ] A go.partiful.com short link works the same as the full link.
- [ ] A mistyped/deleted link, a password-protected invite, or a non-Partiful link: Coco says why she can't read it and offers to work from pasted invitation text.
- [ ] "Do I have anything else that day?" after reading an invite: she checks the calendar for that date.
- [ ] Offline: she says the Mac seems offline; nothing is cached as a failure.

## Partiful import (Connections › Partiful)

- [ ] Paste an invite link (partiful.com/e/…) instead of the calendar link: it explains the difference and doesn't connect.
- [ ] Paste your personal calendar link (calendar icon under an event → Google Calendar → Copy Link): "Connected", the upcoming count and the next three events appear.
- [ ] Your Partiful events show in the Today card and the week browser, tagged Partiful, and can't be moved or deleted from Coco.
- [ ] An event that's also in Google Calendar (e.g. from Partiful's own Google sync) shows once, not twice.
- [ ] Ask the chat "am I free Saturday evening?": Partiful events count as busy.
- [ ] A private invite you're on (page won't load publicly): pasting its link in chat still gives the details, from your calendar.
- [ ] Quit and reopen offline: the last Partiful events still show; the card says why it couldn't refresh.
- [ ] Disconnect: events disappear from the calendar card; the link is gone from the Keychain.

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
