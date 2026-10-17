# Experiment: Coco Editorial Orange

A design exploration of Coco's panel in the **Editorial Orange** style from the Figma Make
file *Create Playful Design Variations* (`AKhsjPOyTgqtgZQzI8Oadf`, style "Editorial Orange",
source `src/themes/OrganicOrangeEditorial.tsx`). It is not the production UI.

## Run it

- **Xcode:** pick the **Coco Editorial Orange** scheme, then ⌘R. Stop any other Coco run first,
  because two copies of the app would fight over the desktop.
  The normal app starts as usual, and the experiment opens in its own window beside it. Click
  Coco to open the real panel and compare the two.
- **Command line (Debug build):** `DesktopBuddy --editorial-orange`
- **Stills for review** (sample data only, unsandboxed Debug build):
  `DesktopBuddy --editorial-orange-snapshots <folder>` renders every experiment state as
  `eo-*.png`, the real panel in the same states as `prod-*.png`, and side-by-side
  `compare-*.png` images.

## Isolation

- Everything lives in `DesktopBuddy/Experiments/EditorialOrange/`, wrapped in `#if DEBUG`.
  Release builds contain none of it.
- Its tokens are scoped to the `EO` namespace. `Theme`, the generated design tokens,
  `design/tokens.json` and the Figma library are untouched.
- The only edit to an existing file is `AppDelegate.swift`: two Debug-only launch flags.
  Without a flag, startup is unchanged.
- It uses the same `AppModel` as the real panel, so tasks, focus, chat and calendars are real
  and shared. Changes made in either window show up in both.

## What it reuses

- Tasks: the `TaskStore` intents and quick-add parser.
- Focus: the `FocusController`.
- Chat: the `AssistantService`, including confirm-before-change for tasks, completions and
  calendar edits.
- Calendars: the merged `Agenda` (Google, Apple Calendar and Partiful, with duplicates shown
  once), `Availability` and `RelativeTiming`.
- Coco: her real art (`CocoLayerView`) and animator.

The experiment's Coco has her own character model, so patting her never moves the desktop
Coco. Her pose follows the app state: listening, thinking, writing, focused or away.

## Not carried over yet

- Keyboard navigation inside the task list (↑/↓/Space/Return). ⌘1–⌘4, ⌘L, ⌘N, ⌘Z, Space
  (timer) and Esc work.
- Notion: paused in the app, so not shown.
- Connecting accounts: rows on the System page open the real Connections window. The OAuth,
  Calendar permission and key flows are not duplicated.
- Light appearance only, as in the reference.

# Experiment: Coco Tactile Orange

A second exploration from the same Make file: style "Tactile Orange"
(`src/themes/OrganicOrangeTactile.tsx`). It's a soft toy-like card (`#E8E5D9` with a white
8pt rim and a solid `#A8A69D` drop) on a dotted `#D5D3C8` desk. Every control is a key with a
thicker bottom edge that sinks when pressed. Sheets pop in with the reference's 0.3s overshoot.
It uses Fredoka when installed and falls back to SF Pro Rounded (Fredoka isn't on this Mac).

- Run it from the **Coco Tactile Orange** scheme, or with `DesktopBuddy --tactile-orange`.
- Stills: `DesktopBuddy --tactile-orange-snapshots <folder>`.
- Code: `DesktopBuddy/Experiments/TactileOrange/` (`TO` namespace, `#if DEBUG`). It shares
  only Coco's masthead view, the entrance and pulse helpers and the sample data with the
  Editorial experiment. Same isolation, the same real `AppModel`, and the same gaps as above.
