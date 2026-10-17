# Coco design system

How Desktop Buddy's design system is organized, how Figma and the Swift code stay in sync, and what still needs a human.

- **Figma file:** [Coco](https://www.figma.com/design/FcDvsetj6U55hFCvRnIf5f/Coco)
- **Token source:** [design/tokens.json](../design/tokens.json), the one file both the app and Figma are generated from.
- **Component ↔ code map:** [design/figma-map.json](../design/figma-map.json)

The system was built from the app's code in October 2026 (the Figma file started empty). The code was then refactored to read every token from the generated file. Snapshots before and after that refactor were pixel-identical.

## How the pieces fit

```
                Figma (variables, text styles)
                   ▲ importTokens()     │ exportTokens()        design/figma/tokens-bridge.js
                   │                    ▼                        (run by the Coco Tokens plugin or Claude)
             design/tokens.json  ◀── scripts/tokens/apply_figma_export.py  (checksum, validation, diff)
                   │
                   ▼ scripts/tokens/generate_swift.py
DesktopBuddy/Generated/DesignTokens.generated.swift  →  Theme.*, Space, Radius, Metrics, BrandPalette, TypeStyle
                   │
                   ▼ used by every SwiftUI view and by CocoLayerView
               the app  →  --snapshots  →  scripts/visual-diff.swift (before/after pixel diff)
```

## 1. Figma file organization

| Page | What's on it |
|---|---|
| Cover | Title card. |
| Getting started | The short version of this document. |
| Foundations | Every variable and text style, with Light and Dark side by side (the same variables, each frame pinned to a mode), primitives, Coco's palette, type specimens, space and radius. |
| Components | 63 components and 24 icons, in sections in dependency order: Icons → Atoms → Key Button → Key Segment → Today → Panel, Bubble & Chat → Settings & Welcome → Editor, Review & Focus → Editor, Chat & Connections → Text Groups → Pairings → Buttons & Pips → Calendar → Calendar — Proposed. Repeated groupings are their own components, nested and exposed wherever they appear: `Text / Prompt Line` (Coco's line), `Text / Task Title` (task title + meta), `Text / Title & Detail` (welcome extras and step headings), `Text / Label & Title` (Up next), `Text / Activity` (chat activity), `Panel / Status Bar` (the panel's top row), `Today / Summary` and `Connections / Card Header`. Small controls are components too: `Pip` (every dot — Kind Step/Status/Activity/Thinking/Listening × On/Off), `Mic Key`, `Panel / Header Key` (the link key; the speaker key is no longer in the app) and `Text Button` (“New chat”); the Focus session bars are `Meter Segment`. Edit one main component to change that grouping everywhere; edit an instance's exposed properties to change one place. |
| Mascot | `Mascot / Coco` (34 poses: 14 sitting; Run Right … Run Down-Right and Gallop 1–4 from the 3D running model; Dash Wind-up / Arrive; Fetch Pickup / Carry / Drop; Treat Beg / Eat / Jump), `Mascot / Tennis Ball`, `Mascot / Treat` and `Brand / App Icon`. |
| Screens | Every window and panel state the app has: Today (Light and Dark), editing a task, voice review, Focus, Focus session complete, Chat, Settings, Connections, Welcome steps 1–4, and a desktop focus scene (Coco, her bubble, the LCD). Each screen is a `Screen / …` component built only from library instances. The **Calendar** section adds Today with the calendar, Today with the week open, two chat screens answering calendar questions, boards for every Today-card and calendar-access state, a duplicates board (one meeting from two calendars = one row; different meetings stay separate), and a clickable **Calendar access** flow (Connect → macOS asks → allowed / not allowed → Today → event detail). |
| Prototype | A clickable prototype of the whole user flow: 16 desktop scenes (1280 × 800) showing the screens in place on a Mac desktop, with Coco, her bubbles and the menu-bar menu. Two flows: **Onboarding** (welcome → desktop) and **Daily use** (desktop → panel, editing, voice review, focus session, chat, Settings, Connections). |

### The calendar

The calendar UI is one schedule built from every connected calendar (Google Calendar, Apple Calendar, Partiful), with duplicates merged before anything is shown — so the components never carry a provider badge by default. In the **Calendar** section:

- `Calendar / Event Row` — State Upcoming · Next · Soon · Now · Past; Title, Time, Location, Join, Repeat; exposed duration, note (“in 12m”, “18m left”) and source labels. *Show Source* is off: where an event lives belongs in the tooltip or Event Detail.
- `Calendar / Open Row`, `Calendar / All-Day Row` (Today / Week), `Calendar / Coming Up Row` (Tomorrow / Thu / Oct 24), `Calendar / Day Key` (Default / Today / Selected × Light / Busy), `Calendar / Week Toggle`.
- `Calendar / Schedule Card` — In Meeting · Today · No Meetings · All Done · Loading · Couldn't Refresh · Week. Built only from the rows above.
- `Connections / Apple Calendar Card` — Not Connected · Asking · No Access · Add Only · Blocked · Connected · Read Failed, with `Connections / Calendar Choice Row`.

**Calendar — Proposed (not in the app yet)** holds `Calendar / Event Detail` and `Chat / Calendar Summary`. They're designed from the same rows so they can be built without new styles; `design/figma-map.json` lists them under `proposed` until code exists.

**Motion** (in each component's description): the week opens and closes in place; changing day cross-fades the agenda (0.12 s ease-out); relative times update once a minute; the proposed detail expands under its row (0.15 s, a cross-fade with Reduce Motion). Nothing animates for decoration.

**Known gaps between Figma and code:** the app shows a small source label (“Apple · Home”) on non-Google rows, while the design keeps it off; Event Detail and the chat summary card are proposed only.

### The prototype

**Links:**
- [Onboarding](https://www.figma.com/proto/FcDvsetj6U55hFCvRnIf5f/Coco?node-id=40-241&starting-point-node-id=40%3A241)
- [Daily use](https://www.figma.com/proto/FcDvsetj6U55hFCvRnIf5f/Coco?node-id=40-1378&starting-point-node-id=40%3A1378)

To show it to someone without file access, use **Share prototype** in Figma's presentation view and choose who can view.

**What's interactive:**
- Every visible button that leads somewhere: welcome Next/Back/Start and the extras' setup buttons, the tabs, task editing, the mic, Up next › Focus, voice review, Start focus, the session-complete answers, Settings › Connections and *Show welcome again*.
- Clicking Coco opens and closes the panel. Her menu-bar item opens her real menu.
- ESC and the Esc key close the panel. Window close buttons and Esc close Settings and Connections.
- A focus session "ends" after 2.5 seconds.
- Settings and Connections scroll inside their 680 pt windows, as in the app.

**How it's built, and keeping it current:**
- Scenes contain *instances* of the `Screen / …` components, so editing a screen updates the prototype.
- Clicks are transparent `hotspot · …` frames over the real controls. If a screen's layout changes, run [design/figma/prototype-wiring.js](../design/figma/prototype-wiring.js) through the Figma MCP (`use_figma`). It removes its own hotspots and rebuilds every interaction from the table at its bottom; a re-run was verified to reproduce the same 74 interactions.
- The desktop wallpaper, menu bar and menu (`Prototype / Desktop`) are prototype props, not app UI.

## 2. Naming

| Thing | Convention | Examples |
|---|---|---|
| Variables | `group/name`, lowercase, in collections by kind | `surface/paper`, `ink/secondary`, `accent/default`, `coco/fur`; space `xl`; radius `key` |
| Collections | Primitives (hidden raw colors), Color (Light/Dark), Brand, Space, Radius, Metrics, Type | — |
| Text styles | `Group/Name` | `Body/Small`, `Mono/Label`, `Display/Countdown` |
| Components | Title Case; area-specific pieces as `Area / Name` | `Key Button`, `Task Row`, `Settings / Toggle Row`, `Chat / Coco Message` |
| Variants | `Property=Value` | `Kind=Primary, Size=Compact, State=Hover` |
| Icons | `Icon/<SF Symbol name>` | `Icon/play.fill` |
| Mascot | `Mascot / Coco`, `State=<pose>` | `State=Sleeping` |

Swift names come from the code and travel with the token. Each variable's **iOS code syntax** is its Swift name (`Theme.paper`, `Space.xl`, `Radius.key`, `Metrics.disabledOpacity`, `BrandPalette.fur`). Each text style's description says `Swift: TypeStyle.bodySmall`. Each component's description names the SwiftUI view that implements it.

## 3. Tokens and how they map to code

`design/tokens.json` keys are the Figma names, and each token carries its `swift` name.

| tokens.json group | Figma collection | Swift (generated) | Notes |
|---|---|---|---|
| `primitives` | Primitives | — | Raw hex, hidden from pickers. Semantic colors alias them. |
| `color` | Color (Light, Dark) | `Theme.paper`, `Theme.accent`, … | Dynamic `Color`s that follow the appearance. |
| `brand` | Brand | `BrandPalette.fur`, … (`NSColor`) | Coco's artwork and the app icon. `coco/tag-light` aliases `orange/500`, so the accent and Coco's tag move together. |
| `space` | Space | `Space.xxxs` … `Space.xxxl` (2–32) | Padding and stack spacing. |
| `radius` | Radius | `Radius.bar` … `Radius.panel` | Named by role: key, control, card, section, panel. |
| `metrics` | Metrics | `Metrics.hairline`, `.disabledOpacity`, `.pressedOpacity`, `.panelWidth`, `.panelHeight` | Opacity is 0–1 in code and tokens.json, 0–100 in Figma; the bridge converts. |
| `fonts` | Type (`font/sans`, `font/mono`) | `Font.Design.default` / `.monospaced` | The app uses SF Pro / SF Mono; Figma uses Inter / Roboto Mono (see Limitations). |
| `typography` | Text styles | `TypeStyle.body`, `.monoLabel`, … | Use `.font(.style(.bodySmall))`, or `.textStyle(.monoKey)` to also get tracking and uppercase. |

**Rule for code:** use these tokens instead of literal values. Literals are allowed only for one-off optical details: icon glyph sizes, the `+` and `›` prompt glyphs, the LCD digits, and nudges of 1–3 pt. These are listed as exceptions in the binding audit below.

## 4. Adding or changing a component

1. **Change the SwiftUI view first,** or at the same time. The code is what ships.
2. In Figma, edit the component on the Components page:
   - Bind fills, strokes, padding, gaps and radii to variables, and text to text styles.
   - Keep `Property=Value` variant names.
   - Expose nested instances that designers need to edit.
3. Put the SwiftUI type and file in the component's description, and add or update its entry in `design/figma-map.json` (node id, key, Swift symbol, file, and an `anchor` string from that file).
4. Run `python3 scripts/tokens/check_figma_map.py`. It fails if a mapped file or symbol no longer exists, or if an SF Symbol in the icon set is no longer used.
5. If the component needs a new token, add it in Figma (with iOS code syntax `Type.name`) and sync. The generator then adds the Swift constant.

**Plugin API lessons from building the library** (they apply to future edits too):
- `resize()` resets hug sizing, so set `counterAxisSizingMode = 'AUTO'` after resizing.
- Expose a nested instance only after it's inside its component.
- After a font change, re-measure text that has fill width.
- Rebinding an existing shape's paint can leave a stale color on screen. If a re-bound color looks wrong, replace the shape.
- Roboto Mono, the stand-in for SF Mono, has no ↩ glyph. Set just that character to Inter, as the Welcome step 4 keycap does.
- A prototype interaction can't point at the frame it's on (Figma rejects self-navigation), and "after delay" timeouts are in milliseconds.

## 5. Mascot and brand assets

Coco is drawn in code (`DesktopBuddy/Character/CocoLayerView.swift`) and animated by `CharacterAnimator`. The Figma vectors are **exports, not the source**:

1. Change her shapes in `CocoLayerView.swift`, or her colors through the Brand variables (sync as for any token).
2. Run the snapshot tool (Debug, unsandboxed; command in the README). It writes `mascot/coco-<pose>.svg` for the 14 sitting poses via `LayerSVGExporter`, which reads her real layer tree, and `RunPreview.exportTricks` adds the running, dash, fetch and treat poses plus `prop-tennis-ball.svg` and `prop-treat.svg`, along with `icon-1024.png`. Upload the SVGs with the Figma MCP `upload_assets` tool (they arrive as editable vectors).
3. Upload the SVGs to the Mascot page. Through Claude this is the Figma MCP `upload_assets`; by hand, drag them in.
4. Swap them into `Mascot / Coco` and re-bind colors to the Brand variables. Claude's import script matched colors by hex and bound 564 paints automatically.
5. Pure black (ground shadow) and white (eye shine) are literals in the code too, so they stay unbound.

The app icon (`Brand / App Icon`, `AppIcon.appiconset`) is rendered by `SnapshotRenderer.renderIcon` from Coco's artwork and the `icon/*` Brand colors. Regenerate it; don't edit it by hand.

## 6. Syncing Figma → code

What actually syncs automatically: **variables and text styles**, meaning colors (both modes), Coco's colors, space, radius, metrics, font families and the type ramp. Component structure does not. A changed component is a design for a code change, and `figma-map.json` tells you which Swift file to edit.

**Steps**
1. Change variables or text styles in Figma. To add a token, give it iOS code syntax (`Theme.myColor`, `Space.huge`, …); otherwise the exporter derives a name and warns.
2. Export:
   - **Plugin:** Figma desktop › Plugins › Development › *Import plugin from manifest…* › `design/figma/plugin/manifest.json`. Run **Coco Tokens › Export tokens › Download** to get `coco-tokens.json`.
   - **Or Claude:** ask it to "sync the Coco tokens from Figma". It runs the same `exportTokens()` through the Figma MCP.
3. In the repo, run the sync script:

   ```bash
   scripts/sync-design-tokens.sh ~/Downloads/coco-tokens.json
   ```

   It does the following, and never commits:
   1. Prints each token change.
   2. Renders "before" snapshots.
   3. Writes `design/tokens.json` and regenerates the Swift.
   4. Rebuilds and renders "after" snapshots.
   5. Writes a red-on-grey pixel diff for every screen to `build/design-sync/diff/`.
   6. Runs the token tests, the map check, the plugin check and the package tests.
4. Review the diff images and `git diff design DesktopBuddy/Generated`, run the app if needed, then commit.

**Code → Figma** (when tokens change in code first): edit `design/tokens.json`, run `python3 scripts/tokens/generate_swift.py`, then push it to Figma. Paste it into the plugin's text box and press **Import**, or ask Claude to run `importTokens()`. The import updates in place and never deletes; anything in Figma that isn't in the JSON is reported, not removed.

**Tested on 2026-10-11:**
- **Round trip with no change:** exporting from Figma gave a file identical to `tokens.json`, and the applier reported "No token changes".
- **Real change:**
  1. Changing `orange/500` to `#0A84FF` in Figma recolored the Figma screens.
  2. The export passed its checksum, and the sync script updated `tokens.json` and regenerated `Theme.accent` and `BrandPalette.accent`.
  3. The app rebuilt, and 13 of 24 snapshots changed, exactly in accent-colored pixels. Dark mode was unchanged, correctly, because dark accent is `orange/400`.
- **Revert:** setting the color back gave the original checksum, and the app re-rendered identically.

## 7. Generated vs hand-maintained files

| File | Kind | Edit it? |
|---|---|---|
| `design/tokens.json` | Source of truth | Yes, or via Figma + sync. Rewritten in canonical order by the applier. |
| `DesktopBuddy/Generated/DesignTokens.generated.swift` | Generated | **No.** Run `scripts/tokens/generate_swift.py`. A test fails if it's stale. |
| `design/figma/plugin/code.js` | Generated from `tokens-bridge.js` | **No.** Run `scripts/tokens/build_plugin.py`. |
| `design/figma/tokens-bridge.js` | Hand-written: Figma import/export logic | Yes; then rebuild the plugin. |
| `design/figma/plugin/manifest.json`, `ui.html` | Hand-written | Yes. |
| `design/figma-map.json` | Hand-maintained; checked by `check_figma_map.py` | Yes, when components change. |
| `design/figma/prototype-wiring.js` | Hand-written: the prototype's interactions | Yes; re-run it in Figma after a screen's layout or a button label changes. |
| `DesktopBuddy/Panel/Theme.swift` | Hand-written: `TypeStyle`, `MonoLabel`, `KeyButtonStyle`, color helper | Yes. |
| `DesktopBuddy/App/LayerSVGExporter.swift`, `SnapshotRenderer.swift` | Hand-written dev tools (Debug only) | Yes. |
| `scripts/visual-diff.swift`, `scripts/sync-design-tokens.sh`, `scripts/tokens/*.py` | Hand-written tooling | Yes. |
| Mascot SVGs, `icon-1024.png` | Generated by `--snapshots` | **No.** Regenerate. |

## 8. Limitations and troubleshooting

**Platform limits** (each one confirmed, not assumed):
- **No Code Connect.** It needs a Dev or Full seat on an Organization or Enterprise plan (the error, 2026-10-11, said exactly that). The mapping lives in `design/figma-map.json` and the component descriptions instead. If the plan changes, add the mappings with the Figma MCP `add_code_connect_map` using the `SwiftUI` label and the paths in that file.
- **No unattended sync.** Figma's REST Variables API is Enterprise-only. A person or Claude exports, and the sync script does the rest.
- **Stand-in fonts in Figma.** Figma's renderer has no SF Pro or SF Mono (SF Pro text measured 0 wide). Figma uses Inter and Roboto Mono at the same sizes and weights, so widths differ slightly from the app. The app always uses the system fonts.
- **Native controls are stand-ins.** The macOS 26 kit's Switch and Stepper couldn't be imported ("Not permitted to upsert from library"). So `Switch`, `Stepper` and `Text Field (native)` are drawn stand-ins, and `Field Well / Kind=Date` stands in for the date picker. They use macOS's default blue where the system accent shows, because the app leaves these controls native; so does the `Link` icon in Connections setup steps.
- **Icons are frozen outlines.** They're the real SF Symbol outlines (SF Pro Semibold) at one weight. Figma has no SF Symbols font, so add a new icon with `swift scripts/sf-symbol-svg.swift <symbol>` and import the SVG.

**The Coco Tokens plugin, tested 2026-10-11:**
- **Code side:** `code.js` ran unmodified inside Figma, with only its UI channel faked.
  - Export gave the repo's exact checksum.
  - Importing that export created 0, updated 75 variables and 17 text styles, and found no extras.
  - A second export was identical.
  - Malformed JSON came back as a clear error.
- **Panel side:** `ui.html` ran in a browser. Export sends its request, the export appears with a working `coco-tokens.json` download (checksum intact), Import sends the pasted JSON, and reports and errors show.
- **Not tested:** clicking through the plugin inside the Figma desktop app. That needs a person; the first run is *Plugins › Development › Import plugin from manifest…*.

**Binding audit (Components page, 2026-10-11):**
- **Colors:** 534 of 552 solid paints are bound to variables. The 18 unbound ones are deliberate and match the code: the LCD's 35% black edge, the native control stand-ins (switch, stepper, text field) and the system-blue link.
- **Text:** 203 of 225 text nodes use a text style. The other 22 are glyphs the code also sets directly (`+`, `›`, LCD digits, the editor's `30m`), or a style plus an override that mirrors the code (ESC keycap tracking, bubble line spacing).

**Troubleshooting**

| Symptom | Fix |
|---|---|
| "Checksum mismatch" | The export was edited or cut off. Export again and don't hand-edit it. |
| "The Figma export isn't valid" | A token is missing a Light/Dark value, aliases something that isn't a primitive, has an unknown weight, or reuses a Swift name. The message names it. Fix in Figma, export again. |
| Warning "no iOS code syntax" | A new variable without a Swift name. Set its iOS code syntax (e.g. `Space.huge`), or accept the derived name. |
| `DesignTokens.generated.swift is stale` (test) | Someone edited `tokens.json` without generating. Run `python3 scripts/tokens/generate_swift.py`. |
| Figma map check fails | A component's Swift file or symbol moved. Update `design/figma-map.json`. |
| Two snapshots always differ | `connections-connected` and `panel-connected` show the current time; differences only in their clock text are expected. |
| Disabled buttons nearly invisible in Figma | An opacity token was entered as 0–1. Figma wants 0–100; the bridge converts, so import through it. |
