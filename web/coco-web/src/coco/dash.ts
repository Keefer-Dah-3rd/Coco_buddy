import { V2, add, sub, mul, len, normalized } from "./math";

/**
 * A dash across the floor: where her paws are at any moment, how fast she's going and
 * which way she's headed. A pure function of time (ported from the Mac app's `Dash`).
 * Points are stage pixels with y up; the position is where her paws touch the ground.
 */
export type DashPhase =
  | { kind: "ready"; k: number }
  | { kind: "running"; k: number }
  | { kind: "settling"; k: number }
  | { kind: "finished" };

export const VIEW_ELEVATION = (24 * Math.PI) / 180;
const FACINGS = 32;
const FACING_BLEND = 0.1;
/** Share of the settle spent braking and turning, in the running drawing. */
export const DASH_HANDBACK = 0.45;

export class Dash {
  static topSpeed = 1400;
  static topCadence = 5.5;
  static windUp = 0.5;
  static settle = 0.5;
  private static strideStep = 1 / 120;

  readonly start: V2;
  readonly end: V2;
  readonly startTime: number;
  readonly readyDuration: number;
  readonly settleDuration: number;
  private readonly course: Course;
  private readonly profile: SpeedProfile;
  private readonly strideOffset: number;
  private readonly strideTable: number[];

  constructor(opts: {
    from: V2;
    to: V2;
    at: number;
    readyDuration?: number;
    settleDuration?: number;
    earliestArrival?: number;
    speed?: number;
    heading?: V2 | null;
    strideOffset?: number;
  }) {
    const speed = opts.speed ?? 0;
    this.start = opts.from;
    this.end = opts.to;
    this.startTime = opts.at;
    this.readyDuration = opts.readyDuration ?? Dash.windUp;
    this.settleDuration = opts.settleDuration ?? Dash.settle;
    this.course = new Course(opts.from, opts.to, opts.heading ?? null, speed);
    let profile = new SpeedProfile(this.course.length, speed);
    const earliest = opts.earliestArrival;
    if (earliest !== undefined && opts.at + this.readyDuration + profile.duration < earliest) {
      const wanted = earliest - opts.at - this.readyDuration;
      let fast = Dash.topSpeed;
      let slow = 60;
      // Duration only grows as the speed limit drops: find the limit that fits.
      for (let i = 0; i < 30; i++) {
        const limit = (fast + slow) / 2;
        if (new SpeedProfile(this.course.length, speed, limit).duration < wanted) fast = limit;
        else slow = limit;
      }
      profile = new SpeedProfile(this.course.length, speed, slow);
    }
    this.profile = profile;
    this.strideOffset = opts.strideOffset ?? 0;
    this.strideTable = Dash.makeStrideTable(profile);
  }

  get launchTime(): number {
    return this.startTime + this.readyDuration;
  }
  get arrivalTime(): number {
    return this.launchTime + this.profile.duration;
  }
  get endTime(): number {
    return this.arrivalTime + this.settleDuration;
  }
  get length(): number {
    return this.course.length;
  }

  phase(t: number): DashPhase {
    if (t < this.launchTime)
      return { kind: "ready", k: this.readyDuration > 0 ? Math.max(0, (t - this.startTime) / this.readyDuration) : 1 };
    if (t < this.arrivalTime) return { kind: "running", k: (t - this.launchTime) / this.profile.duration };
    if (t < this.endTime) return { kind: "settling", k: (t - this.arrivalTime) / this.settleDuration };
    return { kind: "finished" };
  }

  position(t: number): V2 {
    return this.course.point(this.profile.distance(t - this.launchTime));
  }

  speed(t: number): number {
    return this.profile.speed(t - this.launchTime);
  }

  direction(t: number): V2 {
    return this.course.tangent(this.profile.distance(t - this.launchTime));
  }

  /** 0 standing … 1 full tilt. */
  effort(t: number): number {
    return Math.min(1, this.speed(t) / Dash.topSpeed);
  }

  /** Which way she faces on the floor (x right, y away), snapped to 32 facings and blended. */
  facing(t: number): V2 {
    const samples = 6;
    let sx = 0;
    let sy = 0;
    for (let k = 0; k < samples; k++) {
      const f = Dash.facingFor(this.direction(t - (FACING_BLEND * k) / (samples - 1)));
      sx += f.x;
      sy += f.y;
    }
    return normalized({ x: sx, y: sy }) ?? Dash.facingFor(this.direction(t));
  }

  /** The facing for a direction of travel on screen (y up), snapped to the 32 facings. */
  static facingFor(screen: V2): V2 {
    const angle = Math.atan2(screen.y / Math.sin(VIEW_ELEVATION), screen.x);
    const step = (2 * Math.PI) / FACINGS;
    const snapped = Math.round(angle / step) * step;
    return { x: Math.cos(snapped), y: Math.sin(snapped) };
  }

  /** Leg cycles so far; cadence follows speed so her paws never look like they slide. */
  strides(t: number): number {
    const x = (t - this.launchTime) / Dash.strideStep;
    if (!(x > 0)) return this.strideOffset;
    const i = Math.floor(x);
    const table = this.strideTable;
    if (i + 1 >= table.length) return this.strideOffset + (table[table.length - 1] ?? 0);
    const f = x - i;
    return this.strideOffset + table[i] + (table[i + 1] - table[i]) * f;
  }

  /** Changes course: from where she is now, at her current speed, curving round to `newEnd`. */
  redirected(newEnd: V2, t: number): Dash {
    const p = this.phase(t);
    switch (p.kind) {
      case "ready":
        return new Dash({ from: this.start, to: newEnd, at: this.startTime, readyDuration: this.readyDuration });
      case "running":
        return new Dash({
          from: this.position(t),
          to: newEnd,
          at: t,
          readyDuration: 0,
          speed: this.speed(t),
          heading: this.direction(t),
          strideOffset: this.strides(t),
        });
      case "settling":
        if (p.k < DASH_HANDBACK)
          return new Dash({ from: this.end, to: newEnd, at: t, readyDuration: 0, strideOffset: this.strides(t) });
        return new Dash({ from: this.end, to: newEnd, at: t });
      case "finished":
        return new Dash({ from: this.end, to: newEnd, at: t });
    }
  }

  static cadence(speed: number): number {
    return Dash.topCadence * Math.sqrt(Math.min(1, Math.max(0, speed) / Dash.topSpeed));
  }

  private static makeStrideTable(profile: SpeedProfile): number[] {
    const steps = Math.ceil(profile.duration / Dash.strideStep);
    const table = [0];
    let total = 0;
    for (let i = 0; i < steps; i++) {
      const v = profile.speed((i + 0.5) * Dash.strideStep);
      total += Dash.cadence(v) * Dash.strideStep;
      table.push(total);
    }
    return table;
  }
}

/** The line she runs along: straight from a standstill, curving when she changes course. */
class Course {
  private p0: V2;
  private p1: V2;
  private p2: V2;
  private p3: V2;
  private fallback: V2;
  private lengths: number[];
  private static samples = 64;

  constructor(a: V2, b: V2, heading: V2 | null, speed: number) {
    const chord = sub(b, a);
    const d = len(chord);
    const straight = d > 1e-6 ? mul(chord, 1 / d) : null;
    this.fallback = heading ?? straight ?? { x: 0, y: -1 };
    this.p0 = a;
    this.p3 = b;
    if (heading && d > 1) {
      const reach = Math.min(d * 0.5, 30 + speed * 0.15);
      this.p1 = add(a, mul(heading, reach));
      const arrival = normalized(sub(b, this.p1)) ?? this.fallback;
      this.p2 = sub(b, mul(arrival, d * 0.3));
    } else {
      this.p1 = add(a, mul(chord, 1 / 3));
      this.p2 = add(a, mul(chord, 2 / 3));
    }
    const lengths = [0];
    let previous = a;
    let total = 0;
    for (let i = 1; i <= Course.samples; i++) {
      const point = this.bezier(i / Course.samples);
      total += len(sub(point, previous));
      lengths.push(total);
      previous = point;
    }
    this.lengths = lengths;
  }

  get length(): number {
    return this.lengths[this.lengths.length - 1];
  }

  point(s: number): V2 {
    return this.bezier(this.parameter(s));
  }

  tangent(s: number): V2 {
    const u = this.parameter(s);
    const v = 1 - u;
    const { p0, p1, p2, p3 } = this;
    const d = {
      x: 3 * v * v * (p1.x - p0.x) + 6 * v * u * (p2.x - p1.x) + 3 * u * u * (p3.x - p2.x),
      y: 3 * v * v * (p1.y - p0.y) + 6 * v * u * (p2.y - p1.y) + 3 * u * u * (p3.y - p2.y),
    };
    return normalized(d) ?? this.fallback;
  }

  private parameter(sIn: number): number {
    if (this.length <= 0) return 0;
    const s = Math.min(Math.max(sIn, 0), this.length);
    let lo = 0;
    let hi = Course.samples;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (this.lengths[mid] < s) lo = mid;
      else hi = mid;
    }
    const span = this.lengths[hi] - this.lengths[lo];
    const f = span > 0 ? (s - this.lengths[lo]) / span : 0;
    return (lo + f) / Course.samples;
  }

  private bezier(u: number): V2 {
    const v = 1 - u;
    const { p0, p1, p2, p3 } = this;
    const a = v * v * v;
    const b = 3 * v * v * u;
    const c = 3 * v * u * u;
    const e = u * u * u;
    return { x: a * p0.x + b * p1.x + c * p2.x + e * p3.x, y: a * p0.y + b * p1.y + c * p2.y + e * p3.y };
  }
}

/** Eases up from the starting speed, cruises, then eases to a stop — no jolts at the joins. */
class SpeedProfile {
  readonly startSpeed: number;
  readonly peak: number;
  readonly rampUp: number;
  readonly cruise: number;
  readonly rampDown: number;

  constructor(distance: number, v0: number, speedLimit = Dash.topSpeed) {
    this.startSpeed = v0;
    if (!(distance > 0.5)) {
      this.peak = 0;
      this.rampUp = 0;
      this.cruise = 0;
      this.rampDown = 0;
      return;
    }
    const k = Math.min(1, distance / 400);
    const up = (0.16 + 0.19 * k) * (v0 > 0 ? 0.6 : 1);
    const down = 0.22 + 0.23 * k;
    const unlimited = (2 * distance - up * v0) / (up + down);
    if (unlimited < 0) {
      this.peak = v0;
      this.rampUp = 0;
      this.cruise = 0;
      this.rampDown = (2 * distance) / v0;
    } else if (unlimited > speedLimit && speedLimit >= v0) {
      this.peak = speedLimit;
      this.rampUp = up;
      this.rampDown = down;
      this.cruise = (distance - (up * (v0 + speedLimit)) / 2 - (down * speedLimit) / 2) / speedLimit;
    } else {
      this.peak = unlimited;
      this.rampUp = up;
      this.cruise = 0;
      this.rampDown = down;
    }
  }

  get duration(): number {
    return this.rampUp + this.cruise + this.rampDown;
  }

  speed(t: number): number {
    if (t <= 0) return this.startSpeed;
    if (t >= this.duration) return 0;
    if (t < this.rampUp) return this.startSpeed + (this.peak - this.startSpeed) * ss(t / this.rampUp);
    if (t < this.rampUp + this.cruise) return this.peak;
    return this.peak * (1 - ss((t - this.rampUp - this.cruise) / this.rampDown));
  }

  distance(tIn: number): number {
    const t = Math.min(Math.max(tIn, 0), this.duration);
    if (t < this.rampUp) {
      const x = t / this.rampUp;
      return this.rampUp * (this.startSpeed * x + (this.peak - this.startSpeed) * ssIntegral(x));
    }
    const afterRampUp = (this.rampUp * (this.startSpeed + this.peak)) / 2;
    if (t < this.rampUp + this.cruise) return afterRampUp + this.peak * (t - this.rampUp);
    if (!(this.rampDown > 0)) return afterRampUp + this.peak * this.cruise;
    const y = (t - this.rampUp - this.cruise) / this.rampDown;
    return afterRampUp + this.peak * this.cruise + this.rampDown * this.peak * (y - ssIntegral(y));
  }
}

function ss(x: number): number {
  const k = Math.min(1, Math.max(0, x));
  return k * k * (3 - 2 * k);
}

function ssIntegral(x: number): number {
  const k = Math.min(1, Math.max(0, x));
  return k * k * k - (k * k * k * k) / 2;
}
