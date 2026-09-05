// render-cdp.mjs — deterministic MP4 render via CDP virtual time.
//
// The self-contained export has no seek hooks, so we control the clock itself:
// Emulation.setVirtualTimePolicy pauses ALL time in the renderer (rAF, timers,
// performance.now, CSS animations) and advances it in exact per-frame budgets.
//
//   node render-cdp.mjs --in=<html> --out=<mp4> [--fps=30] [--dur=44] [--lead=0]

import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { resolve, dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import puppeteer from "puppeteer";

const arg = (k, d) => {
  const hit = process.argv.find(a => a.startsWith(`--${k}=`));
  return hit ? hit.split("=").slice(1).join("=") : d;
};

const IN = resolve(arg("in", "./Compost Launch Video.html"));
const OUT = resolve(arg("out", "./compost-launch.mp4"));
const FPS = +arg("fps", 30);
const DUR = +arg("dur", 50);
const LEAD = +arg("lead", 0);        // virtual seconds to burn before t=0 capture
const FRAMES = arg("frames", null) ? resolve(arg("frames")) : join(tmpdir(), `compost-cdp-${Date.now()}`);
const KEEP = !!arg("frames", null);

if (!existsSync(IN)) { console.error(`missing: ${IN}`); process.exit(1); }
mkdirSync(FRAMES, { recursive: true });

const run = (cmd, args) => new Promise((ok, bad) => {
  const p = spawn(cmd, args, { stdio: "inherit" });
  p.on("error", bad);
  p.on("close", c => (c === 0 ? ok() : bad(new Error(`${cmd} exited ${c}`))));
});

const browser = await puppeteer.launch({
  headless: "new",
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  timeout: 120000,
  protocolTimeout: 300000,
  args: ["--allow-file-access-from-files", "--font-render-hinting=none", "--force-color-profile=srgb", "--hide-scrollbars",
    "--run-all-compositor-stages-before-draw", "--disable-new-content-rendering-timeout",
    "--disable-threaded-animation", "--disable-threaded-scrolling", "--disable-checker-imaging",
    "--disable-image-animation-resync"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
page.on("console", m => { if (m.type() === "error") console.log("  [page error]", m.text().slice(0, 200)); });


// Freeze the page's clock at 0 until we arm it — the animation timeline reads
// time-since-load, and app boot under virtual time would otherwise eat the intro.
await page.evaluateOnNewDocument(() => {
  const realPerfNow = performance.now.bind(performance);
  const realDateNow = Date.now.bind(Date);
  const realRaf = window.requestAnimationFrame.bind(window);
  let perfBase = null, dateBase = null;
  performance.now = () => (perfBase === null ? 0 : realPerfNow() - perfBase);
  Date.now = () => (dateBase === null ? 1700000000000 : 1700000000000 + realDateNow() - dateBase);
  window.requestAnimationFrame = (cb) => realRaf(() => cb(performance.now()));
  window.__armClock = () => { perfBase = realPerfNow(); dateBase = realDateNow(); };
});

const cdp = await page.createCDPSession();
const expired = () => new Promise(r => cdp.once("Emulation.virtualTimeBudgetExpired", r));

// Grant `ms` of virtual time and wait for it to be consumed.
const advance = async (ms) => {
  const done = expired();
  await cdp.send("Emulation.setVirtualTimePolicy", {
    policy: "pauseIfNetworkFetchesPending",
    budget: ms,
    maxVirtualTimeTaskStarvationCount: 1000000,
  });
  await done;
};

// Pause the clock BEFORE the page runs a single script, then navigate.
await cdp.send("Emulation.setVirtualTimePolicy", { policy: "pause" });
const nav = page.goto(pathToFileURL(IN).href, { waitUntil: "load", timeout: 120000 }).catch(() => {});

// Boot the app under virtual time until the bundler overlay is gone and the app has mounted.
let booted = false;
for (let i = 0; i < 120; i++) {
  await advance(500);
  booted = await page.evaluate(() => {
    const loading = document.querySelector("#__bundler_loading");
    const root = document.querySelector("#root");
    return (!loading || loading.offsetParent === null) && !!root && root.children.length > 0;
  }).catch(() => false);
  if (booted) break;
}
await nav;
if (!booted) { console.error("app never mounted under virtual time"); await browser.close(); process.exit(1); }
console.log("→ app mounted under virtual time");

await page.evaluate(async () => {
  await document.fonts.ready.catch(() => {});
  await Promise.all(Array.from(document.images).map(i => i.complete ? 1 : i.decode().catch(() => 1)));
});

// Hide editor chrome; force the stage background.
await page.addStyleTag({ content: `
  [data-om-playback-bar], .twk-panel, .twk-fab, [data-om-diagnostics], #__bundler_loading { display: none !important; }
  body { margin: 0 !important; background: #f7f6f3 !important; }
` });

// Settle a bit more under the frozen clock.
await advance(1000);

// Hide any fixed/absolute overlay that is not part of the .lv stage (playback bar etc.)
const hidden = await page.evaluate(() => {
  const out = [];
  // Anything stacked at the bottom-center scrubber position goes, container and all.
  for (const [x, y] of [[960, 1062], [960, 1055], [530, 1062], [1390, 1062]]) {
    for (const el of document.elementsFromPoint(x, y)) {
      if (el === document.documentElement || el === document.body) continue;
      if (el.classList.contains("lv") || el.querySelector(".lv")) continue;
      if (el.closest(".lv")) break;  // stage content — never hide
      el.style.setProperty("display", "none", "important");
      out.push(`pt ${el.tagName}.${String(el.className).slice(0, 30)}`);
      break;
    }
  }
  const stage = document.querySelector(".lv");
  for (const el of Array.from(document.body.querySelectorAll("*"))) {
    if (stage && (stage === el || stage.contains(el) || el.contains(stage))) continue;
    const cs = getComputedStyle(el);
    if ((cs.position === "fixed" || cs.position === "absolute") && cs.display !== "none") {
      const r = el.getBoundingClientRect();
      if (r.width > 0 && r.height > 0 && r.height < 200) {
        el.style.setProperty("display", "none", "important");
        out.push(`${el.tagName}.${String(el.className).slice(0, 40)} @${Math.round(r.top)},${Math.round(r.left)} ${Math.round(r.width)}x${Math.round(r.height)}`);
      }
    }
  }
  return out;
});
console.log("→ hid overlays:", JSON.stringify(hidden));

// Arm the clock: the animation timeline starts NOW, at capture frame 0.
await page.evaluate(() => window.__armClock());

if (LEAD > 0) await advance(Math.round(LEAD * 1000));

const TOTAL = Math.round(DUR * FPS);
console.log(`→ capturing ${TOTAL} frames @ ${FPS}fps (${DUR}s)`);

let granted = 0;
for (let f = 0; f < TOTAL; f++) {
  const shot = await cdp.send("Page.captureScreenshot", { format: "png" });
  writeFileSync(join(FRAMES, `f${String(f).padStart(5, "0")}.png`), Buffer.from(shot.data, "base64"));
  const target = Math.round(((f + 1) * 1000) / FPS);
  const step = target - granted;
  granted = target;
  await advance(step);
  if (f % FPS === 0) process.stdout.write(`\r  ${f}/${TOTAL} (${(f / FPS).toFixed(0)}s)   `);
}
process.stdout.write(`\r  ${TOTAL}/${TOTAL} frames        \n`);
await browser.close();

console.log("→ encoding…");
mkdirSync(dirname(OUT), { recursive: true });
await run("ffmpeg", [
  "-y", "-v", "error", "-framerate", String(FPS),
  "-i", join(FRAMES, "f%05d.png"),
  "-c:v", "libx264", "-preset", "slow", "-crf", "17",
  "-pix_fmt", "yuv420p",
  "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
  "-movflags", "+faststart",
  OUT,
]);
if (!KEEP) rmSync(FRAMES, { recursive: true, force: true });
console.log(`✓ ${OUT}`);
