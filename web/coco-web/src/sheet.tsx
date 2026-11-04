import { useEffect, useRef } from "react";
import { makePose, type Pose } from "./coco/pose";
import { runningPose } from "./coco/animator";
import { drawSitting, drawOverlays } from "./coco/sitting";
import { RunningCoco } from "./coco/running";

/** Dev-only contact sheet (open /?sheet): fixed poses, to check the art against the Mac app. */
const CELL = 150;

function poses(): { label: string; pose: Pose }[] {
  const out: { label: string; pose: Pose }[] = [];
  const sit = makePose();
  out.push({ label: "sit", pose: sit });
  const beg = makePose();
  beg.beg = 1;
  beg.earPerk = 1;
  beg.headTilt = 0.15;
  beg.mouthOpen = 0.25;
  beg.tongue = 0.35;
  beg.lift = 2;
  out.push({ label: "beg", pose: beg });
  const bark = makePose();
  bark.mouthOpen = 0.95;
  bark.earPerk = 1;
  out.push({ label: "bark", pose: bark });
  const happy = makePose();
  happy.eyeSmile = 1;
  happy.tongue = 1;
  happy.mouthOpen = 0.55;
  happy.sparkles = 1;
  happy.clock = 0.3;
  out.push({ label: "happy", pose: happy });
  const dangle = makePose();
  dangle.dangle = 1;
  dangle.mouthOpen = 0.35;
  out.push({ label: "carried", pose: dangle });
  const sleep = makePose();
  sleep.eyeOpen = 0;
  sleep.headDip = 4;
  sleep.sleepZ = 1;
  sleep.earPerk = 0.1;
  sleep.clock = 1.2;
  out.push({ label: "sleep", pose: sleep });
  for (let i = 0; i < 8; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / 4;
    out.push({ label: `run ${Math.round((a * 180) / Math.PI)}°`, pose: runningPose(makePose(), { x: Math.cos(a), y: Math.sin(a) }, 0.3, 1, 0.2) });
  }
  for (let i = 0; i < 4; i++) {
    out.push({ label: `stride ${i / 4}`, pose: runningPose(makePose(), { x: 1, y: 0 }, i / 4, 1, i * 0.05) });
  }
  const carry = runningPose(makePose(), { x: -0.7, y: -0.7 }, 0.6, 0.8, 0);
  carry.carry = 1;
  carry.tongue = 0;
  carry.mouthOpen = 0.3;
  out.push({ label: "carry ball", pose: carry });
  const pickup = runningPose(makePose(), { x: 1, y: 0 }, 0, 0, 0);
  pickup.reach = 1;
  pickup.bow = 0.3;
  pickup.crouch = 0.25;
  pickup.carry = 1;
  out.push({ label: "pickup", pose: pickup });
  const bow = runningPose(makePose(), { x: 0.86, y: -0.5 }, 0, 0, 0);
  bow.bow = 1;
  bow.eyeSmile = 0;
  bow.eyeScale = 1.12;
  bow.mouthOpen = 0.45;
  out.push({ label: "play bow", pose: bow });
  const jump = runningPose(makePose(), { x: 0, y: -1 }, 0.3, 0, 0);
  jump.lift = 24;
  jump.gallop = 0.6;
  jump.eyeSmile = 1;
  jump.sparkles = 1;
  jump.clock = 0.4;
  out.push({ label: "jump", pose: jump });
  return out;
}

export function Sheet() {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current!;
    const list = poses();
    const cols = 6;
    const rows = Math.ceil(list.length / cols);
    const dpr = window.devicePixelRatio || 1;
    canvas.width = cols * CELL * dpr;
    canvas.height = rows * CELL * dpr;
    canvas.style.width = `${cols * CELL}px`;
    canvas.style.height = `${rows * CELL}px`;
    const ctx = canvas.getContext("2d")!;
    ctx.scale(dpr, dpr);
    const runner = new RunningCoco();
    list.forEach(({ label, pose }, i) => {
      const x = (i % cols) * CELL;
      const y = Math.floor(i / cols) * CELL;
      ctx.fillStyle = i % 2 ? "#EFEAE0" : "#F3EFE7";
      ctx.fillRect(x, y, CELL, CELL);
      ctx.save();
      const s = 1.0;
      ctx.translate(x + 25, y + 18);
      ctx.scale(s, s);
      if (pose.run < 1) drawSitting(ctx, pose, 1 - pose.run);
      if (pose.run > 0) runner.draw(ctx, pose, pose.run);
      drawOverlays(ctx, pose);
      ctx.restore();
      ctx.fillStyle = "#6b625c";
      ctx.font = "600 11px system-ui";
      ctx.fillText(label, x + 6, y + CELL - 8);
    });
  }, []);
  return <canvas ref={ref} />;
}
