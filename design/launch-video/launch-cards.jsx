// launch-cards.jsx — notch cards, data, motion helpers (pure functions of T)
const { useState: useLvState, useLayoutEffect: useLvLayout, useRef: useLvRef } = React;

/* ---- the only three motion helpers ---- */
const MOTION = {
  enter: (start, dur = 0.5, from = 0, to = 1) => animate({ from, to, start, end: start + dur, ease: Easing.easeOutCubic }),
  draw:  (start, dur = 0.8, from = 0, to = 1) => animate({ from, to, start, end: start + dur, ease: Easing.easeInOutCubic }),
  pop:   (start, dur = 0.7, from = 0, to = 1) => animate({ from, to, start, end: start + dur, ease: Easing.easeOutBack }),
};
// keyframe track: value eases from previous key to this one over `dur` after key.t
function keyed(T, frames, dur = 0.8) {
  let v = frames[0].v;
  for (const f of frames) { if (T < f.t) break; v = v + (f.v - v) * Easing.easeInOutCubic(clamp((T - f.t) / dur, 0, 1)); }
  return v;
}
const typed = (T, text, start, dur) => text.slice(0, Math.floor(clamp((T - start) / dur, 0, 1) * text.length));
const bob = (T, at) => { const p = clamp((T - at) / 0.7, 0, 1); return p >= 1 || p <= 0 ? 1 : 1 + 0.08 * Math.sin(p * Math.PI) * (1 - p); };

const M = { calm: "assets/mascot-calm.png", nudging: "assets/mascot-nudging.png", alert: "assets/mascot-alert.png" };
const Mascot = ({ mood, size, scale = 1 }) => <img src={M[mood]} alt="" style={{ width: size, height: size, objectFit: "contain", flexShrink: 0, transform: `scale(${scale})` }} />;
const Gmail = ({ s = 14 }) => <svg width={s} height={s} viewBox="0 0 24 24"><path fill="#4285F4" d="M2 6.2v11.6c0 .7.5 1.2 1.2 1.2h2.6V11L2 6.2z"/><path fill="#34A853" d="M18.2 19h2.6c.7 0 1.2-.5 1.2-1.2V6.2L18.2 11v8z"/><path fill="#FBBC04" d="M18.2 6.2V11l3.8-2.85V6.7c0-1.36-1.55-2.14-2.64-1.33l-1.16.83z"/><path fill="#EA4335" d="M5.8 11V6.2L12 10.8l6.2-4.6V11L12 15.6 5.8 11z"/><path fill="#C5221F" d="M2 6.7v1.45L5.8 11V6.2L4.64 5.37C3.55 4.56 2 5.34 2 6.7z"/></svg>;
const Check = () => <svg viewBox="0 0 12 12" width="10" height="10"><path d="M2 6.2L5 9L10 3" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>;

/* ---- data ---- */
const DRAFT = { original: "We need this WRAPPED by Friday or the whole launch FALLS APART. I'm not going to keep chasing you — just GET it done.", rewrites: { Calmer: "We're aiming to wrap this by Friday so the launch holds. Could you share where things stand and what would help you finish?", Crisp: "Need this complete by Friday for the launch. What's blocking you, and how can I help?", Diplomatic: "Friday is our launch checkpoint and we'd love to land this by then. Want to find a 15-minute window to align on what's left?" } };
const PHOTOS = [
  { src: "assets/photo-soma-1.jpeg", cap: "Salesforce Tower from 2nd St", place: "SoMa, San Francisco", time: "yesterday · 2:32 PM" },
  { src: "assets/photo-soma-2.jpeg", cap: "Looking up the Salesforce spire", place: "Mission & 2nd", time: "yesterday · 2:41 PM" },
  { src: "assets/photo-dustbin.jpeg", pos: "50% 72%", cap: "saw your logo on a bin at Pier 9 ☺", place: "Pier 9 cafeteria", time: "yesterday · 2:58 PM", bubble: "yes — that's me! the bin at Pier 9. logged it." },
  { src: "assets/photo-poster-hermanmiller.jpeg", cap: "\u201CThings Are Getting Better All The Time\u201D — Herman Miller, 1980", place: "MoMA gift shop", time: "yesterday · 3:08 PM" },
];
const USER_Q = "hey compost, what's on the pile this morning…";
const REPLY = "Three things. Maya's checkpoint in twelve minutes. Two drafts you wrote at 2 AM. And four photos from yesterday's walk in Memory.";

/* ---- cards (all pure functions of T) ---- */
function CueCard({ T, C }) {
  const c3 = T >= C + 3.25, c4 = T >= C + 4.65, all = c3 && c4;
  const items = [["Skim last week's notes", true, "a"], ["Pull the Figma file", true, "b"], ["Decide on top 2 questions", c3, "c"], ["Open the Loom from yesterday", c4, "d"]];
  return (
    <div className="card" style={{ width: 440, height: 320, opacity: MOTION.enter(C + 0.5, 0.4)(T) * (1 - MOTION.enter(C + 7.7, 0.3)(T)) }}>
      <div className="head"><Mascot mood={all ? "alert" : "calm"} size={36} scale={bob(T, C + 4.7)} /><div className="tx"><span className="eyebrow">☀️ Up next · 10:30 AM</span><h3 className="title">App shell checkpoint</h3></div><span className="x">✕</span></div>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}><div className="time">10:30<small>AM</small></div><div className="cd">in 12 min · 25 min</div></div>
      <div data-t="gmail-row" className="row"><Gmail s={16} /><div style={{ flex: 1 }}><div style={{ fontSize: 11.5, fontWeight: 600 }}>From Calendar via Gmail</div><div className="ink3" style={{ fontSize: 11 }}>Maya Chen &amp; Theo Park · accepted</div></div><span className="btn g" style={{ fontSize: 11, padding: "4px 8px" }}>Join Meet</span></div>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>{items.map(([l, on, k]) => <div key={k} className={`check ${on ? "on" : ""}`}><i data-t={`check-${k}`} className="box" style={{ transform: `scale(${bob(T, k === "c" ? C + 3.25 : C + 4.65)})` }}>{on && <Check />}</i><span>{l}</span></div>)}</div>
      <div style={{ display: "flex", gap: 6, alignItems: "center" }}><span className="btn p">↗ Open in Notion</span><span className="btn g">Snooze 5m</span><span className="ink3" style={{ marginLeft: "auto", fontSize: 11 }}>[!cue] · agenda.md</span></div>
    </div>
  );
}

function DraftsCard({ T, C }) {
  const tone = T < C + 2.75 ? "Calmer" : T < C + 5.15 ? "Crisp" : "Diplomatic";
  const swapAt = tone === "Crisp" ? C + 2.75 : tone === "Diplomatic" ? C + 5.15 : C;
  const calm = DRAFT.rewrites[tone];
  const orig = new Set(DRAFT.original.toLowerCase().split(/\W+/));
  return (
    <div className="card" style={{ width: 540, height: 360, opacity: MOTION.enter(C, 0.4)(T) * (1 - MOTION.enter(C + 7.7, 0.3)(T)) }}>
      <div className="head"><Mascot mood="nudging" size={36} /><div className="tx"><span className="eyebrow">🌙 Sleep-on-it · 3 frozen</span><h3 className="title">Morning review</h3></div><span className="x">✕</span></div>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        <div className="drow on"><b>Re: Q2 contractor scope</b><span className="tag s">frozen</span><span className="meta">1:47 AM</span></div>
        <div className="drow"><b>Hackathon retro thoughts</b><span className="tag">frozen</span><span className="meta">2:14 AM</span></div>
      </div>
      <div className="diff">
        <div className="col"><div className="lb"><span>Original · 1:47 AM you</span><span style={{ opacity: .6 }}>raw</span></div>{DRAFT.original.split(/(\s+)/).map((w, i) => /^[A-Z]{3,}$/.test(w) ? <span key={i} className="shout">{w}</span> : w)}</div>
        <div className="col c" style={{ opacity: MOTION.enter(swapAt, 0.35, 0.25, 1)(T) }}><div className="lb"><span>{tone} rewrite</span><span style={{ opacity: .6 }}>Haiku</span></div>{calm.split(/(\s+)/).map((w, i) => { const s = w.replace(/[.,;!?—]/g, "").toLowerCase(); return s.length > 3 && !orig.has(s) ? <span key={i} className="add">{w}</span> : w; })}</div>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11 }}><span className="ink3">Tone</span>{["Calmer", "Crisp", "Diplomatic"].map(t => <span key={t} data-t={`tone-${t}`} className={`pill ${tone === t ? "on" : ""}`}>{t}</span>)}<span style={{ marginLeft: "auto", display: "flex", gap: 6 }}><span className="btn g">Keep mine</span><span className="btn p">✓ Use {tone.toLowerCase()}</span></span></div>
    </div>
  );
}

function VoiceCard({ T, C }) {
  const t = T - C;
  const stage = t < 3.6 ? "listening" : t < 4.6 ? "thinking" : t < 7.4 ? "speaking" : "idle";
  const text = stage === "listening" ? typed(T, USER_Q, C + 0.8, 2.6) : stage === "thinking" ? "" : typed(T, REPLY, C + 4.6, 2.7);
  const col = { listening: "#d77a6b", thinking: "#f0a444", speaking: "#87a877", idle: "#87a877" }[stage];
  const label = { listening: "Listening", thinking: "Thinking", speaking: "Compost", idle: "Compost · finished" }[stage];
  const active = stage !== "idle";
  return (
    <div className="card" style={{ width: 440, height: 210, opacity: MOTION.enter(C, 0.4)(T) * (1 - MOTION.enter(C + 7.7, 0.3)(T)) }}>
      <div style={{ display: "flex", gap: 12, alignItems: "center", flex: 1 }}>
        <div style={{ position: "relative", width: 88, height: 88, flexShrink: 0 }}><div className="halo" style={{ transform: `scale(${1 + 0.06 * Math.sin(T * 2.4)})`, opacity: .6 + .4 * Math.sin(T * 2.4) }} /><Mascot mood={stage === "speaking" ? "nudging" : "calm"} size={88} scale={bob(T, C + 4.6)} /></div>
        <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 8 }}>
          <span data-t="voice-state" className="state"><i style={{ background: col, opacity: .5 + .5 * Math.abs(Math.sin(T * 3.2)) }} />{label}</span>
          <div className="tr">{stage === "thinking" ? <span className="ink3" style={{ fontStyle: "italic" }}>checking the pile…</span> : <>{text}{active && Math.floor(T * 2) % 2 === 0 && <span className="caret" />}</>}</div>
          <div className="wave">{Array.from({ length: 42 }, (_, i) => { const env = Math.sin(i / 41 * Math.PI); const v = active ? (0.35 + 0.65 * Math.abs(Math.sin(T * 7 + i * 0.7) * 0.7 + Math.sin(T * 11.3 + i * 0.4) * 0.4)) * env : 0.1; return <i key={i} style={{ height: Math.max(2, v * 22), background: col, opacity: .55 + v * .45 }} />; })}</div>
          <div style={{ display: "flex", gap: 6 }}>{["What did I miss?", "Read drafts", "Show photos"].map(l => <span key={l} className="btn g" style={{ fontSize: 11, padding: "5px 9px" }}>{l}</span>)}</div>
        </div>
      </div>
    </div>
  );
}

function PhotosCard({ T, C }) {
  const starts = [0, 2.2, 4.4, 7.4];
  let idx = 0; starts.forEach((s, i) => { if (T - C >= s) idx = i; });
  const p = PHOTOS[idx];
  return (
    <div className="card" style={{ width: 540, height: 420, opacity: MOTION.enter(C, 0.4)(T) * (1 - MOTION.enter(C + 9.35, 0.25)(T)) }}>
      <div className="head"><Mascot mood={p.bubble ? "alert" : "calm"} size={36} scale={bob(T, C + 4.6)} /><div className="tx"><span className="eyebrow">📷 Memory pile · 4 from yesterday</span><h3 className="title">{p.place}</h3></div><span className="x">✕</span></div>
      <div className="photo">
        {PHOTOS.map((ph, i) => <img key={i} src={ph.src} alt="" style={{ objectPosition: ph.pos || "50% 50%", opacity: i === 0 ? 1 : MOTION.enter(C + starts[i], 0.45)(T), transform: `scale(${1 + 0.012 * ((T - C - starts[i]) )})` }} />)}
        <span className="arrow" style={{ left: 8 }}>‹</span><span data-t="photo-next" className="arrow" style={{ right: 8 }}>›</span>
        <div className="cap"><b>{p.cap}</b><span>📍 {p.place} · 🕒 {p.time}</span></div>
        {p.bubble && <div data-t="photo-bubble" className="bubble" style={{ opacity: MOTION.enter(C + 4.9, 0.4)(T), transform: `translateY(${(1 - MOTION.pop(C + 4.9, 0.6)(T)) * -8}px)` }}><span style={{ fontSize: 14 }}>🌱</span><span>{p.bubble}</span></div>}
      </div>
      <div className="dots">{PHOTOS.map((ph, i) => <i key={i} style={{ width: i === idx ? 18 : 6, background: i === idx ? "#87a877" : ph.bubble ? "rgba(201,168,90,.5)" : "rgba(255,255,255,.2)" }} />)}</div>
      <div style={{ display: "flex", gap: 6, alignItems: "center" }}><span className="btn p">↗ Open in Notion</span><span className="btn g">+ Tag</span><span className="btn g">Ask about this ↗</span><span style={{ marginLeft: "auto", display: "flex", gap: 4 }}>{(p.bubble ? ["compost-sighting", "lol"] : ["walk"]).map(t => <span key={t} className={`tag ${t === "compost-sighting" ? "s" : ""}`}>#{t}</span>)}</span></div>
    </div>
  );
}


Object.assign(window, { MOTION, keyed, typed, bob, M, Mascot, Gmail, Check, DRAFT, PHOTOS, CueCard, DraftsCard, VoiceCard, PhotosCard });
