// components.jsx — shared atoms for the Compost notch prototype

const { useState, useEffect, useRef, useMemo } = React;

/* ---------- Mascot ---------- */

const MASCOT_SRC = {
  calm:    "assets/mascot-calm.png",
  nudging: "assets/mascot-nudging.png",
  alert:   "assets/mascot-alert.png",
  sweep:   "assets/mascot-sweep.png",
  base:    "assets/mascot-base.png",
};

function Mascot({ mood = "calm", size = 56, bobble = false, className = "" }) {
  const src = MASCOT_SRC[mood] || MASCOT_SRC.calm;
  return (
    <span
      className={`mascot ${bobble ? "bobble" : ""} ${className}`}
      style={{ width: size, height: size }}
    >
      <img src={src} alt="" draggable={false} />
    </span>
  );
}

function MascotMini({ mood = "calm" }) {
  return (
    <span className="mascot-mini">
      <img src={MASCOT_SRC[mood] || MASCOT_SRC.calm} alt="" draggable={false} />
    </span>
  );
}

/* ---------- Tags & button helpers ---------- */

function Tag({ tone = "default", children }) {
  return <span className={`tag ${tone}`}>{children}</span>;
}

function Btn({ kind = "ghost", onClick, icon, children, disabled }) {
  return (
    <button className={`btn ${kind}`} onClick={onClick} disabled={disabled}>
      {icon ? <span>{icon}</span> : null}
      {children}
    </button>
  );
}

/* ---------- Notch shell ---------- */

function Notch({ size = "idle", style = "glossy", children, onClick }) {
  return (
    <div className="notch-wrap">
      <div
        className={`notch size-${size} style-${style}`}
        onClick={onClick}
        role={onClick ? "button" : undefined}
      >
        <span className="camera-dot" />
        <div className="notch-content">{children}</div>
      </div>
    </div>
  );
}

/* ---------- Waveform ---------- */

function Waveform({ active = true, count = 32, color }) {
  const [tick, setTick] = useState(0);
  useEffect(() => {
    if (!active) return;
    let raf;
    const loop = () => {
      setTick(t => t + 1);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [active]);

  // pre-compute pseudo-random per-bar phases for natural variation
  const phases = useMemo(
    () => Array.from({ length: count }, (_, i) => Math.random() * Math.PI * 2 + i * 0.3),
    [count]
  );

  return (
    <div className="waveform" aria-hidden="true">
      {phases.map((p, i) => {
        const t = tick / 6;
        // mix two sinusoids; envelope at edges
        const envelope = Math.sin((i / (count - 1)) * Math.PI);
        const v = active
          ? (0.45 + 0.55 * Math.abs(Math.sin(t + p) * 0.7 + Math.sin(t * 1.7 + p * 1.3) * 0.4)) * envelope
          : 0.10 + 0.05 * Math.sin(i * 0.5);
        const h = Math.max(2, v * 22);
        return (
          <span
            key={i}
            className="wave-bar"
            style={{
              height: h,
              background: color || (active ? `rgba(135,168,119,${0.55 + v * 0.45})` : "rgba(244,244,238,0.18)"),
            }}
          />
        );
      })}
    </div>
  );
}

/* ---------- Slide-to-confirm ---------- */

function SlideToConfirm({ label = "Slide to approve", onDone }) {
  const [done, setDone] = useState(false);
  const [progress, setProgress] = useState(0);
  const ref = useRef(null);
  const dragging = useRef(false);
  const startX = useRef(0);

  function down(e) {
    if (done) return;
    dragging.current = true;
    startX.current = (e.touches ? e.touches[0].clientX : e.clientX);
  }
  function move(e) {
    if (!dragging.current || !ref.current) return;
    const w = ref.current.offsetWidth - 40;
    const x = (e.touches ? e.touches[0].clientX : e.clientX) - startX.current;
    const clamped = Math.max(0, Math.min(w, x));
    setProgress(clamped / w);
    if (clamped / w > 0.92) {
      dragging.current = false;
      setDone(true);
      setProgress(1);
      setTimeout(() => onDone && onDone(), 350);
    }
  }
  function up() {
    if (!dragging.current) return;
    dragging.current = false;
    if (progress < 0.92) {
      setProgress(0);
    }
  }

  useEffect(() => {
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
    window.addEventListener("touchmove", move);
    window.addEventListener("touchend", up);
    return () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
      window.removeEventListener("touchmove", move);
      window.removeEventListener("touchend", up);
    };
  });

  return (
    <div
      ref={ref}
      className={`slide-to-pay ${done ? "done" : ""}`}
    >
      <span
        className="slide-fill"
        style={{ width: done ? "100%" : `calc(${progress * 100}% + 40px)` }}
      />
      <span className="slide-track-label">
        {done ? "✓ Paid · Notion updated" : label}
      </span>
      <span
        className="slide-thumb"
        style={{
          transform: done ? "translateX(calc(100% + 100px))" : `translateX(${progress * (ref.current?.offsetWidth - 40 || 0)}px)`,
        }}
        onMouseDown={down}
        onTouchStart={down}
      >
        {done ? "✓" : "→"}
      </span>
    </div>
  );
}

/* expose globally so other babel scripts can use them */
Object.assign(window, {
  Mascot, MascotMini, MASCOT_SRC,
  Tag, Btn,
  Notch, Waveform, SlideToConfirm,
});
