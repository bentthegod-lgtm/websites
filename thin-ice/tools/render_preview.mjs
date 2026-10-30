// Renders build/preview.json (from tools/export_preview.luau) to PNGs with three.js in
// headless Chromium (Playwright). A rough night-time approximation of Roblox lighting -
// for checking layout, silhouettes and colours only. Usage (from thin-ice/):
//   node tools/render_preview.mjs build/preview.json build/
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const [jsonPath = "build/preview.json", outDir = "build"] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const zoneZ = (k) => 40 + (k - 1) * 64 + 32;
export const VIEWS = [
	{ name: "preview-lobby", groups: ["world", "action"], eye: [16, 15, -66], target: [0, 3, 50], fov: 62 },
	{ name: "preview-camp", groups: ["world"], eye: [-62, 18, -2], target: [0, 4, 14], fov: 60 },
	{ name: "preview-lake", groups: ["world", "action"], eye: [-150, 150, -40], target: [0, 0, 170], fov: 52 },
	{ name: "preview-plan", groups: ["world", "action"], eye: [0, 430, 168], target: [0, 0, 168.01], fov: 38 },
	{ name: "preview-zone1-pine-shallows", groups: ["world", "action"], eye: [-48, 20, zoneZ(1) - 46], target: [0, 0, zoneZ(1)], fov: 60 },
	{ name: "preview-zone2-thin-flats", groups: ["world", "action"], eye: [-48, 20, zoneZ(2) - 46], target: [0, 0, zoneZ(2)], fov: 60 },
	{ name: "preview-zone3-boulder-isles", groups: ["world", "action"], eye: [-48, 20, zoneZ(3) - 46], target: [0, 0, zoneZ(3)], fov: 60 },
	{ name: "preview-zone4-wreck-bay", groups: ["world", "action"], eye: [-48, 20, zoneZ(4) - 46], target: [0, 0, zoneZ(4)], fov: 60 },
	{ name: "preview-action", groups: ["world", "action"], eye: [-10, 8, 98], target: [3, 6, 160], fov: 55 },
	{ name: "preview-characters", groups: ["sheet"], lights: "sheetLights", eye: [2002, 9, -40], target: [2002, 6, 2], fov: 62, sky: 0x1b2a4c, bright: true },
];

export function sceneScript(view, W, H) {
	const parts = view.groups.flatMap((g) => data[g]);
	const lights = data[view.lights || "lights"];
	return `
(function(){
const parts = ${JSON.stringify(parts)};
const allLights = ${JSON.stringify(lights)};
const W = ${W}, H = ${H};
const renderer = new THREE.WebGLRenderer({canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true});
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
renderer.outputEncoding = THREE.sRGBEncoding;
const scene = new THREE.Scene();
const sky = ${view.sky ?? 0x0b1633};
scene.background = new THREE.Color(sky);
scene.fog = new THREE.Fog(0x14203c, 120, 620);
scene.add(new THREE.HemisphereLight(0x9fb8e8, 0x1c2234, ${view.bright ? 1.1 : 0.62}));
scene.add(new THREE.AmbientLight(0x30406a, 0.35));
const moon = new THREE.DirectionalLight(0xbcd0ff, ${view.bright ? 0.9 : 0.55});
moon.position.set(-160, 220, 260); moon.castShadow = true;
moon.shadow.mapSize.set(4096, 4096);
const sc = moon.shadow.camera; sc.left = -320; sc.right = 320; sc.top = 320; sc.bottom = -320; sc.far = 1200;
scene.add(moon);
const target = new THREE.Vector3(${view.target.join(",")});
const eye = new THREE.Vector3(${view.eye.join(",")});
const lights = allLights.map(l => ({...l, d: Math.min(eye.distanceTo(new THREE.Vector3(...l.p)), target.distanceTo(new THREE.Vector3(...l.p)))}))
	.sort((a, b) => a.d - b.d).slice(0, 14);
for (const l of lights) {
	const pl = new THREE.PointLight(new THREE.Color(l.c[0]/255, l.c[1]/255, l.c[2]/255), l.b * 1.6, l.range * 2.2, 1.6);
	pl.position.set(l.p[0], l.p[1], l.p[2]);
	scene.add(pl);
}
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
	if (p.m === 'Neon') mat = new THREE.MeshBasicMaterial({color, fog: p.p[1] < 150});
	else {
		const shiny = p.m === 'Ice' || p.m === 'Glass' || p.m === 'Metal';
		mat = new THREE.MeshStandardMaterial({color, roughness: shiny ? 0.25 : 0.85, metalness: p.m === 'Metal' ? 0.5 : 0.02});
	}
	if (p.t > 0) { mat.transparent = true; mat.opacity = 1 - p.t; mat.depthWrite = p.t < 0.5; }
	const mesh = new THREE.Mesh(geo, mat);
	mesh.position.set(p.p[0], p.p[1], p.p[2]);
	mesh.rotation.set(p.o[0], p.o[1], p.o[2], 'YXZ');
	mesh.castShadow = sx * sy * sz > 0.5 && p.t < 0.5; mesh.receiveShadow = true;
	scene.add(mesh);
}
// stars
const starGeo = new THREE.BufferGeometry(); const sv = [];
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
for (let i = 0; i < 1400; i++) { const a = rnd() * Math.PI * 2, e = 0.12 + rnd() * 1.3; sv.push(Math.cos(a) * Math.cos(e) * 1400, Math.sin(e) * 1400, Math.sin(a) * Math.cos(e) * 1400); }
starGeo.setAttribute('position', new THREE.Float32BufferAttribute(sv, 3));
const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({color: 0xdfe8ff, size: 2.2, sizeAttenuation: false, fog: false}));
stars.position.copy(eye); scene.add(stars);
const cam = new THREE.PerspectiveCamera(${view.fov}, W/H, 0.5, 3000);
cam.position.copy(eye); cam.lookAt(target);
renderer.render(scene, cam);
window.__done = true;
})();`;
}

export async function openPage(W, H) {
	const browser = await chromium.launch({ args: ["--use-gl=swiftshader", "--enable-unsafe-swiftshader"] });
	const page = await browser.newPage({ viewport: { width: W, height: H } });
	await page.setContent(`<!doctype html><html><body style="margin:0;background:#000"><canvas id="c"></canvas></body></html>`);
	await page.addScriptTag({ url: "https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js" });
	return { browser, page };
}

if (import.meta.url === `file://${process.argv[1]}`) {
	const { browser, page } = await openPage(1600, 900);
	const only = process.env.VIEW;
	for (const view of VIEWS) {
		if (only && !view.name.includes(only)) continue;
		await page.evaluate(sceneScript(view, 1600, 900));
		await page.waitForFunction(() => window.__done === true, null, { timeout: 180000 });
		await page.evaluate(() => { window.__done = false; });
		const file = path.join(outDir, view.name + ".png");
		await page.locator("#c").screenshot({ path: file });
		console.log("wrote " + file);
	}
	await browser.close();
}
