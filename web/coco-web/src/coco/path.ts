/**
 * A tiny path format that can be transformed point by point (so line widths stay constant,
 * like Core Animation's path transforms) and traced into a canvas.
 */
export type Cmd =
  | ["M", number, number]
  | ["L", number, number]
  | ["Q", number, number, number, number]
  | ["C", number, number, number, number, number, number]
  | ["Z"];

export type Path = Cmd[];

/** An affine transform: x' = a·x + c·y + e, y' = b·x + d·y + f (canvas/CG order). */
export interface Affine {
  a: number;
  b: number;
  c: number;
  d: number;
  e: number;
  f: number;
}

export class PathBuilder {
  readonly cmds: Path = [];
  move(x: number, y: number): this {
    this.cmds.push(["M", x, y]);
    return this;
  }
  line(x: number, y: number): this {
    this.cmds.push(["L", x, y]);
    return this;
  }
  quad(x: number, y: number, cx: number, cy: number): this {
    this.cmds.push(["Q", cx, cy, x, y]);
    return this;
  }
  curve(x: number, y: number, c1x: number, c1y: number, c2x: number, c2y: number): this {
    this.cmds.push(["C", c1x, c1y, c2x, c2y, x, y]);
    return this;
  }
  close(): this {
    this.cmds.push(["Z"]);
    return this;
  }
}

const K = 0.5522847498;

/** An ellipse in a rect, as four cubic Béziers (exact under any affine transform). */
export function ellipse(x: number, y: number, w: number, h: number): Path {
  const rx = w / 2;
  const ry = h / 2;
  const cx = x + rx;
  const cy = y + ry;
  return [
    ["M", cx + rx, cy],
    ["C", cx + rx, cy + ry * K, cx + rx * K, cy + ry, cx, cy + ry],
    ["C", cx - rx * K, cy + ry, cx - rx, cy + ry * K, cx - rx, cy],
    ["C", cx - rx, cy - ry * K, cx - rx * K, cy - ry, cx, cy - ry],
    ["C", cx + rx * K, cy - ry, cx + rx, cy - ry * K, cx + rx, cy],
    ["Z"],
  ];
}

export function roundedRect(x: number, y: number, w: number, h: number, r: number): Path {
  const k = r * (1 - K);
  return [
    ["M", x + r, y],
    ["L", x + w - r, y],
    ["C", x + w - k, y, x + w, y + k, x + w, y + r],
    ["L", x + w, y + h - r],
    ["C", x + w, y + h - k, x + w - k, y + h, x + w - r, y + h],
    ["L", x + r, y + h],
    ["C", x + k, y + h, x, y + h - k, x, y + h - r],
    ["L", x, y + r],
    ["C", x, y + k, x + k, y, x + r, y],
    ["Z"],
  ];
}

export const UNIT_CIRCLE = ellipse(-1, -1, 2, 2);

export function transform(path: Path, m: Affine): Path {
  const px = (x: number, y: number) => m.a * x + m.c * y + m.e;
  const py = (x: number, y: number) => m.b * x + m.d * y + m.f;
  return path.map((cmd): Cmd => {
    switch (cmd[0]) {
      case "M":
      case "L":
        return [cmd[0], px(cmd[1], cmd[2]), py(cmd[1], cmd[2])];
      case "Q":
        return ["Q", px(cmd[1], cmd[2]), py(cmd[1], cmd[2]), px(cmd[3], cmd[4]), py(cmd[3], cmd[4])];
      case "C":
        return [
          "C",
          px(cmd[1], cmd[2]),
          py(cmd[1], cmd[2]),
          px(cmd[3], cmd[4]),
          py(cmd[3], cmd[4]),
          px(cmd[5], cmd[6]),
          py(cmd[5], cmd[6]),
        ];
      case "Z":
        return ["Z"];
    }
  });
}

export const translate = (path: Path, dx: number, dy: number): Path => transform(path, { a: 1, b: 0, c: 0, d: 1, e: dx, f: dy });
export const scaleXY = (path: Path, sx: number, sy: number): Path => transform(path, { a: sx, b: 0, c: 0, d: sy, e: 0, f: 0 });

export function trace(ctx: CanvasRenderingContext2D, path: Path): void {
  ctx.beginPath();
  for (const cmd of path) {
    switch (cmd[0]) {
      case "M":
        ctx.moveTo(cmd[1], cmd[2]);
        break;
      case "L":
        ctx.lineTo(cmd[1], cmd[2]);
        break;
      case "Q":
        ctx.quadraticCurveTo(cmd[1], cmd[2], cmd[3], cmd[4]);
        break;
      case "C":
        ctx.bezierCurveTo(cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6]);
        break;
      case "Z":
        ctx.closePath();
        break;
    }
  }
}

/** Caches a Path2D for a static path (the sitting drawing never changes shape). */
const cache = new WeakMap<Path, Path2D>();
export function path2D(path: Path): Path2D {
  let p = cache.get(path);
  if (!p) {
    p = new Path2D();
    for (const cmd of path) {
      switch (cmd[0]) {
        case "M":
          p.moveTo(cmd[1], cmd[2]);
          break;
        case "L":
          p.lineTo(cmd[1], cmd[2]);
          break;
        case "Q":
          p.quadraticCurveTo(cmd[1], cmd[2], cmd[3], cmd[4]);
          break;
        case "C":
          p.bezierCurveTo(cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6]);
          break;
        case "Z":
          p.closePath();
          break;
      }
    }
    cache.set(path, p);
  }
  return p;
}
