// render-video.mjs — render "Compost Launch Video" to an MP4, frame by frame.
//
// This bypasses any in-browser video exporter: it drives the animation's own
// seek event in headless Chrome, screenshots every frame as a lossless PNG,
// then hands the sequence to ffmpeg. Deterministic — every frame is a
// synchronous render at an exact timestamp.
//
//   npm i puppeteer            # or: npx puppeteer browsers install chrome
//   brew install ffmpeg        # macOS
//   node render-video.mjs
//
// Flags:
//   --in=<file>     source HTML            (default: ./Compost Launch Video.html)
//   --out=<file>    output video           (default: ./compost-launch.mp4)
//   --fps=<n>       frames per second      (default: 30)
//   --scale=<n>     1 = 1920x1080, 2 = 4K  (default: 1)
//   --frames=<dir>  keep the PNG sequence  (default: temp dir, deleted)
//   --gif           also write a 12fps GIF next to the mp4

import { existsSync, mkdirSync, rmSync } from "node:fs";
import { spawn } from "node:child_process";
import { resolve, dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import puppeteer from "puppeteer";

const arg = (k, d) => {
  const hit = process.argv.find(a => a.startsWith(`--${k}=`));
  return hit ? hit.split("=").slice(1).join("=") : d;
};
const has = k => process.argv.includes(`--${k}`);

const IN = resolve(arg("in", "./Compost Launch Video.html"));
const OUT = resolve(arg("out", "./compost-launch.mp4"));
const FPS = +arg("fps", 30);
const SCALE = +arg("scale", 1);
const KEEP = arg("frames", null);
const FRAMES = KEEP ? resolve(KEEP) : join(tmpdir(), `compost-frames-${Date.now()}`);

if (!existsSync(IN)) { console.error(`✗ source not found: ${IN}`); process.exit(1); }
mkdirSync(FRAMES, { recursive: true });

const run = (cmd, args) => new Promise((ok, bad) => {
  const p = spawn(cmd, args, { stdio: "inherit" });
  p.on("error", bad);
  p.on("close", c => (c === 0 ? ok() : bad(new Error(`${cmd} exited ${c}`))));
});

console.log(`→ source   ${IN}`);
console.log(`→ frames   ${FRAMES}`);
console.log(`→ output   ${OUT}  @ ${FPS}fps, ${1920 * SCALE}x${1080 * SCALE}`);

const browser = await puppeteer.launch({
  headless: "new",
  args: ["--allow-file-access-from-files", "--font-render-hinting=none", "--force-color-profile=srgb", "--hide-scrollbars"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: SCALE });
page.on("console", m => { if (m.type() === "error") console.log("  [page error]", m.text()); });

await page.goto(pathToFileURL(IN).href, { waitUntil: "networkidle0", timeout: 120000 });

// Wait for the animation stage to mount and every image to decode.
await page.waitForSelector("[data-om-exportable-video-with-duration-secs]", { timeout: 60000 });
await page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all(Array.from(document.images).map(i => i.complete ? 1 : i.decode().catch(() => 1)));
});
await new Promise(r => setTimeout(r, 1200));  // let layout measurement settle

// Hide anything that is chrome, not content.
await page.addStyleTag({ content: `
  [data-om-playback-bar], .twk-panel, .twk-fab, [data-om-diagnostics] { display: none !important; }
  body { margin: 0 !important; background: #f7f6f3 !important; }
` });

const DURATION = await page.$eval("[data-om-exportable-video-with-duration-secs]",
  el => +el.getAttribute("data-om-exportable-video-with-duration-secs"));
const TOTAL = Math.round(DURATION * FPS);
console.log(`→ duration ${DURATION}s = ${TOTAL} frames\n`);

const stage = await page.$("[data-om-exportable-video-with-duration-secs]");

for (let f = 0; f < TOTAL; f++) {
  const t = f / FPS;
  await page.evaluate((time, frame) => {
    const el = document.querySelector("[data-om-exportable-video-with-duration-secs]");
    el.dispatchEvent(new CustomEvent("data-om-seek-to-time-frame", {
      detail: { time, frame, sync: true, playing: false },
    }));
  }, t, f);
  // two rAFs: one for React's commit, one for the browser's paint
  await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  await stage.screenshot({
    path: join(FRAMES, `f${String(f).padStart(5, "0")}.png`),
    captureBeyondViewport: false,
    optimizeForSpeed: true,
  });
  if (f % FPS === 0) process.stdout.write(`\r  rendered ${f}/${TOTAL} frames (${(t).toFixed(0)}s)   `);
}
process.stdout.write(`\r  rendered ${TOTAL}/${TOTAL} frames             \n`);
await browser.close();

console.log("\n→ encoding with ffmpeg…");
mkdirSync(dirname(OUT), { recursive: true });
await run("ffmpeg", [
  "-y", "-framerate", String(FPS),
  "-i", join(FRAMES, "f%05d.png"),
  "-c:v", "libx264", "-preset", "slow", "-crf", "17",
  "-pix_fmt", "yuv420p",                     // required for QuickTime / Slack / Keynote
  "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", // h264 needs even dimensions
  "-movflags", "+faststart",
  OUT,
]);

if (has("gif")) {
  const gif = OUT.replace(/\.\w+$/, ".gif");
  const pal = join(FRAMES, "palette.png");
  console.log("\n→ encoding GIF…");
  await run("ffmpeg", ["-y", "-i", OUT, "-vf", "fps=12,scale=1280:-1:flags=lanczos,palettegen=stats_mode=diff", pal]);
  await run("ffmpeg", ["-y", "-i", OUT, "-i", pal, "-lavfi", "fps=12,scale=1280:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3", gif]);
  console.log(`✓ ${gif}`);
}

if (!KEEP) rmSync(FRAMES, { recursive: true, force: true });
console.log(`\n✓ done → ${OUT}`);
