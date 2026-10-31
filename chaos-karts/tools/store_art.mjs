// Placeholder store thumbnail (1920x1080) and game icon (512x512): a three.js render of the
// real game models (tools/export_preview.luau) with the title and callouts over it in HTML.
// The PC polish pass replaces these with proper art (POLISH.md).
// Usage (from chaos-karts/):  node tools/store_art.mjs build/preview.json .
import fs from "node:fs";
import path from "node:path";
import { sceneScript, openPage } from "./render_preview.mjs";

const [, , jsonPath = "build/preview.json", outDir = "."] = process.argv;
const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
const byName = (n) => data.views.find((v) => v.name === n);

async function render3d(page, view, W, H) {
	await page.setViewportSize({ width: W, height: H });
	await page.setContent(`<!doctype html><html><body style="margin:0;background:#000"><canvas id="c"></canvas></body></html>`);
	await page.addScriptTag({ url: "https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js" });
	await page.evaluate(sceneScript(view, W, H));
	await page.waitForFunction(() => window.__done === true, null, { timeout: 300000 });
	const buf = await page.locator("#c").screenshot();
	return "data:image/png;base64," + buf.toString("base64");
}

const FONT = `'Inter Display','Inter',Arial,sans-serif`;
const { browser, page } = await openPage(1920, 1080);

const scene = await render3d(page, byName("preview-parade"), 1920, 1080);
await page.setContent(`<!doctype html><html><body style="margin:0">
<div style="position:relative;width:1920px;height:1080px;overflow:hidden;background:url(${scene}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(20,10,48,.92) 0%,rgba(20,10,48,.6) 34%,rgba(20,10,48,0) 58%)"></div>
  <div style="position:absolute;left:80px;top:100px;width:980px;color:#fff;font-family:${FONT}">
    <div style="display:inline-block;padding:10px 24px;background:#ff46be;border-radius:12px;font-size:36px;font-weight:900;letter-spacing:4px;box-shadow:0 6px 0 #8a1660">KART RACING</div>
    <div style="font-size:176px;font-weight:900;line-height:.9;margin-top:26px;color:#ffd628;-webkit-text-stroke:9px #1a0d36;paint-order:stroke fill;text-shadow:0 12px 0 #ff46be">CHAOS<br>KARTS</div>
    <div style="font-weight:800;font-size:50px;margin-top:30px;color:#3ce6ff">Drift. Boost. Survive the chaos.</div>
    <div style="font-weight:800;font-size:38px;margin-top:36px;line-height:1.7">
      <div>&#9733; 12-kart races &middot; bots fill the grid</div>
      <div>&#9733; Drift for blue, orange, PURPLE boosts</div>
      <div>&#9733; Rooftop leaps, river tunnel, big jumps</div>
      <div>&#9733; Wild world events &middot; final lap = MAX chaos</div>
    </div>
  </div>
</div></body></html>`);
await page.screenshot({ path: path.join(outDir, "thumbnail-1920x1080.png"), clip: { x: 0, y: 0, width: 1920, height: 1080 } });
console.log("wrote thumbnail-1920x1080.png");

const icon = await render3d(page, byName("preview-karts-closeup"), 512, 512);
await page.setViewportSize({ width: 512, height: 512 });
await page.setContent(`<!doctype html><html><body style="margin:0">
<div style="position:relative;width:512px;height:512px;overflow:hidden;background:url(${icon}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(0deg,rgba(20,10,48,.95) 0%,rgba(20,10,48,.25) 42%,rgba(20,10,48,0) 64%)"></div>
  <div style="position:absolute;left:0;right:0;bottom:24px;text-align:center;font-family:${FONT};font-weight:900;font-size:82px;line-height:.9;color:#ffd628;-webkit-text-stroke:5px #1a0d36;paint-order:stroke fill;text-shadow:0 6px 0 #ff46be">CHAOS<br>KARTS</div>
</div></body></html>`);
await page.screenshot({ path: path.join(outDir, "icon-512.png"), clip: { x: 0, y: 0, width: 512, height: 512 } });
console.log("wrote icon-512.png");
await browser.close();
