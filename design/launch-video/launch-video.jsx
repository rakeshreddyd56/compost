// launch-video.jsx — Compost launch video · Notion-native stage, Apple chrome
const { useState: useLvState, useLayoutEffect: useLvLayout, useRef: useLvRef } = React;

/* cursor: macOS arrow + click ripple */
function Cursor({ x, y, o, press, ripple }) {
  return (
    <div style={{ position: "absolute", left: x, top: y, opacity: o, pointerEvents: "none" }}>
      <span style={{ position: "absolute", left: -14, top: -14, width: 28, height: 28, borderRadius: "50%", border: "2px solid rgba(135,168,119,.9)", transform: `scale(${0.4 + ripple * 1.6})`, opacity: ripple > 0 && ripple < 1 ? 1 - ripple : 0 }} />
      <svg style={{ width: 20, height: 24, transform: `scale(${press})`, transformOrigin: "3px 2px" }} viewBox="0 0 20 24"><path d="M3 2v17l4.4-4.1 3.2 6.8 2.8-1.3-3.2-6.7 6.3-.3z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round"/></svg>
    </div>
  );
}

/* callout label with a thin leader line, in stage space */
function Callout({ x, y, dx, dy, o, title, sub }) {
  const lx = x + dx, ly = y + dy;
  return (
    <div className="callout" style={{ left: 0, top: 0, opacity: o }}>
      <svg style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, overflow: "visible" }}><line x1={x} y1={y} x2={lx} y2={ly} stroke="#191919" strokeOpacity=".55" strokeWidth="1.5" /><circle cx={x} cy={y} r="4.5" fill="#fffdf8" stroke="#191919" strokeWidth="1.5" /></svg>
      <div className="lbl" style={{ left: lx + (dx < 0 ? -8 : 8), top: ly - 22, transform: dx < 0 ? "translateX(-100%)" : "none" }}>{title}{sub && <small>{sub}</small>}</div>
    </div>
  );
}

function Piece({ tw }) {
  const { T, CUES: K } = useComposition();
  const notchRef = useLvRef(null);
  const [tgt, setTgt] = useLvState({});
  const tgtRef = useLvRef("");
  useLvLayout(() => {
    const n = notchRef.current; if (!n) return;
    const nr = n.getBoundingClientRect(); const k = nr.width / n.offsetWidth || 1;
    const out = {}; n.querySelectorAll("[data-t]").forEach(el => { const r = el.getBoundingClientRect(); out[el.dataset.t] = { x: Math.round((r.left - nr.left) / k), y: Math.round((r.top - nr.top) / k), w: Math.round(r.width / k), h: Math.round(r.height / k) }; });
    const sig = JSON.stringify(out);
    if (sig !== tgtRef.current) { tgtRef.current = sig; setTgt(out); }
  });

  /* notch geometry */
  const L = K.Launch;
  const W = keyed(T, [{ t: 0, v: 220 }, { t: L + 2.4, v: 300 }, { t: K.Cue + 0.6, v: 440 }, { t: K.Drafts, v: 540 }, { t: K.Voice, v: 440 }, { t: K.Memory, v: 540 }, { t: K.Vision, v: 300 }, { t: K.Vision + 3.4, v: 220 }], 0.75);
  const H = keyed(T, [{ t: 0, v: 34 }, { t: L + 2.4, v: 38 }, { t: K.Cue + 0.6, v: 320 }, { t: K.Drafts, v: 360 }, { t: K.Voice, v: 210 }, { t: K.Memory, v: 420 }, { t: K.Vision, v: 38 }, { t: K.Vision + 3.4, v: 34 }], 0.75);
  const R = keyed(T, [{ t: 0, v: 16 }, { t: K.Cue + 0.6, v: 22 }, { t: K.Vision, v: 16 }], 0.75);
  const left = 960 - W / 2;

  /* camera: notch top is the anchor; LAP frames the whole laptop */
  const LAP = { s: 0.66, py: 250 }, FILL = { s: 1, py: 0 }, N = s => ({ s, py: 0 }), OFF = { s: 0.66, py: 1120 };
  const camK = [{ t: 0, v: OFF }, { t: L - 0.9, v: LAP }, { t: L + 1.4, v: FILL }, { t: K.Cue, v: N(2.05) }, { t: K.Drafts, v: N(1.85) }, { t: K.Voice, v: N(2.05) }, { t: K.Memory, v: N(1.8) }, { t: K.Vision, v: FILL }, { t: K.Vision + 1.8, v: LAP }];
  const cam = k => keyed(T, camK.map(f => ({ t: f.t, v: f.v[k] })), 1.4);
  const drift = T >= K.Cue && T < K.Vision ? 1 + 0.008 * Math.sin((T - K.Cue) * 0.9) : 1;
  const S = cam("s") * drift, PY = cam("py");
  const toStage = (nx, ny) => ({ x: 960 + (nx - W / 2) * S, y: PY + ny * S });

  /* cursor */
  const P = (name, ax = 0.5, ay = 0.5) => { const t = tgt[name] || { x: 40, y: 40, w: 0, h: 0 }; return { x: left + t.x + t.w * ax, y: t.y + t.h * ay }; };
  const path = [
    { t: 0, v: { x: 1300, y: 760 } },
    { t: K.Cue + 2.2, v: P("check-c") }, { t: K.Cue + 3.7, v: P("check-d") }, { t: K.Cue + 5.6, v: { x: 1180, y: 400 } },
    { t: K.Drafts + 1.6, v: P("tone-Crisp") }, { t: K.Drafts + 4.0, v: P("tone-Diplomatic") }, { t: K.Drafts + 6.6, v: { x: 1300, y: 480 } },
    { t: K.Memory + 3.3, v: P("photo-next") }, { t: K.Memory + 6.0, v: { x: 1350, y: 560 } },
  ];
  const cx = keyed(T, path.map(f => ({ t: f.t, v: f.v.x })), 0.9), cy = keyed(T, path.map(f => ({ t: f.t, v: f.v.y })), 0.9);
  const clicks = [K.Cue + 3.2, K.Cue + 4.6, K.Drafts + 2.7, K.Drafts + 5.1, K.Memory + 4.35];
  const press = clicks.reduce((s, c) => s * (T > c && T < c + 0.22 ? 0.84 : 1), 1);
  const ripple = clicks.reduce((r, c) => r || (T > c && T < c + 0.6 ? (T - c) / 0.6 : 0), 0);
  const cO = keyed(T, [{ t: 0, v: 0 }, { t: K.Cue + 1.6, v: 1 }, { t: K.Cue + 6.4, v: 0 }, { t: K.Drafts + 0.8, v: 1 }, { t: K.Drafts + 6.8, v: 0 }, { t: K.Memory + 2.4, v: 1 }, { t: K.Memory + 6.6, v: 0 }], 0.4);

  /* focus ring on the active element (notch space) */
  const focusFor = () => {
    if (T > K.Cue + 2.0 && T < K.Cue + 3.5) return "check-c";
    if (T >= K.Cue + 3.5 && T < K.Cue + 5.2) return "check-d";
    if (T > K.Drafts + 1.4 && T < K.Drafts + 3.8) return "tone-Crisp";
    if (T >= K.Drafts + 3.8 && T < K.Drafts + 6.4) return "tone-Diplomatic";
    return null;
  };
  const fk = focusFor(), ft = fk && tgt[fk];
  const focusO = fk ? 0.75 + 0.25 * Math.sin(T * 5) : 0;

  /* callouts (stage space) */
  const co = (a, b) => MOTION.enter(a, 0.45)(T) * (1 - MOTION.enter(b, 0.35)(T));
  const callouts = [];
  if (tw.showCallouts && T > K.Cue && T < K.Vision) {
    const at = (name, ax, ay) => { const t = tgt[name]; if (!t) return null; return toStage(t.x + t.w * ax, t.y + t.h * ay); };
    const g = at("gmail-row", 0, 0.5); if (g) callouts.push({ ...g, dx: -140, dy: -70, o: co(K.Cue + 1.4, K.Cue + 6.2), title: "From Calendar via Gmail", sub: "written by the Notion agent, not by you" });
    const d = at("tone-Diplomatic", 1, 0.5); if (d) callouts.push({ ...d, dx: 130, dy: 90, o: co(K.Drafts + 1.2, K.Drafts + 7), title: "Pick the tone", sub: "rephraseDraft · live Worker call" });
    const v = at("voice-state", 0, 0.5); if (v) callouts.push({ ...v, dx: -150, dy: -90, o: co(K.Voice + 4.8, K.Voice + 7.6), title: "Answers from your workspace", sub: "voiceReply → recallMemory" });
    const m = at("photo-bubble", 0, 1); if (m) callouts.push({ ...m, dx: -170, dy: 80, o: co(K.Memory + 5.4, K.Memory + 8.4), title: "It spotted itself", sub: "a public compost bin at Pier 9" });
  }

  /* intro + launch beats */
  const agentsO = MOTION.enter(0.3, 0.9)(T) * (1 - MOTION.enter(2.6, 0.6)(T));
  const agentsY = (1 - MOTION.enter(0.3, 0.9)(T)) * 30 - MOTION.enter(2.6, 0.6)(T) * 60;
  const meetO = MOTION.enter(3.0, 0.8)(T) * (1 - MOTION.enter(L - 0.3, 0.6)(T));
  const meetY = (1 - MOTION.enter(3.0, 0.8)(T)) * 24 - MOTION.enter(L - 0.3, 0.6)(T) * 40;
  const screenOn = MOTION.enter(L + 0.9, 0.9)(T);
  const dockBounce = T > L + 1.6 && T < L + 3.0 ? Math.abs(Math.sin(clamp(T - L - 1.6, 0, 1.4) * Math.PI * 2)) * 22 * (1 - clamp((T - L - 1.6) / 1.4, 0, 1)) : 0;
  const visionO = MOTION.enter(K.Vision + 1.6, 0.9)(T);
  const peekText = T < L + 3.4 ? "Compost is waking up…" : "App shell checkpoint";

  return (
    <div className="lv" data-screen-label={`t=${T.toFixed(1)}s`}>
      <div className="paper" />
      {/* Intro */}
      <div className="agents" style={{ opacity: agentsO, transform: `translateY(${-300 + agentsY}px)` }}><img src="assets/notion-agents.png" alt="" /></div>
      <div className="hero" style={{ top: 360, opacity: meetO, transform: `translateY(${meetY}px)` }}><p className="kicker">Built on Notion 3.0 Agents + Workers</p><h1>Meet <span className="u">Compost<svg viewBox="0 0 200 14" preserveAspectRatio="none"><path d="M2 9c40-6 80-6 120-3s50 2 76-2" fill="none" stroke="#4f7942" strokeWidth="5" strokeLinecap="round" strokeDasharray="220" strokeDashoffset={220 * (1 - MOTION.draw(3.6, 0.8)(T))} /></svg></span>.</h1><p>Your Notion, with a sense of time — living in the Mac notch.</p></div>
      {/* Vision */}
      <div className="hero" style={{ top: 78, opacity: visionO, transform: `translateY(${(1 - visionO) * 14}px)` }}><h1 style={{ fontSize: 62 }}>A calm Notion copilot.</h1><p style={{ marginTop: 10, fontSize: 24 }}>Compost · built on Notion 3.0 Agents + Workers</p></div>

      {/* Laptop + desktop */}
      <div className="camroot" style={{ transform: `translate(${960 - 960 * S}px, ${PY}px) scale(${S})` }}>
        <div className="bezel" /><div className="body"><span>MacBook Air</span></div>
        <div className="desk">
          <div style={{ position: "absolute", inset: 0, opacity: screenOn }}>
            <Wallpaper kind={tw.wallpaper} T={T} />
            <MenuBar active="Finder" />
            <Dock bounce={dockBounce} />
          </div>
          <div ref={notchRef} className="notch" style={{ width: W, height: H, marginLeft: -W / 2, borderRadius: `0 0 ${R}px ${R}px` }}>
            <span className="cam" />
            <div className="peek" style={{ width: 300, opacity: (T < K.Cue + 0.4 ? MOTION.enter(L + 2.7, 0.5)(T) : 0) + (T >= K.Vision ? MOTION.enter(K.Vision + 0.55, 0.4)(T) : 0) }}>
              <span style={{ display: "flex", alignItems: "center", gap: 8 }}><span className="mini"><img src={M.calm} alt="" /></span><span className="lab">{T >= K.Vision ? "Your workspace is calm" : peekText}</span></span>
              <span style={{ display: "flex", alignItems: "center", gap: 4 }}>{T >= L + 3.4 && T < K.Vision && <Gmail s={11} />}<span className="chip">{T >= K.Vision ? "✨" : T < L + 3.4 ? "syncing" : "in 12m"}</span></span>
            </div>
            <Shot from={K.Cue + 0.3} to={K.Drafts}><CueCard T={T} C={K.Cue} /></Shot>
            <Shot from={K.Drafts} to={K.Voice}><DraftsCard T={T} C={K.Drafts} /></Shot>
            <Shot from={K.Voice} to={K.Memory}><VoiceCard T={T} C={K.Voice} /></Shot>
            <Shot from={K.Memory} to={K.Vision + 0.65}><PhotosCard T={T} C={K.Memory} /></Shot>
            {ft && <span className="focus" style={{ left: ft.x - 4, top: ft.y - 3, width: ft.w + 8, height: ft.h + 6, opacity: focusO }} />}
          </div>
          {tw.showCursor && <Cursor x={cx} y={cy} o={cO} press={press} ripple={ripple} />}
        </div>
      </div>

      {callouts.map((c, i) => <Callout key={i} {...c} />)}
      {tw.showCaptions && <Captions style={{ font: "inherit", fontSize: 0 }} items={[
        { at: K.Cue + 1.2, until: K.Drafts - 0.3, text: <span className="capbar"><i />Knows what's next — from your Calendar, straight into the notch.</span> },
        { at: K.Drafts + 0.6, until: K.Voice - 0.3, text: <span className="capbar"><i />Softens what you wrote at 2 AM. You pick the tone.</span> },
        { at: K.Voice + 0.6, until: K.Memory - 0.3, text: <span className="capbar"><i />Just ask.</span> },
        { at: K.Memory + 0.8, until: K.Vision - 0.3, text: <span className="capbar"><i />Remembers where you've been.</span> },
      ]} />}
    </div>
  );
}

function LaunchApp() {
  const [tw, setTweak] = useTweaks(window.TWEAK_DEFAULTS);
  return (
    <>
      <CompositionStage width={1920} height={1080} scenes={window.OM_SCENES} playback={window.OM_PLAYBACK} bg="#f7f6f3">
        <Piece tw={tw} />
      </CompositionStage>
      <TweaksPanel title="Tweaks">
        <TweakSection label="Video">
          <TweakToggle label="Motion editor" value={tw.motionEditor} onChange={v => setTweak({ motionEditor: v })} />
          <TweakToggle label="Cursor" value={tw.showCursor} onChange={v => setTweak({ showCursor: v })} />
          <TweakToggle label="Callouts" value={tw.showCallouts} onChange={v => setTweak({ showCallouts: v })} />
          <TweakToggle label="Captions" value={tw.showCaptions} onChange={v => setTweak({ showCaptions: v })} />
        </TweakSection>
        <TweakSection label="Desktop">
          <TweakSelect label="Wallpaper" value={tw.wallpaper} onChange={v => setTweak({ wallpaper: v })} options={[{ value: "sequoia", label: "Sequoia" }, { value: "sonoma", label: "Sonoma" }, { value: "graphite", label: "Graphite" }, { value: "sage", label: "Sage" }]} />
        </TweakSection>
      </TweaksPanel>
    </>
  );
}
ReactDOM.createRoot(document.getElementById("root")).render(<LaunchApp />);
