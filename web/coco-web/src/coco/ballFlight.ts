import { V2, add, sub, mul, len } from "./math";

/**
 * A thrown thing's whole journey: an arc under gravity, a few bounces that each keep less of
 * their height and lose speed to friction, then a roll (or skid) to a stop. A pure function of
 * time in stage pixels with y up, tracked as a point on the floor plus a height above it.
 */
export interface Material {
  bounciness: number;
  firstFriction: number;
  laterFriction: number;
  braking: number;
  rolls: boolean;
  tumble: number | null;
  airBase: number;
  airPerPoint: number;
  airMin: number;
  airMax: number;
}

export const TENNIS_BALL: Material = {
  bounciness: 0.5,
  firstFriction: 0.5,
  laterFriction: 0.65,
  braking: 1100,
  rolls: true,
  tumble: null,
  airBase: 0.42,
  airPerPoint: 1 / 1500,
  airMin: 0.45,
  airMax: 1.15,
};

/** Lighter and flatter: a lower, quicker arc, flipping end over end, a small bounce and a skid. */
export const TREAT: Material = {
  bounciness: 0.28,
  firstFriction: 0.35,
  laterFriction: 0.45,
  braking: 2600,
  rolls: false,
  tumble: 14,
  airBase: 0.3,
  airPerPoint: 1 / 1900,
  airMin: 0.32,
  airMax: 0.85,
};

interface Segment {
  start: number;
  duration: number;
  ground: V2;
  velocity: V2;
  /** Upward speed at the start; null for a roll. */
  lift: number | null;
  height: number;
  braking: number;
  spin: number;
  spinRate: number;
}

export interface Loose {
  ground: V2;
  height: number;
  spin: number;
}

export class BallFlight {
  static gravity = 1900;
  static radius = 7;

  readonly startTime: number;
  readonly rest: V2;
  readonly landTime: number;
  readonly restTime: number;
  readonly landing: V2;
  private readonly segments: Segment[];

  constructor(opts: {
    from: V2;
    height: number;
    to: V2;
    at: number;
    flightTime?: number;
    bounciness?: number;
    material?: Material;
  }) {
    const material = opts.material ?? TENNIS_BALL;
    const g = BallFlight.gravity;
    const r = BallFlight.radius;
    const start = opts.from;
    const throwLength = len(sub(opts.to, start));
    const airTime =
      opts.flightTime ??
      Math.min(material.airMax, Math.max(material.airMin, material.airBase + throwLength * material.airPerPoint));
    let velocity = mul(sub(opts.to, start), 1 / airTime);
    const lift = (0.5 * g * airTime * airTime - opts.height) / airTime;
    const direction = len(velocity) > 1e-6 ? (velocity.x >= 0 ? 1 : -1) : 1;

    const segments: Segment[] = [];
    let clock = 0;
    let spin = 0;
    let spinRate = direction * (material.tumble ?? (len(velocity) / r) * 0.6);
    let position = start;
    segments.push({ start: 0, duration: airTime, ground: start, velocity, lift, height: opts.height, braking: 0, spin: 0, spinRate });
    clock += airTime;
    spin += spinRate * airTime;
    position = add(position, mul(velocity, airTime));
    let impact = lift - g * airTime;

    let keep = opts.bounciness ?? material.bounciness;
    for (let bounce = 0; bounce < 6; bounce++) {
      const up = -impact * keep;
      const peak = (up * up) / (2 * g);
      if (peak < 1.2) break;
      velocity = mul(velocity, bounce === 0 ? material.firstFriction : material.laterFriction);
      spinRate = material.rolls ? ((direction * len(velocity)) / r) * 0.9 : spinRate * 0.35;
      const airborne = (2 * up) / g;
      segments.push({ start: clock, duration: airborne, ground: position, velocity, lift: up, height: 0, braking: 0, spin, spinRate });
      clock += airborne;
      spin += spinRate * airborne;
      position = add(position, mul(velocity, airborne));
      impact = -up;
      keep *= bounce % 2 === 0 ? 0.83 : 0.9;
    }

    const sliding = len(velocity) * 0.85;
    const braking = material.braking;
    const slideTime = sliding / braking;
    const slideDirection = len(velocity) > 1e-6 ? mul(velocity, 1 / len(velocity)) : { x: 0, y: 0 };
    if (slideTime > 0.01) {
      segments.push({
        start: clock,
        duration: slideTime,
        ground: position,
        velocity: mul(slideDirection, sliding),
        lift: null,
        height: 0,
        braking,
        spin,
        spinRate: material.rolls ? (direction * sliding) / r : 0,
      });
      position = add(position, mul(slideDirection, (sliding * slideTime) / 2));
      clock += slideTime;
    }

    this.startTime = opts.at;
    this.segments = segments;
    this.rest = position;
    this.landing = opts.to;
    this.landTime = opts.at + airTime;
    this.restTime = opts.at + clock;
  }

  ground(t: number): V2 {
    const found = this.locate(t);
    if (!found) return t < this.startTime ? this.segments[0].ground : this.rest;
    const [s, dt] = found;
    if (s.lift !== null) return add(s.ground, mul(s.velocity, dt));
    const speed = len(s.velocity);
    const travelled = speed * dt - 0.5 * s.braking * dt * dt;
    return add(s.ground, mul(speed > 0 ? mul(s.velocity, 1 / speed) : { x: 0, y: 0 }, travelled));
  }

  height(t: number): number {
    const found = this.locate(t);
    if (!found || found[0].lift === null) return t < this.startTime ? this.segments[0].height : 0;
    const [s, dt] = found;
    return Math.max(0, s.height + (s.lift ?? 0) * dt - 0.5 * BallFlight.gravity * dt * dt);
  }

  spin(t: number): number {
    const found = this.locate(t);
    if (!found) {
      const last = this.segments[this.segments.length - 1];
      if (!last || t < this.startTime) return 0;
      return last.spin + this.rollSpin(last, last.duration);
    }
    return found[0].spin + this.rollSpin(found[0], found[1]);
  }

  at(t: number): Loose {
    return { ground: this.ground(t), height: this.height(t), spin: this.spin(t) };
  }

  /** Times it hits the floor: the first landing and every bounce. */
  get impacts(): number[] {
    return this.segments.filter((s) => s.lift !== null).map((s) => this.startTime + s.start + s.duration);
  }

  private rollSpin(s: Segment, dt: number): number {
    if (s.lift !== null) return s.spinRate * dt;
    const fraction = s.duration > 0 ? dt / s.duration : 1;
    return s.spinRate * dt * (1 - fraction / 2);
  }

  private locate(t: number): [Segment, number] | null {
    const local = t - this.startTime;
    if (local < 0) return null;
    for (const s of this.segments) {
      if (local < s.start + s.duration) return [s, local - s.start];
    }
    return null;
  }
}
