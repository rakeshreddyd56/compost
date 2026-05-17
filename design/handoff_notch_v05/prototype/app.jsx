// app.jsx — Compost notch interactions prototype (v0.5)

const { useState: useAppState, useEffect: useAppEffect, useRef: useAppRef } = React;

const SCENARIOS = [
  { id: "cue",     label: "Cue",     icon: "☀",  Component: CueScene,    blurb: "First meeting prep. Notch reads your [!cue] page and surfaces what you said you'd do — with the Calendar/Gmail invite embedded so you can join Meet without leaving the notch." },
  { id: "drafts",  label: "Drafts",  icon: "🌙", Component: DraftsScene, blurb: "Sleep-On-It froze your 2 AM drafts. Pick a tone — Calmer, Crisp, Diplomatic — before you let them ship. Replaced drafts get stamped, originals get kept." },
  { id: "voice",   label: "Voice",   icon: "◉",  Component: VoiceScene,  blurb: "Talk to Compost. The mascot listens, the waveform reacts, the notch becomes a conversation. The quick-actions actually navigate to the matching surface." },
  { id: "photos",  label: "Photos",  icon: "📷", Component: PhotosScene, blurb: "Memory pile. Ask Compost about photos by time & place. Slideshow plays in the notch, and the mascot reacts when its own logo shows up in a photo of a public compost bin." },
];

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "scenario": "cue",
  "wallpaper": "sage",
  "notchStyle": "glossy",
  "expanded": true,
  "autoCycle": false,
  "showWindows": true,
  "showCaption": true,
  "showFlowMap": true
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [expanded, setExpanded] = useAppState(t.expanded);
  // Voice has a special "photos" sub-script that gets primed when the user
  // jumps into voice from the photos surface (or anywhere asking about
  // photos).
  const [voiceScript, setVoiceScript] = useAppState("default");

  useAppEffect(() => { setExpanded(t.expanded); }, [t.expanded]);

  useAppEffect(() => {
    if (!t.autoCycle) return;
    const id = setInterval(() => {
      const i = SCENARIOS.findIndex(s => s.id === t.scenario);
      const next = SCENARIOS[(i + 1) % SCENARIOS.length].id;
      setTweak({ scenario: next });
    }, 10000);
    return () => clearInterval(id);
  }, [t.autoCycle, t.scenario]);

  // Cross-scene navigation: any scene can call onNavigate("photos") and
  // we'll switch the scenario + expand. This is what makes the demo feel
  // end-to-end instead of four parallel islands.
  function navigate(target) {
    if (target === "voice-photos") {
      setVoiceScript("photos");
      setTweak({ scenario: "voice" });
      setExpanded(true);
      return;
    }
    if (target === "voice") {
      setVoiceScript("default");
    }
    setTweak({ scenario: target });
    setExpanded(true);
  }

  const scenario = SCENARIOS.find(s => s.id === t.scenario) || SCENARIOS[0];
  const Scene = scenario.Component;

  // build extra props per-scene
  const sceneProps = {
    expanded,
    onToggle: () => setExpanded(e => !e),
    onNavigate: navigate,
  };
  if (scenario.id === "voice") sceneProps.script = voiceScript;

  return (
    <div className={`stage theme-${t.wallpaper}`}>
      <DesktopBackdrop show={t.showWindows} scenario={t.scenario} />

      {/* MacBook bezel + menu strip */}
      <div className="mac-frame" />
      <div className="menu-strip">
        <span className="leaf-dot">🌱 Compost</span>
        <span style={{ opacity: 0.45 }}>File</span>
        <span style={{ opacity: 0.45 }}>Edit</span>
        <span style={{ opacity: 0.45 }}>View</span>
        <span style={{ opacity: 0.45 }}>Notion</span>
      </div>
      <div className="menu-strip menu-strip-right">
        <span style={{ opacity: 0.55 }}>🔋 87%</span>
        <span style={{ opacity: 0.55 }}>🔍</span>
        <span style={{ opacity: 0.55 }}>Sat 12:47</span>
      </div>

      {/* The notch itself */}
      <div className="notch-host" key={scenario.id}>
        <Scene {...sceneProps} />
      </div>

      {/* Scenario dock */}
      <div className="dock">
        {SCENARIOS.map(s => (
          <button
            key={s.id}
            className={`dock-btn ${t.scenario === s.id ? "on" : ""}`}
            onClick={() => navigate(s.id)}
          >
            <span className="icon">{s.icon}</span>
            <span>{s.label}</span>
          </button>
        ))}
        <span className="dock-separator" />
        <button
          className={`dock-btn ${expanded ? "on" : ""}`}
          onClick={() => setExpanded(e => !e)}
          title="Toggle peek/expanded"
        >
          <span className="icon">{expanded ? "▾" : "▴"}</span>
          <span>{expanded ? "Collapse" : "Expand"}</span>
        </button>
      </div>

      {/* Brandmark */}
      <div className="brandmark">
        <span className="leaf">🌱</span>
        <span><span className="b-name">Compost</span> · notch interactions · v0.5</span>
      </div>

      {/* Scene caption */}
      {t.showCaption && (
        <div className="scene-caption" key={scenario.id + "-caption"}>
          <strong>{scenario.label}</strong>
          {scenario.blurb}
        </div>
      )}

      {/* End-to-end flow map */}
      {t.showFlowMap && <FlowMap current={t.scenario} onJump={navigate} />}

      {/* Tweaks */}
      <TweaksPanel title="Tweaks">
        <TweakSection label="Scene">
          <TweakSelect
            label="Scenario"
            value={t.scenario}
            onChange={v => navigate(v)}
            options={SCENARIOS.map(s => ({ value: s.id, label: `${s.icon} ${s.label}` }))}
          />
          <TweakToggle label="Notch expanded" value={t.expanded} onChange={v => setTweak({ expanded: v })} />
          <TweakToggle label="Auto-cycle scenes" value={t.autoCycle} onChange={v => setTweak({ autoCycle: v })} />
        </TweakSection>
        <TweakSection label="Stage">
          <TweakRadio
            label="Wallpaper"
            value={t.wallpaper}
            onChange={v => setTweak({ wallpaper: v })}
            options={[
              { value: "sage", label: "Sage" },
              { value: "paper", label: "Paper" },
              { value: "graphite", label: "Graphite" },
            ]}
          />
          <TweakRadio
            label="Notch finish"
            value={t.notchStyle}
            onChange={v => setTweak({ notchStyle: v })}
            options={[
              { value: "glossy", label: "Glossy" },
              { value: "frosted", label: "Frosted" },
              { value: "sage", label: "Sage" },
            ]}
          />
          <TweakToggle label="Desktop window stubs" value={t.showWindows} onChange={v => setTweak({ showWindows: v })} />
          <TweakToggle label="Scene caption" value={t.showCaption} onChange={v => setTweak({ showCaption: v })} />
          <TweakToggle label="Flow map" value={t.showFlowMap} onChange={v => setTweak({ showFlowMap: v })} />
        </TweakSection>
        <TweakSection label="Demo helpers">
          <TweakButton label="🌱 Run end-to-end demo" onClick={() => runDemo(navigate, setExpanded)} />
        </TweakSection>
      </TweaksPanel>

      <style>{`
        .notch { ${t.notchStyle === "frosted" ? "background: rgba(10,10,12,0.78); backdrop-filter: blur(20px) saturate(140%);" : ""} }
        .notch.style-glossy { ${t.notchStyle === "sage" ? "background: linear-gradient(180deg,#142013 0%,#0a0f08 100%);" : ""} }
      `}</style>
    </div>
  );
}

/* ---------- Flow map: visualises the end-to-end demo path ---------- */

function FlowMap({ current, onJump }) {
  const nodes = [
    { id: "cue",    label: "Cue",    sub: "Meeting prep" },
    { id: "voice",  label: "Voice",  sub: "Ask Compost" },
    { id: "drafts", label: "Drafts", sub: "Tone shift" },
    { id: "photos", label: "Photos", sub: "Memory pile" },
  ];

  return (
    <div style={{
      position: "absolute",
      left: 24,
      bottom: 90,
      display: "flex",
      flexDirection: "column",
      gap: 6,
      zIndex: 25,
      padding: 10,
      background: "rgba(8,9,12,0.55)",
      backdropFilter: "blur(16px) saturate(140%)",
      borderRadius: 14,
      border: "0.5px solid rgba(255,255,255,0.08)",
      maxWidth: 200,
    }}>
      <div style={{
        fontSize: 9.5, fontWeight: 700, letterSpacing: "0.08em",
        textTransform: "uppercase", color: "var(--ink-3)",
        marginBottom: 4,
      }}>
        End-to-end flow
      </div>
      {nodes.map((n, i) => (
        <React.Fragment key={n.id}>
          <button
            onClick={() => onJump(n.id)}
            style={{
              display: "flex", alignItems: "center", gap: 8,
              border: 0,
              background: current === n.id ? "rgba(135,168,119,0.18)" : "transparent",
              color: current === n.id ? "var(--sage-300)" : "var(--ink-2)",
              padding: "5px 8px",
              borderRadius: 8,
              cursor: "pointer",
              fontFamily: "var(--font-display)",
              fontSize: 11.5,
              fontWeight: 600,
              textAlign: "left",
              transition: "all 0.2s",
            }}
          >
            <span style={{
              width: 16, height: 16, borderRadius: "50%",
              background: current === n.id ? "var(--sage-600)" : "rgba(255,255,255,0.08)",
              color: current === n.id ? "#fff" : "var(--ink-3)",
              display: "grid", placeItems: "center",
              fontSize: 9, fontWeight: 700,
            }}>{i + 1}</span>
            <span style={{ flex: 1 }}>
              <span style={{ display: "block" }}>{n.label}</span>
              <span style={{ display: "block", fontSize: 9.5, fontWeight: 500, color: "var(--ink-3)" }}>
                {n.sub}
              </span>
            </span>
          </button>
          {i < nodes.length - 1 && (
            <span style={{
              marginLeft: 16, height: 8, width: 1,
              background: "rgba(255,255,255,0.10)",
            }} />
          )}
        </React.Fragment>
      ))}
    </div>
  );
}

/* ---------- Demo runner: walks the full happy path ---------- */

function runDemo(navigate, setExpanded) {
  const steps = [
    { wait: 0,    do: () => { navigate("cue"); setExpanded(true); } },
    { wait: 3500, do: () => navigate("voice") },
    { wait: 5500, do: () => navigate("drafts") },
    { wait: 5000, do: () => navigate("voice-photos") },
    { wait: 6500, do: () => navigate("photos") },
  ];
  let acc = 0;
  steps.forEach(s => {
    acc += s.wait;
    setTimeout(s.do, acc);
  });
}

/* ---------- Desktop backdrop (window stubs) ---------- */

function DesktopBackdrop({ show, scenario }) {
  if (!show) return null;
  const wins = {
    cue: [
      { left: "5%",  top: "14%", w: 320, h: 380, content: "notion" },
      { left: "70%", top: "20%", w: 290, h: 260, content: "gmail" },
    ],
    drafts: [
      { left: "6%",  top: "18%", w: 360, h: 340, content: "notion" },
      { left: "64%", top: "24%", w: 320, h: 260, content: "draftpile" },
    ],
    voice: [
      { left: "8%", top: "22%", w: 380, h: 300, content: "notion" },
    ],
    photos: [
      { left: "5%",  top: "16%", w: 320, h: 380, content: "memorypile" },
      { left: "68%", top: "22%", w: 310, h: 280, content: "maps" },
    ],
  }[scenario] || [];

  return (
    <>
      {wins.map((w, i) => (
        <div
          key={i + scenario}
          className="window-stub fade-in"
          style={{ left: w.left, top: w.top, width: w.w, height: w.h }}
        >
          <div className="titlebar">
            <span className="tl" style={{ background: "rgba(215,122,107,0.45)" }} />
            <span className="tl" style={{ background: "rgba(240,200,80,0.45)" }} />
            <span className="tl" style={{ background: "rgba(135,168,119,0.50)" }} />
            <span style={{
              marginLeft: 8, fontSize: 10, color: "rgba(255,255,255,0.30)",
              fontFamily: "var(--font-display)", fontWeight: 600,
            }}>
              {w.content === "notion" ? "Hackathon · agenda.md — Notion" :
               w.content === "gmail" ? "Inbox · Maya Chen invited you — Gmail" :
               w.content === "draftpile" ? "Compost Pile · Frozen Drafts" :
               w.content === "memorypile" ? "Compost Pile · Memory pile" :
               w.content === "maps" ? "Maps · SoMa, San Francisco" :
               "Window"}
            </span>
          </div>
          <div className="doc-content">
            <span className="line h" />
            <span className="line med" />
            <span className="line" />
            <span className="line short" />
            <span className="line med" />
            <span className="line" />
            <span className="line short" />
          </div>
        </div>
      ))}
    </>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
