# Desktop Buddy

A native macOS desktop companion. **Coco** — a black-and-white corgi with a white blaze, giant ears and a collar tag — sits on your desktop, keeps your daily list, runs focus sessions, listens when you talk to her, and reacts to what you do. Part Clippy, part virtual pet, part productivity tool; built to stay open all day without getting in the way.

![Coco's states](docs/images/character-light.png)

| Today | Voice: review what Coco heard | Focus (dark mode) |
| --- | --- | --- |
| ![Today panel](docs/images/panel-today-light.png) | ![Voice review](docs/images/panel-voice-review.png) | ![Focus panel](docs/images/panel-focus-dark.png) |

## Status

**Phase 1 — native desktop prototype: done**, plus Coco and voice. Floating character, drag & position memory, panel, tasks (persisted), focus timer with notifications, spoken lines, and voice input for tasks and timer commands.
Next: Phase 2 (daily planning), Phase 3 (Google Calendar + Notion), Phase 4 (assistant). See [docs/INTEGRATIONS_SETUP.md](docs/INTEGRATIONS_SETUP.md).

## Build & run

Requirements: macOS 14+, Xcode 16+ (developed with Xcode 26.5).

1. Open `DesktopBuddy.xcodeproj` and press **⌘R**.
   - The project signs with **John Keefe (Personal Team)**. If Xcode says it can't sign, open *Xcode › Settings › Accounts*, select the Apple ID and sign in again if asked; then build again — Xcode creates the development certificate automatically.
   - Stable signing matters here: macOS ties microphone and speech permissions (and later, Keychain items) to the app's signature, so an ad-hoc build would ask again after every rebuild.
2. Coco appears in the bottom-right corner. The app has no Dock icon — look for her head in the **menu bar**; that's her home (show/hide, voice, settings, quit).

Unit tests (models, timer, voice parsing, animation math) run without launching the app:

```bash
cd Packages/BuddyKit && swift test
```

## Try it

| Do this | Expect |
| --- | --- |
| Hover near Coco | Her eyes follow the cursor (Interactive presence) |
| Watch for a minute | She blinks, glances around, flicks an ear, wags, pants, tilts her head — on a schedule, never constantly |
| Drag her | Legs dangle and ears flop while carried; squashes on landing; snaps back if dropped off-screen |
| Click her | Panel opens beside her; type a task — e.g. `Draft homepage ~45m !!` |
| Tick a task | She celebrates — hops, tongue out, tail going |
| Speaker icon in the panel header | Coco speaks her lines aloud (and her mouth moves with the voice) |
| Mic button or **⌘L**, then say *"I need to finish the homepage, review three portfolio projects for about an hour, and send two emails today"* | Ears up, head cocked, collar tag glowing while she listens; then three editable tasks to review — nothing is added until you press **Add** |
| Say *"start focus on the homepage"* / *"pause"* / *"resume"* / *"stop"* / *"take a break"* | Runs the timer command directly |
| Start a focus session | Panel tucks away; she acknowledges once, then sits on guard; a progress ring fills around her collar tag; countdown under her and in the menu bar |
| Session ends | Chime, celebration, notification; Focus tab asks whether the task got done (never assumed) |
| Right-click her | Talk, presence, focus behaviour, always-on-top, mute, voice, hide, reset position |
| Menu bar › Animation Preview | Plays any state on demand |
| Leave the Mac idle 5 min | She dozes off (airplane ears, Zs); wakes when you return |
| `Esc` / `⌘1` `⌘2` / `Space` / `⌘L` | Close panel / switch tabs / start-pause on Focus / talk |

Permissions are asked only on first use: notifications when you first start a session, microphone and speech recognition when you first press the mic. If you decline, everything else keeps working and the panel shows where to turn them on.

## Architecture

```
DesktopBuddy/                    App target — AppKit windows + SwiftUI views only
  App/        AppModel (composition root: events → behaviour, voice intents), menus, Buddy.name
  Windows/    CharacterPanel (floating, non-activating), BubbleWindow, InteractionPanel
  Character/  CocoLayerView (artwork), CharacterRenderLoop, CharacterModel, BuddyVoice (lines)
  Panel/      Today (+ voice review), Focus, design tokens
  Services/   TaskStore, FocusController, VoiceInput, VoiceOutput, notifications, sounds, presence
Packages/BuddyKit/               Pure Swift package, no UI, unit-tested
  BuddyCore        Tasks, quick-add parser, voice command parser + task splitter, focus timer, persistence
  BuddyCharacter   States, pose model, animator (blinks, idle life, reactions, frame scheduling)
```

**The character is three layers.** `CharacterState` (idle, listening, talking, thinking, celebrating, focused, sleeping) → `CharacterAnimator` turns state + time + events into a `CharacterPose` (plain numbers: eye openness, gaze, ear perk, tail angle, tongue, head tilt…) → `CocoLayerView` draws the pose. Animation is a pure function of time, so it's testable, and Coco replaced the original placeholder robot without touching the animation system.

**Energy.** The animator predicts when anything will next move. Quick motion (blinks, ear flicks, reactions, hops) renders at 60 fps from a display link; slow rhythmic motion (wagging, panting, listening) at 30 fps; at rest a single timer wakes ~10×/s (6×/s asleep), and nothing renders while she's hidden or covered. She's drawn with Core Animation layers — each frame only sets transforms and opacity; the window server rasterises. Measured idle cost (Release build, Intel Mac): **~0.9% CPU, 45 MB**, including her idle life. (The same approach measured 0.5% for the simpler placeholder; a SwiftUI `Canvas` renderer measured 4.4%.) Reduce Motion and Low Power Mode are respected.

**Voice.** Input uses Apple's Speech framework with on-device recognition whenever the language supports it (the panel says so when it doesn't). The mic is open only while you're talking to her — it closes after a pause, after 30 s, or when you click again, and Coco's voice is stopped first so she never hears herself. Transcripts are understood by a small, tested rule-based parser (`VoiceCommandParser`, `TaskSplitter`): timer commands run directly; anything else becomes tasks to review. Splitting on "and" uses Apple's on-device NaturalLanguage tagger, so "finish the homepage and send emails" splits but "buy salt and pepper" doesn't. Output uses the system speech synthesizer — offline, best installed voice, pitched up a touch. When the Phase 4 assistant arrives, the same pipeline feeds the chat.

**Time.** The focus timer stores an end date (or remaining time when paused), never counts ticks. The 1 Hz tick only refreshes the display; completion is decided by comparing dates on tick, wake and launch, with a system notification scheduled at the end date as a backstop.

**Windows.** Three small windows rather than one large transparent one: the character (clicks on transparent pixels pass through), a mouse-transparent speech bubble attached as a child window, and a key-capable, non-activating panel — you can type into it without leaving the app you were using.

**Unobtrusive by rule.** Lines have an importance (`ambient`, `acknowledge`, `important`). Ambient chatter only happens in Interactive presence and never during focus; Coco greets at most once a day; nothing interrupts a focus session except its end. Mute silences her voice too.

## Privacy

- Everything is local: tasks and timer state are JSON files in the app's sandbox container; preferences in UserDefaults.
- App Sandbox entitlements: **microphone only**. No network access — not even for voice (on-device recognition, offline speech synthesis).
- Audio is never recorded or stored; the transcript is used once and discarded.
- Permissions are requested on first use, each with an explanation of what it's for.

## Debug tools

- `--snapshots <folder>` (Debug builds) renders every character state and the panels to PNGs — the images above come from it. Run it from an unsandboxed, locally signed build:

  ```bash
  xcodebuild -project DesktopBuddy.xcodeproj -scheme DesktopBuddy -configuration Debug -derivedDataPath build-snap ENABLE_APP_SANDBOX=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
  ```

  ```bash
  build-snap/Build/Products/Debug/DesktopBuddy.app/Contents/MacOS/DesktopBuddy --snapshots ~/Desktop/coco-snapshots
  ```

- Debug builds log the render frame rate every 10 s:

  ```bash
  /usr/bin/log stream --predicate 'subsystem == "com.keefer.DesktopBuddy" AND category == "render"'
  ```
