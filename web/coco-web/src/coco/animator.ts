import { V2, ease, hash, turn, clamp } from "./math";
import { Pose, makePose, blendPose } from "./pose";
import { Dash, DASH_HANDBACK } from "./dash";
import { Fetch, TreatGame } from "./games";

/**
 * Turns a state plus recent events into a `Pose` for any moment in time. A pure function of
 * time, ported from the Mac app's `CharacterAnimator`: blinks, glances, ear twitches, wags and
 * breathing come from the clock with deterministic noise, so her idle life matches the app.
 */
export type CharacterState = "idle" | "sleeping";
export type Reaction = "poke" | "land" | "nod" | "perk" | "bark";
export type TrickKind = "spin" | "bow" | "jump" | "beg";

const REACTION_DURATION: Record<Reaction, number> = { poke: 1.0, land: 0.9, nod: 0.5, perk: 0.9, bark: 0.4 };

export const TRICK_DURATION: Record<TrickKind, number> = { spin: 1.75, bow: 2.1, jump: 1.45, beg: 2.3 };

export interface Trick {
  kind: TrickKind;
  start: number;
  /** Turning direction for the spin: 1 counter-clockwise on the floor, −1 clockwise. */
  side: number;
}

const FAST = 1 / 60;
const GENTLE = 1 / 30;
const TRANSITION = 0.3;
const BEG_EASE = 0.25;
const SPOTTED = 0.2;
const GAZE_EASE = 0.18;
const HOVER_FADE = 0.25;

const FRONT: V2 = { x: 0, y: -1 };

export class Animator {
  state: CharacterState = "idle";
  reduceMotion = false;

  dash: Dash | null = null;
  fetch: Fetch | null = null;
  treat: TreatGame | null = null;
  trick: Trick | null = null;

  private transitionFrom: Pose | null = null;
  private stateChangedAt = -Infinity;
  private reactions: { kind: Reaction; start: number }[] = [];

  private gazeFrom: V2 = { x: 0, y: 0 };
  private gazeTo: V2 = { x: 0, y: 0 };
  private gazeChangedAt = -Infinity;
  private hovering = false;
  private hoverChangedAt = -Infinity;

  private carried = false;
  private carriedChangedAt = -Infinity;

  private begStart: number | null = null;
  private begEnd: number | null = null;

  // MARK: Inputs

  setState(next: CharacterState, t: number): void {
    if (next === this.state) return;
    this.transitionFrom = this.basePose(t);
    this.state = next;
    this.stateChangedAt = t;
  }

  react(kind: Reaction, t: number): void {
    this.reactions = this.reactions.filter((r) => t - r.start <= REACTION_DURATION[r.kind]);
    this.reactions.push({ kind, start: t });
  }

  /** Point the eyes at a normalised target (−1…1 per axis, +y down), or null to stop. */
  look(target: V2 | null, t: number): void {
    this.gazeFrom = this.hoverGaze(t);
    if (target) this.gazeTo = { x: clamp(target.x, -1, 1), y: clamp(target.y, -1, 1) };
    this.gazeChangedAt = t;
    if ((target !== null) !== this.hovering) {
      this.hovering = target !== null;
      this.hoverChangedAt = t;
    }
  }

  setCarried(isCarried: boolean, t: number): void {
    if (isCarried === this.carried) return;
    this.carried = isCarried;
    this.carriedChangedAt = t;
  }

  get isCarried(): boolean {
    return this.carried;
  }

  setBegging(begging: boolean, t: number): void {
    if (begging) {
      if (!(this.begStart === null || this.begEnd !== null)) return;
      const current = this.begAmount(t);
      this.begStart = t - BEG_EASE * current;
      this.begEnd = null;
    } else {
      if (this.begStart === null || this.begEnd !== null) return;
      this.begEnd = t;
    }
  }

  begAmount(t: number): number {
    if (this.begStart === null) return 0;
    const rising = ease((t - this.begStart) / BEG_EASE);
    if (this.begEnd === null) return rising;
    const peak = ease((this.begEnd - this.begStart) / BEG_EASE);
    return peak * (1 - ease((t - this.begEnd) / BEG_EASE));
  }

  // MARK: Output

  pose(t: number): Pose {
    const p = this.basePose(t);

    const blink = blinkAmount(t);
    p.eyeOpen *= 1 - blink * (1 - p.eyeSmile);

    if (this.state === "idle") {
      for (const event of idleEvents(t)) {
        if (event.kind === "glance" && this.hovering) continue;
        applyIdle(event, t, p);
      }
    }

    const weight = this.hoverInfluence(t) * (this.state === "idle" ? 1 : 0);
    const hover = this.hoverGaze(t);
    p.gazeX += (hover.x - p.gazeX) * weight;
    p.gazeY += (hover.y - p.gazeY) * weight;

    const carry = this.carryAmount(t);
    if (carry > 0) {
      p.dangle = carry;
      p.eyeOpen += (1 - p.eyeOpen) * carry;
      p.eyeScale += 0.14 * carry;
      p.mouthOpen = Math.max(p.mouthOpen, 0.35 * carry);
      p.mouthCurve *= 1 - carry;
      p.tongue *= 1 - carry;
      p.squash -= 0.05 * carry;
      p.headDip *= 1 - carry;
      p.earPerk += (0.35 - p.earPerk) * carry;
      p.earLeft += carry * (0.2 + 0.12 * Math.sin(t * 6.5));
      p.earRight += carry * (0.2 + 0.12 * Math.sin(t * 6.5 + 1));
      p.tail += carry * 0.3 * Math.sin(t * 5);
    }

    for (const r of this.reactions) {
      const dt = t - r.start;
      if (dt >= 0 && dt < REACTION_DURATION[r.kind]) applyReaction(r.kind, dt, p);
    }

    let q = p;
    if (this.dash && t < this.dash.endTime) q = applyDash(this.dash, t, q);
    const beg = this.begAmount(t);
    if (beg > 0) applyBegging(beg, t, q);
    if (this.fetch && t < this.fetch.endTime) q = applyFetch(this.fetch, t, q);
    if (this.treat && t < this.treat.endTime) q = applyTreat(this.treat, t, q);
    if (this.trick && t < this.trick.start + TRICK_DURATION[this.trick.kind]) q = applyTrick(this.trick, t, q);

    if (this.reduceMotion) {
      q.lift = 0;
      q.squash = 0;
      q.tilt = 0;
      q.tail *= 0.3;
      q.earLeft *= 0.3;
      q.earRight *= 0.3;
    }
    q.clock = t;
    return q;
  }

  /** How often to draw right now, or null when nothing is moving. */
  frameInterval(t: number): number | null {
    if (t - this.stateChangedAt < TRANSITION) return FAST;
    if (this.dash && t < this.dash.endTime) return FAST;
    if (this.fetch && t < this.fetch.endTime) return FAST;
    if (this.treat && t < this.treat.endTime) return FAST;
    if (this.trick && t < this.trick.start + TRICK_DURATION[this.trick.kind]) return FAST;
    if (this.begStart !== null && t >= this.begStart && (this.begEnd === null || t - this.begEnd < BEG_EASE)) return FAST;
    if (this.reactions.some((r) => t >= r.start && t - r.start < REACTION_DURATION[r.kind])) return FAST;
    if (this.carried || t - this.carriedChangedAt < 0.25) return FAST;
    if (t - this.gazeChangedAt < GAZE_EASE || t - this.hoverChangedAt < HOVER_FADE) return FAST;
    if (blinkAmount(t) > 0) return FAST;
    if (this.state === "idle") {
      const moving = idleEvents(t).filter((e) => isMoving(e, t) && !(e.kind === "glance" && this.hovering));
      if (moving.some((e) => e.kind === "earTwitch" || e.kind === "glance" || e.kind === "curiousTilt")) return FAST;
      if (moving.length > 0) return GENTLE;
    }
    if (this.state === "sleeping") return 1 / 12;
    return 1 / 10;
  }

  // MARK: Composition

  private basePose(t: number): Pose {
    const target = statePose(this.state, t);
    if (!this.transitionFrom) return target;
    const k = (t - this.stateChangedAt) / TRANSITION;
    if (k >= 1) return target;
    return blendPose(this.transitionFrom, target, ease(k));
  }

  private hoverGaze(t: number): V2 {
    const k = ease((t - this.gazeChangedAt) / GAZE_EASE);
    return { x: this.gazeFrom.x + (this.gazeTo.x - this.gazeFrom.x) * k, y: this.gazeFrom.y + (this.gazeTo.y - this.gazeFrom.y) * k };
  }

  private hoverInfluence(t: number): number {
    const k = ease((t - this.hoverChangedAt) / HOVER_FADE);
    return this.hovering ? k : 1 - k;
  }

  private carryAmount(t: number): number {
    const dt = t - this.carriedChangedAt;
    return this.carried ? ease(dt / 0.15) : 1 - ease(dt / 0.2);
  }
}

// MARK: - Per-state poses

function statePose(state: CharacterState, t: number): Pose {
  const p = makePose();
  if (state === "idle") {
    p.squash = 0.012 * Math.sin((t * 2 * Math.PI) / 4.2);
    p.tail = 0.07 * Math.sin(t * 1.3);
  } else {
    const breath = Math.sin((t * 2 * Math.PI) / 5.5);
    p.squash = 0.022 * breath;
    p.eyeOpen = 0;
    p.headDip = 4 + 0.6 * breath;
    p.headTilt = -0.08;
    p.earPerk = 0.1;
    p.mouthCurve = 0.2;
    p.sleepZ = 1;
  }
  return p;
}

function applyReaction(kind: Reaction, dt: number, p: Pose): void {
  switch (kind) {
    case "poke":
      p.squash += 0.13 * Math.exp(-dt * 6.5) * Math.cos(dt * 24);
      p.eyeScale += 0.22 * Math.exp(-dt * 5);
      p.earLeft += 0.3 * Math.exp(-dt * 4) * Math.sin(dt * 17);
      p.earRight += 0.3 * Math.exp(-dt * 4) * Math.sin(dt * 17 + 0.6);
      p.tail += 0.4 * Math.exp(-dt * 3) * Math.sin(dt * 20);
      break;
    case "land": {
      p.squash += 0.11 * Math.exp(-dt * 8) * Math.cos(dt * 26);
      const flop = 0.3 * Math.exp(-dt * 3.5) * Math.sin(dt * 15);
      p.earLeft += flop;
      p.earRight += flop;
      break;
    }
    case "nod": {
      const bump = Math.sin(Math.min(1, dt / REACTION_DURATION.nod) * Math.PI);
      p.headDip += 3 * bump;
      p.squash += 0.03 * bump;
      p.eyeSmile = Math.min(1, p.eyeSmile + 0.5 * bump);
      break;
    }
    case "bark": {
      // Matches the ~0.2 s sound: open fast, close a touch slower.
      const open = dt < 0.06 ? dt / 0.06 : Math.max(0, 1 - (dt - 0.06) / 0.16);
      p.mouthOpen = Math.max(p.mouthOpen, 0.95 * open);
      p.earPerk = Math.min(1, p.earPerk + 0.3 * open);
      p.squash -= 0.04 * open;
      p.lift += 2 * open;
      p.eyeScale += 0.08 * open;
      p.tail += 0.3 * Math.exp(-dt * 4) * Math.sin(dt * 20);
      break;
    }
    case "perk":
      p.earPerk = Math.min(1, p.earPerk + 0.3 * Math.exp(-dt * 4));
      p.earLeft -= 0.12 * Math.exp(-dt * 5);
      p.earRight -= 0.12 * Math.exp(-dt * 5);
      p.eyeScale += 0.1 * Math.exp(-dt * 6);
      p.lift += 2.5 * Math.sin(Math.min(1, dt / 0.3) * Math.PI);
      p.tail += 0.45 * Math.exp(-dt * 2.5) * Math.sin(dt * 18);
      break;
  }
}

/** The running Coco mid-dash: bounding along with a happy, open-mouthed face. */
export function runningPose(base: Pose, facing: V2, strides: number, effort: number, t: number): Pose {
  const p = { ...base };
  p.run = 1;
  p.headingX = facing.x;
  p.headingY = facing.y;
  p.stride = strides;
  p.gallop = Math.min(1, 0.35 * Math.min(1, effort / 0.03) + effort);
  p.earBack = Math.min(1, 0.2 + effort);
  p.earPerk = 1;
  p.eyeSmile = 0.85;
  p.eyeOpen = 1;
  p.mouthOpen = 0.55;
  p.mouthCurve = 0.8;
  p.tongue = 1;
  p.tail = 0.45 * Math.sin(t * 20);
  p.lift = 0;
  p.squash = 0;
  p.tilt = 0;
  p.headTilt = 0;
  p.headDip = 0;
  return p;
}

/** Plops down: the sitting drawing lands squashed and wobbles back up. */
function plop(p: Pose, s: number, t: number, wag = 0.5): void {
  p.squash += 0.13 * Math.exp(-s * 5) * Math.cos(s * 13);
  p.tongue = Math.max(p.tongue, 1);
  p.mouthOpen = Math.max(p.mouthOpen, 0.45);
  p.eyeSmile = Math.max(p.eyeSmile, 0.7 * (1 - s));
  p.tail += wag * Math.sin(t * 18);
}

function applyDash(dash: Dash, t: number, p: Pose): Pose {
  const phase = dash.phase(t);
  switch (phase.kind) {
    case "ready": {
      const k = phase.k;
      if (k < SPOTTED) {
        // Spots the place: eyes lock on, ears shoot up, a little "!" hop.
        const s = k / SPOTTED;
        const heading = dash.direction(t);
        p.earPerk = 1;
        p.eyeScale += 0.2 * ease(s / 0.4);
        p.gazeX = heading.x;
        p.gazeY = -heading.y;
        p.lift += 3 * Math.sin(s * Math.PI);
        p.squash += 0.06 * ease((s - 0.6) / 0.4);
        p.mouthOpen = Math.max(p.mouthOpen, 0.25 * Math.sin(s * Math.PI));
        return p;
      }
      return windUp(dash, (k - SPOTTED) / (1 - SPOTTED), t, p);
    }
    case "running": {
      const r = runningPose(p, dash.facing(t), dash.strides(t), dash.effort(t), t);
      const now = dash.facing(t);
      const before = dash.facing(t - 0.05);
      const swing = (before.x * now.y - before.y * now.x) / 0.05;
      r.bank = clamp(swing * 0.06, -0.3, 0.3);
      return r;
    }
    case "settling": {
      const k = phase.k;
      if (k < DASH_HANDBACK) {
        const s = k / DASH_HANDBACK;
        const facing = turn(dash.facing(t), FRONT, ease(s / 0.85));
        const r = runningPose(p, facing, dash.strides(t), 0, t);
        r.crouch = 0.4 * ease(s);
        r.earBack = 0.4 * (1 - s);
        return r;
      }
      plop(p, (k - DASH_HANDBACK) / (1 - DASH_HANDBACK), t);
      return p;
    }
    case "finished":
      return p;
  }
}

/** Getting ready: turns to the spot, drops into a play bow, gathers low, then lets go. */
function windUp(dash: Dash, s: number, t: number, base: Pose): Pose {
  const target = dash.facing(t);
  const bow = ease(s / 0.25) * (1 - ease((s - 0.8) / 0.2));
  const wiggle = 0.09 * Math.sin(t * 34) * bow;
  const toward = turn(FRONT, target, ease(s / 0.35));
  const facing = {
    x: toward.x * Math.cos(wiggle) - toward.y * Math.sin(wiggle),
    y: toward.x * Math.sin(wiggle) + toward.y * Math.cos(wiggle),
  };
  const p = runningPose(base, facing, 0, 0, t);
  p.bow = bow;
  p.crouch = 0.6 * Math.exp(-s * 14) + 0.45 * ease((s - 0.45) / 0.35) * (1 - ease((s - 0.88) / 0.12));
  p.tail = 0.65 * Math.sin(t * 28);
  p.earBack = 0;
  p.eyeSmile = 0;
  p.eyeScale = 1.12;
  p.mouthOpen = 0.35;
  p.tongue = 0.5;
  return p;
}

function applyFetch(game: Fetch, t: number, p: Pose): Pose {
  const phase = game.phase(t);
  switch (phase.kind) {
    case "notice": {
      const k = phase.k;
      const g = game.ball.ground(t);
      const ball = { x: g.x - game.home.x, y: g.y + game.ball.height(t) - game.home.y };
      const distance = Math.max(140, Math.hypot(ball.x, ball.y));
      p.gazeX = ball.x / distance;
      p.gazeY = -ball.y / distance;
      p.earPerk = 1;
      p.eyeScale += 0.22 * ease(k / 0.3);
      p.lift += 4 * Math.sin(Math.min(1, k / 0.7) * Math.PI);
      p.squash += 0.07 * ease((k - 0.7) / 0.3);
      p.mouthOpen = Math.max(p.mouthOpen, 0.35);
      p.tail += 0.5 * Math.sin(t * 26);
      return p;
    }
    case "chase": {
      if (phase.dash.kind === "ready") {
        const k = phase.dash.k;
        const r = runningPose(p, turn(FRONT, game.chaseFacing(t), ease(k / 0.7)), game.chase.strides(t), 0, t);
        r.crouch = 0.55 * Math.exp(-k * 10) + 0.3 * ease((k - 0.5) / 0.5);
        r.eyeSmile = 0;
        r.eyeScale = 1.15;
        r.tail = 0.7 * Math.sin(t * 30);
        return r;
      }
      const r = runningPose(p, game.chaseFacing(t), game.chase.strides(t), game.chase.effort(t), t);
      r.eyeSmile = 0.2;
      r.eyeScale = 1.08;
      return r;
    }
    case "pickup": {
      const k = phase.k;
      const r = runningPose(p, game.pickupFacing, game.chase.strides(game.pickupStart) + 0.6 * ease(k / 0.25), 0, t);
      r.gallop = 0.25 * (1 - ease(k / 0.25));
      const down = ease(k / Fetch.contact) * (1 - ease((k - Fetch.contact - 0.08) / 0.3));
      r.reach = down;
      r.bow = 0.3 * down;
      r.crouch = 0.25 * down;
      r.carry = k >= Fetch.contact ? 1 : 0;
      r.tongue = 0;
      r.mouthOpen = k < Fetch.contact ? 0.6 * ease((k - 0.2) / 0.25) : 0.3;
      r.eyeSmile = k >= Fetch.contact ? 0.85 : 0;
      r.tail = (k >= Fetch.contact ? 0.6 : 0.3) * Math.sin(t * 24);
      return r;
    }
    case "homeward": {
      let r: Pose;
      if (phase.dash.kind === "ready") {
        const k = phase.dash.k;
        r = runningPose(p, turn(game.pickupFacing, game.homewardFacing(t), ease(k)), game.homeward.strides(t) + 1.2 * k, 0, t);
        r.gallop = 0.25 * Math.sin(k * Math.PI);
      } else {
        r = runningPose(p, game.homewardFacing(t), game.homeward.strides(t), game.homeward.effort(t), t);
      }
      r.carry = 1;
      r.tongue = 0;
      r.mouthOpen = 0.3;
      r.eyeSmile = 0.85;
      return r;
    }
    case "drop": {
      const k = phase.k;
      if (k < Fetch.handback) {
        const s = k / Fetch.handback;
        const arrived = game.homewardFacing(game.dropStart);
        const r = runningPose(p, turn(arrived, FRONT, ease(s / 0.45)), game.homeward.strides(t), 0, t);
        const release = Fetch.release / Fetch.handback;
        const down = ease((s - 0.25) / (release - 0.25)) * (1 - ease((s - release) / (1 - release)));
        r.reach = down;
        r.bow = 0.3 * down;
        r.crouch = 0.2 * down + 0.35 * ease((s - 0.75) / 0.25);
        r.carry = k < Fetch.release ? 1 : 0;
        r.tongue = k < Fetch.release ? 0 : 1;
        r.mouthOpen = k < Fetch.release ? 0.3 : 0.55;
        r.eyeSmile = 0.85;
        r.tail = 0.6 * Math.sin(t * 22);
        return r;
      }
      const s = (k - Fetch.handback) / (1 - Fetch.handback);
      p.squash += 0.13 * Math.exp(-s * 5) * Math.cos(s * 13);
      p.tongue = 1;
      p.mouthOpen = Math.max(p.mouthOpen, 0.5);
      p.eyeSmile = Math.max(p.eyeSmile, 0.8);
      p.gazeY = 0.5;
      p.tail += 0.55 * Math.sin(t * 20);
      return p;
    }
    case "finished":
      return p;
  }
}

/** Begging: sitting up tall, front paws pawing the air, head cocked, a busy tail. */
function applyBegging(amount: number, t: number, p: Pose): void {
  p.beg = amount;
  p.earPerk = p.earPerk + (1 - p.earPerk) * amount;
  p.eyeScale += 0.14 * amount;
  p.headTilt += (0.12 + 0.05 * Math.sin(t * 2.2)) * amount;
  p.mouthCurve += (0.8 - p.mouthCurve) * amount;
  p.mouthOpen = Math.max(p.mouthOpen, (0.2 + 0.08 * Math.sin(t * 9)) * amount);
  p.tongue = Math.max(p.tongue, 0.35 * amount);
  p.lift += (1.5 + 1.2 * Math.abs(Math.sin(t * 4.5))) * amount;
  p.squash += -0.035 * amount;
  p.tail += 0.4 * Math.sin(t * 18) * amount;
}

/** The happy jump on the spot: crouch, spring up, stretch out at the top, land soft. */
function jumpPose(p: Pose, k: number, t: number, fromSitting: boolean): Pose {
  if (k < TreatGame.handback) {
    const r = runningPose(p, FRONT, 0.3, 0, t);
    const air = TreatGame.jump(k);
    const landed = k >= TreatGame.landing;
    r.lift = TreatGame.jumpHeight * air;
    r.crouch =
      k < TreatGame.takeoff
        ? 0.75 * ease(k / TreatGame.takeoff) + (fromSitting ? 0.5 * Math.exp(-k * 30) : 0)
        : landed
          ? 0.7 * Math.exp(-(k - TreatGame.landing) * 14)
          : 0;
    r.gallop = air > 0 ? 0.6 : 0;
    r.earBack = air > 0 ? 0.25 * (1 - air) : 0;
    r.earPerk = 1;
    r.eyeSmile = 1;
    r.mouthOpen = 0.55 + 0.2 * air;
    r.tongue = 1;
    r.sparkles = k > TreatGame.takeoff ? Math.min(1, (k - TreatGame.takeoff) / 0.08) : 0;
    r.tail = 0.7 * Math.sin(t * 30);
    return r;
  }
  const s = (k - TreatGame.handback) / (1 - TreatGame.handback);
  p.squash += 0.12 * Math.exp(-s * 5) * Math.cos(s * 13);
  p.eyeSmile = Math.max(p.eyeSmile, 1);
  p.tongue = 1;
  p.mouthOpen = Math.max(p.mouthOpen, 0.5);
  p.sparkles = Math.max(p.sparkles, 1 - s);
  p.tail += 0.6 * Math.sin(t * 24);
  return p;
}

function applyTreat(game: TreatGame, t: number, p: Pose): Pose {
  const phase = game.phase(t);
  switch (phase.kind) {
    case "notice": {
      const k = phase.k;
      const g = game.treat.ground(t);
      const treat = { x: g.x - game.home.x, y: g.y + game.treat.height(t) - game.home.y };
      const distance = Math.max(140, Math.hypot(treat.x, treat.y));
      p.gazeX = treat.x / distance;
      p.gazeY = -treat.y / distance;
      p.earPerk = 1;
      p.eyeScale += 0.2;
      p.lift += 3 * Math.sin(Math.min(1, k / 0.8) * Math.PI);
      p.squash += 0.06 * ease((k - 0.75) / 0.25);
      p.mouthOpen = Math.max(p.mouthOpen, 0.3);
      p.tail += 0.55 * Math.sin(t * 28);
      return p;
    }
    case "chase": {
      let r: Pose;
      if (phase.dash.kind === "ready") {
        const k = phase.dash.k;
        r = runningPose(p, turn(FRONT, game.chaseFacing(t), ease(k / 0.7)), game.chase.strides(t), 0, t);
        r.crouch = 0.55 * Math.exp(-k * 10) + 0.3 * ease((k - 0.5) / 0.5);
        r.tail = 0.7 * Math.sin(t * 30);
      } else {
        r = runningPose(p, game.chaseFacing(t), game.chase.strides(t), game.chase.effort(t), t);
      }
      r.eyeSmile = 0.15;
      r.eyeScale = 1.1;
      return r;
    }
    case "eat": {
      const k = phase.k;
      const facing = turn(game.eatFacing, FRONT, ease((k - 0.62) / 0.33));
      const r = runningPose(p, facing, game.chase.strides(game.eatStart) + 0.5 * ease(k / 0.18), 0, t);
      r.gallop = 0.22 * (1 - ease(k / 0.18));
      const bite = TreatGame.bite;
      const chewing = k >= bite && k < TreatGame.chewEnd;
      const down = ease((k - 0.06) / (bite - 0.06));
      const chomp = chewing ? Math.sin(((k - bite) / (TreatGame.chewEnd - bite)) * 3 * Math.PI) : 0;
      r.reach = k < bite ? down : Math.max(0, (0.32 + 0.12 * chomp) * (1 - ease((k - TreatGame.chewEnd + 0.1) / 0.18)));
      r.bow = 0.3 * r.reach;
      r.crouch = 0.2 * r.reach;
      r.mouthOpen = k < bite ? 0.65 * ease((k - 0.12) / 0.14) : chewing ? 0.32 * Math.max(0, chomp) : 0.15;
      r.tongue = k >= TreatGame.chewEnd ? Math.sin(((k - TreatGame.chewEnd) / (1 - TreatGame.chewEnd)) * Math.PI) : 0;
      r.eyeSmile = k < bite ? 0 : 0.95;
      r.earPerk = 1;
      r.earBack = 0;
      r.tail = (k < bite ? 0.3 : 0.65) * Math.sin(t * 24);
      return r;
    }
    case "celebrate":
      return jumpPose(p, phase.k, t, false);
    case "finished":
      return p;
  }
}

// MARK: - Tricks (new for the web)

/** When in a trick she says something (bark), as a share of its length. */
export const TRICK_BARK_AT: Record<TrickKind, number> = { spin: 0.9, bow: 0.3, jump: 0.42, beg: 0.45 };

function applyTrick(trick: Trick, t: number, p: Pose): Pose {
  const k = (t - trick.start) / TRICK_DURATION[trick.kind];
  switch (trick.kind) {
    case "spin": {
      // A quick perk, then a full turn on the spot, trotting round, and back to sitting.
      const swapIn = 0.1;
      const swapOut = 0.88;
      if (k < swapIn) {
        const s = k / swapIn;
        p.earPerk = 1;
        p.eyeScale += 0.15 * ease(s / 0.5);
        p.lift += 2.5 * Math.sin(s * Math.PI);
        p.squash += 0.06 * ease((s - 0.6) / 0.4);
        return p;
      }
      if (k < swapOut) {
        const s = (k - swapIn) / (swapOut - swapIn);
        const angle = -Math.PI / 2 + trick.side * 2 * Math.PI * ease(s);
        const r = runningPose(p, { x: Math.cos(angle), y: Math.sin(angle) }, 3.4 * s, 0, t);
        r.gallop = 0.38 * Math.sin(Math.PI * Math.min(1, s * 1.15));
        r.crouch = 0.55 * Math.exp(-s * 12) + 0.3 * ease((s - 0.82) / 0.18);
        // Leans into the turn, hardest in the middle.
        r.bank = trick.side * 0.22 * Math.sin(Math.PI * s);
        r.earBack = 0.25 + 0.3 * Math.sin(Math.PI * s);
        r.tail = 0.6 * Math.sin(t * 26);
        return r;
      }
      plop(p, (k - swapOut) / (1 - swapOut), t, 0.55);
      return p;
    }
    case "bow": {
      // Play bow: turns a little to the side, front down, rear up and wiggling, then a pounce.
      const swapIn = 0.06;
      const swapOut = 0.86;
      if (k < swapIn) {
        p.squash += 0.07 * ease(k / swapIn);
        p.earPerk = 1;
        return p;
      }
      if (k < swapOut) {
        const s = (k - swapIn) / (swapOut - swapIn);
        const side = { x: trick.side * 0.86, y: -0.5 };
        const toward = turn(FRONT, side, ease(s / 0.18) * (1 - ease((s - 0.82) / 0.18)));
        const bow = ease((s - 0.08) / 0.2) * (1 - ease((s - 0.66) / 0.12));
        const wiggle = 0.1 * Math.sin(t * 34) * bow;
        const facing = {
          x: toward.x * Math.cos(wiggle) - toward.y * Math.sin(wiggle),
          y: toward.x * Math.sin(wiggle) + toward.y * Math.cos(wiggle),
        };
        const hop = Math.sin(Math.PI * clamp((s - 0.7) / 0.16, 0, 1));
        const r = runningPose(p, facing, 0.25 * hop, 0, t);
        r.bow = bow;
        r.lift = 10 * hop;
        r.gallop = 0.5 * hop;
        r.crouch = 0.55 * Math.exp(-s * 16) + 0.45 * ease((s - 0.88) / 0.12);
        r.tail = 0.7 * Math.sin(t * 28);
        r.earBack = 0.2 * hop;
        r.eyeSmile = bow > 0.5 ? 0 : 0.6;
        r.eyeScale = 1.12;
        r.mouthOpen = 0.45;
        r.tongue = 0.6;
        return r;
      }
      plop(p, (k - swapOut) / (1 - swapOut), t, 0.6);
      return p;
    }
    case "jump":
      return jumpPose(p, k, t, true);
    case "beg": {
      // Sit pretty: up on her haunches, paws going, held for a moment.
      const amount = ease(k / 0.12) * (1 - ease((k - 0.86) / 0.14));
      applyBegging(amount, t, p);
      p.eyeSmile = Math.max(p.eyeSmile, 0.4 * amount * (k > 0.55 ? 1 : 0));
      return p;
    }
  }
}

// MARK: - Blinks

const BLINK_PERIOD = 4.4;
const BLINK_LENGTH = 0.17;
const DOUBLE_BLINK_GAP = 0.26;

export function blinkAmount(t: number): number {
  const cycle = Math.floor(t / BLINK_PERIOD);
  const local = t - blinkStart(cycle);
  let amount = blinkCurve(local);
  if (hash(cycle + 0.53) > 0.78) amount = Math.max(amount, blinkCurve(local - DOUBLE_BLINK_GAP));
  return amount;
}

function blinkStart(cycle: number): number {
  return cycle * BLINK_PERIOD + 0.3 + hash(cycle * 1.91) * (BLINK_PERIOD - 0.9);
}

function blinkCurve(x: number): number {
  if (x < 0 || x > BLINK_LENGTH) return 0;
  if (x < 0.06) return x / 0.06;
  if (x < 0.08) return 1;
  return 1 - (x - 0.08) / (BLINK_LENGTH - 0.08);
}

// MARK: - Idle life

type IdleKind = "glance" | "earTwitch" | "wag" | "pant" | "curiousTilt";
interface IdleEvent {
  kind: IdleKind;
  start: number;
  duration: number;
  seed: number;
}

const IDLE_RAMP = 0.18;
const IDLE_KINDS: IdleKind[] = ["glance", "earTwitch", "wag", "pant", "curiousTilt"];
const SCHEDULE: Record<IdleKind, { period: number; chance: number; min: number; max: number; salt: number }> = {
  glance: { period: 7, chance: 0.6, min: 1.2, max: 2.4, salt: 3.17 },
  earTwitch: { period: 8, chance: 0.5, min: 0.45, max: 0.45, salt: 5.3 },
  wag: { period: 15, chance: 0.4, min: 1.6, max: 2.4, salt: 7.9 },
  pant: { period: 30, chance: 0.4, min: 2.5, max: 3.5, salt: 11.3 },
  curiousTilt: { period: 19, chance: 0.4, min: 1.4, max: 2.2, salt: 13.7 },
};

function idleEvent(kind: IdleKind, cycle: number): IdleEvent | null {
  const s = SCHEDULE[kind];
  if (!(hash(cycle * 1.37 + s.salt) < s.chance)) return null;
  const duration = s.min + hash(cycle + s.salt + 0.71) * (s.max - s.min);
  const start = cycle * s.period + 0.5 + hash(cycle + s.salt + 0.37) * Math.max(0, s.period - duration - 1);
  return { kind, start, duration, seed: hash(cycle + s.salt + 1.3) };
}

function idleEvents(t: number): IdleEvent[] {
  const out: IdleEvent[] = [];
  for (const kind of IDLE_KINDS) {
    const e = idleEvent(kind, Math.floor(t / SCHEDULE[kind].period));
    if (e && t >= e.start && t <= e.start + e.duration) out.push(e);
  }
  return out;
}

function envelope(e: IdleEvent, t: number): number {
  const end = e.start + e.duration;
  return Math.min(ease((t - e.start) / IDLE_RAMP), 1 - ease((t - end + IDLE_RAMP) / IDLE_RAMP));
}

function isMoving(e: IdleEvent, t: number): boolean {
  const end = e.start + e.duration;
  if (t < e.start || t > end) return false;
  if (e.kind === "glance" || e.kind === "curiousTilt") return t <= e.start + IDLE_RAMP || t >= end - IDLE_RAMP;
  return true;
}

function applyIdle(e: IdleEvent, t: number, p: Pose): void {
  const dt = t - e.start;
  const env = envelope(e, t);
  switch (e.kind) {
    case "glance":
      p.gazeX += (e.seed * 2 - 1) * env;
      p.gazeY += (hash(e.start) * 2 - 1) * 0.5 * env;
      break;
    case "earTwitch": {
      const flick = 0.32 * Math.sin(dt * 28) * Math.exp(-dt * 6);
      if (e.seed < 0.5) p.earLeft += flick;
      else p.earRight += flick;
      break;
    }
    case "wag":
      p.tail += 0.45 * Math.sin(dt * 16) * env;
      p.tilt += 0.015 * Math.sin(dt * 16) * env;
      break;
    case "pant":
      p.tongue = Math.max(p.tongue, env);
      p.mouthOpen = Math.max(p.mouthOpen, (0.42 + 0.1 * Math.sin(dt * 14)) * env);
      p.squash += 0.015 * Math.sin(dt * 14) * env;
      p.eyeSmile = Math.max(p.eyeSmile, 0.35 * env);
      break;
    case "curiousTilt":
      p.headTilt += (e.seed < 0.5 ? -1 : 1) * 0.2 * env;
      p.earPerk = Math.min(1, p.earPerk + 0.15 * env);
      break;
  }
}
