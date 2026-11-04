import { TennisBallColors, TreatColors } from "./palette";
import { Path, PathBuilder, ellipse, roundedRect, path2D } from "./path";

/** The two seams in a unit circle (y down): curves bowing toward each other. */
export const BALL_SEAMS: Path = new PathBuilder()
  .move(-0.62, -0.78)
  .curve(-0.62, 0.78, -0.05, -0.42, -0.05, 0.42)
  .move(0.62, -0.78)
  .curve(0.62, 0.78, 0.05, -0.42, 0.05, 0.42).cmds;

/**
 * Draws the tennis ball on the floor: contact shadow at `gx, gy` (CSS pixels, y down), the
 * ball `height` above it, seams turned by `spin`. A fixed highlight and lower shading (the
 * light doesn't spin) make it read as a sphere turning.
 */
export function drawBall(ctx: CanvasRenderingContext2D, gx: number, gy: number, height: number, spin: number, scale: number): void {
  const r = 7 * scale;
  const air = Math.min(1, height / 120);
  ctx.save();
  ctx.globalAlpha *= 0.28 * (1 - air * 0.7);
  ctx.fillStyle = "#000";
  ctx.beginPath();
  ctx.ellipse(gx, gy, r * 1.1 * (1 - air * 0.45), r * 0.35 * (1 - air * 0.45), 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  const cx = gx;
  const cy = gy - r - height;
  ctx.save();
  ctx.translate(cx, cy);
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, Math.PI * 2);
  ctx.fillStyle = TennisBallColors.felt;
  ctx.fill();
  ctx.lineWidth = 0.8;
  ctx.strokeStyle = TennisBallColors.edge;
  ctx.stroke();

  ctx.save();
  ctx.rotate(spin);
  ctx.scale(r * 0.98, r * 0.98);
  ctx.strokeStyle = TennisBallColors.seam;
  ctx.lineCap = "round";
  ctx.lineWidth = Math.max(0.9, r * 0.16) / (r * 0.98);
  ctx.stroke(path2D(BALL_SEAMS));
  ctx.restore();

  ctx.save();
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, Math.PI * 2);
  ctx.clip();
  const shade = ctx.createRadialGradient(-0.24 * r, -0.24 * r, 0, -0.24 * r, -0.24 * r, 1.34 * r);
  shade.addColorStop(0, "rgba(255,255,255,0)");
  shade.addColorStop(1, hexAlpha(TennisBallColors.shade, 0.55));
  ctx.fillStyle = shade;
  ctx.fillRect(-r, -r, 2 * r, 2 * r);
  ctx.restore();

  ctx.fillStyle = "rgba(255,255,255,0.55)";
  ctx.beginPath();
  ctx.ellipse(-0.3 * r, -0.35 * r, 0.25 * r, 0.17 * r, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

/** The bone-shaped biscuit, `length` long, centred on the origin (y down). */
function bonePaths(length: number): { parts: Path[]; shine: Path; dots: Path[] } {
  const half = length / 2;
  const knob = length * 0.2;
  const parts: Path[] = [roundedRect(-half + knob, -knob * 0.62, length - 2 * knob, knob * 1.24, knob * 0.4)];
  for (const x of [-half + knob, half - knob]) {
    for (const y of [-knob * 0.72, knob * 0.72]) parts.push(ellipse(x - knob, y - knob, 2 * knob, 2 * knob));
  }
  const shine = new PathBuilder().move(-length * 0.24, -length * 0.07).line(length * 0.2, -length * 0.07).cmds;
  const dots = [-0.12, 0.02, 0.15].map((x) => ellipse(length * x - 0.5, length * 0.06 - 0.5, 1, 1));
  return { parts, shine, dots };
}

const boneCache = new Map<number, ReturnType<typeof bonePaths>>();

/** Draws the treat: tumbling end over end in the air, then lying where it lands. */
export function drawTreat(ctx: CanvasRenderingContext2D, gx: number, gy: number, height: number, spin: number, scale: number): void {
  const length = 18 * scale;
  const key = Math.round(length * 100);
  let bone = boneCache.get(key);
  if (!bone) {
    bone = bonePaths(length);
    boneCache.set(key, bone);
  }
  const air = Math.min(1, height / 100);
  ctx.save();
  ctx.globalAlpha *= 0.26 * (1 - air * 0.7);
  ctx.fillStyle = "#000";
  ctx.beginPath();
  ctx.ellipse(gx, gy, length * 0.5 * (1 - air * 0.45), length * 0.11 * (1 - air * 0.45), 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  ctx.save();
  ctx.translate(gx, gy - length * 0.22 - height);
  ctx.rotate(spin);
  ctx.lineJoin = "round";
  // The outline is stroked first and the fills cover its inner half, so the overlapping
  // knobs read as one biscuit with a single edge.
  ctx.strokeStyle = TreatColors.edge;
  ctx.lineWidth = 1.8;
  for (const part of bone.parts) ctx.stroke(path2D(part));
  ctx.fillStyle = TreatColors.biscuit;
  for (const part of bone.parts) ctx.fill(path2D(part));
  ctx.strokeStyle = TreatColors.highlight;
  ctx.lineCap = "round";
  ctx.lineWidth = Math.max(0.8, length * 0.06);
  ctx.stroke(path2D(bone.shine));
  ctx.fillStyle = hexAlpha(TreatColors.edge, 0.6);
  for (const dot of bone.dots) ctx.fill(path2D(dot));
  ctx.restore();
}

function hexAlpha(hex: string, alpha: number): string {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${alpha})`;
}
