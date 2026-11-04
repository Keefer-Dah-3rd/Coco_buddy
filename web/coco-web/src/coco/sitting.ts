import { Palette } from "./palette";
import { Path, PathBuilder, ellipse, roundedRect, translate, scaleXY, path2D } from "./path";
import { Pose } from "./pose";
import { fract, smoothstep } from "./math";

/**
 * Coco sitting: a black-and-white corgi with a white blaze, giant ears and a collar tag.
 * A canvas port of the Mac app's `CocoLayerView`. Drawn in a 100 × 100 unit box with y down;
 * her paws touch the ground at (50, 93).
 */
const BODY = { x: 50, y: 91 };
const NECK = { x: 50, y: 57 };
export const GROUND_Y = 93;

const shiftBody = (p: Path) => translate(p, -BODY.x, -BODY.y);
const shiftNeck = (p: Path) => translate(p, -NECK.x, -NECK.y);

// MARK: - Shared outlines (the runner reuses these)

/** One ear's outline, its base at the origin and its tip leaning toward −x (y down). */
export const EAR_OUTLINE: Path = new PathBuilder()
  .move(-9, 3)
  .curve(-6.5, -23.5, -12.5, -6, -10.5, -18)
  .quad(-2.6, -22, -4.5, -26.5)
  .curve(9, 1, 1.5, -15, 6, -6)
  .close().cmds;

export const EAR_INSIDE: Path = new PathBuilder()
  .move(-5.8, 0)
  .curve(-5.4, -18, -8.4, -6, -7.6, -14)
  .quad(-3.2, -17, -4.2, -20.2)
  .curve(4.8, -0.5, -0.4, -11, 3, -5)
  .close().cmds;

export const CLOSED_EYE: Path = new PathBuilder().move(-3.3, 0).quad(3.3, 0, 0, 2.4).cmds;
export const HAPPY_EYE: Path = new PathBuilder().move(-3.4, 1.4).quad(3.4, 1.4, 0, -3.4).cmds;

// MARK: - Static shapes

const TAIL_FLUFF = new PathBuilder()
  .move(-3.6, 0)
  .curve(-1, -21, -7.5, -7, -6, -16)
  .quad(3, -20.5, 1.5, -24.5)
  .curve(3.6, 0, 6.2, -14, 6.5, -6)
  .close().cmds;
const TAIL_TIP = new PathBuilder()
  .move(-3.6, -15)
  .curve(-1, -21, -4.8, -17.5, -3, -20)
  .quad(3, -20.5, 1.5, -24.5)
  .curve(4.8, -15, 4.4, -19, 4.9, -17)
  .quad(-3.6, -15, 0.6, -13.2)
  .close().cmds;
const TAIL_POS = { x: 69 - BODY.x, y: 83 - BODY.y };

const SILHOUETTE = shiftBody(
  new PathBuilder()
    .move(36, 57)
    .curve(25.5, 84, 28, 63, 24.5, 74)
    .curve(32, 91, 26, 89, 28.5, 91)
    .line(68, 91)
    .curve(74.5, 84, 71.5, 91, 74, 89)
    .curve(64, 57, 75.5, 74, 72, 63)
    .close().cmds,
);
const HAUNCHES = shiftBody(new PathBuilder().move(28.5, 75).quad(35, 90, 36.5, 79).move(71.5, 75).quad(65, 90, 63.5, 79).cmds);
const BIB = shiftBody(
  new PathBuilder()
    .move(40.5, 60)
    .curve(50, 88, 38.5, 72, 44, 84)
    .curve(59.5, 60, 56, 84, 61.5, 72)
    .quad(40.5, 60, 50, 63)
    .close().cmds,
);

interface Leg {
  pos: { x: number; y: number };
  column: Path;
  paw: Path;
  toes: Path;
}
const LEGS: Leg[] = [38.5, 54].map((x) => {
  const local = { x: x + 3.75, y: 72 };
  const toes = new PathBuilder();
  for (const toeX of [x + 1.9, x + 5.6]) toes.move(toeX, 89.6).line(toeX, 91.6);
  return {
    pos: { x: x + 3.75 - BODY.x, y: 72 - BODY.y },
    column: translate(roundedRect(x, 72, 7.5, 17.5, 3.5), -local.x, -local.y),
    paw: translate(ellipse(x - 1.8, 86.3, 11, 6.4), -local.x, -local.y),
    toes: translate(toes.cmds, -local.x, -local.y),
  };
});

const BAND = shiftBody(
  new PathBuilder().move(33, 56.5).quad(67, 56.5, 50, 63).line(66.5, 60).quad(33.5, 60, 50, 66.5).close().cmds,
);
const TAG_CENTER = { x: 50, y: 65.5 };
const tagCircle = (r: number) => shiftBody(ellipse(TAG_CENTER.x - r, TAG_CENTER.y - r, 2 * r, 2 * r));
const TAG_GLOW = tagCircle(7.5);
const TAG = tagCircle(4.6);
const TAG_FACE = tagCircle(3.4);
const TAG_LIGHT = tagCircle(1.6);

const EAR_RIGHT_OUTLINE = scaleXY(EAR_OUTLINE, -1, 1);
const EAR_RIGHT_INSIDE = scaleXY(EAR_INSIDE, -1, 1);
const EAR_POS = [
  { x: 35 - NECK.x, y: 25 - NECK.y },
  { x: 65 - NECK.x, y: 25 - NECK.y },
];

const SKULL = shiftNeck(
  new PathBuilder()
    .move(50, 17)
    .curve(27, 31, 36, 17, 28, 22)
    .curve(31, 51, 26, 40, 27, 46)
    .curve(50, 58, 35, 56, 42, 58)
    .curve(69, 51, 58, 58, 65, 56)
    .curve(73, 31, 73, 46, 74, 40)
    .curve(50, 17, 72, 22, 64, 17)
    .close().cmds,
);
const BLAZE = shiftNeck(
  new PathBuilder()
    .move(48.6, 19.5)
    .quad(51.4, 19.5, 50, 18.6)
    .curve(55.5, 41, 52.2, 28, 53.5, 36)
    .line(44.5, 41)
    .curve(48.6, 19.5, 46.5, 36, 47.8, 28)
    .close().cmds,
);
const MUZZLE = shiftNeck(
  new PathBuilder()
    .move(50, 38.5)
    .curve(38.5, 46.5, 43, 38.5, 38.5, 41.5)
    .curve(50, 55.5, 38.5, 52, 44, 55.5)
    .curve(61.5, 46.5, 56, 55.5, 61.5, 52)
    .curve(50, 38.5, 61.5, 41.5, 57, 38.5)
    .close().cmds,
);
const NOSE = shiftNeck(
  new PathBuilder()
    .move(45.4, 40.2)
    .curve(54.6, 40.2, 47, 38.4, 53, 38.4)
    .curve(50, 44.8, 55.2, 42.2, 52.2, 44.8)
    .curve(45.4, 40.2, 47.8, 44.8, 44.8, 42.2)
    .close().cmds,
);
const NOSE_SHINE = shiftNeck(ellipse(46.6, 39.4, 2.8, 1.3));

const EYE_OPEN = ellipse(-3.3, -3.7, 6.6, 7.4);
const EYE_SHINE = ellipse(0.2, -2.8, 2.2, 2.2);
const EYE_GLINT = ellipse(-1.9, 1.1, 1, 1);
const MOUTH_INSIDE = ellipse(-4.75, 0, 9.5, 7);
const MOUTH_TOP = { x: 0, y: 47 - NECK.y };

const SPARKLE: Path = [
  ...roundedRect(-3.5, -0.9, 7, 1.8, 0.01),
  ...roundedRect(-0.9, -3.5, 1.8, 7, 0.01),
];
const GROUND_SHADOW = ellipse(-29, -2.5, 58, 5);

// MARK: - Drawing helpers

function fill(ctx: CanvasRenderingContext2D, path: Path, color: string, alpha = 1): void {
  if (alpha <= 0.001) return;
  const a = ctx.globalAlpha;
  ctx.globalAlpha = a * alpha;
  ctx.fillStyle = color;
  ctx.fill(path2D(path));
  ctx.globalAlpha = a;
}

function stroke(ctx: CanvasRenderingContext2D, path: Path, color: string, width: number, alpha = 1): void {
  if (alpha <= 0.001) return;
  const a = ctx.globalAlpha;
  ctx.globalAlpha = a * alpha;
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke(path2D(path));
  ctx.globalAlpha = a;
}

function shape(ctx: CanvasRenderingContext2D, path: Path, fillColor: string, strokeColor?: string, width = 0.9): void {
  fill(ctx, path, fillColor);
  if (strokeColor) stroke(ctx, path, strokeColor, width);
}

// MARK: - Per-frame

/** Draws the ground shadow and the sitting Coco. `ctx` is in unit-box coordinates. */
export function drawSitting(ctx: CanvasRenderingContext2D, p: Pose, alpha: number): void {
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  const lift = p.lift;
  const dangle = p.dangle;
  const run = Math.min(1, Math.max(0, p.run));

  // Contact shadow: shrinks and fades as she leaves the ground.
  const air = Math.min(1, lift / 14);
  const shadowAlpha = 0.22 * (1 - air * 0.6) * (1 - dangle) * (1 - run);
  if (shadowAlpha > 0.001) {
    ctx.save();
    ctx.translate(50, GROUND_Y);
    ctx.scale(1 - air * 0.35, 1);
    fill(ctx, GROUND_SHADOW, "#000", shadowAlpha);
    ctx.restore();
  }
  if (alpha <= 0.001) return;

  ctx.save();
  ctx.globalAlpha *= alpha;
  // Squash/stretch anchored at the paws, then tilt around the same point.
  ctx.translate(BODY.x, BODY.y - lift);
  ctx.rotate(p.tilt);
  ctx.scale(1 + p.squash, 1 - p.squash);

  // Tail
  ctx.save();
  ctx.translate(TAIL_POS.x, TAIL_POS.y);
  ctx.rotate(0.75 + p.tail + dangle * 1.5);
  shape(ctx, TAIL_FLUFF, Palette.fur, Palette.rim);
  fill(ctx, TAIL_TIP, Palette.white);
  ctx.restore();

  shape(ctx, SILHOUETTE, Palette.fur, Palette.rim);
  stroke(ctx, HAUNCHES, Palette.rim, 0.8);
  fill(ctx, BIB, Palette.white);

  // Front legs; begging lifts them, paws pawing the air in turn.
  const beg = Math.min(1, Math.max(0, p.beg));
  LEGS.forEach((leg, index) => {
    const swing = dangle * 0.22 * Math.sin(p.clock * 7 + index * 1.7);
    const paw = beg * 1.6 * Math.sin(p.clock * 10 + index * Math.PI);
    ctx.save();
    ctx.translate(leg.pos.x, leg.pos.y + 3 * dangle - 9 * beg + paw);
    ctx.rotate(swing);
    shape(ctx, leg.column, Palette.white, Palette.whiteEdge, 0.7);
    shape(ctx, leg.paw, Palette.white, Palette.whiteEdge, 0.7);
    stroke(ctx, leg.toes, Palette.whiteEdge, 0.6);
    ctx.restore();
  });

  // Collar and the round tag (its light glows with `led`).
  shape(ctx, BAND, Palette.collar, Palette.collarRim, 0.6);
  const led = Math.min(1, Math.max(0, p.led));
  fill(ctx, TAG_GLOW, Palette.accent, 0.35 * led);
  shape(ctx, TAG, Palette.collar, Palette.collarRim, 0.6);
  fill(ctx, TAG_FACE, Palette.tagFace);
  fill(ctx, TAG_LIGHT, Palette.accent, led);

  drawHead(ctx, p);
  ctx.restore();
}

function drawHead(ctx: CanvasRenderingContext2D, p: Pose): void {
  ctx.save();
  ctx.translate(0, NECK.y - BODY.y + p.headDip);
  ctx.rotate(p.headTilt);

  // Ears first, so the head covers their bases.
  const relax = (1 - Math.min(1.1, Math.max(0, p.earPerk))) * 0.55;
  const earAngles = [-(relax + p.earLeft), relax + p.earRight];
  for (let i = 0; i < 2; i++) {
    ctx.save();
    ctx.translate(EAR_POS[i].x, EAR_POS[i].y);
    ctx.rotate(earAngles[i]);
    shape(ctx, i === 0 ? EAR_OUTLINE : EAR_RIGHT_OUTLINE, Palette.fur, Palette.rim);
    fill(ctx, i === 0 ? EAR_INSIDE : EAR_RIGHT_INSIDE, Palette.innerEar);
    ctx.restore();
  }

  shape(ctx, SKULL, Palette.fur, Palette.rim);
  fill(ctx, BLAZE, Palette.white);
  fill(ctx, MUZZLE, Palette.white);

  // Eyes
  const gx = p.gazeX * 1.6;
  const gy = p.gazeY * 1.2;
  const scale = p.eyeScale;
  const happy = smoothstep(0.3, 0.7, p.eyeSmile);
  const openness = smoothstep(0.12, 0.45, p.eyeOpen);
  for (let i = 0; i < 2; i++) {
    ctx.save();
    ctx.translate((i === 0 ? -9.5 : 9.5) + gx, -22 + gy);
    const openAlpha = openness * (1 - happy);
    if (openAlpha > 0.001) {
      ctx.save();
      ctx.scale(scale, scale * Math.max(0.08, Math.min(1, p.eyeOpen)));
      const a = ctx.globalAlpha;
      ctx.globalAlpha = a * openAlpha;
      shape(ctx, EYE_OPEN, Palette.eye, Palette.eyeRim, 0.7);
      fill(ctx, EYE_SHINE, "rgba(255,255,255,0.9)");
      fill(ctx, EYE_GLINT, "rgba(255,255,255,0.5)");
      ctx.globalAlpha = a;
      ctx.restore();
    }
    stroke(ctx, CLOSED_EYE, Palette.closedEye, 1.3, (1 - openness) * (1 - happy));
    if (happy > 0.001) {
      ctx.save();
      ctx.scale(scale, scale);
      stroke(ctx, HAPPY_EYE, Palette.closedEye, 1.5, happy);
      ctx.restore();
    }
    ctx.restore();
  }

  // Mouth: one fixed ellipse, scaled; the tongue; the smile line.
  const open = Math.max(0, p.mouthOpen);
  const tongueOut = Math.min(1, Math.max(0, p.tongue));
  if (open >= 0.04) {
    ctx.save();
    ctx.translate(MOUTH_TOP.x, MOUTH_TOP.y - 0.6);
    ctx.scale((6.5 + 3 * open) / 9.5, Math.max(0.01, (1 + 6 * open) / 7));
    fill(ctx, MOUTH_INSIDE, Palette.mouthInside);
    ctx.restore();
  }
  if (!(tongueOut < 0.02 && open < 0.2)) {
    const length = 2 + 7 * tongueOut + 2 * open;
    const top = MOUTH_TOP.y + 0.8;
    ctx.fillStyle = Palette.tongue;
    ctx.beginPath();
    roundRectPath(ctx, -2.6, top, 5.2, length, Math.min(2.6, length / 2));
    ctx.fill();
    ctx.fillStyle = Palette.tongueGroove;
    ctx.fillRect(-0.25, top + 1, 0.5, Math.min(3, Math.max(0, length - 1.2)));
  }
  const c = p.mouthCurve;
  ctx.save();
  ctx.translate(MOUTH_TOP.x, MOUTH_TOP.y);
  ctx.strokeStyle = Palette.mouthLine;
  ctx.lineWidth = 1.1;
  ctx.beginPath();
  ctx.moveTo(0, -2.4);
  ctx.lineTo(0, 0);
  ctx.quadraticCurveTo(-2.5, 2.2 + 1.4 * c, -5, -0.8 - 0.6 * c);
  ctx.moveTo(0, 0);
  ctx.quadraticCurveTo(2.5, 2.2 + 1.4 * c, 5, -0.8 - 0.6 * c);
  ctx.stroke();
  ctx.restore();

  fill(ctx, NOSE, Palette.nose);
  fill(ctx, NOSE_SHINE, "rgba(255,255,255,0.55)");
  ctx.restore();
}

function roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + w - r, y);
  ctx.arcTo(x + w, y, x + w, y + r, r);
  ctx.lineTo(x + w, y + h - r);
  ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
  ctx.lineTo(x + r, y + h);
  ctx.arcTo(x, y + h, x, y + h - r, r);
  ctx.lineTo(x, y + r);
  ctx.arcTo(x, y, x + r, y, r);
  ctx.closePath();
}

/** Sleep Zs and celebration sparkles, around her in the unit box. */
export function drawOverlays(ctx: CanvasRenderingContext2D, p: Pose): void {
  if (p.sleepZ > 0.01) {
    for (let index = 0; index < 3; index++) {
      const phase = fract(p.clock * 0.32 + index / 3);
      const size = 4 + phase * 3.5;
      const x = 78 + phase * 10 + Math.sin(phase * 6) * 1.5;
      const y = 28 - phase * 22;
      const alpha = Math.sin(phase * Math.PI) * p.sleepZ;
      const z = new PathBuilder()
        .move(x - size / 2, y - size / 2)
        .line(x + size / 2, y - size / 2)
        .line(x - size / 2, y + size / 2)
        .line(x + size / 2, y + size / 2).cmds;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      strokeOnce(ctx, z, Palette.white, 3.4, alpha);
      strokeOnce(ctx, z, Palette.ink, 1.5, alpha);
    }
  }
  if (p.sparkles > 0.05) {
    for (let index = 0; index < 6; index++) {
      const phase = fract(p.clock * 1.3 + index * 0.37);
      const s = Math.sin(phase * Math.PI) * p.sparkles;
      if (s < 0.05) continue;
      const angle = (index / 6) * 2 * Math.PI + 0.4;
      const radius = 43 + phase * 5;
      ctx.save();
      ctx.translate(50 + Math.cos(angle) * radius, 50 + Math.sin(angle) * radius * 0.85);
      ctx.scale(s, s);
      fill(ctx, SPARKLE, Palette.accent);
      ctx.restore();
    }
  }
}

function strokeOnce(ctx: CanvasRenderingContext2D, path: Path, color: string, width: number, alpha: number): void {
  if (alpha <= 0.001) return;
  const a = ctx.globalAlpha;
  ctx.globalAlpha = a * alpha;
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.beginPath();
  for (const cmd of path) {
    if (cmd[0] === "M") ctx.moveTo(cmd[1], cmd[2]);
    else if (cmd[0] === "L") ctx.lineTo(cmd[1], cmd[2]);
  }
  ctx.stroke();
  ctx.globalAlpha = a;
}
