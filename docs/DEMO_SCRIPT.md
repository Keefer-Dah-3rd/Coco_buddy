# 60-second demo

A screen recording for a portfolio page or a LinkedIn post. It shows Coco as a character first and a tool second, and ends on the craft: energy, privacy and confirmation before every change.

## Before you record

- **Build:** Release (*Edit Scheme › Run › Build Configuration › Release*), so the frame rate and CPU match what you'll claim.
- **Desktop:** a clean wallpaper with plenty of contrast behind Coco (a mid-tone works for both her black and white fur). Hide desktop icons:

  ```bash
  defaults write com.apple.finder CreateDesktop false && killall Finder
  ```

  Turn them back on afterwards with `true`.
- **Notifications:** turn on Do Not Disturb, except for Desktop Buddy (System Settings › Focus › Do Not Disturb › Allowed Apps).
- **Data:** start from Settings › *Delete all my data* so the welcome shows. Have the Claude key and Google Calendar connected *after* the welcome (or keep a second user account set up for demos). Put one real meeting on today's calendar about 40 minutes out.
- **Focus length:** Settings › Focus › 5 min. You'll speed up the wait in the edit.
- **Sound:** barks and voice on, system volume at about 60%. Record system audio with QuickTime or a tool like Audio Hijack. The barks sell it.
- **Capture:** ⌘⇧5 › *Record Selected Portion*, 1920×1080 around the bottom-right quarter of the screen, with *Show Mouse Clicks* on.

## Shot list

| Time | On screen | Do | Caption (or voice-over) |
| --- | --- | --- | --- |
| 0:00–0:05 | Empty desktop, Coco idle in the corner | Do nothing. Let her blink, glance and flick an ear | **Meet Coco.** A desktop corgi who helps you plan your day |
| 0:05–0:09 | Coco follows the cursor | Sweep the mouse past her slowly, then drag her up and drop her | Native macOS · Swift + Core Animation |
| 0:09–0:16 | Panel opens | Click her (she barks). Type `Finish homepage hero ~45m !!` and press Return, then `Send invoices @today` and Return | Tasks in plain language: estimates, priority, today-only |
| 0:16–0:24 | Voice | Press ⌘L and say *"Review three portfolio projects for an hour and email Sam"*. Two drafts appear; press **Add** | Talk to her. Nothing is added until you say so |
| 0:24–0:33 | Chat | ⌘3, then type *"What should I do before my 2 o'clock?"*. She thinks, then talks as the reply streams. The *Looked at your tasks and calendar* marker shows | Ask Claude about your day. It only sees your tasks when it needs to, and the chat shows it each time |
| 0:33–0:38 | Chat proposes focus | Reply *"start focus on the homepage"*. The panel tucks away | One click, and you're focusing |
| 0:38–0:46 | Focus | Coco on guard, the progress ring filling around her tag, the countdown in the menu bar. **Speed-ramp** this stretch to 8×. The chime and celebration play at the end | Quiet while you work. About 1% CPU at idle |
| 0:46–0:51 | The "Did you finish?" card | Click **Yes, done**. The task ticks; she hops and barks | She never marks anything done by herself |
| 0:51–0:56 | Global shortcut | Switch to a browser, press ⌃⌥C, and the panel pops up over it; press Esc | ⌃⌥C from anywhere · fully keyboard- and VoiceOver-friendly |
| 0:56–1:00 | Coco dozing | Cut to her napping (airplane ears, Zs), then fade out on the app icon | **Desktop Buddy** · github.com/Keefer-Dah-3rd/Coco_buddy |

## Notes

- Keep the cursor still when you aren't demonstrating something; her eyes follow it.
- If a chat reply runs long, trim the middle of the stream in the edit rather than re-recording.
- To get the nap shot without waiting 5 minutes, use menu bar › *Animation Preview › Sleeping*.
- Export 1080p at 30 fps (60 fps if the platform keeps it; the motion is smoother). Add captions as burned-in text, since most feeds play muted, but keep the barks in the audio.
- A still for the thumbnail: the 0:38 frame (Coco on guard with the ring half full) or `docs/images/character-light.png`.
