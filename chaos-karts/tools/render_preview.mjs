// Renders build/preview.json (tools/export_preview.luau) to PNGs with three.js in headless
// Chromium (Playwright). A rough dusk approximation of Roblox lighting with neon as
// emissive - for checking layout, silhouettes, colours and elevation only.
// Usage (from chaos-karts/):
//   node tools/render_preview.mjs build/preview.json build/
//   (set PLAYWRIGHT_MODULE to Playwright's path if it isn't local; VIEW=name renders one)
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const [jsonPath = "build/preview.json", outDir = "build"] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

export function sceneScript(view, W, H) {
	const groups = view.groups || ["world", "karts"];
	const parts = groups.flatMap((g) => data[g] || []);
	return `
(function(){
const parts = ${JSON.stringify(parts)};
const allLights = ${JSON.stringify(data.lights)};
const W = ${W}, H = ${H};
const renderer = new THREE.WebGLRenderer({canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true, logarithmicDepthBuffer: true});
renderer.setSize(W, H);
renderer.shadowMap.enabled = ${view.top ? "false" : "true"};
renderer.outputEncoding = THREE.sRGBEncoding;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = ${view.top ? 1.05 : 1.15};
const scene = new THREE.Scene();
const sky = document.createElement('canvas'); sky.width = 2; sky.height = 256;
const g = sky.getContext('2d'); const gr = g.createLinearGradient(0, 0, 0, 256);
gr.addColorStop(0, '#26236a'); gr.addColorStop(0.45, '#7b4c9c'); gr.addColorStop(0.75, '#f0877a'); gr.addColorStop(1, '#ffc58a');
g.fillStyle = gr; g.fillRect(0, 0, 2, 256);
scene.background = ${view.bright ? "new THREE.Color(0x1d1838)" : view.top ? "new THREE.Color(0x1b2a20)" : "new THREE.CanvasTexture(sky)"};
${view.top ? "" : `scene.fog = new THREE.Fog(0x9a6f96, ${view.interior ? 260 : 700}, ${view.interior ? 900 : 3200});`}
scene.add(new THREE.HemisphereLight(0xffe0c8, 0x403a70, ${view.bright ? 0.9 : view.interior ? 0.5 : view.top ? 0.8 : 0.6}));
scene.add(new THREE.AmbientLight(0x5a5080, ${view.top ? 0.4 : view.interior ? 0.4 : 0.2}));
const sun = new THREE.DirectionalLight(0xffc090, ${view.interior ? 0.2 : 1.0});
sun.position.set(-900, 700, -500); sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
const target = new THREE.Vector3(${view.target.join(",")});
const eye = new THREE.Vector3(${view.eye.join(",")});
sun.target.position.copy(target); scene.add(sun.target);
sun.position.set(target.x - 900, 700, target.z - 500);
const sc = sun.shadow.camera; sc.left = -500; sc.right = 500; sc.top = 500; sc.bottom = -500; sc.far = 3000;
scene.add(sun);
const lights = allLights.map(l => ({...l, d: Math.min(eye.distanceTo(new THREE.Vector3(...l.p)), target.distanceTo(new THREE.Vector3(...l.p)))}))
	.sort((a, b) => a.d - b.d).slice(0, 14);
for (const l of lights) {
	const pl = new THREE.PointLight(new THREE.Color(l.c[0]/255, l.c[1]/255, l.c[2]/255), l.b * 1.3, l.range * 2.2, 1.6);
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
const geoCache = {};
for (const p of parts) {
	const [sx, sy, sz] = p.s;
	let geo;
	if (p.sh === 'Cylinder') { geo = new THREE.CylinderGeometry(Math.min(sy, sz)/2, Math.min(sy, sz)/2, sx, 20); geo.rotateZ(Math.PI/2); }
	else if (p.sh === 'Ball') { geo = new THREE.SphereGeometry(1, 16, 10); geo.scale(sx/2, sy/2, sz/2); }
	else if (p.sh === 'Wedge') { geo = wedge(sx, sy, sz); }
	else { geo = new THREE.BoxGeometry(sx, sy, sz); }
	const color = new THREE.Color(p.c[0]/255, p.c[1]/255, p.c[2]/255);
	let mat;
	if (p.m === 'Neon') { mat = new THREE.MeshBasicMaterial({color: color.clone().multiplyScalar(1.6), fog: true}); mat.toneMapped = false; }
	else {
		const shiny = p.m === 'Glass' || p.m === 'Metal' || p.m === 'DiamondPlate' || p.m === 'Marble';
		mat = new THREE.MeshStandardMaterial({color, roughness: shiny ? 0.3 : 0.85, metalness: p.m === 'Metal' ? 0.5 : 0.02});
	}
	if (p.t > 0) { mat.transparent = true; mat.opacity = 1 - p.t; mat.depthWrite = p.t < 0.5; }
	const mesh = new THREE.Mesh(geo, mat);
	mesh.position.set(p.p[0], p.p[1], p.p[2]);
	mesh.rotation.set(p.o[0], p.o[1], p.o[2], 'YXZ');
	mesh.castShadow = sx * sy * sz > 2 && p.t < 0.5 && p.m !== 'Neon' && sx < 900 && sz < 900; mesh.receiveShadow = true;
	scene.add(mesh);
}
const cam = new THREE.PerspectiveCamera(${view.fov}, W/H, 0.5, 9000);
cam.position.copy(eye);
${view.top ? "cam.up.set(0, 0, -1);" : ""}
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
	const W = 1600, H = 900;
	const { browser, page } = await openPage(W, H);
	const only = process.env.VIEW;
	for (const view of data.views) {
		if (only && !view.name.includes(only)) continue;
		const size = view.top ? [1400, 1400] : [W, H];
		await page.setViewportSize({ width: size[0], height: size[1] });
		await page.evaluate(sceneScript(view, size[0], size[1]));
		await page.waitForFunction(() => window.__done === true, null, { timeout: 300000 });
		await page.evaluate(() => { window.__done = false; });
		const file = path.join(outDir, view.name + ".png");
		await page.locator("#c").screenshot({ path: file });
		console.log("wrote " + file);
	}
	await browser.close();
}
