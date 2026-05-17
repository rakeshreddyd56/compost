# Interactions — Compost Notch v0.4

> Timing, easing, and state machines for every animated surface.

All values are gated through `GardenStyle.reduceMotion` — when reduce
motion is on, durations become 0 and `repeatForever` becomes a no-op.

## Global rules

- **Spring response**: `0.55s @ 0.78 damping` for expand,
  `0.40s @ 0.85 damping` for collapse
- **Easing**: `cubic-bezier(0.22, 1, 0.36, 1)` for everything else
- **No bounce > 1.05×** anywhere — Compost is calm, not playful

## Notch shell

| Trigger | Animation | Duration |
|---|---|---|
| Idle → Peek | width 220→300, height 34→38, corner 16→18 | `springExpand` |
| Peek → Expanded | width 300→440 (or 540 wide), height auto, corner 18→22 | `springExpand` |
| Expanded → Peek | reverse | `springCollapse` |
| Peek scenario change (no resize) | content crossfade 180ms | `easeOut` |

## Peek

| Trigger | Animation |
|---|---|
| Imminent cue (<10m) | leaf icon scale 1.0↔1.15, `pulse` |
| Live activity (voice) | red dot opacity 0.4↔1, scale 0.8↔1.1, `pulse` |
| Multi-invoice rotate | label slides left -8pt fade-out, replacement slides in from right +8pt, total 220ms `easeOut`, repeats every 4s |

## Cue scene

| Trigger | Animation |
|---|---|
| Mascot mood swap (calm → alert when <5m) | crossfade 240ms `easeOut` |
| Checklist item tap | checkbox fill + scale 0.95→1 (60ms in, 120ms back) |
| All items checked | mascot one-shot `.bobble` (0.7s spring) + mood → `.alert` |
| Open in Notion click | button scale 0.97 on press (100ms); toast slides up from bottom |
| Join Meet click | button scale 0.97; toast `Joining Google Meet…` |
| Snooze 5m | time strip increments by 5 with 220ms `easeOut` slide; toast `Snoozed — back in 5m` |
| Ask Compost click | scene fades; voice surface springs in (`springExpand`) |

## Drafts scene

| Trigger | Animation |
|---|---|
| Tap draft row | bg color 200ms `easeOut`, border 200ms `easeOut` |
| Tone pill tap | pill bg 180ms `easeOut`; calmer-text container fades to 0.4 opacity, swaps text, fades back to 1.0 over 220ms total |
| `↻ rephrase` click | calmer pane shows a shimmer overlay (linear-gradient at -45°, animated x: -100% → 200% over 1.2s) until response lands |
| Use calmer | mascot `.bobble` once; row collapses 320ms `springCollapse` |
| Inline error | shake the diff pane 6px once (translate -3 → 3 → -2 → 2 → 0, 280ms) — gate on reduce-motion |

## Voice scene

| Trigger | Animation |
|---|---|
| Mascot halo | radial gradient scale 0.95↔1.05, opacity 0.5↔1, `glow` (2.5s infinite) |
| State pill dot | `pulse` (1s infinite) |
| Waveform | bars animate continuously via `CADisplayLink`; amplitude maps from real RMS during `listening`, from a 2-sin synthetic mix during `thinking`/`speaking` |
| Caret in transcript | 1s steps(1) infinite blink |
| Mascot bobble on speech start | once per `speaking` transition, 0.7s spring |
| Idle auto-collapse | 4s timer after stage hits `idle`, then `springCollapse` |
| Listening color | waveform + dot transition to `accentRose` 220ms `easeInOut` |
| Thinking color | bars to `sage400` 220ms |
| Speaking color | bars stay `sage400`, mascot bobbles |

## Photos scene

| Trigger | Animation |
|---|---|
| Photo change (auto or manual) | crossfade 220ms `easeOut` |
| Slideshow auto-advance | 3.5s dwell; 5.0s dwell on photos with `mascotReaction` |
| Pause / Play button tap | icon swap 120ms; halt / restart auto-advance timer |
| Prev / Next arrows | photo crossfades; arrows fade in on hover (180ms) |
| Dot tap | active dot width 6→18 200ms `springExpand`; inactive 18→6 |
| Mascot speech bubble appears | slide from top -8px + opacity 0→1, 220ms `springExpand` |
| Mascot bobble (self-sighting frame) | 0.7s spring, fires once per entry |
| Mood crossfade between photos | 240ms `easeOut` on the head mascot |
| + Tag tapped | actions row crossfades to input row 180ms; input gets focus |
| Save tag | toast slides up from bottom 220ms; input row crossfades back |
| Open in Notion | toast `Opened Memory pile in Notion` |
| Ask about this | scene swaps to voice surface with photos script; `springExpand` |
| Voice surface returning to Photos | photos surface springs back in; slideshow resumes at same idx |

## Inter-scene transitions

The notch surface itself swaps via the same `springExpand` /
`springCollapse` envelope:

| Trigger | Path |
|---|---|
| Voice quick-action "What did I miss?" | voice → cue (expanded) |
| Voice quick-action "Read drafts" | voice → drafts (expanded) |
| Voice quick-action "Show photos" | voice → photos (expanded) |
| Cue "Ask Compost ↗" | cue → voice (freeform script) |
| Photos "Ask about this ↗" | photos → voice (photos script) |
| Voice end / Esc | restore the **previous** surface (saved by `enterVoice`) |

## State machines

### Cue (per CueCard)

```
no-cue ── cue arrives ──> peek
peek ── tap or <10m + still <10m elapsed ──> expanded
expanded ── close / 30s idle ──> peek
peek ── currentTime passed ──> archived (out of state)
```

### Drafts (per FrozenDraft)

```
pending → frozen → ready → (reviewed | rejected | expired)
                       ↓
                  tone changes don't change Status
                  (only Active Tone + Rewrite Variants)
```

### Photos (per Photo)

```
peek ── tap ──> expanded(playing)
expanded ── pause ──> expanded(paused) ── play ──> expanded(playing)
expanded ── photo.mascotReaction set ──> speech bubble overlay (no state change)
expanded ── + Tag ──> tagging ── save ──> expanded + toast
expanded ── Ask about this ──> voice(photos script)
voice(photos) ── end ──> expanded (resume at same idx)
```

### Voice

```
       hotkey
idle ──────────> listening
                      │ silence 800ms
                      ↓
                  thinking
                      │ claude.complete returns
                      ↓
                  speaking
                      │ TTS done
                      ↓
                    idle ──────────> (auto-collapse 4s)
                                       │ user speaks
                                       ↓
                                    listening (loop)
```

Voice also has a `quickActionTaken` exit:

```
any-stage ── quick-action button ──> exitVoice() ──> target surface
```

## Reduce motion

When `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true`:

- All durations → 0
- `repeatForever` animations don't run (single static state)
- Mascot `.bobble`, halo `glow`, waveform `glowPulse` all become static
- Crossfades become instant swaps
- Slide-to-confirm becomes a single Approve button + Cancel
  - Important: the slide-to-confirm primitive is **not accessible
    without a fallback**; in reduce-motion + VoiceOver, render a tappable
    button labeled `Approve and pay $2,400` instead

## Haptics

| Moment | Pattern | Surface |
|---|---|---|
| Voice mode start | `.generic` | Voice scene (subtle) |
| Voice mode end | `.alignment` | Voice scene |
| Cue countdown crosses 10m | `.alignment` | Cue scene (only if user is at machine) |
| All checklist items checked | `.levelChange` | Cue scene |
| Self-sighting photo enters viewer | `.alignment` | Photos scene |
| Tag saved successfully | `.generic` | Photos scene |

Use `NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime:)`.
