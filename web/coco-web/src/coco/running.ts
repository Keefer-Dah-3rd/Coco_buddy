import { Palette, TennisBallColors } from "./palette";
import { Path, Affine, transform, trace, UNIT_CIRCLE } from "./path";
import { Pose, makePose } from "./pose";
import { EAR_OUTLINE, EAR_INSIDE, HAPPY_EYE } from "./sitting";
import { VIEW_ELEVATION } from "./dash";
import { smoothstep } from "./math";
import { BALL_SEAMS } from "./props";

/**
 * Coco on the run — a canvas port of the Mac app's `RunningCoco`.
 *
 * She's built as a small 3D model (ellipsoids for body and head, capsules for legs and tail,
 * flat cards for the ears, markings laid on the surfaces), seen through a fixed camera aimed
 * down at the floor, and redrawn as flat shapes in her palette and outline style each frame.
 * Any heading works, so turning blends by nature. Coordinates are the 100-unit box (y down)
 * with the ground under her body at (50, 93).
 */

// MARK: - Vectors

type Vec = [number, number, number];
const v = (x: number, y: number, z: number): Vec => [x, y, z];
const vadd = (a: Vec, b: Vec): Vec => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const vsub = (a: Vec, b: Vec): Vec => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const vmul = (a: Vec, k: number): Vec => [a[0] * k, a[1] * k, a[2] * k];
const vlen = (a: Vec): number => Math.hypot(a[0], a[1], a[2]);
const vdot = (a: Vec, b: Vec): number => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const vcross = (a: Vec, b: Vec): Vec => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const vnorm = (a: Vec): Vec => {
  const l = vlen(a);
  return l > 1e-9 ? vmul(a, 1 / l) : a;
};
const vneg = (a: Vec): Vec => [-a[0], -a[1], -a[2]];

/** Rotates `a` about a unit axis (Rodrigues). */
function rotate(a: Vec, axis: Vec, angle: number): Vec {
  const k = vnorm(axis);
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return vadd(vadd(vmul(a, c), vmul(vcross(k, a), s)), vmul(k, vdot(k, a) * (1 - c)));
}

/** An orthonormal frame placed in the world. */
class Frame {
  constructor(
    readonly origin: Vec,
    readonly forward: Vec,
    readonly left: Vec,
    readonly up: Vec,
  ) {}

  point(p: Vec): Vec {
    return vadd(this.origin, this.vector(p));
  }
  vector(p: Vec): Vec {
    return vadd(vadd(vmul(this.forward, p[0]), vmul(this.left, p[1])), vmul(this.up, p[2]));
  }
  pitched(angle: number, pivot: Vec): Frame {
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    return this.turned(pivot, vadd(vmul(this.forward, c), vmul(this.up, s)), this.left, vsub(vmul(this.up, c), vmul(this.forward, s)));
  }
  rolled(angle: number, pivot: Vec): Frame {
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    return this.turned(pivot, this.forward, vsub(vmul(this.left, c), vmul(this.up, s)), vadd(vmul(this.up, c), vmul(this.left, s)));
  }
  private turned(pivot: Vec, f: Vec, l: Vec, u: Vec): Frame {
    const anchor = this.point(pivot);
    const frame = new Frame([0, 0, 0], f, l, u);
    return new Frame(vsub(anchor, frame.vector(pivot)), f, l, u);
  }
}

// MARK: - Camera

const sinE = Math.sin(VIEW_ELEVATION);
const cosE = Math.cos(VIEW_ELEVATION);
const TO_VIEWER: Vec = [0, -cosE, sinE];
/** A touch larger than its units, so from the front she's the size of the sitting drawing. */
export const CAMERA_SCALE = 1.12;

interface P2 {
  x: number;
  y: number;
}

const Camera = {
  point(p: Vec): P2 {
    return { x: 50 + p[0] * CAMERA_SCALE, y: 93 - (p[1] * sinE + p[2] * cosE) * CAMERA_SCALE };
  },
  vector(a: Vec): P2 {
    return { x: a[0] * CAMERA_SCALE, y: -(a[1] * sinE + a[2] * cosE) * CAMERA_SCALE };
  },
  /** Larger is farther from the viewer. */
  depth(p: Vec): number {
    return p[1] * cosE - p[2] * sinE;
  },
  facing(normal: Vec): number {
    return vdot(normal, TO_VIEWER);
  },
  /** The outline of an ellipsoid with these semi-axes, as the image of a unit circle. */
  ellipsoid(center: Vec, a: Vec, b: Vec, c: Vec): Path {
    const m = [Camera.vector(a), Camera.vector(b), Camera.vector(c)];
    const q11 = m.reduce((s, k) => s + k.x * k.x, 0);
    const q12 = m.reduce((s, k) => s + k.x * k.y, 0);
    const q22 = m.reduce((s, k) => s + k.y * k.y, 0);
    const l11 = Math.max(1e-6, Math.sqrt(q11));
    const l21 = q12 / l11;
    const l22 = Math.sqrt(Math.max(1e-6, q22 - l21 * l21));
    const o = Camera.point(center);
    return transform(UNIT_CIRCLE, { a: l11, b: l21, c: 0, d: l22, e: o.x, f: o.y });
  },
  /** A flat drawing laid on a plane: its x along `x`, its y along `y` (screen vectors). */
  card(path: Path, origin: P2, x: P2, y: P2): Path {
    const m: Affine = { a: x.x, b: x.y, c: y.x, d: y.y, e: origin.x, f: origin.y };
    return transform(path, m);
  },
  cardWorld(path: Path, origin: Vec, x: Vec, y: Vec): Path {
    return Camera.card(path, Camera.point(origin), Camera.vector(x), Camera.vector(y));
  },
  line(points: Vec[]): Path {
    return points.map((p, i) => {
      const q = Camera.point(p);
      return [i === 0 ? "M" : "L", q.x, q.y] as ["M" | "L", number, number];
    });
  },
};

// MARK: - Anatomy (x forward, y to her left, z up; origin on the ground under her middle)

interface Ellipsoid {
  center: Vec;
  radii: Vec;
  pitch?: number;
}

const Anatomy = {
  chest: { center: v(13, 0, 24), radii: v(14, 14.5, 14) } as Ellipsoid,
  belly: { center: v(0, 0, 22.5), radii: v(21, 13.5, 12) } as Ellipsoid,
  rump: { center: v(-14.5, 0, 24), radii: v(13.5, 14.5, 13.5) } as Ellipsoid,
  bib: { center: v(19.5, 0, 22), radii: v(6.5, 9, 9.5) } as Ellipsoid,
  neck: v(20, 0, 32),
  skull: { center: v(30, 0, 43), radii: v(16, 19.5, 17) } as Ellipsoid,
  muzzle: { center: v(43, 0, 35.5), radii: v(10, 8, 7) } as Ellipsoid,
  nose: { center: v(52.5, 0, 38.3), radii: v(2.6, 3.5, 2.7) } as Ellipsoid,
  blaze: { center: v(43.2, 0, 46.5), radii: v(2, 3.6, 8), pitch: 0.35 } as Ellipsoid,
  mouth: v(48.5, 0, 31.2),
  ballHold: v(52, 0, 28),
  ballRadius: 6.3,
  earBase: v(25.5, 10.5, 55.5),
  collarCenter: v(21, 0, 32),
  collarAxis: v(0.62, 0, 0.78),
  collarRadius: 12.2,
  tailBase: v(-25, 0, 32),
  shoulder: v(14, 8, 14),
  hip: v(-15, 8.5, 14),
  pawRadius: 2.6,
};

function surface(e: Ellipsoid, direction: Vec): { point: Vec; normal: Vec } {
  const d: Vec = [direction[0] / e.radii[0], direction[1] / e.radii[1], direction[2] / e.radii[2]];
  const t = 1 / vlen(d);
  const offset = vmul(direction, t);
  const r2: Vec = [e.radii[0] ** 2, e.radii[1] ** 2, e.radii[2] ** 2];
  return { point: vadd(e.center, offset), normal: vnorm([offset[0] / r2[0], offset[1] / r2[1], offset[2] / r2[2]]) };
}

// MARK: - Parts and regions

type Style =
  | { kind: "shape"; fill: string; edge: string | null }
  | { kind: "limb"; width: number; fill: string; edge: string | null }
  | { kind: "marking"; fill: string; stroke: string | null; width: number }
  | { kind: "curve"; width: number; stroke: string };

const RIM = 0.9;

class Part {
  path: Path | null = null;
  depth = 0;
  opacity = 1;
  constructor(readonly style: Style) {}

  get hasEdge(): boolean {
    return (this.style.kind === "shape" || this.style.kind === "limb") && this.style.edge !== null;
  }

  show(path: Path, depth: number, opacity = 1): void {
    this.path = path;
    this.depth = depth;
    this.opacity = opacity;
  }

  showEllipsoid(e: Ellipsoid, frame: Frame, bias = 0): void {
    let forward = frame.forward;
    let up = frame.up;
    if (e.pitch) {
      forward = vadd(vmul(frame.forward, Math.cos(e.pitch)), vmul(frame.up, Math.sin(e.pitch)));
      up = vsub(vmul(frame.up, Math.cos(e.pitch)), vmul(frame.forward, Math.sin(e.pitch)));
    }
    const center = frame.point(e.center);
    this.show(
      Camera.ellipsoid(center, vmul(forward, e.radii[0]), vmul(frame.left, e.radii[1]), vmul(up, e.radii[2])),
      Camera.depth(center) - bias,
    );
  }

  drawEdge(ctx: CanvasRenderingContext2D): void {
    if (!this.path || !this.hasEdge) return;
    const s = this.style as { kind: "shape" | "limb"; edge: string; width?: number };
    ctx.globalAlpha = this.opacity;
    ctx.strokeStyle = s.edge;
    ctx.lineWidth = s.kind === "limb" ? (s.width ?? 0) + RIM * 2 : RIM * 2;
    trace(ctx, this.path);
    ctx.stroke();
  }

  drawFill(ctx: CanvasRenderingContext2D): void {
    if (!this.path) return;
    ctx.globalAlpha = this.opacity;
    const s = this.style;
    trace(ctx, this.path);
    switch (s.kind) {
      case "shape":
        ctx.fillStyle = s.fill;
        ctx.fill();
        break;
      case "limb":
        ctx.strokeStyle = s.fill;
        ctx.lineWidth = s.width;
        ctx.stroke();
        break;
      case "marking":
        ctx.fillStyle = s.fill;
        ctx.fill();
        if (s.stroke && s.width > 0) {
          ctx.strokeStyle = s.stroke;
          ctx.lineWidth = s.width;
          ctx.stroke();
        }
        break;
      case "curve":
        ctx.strokeStyle = s.stroke;
        ctx.lineWidth = s.width;
        ctx.stroke();
        break;
    }
  }

  reset(): void {
    this.path = null;
    this.opacity = 1;
  }
}

/** Parts that share one outline and are painted together. */
class Region {
  depth = 0;
  constructor(readonly parts: Part[]) {}
}

const shape = (fill: string, edge: string | null = null) => new Part({ kind: "shape", fill, edge });
const limb = (width: number, fill: string, edge: string | null) => new Part({ kind: "limb", width, fill, edge });
const marking = (fill: string, stroke: string | null = null, width = 0) => new Part({ kind: "marking", fill, stroke, width });
const curve = (width: number, stroke: string) => new Part({ kind: "curve", width, stroke });

// MARK: - The runner

export class RunningCoco {
  private shadow: { path: Path | null; opacity: number } = { path: null, opacity: 0 };

  private chest = shape(Palette.fur, Palette.rim);
  private belly = shape(Palette.fur, Palette.rim);
  private rump = shape(Palette.fur, Palette.rim);
  private bib = shape(Palette.white);
  private torso = new Region([this.chest, this.belly, this.rump, this.bib]);

  private skull = shape(Palette.fur, Palette.rim);
  private muzzle = shape(Palette.white, Palette.rim);
  private nose = shape(Palette.nose);
  private blaze = shape(Palette.white);
  private mouth = shape(Palette.mouthInside);
  private tongue = limb(4.4, Palette.tongue, Palette.tongueGroove);
  private ball = shape(TennisBallColors.felt, TennisBallColors.edge);
  private ballSeams = curve(1.1, TennisBallColors.seam);
  private ears = [0, 1].map(() => ({ outer: shape(Palette.fur, Palette.rim), inside: shape(Palette.innerEar) }));
  private eyes = [0, 1].map(() => ({
    open: marking(Palette.eye, Palette.eyeRim, 0.7),
    shine: marking("rgba(255,255,255,0.9)"),
    happy: curve(1.5, Palette.closedEye),
  }));
  private head = new Region([
    this.skull,
    this.muzzle,
    this.nose,
    this.blaze,
    this.mouth,
    this.tongue,
    this.ball,
    this.ballSeams,
    ...this.ears.flatMap((e) => [e.outer, e.inside]),
    ...this.eyes.flatMap((e) => [e.open, e.shine, e.happy]),
  ]);

  private tailFur = limb(9, Palette.fur, Palette.rim);
  private tailTip = limb(7.4, Palette.white, Palette.whiteEdge);
  private tail = new Region([this.tailFur, this.tailTip]);

  private band = limb(3.2, Palette.collar, Palette.collarRim);
  private tag = shape(Palette.collar, Palette.collarRim);
  private tagFace = shape(Palette.tagFace);
  private tagLight = shape(Palette.accent);
  private collar = new Region([this.band, this.tag, this.tagFace, this.tagLight]);

  private limbs = [0, 1, 2, 3].map((index) => ({
    leg: index < 2 ? limb(7.4, Palette.white, Palette.whiteEdge) : limb(8.2, Palette.fur, Palette.rim),
    paw: shape(Palette.white, Palette.whiteEdge),
  }));
  private legs = this.limbs.map((l) => new Region([l.leg, l.paw]));

  draw(ctx: CanvasRenderingContext2D, p: Pose, alpha: number): void {
    const g = Math.min(1, Math.max(0, p.gallop));
    const bow = Math.min(1, Math.max(0, p.bow));
    const phase = p.stride - Math.floor(p.stride);
    const { floor, body, head, lift } = frames(p, reachPitch());
    this.layoutShadow(floor, lift);
    this.layoutBody(body);
    this.layoutHead(head, p, g, phase);
    this.layoutCollar(body, p.led);
    this.layoutTail(body, p.tail, g, bow);
    this.layoutLegs(body, floor, g, bow, phase, Math.max(0, p.lift));
    this.paint(ctx, alpha);
  }

  private layoutShadow(floor: Frame, airborne: number): void {
    const air = Math.min(1, Math.max(0, airborne) / 16);
    const center = floor.point(v(-1, 0, 0));
    this.shadow.path = Camera.ellipsoid(
      center,
      vmul(floor.forward, 27 * (1 - air * 0.3)),
      vmul(floor.left, 14 * (1 - air * 0.3)),
      vmul(floor.up, 0.01),
    );
    this.shadow.opacity = 0.2 * (1 - air * 0.6);
  }

  private layoutBody(body: Frame): void {
    this.chest.showEllipsoid(Anatomy.chest, body);
    this.belly.showEllipsoid(Anatomy.belly, body);
    this.rump.showEllipsoid(Anatomy.rump, body);
    // The white chest sits just inside the chest: seen from the front and sides only.
    this.bib.showEllipsoid(Anatomy.bib, body, 0.5);
    this.torso.depth = Camera.depth(body.point(v(-1, 0, 23)));
  }

  private layoutHead(frame: Frame, p: Pose, g: number, phase: number): void {
    const tau = 2 * Math.PI;
    this.skull.showEllipsoid(Anatomy.skull, frame);
    this.muzzle.showEllipsoid(Anatomy.muzzle, frame, 1);
    this.nose.showEllipsoid(Anatomy.nose, frame, 1.5);
    this.blaze.showEllipsoid(Anatomy.blaze, frame, 0.5);

    // Mouth open under the muzzle, tongue hanging out and flapping with her stride.
    const open = Math.min(1, Math.max(0, p.mouthOpen));
    const mouthAt = frame.point(Anatomy.mouth);
    const mouthNormal = frame.vector(v(0.55, 0, -0.84));
    if (open > 0.04 && Camera.facing(mouthNormal) > -0.25) {
      const across = vmul(frame.left, 3.6);
      const down = vmul(vnorm(vcross(mouthNormal, frame.left)), 0.6 + 3 * open);
      this.mouth.show(Camera.cardWorld(UNIT_CIRCLE, mouthAt, across, down), Camera.depth(mouthAt) - 0.4);
    }
    const tongueOut = Math.min(1, Math.max(0, p.tongue));
    if (tongueOut > 0.05) {
      const swing = 0.35 * g + 0.22 * g * Math.sin(tau * (phase + 0.15));
      const length = 2.5 + 5.5 * tongueOut;
      const start = frame.point(vadd(Anatomy.mouth, v(-1.2, 0, 0.6)));
      const end = vadd(start, vmul(frame.vector(v(-Math.sin(swing), 0, -Math.cos(swing))), length));
      this.tongue.show(Camera.line([start, end]), Camera.depth(vmul(vadd(start, end), 0.5)) - 0.2);
    }

    // A tennis ball held in the front of her mouth.
    if (p.carry > 0.5) {
      const center = frame.point(Anatomy.ballHold);
      const r = Anatomy.ballRadius;
      this.ball.show(
        Camera.ellipsoid(center, vmul(frame.forward, r), vmul(frame.left, r), vmul(frame.up, r)),
        Camera.depth(center) - 1.2,
      );
      const screen = Camera.vector(v(r, 0, 0)).x;
      this.ballSeams.show(
        Camera.card(BALL_SEAMS, Camera.point(center), { x: screen, y: 0 }, { x: 0, y: screen }),
        Camera.depth(center) - 1.21,
      );
    }

    // Ears: the sitting Coco's own outline on a card standing up from the skull.
    const flap = 0.18 * g * Math.sin(tau * (phase - 0.2));
    const back = 0.06 + 0.38 * Math.min(1, Math.max(0, p.earBack)) + flap;
    const splay = 0.14 + (1 - Math.min(1, Math.max(0, p.earPerk))) * 0.45;
    this.ears.forEach((ear, index) => {
      const side = index === 0 ? 1 : -1;
      const out = vmul(frame.left, side);
      let up = vadd(vmul(frame.up, Math.cos(splay)), vmul(out, Math.sin(splay)));
      let across = vneg(vsub(vmul(out, Math.cos(splay)), vmul(frame.up, Math.sin(splay))));
      let front = frame.forward;
      const turnBy = 0.42 * side;
      up = rotate(up, frame.up, turnBy);
      across = rotate(across, frame.up, turnBy);
      front = rotate(front, frame.up, turnBy);
      up = rotate(up, across, back * side);
      front = rotate(front, across, back * side);

      const base = frame.point(v(Anatomy.earBase[0], Anatomy.earBase[1] * side, Anatomy.earBase[2]));
      const scale = 1.14;
      const lengthwise = Camera.vector(vmul(up, -scale));
      const crosswise = readableWidth(Camera.vector(vmul(across, scale)), lengthwise, Camera.vector(out), 0.45 * scale);
      const outline = Camera.card(EAR_OUTLINE, Camera.point(base), crosswise, lengthwise);
      const center = vadd(base, vmul(up, 11));
      ear.outer.show(outline, Camera.depth(center));
      const seen = Camera.facing(front);
      if (seen > 0.02) {
        const inside = Camera.card(EAR_INSIDE, Camera.point(vadd(base, vmul(up, 1.2))), crosswise, lengthwise);
        ear.inside.show(inside, Camera.depth(center) - 0.01, smoothstep(0.02, 0.3, seen));
      }
    });

    // Eyes are markings on the skull, foreshortened as she turns.
    const happy = smoothstep(0.3, 0.7, p.eyeSmile);
    const openness = smoothstep(0.12, 0.45, p.eyeOpen);
    this.eyes.forEach((eye, index) => {
      const side = index === 0 ? 1 : -1;
      const s = surface(Anatomy.skull, v(0.66, 0.5 * side, 0.2));
      const at = frame.point(s.point);
      const normal = frame.vector(s.normal);
      const seen = Camera.facing(normal);
      if (seen <= 0.02) return;
      const visible = smoothstep(0.02, 0.25, seen);
      let across = vcross(frame.up, normal);
      across = vlen(across) > 1e-6 ? vnorm(across) : frame.left;
      let upward = vnorm(vcross(normal, across));
      if (vdot(upward, frame.up) < 0) upward = vneg(upward);
      const depth = Camera.depth(at);
      const scale = p.eyeScale;
      if (happy < 0.99 && openness > 0.02) {
        const tall = Math.max(0.08, Math.min(1, p.eyeOpen));
        const disc = Camera.cardWorld(UNIT_CIRCLE, at, vmul(across, 3.3 * scale), vmul(upward, -3.7 * scale * tall));
        eye.open.show(disc, depth, visible * openness * (1 - happy));
        const glintAt = vadd(vadd(at, vmul(across, 1.3 * scale)), vmul(upward, 1.5 * scale));
        const glint = Camera.cardWorld(UNIT_CIRCLE, glintAt, vmul(across, 1.1 * scale), vmul(upward, -1.1 * scale * tall));
        eye.shine.show(glint, depth - 0.01, visible * openness * (1 - happy));
      }
      if (happy > 0.01) {
        const arc = Camera.cardWorld(HAPPY_EYE, at, vmul(across, scale), vmul(upward, -scale));
        eye.happy.show(arc, depth - 0.02, visible * happy);
      }
    });
    this.head.depth = Camera.depth(frame.point(Anatomy.skull.center)) - 3;
  }

  private layoutCollar(body: Frame, led: number): void {
    const center = body.point(Anatomy.collarCenter);
    const axis = vnorm(body.vector(Anatomy.collarAxis));
    const e1 = body.left;
    const e2 = vnorm(vcross(axis, e1));
    const r = Anatomy.collarRadius;
    // Only the half of the ring nearest the viewer shows; the neck hides the rest.
    const d1 = Camera.depth(vadd(center, e1)) - Camera.depth(center);
    const d2 = Camera.depth(vadd(center, e2)) - Camera.depth(center);
    const nearest = Math.atan2(-d2, -d1);
    const points: Vec[] = [];
    for (let i = 0; i <= 14; i++) {
      const a = nearest - Math.PI / 2 + (Math.PI * i) / 14;
      points.push(vadd(center, vmul(vadd(vmul(e1, Math.cos(a)), vmul(e2, Math.sin(a))), r)));
    }
    this.band.show(Camera.line(points), Camera.depth(center));

    // The round tag hangs at the front of the collar.
    const hang = vsub(center, vmul(e2, r + 1.2));
    const facing = vnorm(body.vector(v(0.92, 0, -0.38)));
    if (Camera.facing(facing) > 0) {
      const across = vnorm(vcross(body.up, facing));
      const upward = vnorm(vcross(facing, across));
      const depth = Camera.depth(hang) - 0.5;
      this.tag.show(Camera.cardWorld(UNIT_CIRCLE, hang, vmul(across, 4.2), vmul(upward, -4.2)), depth);
      this.tagFace.show(Camera.cardWorld(UNIT_CIRCLE, hang, vmul(across, 3), vmul(upward, -3)), depth - 0.01);
      if (led > 0.02) {
        this.tagLight.show(Camera.cardWorld(UNIT_CIRCLE, hang, vmul(across, 1.4), vmul(upward, -1.4)), depth - 0.02, Math.min(1, led));
      }
    }
    this.collar.depth = Camera.depth(center) - 1.5;
  }

  private layoutTail(body: Frame, wag: number, g: number, bow: number): void {
    // Up and back, streaming lower at speed, high in a play bow, wagging side to side.
    const lift = 0.95 - 0.4 * g + 0.3 * bow;
    const swing = wag * 1.3;
    const direction = (elevation: number) =>
      body.vector(v(-Math.cos(elevation) * Math.cos(swing), Math.cos(elevation) * Math.sin(swing), Math.sin(elevation)));
    const base = body.point(Anatomy.tailBase);
    const middle = vadd(base, vmul(direction(lift), 10));
    const end = vadd(middle, vmul(direction(lift + 0.45), 5.5));
    this.tailFur.show(Camera.line([base, middle]), Camera.depth(vmul(vadd(base, middle), 0.5)));
    this.tailTip.show(Camera.line([middle, end]), Camera.depth(vmul(vadd(middle, end), 0.5)) - 0.1);
    this.tail.depth = Camera.depth(middle) + 2;
  }

  /** `jump` lifts the paws off the floor with her (a leap, not a gallop's bounce). */
  private layoutLegs(body: Frame, floor: Frame, g: number, bow: number, phase: number, jump: number): void {
    // A bounding gallop: the hind pair drives together, then the front pair reaches.
    const offsets = [0.5, 0.57, 0.0, 0.07];
    const stance = 0.42;
    this.limbs.forEach((l, index) => {
      const fore = index < 2;
      const side = index % 2 === 0 ? 1 : -1;
      const joint = fore ? Anatomy.shoulder : Anatomy.hip;
      const top = body.point(v(joint[0], joint[1] * side, joint[2]));
      const q = (phase + offsets[index]) % 1;
      const reach = 11 * g;
      let dx: number;
      let dz = 0;
      if (q < stance) {
        dx = reach * (1 - (2 * q) / stance);
      } else {
        const u = (q - stance) / (1 - stance);
        dx = -reach + 2 * reach * smoothstep(0, 1, u);
        dz = 7 * g * Math.sin(Math.PI * u) * (fore ? 1 : 0.85);
      }
      dx += fore ? 3.5 * g + 9 * bow : -3.5 * g - 1.5 * bow;
      const paw = floor.point(v(joint[0] + dx, (joint[1] + 0.6) * side, Anatomy.pawRadius + dz + jump));
      l.leg.show(Camera.line([top, paw]), Camera.depth(vmul(vadd(top, paw), 0.5)));
      l.paw.show(
        Camera.ellipsoid(paw, vmul(floor.forward, 4.5), vmul(floor.left, 3.6), vmul(floor.up, Anatomy.pawRadius)),
        Camera.depth(paw) - 0.05,
      );
      this.legs[index].depth = Camera.depth(vmul(vadd(top, paw), 0.5));
    });
  }

  /** Far regions first; legs always just before the body, which covers their tops. */
  private paint(ctx: CanvasRenderingContext2D, alpha: number): void {
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    const base = ctx.globalAlpha * alpha;
    if (this.shadow.path) {
      ctx.globalAlpha = base * this.shadow.opacity;
      ctx.fillStyle = "#000";
      trace(ctx, this.shadow.path);
      ctx.fill();
    }
    const order = [this.torso, this.head, this.tail, this.collar].sort((a, b) => b.depth - a.depth);
    const torsoIndex = Math.max(0, order.indexOf(this.torso));
    order.splice(torsoIndex, 0, ...[...this.legs].sort((a, b) => b.depth - a.depth));

    const withAlpha = (part: Part, draw: () => void) => {
      const own = part.opacity;
      part.opacity = own * base;
      draw();
      part.opacity = own;
    };
    for (const region of order) {
      const shown = region.parts.filter((part) => part.path !== null);
      for (const part of shown) withAlpha(part, () => part.drawEdge(ctx));
      for (const part of [...shown].sort((a, b) => b.depth - a.depth)) withAlpha(part, () => part.drawFill(ctx));
      region.parts.forEach((part) => part.reset());
    }
    ctx.restore();
  }
}

/** A flat ear seen edge-on would vanish; real ears are cupped, so keep a minimum width. */
function readableWidth(across: P2, length: P2, outward: P2, minimum: number): P2 {
  const size = Math.hypot(length.x, length.y);
  if (size <= 1e-6) return across;
  const perpendicular = { x: -length.y / size, y: length.x / size };
  const width = across.x * perpendicular.x + across.y * perpendicular.y;
  if (Math.abs(width) >= minimum) return across;
  const outwardSide = outward.x * perpendicular.x + outward.y * perpendicular.y;
  const sign = width !== 0 ? (width > 0 ? 1 : -1) : outwardSide > 0 ? -1 : 1;
  const extra = sign * minimum - width;
  return { x: across.x + perpendicular.x * extra, y: across.y + perpendicular.y * extra };
}

// MARK: - Frames and fetch geometry

/** Where she stands and how her body and head are turned. Drawing and fetch geometry share it. */
function frames(p: Pose, pitch: number): { floor: Frame; body: Frame; head: Frame; lift: number } {
  const tau = 2 * Math.PI;
  const g = Math.min(1, Math.max(0, p.gallop));
  const bow = Math.min(1, Math.max(0, p.bow));
  const crouch = Math.min(1, Math.max(0, p.crouch));
  const reach = Math.min(1, Math.max(0, p.reach));
  const phase = p.stride - Math.floor(p.stride);

  const heading: Vec = [p.headingX, p.headingY, 0];
  const facing = vlen(heading) > 1e-6 ? vnorm(heading) : v(0, -1, 0);
  const floor = new Frame([0, 0, 0], facing, v(-facing[1], facing[0], 0), v(0, 0, 1));

  const bounce = 0.5 - 0.5 * Math.cos(tau * (phase - 0.1));
  const rock = 0.1 * g * Math.sin(tau * (phase + 0.05));
  const lift = p.lift + 4.5 * g * bounce + 2.5 * bow - 4.5 * crouch;
  const body = new Frame(v(0, 0, lift), floor.forward, floor.left, floor.up)
    .pitched(rock - 0.36 * bow, v(-2, 0, 22))
    .rolled(p.bank, v(0, 0, 4));
  const head = body
    .pitched(-0.6 * rock + 0.32 * bow - 0.06 * crouch + 0.05 * g * Math.sin(tau * (phase + 0.35)) - pitch * reach, Anatomy.neck)
    .rolled(-p.headTilt * 0.8, Anatomy.skull.center);
  return { floor, body, head, lift };
}

/** The pose at the moment her mouth closes on a ball on the floor. */
function pickupPose(): Pose {
  const p = makePose();
  p.headingX = 1;
  p.headingY = 0;
  p.reach = 1;
  p.bow = 0.3;
  p.crouch = 0.25;
  return p;
}

let cachedPitch: number | null = null;
/** How far the head tips down at full reach: just enough that the ball touches the floor. */
function reachPitch(): number {
  if (cachedPitch !== null) return cachedPitch;
  let low = 0;
  let high = 1.6;
  const pose = pickupPose();
  for (let i = 0; i < 40; i++) {
    const mid = (low + high) / 2;
    const height = frames(pose, mid).head.point(Anatomy.ballHold)[2];
    if (height > Anatomy.ballRadius) low = mid;
    else high = mid;
  }
  cachedPitch = (low + high) / 2;
  return cachedPitch;
}

/**
 * Fetch geometry in pixels for an art box this wide: how far ahead of her paws the ball in her
 * mouth is when her head is down, and how high its bottom is when she lets go.
 */
export function fetchReach(artWidth: number): { reach: number; mouthHeight: number } {
  const points = (artWidth / 100) * CAMERA_SCALE;
  const pitch = reachPitch();
  const atFloor = frames(pickupPose(), pitch).head.point(Anatomy.ballHold);
  const letGo = pickupPose();
  letGo.reach = 0.55;
  const atRelease = frames(letGo, pitch).head.point(Anatomy.ballHold);
  return { reach: atFloor[0] * points, mouthHeight: Math.max(2, atRelease[2] - Anatomy.ballRadius) * points };
}
