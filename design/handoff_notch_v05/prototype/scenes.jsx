// scenes.jsx — four notch-interaction scenarios
// Cue · Drafts · Voice · Photos (Memory pile)

const { useState: useSceneState, useEffect: useSceneEffect, useRef: useSceneRef, useMemo: useSceneMemo, useCallback: useSceneCallback } = React;

/* ============================================================
 * Small shared bits
 * ============================================================ */

// Gmail "M" logo, drawn so it renders crisp at any size
function GmailIcon({ size = 14 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M2 6.2v11.6c0 .7.5 1.2 1.2 1.2h2.6V11L2 6.2z"/>
      <path fill="#34A853" d="M18.2 19h2.6c.7 0 1.2-.5 1.2-1.2V6.2L18.2 11v8z"/>
      <path fill="#FBBC04" d="M18.2 6.2V11l3.8-2.85V6.7c0-1.36-1.55-2.14-2.64-1.33l-1.16.83z"/>
      <path fill="#EA4335" d="M5.8 11V6.2L12 10.8l6.2-4.6V11L12 15.6 5.8 11z"/>
      <path fill="#C5221F" d="M2 6.7v1.45L5.8 11V6.2L4.64 5.37C3.55 4.56 2 5.34 2 6.7z"/>
    </svg>
  );
}

function GoogleMeetIcon({ size = 14 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#00832d" d="M13 12l3-2.7v5.4L13 12z"/>
      <path fill="#0066da" d="M3 7v10h7V7H3z"/>
      <path fill="#e94235" d="M16 5.7L13 8.4V7c0-1.1-.9-2-2-2H7l9 .7z"/>
      <path fill="#2684fc" d="M16 18.3L13 15.6V17c0 1.1-.9 2-2 2H7l9-.7z"/>
      <path fill="#ffba00" d="M21 9.3v5.4c0 .8-.9 1.3-1.6.9L16 14.4V9.6l3.4-1.2c.7-.4 1.6.1 1.6.9z"/>
    </svg>
  );
}

// Tiny toast surfaced inside the notch for cross-scene confirmations
function NotchToast({ children, onDone, duration = 2000 }) {
  useSceneEffect(() => {
    const t = setTimeout(() => onDone && onDone(), duration);
    return () => clearTimeout(t);
  }, []);
  return (
    <div style={{
      position: "absolute",
      left: 16, right: 16, bottom: 12,
      background: "rgba(135,168,119,0.18)",
      border: "0.5px solid rgba(135,168,119,0.40)",
      color: "var(--sage-300)",
      borderRadius: 999,
      padding: "8px 12px",
      fontSize: 11.5,
      fontFamily: "var(--font-display)",
      fontWeight: 600,
      display: "flex", alignItems: "center", gap: 6,
      zIndex: 10,
    }}>
      <span>✓</span> {children}
    </div>
  );
}

/* ============================================================
 * SCENE 1 — CUE: first meeting prep (with Gmail / Meet linkage)
 * ============================================================ */

function CueScene({ expanded, onToggle, onNavigate }) {
  const [checked, setChecked] = useSceneState({ a: true, b: true, c: false, d: false });
  const [snoozed, setSnoozed] = useSceneState(false);
  const [opened, setOpened] = useSceneState(false);

  const prepItems = [
    { id: "a", label: "Skim last week's notes" },
    { id: "b", label: "Pull the Figma file" },
    { id: "c", label: "Decide on top 2 questions" },
    { id: "d", label: "Open the Loom from yesterday" },
  ];

  const allChecked = Object.values(checked).every(v => v);

  if (!expanded) {
    return (
      <Notch size="peek" onClick={onToggle}>
        <div className="peek">
          <div className="peek-left">
            <MascotMini mood={snoozed ? "calm" : "calm"} />
            <span className="peek-label">App shell checkpoint</span>
          </div>
          <div className="peek-right">
            <span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
              <GmailIcon size={11} />
              <span className="peek-chip">{snoozed ? "in 17m" : "in 12m"}</span>
            </span>
          </div>
        </div>
      </Notch>
    );
  }

  return (
    <Notch size="expanded" style="glossy">
      <div className="expanded fade-in">
        <div className="exp-head">
          <Mascot mood={allChecked ? "alert" : "calm"} size={36} bobble={allChecked} />
          <div className="exp-head-text">
            <span className="exp-eyebrow">☀️ Up next · {snoozed ? "10:35 AM" : "10:30 AM"}</span>
            <h3 className="exp-title">App shell checkpoint</h3>
          </div>
          <button className="exp-close" onClick={onToggle} aria-label="Collapse">✕</button>
        </div>

        <div className="cue-time-strip">
          <div className="cue-time">{snoozed ? "10:35" : "10:30"}<span className="ampm">AM</span></div>
          <div className="cue-countdown">in {snoozed ? 17 : 12} min · 25 min</div>
        </div>

        {/* Gmail / Calendar invite row */}
        <div style={{
          display: "flex", alignItems: "center", gap: 8,
          padding: "8px 10px",
          background: "var(--card)",
          borderRadius: "var(--r-md)",
          border: "0.5px solid var(--hair)",
        }}>
          <GmailIcon size={16} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11.5, color: "var(--ink)", fontFamily: "var(--font-display)", fontWeight: 600 }}>
              From Calendar via Gmail
            </div>
            <div style={{ fontSize: 11, color: "var(--ink-3)" }}>
              Maya Chen &amp; Theo Park · accepted ·{" "}
              <span style={{ color: "var(--sage-300)" }}>2 attendees</span>
            </div>
          </div>
          <button
            onClick={() => setOpened("meet")}
            style={{
              display: "flex", alignItems: "center", gap: 4,
              padding: "4px 8px",
              borderRadius: 999,
              border: 0,
              background: "rgba(255,255,255,0.06)",
              color: "var(--ink-2)",
              fontSize: 11,
              fontFamily: "var(--font-display)",
              fontWeight: 600,
              cursor: "pointer",
            }}
          >
            <GoogleMeetIcon size={12} />
            Join Meet
          </button>
        </div>

        <div style={{ fontSize: 12.5, color: "var(--ink-2)", lineHeight: 1.45 }}>
          You promised the notch would feel <em>alive</em> by today. Maya is bringing the worker logs.
        </div>

        <div className="checklist">
          {prepItems.map(p => (
            <div
              key={p.id}
              className={`check ${checked[p.id] ? "done" : ""}`}
              onClick={() => setChecked(c => ({ ...c, [p.id]: !c[p.id] }))}
            >
              <span className="box">
                {checked[p.id] && (
                  <svg viewBox="0 0 12 12" width="10" height="10">
                    <path d="M2 6.2L5 9L10 3" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </span>
              <span className="label">{p.label}</span>
            </div>
          ))}
        </div>

        <div style={{ display: "flex", gap: 6, marginTop: 4, alignItems: "center", flexWrap: "wrap" }}>
          <Btn kind="primary" icon="↗" onClick={() => setOpened("notion")}>Open in Notion</Btn>
          <Btn kind="ghost" onClick={() => setSnoozed(s => !s)}>
            {snoozed ? "Un-snooze" : "Snooze 5m"}
          </Btn>
          <Btn kind="muted" onClick={() => onNavigate && onNavigate("voice")}>
            Ask Compost ↗
          </Btn>
          <span style={{ marginLeft: "auto", fontSize: 11, color: "var(--ink-3)" }}>
            [!cue] · agenda.md
          </span>
        </div>

        {opened === "notion" && (
          <NotchToast onDone={() => setOpened(false)}>Opened agenda.md in Notion</NotchToast>
        )}
        {opened === "meet" && (
          <NotchToast onDone={() => setOpened(false)}>Joining Google Meet…</NotchToast>
        )}
        {snoozed && !opened && (
          <NotchToast onDone={() => {}} duration={1400}>
            Snoozed — back in 5m
          </NotchToast>
        )}
      </div>
    </Notch>
  );
}

/* ============================================================
 * SCENE 2 — DRAFTS: pending review + tone shift
 * ============================================================ */

const DRAFTS = [
  {
    id: "d1",
    title: "Re: Q2 contractor scope",
    frozenAt: "1:47 AM",
    original: "We need this WRAPPED by Friday or the whole launch FALLS APART. I'm not going to keep chasing you — just GET it done.",
    rewrites: {
      Calmer:      "We're aiming to wrap this by Friday so the launch holds. Could you share where things stand and what would help you finish?",
      Crisp:       "Need this complete by Friday for the launch. What's blocking you, and how can I help?",
      Diplomatic:  "Friday is our launch checkpoint and we'd love to land this by then. Want to find a 15-minute window to align on what's left?",
    },
  },
  {
    id: "d2",
    title: "Hackathon retro thoughts",
    frozenAt: "2:14 AM",
    original: "Honestly the whole demo workflow is BROKEN. Nobody tested it. I am DONE babysitting deploys for people who refuse to read the runbook.",
    rewrites: {
      Calmer:      "The demo workflow snagged a few times today, mostly around deploys. Could we walk through the runbook together next time to surface what's missing?",
      Crisp:       "Demo workflow is fragile, especially around deploys. Want to do a runbook review so the next pass is smoother?",
      Diplomatic:  "I think there's an opportunity to harden the demo workflow — the deploy steps tripped us up. Could we revisit the runbook as a team?",
    },
  },
  {
    id: "d3",
    title: "Note to self · pricing page",
    frozenAt: "12:53 AM",
    original: "ditch the 3-column thing it is UGLY and nobody reads the middle one anyway. start over with literally one button and a price tag",
    rewrites: {
      Calmer:      "The three-column layout isn't landing — the middle tier gets ignored. Try a single, clear price with one CTA and see if it converts better.",
      Crisp:       "Three-column pricing isn't working. Test a single-tier page with one price and one button.",
      Diplomatic:  "The current three-column pricing may be doing more harm than good. Could be worth A/B testing against a simpler single-tier page.",
    },
  },
];

function DraftsScene({ expanded, onToggle, onNavigate }) {
  const [activeId, setActiveId] = useSceneState(DRAFTS[0].id);
  const [tone, setTone] = useSceneState("Calmer");
  const [shimmer, setShimmer] = useSceneState(false);
  const [rephrasing, setRephrasing] = useSceneState(false);
  const [resolved, setResolved] = useSceneState({});
  const [toast, setToast] = useSceneState(null);
  const active = DRAFTS.find(d => d.id === activeId);

  function pickTone(t) {
    if (t === tone) return;
    setTone(t);
    setRephrasing(true);
    setShimmer(true);
    setTimeout(() => {
      setRephrasing(false);
      setShimmer(false);
    }, 700);
  }

  function rephraseAgain() {
    setRephrasing(true);
    setShimmer(true);
    setTimeout(() => {
      setRephrasing(false);
      setShimmer(false);
    }, 900);
  }

  function approve() {
    setResolved(r => ({ ...r, [activeId]: "approved" }));
    setToast(`Replaced ${active.title} with ${tone.toLowerCase()} version`);
    // Move to next unresolved draft
    const next = DRAFTS.find(d => d.id !== activeId && !resolved[d.id]);
    if (next) setTimeout(() => setActiveId(next.id), 400);
  }

  function keep() {
    setResolved(r => ({ ...r, [activeId]: "kept" }));
    setToast(`Kept original of ${active.title}`);
    const next = DRAFTS.find(d => d.id !== activeId && !resolved[d.id]);
    if (next) setTimeout(() => setActiveId(next.id), 400);
  }

  const unresolvedCount = DRAFTS.filter(d => !resolved[d.id]).length;

  if (!expanded) {
    return (
      <Notch size="peek" onClick={onToggle}>
        <div className="peek">
          <div className="peek-left">
            <MascotMini mood="nudging" />
            <span className="peek-label">{unresolvedCount || 0} drafts on ice</span>
          </div>
          <div className="peek-right">
            <span className="peek-chip warn">review</span>
          </div>
        </div>
      </Notch>
    );
  }

  // diff helpers
  const renderOriginal = txt =>
    txt.split(/(\s+)/).map((w, i) => {
      const isShout = /^[A-Z]{3,}$/.test(w);
      return isShout
        ? <span key={i} className="shout">{w}</span>
        : <span key={i}>{w}</span>;
    });

  const calmer = active.rewrites[tone];
  const calmerWords = calmer.split(/\s+/);
  const originalSet = new Set(active.original.toLowerCase().split(/\W+/));
  const renderCalmer = () =>
    calmerWords.map((w, i) => {
      const stripped = w.replace(/[.,;!?]/g, "").toLowerCase();
      const novel = stripped.length > 3 && !originalSet.has(stripped);
      return (
        <React.Fragment key={i}>
          {novel ? <span className="added">{w}</span> : w}
          {i < calmerWords.length - 1 ? " " : ""}
        </React.Fragment>
      );
    });

  return (
    <Notch size="wide" style="glossy">
      <div className="expanded fade-in">
        <div className="exp-head">
          <Mascot mood="nudging" size={36} />
          <div className="exp-head-text">
            <span className="exp-eyebrow">🌙 Sleep-on-it · {unresolvedCount} frozen</span>
            <h3 className="exp-title">Morning review</h3>
          </div>
          <button className="exp-close" onClick={onToggle}>✕</button>
        </div>

        <div className="draft-list">
          {DRAFTS.map(d => {
            const status = resolved[d.id];
            return (
              <div
                key={d.id}
                className={`draft-item ${activeId === d.id ? "active" : ""}`}
                onClick={() => setActiveId(d.id)}
                style={status ? { opacity: 0.55 } : {}}
              >
                <div className="draft-head">
                  <span className="draft-title">{d.title}</span>
                  {status === "approved" ? (
                    <Tag tone="sage">✓ replaced</Tag>
                  ) : status === "kept" ? (
                    <Tag tone="default">kept original</Tag>
                  ) : (
                    <Tag tone={activeId === d.id ? "sage" : "default"}>frozen</Tag>
                  )}
                  <span className="draft-meta">{d.frozenAt}</span>
                </div>
              </div>
            );
          })}
        </div>

        <div className="diff-pane">
          <div className="diff-col original">
            <div className="diff-label">
              <span>Original · {active.frozenAt} you</span>
              <span style={{ opacity: 0.6 }}>raw</span>
            </div>
            {renderOriginal(active.original)}
          </div>
          <div
            className={`diff-col calmer ${shimmer ? "fade-in" : ""}`}
            key={tone + "-" + active.id}
            style={rephrasing ? { opacity: 0.4, transition: "opacity 0.18s" } : {}}
          >
            <div className="diff-label">
              <span>{tone} rewrite</span>
              <span style={{ opacity: 0.6 }}>Haiku</span>
            </div>
            {renderCalmer()}
          </div>
        </div>

        <div className="tone-row">
          <span className="label">Tone</span>
          {["Calmer", "Crisp", "Diplomatic"].map(t => (
            <button
              key={t}
              className={`tone-pill ${tone === t ? "on" : ""}`}
              onClick={() => pickTone(t)}
            >
              {t}
            </button>
          ))}
          <button className="tone-pill" onClick={rephraseAgain} title="Generate another">
            {rephrasing ? "…" : "↻ rephrase"}
          </button>
          <div style={{ marginLeft: "auto", display: "flex", gap: 6 }}>
            <Btn kind="ghost" onClick={keep} disabled={!!resolved[activeId]}>Keep mine</Btn>
            <Btn kind="primary" icon="✓" onClick={approve} disabled={!!resolved[activeId]}>
              Use {tone.toLowerCase()}
            </Btn>
          </div>
        </div>

        {toast && (
          <NotchToast onDone={() => setToast(null)} duration={1800}>
            {toast}
          </NotchToast>
        )}
      </div>
    </Notch>
  );
}

/* ============================================================
 * SCENE 3 — VOICE: talking to the mascot
 * ============================================================ */

const VOICE_SCRIPT_DEFAULT = [
  { stage: "listening", text: "hey compost, what's on the pile this morning…" },
  { stage: "thinking",  text: "" },
  { stage: "speaking",  text: "Three things. Maya's checkpoint in twelve minutes. Two drafts you wrote at 2 AM. And five photos from yesterday's walk waiting in Memory pile." },
  { stage: "idle",      text: "Three things. Maya's checkpoint in twelve minutes. Two drafts you wrote at 2 AM. And five photos from yesterday's walk waiting in Memory pile." },
];

const VOICE_SCRIPT_PHOTOS = [
  { stage: "listening", text: "compost, what photos did i take yesterday around the gallery?" },
  { stage: "thinking",  text: "" },
  { stage: "speaking",  text: "Five from SoMa between 2:30 and 3:15 PM. Two skyline shots near the Salesforce Tower, two posters from the Herman Miller gallery, and — heh — you caught my logo on a trash can.", followUp: "photos" },
  { stage: "idle",      text: "Tap the Photos tab to flip through them." },
];

function VoiceScene({ expanded, onToggle, onNavigate, script = "default" }) {
  const SCRIPT = script === "photos" ? VOICE_SCRIPT_PHOTOS : VOICE_SCRIPT_DEFAULT;
  const [step, setStep] = useSceneState(0);
  const [typed, setTyped] = useSceneState("");
  const stageRef = useSceneRef(SCRIPT[0]);

  // reset when script changes
  useSceneEffect(() => {
    setStep(0);
    setTyped("");
  }, [script]);

  // advance through the script
  useSceneEffect(() => {
    if (!expanded) return;
    const cur = SCRIPT[step];
    stageRef.current = cur;

    let cancelled = false;

    if (cur.stage === "listening") {
      let i = 0;
      setTyped("");
      const id = setInterval(() => {
        if (cancelled) return;
        i++;
        setTyped(cur.text.slice(0, i));
        if (i >= cur.text.length) {
          clearInterval(id);
          setTimeout(() => !cancelled && setStep(s => s + 1), 600);
        }
      }, 38);
      return () => { cancelled = true; clearInterval(id); };
    } else if (cur.stage === "thinking") {
      const t = setTimeout(() => !cancelled && setStep(s => s + 1), 1200);
      return () => { cancelled = true; clearTimeout(t); };
    } else if (cur.stage === "speaking") {
      let i = 0;
      setTyped("");
      const id = setInterval(() => {
        if (cancelled) return;
        i++;
        setTyped(cur.text.slice(0, i));
        if (i >= cur.text.length) {
          clearInterval(id);
          setTimeout(() => !cancelled && setStep(s => s + 1), 1400);
        }
      }, 24);
      return () => { cancelled = true; clearInterval(id); };
    }
  }, [step, expanded, script]);

  // loop back to start after idle
  useSceneEffect(() => {
    if (!expanded) return;
    const cur = SCRIPT[step];
    if (cur?.stage === "idle") {
      const t = setTimeout(() => setStep(0), 5500);
      return () => clearTimeout(t);
    }
  }, [step, expanded, script]);

  useSceneEffect(() => {
    if (!expanded) { setStep(0); setTyped(""); }
  }, [expanded]);

  const current = SCRIPT[step] || SCRIPT[0];

  if (!expanded) {
    return (
      <Notch size="peek" onClick={onToggle}>
        <div className="peek">
          <div className="peek-left">
            <span style={{
              display: "inline-flex", alignItems: "center", gap: 4,
              color: "var(--rose)", fontWeight: 600, fontSize: 12,
            }}>
              <span style={{
                width: 7, height: 7, borderRadius: "50%",
                background: "var(--rose)",
                animation: "pulseDot 1s ease-in-out infinite",
              }} />
              LIVE
            </span>
          </div>
          <div style={{ flex: 1, display: "flex", justifyContent: "center", minWidth: 0 }}>
            <Waveform active={true} count={20} color="rgba(215,122,107,0.85)" />
          </div>
          <div className="peek-right">
            <span className="peek-chip live">listening</span>
          </div>
        </div>
      </Notch>
    );
  }

  const mascotMood =
    current.stage === "thinking" ? "calm" :
    current.stage === "speaking" ? "nudging" :
    "calm";

  const stageLabel = {
    listening: "Listening",
    thinking:  "Thinking",
    speaking:  "Compost",
    idle:      "Compost · finished",
  }[current.stage] || "Listening";

  return (
    <Notch size="expanded" style="glossy">
      <div className="expanded fade-in">
        <div className="voice-stage">
          <div className="voice-mascot-slot">
            <Mascot mood={mascotMood} size={96} bobble={current.stage === "speaking"} />
          </div>
          <div className="voice-body">
            <span className="voice-state-label">
              <span className="dot" style={{
                background: current.stage === "listening" ? "var(--rose)" :
                            current.stage === "thinking" ? "var(--amber)" :
                            "var(--sage-400)"
              }} />
              {stageLabel}
            </span>
            <div className="voice-transcript">
              {current.stage === "thinking" ? (
                <span style={{ color: "var(--ink-3)", fontStyle: "italic" }}>checking the pile…</span>
              ) : (
                <>
                  {typed}
                  {current.stage !== "idle" && <span className="voice-caret" />}
                </>
              )}
            </div>
            <Waveform
              active={current.stage !== "idle"}
              count={42}
              color={current.stage === "listening" ? "rgba(215,122,107,0.85)" : undefined}
            />
            <div className="voice-quick">
              <Btn kind="ghost" onClick={() => onNavigate && onNavigate("cue")}>What did I miss?</Btn>
              <Btn kind="ghost" onClick={() => onNavigate && onNavigate("drafts")}>Read drafts</Btn>
              <Btn kind="ghost" onClick={() => onNavigate && onNavigate("photos")}>Show photos</Btn>
              <button
                className="btn muted"
                style={{ marginLeft: "auto" }}
                onClick={onToggle}
              >
                Tap to end
              </button>
            </div>
          </div>
        </div>
      </div>
    </Notch>
  );
}

/* ============================================================
 * SCENE 4 — PHOTOS / MEMORY PILE: slideshow with mascot reactions
 * ============================================================ */

const PHOTOS = [
  {
    id: "p1",
    src: "assets/photo-soma-1.jpeg",
    caption: "Salesforce Tower from 2nd St",
    place: "SoMa, San Francisco",
    timeISO: "2026-05-15T14:32:00",
    timeLabel: "yesterday · 2:32 PM",
    lat: 37.789, lng: -122.397,
    tags: ["walk", "skyline"],
    mascot: null,
  },
  {
    id: "p2",
    src: "assets/photo-soma-2.jpeg",
    caption: "Looking up the Salesforce spire",
    place: "Mission & 2nd, San Francisco",
    timeISO: "2026-05-15T14:41:00",
    timeLabel: "yesterday · 2:41 PM",
    lat: 37.789, lng: -122.397,
    tags: ["walk", "skyline"],
    mascot: null,
  },
  {
    id: "p3",
    src: "assets/photo-dustbin.jpeg",
    caption: "saw your logo on a bin at Pier 9 ☺",
    place: "Pier 9 cafeteria",
    timeISO: "2026-05-15T14:58:00",
    timeLabel: "yesterday · 2:58 PM",
    lat: 37.799, lng: -122.398,
    tags: ["compost-sighting", "lol"],
    mascot: "self-sighting",  // mascot reacts here
  },
  {
    id: "p4",
    src: "assets/photo-poster-hermanmiller.jpeg",
    caption: '"Things Are Getting Better All The Time" — Herman Miller, 1980',
    place: "MoMA gift shop",
    timeISO: "2026-05-15T15:08:00",
    timeLabel: "yesterday · 3:08 PM",
    lat: 37.785, lng: -122.402,
    tags: ["poster", "design-history"],
    mascot: "delighted",
  },
  {
    id: "p5",
    src: "assets/photo-poster-peugeot.jpeg",
    caption: "Cycles Peugeot, Roger Pérot, 1931",
    place: "MoMA gift shop",
    timeISO: "2026-05-15T15:11:00",
    timeLabel: "yesterday · 3:11 PM",
    lat: 37.785, lng: -122.402,
    tags: ["poster", "design-history"],
    mascot: null,
  },
];

function PhotosScene({ expanded, onToggle, onNavigate, autoplayHint = false }) {
  const [idx, setIdx] = useSceneState(0);
  const [playing, setPlaying] = useSceneState(true);
  const [tagOpen, setTagOpen] = useSceneState(false);
  const [tagInput, setTagInput] = useSceneState("");
  const [toast, setToast] = useSceneState(null);
  const [savedTags, setSavedTags] = useSceneState({});

  const photo = PHOTOS[idx];

  // auto-advance
  useSceneEffect(() => {
    if (!expanded || !playing) return;
    const t = setTimeout(() => {
      setIdx(i => (i + 1) % PHOTOS.length);
    }, photo.mascot ? 5000 : 3500);
    return () => clearTimeout(t);
  }, [idx, expanded, playing]);

  // pause when collapsed
  useSceneEffect(() => {
    if (!expanded) {
      setTagOpen(false);
    }
  }, [expanded]);

  function next() { setIdx(i => (i + 1) % PHOTOS.length); }
  function prev() { setIdx(i => (i - 1 + PHOTOS.length) % PHOTOS.length); }
  function saveTag() {
    if (!tagInput.trim()) { setTagOpen(false); return; }
    setSavedTags(t => ({ ...t, [photo.id]: tagInput.trim() }));
    setToast(`Tagged "${tagInput.trim()}" · written to Notion`);
    setTagInput("");
    setTagOpen(false);
  }

  if (!expanded) {
    return (
      <Notch size="peek" onClick={onToggle}>
        <div className="peek">
          <div className="peek-left">
            <MascotMini mood="calm" />
            <span className="peek-label">5 from SoMa yesterday</span>
          </div>
          <div className="peek-right">
            <span className="peek-chip" style={{
              background: "rgba(201,168,90,0.18)",
              color: "var(--gold)",
            }}>📷</span>
          </div>
        </div>
      </Notch>
    );
  }

  // Mascot mood + speech bubble for special frames
  let mascotMood = "calm";
  let mascotBobble = false;
  let mascotSays = null;
  if (photo.mascot === "self-sighting") {
    mascotMood = "alert";
    mascotBobble = true;
    mascotSays = "yes — that's me! the bin at Pier 9. logged it.";
  } else if (photo.mascot === "delighted") {
    mascotMood = "nudging";
    mascotSays = "this one's good. tag it for the moodboard?";
  }

  return (
    <Notch size="wide" style="glossy">
      <div className="expanded fade-in">
        <div className="exp-head">
          <Mascot mood={mascotMood} size={36} bobble={mascotBobble} />
          <div className="exp-head-text">
            <span className="exp-eyebrow">📷 Memory pile · {PHOTOS.length} from yesterday</span>
            <h3 className="exp-title">{photo.place}</h3>
          </div>
          <button className="exp-close" onClick={onToggle}>✕</button>
        </div>

        {/* Photo viewer */}
        <div style={{
          position: "relative",
          width: "100%",
          height: 260,
          borderRadius: "var(--r-md)",
          overflow: "hidden",
          background: "#111",
          border: "0.5px solid var(--hair)",
        }}>
          <img
            src={photo.src}
            alt={photo.caption}
            key={photo.id}
            style={{
              width: "100%",
              height: "100%",
              objectFit: "cover",
              display: "block",
              animation: "fadeIn 0.4s var(--ease)",
            }}
          />

          {/* prev / next arrows */}
          <button
            onClick={prev}
            aria-label="Previous photo"
            style={{
              position: "absolute", left: 8, top: "50%", transform: "translateY(-50%)",
              width: 32, height: 32, borderRadius: "50%",
              background: "rgba(0,0,0,0.55)",
              backdropFilter: "blur(8px)",
              border: "0.5px solid rgba(255,255,255,0.15)",
              color: "#fff", cursor: "pointer",
              display: "grid", placeItems: "center",
              fontSize: 14,
            }}
          >‹</button>
          <button
            onClick={next}
            aria-label="Next photo"
            style={{
              position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)",
              width: 32, height: 32, borderRadius: "50%",
              background: "rgba(0,0,0,0.55)",
              backdropFilter: "blur(8px)",
              border: "0.5px solid rgba(255,255,255,0.15)",
              color: "#fff", cursor: "pointer",
              display: "grid", placeItems: "center",
              fontSize: 14,
            }}
          >›</button>

          {/* Bottom gradient + meta */}
          <div style={{
            position: "absolute", inset: "auto 0 0 0",
            padding: "30px 12px 10px 12px",
            background: "linear-gradient(0deg, rgba(0,0,0,0.75), transparent)",
            color: "#fff",
            fontFamily: "var(--font-display)",
          }}>
            <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 2 }}>
              {photo.caption}
            </div>
            <div style={{ fontSize: 10.5, opacity: 0.75, display: "flex", gap: 8 }}>
              <span>📍 {photo.place}</span>
              <span>· 🕒 {photo.timeLabel}</span>
            </div>
          </div>

          {/* Mascot speech bubble overlay */}
          {mascotSays && (
            <div style={{
              position: "absolute",
              left: 10, top: 10,
              maxWidth: 260,
              padding: "8px 10px",
              borderRadius: 12,
              background: "rgba(20,32,19,0.92)",
              border: "0.5px solid rgba(135,168,119,0.4)",
              fontSize: 11.5,
              color: "var(--sage-300)",
              fontFamily: "var(--font-display)",
              fontWeight: 500,
              lineHeight: 1.35,
              boxShadow: "0 8px 24px rgba(0,0,0,0.5)",
              display: "flex", alignItems: "flex-start", gap: 6,
            }}>
              <span style={{ fontSize: 14 }}>🌱</span>
              <span>{mascotSays}</span>
            </div>
          )}

          {/* play/pause indicator */}
          <button
            onClick={() => setPlaying(p => !p)}
            aria-label={playing ? "Pause slideshow" : "Play slideshow"}
            style={{
              position: "absolute", top: 8, right: 8,
              width: 28, height: 28, borderRadius: "50%",
              background: "rgba(0,0,0,0.55)",
              backdropFilter: "blur(8px)",
              border: "0.5px solid rgba(255,255,255,0.15)",
              color: "#fff", cursor: "pointer",
              fontSize: 11,
            }}
          >{playing ? "⏸" : "▶"}</button>
        </div>

        {/* Dot indicator */}
        <div style={{ display: "flex", justifyContent: "center", gap: 6 }}>
          {PHOTOS.map((p, i) => (
            <button
              key={p.id}
              onClick={() => setIdx(i)}
              aria-label={`Go to photo ${i + 1}`}
              style={{
                width: i === idx ? 18 : 6, height: 6,
                borderRadius: 3,
                border: 0,
                background: i === idx
                  ? "var(--sage-400)"
                  : (p.mascot ? "rgba(201,168,90,0.50)" : "rgba(255,255,255,0.20)"),
                cursor: "pointer",
                transition: "width 0.3s var(--spring), background 0.2s",
                padding: 0,
              }}
            />
          ))}
        </div>

        {/* Tag input */}
        {tagOpen ? (
          <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
            <input
              autoFocus
              type="text"
              value={tagInput}
              onChange={e => setTagInput(e.target.value)}
              onKeyDown={e => {
                if (e.key === "Enter") saveTag();
                if (e.key === "Escape") setTagOpen(false);
              }}
              placeholder="add a tag, then ⏎"
              style={{
                flex: 1,
                padding: "6px 10px",
                borderRadius: 999,
                border: "0.5px solid var(--hair)",
                background: "var(--card)",
                color: "var(--ink)",
                fontSize: 12,
                fontFamily: "var(--font-text)",
                outline: "none",
              }}
            />
            <Btn kind="ghost" onClick={() => setTagOpen(false)}>Cancel</Btn>
            <Btn kind="primary" onClick={saveTag}>Save</Btn>
          </div>
        ) : (
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
            <Btn kind="primary" icon="↗" onClick={() => setToast("Opened Memory pile in Notion")}>
              Open in Notion
            </Btn>
            <Btn kind="ghost" onClick={() => setTagOpen(true)}>+ Tag</Btn>
            <Btn kind="ghost" onClick={() => onNavigate && onNavigate("voice-photos")}>
              Ask about this ↗
            </Btn>
            {/* tags row */}
            <div style={{ display: "flex", gap: 4, marginLeft: "auto", flexWrap: "wrap" }}>
              {[...photo.tags, savedTags[photo.id]].filter(Boolean).map((t, i) => (
                <Tag key={i} tone={t === "compost-sighting" ? "sage" : "default"}>#{t}</Tag>
              ))}
            </div>
          </div>
        )}

        {toast && (
          <NotchToast onDone={() => setToast(null)} duration={1800}>
            {toast}
          </NotchToast>
        )}
      </div>
    </Notch>
  );
}

Object.assign(window, { CueScene, DraftsScene, VoiceScene, PhotosScene, GmailIcon, GoogleMeetIcon });
