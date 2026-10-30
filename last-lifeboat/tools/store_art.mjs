// Store thumbnail (1920x1080) and game icon (512x512): a three.js render of the real game
// models (tools/export_preview.luau: the Iron Leviathan mid-sink) with the title, pitch and
// feature callouts laid over it in HTML.
// Usage (from last-lifeboat/):  node tools/store_art.mjs build/preview.json .
import fs from "node:fs";
import path from "node:path";
import { sceneScript, openPage } from "./render_preview.mjs";

const [, , , outDir = "."] = process.argv;
const VIEW = process.env.ART_VIEW ? JSON.parse(process.env.ART_VIEW) : null;
const ICON_VIEW = process.env.ICON_VIEW ? JSON.parse(process.env.ICON_VIEW) : null;

async function render3d(page, view, W, H) {
	await page.setViewportSize({ width: W, height: H });
	await page.setContent(`<!doctype html><html><body style="margin:0;background:#000"><canvas id="c"></canvas></body></html>`);
	await page.addScriptTag({ url: "https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js" });
	await page.evaluate(sceneScript(view, W, H));
	await page.waitForFunction(() => window.__done === true, null, { timeout: 240000 });
	const buf = await page.locator("#c").screenshot();
	return "data:image/png;base64," + buf.toString("base64");
}

const FONT = `'Inter Display','Inter',Arial,sans-serif`;
const { browser, page } = await openPage(1920, 1080);

// Thumbnail: the Iron Leviathan going down by the bow, stern and funnels rising.
const scene = await render3d(page, VIEW || { groups: ["sunk"], lights: "sunkLights", eye: [300, 26, 120], target: [40, 30, -10], fov: 50, water: true }, 1920, 1080);
await page.setContent(`<!doctype html><html><body style="margin:0">
<div style="position:relative;width:1920px;height:1080px;overflow:hidden;background:url(${scene}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(10,18,40,.94) 0%,rgba(10,18,40,.72) 33%,rgba(10,18,40,0) 56%)"></div>
  <div style="position:absolute;left:84px;top:110px;width:960px;color:#fff6e4;font-family:${FONT}">
    <div style="display:inline-block;padding:10px 24px;background:#d64032;border-radius:12px;color:#fff;font-size:36px;font-weight:900;letter-spacing:4px;box-shadow:0 6px 0 #7a1d16">CO-OP ESCAPE</div>
    <div style="font-size:170px;font-weight:900;line-height:.92;margin-top:28px;color:#fff6e4;-webkit-text-stroke:8px #0b1530;paint-order:stroke fill;text-shadow:0 10px 0 #c99a3e">LAST<br>LIFEBOAT</div>
    <div style="font-weight:800;font-size:52px;margin-top:34px;color:#ffd27a">The ship is sinking. One boat. Go!</div>
    <div style="font-weight:800;font-size:40px;margin-top:40px;line-height:1.7;color:#fff">
      <div>&#9875; Climb a ship that tilts with every lurch</div>
      <div>&#9875; Dive flooded halls &middot; watch your air</div>
      <div>&#9875; Grab treasure &middot; revive your crew</div>
      <div>&#9875; 3 giant ships &middot; 1-8 players</div>
    </div>
  </div>
</div></body></html>`);
await page.screenshot({ path: path.join(outDir, "thumbnail-1920x1080.png"), clip: { x: 0, y: 0, width: 1920, height: 1080 } });
console.log("wrote thumbnail-1920x1080.png");

// Icon: the tilted stern and funnels over the water, with the title.
const icon = await render3d(page, ICON_VIEW || { groups: ["sunk"], lights: "sunkLights", eye: [330, 16, 60], target: [40, 34, -60], fov: 40, water: true }, 512, 512);
await page.setViewportSize({ width: 512, height: 512 });
await page.setContent(`<!doctype html><html><body style="margin:0">
<div style="position:relative;width:512px;height:512px;overflow:hidden;background:url(${icon}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(0deg,rgba(10,18,40,.95) 0%,rgba(10,18,40,.3) 40%,rgba(10,18,40,0) 62%)"></div>
  <div style="position:absolute;left:0;right:0;bottom:22px;text-align:center;font-family:${FONT};font-weight:900;font-size:76px;line-height:.92;color:#fff6e4;-webkit-text-stroke:5px #0b1530;paint-order:stroke fill;text-shadow:0 6px 0 #c99a3e">LAST<br>LIFEBOAT</div>
</div></body></html>`);
await page.screenshot({ path: path.join(outDir, "icon-512.png"), clip: { x: 0, y: 0, width: 512, height: 512 } });
console.log("wrote icon-512.png");
await browser.close();
if (!fs.existsSync(path.join(outDir, "icon-512.png"))) process.exit(1);
