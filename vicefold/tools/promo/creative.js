// VICEFOLD: the App Store header video (21:9) and the search results video (3:2), on the same model as Foldly's:
// a light page, the name and the title on the left (centred for search), three labels, and an iPhone Duo that turns,
// folds and shows three screens of the app. A silent 12 s loop with no jump; the title is on every frame, so any
// frame can be the poster.
const Q = new URLSearchParams(location.search);
const KIND = Q.get('kind') || 'header', LANG = Q.get('lang') || 'en';
const HD = KIND === 'header';
const W = HD ? 1920 : 1200, H = HD ? 823 : 800, DUR = 12;
const T = TEXTS[LANG], PRE = LANG === 'en' ? '' : LANG + '-';
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const lerp = (a, b, k) => a + (b - a) * k;
const eio = k => { k = clamp(k); return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2; };
function el(tag, cls, parent, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; if (parent) parent.appendChild(e); return e; }
const TAU = Math.PI * 2;
const stage = document.getElementById('stage');
stage.style.width = W + 'px'; stage.style.height = H + 'px'; stage.className = KIND;

// ---------------------------------------------------------------- the page: off-white, with soft glows that drift
const bgc = document.getElementById('bg'); bgc.width = W; bgc.height = H;
const bg = bgc.getContext('2d');
function drawBg(t) {
  const a = t / DUR * TAU;
  bg.fillStyle = '#F4F7F8'; bg.fillRect(0, 0, W, H);
  const R = Math.max(W, H);
  const spots = [[0.3 + 0.05 * Math.cos(a), 0.62 + 0.06 * Math.sin(a), 0.42, '255,138,61', 0.13], [0.86 + 0.04 * Math.sin(a), 0.2 + 0.05 * Math.cos(a), 0.4, '255,79,139', 0.11],
    [0.62 + 0.05 * Math.cos(a + 2), 0.9 + 0.04 * Math.sin(a + 2), 0.45, '75,163,255', 0.12], [0.08 + 0.03 * Math.sin(a + 1), 0.1, 0.36, '20,176,138', 0.09]];
  for (const [x, y, r, c, al] of spots) {
    const g = bg.createRadialGradient(x * W, y * H, 0, x * W, y * H, r * R);
    g.addColorStop(0, `rgba(${c},${al})`); g.addColorStop(1, `rgba(${c},0)`);
    bg.fillStyle = g; bg.fillRect(0, 0, W, H);
  }
}

// ---------------------------------------------------------------- words (they never move)
const txt = el('div', 'txt', stage);
const brand = el('div', 'brand', txt); el('img', '', brand).src = 'icon.png'; el('span', '', brand, T.brand);
const title = el('div', 'title', txt);
el('div', '', title, T.title[0]); el('div', 'acc', title, T.title[1]);
el('div', 'sub', txt, T.sub);
const chips = el('div', 'chips', txt); T.chips.forEach(c => el('span', '', chips, c));

// ---------------------------------------------------------------- the iPhone Duo: two halves around a hinge
const persp = el('div', 'persp', stage);
const SHOTS = ['duo-1', 'duo-2', 'duo-5'];
const BOX = HD ? { cx: 1340, cy: 398, w: 710 } : { cx: 600, cy: 540, w: 520 };
const [sw, sh] = DATA.sizes[PRE + SHOTS[0]];
const DW = BOX.w, DH = DW * sh / sw;
const ground = el('div', 'ground', persp);
Object.assign(ground.style, { left: BOX.cx - DW * 0.42 + 'px', top: BOX.cy + DH * 0.6 + 'px', width: DW * 0.84 + 'px', height: DH * 0.12 + 'px' });
const dev = el('div', 'dev', persp);
Object.assign(dev.style, { left: BOX.cx - DW / 2 + 'px', top: BOX.cy - DH / 2 + 'px', width: DW + 'px', height: DH + 'px' });
dev.style.setProperty('--r', DW * 0.062 + 'px'); dev.style.setProperty('--bz', DW * 0.016 + 'px');
const halves = ['right', 'left'].map(side => {
  const half = el('div', 'half ' + side, dev);
  const face = el('div', 'face', half);
  const imgs = SHOTS.map(s => { const i = el('img', '', face); i.src = PRE + s + '.png'; i.style.width = DW + 'px'; i.style.height = DH + 'px'; if (side === 'right') i.style.marginLeft = -DW / 2 + 'px'; return i; });
  el('div', 'shade', face);
  return { half, imgs, shade: face.lastChild };
});
const hinge = el('div', 'hinge', dev);
// Three poses of 4 s each: [turn, tilt, roll, fold of the left half, size]. The move takes 1.2 s around each change.
const POSES = [[-16, 7, 2.5, 0, 1], [13, 9, -3, 0, 1.03], [-22, 13, 1.5, 34, 0.98]];
function render(t) {
  drawBg(t);
  const n = POSES.length, step = DUR / n, tt = (t % DUR + DUR) % DUR;
  const i = Math.floor(tt / step), u = tt - i * step;
  // The move straddles the boundary: it starts 0.6 s before and ends 0.6 s after.
  let from = POSES[i], to = POSES[i], k = 0;
  if (u > step - 0.6) { to = POSES[(i + 1) % n]; k = eio((u - (step - 0.6)) / 1.2); }
  else if (u < 0.6) { from = POSES[(i + n - 1) % n]; k = eio((u + 0.6) / 1.2); }
  const p = from.map((v, j) => lerp(v, to[j], k));
  const a = t / DUR * TAU;
  dev.style.transform = `translateY(${Math.sin(a * 2) * 6}px) rotateY(${p[0] + Math.sin(a * 3) * 1.5}deg) rotateX(${p[1] + Math.cos(a * 2) * 1}deg) rotateZ(${p[2]}deg) scale(${p[4]})`;
  halves[1].half.style.transform = `rotateY(${p[3]}deg)`;
  halves[1].shade.style.opacity = p[3] / 34 * 0.14;
  hinge.style.opacity = 1;
  ground.style.transform = `scaleX(${1 - p[3] / 34 * 0.14}) translateX(${p[0] * 1.2}px)`;
  // The screen changes with the pose, in the middle of the move.
  halves.forEach(h => h.imgs.forEach((img, j) => {
    let dt = tt - j * step; if (dt > DUR / 2) dt -= DUR; if (dt < -DUR / 2) dt += DUR;
    // The new screen fades in over the one before, which stays whole underneath (no see-through moment).
    const arriving = dt >= -0.15 && dt < 0.15, showing = dt >= 0.15 && dt < step + 0.15;
    img.style.opacity = arriving ? eio((dt + 0.15) / 0.3) : showing ? 1 : 0;
    img.style.zIndex = arriving ? 2 : 1;
  }));
}
async function ready() {
  await document.fonts.load("900 100px 'Inter Display'"); await document.fonts.load('600 30px Inter'); await document.fonts.ready;
  await Promise.all([...document.images].map(i => i.decode().catch(() => 0)));
  return true;
}
