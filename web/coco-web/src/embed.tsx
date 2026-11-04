import { createRoot, type Root } from "react-dom/client";
import { CocoPlayground, type CocoPlaygroundProps } from "./CocoPlayground";

/**
 * Drop-in Coco for any website, Semplice/WordPress included. Load this one script and add
 *
 *   <div data-coco data-height="460"></div>
 *
 * anywhere on the page. Options (all optional): data-height, data-size, data-background,
 * data-radius, data-wander="false", data-sound="false", data-toolbar="false", data-font.
 * Each Coco lives in a shadow root, so the site's theme CSS can't restyle her stage.
 */
const mounted = new WeakMap<Element, Root>();

function readOptions(el: HTMLElement): CocoPlaygroundProps {
  const d = el.dataset;
  const flag = (value: string | undefined, fallback: boolean) =>
    value === undefined ? fallback : !["false", "0", "no", "off"].includes(value.trim().toLowerCase());
  const number = (value: string | undefined) => {
    const n = value === undefined ? NaN : Number(value);
    return Number.isFinite(n) ? n : undefined;
  };
  const height = d.height === undefined ? undefined : number(d.height) ?? d.height;
  return {
    height,
    size: number(d.size),
    background: d.background,
    radius: number(d.radius),
    wander: flag(d.wander, true),
    sound: flag(d.sound, true),
    toolbar: flag(d.toolbar, true),
    style: d.font ? ({ ["--coco-font" as string]: d.font } as React.CSSProperties) : undefined,
  };
}

export function mount(el: HTMLElement, options?: CocoPlaygroundProps): () => void {
  if (mounted.has(el)) return () => unmount(el);
  const shadow = el.shadowRoot ?? el.attachShadow({ mode: "open" });
  const host = document.createElement("div");
  host.style.width = "100%";
  shadow.appendChild(host);
  if (!el.style.display) el.style.display = "block";
  const root = createRoot(host);
  root.render(<CocoPlayground {...readOptions(el)} {...options} />);
  mounted.set(el, root);
  return () => unmount(el);
}

export function unmount(el: Element): void {
  const root = mounted.get(el);
  if (!root) return;
  root.unmount();
  mounted.delete(el);
  el.shadowRoot?.replaceChildren();
}

function scan(scope: ParentNode = document): void {
  scope.querySelectorAll<HTMLElement>("[data-coco]").forEach((el) => {
    if (!mounted.has(el)) mount(el);
  });
}

function start(): void {
  scan();
  // Semplice (and other themes) can swap page content without a reload: watch for new spots,
  // and let go of Cocos whose spot was removed.
  new MutationObserver((records) => {
    for (const record of records) {
      record.addedNodes.forEach((node) => {
        if (!(node instanceof HTMLElement)) return;
        if (node.matches("[data-coco]")) mount(node);
        scan(node);
      });
      record.removedNodes.forEach((node) => {
        if (!(node instanceof HTMLElement)) return;
        if (mounted.has(node)) unmount(node);
        node.querySelectorAll("[data-coco]").forEach((el) => unmount(el));
      });
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
else start();
