// Renders build/classroom.json (from tools/export_classroom.luau) to build/classroom-preview.png
// with three.js in headless Chromium. Same approach as snatch-tycoon/tools/render_preview.mjs.
// Usage (from phones-away/):
//   node tools/render_preview.mjs build/classroom.json <path to three.min.js> build/classroom-preview.png
// three.min.js: e.g. `npm pack three@0.160.0` and extract package/build/three.min.js.
import fs from "node:fs";
import { createRequire } from "node:module";

// Set PLAYWRIGHT_MODULE to the playwright package path if it isn't resolvable from here.
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");

const [jsonPath = "build/classroom.json", threePath, outPath = "build/classroom-preview.png"] = process.argv.slice(2);
if (!threePath) {
	console.error("usage: node tools/render_preview.mjs <classroom.json> <three.min.js> <out.png>");
	process.exit(1);
}
const world = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
const W = 1600, H = 900;

const html = `<!doctype html><html><head><style>body{margin:0;background:#000}</style></head><body><canvas id="c"></canvas></body></html>`;

// Default view: from the back-right corner over the desks toward the board and the teacher.
// PREVIEW_VIEW="ex,ey,ez,ax,ay,az" overrides it (for checking other corners).
const custom = process.env.PREVIEW_VIEW && process.env.PREVIEW_VIEW.split(",").map(Number);
const view = custom ? { eye: custom.slice(0, 3), at: custom.slice(3, 6) } : { eye: [24, 13.5, 24], at: [-3, 2.5, -10] };

function sceneScript() {
	return `
(function(){
const world = ${JSON.stringify(world)};
const renderer = new THREE.WebGLRenderer({canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true});
renderer.setSize(${W}, ${H});
renderer.setClearColor(0xbfe3ff);
const scene = new THREE.Scene();
scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8070, 1.55));
const sun = new THREE.DirectionalLight(0xfff4e0, 1.2); sun.position.set(-40, 60, 30); scene.add(sun);
function matrixOf(c) {
	return new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
}
// A text plane on a part's Front (-Z) or Back (+Z) face, like a SurfaceGui.
function textPlane(text, w, h, color, matrix, z, flip, fontPx, align) {
	const scale = 64;
	const canvas = document.createElement('canvas');
	canvas.width = Math.max(64, Math.round(w * scale)); canvas.height = Math.max(64, Math.round(h * scale));
	const g = canvas.getContext('2d');
	g.fillStyle = 'rgb(' + color.map(v => Math.round(v * 255)).join(',') + ')';
	const lines = text.split('\\n');
	let size = fontPx || Math.min(canvas.height / (lines.length + 0.6), canvas.width / Math.max(...lines.map(l => l.length)) * 1.7);
	g.font = 'bold ' + size + 'px Arial';
	if (fontPx) {
		// TextScaled with a max size: shrink until every line fits.
		const widest = Math.max(...lines.map(l => g.measureText(l).width));
		size = Math.min(size, size * (canvas.width * 0.92) / widest, canvas.height * 0.9 / (lines.length * 1.15 + 0.5));
		g.font = 'bold ' + size + 'px Arial';
	}
	g.textAlign = align || 'center'; g.textBaseline = 'middle';
	lines.forEach((l, i) => {
		const x = align === 'left' ? size * 0.6 : canvas.width / 2;
		const y = align === 'left' ? size * (0.9 + i * 1.15) : canvas.height / 2 + (i - (lines.length - 1) / 2) * size * 1.1;
		g.fillText(l, x, y);
	});
	const tex = new THREE.CanvasTexture(canvas);
	const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({map: tex, transparent: true}));
	if (flip) mesh.rotateY(Math.PI);
	mesh.position.z = z;
	const holder = new THREE.Group(); holder.add(mesh); holder.applyMatrix4(matrix);
	scene.add(holder);
}
for (const p of world.parts) {
	let geo; const [sx, sy, sz] = p.size;
	if (p.shape === 'Ellipsoid') { geo = new THREE.SphereGeometry(0.5, 18, 12); geo.scale(sx, sy, sz); }
	else if (p.shape === 'Ball') { geo = new THREE.SphereGeometry(Math.min(sx, sy, sz) / 2, 18, 12); }
	else if (p.shape === 'Cylinder') { geo = new THREE.CylinderGeometry(Math.min(sy, sz) / 2, Math.min(sy, sz) / 2, sx, 20); geo.rotateZ(Math.PI / 2); }
	else { geo = new THREE.BoxGeometry(sx, sy, sz); }
	const color = new THREE.Color(p.color[0], p.color[1], p.color[2]);
	let mat;
	if (p.material === 'Neon') mat = new THREE.MeshBasicMaterial({color});
	else mat = new THREE.MeshStandardMaterial({color, roughness: p.material === 'Metal' || p.material === 'Foil' ? 0.3 : 0.65, metalness: p.material === 'Metal' ? 0.45 : 0});
	if (p.transparency > 0) { mat.transparent = true; mat.opacity = 1 - p.transparency; }
	const mesh = new THREE.Mesh(geo, mat);
	const m = matrixOf(p.cf);
	mesh.applyMatrix4(m);
	scene.add(mesh);
	if (p.text && (p.text.face === 'Front' || p.text.face === 'Back')) {
		const back = p.text.face === 'Back';
		textPlane(p.text.value, sx * 0.95, sy * 0.9, p.text.color, m, (back ? 1 : -1) * (sz / 2 + 0.02), !back);
	}
}
// The whiteboard writing (a SurfaceGui on the board's Back face, toward the class).
const b = world.board;
textPlane(b.text, b.size[0], b.size[1], [0.16, 0.27, 0.67], matrixOf(b.cf), 0.08, false, 136, 'left'); // TextSize 64 at 30 px per stud
const cam = new THREE.PerspectiveCamera(58, ${W} / ${H}, 0.3, 500);
const view = ${JSON.stringify(view)};
cam.position.set(...view.eye);
cam.lookAt(...view.at);
renderer.render(scene, cam);
window.__done = true;
})();`;
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H } });
await page.setContent(html);
await page.addScriptTag({ path: threePath });
await page.addScriptTag({ content: sceneScript() });
await page.waitForFunction(() => window.__done === true);
await page.screenshot({ path: outPath });
console.log("wrote", outPath);
await browser.close();
