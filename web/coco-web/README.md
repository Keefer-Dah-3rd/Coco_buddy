# Coco for the web

Coco the corgi on a web page, built with React and TypeScript. Her drawings, her running and her tricks are ported straight from the Desktop Buddy Mac app, so she looks and moves the same way.

What visitors can do:

- **Come**: click or tap anywhere and she runs there. Hold the mouse button down and move it, and she follows.
- **Carry her**: drag Coco to pick her up and put her down somewhere else. Tap her and she barks hello.
- **Ball**: click where you want to throw it. She chases it, picks it up, brings it back and drops it at your feet.
- **Treat**: she begs while you hold it out. Click to toss it, and she runs after it, eats it and jumps for joy.
- **Bark**: one of her four real barks, with a "Woof!" bubble.
- **Trick**: spin, play bow, happy jump and sit pretty, one after the other.

When nobody is playing, she trots around now and then and sometimes does a trick. If nobody comes by for a while, she falls asleep, and a click wakes her up.

Keyboard: arrow keys move her, **B** barks, **T** does a trick, **F** throws the ball, **S** tosses a treat. Click the stage first so it has focus.

## Put her on your Semplice site

Run `npm run build` first. It writes three ready-made files to `dist/embed/`. (Built copies are already in that folder.)

### Option 1: one paste, no hosting

1. Open `dist/embed/semplice-snippet.html` in a text editor and copy all of it.
2. In the Semplice editor, add a **Code** module where you want Coco, and paste it in.
3. Save, then view the page live. The editor preview may not run scripts.

This file is about 260 KB because it carries React, Coco and her barks. If your host or a security plugin won't save that much code, use option 2.

### Option 2: host the script (most reliable)

1. Upload `dist/embed/coco-embed.js` somewhere that serves files as they are, such as GitHub Pages, Netlify or your host's file manager. WordPress's Media Library refuses `.js` files by default.
2. Put this in a Semplice **Code** module, with your file's address in `src`:

```html
<div data-coco data-height="460"></div>
<script src="https://YOUR-SITE.com/path/to/coco-embed.js" defer></script>
```

You can add more than one `<div data-coco>` to a page. One script runs all of them.

### Option 3: an iframe

Host `dist/embed/coco.html` (it has everything inside it), then use:

```html
<iframe src="https://YOUR-SITE.com/path/to/coco.html" title="Coco the corgi"
        style="width:100%;height:460px;border:0;border-radius:20px"></iframe>
```

### Options on the `<div>`

| Attribute | Default | What it does |
| --- | --- | --- |
| `data-height` | `460` | Stage height in pixels, or any CSS length such as `70vh` |
| `data-size` | `120` | Coco's size in pixels (she shrinks a little on narrow phones) |
| `data-background` | `#F3EFE7` | Any CSS color, or `transparent` to show your page behind her |
| `data-radius` | `20` | Corner radius of the stage |
| `data-wander` | `true` | `false` keeps her still unless someone plays with her |
| `data-sound` | `true` | `false` starts with barks muted (visitors can switch them on) |
| `data-toolbar` | `true` | `false` hides the toolbar, leaving click-to-call, drag and tap-to-bark |
| `data-font` | system rounded | The toolbar's font family, for example `"Inter", sans-serif` |

Example: a dark, quiet Coco with your site's font:

```html
<div data-coco data-height="380" data-background="#221D1B" data-wander="false" data-font="'Inter', sans-serif"></div>
```

Each Coco is drawn inside a shadow root, so your theme's CSS can't restyle her buttons, and her styles don't leak into your page.

## Use her in a React app

Copy `src/CocoPlayground.tsx`, `src/styles.ts`, `src/coco/` and `src/assets/` into your project, then:

```tsx
import { CocoPlayground } from "./CocoPlayground";

<CocoPlayground height={460} size={120} background="#F3EFE7" wander sound />
```

The props match the `data-` options above (`height`, `size`, `background`, `radius`, `wander`, `sound`, `toolbar`), plus `className` and `style`.

## Develop

```bash
npm install
npm run dev
```

Pages on the dev server:

- `/` is the demo page.
- `/?sheet` is a contact sheet of fixed poses, for checking her art against the Mac app.
- `/?strip=treat` shows a game frame by frame on a virtual clock. The other strips are `fetch`, `call`, `spin`, `bow`, `jump` and `beg`.
- `/test/semplice-test.html` loads the built embed on a page with pushy theme CSS (run `npm run build` first).

`npm run build` checks types, builds the demo into `dist/demo/` and the embed into `dist/embed/`.

## How it's built

- `src/coco/animator.ts`: her behavior as a pure function of time, ported from the app's `CharacterAnimator`. It covers blinks, idle life, reactions, the dash, fetch and treats, plus the web-only tricks.
- `src/coco/dash.ts`, `ballFlight.ts`, `games.ts`: running, ball and treat physics, fetch and the treat game, from the app's `Dash`, `BallFlight`, `Fetch` and `TreatGame`.
- `src/coco/sitting.ts` and `running.ts`: her two drawings on a canvas. The sitting drawing ports `CocoLayerView`. The runner ports `RunningCoco`, the small 3D model that can face any direction.
- `src/coco/engine.ts`: the stage, where her position, the pointer, the games and the drawing come together.
- `src/CocoPlayground.tsx`: the React component, with the toolbar, sound, resizing and pausing when she's scrolled out of view.

Browsers only allow sound after a visitor clicks or taps, so her first barks before that are silent (her mouth still moves). With "reduce motion" turned on in the system settings, she keeps her body movement small and doesn't wander.
