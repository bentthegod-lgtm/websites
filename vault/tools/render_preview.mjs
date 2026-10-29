// Renders build/preview.json (from tools/export_preview.luau) to PNGs with three.js in
// headless Chromium (Playwright). Rough approximation of Roblox lighting - for checking
// layout, silhouettes and colours only. Usage (from vault/):
//   node tools/render_preview.mjs build/preview.json build/
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const [jsonPath = "build/preview.json", outDir = "build"] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const S = 150; // GameConfig.DepthSpacing
const VIEWS = [];
const names = ["b1", "b2", "b3", "b4", "b5", "b6", "b7"];
names.forEach((n, i) => {
	const y = -i * S;
	VIEWS.push({ name: `preview-${n}-arrival`, groups: ["world", "loot", "action"], eye: [0, y + 9, -64], target: [0, y + 4, 30], fov: 70, sky: 0x101014 });
	VIEWS.push({ name: `preview-${n}-chamber`, groups: ["world", "loot", "action"], eye: [-50, y + 17, -32], target: [12, y + 2, 40], fov: 70, sky: 0x101014 });
	VIEWS.push({ name: `preview-${n}-stacks`, groups: ["world", "loot", "action"], eye: [0, y + 7, -17], target: [0, y + 3.5, -30], fov: 60, sky: 0x101014 });
});
VIEWS.push({ name: "preview-b1-exit", groups: ["world", "loot"], eye: [-6, 9, 63], target: [10, 6, 78], fov: 70, sky: 0x101014 });
VIEWS.push({ name: "preview-b1-deposit", groups: ["world", "loot"], eye: [-20, 8, -40], target: [-30, 4, -60], fov: 60, sky: 0x101014 });
VIEWS.push({ name: "preview-b1-elevator", groups: ["world"], eye: [0, 6, -74], target: [0, 5, -92], fov: 70, sky: 0x101014 });
VIEWS.push({ name: "preview-b7-entrance", groups: ["world", "loot"], eye: [0, -900 + 8, -60], target: [0, -900 + 10, 0], fov: 70, sky: 0x101014 });
VIEWS.push({ name: "preview-catalog", groups: ["sheet"], eye: [3000, 25, 31], target: [3000, 0, 3], fov: 52, sky: 0x2a2c33 });
VIEWS.push({ name: "preview-stack-modes", groups: ["sheet"], eye: [3000, 9, 52], target: [3000, 4, 34], fov: 55, sky: 0x2a2c33 });


function script(view) {
	const parts = view.groups.flatMap((g) => data[g]);
	return `
(function(){
const parts = ${JSON.stringify(parts)};
const W = 1600, H = 900;
const renderer = new THREE.WebGLRenderer({canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true});
renderer.setSize(W, H);
renderer.shadowMap.enabled = false;
const scene = new THREE.Scene();
scene.background = new THREE.Color(${view.sky});
scene.fog = new THREE.Fog(${view.sky}, 260, 900);
scene.add(new THREE.HemisphereLight(0xfff4e6, 0x55504a, 1.25));
scene.add(new THREE.AmbientLight(0xffffff, 0.25));
const sun = new THREE.DirectionalLight(0xfff0dc, 0.55);
sun.position.set(-200, 160, 120); sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
const sc = sun.shadow.camera; sc.left = -420; sc.right = 420; sc.top = 420; sc.bottom = -420; sc.far = 1400;
scene.add(sun);
function wedge(sx, sy, sz) {
	const g = new THREE.BufferGeometry();
	const x = sx/2, y = sy/2, z = sz/2;
	const v = [ -x,-y,-z, x,-y,-z, x,-y,z, -x,-y,z, -x,y,z, x,y,z ];
	const idx = [0,1,2, 0,2,3, 3,2,5, 3,5,4, 0,4,5, 0,5,1, 0,3,4, 1,5,2];
	g.setAttribute('position', new THREE.Float32BufferAttribute(v, 3));
	g.setIndex(idx); g.computeVertexNormals(); return g;
}
for (const p of parts) {
	const [sx, sy, sz] = p.s;
	let geo;
	if (p.sh === 'Cylinder') { geo = new THREE.CylinderGeometry(Math.min(sy, sz)/2, Math.min(sy, sz)/2, sx, 20); geo.rotateZ(Math.PI/2); }
	else if (p.sh === 'Ball') { geo = new THREE.SphereGeometry(Math.min(sx, sy, sz)/2, 18, 12); }
	else if (p.sh === 'Wedge') { geo = wedge(sx, sy, sz); }
	else { geo = new THREE.BoxGeometry(sx, sy, sz); }
	const color = new THREE.Color(p.c[0]/255, p.c[1]/255, p.c[2]/255);
	let mat;
	if (p.m === 'Neon') mat = new THREE.MeshBasicMaterial({color});
	else if (p.m === 'Glass') mat = new THREE.MeshStandardMaterial({color, roughness: 0.1, metalness: 0.3, transparent: true, opacity: Math.max(0.25, 1 - p.t)});
	else if (p.m === 'ForceField') mat = new THREE.MeshBasicMaterial({color, transparent: true, opacity: 0.25});
	else mat = new THREE.MeshStandardMaterial({color, roughness: (p.m === 'Metal' || p.m === 'DiamondPlate') ? 0.35 : 0.8, metalness: (p.m === 'Metal' || p.m === 'DiamondPlate') ? 0.45 : 0.02});
	if (p.t > 0 && p.m !== 'ForceField') { mat.transparent = true; mat.opacity = 1 - p.t; }
	const mesh = new THREE.Mesh(geo, mat);
	mesh.position.set(p.p[0], p.p[1], p.p[2]);
	mesh.rotation.set(p.o[0], p.o[1], p.o[2], 'YXZ');
	mesh.castShadow = sx * sy * sz > 0.5; mesh.receiveShadow = true;
	scene.add(mesh);
}
const cam = new THREE.PerspectiveCamera(${view.fov}, W/H, 0.5, 3000);
cam.position.set(${view.eye.join(",")}); cam.lookAt(${view.target.join(",")});
renderer.render(scene, cam);
window.__done = true;
})();`;
}

const browser = await chromium.launch({ args: ["--use-gl=swiftshader", "--enable-unsafe-swiftshader"] });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
await page.setContent(`<!doctype html><html><body style="margin:0"><canvas id="c"></canvas></body></html>`);
await page.addScriptTag({ url: "https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js" });
for (const view of VIEWS.filter((v) => !process.env.ONLY || v.name.includes(process.env.ONLY))) {
	await page.evaluate(script(view));
	await page.waitForFunction(() => window.__done === true, null, { timeout: 120000 });
	await page.evaluate(() => { window.__done = false; });
	const file = path.join(outDir, view.name + ".png");
	await page.locator("#c").screenshot({ path: file });
	console.log("wrote " + file);
}
await browser.close();
