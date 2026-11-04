import bark1 from "../assets/barks/bark-1.wav?inline";
import bark2 from "../assets/barks/bark-2.wav?inline";
import bark3 from "../assets/barks/bark-3.wav?inline";
import bark4 from "../assets/barks/bark-4.wav?inline";

const SOURCES = [bark1, bark2, bark3, bark4];

/**
 * Coco's four single barks (cut from a recording of her), never the same one twice in a row.
 * Browsers only allow sound after the visitor interacts with the page, so audio starts on
 * the first click or tap; until then a bark is silent but her mouth still moves.
 */
export class BarkPlayer {
  private ctx: AudioContext | null = null;
  private buffers: AudioBuffer[] = [];
  private loading: Promise<void> | null = null;
  private last = -1;
  volume = 0.55;

  /** Call from a user gesture (pointerdown, click, keydown). */
  unlock(): void {
    if (typeof window === "undefined") return;
    if (!this.ctx) {
      const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return;
      try {
        this.ctx = new Ctor();
      } catch {
        return;
      }
    }
    if (this.ctx.state === "suspended") void this.ctx.resume().catch(() => undefined);
    if (!this.loading) this.loading = this.load();
  }

  private async load(): Promise<void> {
    const ctx = this.ctx;
    if (!ctx) return;
    const decoded = await Promise.all(
      SOURCES.map(async (src) => {
        try {
          const data = await (await fetch(src)).arrayBuffer();
          return await ctx.decodeAudioData(data);
        } catch {
          return null;
        }
      }),
    );
    this.buffers = decoded.filter((b): b is AudioBuffer => b !== null);
  }

  play(): void {
    const ctx = this.ctx;
    if (!ctx || this.buffers.length === 0 || ctx.state !== "running") return;
    let index = Math.floor(Math.random() * this.buffers.length);
    if (index === this.last && this.buffers.length > 1) index = (index + 1) % this.buffers.length;
    this.last = index;
    const source = ctx.createBufferSource();
    source.buffer = this.buffers[index];
    // A touch of pitch variety so repeated barks don't sound canned.
    source.playbackRate.value = 0.96 + Math.random() * 0.08;
    const gain = ctx.createGain();
    gain.gain.value = this.volume;
    source.connect(gain).connect(ctx.destination);
    source.start();
  }

  dispose(): void {
    void this.ctx?.close().catch(() => undefined);
    this.ctx = null;
    this.buffers = [];
    this.loading = null;
  }
}
