// Store thumbnail (1920x1080) and game icon (512x512): a three.js render of the real game
// models (tools/export_preview.luau) with the title and pitch laid over it in HTML.
// Usage (from thin-ice/):  node tools/store_art.mjs build/preview.json .
import fs from "node:fs";
import path from "node:path";
import { sceneScript, openPage } from "./render_preview.mjs";

const [, , , outDir = "."] = process.argv;

async function render3d(page, view, W, H) {
	await page.setViewportSize({ width: W, height: H });
	await page.setContent(`<!doctype html><html><body style="margin:0;background:#000"><canvas id="c"></canvas></body></html>`);
	await page.addScriptTag({ url: "https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js" });
	await page.evaluate(sceneScript(view, W, H));
	await page.waitForFunction(() => window.__done === true, null, { timeout: 180000 });
	const buf = await page.locator("#c").screenshot();
	return "data:image/png;base64," + buf.toString("base64");
}

const FONT = `'Inter Display','Inter',Arial,sans-serif`;

const { browser, page } = await openPage(1920, 1080);

// Thumbnail: the team on the Thin Flats, the Antlered listening behind them.
const scene = await render3d(page, { groups: ["world", "poster"], lights: "posterLights", eye: [-4, 5, 98], target: [-14, 10, 150], fov: 46 }, 1920, 1080);
await page.setContent(`<!doctype html><html><body style="margin:0">
<div style="position:relative;width:1920px;height:1080px;overflow:hidden;background:url(${scene}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(6,12,32,.92) 0%,rgba(6,12,32,.7) 34%,rgba(6,12,32,0) 58%)"></div>
  <div style="position:absolute;inset:0;background:radial-gradient(ellipse at 70% 45%,rgba(0,0,0,0) 40%,rgba(2,6,20,.55) 100%)"></div>
  <div style="position:absolute;left:90px;top:150px;width:900px;color:#eef6ff;font-family:${FONT}">
    <div style="display:inline-block;padding:10px 22px;border:3px solid #9ad8ff;border-radius:12px;color:#9ad8ff;font-size:34px;font-weight:800;letter-spacing:4px">CO-OP SURVIVAL HORROR</div>
    <div style="font-size:190px;font-weight:900;white-space:nowrap;line-height:1;margin-top:26px;letter-spacing:2px;text-shadow:0 0 40px rgba(150,220,255,.55),0 8px 0 #2a4f86">THIN ICE</div>
    <div style="font-family:${FONT};font-weight:700;font-size:48px;margin-top:28px;color:#d6e9ff;line-height:1.25">Cross the frozen lake.<br>Don't wake what's listening.</div>
    <div style="font-family:${FONT};font-weight:700;font-size:40px;margin-top:44px;line-height:1.7;color:#fff">
      <div>&#10052; Every step can crack the ice</div>
      <div>&#10052; A blind monster hunts by sound</div>
      <div>&#10052; Thaw friends &middot; 1-6 players</div>
    </div>
  </div>
</div></body></html>`);
await page.screenshot({ path: path.join(outDir, "thumbnail-1920x1080.png"), clip: { x: 0, y: 0, width: 1920, height: 1080 } });
console.log("wrote thumbnail-1920x1080.png");

// Icon: the Antlered's head and antlers from below, with the title.
const icon = await render3d(page, { groups: ["world", "poster"], lights: "posterLights", eye: [-14, 6, 132], target: [-18, 12.5, 150], fov: 46 }, 512, 512);
await page.setViewportSize({ width: 512, height: 512 });
await page.setContent(`<!doctype html><html><body style="margin:0">
<div style="position:relative;width:512px;height:512px;overflow:hidden;background:url(${icon}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(0deg,rgba(6,12,32,.95) 0%,rgba(6,12,32,.2) 38%,rgba(6,12,32,0) 60%)"></div>
  <div style="position:absolute;left:0;right:0;bottom:30px;text-align:center;color:#eef6ff;font-family:${FONT};font-weight:900;font-size:88px;letter-spacing:1px;text-shadow:0 0 22px rgba(150,220,255,.6),0 5px 0 #2a4f86">THIN ICE</div>
</div></body></html>`);
await page.screenshot({ path: path.join(outDir, "icon-512.png"), clip: { x: 0, y: 0, width: 512, height: 512 } });
console.log("wrote icon-512.png");
await browser.close();
if (!fs.existsSync(path.join(outDir, "icon-512.png"))) process.exit(1);
