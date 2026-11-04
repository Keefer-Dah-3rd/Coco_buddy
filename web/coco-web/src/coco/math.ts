/** Small 2D vector helpers. Game space is in CSS pixels with y pointing UP (as on the Mac). */
export interface V2 {
  x: number;
  y: number;
}

export const v2 = (x: number, y: number): V2 => ({ x, y });
export const add = (a: V2, b: V2): V2 => ({ x: a.x + b.x, y: a.y + b.y });
export const sub = (a: V2, b: V2): V2 => ({ x: a.x - b.x, y: a.y - b.y });
export const mul = (a: V2, k: number): V2 => ({ x: a.x * k, y: a.y * k });
export const len = (a: V2): number => Math.hypot(a.x, a.y);
export const dist = (a: V2, b: V2): number => Math.hypot(a.x - b.x, a.y - b.y);

export function normalized(a: V2): V2 | null {
  const l = len(a);
  return l > 1e-9 ? { x: a.x / l, y: a.y / l } : null;
}

export const clamp = (x: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, x));

/** Smoothstep, clamped to 0…1. */
export function ease(x: number): number {
  const k = clamp(x, 0, 1);
  return k * k * (3 - 2 * k);
}

export function smoothstep(lower: number, upper: number, x: number): number {
  return ease((x - lower) / (upper - lower));
}

export const fract = (x: number): number => x - Math.floor(x);

/** Cheap deterministic noise in 0..<1 (same as the Mac app, so her habits match). */
export function hash(x: number): number {
  const v = Math.sin(x * 12.9898 + 78.233) * 43758.5453;
  return v - Math.floor(v);
}

/** Turns a unit vector toward another the shorter way round; k from 0 to 1. */
export function turn(a: V2, b: V2, k: number): V2 {
  const start = Math.atan2(a.y, a.x);
  let delta = Math.atan2(b.y, b.x) - start;
  if (delta > Math.PI) delta -= 2 * Math.PI;
  if (delta < -Math.PI) delta += 2 * Math.PI;
  const angle = start + delta * k;
  return { x: Math.cos(angle), y: Math.sin(angle) };
}
