# Builds a self-contained three.js preview page from an export_preview JSON.
# Usage: python3 tools/preview_html.py build/ripe.json out.html "camX,camY,camZ,lookX,lookY,lookZ"
import json,sys
data=open(sys.argv[1]).read()
cam=sys.argv[3]  # "x,y,z,tx,ty,tz"
html='''<!doctype html><html><body style="margin:0;background:#bfe3ff">
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script>
const parts=%s;
const W=1600,H=900;
const r=new THREE.WebGLRenderer({antialias:true});r.setSize(W,H);document.body.appendChild(r.domElement);
const s=new THREE.Scene();s.background=new THREE.Color(0xbfe3ff);
const c=[%s];
const cam=new THREE.PerspectiveCamera(40,W/H,0.1,3000);cam.position.set(c[0],c[1],c[2]);cam.lookAt(c[3],c[4],c[5]);
s.add(new THREE.HemisphereLight(0xffffff,0x667755,0.75));
const d=new THREE.DirectionalLight(0xffffff,0.8);d.position.set(-40,90,-60);s.add(d);
for(const p of parts){
 let g;
 if(p.mesh==="Sphere"){g=new THREE.SphereGeometry(0.5,20,14);g.scale(p.s[0],p.s[1],p.s[2]);}
 else if(p.mesh==="Head"){g=new THREE.SphereGeometry(0.5,20,14);g.scale(p.s[0]*0.75,p.s[1]*1.4,p.s[2]*1.25);}
 else if(p.sh==="Ball"){const m=Math.min(...p.s);g=new THREE.SphereGeometry(m/2,20,14);}
 else if(p.sh==="Cylinder"){const rr=Math.min(p.s[1],p.s[2])/2;g=new THREE.CylinderGeometry(rr,rr,p.s[0],20);g.rotateZ(-Math.PI/2);}
 else g=new THREE.BoxGeometry(p.s[0],p.s[1],p.s[2]);
 const col=new THREE.Color(`rgb(${p.c[0]},${p.c[1]},${p.c[2]})`);
 const mat=new THREE.MeshLambertMaterial({color:col,transparent:p.t>0,opacity:1-p.t,emissive:p.m==="Neon"?col:0x000000});
 const mesh=new THREE.Mesh(g,mat);
 const f=p.cf;const M=new THREE.Matrix4();M.set(f[3],f[4],f[5],f[0],f[6],f[7],f[8],f[1],f[9],f[10],f[11],f[2],0,0,0,1);
 mesh.applyMatrix4(M);s.add(mesh);
}
r.render(s,cam);document.title='done';
</script></body></html>'''%(data,cam)
open(sys.argv[2],'w').write(html)
