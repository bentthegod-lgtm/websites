// Renders build/preview.json (from tools/export_preview.luau) to PNGs with three.js in
// headless Chromium (Playwright). A rough dusk approximation of Roblox lighting, with a
// flat translucent sea at Y = 0 standing in for the terrain water - for checking layout,
// silhouettes and colours only. Usage (from last-lifeboat/):
//   node tools/render_preview.mjs build/preview.json build/
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const [jsonPath = "build/preview.json", outDir = "build"] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const X = 70; // GameConfig.World.ShipX
const lev = (z) => -160 + z; // Leviathan stern at z = -160
export const VIEWS = [
	{ name: "preview-lobby", groups: ["lobby", "ship_Gull", "crew"], lights: "lights", eye: [-62, 16, -46], target: [40, 16, 12], fov: 62, water: true },
	{ name: "preview-ship-gull", groups: ["lobby", "ship_Gull"], lights: "lights_Gull", eye: [210, 46, 150], target: [70, 16, 0], fov: 46, water: true },
	{ name: "preview-ship-aurora", groups: ["ship_Aurora"], lights: "lights_Aurora", eye: [250, 60, 210], target: [70, 24, 0], fov: 50, water: true },
	{ name: "preview-ship-leviathan", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [300, 80, 260], target: [70, 30, 0], fov: 52, water: true },
	{ name: "preview-ship-leviathan-stern", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [190, 120, -300], target: [70, 60, -120], fov: 50, water: true },
	{ name: "preview-sinking", groups: ["sunk"], lights: "sunkLights", eye: [330, 50, 230], target: [70, 10, -10], fov: 52, water: true },
	{ name: "preview-sinking-deck", groups: ["sunk"], lights: "sunkLights", eye: [X + 14, 112, -150], target: [X, 40, 40], fov: 62, water: true },
	{ name: "preview-plan", groups: ["lobby", "ship_Leviathan"], lights: "lights_Leviathan", eye: [20, 620, 0], target: [20, 0, 0.01], fov: 44, water: true, top: true },
	{ name: "preview-interior-engine-room", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [X - 3, 13, lev(30)], target: [X + 2, 9, lev(120)], fov: 70, interior: true },
	{ name: "preview-interior-cargo-hold", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [X + 3, 27, lev(40)], target: [X - 2, 23, lev(130)], fov: 70, interior: true },
	{ name: "preview-interior-cabins", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [X, 55, lev(30)], target: [X, 52, lev(130)], fov: 70, interior: true },
	{ name: "preview-interior-dining-hall", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [X - 6, 70, lev(36)], target: [X + 4, 64, lev(140)], fov: 72, interior: true },
	{ name: "preview-interior-promenade", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [X - 10, 83, lev(40)], target: [X + 8, 78, lev(150)], fov: 70, interior: true },
	{ name: "preview-top-deck", groups: ["ship_Leviathan"], lights: "lights_Leviathan", eye: [X + 20, 104, lev(-6)], target: [X, 92, lev(120)], fov: 66, water: true },
	{ name: "preview-loot-and-crew", groups: ["sheet"], lights: "sheetLights", eye: [2000, 9, -26], target: [2000, 1.5, 3], fov: 58, bright: true },
];

export function sceneScript(view, W, H) {
	const parts = view.groups.flatMap((g) => data[g] || []);
	const lights = data[view.lights || "lights"] || [];
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
// dusk sky: a vertical gradient
const sky = document.createElement('canvas'); sky.width = 2; sky.height = 256;
const g = sky.getContext('2d'); const gr = g.createLinearGradient(0, 0, 0, 256);
gr.addColorStop(0, '#2b2f5e'); gr.addColorStop(0.45, '#7a4f78'); gr.addColorStop(0.75, '#e8875a'); gr.addColorStop(1, '#f7c27a');
g.fillStyle = gr; g.fillRect(0, 0, 2, 256);
scene.background = ${view.bright ? "new THREE.Color(0x24304f)" : "new THREE.CanvasTexture(sky)"};
scene.fog = new THREE.Fog(0x8a6a7e, ${view.interior ? 160 : 260}, ${view.interior ? 420 : 1100});
scene.add(new THREE.HemisphereLight(0xffd6b0, 0x2a3050, ${view.bright ? 1.0 : view.interior ? 0.3 : 0.62}));
scene.add(new THREE.AmbientLight(0x404868, 0.35));
const sun = new THREE.DirectionalLight(0xffb37a, ${view.interior ? 0.25 : 0.9});
sun.position.set(-420, 160, -260); sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
const sc = sun.shadow.camera; sc.left = -450; sc.right = 450; sc.top = 450; sc.bottom = -450; sc.far = 1600;
scene.add(sun);
const target = new THREE.Vector3(${view.target.join(",")});
const eye = new THREE.Vector3(${view.eye.join(",")});
const lights = allLights.map(l => ({...l, d: Math.min(eye.distanceTo(new THREE.Vector3(...l.p)), target.distanceTo(new THREE.Vector3(...l.p)))}))
	.sort((a, b) => a.d - b.d).slice(0, 16);
for (const l of lights) {
	const pl = new THREE.PointLight(new THREE.Color(l.c[0]/255, l.c[1]/255, l.c[2]/255), l.b * (${view.interior ? 0.8 : 1.4}), l.range * (${view.interior ? 1.4 : 2.0}), 1.8);
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
	if (p.sh === 'Cylinder') { geo = new THREE.CylinderGeometry(Math.min(sy, sz)/2, Math.min(sy, sz)/2, sx, 24); geo.rotateZ(Math.PI/2); }
	else if (p.sh === 'Ball') { geo = new THREE.SphereGeometry(Math.min(sx, sy, sz)/2, 18, 12); }
	else if (p.sh === 'Wedge') { geo = wedge(sx, sy, sz); }
	else { geo = new THREE.BoxGeometry(sx, sy, sz); }
	const color = new THREE.Color(p.c[0]/255, p.c[1]/255, p.c[2]/255);
	let mat;
	if (p.m === 'Neon') mat = new THREE.MeshBasicMaterial({color, fog: true});
	else {
		const shiny = p.m === 'Glass' || p.m === 'Metal' || p.m === 'DiamondPlate';
		mat = new THREE.MeshStandardMaterial({color, roughness: shiny ? 0.35 : 0.85, metalness: p.m === 'Metal' ? 0.45 : 0.02, side: THREE.DoubleSide});
		if (p.sh === 'Truss') { mat.wireframe = true; }
	}
	if (p.t > 0) { mat.transparent = true; mat.opacity = 1 - p.t; mat.depthWrite = p.t < 0.5; }
	const mesh = new THREE.Mesh(geo, mat);
	mesh.position.set(p.p[0], p.p[1], p.p[2]);
	mesh.rotation.set(p.o[0], p.o[1], p.o[2], 'YXZ');
	mesh.castShadow = sx * sy * sz > 0.5 && p.t < 0.5 && p.m !== 'Neon'; mesh.receiveShadow = true;
	scene.add(mesh);
}
${view.water ? `
const sea = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000), new THREE.MeshBasicMaterial({color: 0x2a5a72, transparent: true, opacity: 0.8}));
sea.rotation.x = -Math.PI / 2; sea.position.y = 0; sea.receiveShadow = true; scene.add(sea);
const deep = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000), new THREE.MeshBasicMaterial({color: 0x0b2232}));
deep.rotation.x = -Math.PI / 2; deep.position.y = -30; scene.add(deep);` : ""}
const cam = new THREE.PerspectiveCamera(${view.fov}, W/H, 0.5, 4000);
cam.position.copy(eye);
${view.top ? "cam.up.set(1, 0, 0);" : ""}
cam.lookAt(target);
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
		await page.waitForFunction(() => window.__done === true, null, { timeout: 240000 });
		await page.evaluate(() => { window.__done = false; });
		const file = path.join(outDir, view.name + ".png");
		await page.locator("#c").screenshot({ path: file });
		console.log("wrote " + file);
	}
	await browser.close();
}
