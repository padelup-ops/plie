// Vidéo de présentation d'Origamo : rendu image par image, render(t) dessine l'instant t.
const W = 1080, H = 1920;
const LANG = new URLSearchParams(location.search).get('lang') || 'fr';
const T = TEXTS[LANG];
const PW = 860, PH = 600, BEZ = 24;           // un demi-appareil, en paysage
const SW = PW - 2 * BEZ, SH = PH - 2 * BEZ;    // un demi-écran
const VS = { w: SW, h: 2 * SH };               // l'écran déplié entier

const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const lerp = (a, b, k) => a + (b - a) * k;
const ease = k => k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
const easeOut = k => 1 - Math.pow(1 - clamp(k), 3);
const back = k => { k = clamp(k); const c = 1.7; return 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2); };
function hash(i, s = 0) { let x = (Math.imul(i, 2654435761) + Math.imul(s, 40503) + 97) >>> 0; x = (x ^ (x >>> 13)) >>> 0; x = Math.imul(x, 0x5bd1e995) >>> 0; x = (x ^ (x >>> 15)) >>> 0; return (x % 10000) / 10000; }
function scene(t) { for (const s of CUES.scenes) if (t >= s[1] && t < s[2]) return s; return CUES.scenes[CUES.scenes.length - 1]; }

// ------------------------------------------------------------------ appareil 3D
const POSES = {
  hook:   t => ({ fold: lerp(2, 180, ease(clamp((t - 0.35) / 1.3))), tilt: lerp(8, 24, ease(clamp(t / 2.4))), rz: lerp(-6, 0, ease(clamp(t / 2))), s: lerp(0.86, 1.0, easeOut(t / 2.5)), y: 40, show: 1 }),
  rayon:  t => ({ fold: 150 + 22 * Math.cos(2 * Math.PI * (t - CUES.rayonHits[0]) / 1.0), tilt: 30, rz: -3, s: 1.0, y: 70, show: 1 }),
  chess:  t => ({ fold: 180, tilt: 44, rz: lerp(-8, -2, ease(clamp((t - 5.6) / 3))), s: 0.95, y: 90, show: 1 }),
  piano:  t => ({ fold: 112, tilt: 60, rz: 0, s: 1.02, y: 170, show: 1 }),
  filet:  t => ({ fold: 108, tilt: 58, rz: 3, s: 1.02, y: 170, show: 1 }),
  hockey: t => ({ fold: 180, tilt: 42, rz: 5, s: 0.94, y: 90, show: 1 }),
  ferme:  t => ({ fold: lerp(180, 0, ease(clamp((t - 16.7) / (CUES.fermeClose - 16.7)))), tilt: lerp(40, 14, ease(clamp((t - 16.6) / 1.0))), rz: lerp(4, -4, ease(clamp((t - 16.6) / 2.4))), s: 1.0, y: 110, show: 1 }),
  grid:   t => ({ fold: 0, tilt: 14, rz: -4, s: lerp(1.0, 0.5, ease(clamp((t - 19) / 0.5))), y: lerp(110, 900, ease(clamp((t - 19) / 0.5))), show: 1 - clamp((t - 19) / 0.45) }),
  end:    t => ({ fold: 0, tilt: 14, rz: 0, s: 0.5, y: 900, show: 0 }),
};
function pose(t) {
  const s = scene(t);
  let p = POSES[s[0]](t);
  // Fondu de pose avec la scène précédente au début de chaque scène
  const k = clamp((t - s[1]) / 0.45);
  const i = CUES.scenes.indexOf(s);
  if (i > 0 && k < 1 && s[0] !== 'grid') {
    const prev = POSES[CUES.scenes[i - 1][0]](s[1] - 0.001);
    const e = ease(k);
    const q = {};
    for (const key in p) q[key] = lerp(prev[key], p[key], e);
    p = q;
  }
  return p;
}

// ------------------------------------------------------------------ fond
const bg = document.getElementById('bg').getContext('2d');
const ACCENT = { hook: ['#3DE0FF', '#FF4F9A', '#FFC53D'], rayon: ['#6A3DE8', '#3DE0FF', '#1F4FC9'], chess: ['#E3B66E', '#8A5A3C', '#6A5CFF'],
  piano: ['#C9A2FF', '#F3D79A', '#8E1B22'], filet: ['#5B8CFF', '#3CCB7F', '#FF5C4D'], hockey: ['#3DE0FF', '#FF4F9A', '#7B5CFF'],
  ferme: ['#5FD3A0', '#C7E86B', '#FF9AC4'], grid: ['#3DE0FF', '#FF4F9A', '#FFC53D'], end: ['#FF4F9A', '#7B5CFF', '#3DE0FF'] };
function drawBackground(t) {
  const s = scene(t)[0];
  bg.fillStyle = '#0B0C1C';
  bg.fillRect(0, 0, W, H);
  bg.save();
  bg.filter = 'blur(120px)';
  ACCENT[s].forEach((c, i) => {
    const x = W * (0.5 + 0.42 * Math.sin(t * 0.35 + i * 2.1)), y = H * (0.45 + 0.32 * Math.cos(t * 0.27 + i * 1.7));
    bg.globalAlpha = 0.42;
    bg.fillStyle = c;
    bg.beginPath(); bg.arc(x, y, 420 + 60 * Math.sin(t * 0.6 + i), 0, 7); bg.fill();
  });
  bg.restore();
  bg.globalAlpha = 1;
  // fines étoiles
  for (let i = 0; i < 80; i++) {
    const x = hash(i, 1) * W, y = (hash(i, 2) * H + t * 18 * (0.3 + hash(i, 3))) % H;
    bg.fillStyle = `rgba(255,255,255,${0.15 + 0.25 * hash(i, 4)})`;
    bg.fillRect(x, y, 2, 2);
  }
  const v = bg.createRadialGradient(W / 2, H / 2, H * 0.25, W / 2, H / 2, H * 0.75);
  v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,0.55)');
  bg.fillStyle = v; bg.fillRect(0, 0, W, H);
}

// ------------------------------------------------------------------ écrans
const full = document.createElement('canvas'); full.width = VS.w; full.height = VS.h;
const fx = full.getContext('2d');
const topC = document.getElementById('scrTop').getContext('2d');
const botC = document.getElementById('scrBot').getContext('2d');
const outC = document.getElementById('scrOut').getContext('2d');

function rr(c, x, y, w, h, r) { c.beginPath(); c.roundRect(x, y, w, h, r); }
function text(c, s, x, y, size, color, weight = 800, align = 'center', font = 'Inter') {
  c.font = `${weight} ${size}px ${font}`; c.fillStyle = color; c.textAlign = align; c.textBaseline = 'middle'; c.fillText(s, x, y);
}
function shadedBall(c, x, y, r, color, hi = '#fff') {
  c.fillStyle = 'rgba(0,0,0,0.3)'; c.beginPath(); c.arc(x + r * 0.15, y + r * 0.25, r, 0, 7); c.fill();
  const g = c.createRadialGradient(x - r * 0.35, y - r * 0.4, 0, x, y, r * 1.5);
  g.addColorStop(0, hi); g.addColorStop(0.45, color); g.addColorStop(1, color);
  c.fillStyle = g; c.beginPath(); c.arc(x, y, r, 0, 7); c.fill();
}

// Accueil de l'app
function screenHub(c, t) {
  const g = c.createLinearGradient(0, 0, 0, VS.h); g.addColorStop(0, '#141734'); g.addColorStop(1, '#0E1020');
  c.fillStyle = g; c.fillRect(0, 0, VS.w, VS.h);
  const tg = c.createLinearGradient(80, 0, VS.w - 80, 0);
  ['#3DE0FF', '#FF4F9A', '#FFC53D', '#FF7A2F'].forEach((col, i) => tg.addColorStop(i / 3, col));
  c.font = '900 120px "Inter Display"'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillStyle = tg;
  c.fillText('ORIGAMO', VS.w / 2, 170);
  text(c, T.hubSub, VS.w / 2, 260, 34, '#fff', 700);
  const cards = [['#3DE0FF', T.names[0]], ['#FF4F9A', T.names[1]], ['#E3B66E', T.names[8]], ['#C9A2FF', T.names[10]], ['#5B8CFF', T.names[5]]];
  cards.forEach(([col, name], i) => {
    const y = 360 + i * 152;
    rr(c, 40, y, VS.w - 80, 128, 26); c.fillStyle = 'rgba(255,255,255,0.07)'; c.fill();
    c.strokeStyle = 'rgba(255,255,255,0.12)'; c.lineWidth = 2; c.stroke();
    const ig = c.createLinearGradient(64, y + 18, 156, y + 110); ig.addColorStop(0, col); ig.addColorStop(1, col + '99');
    rr(c, 64, y + 18, 92, 92, 22); c.fillStyle = ig; c.fill();
    text(c, name, 186, y + 50, 40, '#fff', 900, 'left');
    rr(c, 186, y + 78, 220, 30, 15); c.fillStyle = col + '30'; c.fill();
  });
}

// RAYON : le miroir suit la charnière
function screenRayon(c, t, fold) {
  const g = c.createRadialGradient(VS.w / 2, VS.h * 0.45, 0, VS.w / 2, VS.h * 0.45, VS.h * 0.7);
  g.addColorStop(0, '#1E2150'); g.addColorStop(1, '#0C0E22'); c.fillStyle = g; c.fillRect(0, 0, VS.w, VS.h);
  c.save(); c.filter = 'blur(60px)';
  [['#6A3DE8', 0.25, 0.25], ['#1FA2C9', 0.78, 0.7], ['#C93D8B', 0.7, 0.18]].forEach(([col, x, y]) => {
    c.globalAlpha = 0.35; c.fillStyle = col; c.beginPath(); c.arc(VS.w * x, VS.h * y, 220, 0, 7); c.fill(); });
  c.restore(); c.globalAlpha = 1;
  for (let i = 0; i < 90; i++) { const tw = 0.4 + 0.6 * (0.5 + 0.5 * Math.sin(t * 3 + i)); c.fillStyle = `rgba(255,255,255,${0.6 * tw})`;
    c.beginPath(); c.arc(hash(i, 7) * VS.w, hash(i, 8) * VS.h, 1 + 1.5 * hash(i, 9), 0, 7); c.fill(); }
  // murs
  c.lineCap = 'round';
  [[0.15, 0.62, 0.42, 0.62], [0.62, 0.36, 0.9, 0.36]].forEach(([a, b, x2, y2]) => {
    c.strokeStyle = '#4A5180'; c.lineWidth = 22; c.beginPath(); c.moveTo(a * VS.w, b * VS.h); c.lineTo(x2 * VS.w, y2 * VS.h); c.stroke();
    c.strokeStyle = 'rgba(255,255,255,0.2)'; c.lineWidth = 4; c.stroke(); });
  const em = [0.08 * VS.w, 0.86 * VS.h], mir = [0.5 * VS.w, 0.5 * VS.h], target = [0.82 * VS.w, 0.12 * VS.h];
  // miroir piloté par la charnière : au pli maximal il renvoie le laser sur la cible
  const want = Math.atan2(target[1] - mir[1], target[0] - mir[0]);
  const inc = Math.atan2(mir[1] - em[1], mir[0] - em[0]);
  const ideal = (want + inc + Math.PI) / 2 + Math.PI / 2;
  const ang = ideal + (fold - 172) * Math.PI / 180 * 0.9;
  const dx = Math.cos(inc), dy = Math.sin(inc), nx = Math.cos(ang + Math.PI / 2), ny = Math.sin(ang + Math.PI / 2);
  const dot = dx * nx + dy * ny, rx = dx - 2 * dot * nx, ry = dy - 2 * dot * ny;
  const end = [mir[0] + rx * 2000, mir[1] + ry * 2000];
  const dist = Math.abs((target[0] - mir[0]) * ry - (target[1] - mir[1]) * rx);
  const hit = dist < 34 && (target[0] - mir[0]) * rx + (target[1] - mir[1]) * ry > 0;
  // cible
  const pulse = 0.5 + 0.5 * Math.sin(t * 6);
  if (hit) { c.save(); c.filter = 'blur(30px)'; c.fillStyle = 'rgba(255,197,61,0.8)'; c.beginPath(); c.arc(target[0], target[1], 90, 0, 7); c.fill(); c.restore(); }
  c.strokeStyle = '#FFC53D'; c.lineWidth = 8; c.beginPath(); c.arc(target[0], target[1], 46, 0, 7); c.stroke();
  c.globalAlpha = 0.3 + 0.2 * pulse; c.beginPath(); c.arc(target[0], target[1], 64 + 8 * pulse, 0, 7); c.lineWidth = 3; c.stroke(); c.globalAlpha = 1;
  c.fillStyle = 'rgba(255,197,61,0.4)'; c.beginPath(); c.arc(target[0], target[1], 20, 0, 7); c.fill();
  // rayon
  const col = hit ? '#FFC53D' : '#FF3B5C';
  const beam = () => { c.beginPath(); c.moveTo(em[0], em[1]); c.lineTo(mir[0], mir[1]); c.lineTo(hit ? target[0] : end[0], hit ? target[1] : end[1]); };
  c.save(); c.filter = 'blur(14px)'; c.strokeStyle = col; c.lineWidth = 26; beam(); c.stroke(); c.restore();
  c.strokeStyle = col; c.lineWidth = 9; beam(); c.stroke();
  c.strokeStyle = 'rgba(255,255,255,0.9)'; c.lineWidth = 3; beam(); c.stroke();
  // miroir (bleu, piloté) et émetteur
  const ml = 110, mx = Math.cos(ang) * ml, my = Math.sin(ang) * ml;
  c.save(); c.filter = 'blur(8px)'; c.strokeStyle = '#3DE0FF'; c.lineWidth = 24; c.beginPath(); c.moveTo(mir[0] - mx, mir[1] - my); c.lineTo(mir[0] + mx, mir[1] + my); c.stroke(); c.restore();
  const mg = c.createLinearGradient(mir[0] - mx, mir[1] - my, mir[0] + mx, mir[1] + my); mg.addColorStop(0, '#3DE0FF'); mg.addColorStop(0.5, '#fff'); mg.addColorStop(1, '#3DE0FF');
  c.strokeStyle = mg; c.lineWidth = 12; c.beginPath(); c.moveTo(mir[0] - mx, mir[1] - my); c.lineTo(mir[0] + mx, mir[1] + my); c.stroke();
  shadedBall(c, em[0], em[1], 26, '#FF5C4D');
  return hit;
}

// Échecs : l'échiquier coupé par la charnière, chaque camp tourné vers son joueur
const PIECE_PATHS = {};
for (const name in PIECES) {
  const p = new Path2D();
  for (const s of PIECES[name].shapes) {
    if (s[0] === 'rr') p.roundRect(s[1], s[2], s[3] - s[1], s[4] - s[2], s[5]);
    else if (s[0] === 'c') { p.moveTo(s[1] + s[3], s[2]); p.arc(s[1], s[2], s[3], 0, Math.PI * 2); }
    else if (s[0] === 'e') { p.moveTo(s[1] + s[3], s[2]); p.ellipse(s[1], s[2], s[3], s[4], 0, 0, Math.PI * 2); }
    else p.addPath(new Path2D(s[1]));
  }
  const d = new Path2D(), dots = new Path2D();
  for (const s of PIECES[name].details) {
    if (s[0] === 'ln') { d.moveTo(s[1], s[2]); d.lineTo(s[3], s[4]); }
    else if (s[0] === 'dp') d.addPath(new Path2D(s[1]));
    else if (s[0] === 'dc') { dots.moveTo(s[1] + s[3], s[2]); dots.arc(s[1], s[2], s[3], 0, Math.PI * 2); }
  }
  PIECE_PATHS[name] = { body: p, detail: d, dots };
}
function drawPiece(c, name, white, x, y, size, rot = 0, lift = 0) {
  const P = PIECE_PATHS[name];
  c.save(); c.translate(x, y); c.rotate(rot); c.scale(size / 100 * (1 + 0.1 * lift), size / 100 * (1 + 0.1 * lift)); c.translate(-50, -52);
  c.save(); c.translate(3 + 4 * lift, 4 + 8 * lift); c.filter = `blur(${2 + 4 * lift}px)`; c.fillStyle = 'rgba(0,0,0,0.4)'; c.fill(P.body); c.restore();
  c.lineJoin = 'round'; c.lineWidth = 5; c.strokeStyle = white ? '#2A1D12' : '#050507'; c.stroke(P.body);
  const g = c.createLinearGradient(0, 0, 100, 100);
  if (white) { g.addColorStop(0, '#FFFFFF'); g.addColorStop(0.55, '#F3EAD8'); g.addColorStop(1, '#D6C3A0'); }
  else { g.addColorStop(0, '#5A5A68'); g.addColorStop(0.5, '#2A2A33'); g.addColorStop(1, '#0C0C10'); }
  c.fillStyle = g; c.fill(P.body);
  if (!white) { c.lineWidth = 1.6; c.strokeStyle = 'rgba(185,185,204,0.45)'; c.stroke(P.body); }
  c.save(); c.clip(P.body); const sh = c.createLinearGradient(0, 0, 45, 0); sh.addColorStop(0, `rgba(255,255,255,${white ? 0.45 : 0.32})`); sh.addColorStop(1, 'rgba(255,255,255,0)');
  c.fillStyle = sh; c.fillRect(0, 0, 100, 100); c.restore();
  c.lineWidth = 2.2; c.lineCap = 'round'; c.strokeStyle = white ? 'rgba(42,29,18,0.55)' : 'rgba(216,216,230,0.55)'; c.stroke(P.detail);
  c.fillStyle = white ? 'rgba(42,29,18,0.85)' : 'rgba(216,216,230,0.85)'; c.fill(P.dots);
  c.restore();
}
const GRAIN_CACHE = {};
function chessBoardImage(side) {
  if (GRAIN_CACHE[side]) return GRAIN_CACHE[side];
  const cv = document.createElement('canvas'); cv.width = side; cv.height = side; const c = cv.getContext('2d');
  const frame = side * 0.06, q = (side - 2 * frame) / 8;
  const fg = c.createLinearGradient(0, 0, side, side); fg.addColorStop(0, '#6B3E22'); fg.addColorStop(0.5, '#4A2614'); fg.addColorStop(1, '#2E160B');
  rr(c, 0, 0, side, side, side * 0.03); c.fillStyle = fg; c.fill();
  for (let r = 0; r < 8; r++) for (let f = 0; f < 8; f++) {
    const x = frame + f * q, y = frame + (7 - r) * q, light = (r + f) % 2 === 1;
    const g = c.createLinearGradient(x, y, x + q, y + q);
    if (light) { g.addColorStop(0, '#F0D7AC'); g.addColorStop(1, '#DDB988'); } else { g.addColorStop(0, '#9A6440'); g.addColorStop(1, '#76472B'); }
    c.fillStyle = g; c.fillRect(x, y, q + 0.5, q + 0.5);
    c.save(); c.beginPath(); c.rect(x, y, q, q); c.clip();
    for (let k = 0; k < 7; k++) {
      const seed = r * 8 + f, off = (k + 0.5 + (hash(seed, k) - 0.5) * 0.6) / 7, amp = q * (0.015 + 0.03 * hash(seed, k + 20)), ph = hash(seed, k + 40) * 6.28, fr = 0.6 + hash(seed, k + 60);
      c.beginPath();
      for (let j = 0; j <= 8; j++) { const tt = j / 8, wv = amp * Math.sin(tt * 6.28 * fr + ph);
        const px = light ? x + tt * q : x + off * q + wv, py = light ? y + off * q + wv : y + tt * q; if (j === 0) c.moveTo(px, py); else c.lineTo(px, py); }
      c.strokeStyle = light ? `rgba(138,90,48,${0.15 * (0.5 + hash(seed, k + 90))})` : `rgba(62,32,16,${0.3 * (0.5 + hash(seed, k + 90))})`;
      c.lineWidth = 0.5 + 1.1 * hash(seed, k + 80); c.stroke();
    }
    c.restore();
  }
  const lg = c.createLinearGradient(frame, frame, side - frame, side - frame); lg.addColorStop(0, 'rgba(255,255,255,0.16)'); lg.addColorStop(0.5, 'rgba(255,255,255,0)'); lg.addColorStop(1, 'rgba(0,0,0,0.14)');
  c.fillStyle = lg; c.fillRect(frame, frame, side - 2 * frame, side - 2 * frame);
  c.strokeStyle = 'rgba(217,178,106,0.85)'; c.lineWidth = 2; c.strokeRect(frame - 3, frame - 3, side - 2 * frame + 6, side - 2 * frame + 6);
  for (let i = 0; i < 8; i++) {
    text(c, 'abcdefgh'[i], frame + (i + 0.5) * q, side - frame * 0.5, frame * 0.42, '#E2C189', 600, 'center', 'DejaVu Serif');
    c.save(); c.translate(frame + (i + 0.5) * q, frame * 0.5); c.rotate(Math.PI); text(c, 'abcdefgh'[i], 0, 0, frame * 0.42, '#E2C189', 600, 'center', 'DejaVu Serif'); c.restore();
  }
  GRAIN_CACHE[side] = cv; return cv;
}
const START = { 'a1': 'R', 'b1': 'N', 'c1': 'B', 'd1': 'Q', 'e1': 'K', 'f1': 'B', 'g1': 'N', 'h1': 'R', 'a8': 'r', 'b8': 'n', 'c8': 'b', 'd8': 'q', 'e8': 'k', 'f8': 'b', 'g8': 'n', 'h8': 'r' };
for (const f of 'abcdefgh') { START[f + '2'] = 'P'; START[f + '7'] = 'p'; }
const PNAME = { k: 'king', q: 'queen', r: 'rook', b: 'bishop', n: 'knight', p: 'pawn' };
function screenChess(c, t) {
  const g = c.createLinearGradient(0, 0, 0, VS.h); g.addColorStop(0, '#1A1530'); g.addColorStop(1, '#14112A'); c.fillStyle = g; c.fillRect(0, 0, VS.w, VS.h);
  const side = Math.min(VS.w * 0.94, VS.h * 0.7), bx = (VS.w - side) / 2, by = (VS.h - side) / 2;
  c.drawImage(chessBoardImage(Math.round(side)), bx, by, side, side);
  const frame = side * 0.06, q = (side - 2 * frame) / 8;
  const sq = s => [bx + frame + ('abcdefgh'.indexOf(s[0]) + 0.5) * q, by + frame + (8 - parseInt(s[1]) + 0.5) * q];
  // position et animation des coups
  const pos = Object.assign({}, START); let moving = null, last = null, select = null;
  for (const [tm, uci] of CUES.chessMoves) {
    const from = uci.slice(0, 2), to = uci.slice(2, 4);
    if (t >= tm + 0.32) { pos[to] = pos[from]; delete pos[from]; last = [from, to]; }
    else if (t >= tm) { moving = { from, to, k: ease((t - tm) / 0.32), piece: pos[from] }; delete pos[from]; last = [from, to]; break; }
    else if (t >= tm - 0.35) { select = from; break; }
    else break;
  }
  const hl = s => { const [x, y] = sq(s); c.fillStyle = 'rgba(246,211,101,0.4)'; c.fillRect(x - q / 2, y - q / 2, q, q); };
  if (last) { hl(last[0]); hl(last[1]); }
  if (select) {
    hl(select);
    const m = CUES.chessMoves.find(([, u]) => u.startsWith(select)); const [tx, ty] = sq(m[1].slice(2, 4));
    c.fillStyle = 'rgba(26,16,8,0.32)'; c.beginPath(); c.arc(tx, ty, q * 0.17, 0, 7); c.fill();
  }
  for (const s in pos) { const [x, y] = sq(s); const ch = pos[s], white = ch === ch.toUpperCase(); drawPiece(c, PNAME[ch.toLowerCase()], white, x, y, q * 0.92, white ? 0 : Math.PI, s === select ? 1 : 0); }
  if (moving) {
    const [x0, y0] = sq(moving.from), [x1, y1] = sq(moving.to); const white = moving.piece === moving.piece.toUpperCase();
    drawPiece(c, PNAME[moving.piece.toLowerCase()], white, lerp(x0, x1, moving.k), lerp(y0, y1, moving.k), q * 0.92, white ? 0 : Math.PI, 1 - moving.k * 0.6);
  }
  // panneaux des deux joueurs, tournés chacun vers son joueur
  const panel = (y, rot, name, time, active) => {
    c.save(); c.translate(VS.w / 2, y); c.rotate(rot);
    rr(c, -VS.w * 0.44, -46, VS.w * 0.88, 92, 26); c.fillStyle = 'rgba(255,255,255,0.08)'; c.fill();
    c.strokeStyle = active ? 'rgba(227,182,110,0.9)' : 'rgba(255,255,255,0.12)'; c.lineWidth = 3; c.stroke();
    drawPiece(c, 'king', rot === 0, -VS.w * 0.44 + 54, 0, 64);
    text(c, name, -VS.w * 0.44 + 104, -10, 30, '#fff', 900, 'left'); text(c, active ? T.yourMove : T.waiting, -VS.w * 0.44 + 104, 22, 20, active ? '#E3B66E' : 'rgba(255,255,255,0.6)', 700, 'left');
    rr(c, VS.w * 0.44 - 170, -28, 150, 56, 14); c.fillStyle = active ? '#E3B66E' : 'rgba(0,0,0,0.35)'; c.fill();
    text(c, time, VS.w * 0.44 - 95, 1, 32, active ? '#0E1020' : '#fff', 900);
    c.restore();
  };
  const whiteTurn = CUES.chessMoves.filter(([tm]) => t >= tm).length % 2 === 0;
  const clockW = 300 - Math.max(0, t - 5.6) * (whiteTurn ? 1 : 0.4), clockB = 300 - Math.max(0, t - 6.2) * (whiteTurn ? 0.4 : 1);
  const fmt = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
  panel(by + side + (VS.h - by - side) / 2, 0, T.white, fmt(clockW), whiteTurn);
  panel(by / 2, Math.PI, T.black, fmt(clockB), !whiteTurn);
}

// PIANO : partition en haut, clavier en bas
const NAMES_FR = ['Do', 'Do♯', 'Ré', 'Ré♯', 'Mi', 'Fa', 'Fa♯', 'Sol', 'Sol♯', 'La', 'La♯', 'Si'], NAMES_EN = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
const isBlack = m => [1, 3, 6, 8, 10].includes(m % 12);
function screenPiano(c, t) {
  // haut : le pupitre
  const wood = c.createLinearGradient(0, 0, 0, SH); wood.addColorStop(0, '#2A1C14'); wood.addColorStop(1, '#3B271B');
  c.fillStyle = wood; c.fillRect(0, 0, VS.w, SH);
  const px = 30, py = 34, pw = VS.w - 60, ph = SH - 64;
  c.save(); c.filter = 'blur(10px)'; c.fillStyle = 'rgba(0,0,0,0.5)'; rr(c, px, py + 8, pw, ph, 14); c.fill(); c.restore();
  const pg = c.createLinearGradient(0, py, 0, py + ph); pg.addColorStop(0, '#FFFBF1'); pg.addColorStop(1, '#F3E9D2'); c.fillStyle = pg; rr(c, px, py, pw, ph, 14); c.fill();
  const ink = '#231C16', gap = 22, bottom = py + ph * 0.66;
  text(c, T.song, px + 24, py + 36, 28, ink, 800, 'left', 'DejaVu Serif');
  c.strokeStyle = 'rgba(35,28,22,0.75)'; c.lineWidth = 1.6;
  for (let l = 0; l < 5; l++) { c.beginPath(); c.moveTo(px + 16, bottom - l * gap); c.lineTo(px + pw - 16, bottom - l * gap); c.stroke(); }
  text(c, '𝄞', px + 52, bottom - gap * 1.7, gap * 6.3, ink, 400, 'center', 'DejaVu Sans');
  const notes = CUES.piano; let idx = notes.filter(([tm]) => t >= tm).length;
  const playX = px + 190, step = 64;
  const scroll = lerp(Math.max(0, idx - 1), idx, easeOut(clamp((t - (notes[Math.max(0, idx - 1)] || [0])[0]) / 0.18)));
  c.strokeStyle = 'rgba(201,162,255,0.55)'; c.lineWidth = 4; c.beginPath(); c.moveTo(playX, bottom - gap * 6); c.lineTo(playX, bottom + gap * 2.4); c.stroke();
  notes.forEach(([tm, m], i) => {
    const x = playX + (i - scroll + 1) * step; if (x < px + 110 || x > px + pw - 20) return;
    const letter = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][m % 12], st = (Math.floor(m / 12) - 1) * 7 + letter - 30, y = bottom - st * gap / 2;
    const played = t >= tm, cur = i === idx;
    const col = played ? '#2F9E6B' : (cur ? '#B07A1E' : ink);
    if (cur) { const rg = c.createRadialGradient(x, y, 0, x, y, 36); rg.addColorStop(0, 'rgba(201,162,255,0.6)'); rg.addColorStop(1, 'rgba(201,162,255,0)'); c.fillStyle = rg; c.beginPath(); c.arc(x, y, 36, 0, 7); c.fill(); }
    c.save(); c.translate(x, y); c.rotate(-0.35); c.fillStyle = col; c.beginPath(); c.ellipse(0, 0, gap * 0.66, gap * 0.48, 0, 0, 7); c.fill(); c.restore();
    const up = st < 4; c.strokeStyle = col; c.lineWidth = 2.6; c.beginPath(); c.moveTo(x + (up ? gap * 0.6 : -gap * 0.6), y); c.lineTo(x + (up ? gap * 0.6 : -gap * 0.6), y + (up ? -gap * 3.3 : gap * 3.3)); c.stroke();
    text(c, (LANG === 'fr' ? NAMES_FR : NAMES_EN)[m % 12], x, bottom + gap * 2.5, 20, col, 800);
  });
  // bas : le clavier
  const ky = SH, kh = SH;
  const fb = c.createLinearGradient(0, ky, 0, ky + 44); fb.addColorStop(0, '#1B1210'); fb.addColorStop(1, '#120C0A'); c.fillStyle = fb; c.fillRect(0, ky, VS.w, 44);
  c.font = '900 20px "DejaVu Serif"'; c.fillStyle = '#E2C189'; c.textAlign = 'center'; c.fillText('O R I G A M O', VS.w / 2, ky + 24);
  c.fillStyle = '#8E1B22'; c.fillRect(0, ky + 40, VS.w, 4);
  const lo = 60, whites = []; for (let m = lo; m <= 84; m++) if (!isBlack(m)) whites.push(m);
  const n = 14, ww = VS.w / n, top = ky + 44, h = kh - 44;
  const lit = new Set(); notes.forEach(([tm, m]) => { if (t >= tm && t < tm + 0.2) lit.add(m); });
  const guide = notes[idx] ? notes[idx][1] : null;
  whites.slice(0, n).forEach((m, i) => {
    const down = lit.has(m), x = i * ww;
    const kg = c.createLinearGradient(0, top, 0, top + h);
    if (down) { kg.addColorStop(0, '#E4DDCF'); kg.addColorStop(1, '#CFC6B4'); } else { kg.addColorStop(0, '#FFFEFA'); kg.addColorStop(0.6, '#F1EBDD'); kg.addColorStop(1, '#E2D9C6'); }
    rr(c, x + 1.5, top - 8, ww - 3, h + 8 - (down ? 4 : 0), 8); c.fillStyle = kg; c.fill();
    if (m === guide) { const gg = c.createLinearGradient(0, top + h * 0.4, 0, top + h); gg.addColorStop(0, 'rgba(201,162,255,0)'); gg.addColorStop(1, `rgba(201,162,255,${0.5 + 0.3 * Math.sin(t * 10)})`); c.fillStyle = gg; c.fill(); }
    if (down) { c.fillStyle = 'rgba(201,162,255,0.35)'; c.fill(); }
    c.strokeStyle = 'rgba(140,130,112,0.6)'; c.lineWidth = 1.5; c.stroke();
    text(c, (LANG === 'fr' ? NAMES_FR : NAMES_EN)[m % 12], x + ww / 2, top + h - 30, 20, m === guide ? '#6A3FB0' : '#7A6F5C', 800);
  });
  whites.slice(0, n).forEach((m, i) => {
    const b = m + 1; if (!isBlack(b) || i === n - 1) return;
    const x = (i + 1) * ww - ww * 0.3, bw = ww * 0.6, bh = h * 0.6;
    c.fillStyle = 'rgba(0,0,0,0.35)'; rr(c, x + 3, top + 4, bw, bh, 6); c.fill();
    const bg2 = c.createLinearGradient(x, top, x + bw, top + bh); bg2.addColorStop(0, '#2C2830'); bg2.addColorStop(1, '#0E0C10');
    rr(c, x, top - 6, bw, bh + 6, 6); c.fillStyle = bg2; c.fill();
  });
}

// FILET : ping-pong, le filet sur la charnière
function filetBall(t) {
  const K = CUES.filet; let i = 0; while (i < K.length - 2 && t >= K[i + 1][0]) i++;
  const a = K[i], b = K[i + 1], k = clamp((t - a[0]) / (b[0] - a[0]));
  const arc = Math.sin(Math.PI * k) * 0.16;
  return { x: lerp(a[1], b[1], k), v: lerp(a[2], b[2], k), z: lerp(a[3], b[3], k) + arc };
}
function screenFilet(c, t) {
  // salle
  const wall = c.createLinearGradient(0, 0, 0, SH * 0.3); wall.addColorStop(0, '#0D1030'); wall.addColorStop(1, '#1E2558'); c.fillStyle = wall; c.fillRect(0, 0, VS.w, SH * 0.3);
  const fl = c.createLinearGradient(0, SH * 0.3, 0, SH); fl.addColorStop(0, '#4A1E22'); fl.addColorStop(1, '#8A3530'); c.fillStyle = fl; c.fillRect(0, SH * 0.3, VS.w, SH * 0.7);
  c.fillStyle = '#A2443A'; c.fillRect(0, SH, VS.w, SH);
  c.fillStyle = '#1C3F9E'; c.fillRect(0, SH * 0.24, VS.w, SH * 0.07);
  c.font = '900 24px Inter'; c.fillStyle = 'rgba(255,255,255,0.55)'; c.textAlign = 'center';
  for (let x = 80, f = 0; x < VS.w; x += 170, f++) c.fillText(f % 2 ? 'FILET' : 'ORIGAMO', x, SH * 0.285);
  for (let i = 0; i < 40; i++) { c.fillStyle = 'rgba(58,67,120,0.85)'; c.beginPath(); c.arc(hash(i, 31) * VS.w, SH * 0.235 - hash(i, 32) * 40, 9, 0, 7); c.fill(); }
  // table : moitié adverse en perspective, ta moitié vue de dessus
  const cx = VS.w / 2, tw = 470, far = 0.47;
  c.fillStyle = '#1B4FA8'; c.beginPath(); c.moveTo(cx - tw / 2, SH); c.lineTo(cx + tw / 2, SH); c.lineTo(cx + tw / 2 * far, SH * 0.42); c.lineTo(cx - tw / 2 * far, SH * 0.42); c.closePath(); c.fill();
  c.strokeStyle = '#fff'; c.lineWidth = 4; c.stroke();
  const ng = c.createLinearGradient(0, SH, 0, SH + SH * 0.78); ng.addColorStop(0, '#2A6FD6'); ng.addColorStop(1, '#1B4FA8');
  c.fillStyle = 'rgba(0,0,0,0.35)'; c.fillRect(cx - tw / 2 + 8, SH + 14, tw, SH * 0.78);
  c.fillStyle = ng; c.fillRect(cx - tw / 2, SH, tw, SH * 0.78); c.strokeRect(cx - tw / 2, SH, tw, SH * 0.78);
  c.lineWidth = 2; c.beginPath(); c.moveTo(cx, SH * 0.42); c.lineTo(cx, SH + SH * 0.78); c.stroke();
  // adversaire
  const opp = filetBall(t), ox = cx + (opp.v < 0.5 ? (opp.x - 0.5) * tw * 0.5 : 0) + 60;
  c.fillStyle = '#FF8A3D'; rr(c, ox - 34, SH * 0.2, 68, 120, 30); c.fill();
  shadedBall(c, ox, SH * 0.17, 26, '#F2C29B', '#FFE6D0');
  c.fillStyle = '#2B2B38'; c.beginPath(); c.arc(ox - 70, SH * 0.3, 26, 0, 7); c.fill();
  // filet
  c.fillStyle = 'rgba(11,14,28,0.5)'; c.fillRect(cx - tw / 2 - 30, SH - 46, tw + 60, 46); c.fillStyle = '#fff'; c.fillRect(cx - tw / 2 - 30, SH - 46, tw + 60, 5);
  // balle
  const b = filetBall(t);
  const project = (x, v) => v < 0.5
    ? (() => { const k = (0.5 - v) / 0.5, s = lerp(1, far, clamp(k / 0.85)); return [cx + (x - 0.5) * tw * s, lerp(SH, SH * 0.42, clamp(k / 0.85))]; })()
    : [cx + (x - 0.5) * tw, SH + (v - 0.5) / 0.5 * SH * 0.9];
  const [bxp, byp] = project(b.x, b.v);
  c.fillStyle = 'rgba(0,0,0,0.3)'; c.beginPath(); c.ellipse(bxp, byp, 14, 7, 0, 0, 7); c.fill();
  shadedBall(c, bxp, byp - b.z * 420, 13, '#FFF6E6');
  // ta raquette
  const pv = Math.min(0.95, Math.max(0.78, b.v)), [rx, ry] = project(b.v > 0.6 ? b.x : 0.5, 0.86);
  c.save(); c.translate(rx + 30, ry); c.rotate(0.25);
  c.fillStyle = '#C8904F'; rr(c, -9, 34, 18, 46, 6); c.fill(); c.fillStyle = '#1A1A1A'; c.beginPath(); c.arc(0, 0, 50, 0, 7); c.fill();
  const pr = c.createRadialGradient(-15, -18, 0, 0, 0, 70); pr.addColorStop(0, '#FF6B75'); pr.addColorStop(1, '#C02030'); c.fillStyle = pr; c.beginPath(); c.arc(0, 0, 47, 0, 7); c.fill(); c.restore();
}

// AIR HOCKEY : table néon, la charnière au milieu
function puckAt(t) {
  const K = CUES.hockey; if (t < K[0][0]) return { x: K[0][1], v: K[0][2] };
  let i = 0; while (i < K.length - 2 && t >= K[i + 1][0]) i++;
  const a = K[i], b = K[i + 1], k = clamp((t - a[0]) / (b[0] - a[0]));
  return { x: lerp(a[1], b[1], k), v: lerp(a[2], b[2], k) };
}
function screenHockey(c, t) {
  c.fillStyle = '#070B26'; c.fillRect(0, 0, VS.w, VS.h);
  const rg = c.createRadialGradient(VS.w / 2, VS.h / 2, 0, VS.w / 2, VS.h / 2, VS.h * 0.6); rg.addColorStop(0, 'rgba(42,60,255,0.22)'); rg.addColorStop(1, 'rgba(0,0,0,0)'); c.fillStyle = rg; c.fillRect(0, 0, VS.w, VS.h);
  for (let x = 12; x < VS.w; x += 26) for (let y = 12; y < VS.h; y += 26) { c.fillStyle = 'rgba(255,255,255,0.06)'; c.fillRect(x, y, 2, 2); }
  const neon = (draw, col, w) => { c.save(); c.shadowColor = col; c.shadowBlur = w * 4; c.strokeStyle = col; c.lineWidth = w; draw(); c.stroke(); c.restore(); c.strokeStyle = 'rgba(255,255,255,0.6)'; c.lineWidth = w * 0.3; draw(); c.stroke(); };
  neon(() => { c.beginPath(); c.roundRect(8, 8, VS.w - 16, VS.h - 16, 30); }, '#7B5CFF', 5);
  c.setLineDash([22, 16]); neon(() => { c.beginPath(); c.moveTo(0, VS.h / 2); c.lineTo(VS.w, VS.h / 2); }, '#FF4A5A', 4); c.setLineDash([]);
  neon(() => { c.beginPath(); c.arc(VS.w / 2, VS.h / 2, 110, 0, 7); }, '#FF4A5A', 3);
  neon(() => { c.beginPath(); c.moveTo(VS.w * 0.3, 10); c.lineTo(VS.w * 0.7, 10); }, '#3DE0FF', 10);
  neon(() => { c.beginPath(); c.moveTo(VS.w * 0.3, VS.h - 10); c.lineTo(VS.w * 0.7, VS.h - 10); }, '#FF5C4D', 10);
  const p = puckAt(t), P = [p.x * VS.w, p.v * VS.h];
  for (let k = 1; k <= 10; k++) { const q = puckAt(t - k * 0.018); c.fillStyle = `rgba(61,224,255,${0.25 * (1 - k / 11)})`; c.beginPath(); c.arc(q.x * VS.w, q.v * VS.h, 30 * (1 - k / 14), 0, 7); c.fill(); }
  const goal = t >= CUES.hockey[CUES.hockey.length - 1][0];
  const mallet = (x, y, col) => { c.save(); c.shadowColor = col; c.shadowBlur = 40; shadedBall(c, x, y, 58, col); c.restore(); c.fillStyle = 'rgba(255,255,255,0.35)'; c.beginPath(); c.arc(x, y, 26, 0, 7); c.fill(); };
  const bottomX = p.v > 0.5 ? lerp(VS.w / 2, P[0], 0.85) : VS.w / 2 + 120 * Math.sin(t * 2), topX = p.v < 0.5 ? lerp(VS.w / 2, P[0], 0.8) : VS.w / 2 - 100 * Math.sin(t * 2.3);
  mallet(bottomX, Math.max(VS.h * 0.62, Math.min(VS.h * 0.86, P[1] + 70)), '#FF5C4D');
  mallet(topX, Math.min(VS.h * 0.36, Math.max(VS.h * 0.12, P[1] - 70)), '#3DE0FF');
  if (!goal) { c.save(); c.shadowColor = '#3DE0FF'; c.shadowBlur = 30; c.fillStyle = '#111'; c.beginPath(); c.arc(P[0], P[1], 32, 0, 7); c.fill(); c.strokeStyle = '#3DE0FF'; c.lineWidth = 5; c.stroke(); c.restore(); }
  if (goal) { c.save(); c.shadowColor = '#FF4F9A'; c.shadowBlur = 40; text(c, T.goal, VS.w / 2, VS.h / 2, 150, '#fff', 900); c.restore(); }
}

// FERME : l'écran extérieur, la plante pousse
function screenOuter(c, t) {
  const w = SW, h = SH;
  const g = c.createLinearGradient(0, 0, 0, h); g.addColorStop(0, '#0F2A22'); g.addColorStop(1, '#09140F'); c.fillStyle = g; c.fillRect(0, 0, w, h);
  const grow = clamp((t - CUES.fermeClose - 0.1) / 1.15);
  const cx = w * 0.36, base = h * 0.84;
  // halo
  const halo = c.createRadialGradient(cx, base - 220 * grow, 0, cx, base - 220 * grow, 220); halo.addColorStop(0, `rgba(255,154,196,${0.35 * grow})`); halo.addColorStop(1, 'rgba(255,154,196,0)'); c.fillStyle = halo; c.fillRect(0, 0, w, h);
  // pot
  const pg = c.createLinearGradient(cx - 80, 0, cx + 80, 0); pg.addColorStop(0, '#E08A5C'); pg.addColorStop(0.5, '#C8673E'); pg.addColorStop(1, '#8F4426');
  c.fillStyle = pg; c.beginPath(); c.moveTo(cx - 80, base - 90); c.lineTo(cx + 80, base - 90); c.lineTo(cx + 60, base); c.lineTo(cx - 60, base); c.closePath(); c.fill();
  c.fillStyle = '#D9784D'; rr(c, cx - 92, base - 108, 184, 24, 8); c.fill(); c.fillStyle = '#3B2416'; c.beginPath(); c.ellipse(cx, base - 100, 82, 9, 0, 0, 7); c.fill();
  // tige, feuilles, fleur
  const top = base - 100 - 260 * grow;
  c.strokeStyle = '#5BBF6A'; c.lineWidth = 9; c.lineCap = 'round'; c.beginPath(); c.moveTo(cx, base - 100); c.quadraticCurveTo(cx + 30, (base - 100 + top) / 2, cx, top); c.stroke();
  [[0.35, -1], [0.6, 1], [0.8, -1]].forEach(([k, side]) => { if (grow < k * 0.9) return; const y = lerp(base - 100, top, k);
    c.fillStyle = '#4FA65C'; c.beginPath(); c.moveTo(cx + 8, y); c.quadraticCurveTo(cx + side * 60, y - 50, cx + side * 90, y - 20); c.quadraticCurveTo(cx + side * 50, y + 10, cx + 8, y); c.fill(); });
  const bloom = clamp((t - CUES.fermeBloom + 0.25) / 0.4);
  if (bloom > 0) {
    for (let k = 0; k < 8; k++) { const a = k * Math.PI / 4 + t * 0.3; const r = 34 * Math.max(0.01, back(bloom));
      const pgr = c.createRadialGradient(cx, top, 0, cx, top, r * 2); pgr.addColorStop(0, '#FFD1E3'); pgr.addColorStop(1, '#FF6FA8');
      c.fillStyle = pgr; c.beginPath(); c.arc(cx + Math.cos(a) * r, top + Math.sin(a) * r, r * 0.7, 0, 7); c.fill(); }
    shadedBall(c, cx, top, 22 * Math.max(0.01, back(bloom)), '#C8902E', '#FFE27A');
  }
  // minuteur
  const total = 25 * 60 - Math.floor(clamp((t - CUES.fermeClose) / 1.7) * 25 * 60);
  const tx = w * 0.72;
  c.strokeStyle = 'rgba(95,211,160,0.2)'; c.lineWidth = 14; c.beginPath(); c.arc(tx, h * 0.48, 110, 0, 7); c.stroke();
  c.strokeStyle = '#5FD3A0'; c.lineCap = 'round'; c.beginPath(); c.arc(tx, h * 0.48, 110, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (1 - total / 1500)); c.stroke();
  text(c, `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`, tx, h * 0.46, 52, '#fff', 900);
  text(c, T.focus, tx, h * 0.56, 22, '#5FD3A0', 800);
}

function renderScreens(t, p) {
  const s = scene(t)[0];
  fx.setTransform(1, 0, 0, 1, 0, 0);
  let hit = false;
  if (s === 'hook' || s === 'grid' || s === 'end') screenHub(fx, t);
  else if (s === 'rayon') hit = screenRayon(fx, t, p.fold);
  else if (s === 'chess') screenChess(fx, t);
  else if (s === 'piano') screenPiano(fx, t);
  else if (s === 'filet') screenFilet(fx, t);
  else if (s === 'hockey') screenHockey(fx, t);
  else if (s === 'ferme') screenHub(fx, t);
  topC.drawImage(full, 0, 0, SW, SH, 0, 0, SW, SH);
  botC.drawImage(full, 0, SH, SW, SH, 0, 0, SW, SH);
  // écran éteint pendant la fermeture
  if (s === 'ferme') { const k = clamp((t - 16.7) / 0.5); topC.fillStyle = botC.fillStyle = `rgba(0,0,0,${0.85 * k})`; topC.fillRect(0, 0, SW, SH); botC.fillRect(0, 0, SW, SH); }
  screenOuter(outC, t);
  // Reflet sur la vitre
  for (const c of [topC, botC]) { const g = c.createLinearGradient(0, 0, SW, SH); g.addColorStop(0, 'rgba(255,255,255,0.10)'); g.addColorStop(0.4, 'rgba(255,255,255,0)'); c.fillStyle = g; c.fillRect(0, 0, SW, SH); }
  return hit;
}

// ------------------------------------------------------------------ textes
const headline = document.getElementById('headline'), sub = document.getElementById('sub');
let lastKey = '';
function setText(el, s) {
  // *mots* = mots en couleur (même sur plusieurs mots)
  let accent = false;
  el.innerHTML = s.split(' ').map((w, i) => {
    const start = w.startsWith('*'), end = w.endsWith('*');
    if (start) accent = true;
    const clean = w.replace(/\*/g, '');
    const html = `<span class="w" style="--i:${i}">${accent ? '<b>' + clean + '</b>' : clean}</span>`;
    if (end) accent = false;
    return html;
  }).join(' ');
}
function renderText(t) {
  const s = scene(t), key = s[0];
  const tx = T.scenes[key];
  if (key !== lastKey) { lastKey = key; if (tx) { setText(headline, tx[0]); sub.textContent = tx[1] || ''; } else { headline.innerHTML = ''; sub.textContent = ''; } }
  const local = t - s[1], outK = clamp((s[2] - t) / 0.25);
  headline.querySelectorAll('.w').forEach(el => {
    const i = parseInt(el.style.getPropertyValue('--i')); const k = easeOut((local - 0.08 - i * 0.07) / 0.35);
    el.style.opacity = k * outK; el.style.transform = `translateY(${(1 - k) * 60}px) scale(${0.9 + 0.1 * k})`;
  });
  const ks = easeOut((local - 0.35) / 0.4); sub.style.opacity = ks * outK; sub.style.transform = `translateY(${(1 - ks) * 30}px)`;
  document.getElementById('texts').style.display = key === 'end' || key === 'grid' ? 'none' : 'block';
}

// ------------------------------------------------------------------ mosaïque des 13 jeux
const GRID_COLORS = ['#3DE0FF', '#FF4F9A', '#8BDB4F', '#FFC53D', '#FF8A3D', '#5B8CFF', '#E84C5A', '#3DE0FF', '#E3B66E', '#E07A5F', '#C9A2FF', '#FF7A2F', '#5FD3A0'];
const gc = document.getElementById('grid').getContext('2d');
function glyph(c, i, x, y, s, t) {
  c.save(); c.translate(x, y); c.lineCap = 'round'; c.lineJoin = 'round'; c.strokeStyle = '#0E1020'; c.fillStyle = '#0E1020'; c.lineWidth = s * 0.09;
  const L = s;
  switch (i) {
    case 0: c.beginPath(); c.moveTo(-L * .35, L * .3); c.lineTo(0, -L * .05); c.lineTo(L * .3, L * .1); c.lineTo(L * .35, -L * .32); c.stroke(); c.beginPath(); c.arc(L * .35, -L * .32, L * .08, 0, 7); c.fill(); break;
    case 1: c.beginPath(); c.arc(0, 0, L * .3, 0, 7); c.stroke(); [[-.1, -.12], [.12, -.08], [.05, .14]].forEach(([a, b]) => { c.beginPath(); c.arc(a * L, b * L, L * .06, 0, 7); c.fill(); }); break;
    case 2: c.beginPath(); c.moveTo(-L * .35, L * .25); c.lineTo(L * .3, -L * .2); c.stroke(); c.beginPath(); c.arc(-L * .05, -L * .22, L * .09, 0, 7); c.fill(); break;
    case 3: c.beginPath(); c.arc(0, 0, L * .32, 0, 7); c.stroke(); c.beginPath(); c.moveTo(0, 0); c.lineTo(L * .18, -L * .15); c.stroke(); break;
    case 4: c.beginPath(); c.arc(0, 0, L * .3, 0, 7); c.stroke(); c.beginPath(); c.moveTo(-L * .3, 0); c.lineTo(L * .3, 0); c.moveTo(0, -L * .3); c.lineTo(0, L * .3); c.stroke(); break;
    case 5: c.beginPath(); c.arc(-L * .05, -L * .05, L * .22, 0, 7); c.fill(); c.beginPath(); c.moveTo(L * .1, L * .12); c.lineTo(L * .3, L * .32); c.stroke(); c.beginPath(); c.arc(L * .28, -L * .28, L * .07, 0, 7); c.fill(); break;
    case 6: [0.32, 0.2, 0.08].forEach(r => { c.beginPath(); c.arc(0, 0, L * r, 0, 7); c.stroke(); }); break;
    case 7: c.beginPath(); c.arc(0, 0, L * .3, 0, 7); c.stroke(); c.beginPath(); c.arc(0, 0, L * .14, 0, 7); c.fill(); break;
    case 8: c.restore(); drawPiece(c, 'knight', true, x, y, L * 0.85); return;
    case 9: c.lineWidth = s * 0.06; c.beginPath(); c.arc(0, L * .06, L * .3, 0, 7); c.stroke(); c.beginPath(); c.arc(0, -L * .04, L * .3, 0, 7); c.fill(); break;
    case 10: for (let k = 0; k < 5; k++) { c.strokeRect(-L * .35 + k * L * .14, -L * .25, L * .14, L * .5); } [1, 2, 4].forEach(k => c.fillRect(-L * .35 + k * L * .14 - L * .04, -L * .25, L * .08, L * .3)); break;
    case 11: c.beginPath(); c.arc(0, 0, L * .16, 0, 7); c.fill(); for (let k = 0; k < 8; k++) { const a = k * Math.PI / 4; c.beginPath(); c.moveTo(Math.cos(a) * L * .24, Math.sin(a) * L * .24); c.lineTo(Math.cos(a) * L * .36, Math.sin(a) * L * .36); c.stroke(); } break;
    case 12: c.beginPath(); c.moveTo(0, L * .32); c.quadraticCurveTo(-L * .35, 0, 0, -L * .32); c.quadraticCurveTo(L * .35, 0, 0, L * .32); c.fill(); break;
  }
  c.restore();
}
function renderGrid(t) {
  gc.clearRect(0, 0, W, H);
  const s = scene(t)[0];
  if (s !== 'grid') { document.getElementById('grid').style.opacity = 0; return; }
  const out = clamp((21.6 - t) / 0.3);
  document.getElementById('grid').style.opacity = out;
  // titre
  const kt = easeOut((t - 19.05) / 0.4);
  gc.save(); gc.globalAlpha = kt; gc.translate(W / 2, 330 - (1 - kt) * 40);
  gc.font = '900 150px "Inter Display"'; gc.textAlign = 'center'; gc.textBaseline = 'middle';
  const tg = gc.createLinearGradient(-300, 0, 300, 0); ['#3DE0FF', '#FF4F9A', '#FFC53D'].forEach((c, i) => tg.addColorStop(i / 2, c)); gc.fillStyle = tg;
  gc.fillText(T.scenes.grid[0], 0, 0); gc.font = '700 46px Inter'; gc.fillStyle = '#fff'; gc.fillText(T.scenes.grid[1], 0, 110); gc.restore();
  const cols = 3, tw = 290, th = 230, gx = (W - cols * tw - 2 * 30) / 2, gy = 560;
  T.names.forEach((name, i) => {
    const k = back((t - CUES.gridPops[i]) / 0.3); if (k <= 0) return;
    const lastRow = i >= 12, cx = lastRow ? W / 2 : gx + (i % cols) * (tw + 30) + tw / 2, cy = gy + Math.floor(i / cols) * (th + 22) + th / 2;
    gc.save(); gc.translate(cx, cy); gc.scale(k, k); gc.globalAlpha = clamp(k);
    rr(gc, -tw / 2, -th / 2, tw, th, 34); gc.fillStyle = 'rgba(255,255,255,0.09)'; gc.fill(); gc.strokeStyle = GRID_COLORS[i] + 'aa'; gc.lineWidth = 3; gc.stroke();
    const ig = gc.createLinearGradient(-60, -100, 60, 20); ig.addColorStop(0, GRID_COLORS[i]); ig.addColorStop(1, GRID_COLORS[i] + '88');
    rr(gc, -62, -98, 124, 124, 30); gc.fillStyle = ig; gc.fill();
    gc.restore();
    glyph(gc, i, cx, cy - 36 * k, Math.max(1, 120 * k), t);
    gc.save(); gc.globalAlpha = clamp(k); gc.font = `900 ${name.length > 12 ? 24 : 30}px Inter`; gc.fillStyle = '#fff'; gc.textAlign = 'center'; gc.textBaseline = 'middle';
    gc.fillText(name, cx, cy + 78 * k); gc.restore();
  });
}

// ------------------------------------------------------------------ fin
const ec = document.getElementById('endc').getContext('2d');
const icon = new Image(); icon.src = ICON;
const conf = Array.from({ length: 140 }, (_, i) => ({ x: hash(i, 1), vx: (hash(i, 2) - 0.5) * 0.25, vy: 0.3 + hash(i, 3), spin: hash(i, 4) * 6, size: 14 + 14 * hash(i, 5), col: GRID_COLORS[i % 13], d: hash(i, 6) * 0.5 }));
function renderEnd(t) {
  ec.clearRect(0, 0, W, H);
  if (t < 21.6) { document.getElementById('endc').style.opacity = 0; return; }
  document.getElementById('endc').style.opacity = 1;
  const k = back((t - 21.7) / 0.6), ki = easeOut((t - 21.7) / 0.5);
  // halo et icône
  const halo = ec.createRadialGradient(W / 2, 760, 0, W / 2, 760, 520); halo.addColorStop(0, `rgba(255,111,200,${0.45 * ki})`); halo.addColorStop(1, 'rgba(0,0,0,0)'); ec.fillStyle = halo; ec.fillRect(0, 0, W, H);
  if (icon.complete) {
    ec.save(); ec.translate(W / 2, 760); ec.rotate((1 - ki) * -0.5 + Math.sin(t * 1.5) * 0.03); ec.scale(k, k);
    ec.shadowColor = 'rgba(0,0,0,0.5)'; ec.shadowBlur = 50; ec.shadowOffsetY = 20;
    rr(ec, -230, -230, 460, 460, 104); ec.save(); ec.clip(); ec.drawImage(icon, -230, -230, 460, 460); ec.restore(); ec.restore();
  }
  const kt = easeOut((t - 22.1) / 0.5);
  ec.save(); ec.globalAlpha = kt; ec.translate(W / 2, 1150 + (1 - kt) * 40);
  const tg = ec.createLinearGradient(-330, 0, 330, 0); ['#3DE0FF', '#FF4F9A', '#FFC53D', '#FF7A2F'].forEach((c, i) => tg.addColorStop(i / 3, c));
  ec.font = '900 168px "Inter Display"'; ec.textAlign = 'center'; ec.textBaseline = 'middle'; ec.fillStyle = tg; ec.fillText('ORIGAMO', 0, 0);
  ec.font = '700 50px Inter'; ec.fillStyle = '#fff'; ec.fillText(T.made, 0, 120); ec.restore();
  const kc = back((t - 22.6) / 0.5);
  if (kc > 0) {
    ec.save(); ec.translate(W / 2, 1420); ec.scale(kc, kc);
    ec.font = '900 46px Inter'; const wpx = ec.measureText(T.cta).width + 100;
    rr(ec, -wpx / 2, -52, wpx, 104, 52); const cg = ec.createLinearGradient(-wpx / 2, 0, wpx / 2, 0); cg.addColorStop(0, '#FFC53D'); cg.addColorStop(1, '#FF8A3D'); ec.fillStyle = cg; ec.fill();
    ec.fillStyle = '#0E1020'; ec.textAlign = 'center'; ec.textBaseline = 'middle'; ec.fillText(T.cta, 0, 2); ec.restore();
  }
  // confettis
  const lt = t - 21.9;
  if (lt > 0) for (const p of conf) {
    const tt = lt - p.d; if (tt < 0) continue;
    const x = (p.x + p.vx * tt) * W + Math.sin(tt * 3 + p.spin) * 20, y = -40 + (p.vy * tt + 0.5 * tt * tt) * H * 0.33;
    if (y > H + 40) continue;
    ec.save(); ec.translate(x, y); ec.rotate(p.spin + tt * 5); ec.globalAlpha = clamp((3.2 - tt) / 0.8); ec.fillStyle = p.col; ec.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2); ec.restore();
  }
}

// ------------------------------------------------------------------ appareil
const dev = document.getElementById('device'), topP = document.getElementById('top'), cam = document.getElementById('cam');
function renderDevice(t, p) {
  cam.style.opacity = p.show;
  cam.style.transform = `translate(${W / 2}px, ${1040 + p.y}px)`;
  dev.style.transform = `rotateX(${p.tilt}deg) rotateZ(${p.rz}deg) scale(${p.s})`;
  topP.style.transform = `rotateX(${-(180 - p.fold)}deg)`;
}

window.render = function (t) {
  drawBackground(t);
  const p = pose(t);
  renderDevice(t, p);
  renderScreens(t, p);
  renderText(t);
  renderGrid(t);
  renderEnd(t);
};
window.ready = () => document.fonts.ready.then(() => icon.decode().catch(() => {})).then(() => true);
