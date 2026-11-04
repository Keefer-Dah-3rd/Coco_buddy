import { useEffect, useRef, useState, type CSSProperties } from "react";
import { CocoEngine, type Tool } from "./coco/engine";
import { BarkPlayer } from "./coco/sounds";
import { STYLES } from "./styles";

export interface CocoPlaygroundProps {
  /** Stage height: a number of pixels or any CSS length (default 460). */
  height?: number | string;
  /** Coco's size in pixels at most; she shrinks a little on narrow screens (default 120). */
  size?: number;
  /** Stage background: any CSS color or "transparent" (default a warm floor). */
  background?: string;
  /** Trots around and does a trick now and then when nobody's playing (default true). */
  wander?: boolean;
  /** Barks out loud once the visitor has clicked or tapped (default true). */
  sound?: boolean;
  /** Show the toolbar (default true). */
  toolbar?: boolean;
  /** Corner radius of the stage in pixels (default 20). */
  radius?: number;
  className?: string;
  style?: CSSProperties;
}

const HINTS: Record<Tool, { mouse: string; touch: string }> = {
  come: { mouse: "Click anywhere to call Coco · drag her to carry her", touch: "Tap anywhere to call Coco · drag her to carry her" },
  ball: { mouse: "Click where you want to throw the ball", touch: "Tap where you want to throw the ball" },
  treat: { mouse: "She’s begging — click to toss the treat", touch: "Hold to show her the treat, let go to toss it" },
};

const now = () => performance.now() / 1000;

/**
 * Coco the corgi on a web page: call her over, carry her, throw her ball, toss her a treat,
 * ask for a trick or a bark. Her art and motion are ported from the Desktop Buddy Mac app.
 */
export function CocoPlayground({
  height = 460,
  size = 120,
  background = "#F3EFE7",
  wander = true,
  sound = true,
  toolbar = true,
  radius = 20,
  className,
  style,
}: CocoPlaygroundProps) {
  const stageRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<CocoEngine | null>(null);
  const barksRef = useRef<BarkPlayer | null>(null);
  const kickRef = useRef<() => void>(() => undefined);
  const [tool, setTool] = useState<Tool>("come");
  const [soundOn, setSoundOn] = useState(sound);
  const [touchy, setTouchy] = useState(
    () => typeof window !== "undefined" && (window.matchMedia?.("(hover: none) and (pointer: coarse)").matches ?? false),
  );

  // The engine, the frame loop and the stage's size.
  useEffect(() => {
    const stage = stageRef.current;
    const canvas = canvasRef.current;
    if (!stage || !canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const barks = new BarkPlayer();
    barksRef.current = barks;
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    const engine = new CocoEngine(
      { artSize: size, wander: wander && !reduce, onBark: () => barks.play(), bottomInset: toolbar ? 58 : 0 },
      now(),
    );
    engine.animator.reduceMotion = reduce;
    engine.sound = soundOn;
    engineRef.current = engine;

    let raf = 0;
    let next = 0;
    let onScreen = true;
    let dpr = 1;

    const draw = (t: number) => {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      engine.draw(ctx, t);
    };
    const frame = () => {
      raf = requestAnimationFrame(frame);
      const t = now();
      engine.update(t);
      if (t + 0.002 < next) return;
      draw(t);
      next = t + engine.frameDelay(t) - 0.004;
    };
    const start = () => {
      if (raf || !onScreen) return;
      next = 0;
      raf = requestAnimationFrame(frame);
    };
    const stop = () => {
      cancelAnimationFrame(raf);
      raf = 0;
    };
    kickRef.current = () => {
      next = 0;
      start();
    };

    const resize = () => {
      const rect = stage.getBoundingClientRect();
      const w = Math.max(1, Math.round(rect.width));
      const h = Math.max(1, Math.round(rect.height));
      dpr = Math.min(3, window.devicePixelRatio || 1);
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
      canvas.style.width = `${w}px`;
      canvas.style.height = `${h}px`;
      engine.setOptions({ artSize: Math.round(Math.min(size, Math.max(84, w * 0.24))) });
      engine.setSize(w, h);
      next = 0;
      if (onScreen) draw(now());
    };
    resize();
    const resizer = new ResizeObserver(resize);
    resizer.observe(stage);

    // Rest when she's scrolled out of view.
    const watcher = new IntersectionObserver((entries) => {
      onScreen = entries.some((e) => e.isIntersecting);
      if (onScreen) start();
      else stop();
    });
    watcher.observe(stage);

    // On touch screens a swipe over the stage still scrolls the page — except one that starts
    // on Coco (that picks her up).
    const onTouchStart = (event: TouchEvent) => {
      const touch = event.touches[0];
      if (!touch) return;
      const rect = canvas.getBoundingClientRect();
      if (engine.isOnCoco(touch.clientX - rect.left, touch.clientY - rect.top)) event.preventDefault();
    };
    canvas.addEventListener("touchstart", onTouchStart, { passive: false });

    start();
    return () => {
      stop();
      resizer.disconnect();
      watcher.disconnect();
      canvas.removeEventListener("touchstart", onTouchStart);
      barks.dispose();
      engineRef.current = null;
    };
    // The engine lives as long as the component; prop changes are applied below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    engineRef.current?.setOptions({ wander });
  }, [wander]);

  useEffect(() => {
    engineRef.current?.setOptions({ bottomInset: toolbar ? 58 : 0 });
  }, [toolbar]);

  useEffect(() => {
    if (engineRef.current) engineRef.current.sound = soundOn;
  }, [soundOn]);

  const engine = () => engineRef.current;
  const local = (event: { clientX: number; clientY: number }) => {
    const rect = canvasRef.current!.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };
  const wake = () => {
    barksRef.current?.unlock();
    kickRef.current();
  };

  const chooseTool = (next: Tool) => {
    wake();
    setTool(next);
    engine()?.setTool(next, now());
  };

  const bark = () => {
    wake();
    engine()?.bark(now());
  };

  const trick = () => {
    wake();
    engine()?.trick(now());
  };

  const toggleSound = () => {
    barksRef.current?.unlock();
    setSoundOn((on) => !on);
  };

  const onKeyDown = (event: React.KeyboardEvent) => {
    const e = engine();
    if (!e) return;
    const t = now();
    const moves: Record<string, [number, number]> = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, 1], ArrowDown: [0, -1] };
    const move = moves[event.key];
    if (move) {
      e.nudge(move[0], move[1], t);
    } else if (event.key === "b" || event.key === "B") {
      e.bark(t);
    } else if (event.key === "t" || event.key === "T") {
      e.trick(t);
    } else if (event.key === "f" || event.key === "F") {
      e.throwToward("ball", t);
    } else if (event.key === "s" || event.key === "S") {
      e.throwToward("treat", t);
    } else {
      return;
    }
    event.preventDefault();
    wake();
  };

  const stageStyle = {
    height: typeof height === "number" ? `${height}px` : height,
    background,
    borderRadius: radius,
    "--coco-hint": isDark(background) ? "rgba(244, 240, 232, 0.62)" : "rgba(34, 29, 27, 0.55)",
    ...style,
  } as CSSProperties;

  return (
    <div className={`coco-root${className ? ` ${className}` : ""}`} style={stageStyle} ref={stageRef}>
      <style>{STYLES}</style>
      <canvas
        ref={canvasRef}
        className={`coco-canvas coco-tool-${tool}`}
        tabIndex={0}
        role="img"
        aria-label="Coco, a black-and-white corgi. Click to call her, drag to carry her. Keys: arrows move her, B barks, T does a trick, F throws her ball, S tosses a treat."
        onPointerDown={(event) => {
          if (event.button !== 0 && event.pointerType === "mouse") return;
          wake();
          if (event.pointerType !== "mouse") setTouchy(true);
          const p = local(event);
          if (engine()?.pointerDown(p.x, p.y, event.pointerId, event.pointerType, now())) {
            event.currentTarget.setPointerCapture?.(event.pointerId);
          }
        }}
        onPointerMove={(event) => {
          const p = local(event);
          engine()?.pointerMove(p.x, p.y, event.pointerId, event.pointerType, now());
          if (event.pointerType === "mouse") kickRef.current();
        }}
        onPointerUp={(event) => {
          const p = local(event);
          engine()?.pointerUp(p.x, p.y, event.pointerId, now());
          kickRef.current();
        }}
        onPointerCancel={(event) => engine()?.pointerCancel(event.pointerId, now())}
        onPointerLeave={(event) => {
          if (event.pointerType === "mouse") engine()?.pointerLeave(now());
        }}
        onKeyDown={onKeyDown}
      />
      <div className="coco-hint" aria-live="polite">
        {touchy ? HINTS[tool].touch : HINTS[tool].mouse}
      </div>
      {toolbar && (
        <div className="coco-toolbar" role="toolbar" aria-label="Play with Coco">
          <div className="coco-segment" role="radiogroup" aria-label="What’s in your hand">
            <ToolButton current={tool} value="come" label="Come" onChoose={chooseTool} icon={<PawIcon />} />
            <ToolButton current={tool} value="ball" label="Ball" onChoose={chooseTool} icon={<BallIcon />} />
            <ToolButton current={tool} value="treat" label="Treat" onChoose={chooseTool} icon={<BoneIcon />} />
          </div>
          <span className="coco-divider" aria-hidden="true" />
          <button type="button" className="coco-button" onClick={bark} title="Bark (B)">
            <BarkIcon />
            <span className="coco-label">Bark</span>
          </button>
          <button type="button" className="coco-button" onClick={trick} title="Do a trick (T)">
            <SparkleIcon />
            <span className="coco-label">Trick</span>
          </button>
          <button
            type="button"
            className="coco-button coco-icon-only"
            onClick={toggleSound}
            aria-pressed={soundOn}
            aria-label={soundOn ? "Sound on" : "Sound off"}
            title={soundOn ? "Sound on" : "Sound off"}
          >
            {soundOn ? <SoundOnIcon /> : <SoundOffIcon />}
          </button>
        </div>
      )}
    </div>
  );
}

function ToolButton(props: { current: Tool; value: Tool; label: string; icon: JSX.Element; onChoose: (tool: Tool) => void }) {
  const selected = props.current === props.value;
  return (
    <button
      type="button"
      role="radio"
      aria-checked={selected}
      className={`coco-button coco-seg${selected ? " coco-selected" : ""}`}
      onClick={() => props.onChoose(props.value)}
    >
      {props.icon}
      <span className="coco-label">{props.label}</span>
    </button>
  );
}

/** Whether a CSS color is dark enough to need light text on it (hex and rgb() only). */
function isDark(color: string): boolean {
  let r: number, g: number, b: number;
  const hex = color.trim().match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
  const rgb = color.trim().match(/^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/i);
  if (hex) {
    const h = hex[1].length === 3 ? hex[1].replace(/./g, "$&$&") : hex[1];
    r = parseInt(h.slice(0, 2), 16);
    g = parseInt(h.slice(2, 4), 16);
    b = parseInt(h.slice(4, 6), 16);
  } else if (rgb) {
    [r, g, b] = [Number(rgb[1]), Number(rgb[2]), Number(rgb[3])];
  } else {
    return false;
  }
  return 0.2126 * r + 0.7152 * g + 0.0722 * b < 128;
}

// MARK: - Icons (drawn to match Coco's palette; 20 × 20)

const iconProps = { width: 18, height: 18, viewBox: "0 0 20 20", "aria-hidden": true, focusable: false } as const;

function PawIcon() {
  return (
    <svg {...iconProps}>
      <g fill="currentColor">
        <ellipse cx="10" cy="13.2" rx="4.2" ry="3.6" />
        <ellipse cx="4.6" cy="8.6" rx="1.8" ry="2.3" />
        <ellipse cx="8" cy="5.4" rx="1.8" ry="2.4" />
        <ellipse cx="12" cy="5.4" rx="1.8" ry="2.4" />
        <ellipse cx="15.4" cy="8.6" rx="1.8" ry="2.3" />
      </g>
    </svg>
  );
}

function BallIcon() {
  return (
    <svg {...iconProps}>
      <circle cx="10" cy="10" r="7.2" fill="#D7E83C" stroke="#8A9A1E" strokeWidth="1.2" />
      <path d="M5.4 4.6c3 3 3 7.8 0 10.8M14.6 4.6c-3 3-3 7.8 0 10.8" fill="none" stroke="#F7F8EC" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function BoneIcon() {
  return (
    <svg {...iconProps}>
      <g transform="rotate(-30 10 10)" fill="#C9813F" stroke="#7D4A22" strokeWidth="1.1" strokeLinejoin="round">
        <path d="M6 8.2h8a2.3 2.3 0 1 1 1.6 3.2 2.3 2.3 0 1 1-1.6 1.6H6a2.3 2.3 0 1 1-1.6-1.6A2.3 2.3 0 1 1 6 8.2z" />
      </g>
    </svg>
  );
}

function BarkIcon() {
  return (
    <svg {...iconProps}>
      <path
        d="M4 4.5h12a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5H9l-3.6 3v-3H4A1.5 1.5 0 0 1 2.5 12V6A1.5 1.5 0 0 1 4 4.5z"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <path d="M7 9h.01M10 9h.01M13 9h.01" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
    </svg>
  );
}

function SparkleIcon() {
  return (
    <svg {...iconProps}>
      <path d="M9 2.5l1.6 4.4L15 8.5l-4.4 1.6L9 14.5l-1.6-4.4L3 8.5l4.4-1.6z" fill="#FF5A1F" />
      <path d="M15.2 12.6l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z" fill="currentColor" />
    </svg>
  );
}

function SoundOnIcon() {
  return (
    <svg {...iconProps}>
      <path d="M3.5 7.5h2.8L10 4.4v11.2l-3.7-3.1H3.5z" fill="currentColor" />
      <path d="M13 7.2a4 4 0 0 1 0 5.6M15.2 5a7 7 0 0 1 0 10" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

function SoundOffIcon() {
  return (
    <svg {...iconProps}>
      <path d="M3.5 7.5h2.8L10 4.4v11.2l-3.7-3.1H3.5z" fill="currentColor" />
      <path d="M13 7.5l4.5 5M17.5 7.5l-4.5 5" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

export default CocoPlayground;
