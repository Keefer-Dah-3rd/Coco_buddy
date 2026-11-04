/**
 * Coco's stage styles. Every class is prefixed `coco-` and buttons reset what a theme might
 * set, so a WordPress/Semplice theme can't restyle the toolbar (the embed also mounts inside
 * a shadow root, which keeps the page's CSS out entirely).
 */
export const STYLES = `
.coco-root {
  position: relative;
  width: 100%;
  overflow: hidden;
  container-type: inline-size;
  font-family: var(--coco-font, ui-rounded, "SF Pro Rounded", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif);
  -webkit-tap-highlight-color: transparent;
  user-select: none;
  -webkit-user-select: none;
  box-sizing: border-box;
}
.coco-root *, .coco-root *::before, .coco-root *::after { box-sizing: border-box; }
.coco-canvas {
  position: absolute;
  inset: 0;
  display: block;
  width: 100%;
  height: 100%;
  touch-action: pan-y pinch-zoom;
  outline: none;
  cursor: pointer;
}
.coco-canvas.coco-tool-ball, .coco-canvas.coco-tool-treat { cursor: none; }
@media (hover: none) { .coco-canvas.coco-tool-ball, .coco-canvas.coco-tool-treat { cursor: auto; } }
.coco-canvas:focus-visible { box-shadow: inset 0 0 0 3px rgba(255, 90, 31, 0.55); }
.coco-hint {
  position: absolute;
  top: 14px;
  left: 16px;
  right: 16px;
  font-size: 13px;
  line-height: 1.35;
  font-weight: 600;
  color: var(--coco-hint, rgba(34, 29, 27, 0.55));
  pointer-events: none;
  letter-spacing: 0.01em;
}
.coco-toolbar {
  position: absolute;
  left: 50%;
  bottom: 14px;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 5px;
  max-width: calc(100% - 20px);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.92);
  -webkit-backdrop-filter: saturate(1.4) blur(10px);
  backdrop-filter: saturate(1.4) blur(10px);
  box-shadow: 0 1px 2px rgba(34, 29, 27, 0.08), 0 6px 20px rgba(34, 29, 27, 0.12);
  border: 1px solid rgba(34, 29, 27, 0.08);
}
.coco-segment {
  display: flex;
  gap: 2px;
  padding: 2px;
  border-radius: 999px;
  background: rgba(34, 29, 27, 0.06);
}
.coco-root .coco-button {
  all: unset;
  box-sizing: border-box;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 36px;
  padding: 0 14px 0 11px;
  border-radius: 999px;
  font: inherit;
  font-size: 14px;
  font-weight: 650;
  line-height: 1;
  color: #221D1B;
  cursor: pointer;
  white-space: nowrap;
  transition: background-color 120ms ease, color 120ms ease, transform 120ms ease;
}
.coco-root .coco-button:hover { background: rgba(34, 29, 27, 0.07); }
.coco-root .coco-button:active { transform: scale(0.96); }
.coco-root .coco-button:focus-visible { outline: 2px solid #FF5A1F; outline-offset: 1px; }
.coco-root .coco-button svg { flex: none; }
.coco-root .coco-seg { height: 32px; }
.coco-root .coco-seg.coco-selected,
.coco-root .coco-seg.coco-selected:hover { background: #221D1B; color: #F4F0E8; }
.coco-root .coco-icon-only { padding: 0; width: 36px; }
.coco-divider {
  width: 1px;
  height: 22px;
  margin: 0 2px;
  background: rgba(34, 29, 27, 0.12);
}
@container (max-width: 560px) {
  .coco-root .coco-label { display: none; }
  .coco-root .coco-button { padding: 0; width: 36px; }
  .coco-root .coco-seg { width: 38px; }
  .coco-hint { font-size: 12px; }
}
@media (prefers-reduced-motion: reduce) {
  .coco-root .coco-button { transition: none; }
}
`;
