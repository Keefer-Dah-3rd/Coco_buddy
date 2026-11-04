import { useEffect, useRef } from "react";
import { CocoEngine, type Tool } from "./coco/engine";
import type { TrickKind } from "./coco/animator";

/**
 * Dev-only filmstrips (open /?strip=treat, fetch, call, spin, bow, jump, beg): the engine
 * driven on a virtual clock, one frame per cell, so every beat of a game can be checked.
 */
const W = 250;
const H = 170;

type Scenario = { tool?: Tool; tap?: [number, number]; trick?: TrickKind; step: number; frames: number };

const SCENARIOS: Record<string, Scenario> = {
  treat: { tool: "treat", tap: [215, 60], step: 0.2, frames: 24 },
  fetch: { tool: "ball", tap: [40, 60], step: 0.25, frames: 24 },
  call: { tool: "come", tap: [210, 50], step: 0.12, frames: 18 },
  spin: { trick: "spin", step: 0.1, frames: 18 },
  bow: { trick: "bow", step: 0.12, frames: 18 },
  jump: { trick: "jump", step: 0.08, frames: 18 },
  beg: { trick: "beg", step: 0.14, frames: 18 },
};

export function Strips({ name }: { name: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const s = SCENARIOS[name] ?? SCENARIOS.treat;
    const cols = 3;
    const rows = Math.ceil(s.frames / cols);
    const dpr = window.devicePixelRatio || 1;
    const canvas = ref.current!;
    canvas.width = cols * W * dpr;
    canvas.height = rows * H * dpr;
    canvas.style.width = `${cols * W}px`;
    canvas.style.height = `${rows * H}px`;
    const out = canvas.getContext("2d")!;
    const cell = document.createElement("canvas");
    cell.width = W * dpr;
    cell.height = H * dpr;
    const ctx = cell.getContext("2d")!;

    const t0 = 100;
    const engine = new CocoEngine({ artSize: 72, wander: false }, t0 - 5);
    engine.setSize(W, H);
    engine.update(t0 - 1);
    if (s.tool) engine.setTool(s.tool, t0);
    if (s.tap) {
      engine.pointerDown(s.tap[0], s.tap[1], 1, "touch", t0);
      engine.pointerUp(s.tap[0], s.tap[1], 1, t0 + 0.01);
    }
    if (s.trick) engine.trick(t0, s.trick);

    for (let i = 0; i < s.frames; i++) {
      const t = t0 + 0.02 + i * s.step;
      engine.update(t);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      engine.draw(ctx, t);
      const x = (i % cols) * W;
      const y = Math.floor(i / cols) * H;
      out.setTransform(dpr, 0, 0, dpr, 0, 0);
      out.fillStyle = i % 2 ? "#EFEAE0" : "#F3EFE7";
      out.fillRect(x, y, W, H);
      out.drawImage(cell, x, y, W, H);
      out.fillStyle = "#6b625c";
      out.font = "600 11px system-ui";
      out.fillText(`${(t - t0).toFixed(2)} s`, x + 6, y + 14);
    }
  }, [name]);
  return <canvas ref={ref} />;
}
