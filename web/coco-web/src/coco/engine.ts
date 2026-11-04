import { V2, add, sub, mul, dist, len, clamp, ease } from "./math";
import { Animator, TrickKind, TRICK_DURATION, TRICK_BARK_AT } from "./animator";
import { Dash } from "./dash";
import { BallFlight, TREAT, Loose } from "./ballFlight";
import { Fetch, TreatGame } from "./games";
import { drawSitting, drawOverlays } from "./sitting";
import { RunningCoco, fetchReach } from "./running";
import { drawBall, drawTreat } from "./props";
import { Palette } from "./palette";

export type Tool = "come" | "ball" | "treat";

export interface EngineOptions {
  /** Coco's art box in CSS pixels (the Mac app's is 96). */
  artSize: number;
  /** Trots around on her own when nobody's playing with her. */
  wander: boolean;
  /** Called for every bark, so the host can play the sound. */
  onBark?: () => void;
  /** Floor kept clear at the bottom of the stage (for the toolbar), in pixels. */
  bottomInset?: number;
}

/** The Mac app's physics is tuned for a 96 pt Coco; everything sized by her scales from that. */
const APP_ART = 96;
const TRICKS: TrickKind[] = ["spin", "bow", "jump", "beg"];
/** Seconds a ball or treat on the floor takes to fade. */
const FADE = 0.45;
const BARK_WORDS = ["Woof!", "Arf!", "Bork!", "Woof!"];

interface Grab {
  pointerId: number;
  start: V2;
  /** From the pointer to her paws, in world space. */
  offset: V2;
  carrying: boolean;
}

interface FloorPress {
  pointerId: number;
  start: V2;
  lastRedirect: number;
}

/**
 * Coco on a web page: her position on the floor, the games she plays and the pointer, all in
 * one place, drawn onto a canvas. Game space is CSS pixels with y UP from the bottom of the
 * stage (as on the Mac, where all of her motion was designed); drawing flips it.
 */
export class CocoEngine {
  readonly animator = new Animator();
  private runner = new RunningCoco();
  private opts: EngineOptions;

  private width = 600;
  private height = 400;
  /** Where her paws touch the floor (world, y up). */
  private paws: V2 = { x: 300, y: 140 };

  tool: Tool = "come";
  sound = true;

  private ballRestAt: V2 | null = null;
  private ballRestSpin = 0;
  private ballRestSince = 0;
  /** How long a ball on the floor stays before it's back in your hand. */
  private ballLingers = 0;
  private treatLeft: Loose | null = null;
  private treatLeftSince = 0;

  private grab: Grab | null = null;
  private press: FloorPress | null = null;
  private pointer: V2 | null = null;
  private pointerType = "mouse";

  private pendingTrick: TrickKind | null = null;
  private trickIndex = 0;
  private barks: number[] = [];
  private lastBark = -Infinity;
  private bubble: { text: string; start: number } | null = null;
  private ripple: { at: V2; start: number; color: string } | null = null;

  private lastInteraction = 0;
  private nextWander = 0;
  private carriedLift = 0;
  /** How much of the running drawing showed last frame (she's wider when running). */
  private lastRun = 0;

  constructor(opts: EngineOptions, now: number) {
    this.opts = opts;
    this.lastInteraction = now;
    this.scheduleWander(now, true);
  }

  setOptions(opts: Partial<EngineOptions>): void {
    this.opts = { ...this.opts, ...opts };
    this.clampIntoStage();
  }

  get artSize(): number {
    return this.opts.artSize;
  }

  private get scale(): number {
    return this.opts.artSize / APP_ART;
  }

  setSize(width: number, height: number): void {
    this.width = Math.max(1, width);
    this.height = Math.max(1, height);
    // She takes her spot in the middle the first time the stage has a real size.
    if (!this.placed && width > 60 && height > 60) {
      this.placed = true;
      this.paws = this.clampToStage({ x: this.width / 2, y: this.height * 0.32 });
    }
    this.clampIntoStage();
  }

  private placed = false;

  // MARK: - Geometry

  /** Where her paws may go so all of her stays on the stage. */
  private get bounds(): { minX: number; maxX: number; minY: number; maxY: number } {
    const a = this.opts.artSize;
    const minX = Math.min(a * 0.45, this.width / 2);
    const minY = Math.min(Math.max(a * 0.08, this.opts.bottomInset ?? 0), this.height / 2);
    return {
      minX,
      maxX: Math.max(minX, this.width - a * 0.45),
      minY,
      maxY: Math.max(minY, this.height - a * 1.02),
    };
  }

  private clampToStage(p: V2): V2 {
    const b = this.bounds;
    return { x: clamp(p.x, b.minX, b.maxX), y: clamp(p.y, b.minY, b.maxY) };
  }

  private clampIntoStage(): void {
    if (this.busy || this.grab?.carrying) return;
    this.paws = this.clampToStage(this.paws);
    if (this.ballRestAt) {
      this.ballRestAt = { x: clamp(this.ballRestAt.x, 8, this.width - 8), y: clamp(this.ballRestAt.y, 4, this.height - 8) };
    }
  }

  private toWorld(cssX: number, cssY: number): V2 {
    return { x: cssX, y: this.height - cssY };
  }

  /** Is this point (CSS pixels on the stage) on her? */
  isOnCoco(cssX: number, cssY: number): boolean {
    return this.hits(this.toWorld(cssX, cssY));
  }

  /** Is this point (world) on her? */
  private hits(p: V2): boolean {
    const a = this.opts.artSize;
    const half = a * (this.lastRun > 0.5 ? 0.42 : 0.3);
    const paws = this.paws;
    return p.x >= paws.x - half && p.x <= paws.x + half && p.y >= paws.y - a * 0.06 && p.y <= paws.y + a * 0.92;
  }

  // MARK: - State

  get busy(): boolean {
    return this.animator.fetch !== null || this.animator.treat !== null || this.animator.trick !== null;
  }

  private get dashing(): boolean {
    return this.animator.dash !== null;
  }

  private touch(t: number): void {
    this.lastInteraction = t;
    if (this.animator.state === "sleeping") {
      this.animator.setState("idle", t);
      this.animator.react("perk", t);
    }
  }

  // MARK: - Actions

  /** One bark, with her mouth in sync and a little word bubble. */
  bark(t: number, minimumGap = 0.25): void {
    if (t - this.lastBark < minimumGap) return;
    this.lastBark = t;
    this.animator.react("bark", t);
    this.bubble = { text: BARK_WORDS[Math.floor(Math.random() * BARK_WORDS.length)], start: t };
    if (this.sound) this.opts.onBark?.();
  }

  /** Does a trick on the spot (the next in turn, or `kind`). Waits if she's busy. */
  trick(t: number, kind?: TrickKind): void {
    this.touch(t);
    const next = kind ?? TRICKS[this.trickIndex++ % TRICKS.length];
    if (this.busy || this.dashing || this.grab?.carrying) {
      this.pendingTrick = next;
      return;
    }
    this.startTrick(next, t);
  }

  private startTrick(kind: TrickKind, t: number): void {
    this.animator.setBegging(false, t);
    this.animator.trick = { kind, start: t, side: Math.random() < 0.5 ? 1 : -1 };
    this.barks.push(t + TRICK_DURATION[kind] * TRICK_BARK_AT[kind]);
  }

  /** Sends her running to a point (world). A second call mid-run changes course. */
  private call(target: V2, t: number, pace?: number): void {
    const to = this.clampToStage(target);
    const dash = this.animator.dash;
    if (dash) {
      this.animator.dash = dash.redirected(to, t);
    } else if (dist(this.paws, to) < 6) {
      this.animator.react("perk", t);
    } else if (pace) {
      const d = dist(this.paws, to);
      this.animator.dash = new Dash({
        from: this.paws,
        to,
        at: t,
        readyDuration: 0.45,
        settleDuration: Dash.settle,
        earliestArrival: t + 0.45 + d / pace,
      });
    } else {
      this.animator.dash = new Dash({ from: this.paws, to, at: t });
    }
  }

  private stopDash(t: number): void {
    const dash = this.animator.dash;
    if (!dash) return;
    this.paws = this.clampToStage(dash.position(t));
    this.animator.dash = null;
  }

  /** Throws her ball to land at `target` (world): she chases it, brings it back and drops it. */
  private throwBall(target: V2, t: number): void {
    if (this.busy) return;
    this.stopDash(t);
    this.animator.setBegging(false, t);
    const s = this.scale;
    const home = this.paws;
    const away = sub(target, home);
    const d = len(away);
    const direction = d > 1 ? mul(away, 1 / d) : { x: -1, y: 0 };
    const launch = add(add(home, mul(direction, 22 * s)), { x: 0, y: 4 });
    const geometry = fetchReach(this.opts.artSize);
    for (let step = 0; step <= 12; step++) {
      const landing = add(launch, mul(sub(target, launch), 1 - step * 0.075));
      const flight = new BallFlight({ from: launch, height: 46 * s, to: landing, at: t });
      const game = new Fetch(home, flight, t, geometry.reach, geometry.mouthHeight);
      if (this.reachable(flight.rest, game.pickupSpot)) {
        this.ballRestAt = null;
        this.animator.fetch = game;
        // A proud bark as she drops it at your feet.
        this.barks.push(game.releaseTime + 0.3);
        return;
      }
    }
  }

  /** Tosses her a treat to land at `target` (world): she chases it, eats it, jumps for joy. */
  private throwTreat(target: V2, t: number): void {
    if (this.busy) return;
    this.stopDash(t);
    this.animator.setBegging(false, t);
    const s = this.scale;
    const home = this.paws;
    const away = sub(target, home);
    const d = len(away);
    const direction = d > 1 ? mul(away, 1 / d) : { x: -1, y: 0 };
    const launch = add(add(home, mul(direction, 10 * s)), { x: 0, y: 6 });
    const reach = fetchReach(this.opts.artSize).reach;
    for (let step = 0; step <= 12; step++) {
      const landing = add(launch, mul(sub(target, launch), 1 - step * 0.075));
      const flight = new BallFlight({ from: launch, height: 72 * s, to: landing, at: t, material: TREAT });
      const game = new TreatGame(home, flight, t, reach);
      if (this.reachable(flight.rest, game.eatSpot)) {
        this.treatLeft = null;
        this.animator.treat = game;
        this.barks.push(game.celebrateStart + TreatGame.celebrateDuration * (TreatGame.takeoff + 0.05));
        return;
      }
    }
  }

  private reachable(rest: V2, standing: V2): boolean {
    const floor = Math.max(4, (this.opts.bottomInset ?? 0) * 0.7);
    const inStage = rest.x >= 8 && rest.x <= this.width - 8 && rest.y >= floor && rest.y <= this.height - 8;
    return inStage && dist(this.clampToStage(standing), standing) < 1;
  }

  /** Cuts a game short (she was picked up). The ball or treat ends up lying on the floor. */
  private stopGames(t: number): void {
    const fetch = this.animator.fetch;
    if (fetch) {
      if (fetch.isCarrying(t)) this.ballRestAt = { x: this.paws.x, y: this.paws.y - 12 * this.scale };
      else if (t < fetch.contactTime) this.ballRestAt = fetch.ball.rest;
      else this.ballRestAt = fetch.drop.rest;
      this.ballRestSpin = fetch.ball.spin(fetch.ball.restTime);
      this.ballRestSince = t;
      this.ballLingers = 8;
      this.animator.fetch = null;
    }
    const treat = this.animator.treat;
    if (treat) {
      if (t < treat.biteTime) {
        this.treatLeft = { ground: treat.treat.rest, height: 0, spin: treat.treat.spin(treat.treat.restTime) };
        this.treatLeftSince = t;
      }
      this.animator.treat = null;
    }
    this.animator.trick = null;
    this.barks = [];
  }

  // MARK: - Pointer (CSS pixels relative to the stage)

  pointerDown(x: number, y: number, pointerId: number, pointerType: string, t: number): boolean {
    this.pointerType = pointerType;
    this.touch(t);
    const p = this.toWorld(x, y);
    this.pointer = p;
    if (this.hits(p)) {
      this.grab = { pointerId, start: p, offset: sub(this.paws, p), carrying: false };
      return true;
    }
    this.press = { pointerId, start: p, lastRedirect: t };
    if (this.tool === "come") {
      if (!this.busy) {
        this.call(p, t);
        this.ripple = { at: this.clampToStage(p), start: t, color: Palette.accent };
      }
    } else if (this.tool === "treat") {
      if (!this.busy && !this.dashing) this.animator.setBegging(true, t);
    }
    return true;
  }

  pointerMove(x: number, y: number, pointerId: number, pointerType: string, t: number): void {
    this.pointerType = pointerType;
    const p = this.toWorld(x, y);
    this.pointer = p;
    // She sleeps through the mouse just passing by (a click wakes her); otherwise a pointer
    // on the stage keeps her company.
    if (this.animator.state === "idle") this.lastInteraction = t;

    const grab = this.grab;
    if (grab && grab.pointerId === pointerId) {
      if (!grab.carrying && dist(p, grab.start) > 5) {
        // Picked up: whatever she was doing stops.
        grab.carrying = true;
        if (this.dashing) this.stopDash(t);
        this.stopGames(t);
        this.pendingTrick = null;
        this.animator.setBegging(false, t);
        this.animator.setCarried(true, t);
      }
      if (grab.carrying) {
        const b = this.bounds;
        const target = add(p, grab.offset);
        this.paws = { x: clamp(target.x, b.minX, b.maxX), y: clamp(target.y, b.minY - this.opts.artSize * 0.04, b.maxY) };
      }
      return;
    }

    const press = this.press;
    if (press && press.pointerId === pointerId && this.tool === "come" && !this.busy && t - press.lastRedirect > 0.12) {
      // Holding the pointer down and moving it: she follows.
      if (dist(p, press.start) > 12) {
        press.lastRedirect = t;
        press.start = p;
        this.call(p, t);
      }
    }

    this.updateGaze(t);
    this.updateBegging(t);
  }

  pointerUp(x: number, y: number, pointerId: number, t: number): void {
    const p = this.toWorld(x, y);
    const grab = this.grab;
    if (grab && grab.pointerId === pointerId) {
      this.grab = null;
      if (grab.carrying) {
        this.animator.setCarried(false, t);
        this.animator.react("land", t);
        this.paws = this.clampToStage(this.paws);
      } else {
        // A tap on her: a happy poke and a hello.
        this.animator.react("poke", t);
        this.bark(t, 0.6);
      }
      this.scheduleWander(t);
      return;
    }
    const press = this.press;
    if (press && press.pointerId === pointerId) {
      this.press = null;
      if (this.tool === "ball") {
        this.throwBall(p, t);
        if (this.animator.fetch) this.ripple = null;
      } else if (this.tool === "treat") {
        this.throwTreat(p, t);
        if (!this.animator.treat) this.updateBegging(t);
      }
    }
  }

  pointerCancel(pointerId: number, t: number): void {
    if (this.grab?.pointerId === pointerId) {
      if (this.grab.carrying) {
        this.animator.setCarried(false, t);
        this.animator.react("land", t);
      }
      this.grab = null;
    }
    if (this.press?.pointerId === pointerId) this.press = null;
    this.updateBegging(t);
  }

  pointerLeave(t: number): void {
    if (this.pointerType === "mouse") this.pointer = null;
    this.animator.look(null, t);
    this.updateBegging(t);
  }

  setTool(tool: Tool, t: number): void {
    this.tool = tool;
    this.updateBegging(t);
  }

  /** Arrow keys: a short trot that way. */
  nudge(dx: number, dy: number, t: number): void {
    this.touch(t);
    if (this.busy) return;
    const step = this.opts.artSize * 1.1;
    const from = this.animator.dash ? this.animator.dash.end : this.paws;
    this.call(add(from, { x: dx * step, y: dy * step }), t);
  }

  /** Keyboard throw: toward the middle of the stage, away from her. */
  throwToward(kind: "ball" | "treat", t: number): void {
    this.touch(t);
    const center = { x: this.width / 2, y: this.height * 0.45 };
    const away = sub(center, this.paws);
    const target = len(away) < 60 ? add(this.paws, { x: this.paws.x < this.width / 2 ? 220 : -220, y: 0 }) : add(this.paws, mul(away, 1.6));
    const clamped = { x: clamp(target.x, 20, this.width - 20), y: clamp(target.y, 10, this.height - 20) };
    if (kind === "ball") this.throwBall(clamped, t);
    else this.throwTreat(clamped, t);
  }

  private updateGaze(t: number): void {
    const p = this.pointer;
    if (!p || this.grab?.carrying) {
      this.animator.look(null, t);
      return;
    }
    const head = add(this.paws, { x: 0, y: this.opts.artSize * 0.62 });
    const d = sub(p, head);
    const range = Math.max(160, this.opts.artSize * 2.4);
    this.animator.look({ x: d.x / range, y: -d.y / range }, t);
  }

  /** With the treat tool out and the pointer on the stage (or a finger down), she begs. */
  private updateBegging(t: number): void {
    const holding = this.tool === "treat" && (this.pointerType === "mouse" ? this.pointer !== null : this.press !== null);
    const can = !this.busy && !this.dashing && !this.grab?.carrying;
    this.animator.setBegging(holding && can, t);
  }

  // MARK: - Every frame

  /** Advances games and her own little life. Call once per frame before `draw`. */
  update(t: number): void {
    const a = this.animator;

    if (a.dash) {
      this.paws = a.dash.position(t);
      if (t >= a.dash.endTime) {
        this.paws = a.dash.end;
        a.dash = null;
        this.scheduleWander(t);
      }
    }
    if (a.fetch) {
      this.paws = a.fetch.position(t);
      if (t >= a.fetch.endTime) {
        this.ballRestAt = a.fetch.drop.rest;
        this.ballRestSpin = a.fetch.drop.spin(a.fetch.drop.restTime);
        this.ballRestSince = t;
        // Dropped at your feet: it's back in your hand in a moment.
        this.ballLingers = 2.2;
        a.fetch = null;
        this.scheduleWander(t);
      }
    }
    if (a.treat) {
      this.paws = a.treat.position(t);
      if (t >= a.treat.endTime) {
        a.treat = null;
        this.scheduleWander(t);
        this.updateBegging(t);
      }
    }
    if (a.trick && t >= a.trick.start + TRICK_DURATION[a.trick.kind]) {
      a.trick = null;
      this.scheduleWander(t);
    }
    if (this.pendingTrick && !this.busy && !this.dashing && !this.grab?.carrying) {
      const kind = this.pendingTrick;
      this.pendingTrick = null;
      this.startTrick(kind, t);
    }

    // Scheduled barks (a proud drop, a happy jump, a trick's finish).
    if (this.barks.length > 0 && this.barks.some((b) => b <= t)) {
      this.barks = this.barks.filter((b) => b > t);
      this.bark(t, 0.2);
    }

    // A ball or treat left lying around fades away after a while.
    if (this.ballRestAt && t - this.ballRestSince > this.ballLingers + FADE) this.ballRestAt = null;
    if (this.treatLeft && t - this.treatLeftSince > 8 + FADE) this.treatLeft = null;

    // Her own life: a trot round now and then, a nap when nobody's been by for a while.
    const free = !this.busy && !this.dashing && !this.grab && !this.press && a.begAmount(t) === 0;
    if (free && a.state === "idle" && t - this.lastInteraction > 75) {
      a.setState("sleeping", t);
    } else if (free && a.state === "idle" && this.opts.wander && !a.reduceMotion && t >= this.nextWander) {
      this.wander(t);
    }

    this.carriedLift += ((this.grab?.carrying ? 1 : 0) - this.carriedLift) * 0.25;
  }

  private scheduleWander(t: number, first = false): void {
    this.nextWander = t + (first ? 4 + Math.random() * 3 : 7 + Math.random() * 8);
  }

  private wander(t: number): void {
    this.scheduleWander(t);
    if (Math.random() < 0.18) {
      this.startTrick(Math.random() < 0.6 ? "spin" : "bow", t);
      return;
    }
    const b = this.bounds;
    const maxStep = Math.min(320, Math.max(90, (b.maxX - b.minX) * 0.6));
    for (let i = 0; i < 8; i++) {
      const angle = Math.random() * Math.PI * 2;
      const d = 70 + Math.random() * (maxStep - 70);
      const target = add(this.paws, { x: Math.cos(angle) * d, y: Math.sin(angle) * d * 0.6 });
      const clamped = this.clampToStage(target);
      if (dist(clamped, this.paws) > 60) {
        // A relaxed trot, not a sprint.
        this.call(clamped, t, 380 + Math.random() * 160);
        return;
      }
    }
  }

  /** Seconds until the next frame is worth drawing. */
  frameDelay(t: number): number {
    const fast = 1 / 60;
    if (this.grab || this.press || this.bubble || this.ripple || this.barks.length > 0) return fast;
    if (this.ballRestAt && t > this.ballRestSince + this.ballLingers - 0.05) return fast;
    if (this.treatLeft && t > this.treatLeftSince + 8 - 0.05) return fast;
    if (this.tool !== "come" && this.pointer) return fast;
    const interval = this.animator.frameInterval(t) ?? 1 / 10;
    const untilWander = this.opts.wander ? Math.max(fast, this.nextWander - t) : Infinity;
    return Math.min(interval, untilWander);
  }

  // MARK: - Drawing

  draw(ctx: CanvasRenderingContext2D, t: number): void {
    ctx.clearRect(0, 0, this.width, this.height);
    const a = this.animator;
    const pose = a.pose(t);
    const scale = this.scale;

    // What's on the floor besides her, with its floor position (world).
    type Item = { y: number; draw: () => void };
    const items: Item[] = [];
    const cssY = (worldY: number) => this.height - worldY;

    const fetch = a.fetch;
    let ball: Loose | null = null;
    if (fetch) ball = fetch.looseBall(t);
    else if (this.ballRestAt) ball = { ground: this.ballRestAt, height: 0, spin: this.ballRestSpin };
    const faded = (since: number, lingers: number) => 1 - ease((t - since - lingers) / FADE);
    if (ball) {
      const b = ball;
      const alpha = fetch ? 1 : faded(this.ballRestSince, this.ballLingers);
      items.push({ y: b.ground.y, draw: () => withAlpha(ctx, alpha, () => drawBall(ctx, b.ground.x, cssY(b.ground.y), b.height, b.spin, scale)) });
    }
    const treat = a.treat ? a.treat.looseTreat(t) : this.treatLeft;
    if (treat) {
      const tr = treat;
      const alpha = a.treat ? 1 : faded(this.treatLeftSince, 8);
      items.push({ y: tr.ground.y, draw: () => withAlpha(ctx, alpha, () => drawTreat(ctx, tr.ground.x, cssY(tr.ground.y), tr.height, tr.spin, scale)) });
    }
    items.push({ y: this.paws.y, draw: () => this.drawCoco(ctx, pose) });
    // Far first: larger y is farther up the floor.
    items.sort((p, q) => q.y - p.y);

    this.drawRipple(ctx, t);
    for (const item of items) item.draw();
    this.drawGhost(ctx, t);
    this.drawBubble(ctx, pose, t);
  }

  private drawCoco(ctx: CanvasRenderingContext2D, pose: ReturnType<Animator["pose"]>): void {
    const a = this.opts.artSize;
    const s = a / 100;
    const lift = this.carriedLift * a * 0.08;
    const x = this.paws.x;
    const y = this.height - this.paws.y - lift;
    ctx.save();
    ctx.translate(x - 50 * s, y - 93 * s);
    ctx.scale(s, s);
    const run = clamp(pose.run, 0, 1);
    this.lastRun = run;
    drawSitting(ctx, pose, 1 - run);
    if (run > 0.001) this.runner.draw(ctx, pose, run);
    drawOverlays(ctx, pose);
    ctx.restore();
  }

  private drawRipple(ctx: CanvasRenderingContext2D, t: number): void {
    const r = this.ripple;
    if (!r) return;
    const k = (t - r.start) / 0.7;
    if (k >= 1) {
      this.ripple = null;
      return;
    }
    const x = r.at.x;
    const y = this.height - r.at.y;
    const grow = ease(k);
    ctx.save();
    ctx.globalAlpha = 0.5 * (1 - k);
    ctx.strokeStyle = r.color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.ellipse(x, y, 10 + 18 * grow, (10 + 18 * grow) * 0.42, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  /** The ball or treat in your hand, following the pointer while that tool is out. */
  private drawGhost(ctx: CanvasRenderingContext2D, t: number): void {
    if (this.tool === "come" || !this.pointer || this.grab || this.pointerType !== "mouse") return;
    if (this.tool === "ball" && (this.animator.fetch || this.ballRestAt)) return;
    if (this.tool === "treat" && this.animator.treat) return;
    const p = this.pointer;
    if (this.hits(p)) return;
    ctx.save();
    ctx.globalAlpha = 0.85;
    const bob = Math.sin(t * 6) * 1.5;
    if (this.tool === "ball") drawBall(ctx, p.x, this.height - p.y + 8, 0 + bob + 8, 0, this.scale);
    else drawTreat(ctx, p.x, this.height - p.y + 8, bob + 8, -0.3, this.scale);
    ctx.restore();
  }

  private drawBubble(ctx: CanvasRenderingContext2D, pose: ReturnType<Animator["pose"]>, t: number): void {
    const b = this.bubble;
    if (!b) return;
    const k = (t - b.start) / 0.9;
    if (k >= 1) {
      this.bubble = null;
      return;
    }
    const a = this.opts.artSize;
    const pop = k < 0.15 ? ease(k / 0.15) : 1;
    const fade = 1 - ease((k - 0.7) / 0.3);
    const x = this.paws.x + a * 0.38;
    const y = this.height - this.paws.y - a * (1.0 + 0.04 * pose.lift / 10) - this.carriedLift * a * 0.08 - 6 * k;
    const size = Math.max(11, Math.round(a * 0.13));
    ctx.save();
    ctx.font = `700 ${size}px ui-rounded, "SF Pro Rounded", system-ui, -apple-system, "Segoe UI", sans-serif`;
    const w = ctx.measureText(b.text).width + size * 1.1;
    const h = size * 1.75;
    // Kept on the stage, even when she's right at the top or the side.
    const bx = Math.min(this.width - w / 2 - 6, Math.max(w / 2 + 6, x));
    const by = Math.max(h / 2 + 6, y);
    ctx.globalAlpha = fade;
    ctx.translate(bx, by);
    ctx.scale(0.6 + 0.4 * pop, 0.6 + 0.4 * pop);
    ctx.fillStyle = "#FFFFFF";
    ctx.strokeStyle = "rgba(34,29,27,0.14)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    const r = h / 2;
    ctx.moveTo(-w / 2 + r, -h / 2);
    ctx.lineTo(w / 2 - r, -h / 2);
    ctx.arc(w / 2 - r, 0, r, -Math.PI / 2, Math.PI / 2);
    ctx.lineTo(-w / 2 + r + 6, h / 2);
    ctx.lineTo(-w / 2 + r - 2, h / 2 + 6);
    ctx.lineTo(-w / 2 + r, h / 2);
    ctx.arc(-w / 2 + r, 0, r, Math.PI / 2, (3 * Math.PI) / 2);
    ctx.closePath();
    ctx.shadowColor = "rgba(0,0,0,0.12)";
    ctx.shadowBlur = 6;
    ctx.shadowOffsetY = 2;
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.stroke();
    ctx.fillStyle = Palette.fur;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(b.text, 0, 1);
    ctx.restore();
  }
}

function withAlpha(ctx: CanvasRenderingContext2D, alpha: number, draw: () => void): void {
  if (alpha <= 0.001) return;
  ctx.save();
  ctx.globalAlpha *= alpha;
  draw();
  ctx.restore();
}
