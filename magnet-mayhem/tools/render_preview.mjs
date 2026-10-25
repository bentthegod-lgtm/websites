// Renders build/preview.json (from tools/export_preview.luau) to PNGs with three.js in
// headless Chromium (Playwright). Rough approximation of Roblox lighting - for checking
// layout, silhouettes and colours only. Usage (from magnet-mayhem/):
//   node tools/render_preview.mjs build/preview.json build/
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const [jsonPath = "build/preview.json", outDir = "build"] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const VIEWS = [
	{ name: "preview-rustyard", groups: ["world", "scrap", "hero"], eye: [-170, 150, 210], target: [60, 0, -20], fov: 50, sky: 0xe6c79a },
	{ name: "preview-shredder", groups: ["world", "scrap", "hero"], eye: [30, 16, 20], target: [0, 6, -26], fov: 55, sky: 0xe6c79a },
	{ name: "preview-player", groups: ["world", "scrap", "hero"], eye: [16, 9, 8], target: [6, 5, -6], fov: 50, sky: 0xe6c79a },
	{ name: "preview-metro", groups: ["world", "scrap"], eye: [205, 40, 60], target: [320, 0, -10], fov: 55, sky: 0x9a9ac0 },
	{ name: "preview-catalog", groups: ["sheet"], eye: [2036, 30, -38], target: [2036, 2, 16], fov: 45, sky: 0x2a2c33 },
];

function script(view) {
	const parts = view.groups.flatMap((g) => data[g]);
	return `
(function(){
const parts = ${JSON.stringify(parts)};
const W = 1600, H = 900;
const renderer = new THREE.WebGLRenderer({canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true});
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
const scene = new THREE.Scene();
scene.background = new THREE.Color(${view.sky});
scene.fog = new THREE.Fog(${view.sky}, 250, 900);
scene.add(new THREE.HemisphereLight(0xfff1dc, 0x6a5a48, 0.9));
const sun = new THREE.DirectionalLight(0xffd9a0, 1.25);
sun.position.set(-200, 160, 120); sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
const sc = sun.shadow.camera; sc.left = -320; sc.right = 320; sc.top = 320; sc.bottom = -320; sc.far = 900;
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
for (const view of VIEWS) {
	await page.evaluate(script(view));
	await page.waitForFunction(() => window.__done === true, null, { timeout: 120000 });
	await page.evaluate(() => { window.__done = false; });
	const file = path.join(outDir, view.name + ".png");
	await page.locator("#c").screenshot({ path: file });
	console.log("wrote " + file);
}
await browser.close();
