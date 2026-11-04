import { V2, add, sub, len } from "./math";
import { Dash, DashPhase, VIEW_ELEVATION } from "./dash";
import { BallFlight, Loose } from "./ballFlight";

/** Her mouth's offset on screen from her paws, for a facing on the floor. */
export function mouthOffset(facing: V2, reach: number): V2 {
  return { x: facing.x * reach, y: facing.y * reach * Math.sin(VIEW_ELEVATION) };
}

function towards(screen: V2): V2 | null {
  return len(screen) > 1e-6 ? Dash.facingFor(screen) : null;
}

/** Where to stand, and which way to face, so her mouth — not her paws — ends up over a target. */
export function approach(target: V2, home: V2, reach: number): { spot: V2; facing: V2 } {
  let facing = towards(sub(target, home)) ?? { x: 0, y: -1 };
  let spot = sub(target, mouthOffset(facing, reach));
  for (let i = 0; i < 3; i++) {
    const direction = towards(sub(spot, home));
    if (!direction || len(sub(spot, home)) <= 20) break;
    facing = direction;
    spot = sub(target, mouthOffset(facing, reach));
  }
  return { spot, facing };
}

export type FetchPhase =
  | { kind: "notice"; k: number }
  | { kind: "chase"; dash: DashPhase }
  | { kind: "pickup"; k: number }
  | { kind: "homeward"; dash: DashPhase }
  | { kind: "drop"; k: number }
  | { kind: "finished" };

/**
 * A game of fetch: she notices the throw, chases while the ball is in the air (paced to reach
 * it as it settles), picks it up, runs back to where she started and drops it at her paws.
 */
export class Fetch {
  static noticeDuration = 0.32;
  static chaseWindUp = 0.2;
  static pickupDuration = 0.9;
  static contact = 0.5;
  static turnAround = 0.38;
  static dropDuration = 1.0;
  static release = 0.42;
  static handback = 0.64;

  readonly startTime: number;
  readonly home: V2;
  readonly ball: BallFlight;
  readonly chase: Dash;
  readonly homeward: Dash;
  readonly pickupSpot: V2;
  readonly pickupFacing: V2;
  readonly drop: BallFlight;

  constructor(home: V2, ball: BallFlight, time: number, reach: number, mouthHeight: number) {
    this.home = home;
    this.ball = ball;
    this.startTime = time;
    const a = approach(ball.rest, home, reach);
    this.pickupSpot = a.spot;
    this.pickupFacing = a.facing;
    this.chase = new Dash({
      from: home,
      to: this.pickupSpot,
      at: time + Fetch.noticeDuration,
      readyDuration: Fetch.chaseWindUp,
      settleDuration: 0,
      earliestArrival: ball.restTime + 0.05,
    });
    const pickupEnd = this.chase.arrivalTime + Fetch.pickupDuration;
    this.homeward = new Dash({ from: this.pickupSpot, to: home, at: pickupEnd, readyDuration: Fetch.turnAround, settleDuration: 0 });
    const mouth = add(home, mouthOffset({ x: 0, y: -1 }, reach));
    const fall = Math.sqrt((2 * mouthHeight) / BallFlight.gravity);
    this.drop = new BallFlight({
      from: mouth,
      height: mouthHeight,
      to: add(mouth, { x: 0, y: -4 }),
      at: this.homeward.arrivalTime + Fetch.dropDuration * Fetch.release,
      flightTime: Math.max(0.06, fall),
      bounciness: 0.5,
    });
  }

  get pickupStart(): number {
    return this.chase.arrivalTime;
  }
  get contactTime(): number {
    return this.pickupStart + Fetch.pickupDuration * Fetch.contact;
  }
  get dropStart(): number {
    return this.homeward.arrivalTime;
  }
  get releaseTime(): number {
    return this.dropStart + Fetch.dropDuration * Fetch.release;
  }
  get endTime(): number {
    return this.dropStart + Fetch.dropDuration;
  }

  phase(t: number): FetchPhase {
    if (t < this.chase.startTime) return { kind: "notice", k: Math.max(0, (t - this.startTime) / Fetch.noticeDuration) };
    if (t < this.chase.arrivalTime) return { kind: "chase", dash: this.chase.phase(t) };
    if (t < this.homeward.startTime) return { kind: "pickup", k: (t - this.pickupStart) / Fetch.pickupDuration };
    if (t < this.homeward.arrivalTime) return { kind: "homeward", dash: this.homeward.phase(t) };
    if (t < this.endTime) return { kind: "drop", k: (t - this.dropStart) / Fetch.dropDuration };
    return { kind: "finished" };
  }

  position(t: number): V2 {
    switch (this.phase(t).kind) {
      case "notice":
        return this.home;
      case "chase":
        return this.chase.position(t);
      case "pickup":
        return this.pickupSpot;
      case "homeward":
        return this.homeward.position(t);
      default:
        return this.home;
    }
  }

  isCarrying(t: number): boolean {
    return t >= this.contactTime && t < this.releaseTime;
  }

  looseBall(t: number): Loose | null {
    if (this.isCarrying(t)) return null;
    return (t < this.contactTime ? this.ball : this.drop).at(t);
  }

  chaseFacing(t: number): V2 {
    return this.chase.length > 20 ? this.chase.facing(t) : this.pickupFacing;
  }

  homewardFacing(t: number): V2 {
    return this.homeward.length > 20 ? this.homeward.facing(t) : { x: 0, y: -1 };
  }
}

export type TreatPhase =
  | { kind: "notice"; k: number }
  | { kind: "chase"; dash: DashPhase }
  | { kind: "eat"; k: number }
  | { kind: "celebrate"; k: number }
  | { kind: "finished" };

/** A treat: she follows the toss, chases it, eats it where it lands and jumps for joy. */
export class TreatGame {
  static noticeDuration = 0.22;
  static chaseWindUp = 0.15;
  static eatDuration = 1.35;
  static bite = 0.3;
  static chewEnd = 0.8;
  static celebrateDuration = 1.35;
  static takeoff = 0.3;
  static landing = 0.6;
  static handback = 0.84;
  static jumpHeight = 24;

  readonly startTime: number;
  readonly home: V2;
  readonly treat: BallFlight;
  readonly chase: Dash;
  readonly eatSpot: V2;
  readonly eatFacing: V2;

  constructor(home: V2, treat: BallFlight, time: number, reach: number) {
    this.home = home;
    this.treat = treat;
    this.startTime = time;
    const a = approach(treat.rest, home, reach);
    this.eatSpot = a.spot;
    this.eatFacing = a.facing;
    this.chase = new Dash({
      from: home,
      to: this.eatSpot,
      at: time + TreatGame.noticeDuration,
      readyDuration: TreatGame.chaseWindUp,
      settleDuration: 0,
      earliestArrival: treat.restTime + 0.05,
    });
  }

  get eatStart(): number {
    return this.chase.arrivalTime;
  }
  get biteTime(): number {
    return this.eatStart + TreatGame.eatDuration * TreatGame.bite;
  }
  get celebrateStart(): number {
    return this.eatStart + TreatGame.eatDuration;
  }
  get endTime(): number {
    return this.celebrateStart + TreatGame.celebrateDuration;
  }

  phase(t: number): TreatPhase {
    if (t < this.chase.startTime) return { kind: "notice", k: Math.max(0, (t - this.startTime) / TreatGame.noticeDuration) };
    if (t < this.chase.arrivalTime) return { kind: "chase", dash: this.chase.phase(t) };
    if (t < this.celebrateStart) return { kind: "eat", k: (t - this.eatStart) / TreatGame.eatDuration };
    if (t < this.endTime) return { kind: "celebrate", k: (t - this.celebrateStart) / TreatGame.celebrateDuration };
    return { kind: "finished" };
  }

  position(t: number): V2 {
    const kind = this.phase(t).kind;
    if (kind === "notice") return this.home;
    if (kind === "chase") return this.chase.position(t);
    return this.eatSpot;
  }

  looseTreat(t: number): Loose | null {
    return t < this.biteTime ? this.treat.at(t) : null;
  }

  chaseFacing(t: number): V2 {
    return this.chase.length > 20 ? this.chase.facing(t) : this.eatFacing;
  }

  /** Height of the celebration jump, 0…1 of the jump height. */
  static jump(k: number): number {
    if (k <= TreatGame.takeoff || k >= TreatGame.landing) return 0;
    const u = (k - TreatGame.takeoff) / (TreatGame.landing - TreatGame.takeoff);
    return 4 * u * (1 - u);
  }
}
