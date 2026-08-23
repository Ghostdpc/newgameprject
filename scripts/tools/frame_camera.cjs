#!/usr/bin/env node
// 给定地板 AABB + FOV + 宽高比，无偏航正对 -Z，在指定俯角下求最小距离使整块地板入镜，
// 报告相机位姿、镜头顶端命中的墙高，用于选俯角。
const FLOOR = { min: [-2.68, 0, -6.22], max: [4.61, 0, 2.77] };
const CENTER = [(FLOOR.min[0] + FLOOR.max[0]) / 2, 0, (FLOOR.min[2] + FLOOR.max[2]) / 2];
const FOV_V = 50 * Math.PI / 180;
const ASPECT = 1920 / 1080;
const FOV_H = 2 * Math.atan(Math.tan(FOV_V / 2) * ASPECT);
const MARGIN = 1.06; // 6% 边距
const WALL_TOP = 6.06;

function frame(pitchDeg) {
  const p = pitchDeg * Math.PI / 180;
  const fwd = [0, -Math.sin(p), -Math.cos(p)];
  const right = [1, 0, 0];
  const up = [fwd[1] * right[2] - fwd[2] * right[1], fwd[2] * right[0] - fwd[0] * right[2], fwd[0] * right[1] - fwd[1] * right[0]];
  // up = right x fwd 实际取相机 up = fwd cross right? 用: camUp = right × fwd
  const camUp = [right[1] * fwd[2] - right[2] * fwd[1], right[2] * fwd[0] - right[0] * fwd[2], right[0] * fwd[1] - right[1] * fwd[0]];
  const tanV = Math.tan(FOV_V / 2) / MARGIN;
  const tanH = Math.tan(FOV_H / 2) / MARGIN;
  // 求最小 d：对每个角点，相机=CENTER - d*fwd，向量 v=corner-cam=(corner-CENTER)+d*fwd
  // 投影 fdist=v·fwd, h=v·right, u=v·camUp，需 |h|<=fdist*tanH, |u|<=fdist*tanV
  const corners = [];
  for (const x of [FLOOR.min[0], FLOOR.max[0]]) for (const z of [FLOOR.min[2], FLOOR.max[2]]) corners.push([x - CENTER[0], 0, z - CENTER[2]]);
  let d = 0;
  for (const c of corners) {
    const cf = c[0] * fwd[0] + c[1] * fwd[1] + c[2] * fwd[2];
    const ch = c[0] * right[0] + c[1] * right[1] + c[2] * right[2];
    const cu = c[0] * camUp[0] + c[1] * camUp[1] + c[2] * camUp[2];
    // fdist = cf + d ; 约束 |ch| <= (cf+d)*tanH  → d >= |ch|/tanH - cf
    d = Math.max(d, Math.abs(ch) / tanH - cf, Math.abs(cu) / tanV - cf);
  }
  const cam = [CENTER[0] - d * fwd[0], CENTER[1] - d * fwd[1], CENTER[2] - d * fwd[2]];
  // 顶端镜头射线俯角 = p - FOV_V/2；命中背墙(z=FLOOR.min[2]-margin?) 或墙面。评估上边缘在 z=FLOOR far 处的高度
  const topPitch = p - FOV_V / 2;
  // 顶边射线方向
  const topDir = [0, -Math.sin(topPitch), -Math.cos(topPitch)];
  // 命中后墙平面 z = FLOOR.min[2] (最远地板边对应墙)
  const zWall = FLOOR.min[2];
  const t = (zWall - cam[2]) / topDir[2];
  const wallHitY = cam[1] + t * topDir[1];
  return { d, cam, topPitchDeg: topPitch * 180 / Math.PI, wallHitY };
}

console.log(`FOV_H=${(FOV_H * 180 / Math.PI).toFixed(1)}°  aim=${CENTER.map(v => v.toFixed(2))}`);
for (const p of [25, 30, 35, 40, 45, 50, 55]) {
  const r = frame(p);
  const wallTxt = r.wallHitY >= WALL_TOP ? `>=顶(${WALL_TOP})越顶` : r.wallHitY.toFixed(2);
  console.log(`pitch=${p}°  dist=${r.d.toFixed(2)}  cam=[${r.cam.map(v => v.toFixed(2)).join(', ')}]  height=${r.cam[1].toFixed(2)}  上边缘命中背墙Y=${wallTxt}`);
}
