// Renders build/blobbies.json (from export_blobbies.luau) to PNG contact sheets with three.js
// in headless Chromium. Usage (from snatch-tycoon/):
//   node tools/render_preview.mjs build/blobbies.json <path to three.min.js> build/
// three.min.js: e.g. `npm pack three@0.160.0` and extract package/build/three.min.js.
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

// Set PLAYWRIGHT_MODULE to the playwright package path if it isn't installed next to this file.
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");

const [jsonPath = "build/blobbies.json", threePath, outDir = "build", worldPath] = process.argv.slice(2);
if (!threePath) {
	console.error("usage: node tools/render_preview.mjs <blobbies.json> <three.min.js> <outDir>");
	process.exit(1);
}
const models = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const page_html = `<!doctype html><html><head><style>
body{margin:0;background:#2a1e4a;font-family:Arial Black,Arial,sans-serif}
#labels div{position:absolute;color:#fff;text-align:center;font-size:17px;text-shadow:0 2px 0 #000,0 0 4px #000}
#labels small{display:block;font-size:13px}
</style></head><body><canvas id="c"></canvas><div id="labels"></div></body></html>`;

function sceneScript(sheet, cols, cellW, cellH) {
	return `
(function(){
const sheet = ${JSON.stringify(sheet)};
const cols = ${cols}, cellW = ${cellW}, cellH = ${cellH};
const rows = Math.ceil(sheet.length / cols);
const W = cols * cellW, H = rows * cellH;
const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({canvas, antialias:true, preserveDrawingBuffer:true});
renderer.setSize(W, H);
renderer.setScissorTest(true);
renderer.shadowMap.enabled = true;
const labels = document.getElementById('labels');
sheet.forEach((m, i) => {
	const scene = new THREE.Scene();
	scene.add(new THREE.HemisphereLight(0xffffff, 0x8070a0, 1.6));
	const sun = new THREE.DirectionalLight(0xffffff, 1.6); sun.position.set(-4, 8, -6); scene.add(sun);
	const ground = new THREE.Mesh(new THREE.CylinderGeometry(4.5, 4.5, 0.3, 40), new THREE.MeshStandardMaterial({color: 0xf2eee8}));
	ground.position.y = -0.15; scene.add(ground);
	const ring = new THREE.Mesh(new THREE.CylinderGeometry(4.7, 4.7, 0.18, 40), new THREE.MeshBasicMaterial({color: new THREE.Color(m.rarityColor[0]/255, m.rarityColor[1]/255, m.rarityColor[2]/255)}));
	ring.position.y = -0.3; scene.add(ring);
	m.parts.forEach((p, k) => {
		let geo;
		const [sx, sy, sz] = p.size;
		if (p.shape === 'Ellipsoid') { geo = new THREE.SphereGeometry(0.5, 24, 16); geo.scale(sx, sy, sz); }
		else if (p.shape === 'Ball') { const d = Math.min(sx, sy, sz); geo = new THREE.SphereGeometry(d/2, 24, 16); }
		else if (p.shape === 'Cylinder') { geo = new THREE.CylinderGeometry(Math.min(sy,sz)/2, Math.min(sy,sz)/2, sx, 24); geo.rotateZ(Math.PI/2); }
		else { geo = new THREE.BoxGeometry(sx, sy, sz); }
		let color = new THREE.Color(p.color[0], p.color[1], p.color[2]);
		if (p.rainbow) color = new THREE.Color().setHSL((k * 0.09) % 1, 0.8, 0.6);
		let mat;
		if (p.material === 'Neon') mat = new THREE.MeshBasicMaterial({color});
		else mat = new THREE.MeshStandardMaterial({color, roughness: p.material === 'Metal' ? 0.25 : (p.material === 'Glass' ? 0.05 : 0.55), metalness: p.material === 'Metal' ? 0.7 : 0});
		if (p.transparency > 0) { mat.transparent = true; mat.opacity = 1 - p.transparency; }
		const mesh = new THREE.Mesh(geo, mat);
		const c = p.cf;
		const mtx = new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
		mesh.applyMatrix4(mtx);
		scene.add(mesh);
	});
	const h = Math.max(m.height, 3);
	const cam = new THREE.PerspectiveCamera(35, cellW / cellH, 0.1, 200);
	// Blobbies face -Z; look at them from the front, slightly to the side and above.
	cam.position.set(h * 0.9, h * 0.75, -h * 2.3 - 3);
	cam.lookAt(0, h * 0.42, 0);
	const col = i % cols, row = Math.floor(i / cols);
	const x = col * cellW, y = H - (row + 1) * cellH;
	renderer.setViewport(x, y, cellW, cellH);
	renderer.setScissor(x, y, cellW, cellH);
	renderer.setClearColor(new THREE.Color(0.17 + (i % 2) * 0.02, 0.12, 0.3));
	renderer.render(scene, cam);
	const d = document.createElement('div');
	d.style.left = (col * cellW) + 'px'; d.style.top = (row * cellH + cellH - 46) + 'px'; d.style.width = cellW + 'px';
	d.innerHTML = (m.mutation ? m.mutation + ' ' : '') + m.name + '<small style="color:rgb(' + m.rarityColor.join(',') + ')">' + m.rarity + '</small>';
	labels.appendChild(d);
});
window.__done = [W, H];
})();`;
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
async function sheet(list, cols, cellW, cellH, file) {
	await page.setContent(page_html);
	await page.addScriptTag({ path: threePath });
	await page.addScriptTag({ content: sceneScript(list, cols, cellW, cellH) });
	const [w, h] = await page.evaluate(() => window.__done);
	await page.setViewportSize({ width: w, height: h });
	await page.screenshot({ path: path.join(outDir, file), clip: { x: 0, y: 0, width: w, height: h } });
	console.log("wrote", path.join(outDir, file));
}
await sheet(models.filter((m) => m.mutation === ""), 5, 320, 280, "blobbies-preview.png");
const picks = ["CaptainSquish", "DiscoDumpling", "Gigachonk", "CosmoBlorbo", "Blorbzilla"];
await sheet(models.filter((m) => picks.includes(m.id)), 4, 300, 260, "mutations-preview.png");
if (worldPath) {
	const world = JSON.parse(fs.readFileSync(worldPath, "utf8"));
	const views = [
		{ file: "world-overview.png", eye: [-150, 150, -260], at: [0, 0, -10] },
		{ file: "world-base.png", eye: "plot", at: "plot" },
	];
	for (const v of views) {
		await page.setViewportSize({ width: 1600, height: 900 });
		await page.setContent(page_html);
		await page.addScriptTag({ path: threePath });
		await page.addScriptTag({ content: worldScript(world, v) });
		await page.evaluate(() => window.__done);
		await page.screenshot({ path: path.join(outDir, v.file) });
		console.log("wrote", path.join(outDir, v.file));
	}
}
await browser.close();

function worldScript(world, view) {
	return `
(function(){
const world = ${JSON.stringify(world)};
const view = ${JSON.stringify(view)};
const renderer = new THREE.WebGLRenderer({canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true});
renderer.setSize(1600, 900);
renderer.setClearColor(0x9fd3ff);
const scene = new THREE.Scene();
scene.add(new THREE.HemisphereLight(0xffffff, 0x6a8a5a, 1.5));
const sun = new THREE.DirectionalLight(0xffffff, 1.4); sun.position.set(-60, 120, -40); scene.add(sun);
for (const p of world.parts) {
	let geo; const [sx, sy, sz] = p.size;
	if (p.shape === 'Ellipsoid') { geo = new THREE.SphereGeometry(0.5, 16, 12); geo.scale(sx, sy, sz); }
	else if (p.shape === 'Ball') { geo = new THREE.SphereGeometry(Math.min(sx, sy, sz) / 2, 16, 12); }
	else if (p.shape === 'Cylinder') { geo = new THREE.CylinderGeometry(Math.min(sy, sz) / 2, Math.min(sy, sz) / 2, sx, 20); geo.rotateZ(Math.PI / 2); }
	else { geo = new THREE.BoxGeometry(sx, sy, sz); }
	const color = new THREE.Color(p.color[0], p.color[1], p.color[2]);
	const mat = p.material === 'Neon' ? new THREE.MeshBasicMaterial({color}) : new THREE.MeshStandardMaterial({color, roughness: 0.6, metalness: p.material === 'Metal' ? 0.5 : 0});
	if (p.transparency > 0) { mat.transparent = true; mat.opacity = 1 - p.transparency; }
	const mesh = new THREE.Mesh(geo, mat);
	const c = p.cf;
	mesh.applyMatrix4(new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1));
	scene.add(mesh);
}
const cam = new THREE.PerspectiveCamera(50, 16 / 9, 0.5, 2000);
if (view.eye === 'plot') {
	const c = world.plot1;
	const m = new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
	cam.position.copy(new THREE.Vector3(18, 34, -62).applyMatrix4(m));
	cam.lookAt(new THREE.Vector3(0, 2, 4).applyMatrix4(m));
} else {
	cam.position.set(...view.eye); cam.lookAt(...view.at);
}
renderer.render(scene, cam);
window.__done = true;
})();`;
}
