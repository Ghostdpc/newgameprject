#!/usr/bin/env node
// 计算 glb 中各 mesh 节点的世界 AABB，输出地板/整体范围，用于关卡相机取景
const fs = require('fs');

const file = process.argv[2];
if (!file) { console.error('用法: node glb_aabb.cjs <glb路径>'); process.exit(1); }

const buf = fs.readFileSync(file);
if (buf.readUInt32LE(0) !== 0x46546C67) { console.error('非 glb'); process.exit(1); }
let off = 12, json = null, bin = null;
while (off < buf.length) {
  const len = buf.readUInt32LE(off); const type = buf.readUInt32LE(off + 4);
  const data = buf.slice(off + 8, off + 8 + len);
  if (type === 0x4E4F534A) json = JSON.parse(data.toString('utf8'));
  else if (type === 0x004E4942) bin = data;
  off += 8 + len;
}
const g = json;

function mul(a, b) { // 4x4 column-major a*b
  const r = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let rI = 0; rI < 4; rI++) {
    let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + rI] * b[c * 4 + k];
    r[c * 4 + rI] = s;
  }
  return r;
}
function trs(node) {
  if (node.matrix) return node.matrix.slice();
  const t = node.translation || [0, 0, 0];
  const q = node.rotation || [0, 0, 0, 1];
  const s = node.scale || [1, 1, 1];
  const [x, y, z, w] = q;
  const xx = x * x, yy = y * y, zz = z * z, xy = x * y, xz = x * z, yz = y * z, wx = w * x, wy = w * y, wz = w * z;
  const r = [
    (1 - 2 * (yy + zz)) * s[0], (2 * (xy + wz)) * s[0], (2 * (xz - wy)) * s[0], 0,
    (2 * (xy - wz)) * s[1], (1 - 2 * (xx + zz)) * s[1], (2 * (yz + wx)) * s[1], 0,
    (2 * (xz + wy)) * s[2], (2 * (yz - wx)) * s[2], (1 - 2 * (xx + yy)) * s[2], 0,
    t[0], t[1], t[2], 1,
  ];
  return r;
}
function xform(m, p) {
  return [
    m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
    m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
    m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
  ];
}

const groups = {}; // key -> {min,max}
function acc(key, p) {
  let b = groups[key];
  if (!b) { b = groups[key] = { min: [1e9, 1e9, 1e9], max: [-1e9, -1e9, -1e9] }; }
  for (let i = 0; i < 3; i++) { b.min[i] = Math.min(b.min[i], p[i]); b.max[i] = Math.max(b.max[i], p[i]); }
}

function classify(name) {
  const n = (name || '').toLowerCase();
  if (n.includes('floor')) return 'FLOOR';
  if (n.includes('wall') || n.includes('wallpaper') || n.includes('window') || n.includes('door')) return 'WALL';
  return 'OTHER';
}

function walk(nodeIdx, parent) {
  const node = g.nodes[nodeIdx];
  const world = mul(parent, trs(node));
  if (node.mesh !== undefined) {
    const cls = classify(node.name);
    const mesh = g.meshes[node.mesh];
    for (const prim of mesh.primitives) {
      const ai = prim.attributes.POSITION;
      const a = g.accessors[ai];
      if (!a.min || !a.max) continue;
      const [x0, y0, z0] = a.min, [x1, y1, z1] = a.max;
      const corners = [
        [x0, y0, z0], [x1, y0, z0], [x0, y1, z0], [x1, y1, z0],
        [x0, y0, z1], [x1, y0, z1], [x0, y1, z1], [x1, y1, z1],
      ];
      for (const c of corners) { const w = xform(world, c); acc(cls, w); acc('ALL', w); }
    }
  }
  for (const ch of (node.children || [])) walk(ch, world);
}

const scene = g.scenes[g.scene || 0];
const I = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
for (const r of scene.nodes) walk(r, I);

for (const k of ['FLOOR', 'WALL', 'OTHER', 'ALL']) {
  const b = groups[k];
  if (!b) { console.log(k, ' (none)'); continue; }
  const size = b.max.map((v, i) => (v - b.min[i]).toFixed(2));
  const ctr = b.max.map((v, i) => ((v + b.min[i]) / 2).toFixed(2));
  console.log(`${k}: min=[${b.min.map(v => v.toFixed(2))}] max=[${b.max.map(v => v.toFixed(2))}] size=[${size}] center=[${ctr}]`);
}
