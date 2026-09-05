# Render the launch video (terminal)

The in-browser exporter is producing broken files. This path renders the
video **frame by frame in headless Chrome and encodes with ffmpeg** — no
in-browser exporter involved, deterministic output, real H.264.

## Files

| File | What |
|---|---|
| `Compost Launch Video.html` | **self-contained** — every script, image and font inlined. Works offline, double-click to watch. This is what the renderer loads. |
| `render-video.mjs` | Puppeteer + ffmpeg renderer |
| `Launch Video.html` + `*.jsx` + `assets/` | the editable source (multi-file) |
| `VOICE-OVER.md` | narration script, timed to the sections |

## One-time setup

```bash
cd design/launch-video
npm init -y
npm i puppeteer
npx puppeteer browsers install chrome

# ffmpeg
brew install ffmpeg          # macOS
# sudo apt install ffmpeg    # Debian/Ubuntu
```

## Render

```bash
node render-video.mjs
```

Writes `compost-launch.mp4` (1920×1080, 30fps, H.264 yuv420p +faststart —
plays in QuickTime, Slack, Keynote, Premiere, browsers).

Takes a few minutes: it renders ~1470 individual frames.

### Options

```bash
node render-video.mjs --fps=60                    # smoother
node render-video.mjs --scale=2                   # 4K (3840x2160)
node render-video.mjs --out=out/launch-4k.mp4 --scale=2 --fps=60
node render-video.mjs --gif                       # also write a 12fps GIF
node render-video.mjs --frames=./frames           # keep the PNG sequence
```

Keeping the PNG sequence is useful if you'd rather cut it in Premiere /
Resolve / Final Cut — import `frames/f%05d.png` as an image sequence at
the same fps.

## If a frame looks wrong

Render a single frame and inspect it:

```bash
node -e '
import("puppeteer").then(async ({default:p}) => {
  const b = await p.launch({headless:"new"});
  const pg = await b.newPage();
  await pg.setViewport({width:1920,height:1080});
  await pg.goto("file://"+process.cwd()+"/Compost Launch Video.html",{waitUntil:"networkidle0"});
  await new Promise(r=>setTimeout(r,2000));
  const t = +process.argv[1] || 12;
  await pg.evaluate(time => document.querySelector("[data-om-exportable-video-with-duration-secs]")
    .dispatchEvent(new CustomEvent("data-om-seek-to-time-frame",{detail:{time,sync:true}})), t);
  await new Promise(r=>setTimeout(r,300));
  await pg.screenshot({path:`frame-${t}.png`});
  await b.close();
});' 12
```

## Timeline

Section durations live in `window.OM_SCENES` at the top of
`Launch Video.html` (the multi-file source). Edit a `dur`, re-run
`render-video.mjs`, done.

```
Intro 6s · Launch 4s · Cue 8s · Drafts 8s · Voice 8s · Memory 9s · Vision 6s  = 49s
```

After editing the source, regenerate the self-contained file — or just
point the renderer at the source instead:

```bash
node render-video.mjs --in="./Launch Video.html"
```

(The multi-file version needs its sibling `.jsx` files and `assets/`
present, and pulls React from a CDN, so it needs network. The
self-contained one doesn't.)
