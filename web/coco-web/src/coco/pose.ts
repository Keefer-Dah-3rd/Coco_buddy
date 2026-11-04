/**
 * Every visual parameter the artwork needs, as plain numbers — the contract between
 * animation and art (ported from the Mac app's `CharacterPose`). The animator never draws;
 * the artwork never decides behaviour.
 */
export interface Pose {
  // Body
  lift: number;
  squash: number;
  tilt: number;
  // Head
  headTilt: number;
  headDip: number;
  // Eyes
  eyeOpen: number;
  eyeSmile: number;
  eyeScale: number;
  gazeX: number;
  gazeY: number;
  // Mouth
  mouthOpen: number;
  mouthCurve: number;
  tongue: number;
  // Ears and tail
  earPerk: number;
  earLeft: number;
  earRight: number;
  tail: number;
  // Running
  run: number;
  headingX: number;
  headingY: number;
  stride: number;
  gallop: number;
  bow: number;
  crouch: number;
  bank: number;
  earBack: number;
  reach: number;
  carry: number;
  beg: number;
  // Extras
  led: number;
  dangle: number;
  sleepZ: number;
  sparkles: number;
  clock: number;
}

export function makePose(): Pose {
  return {
    lift: 0,
    squash: 0,
    tilt: 0,
    headTilt: 0,
    headDip: 0,
    eyeOpen: 1,
    eyeSmile: 0,
    eyeScale: 1,
    gazeX: 0,
    gazeY: 0,
    mouthOpen: 0,
    mouthCurve: 0.4,
    tongue: 0,
    earPerk: 0.8,
    earLeft: 0,
    earRight: 0,
    tail: 0,
    run: 0,
    headingX: 0,
    headingY: -1,
    stride: 0,
    gallop: 0,
    bow: 0,
    crouch: 0,
    bank: 0,
    earBack: 0,
    reach: 0,
    carry: 0,
    beg: 0,
    led: 0,
    dangle: 0,
    sleepZ: 0,
    sparkles: 0,
    clock: 0,
  };
}

const STEPPED: ReadonlySet<keyof Pose> = new Set<keyof Pose>(["carry", "clock"]);

/** Any two poses blend linearly (carry and clock snap to the second). */
export function blendPose(a: Pose, b: Pose, t: number): Pose {
  const p = makePose();
  for (const key of Object.keys(p) as (keyof Pose)[]) {
    p[key] = STEPPED.has(key) ? b[key] : a[key] + (b[key] - a[key]) * t;
  }
  return p;
}
