// VICEFOLD promo video: drawn frame by frame, render(t) shows the instant t (seconds).
// Two formats: wide (1920x1080, for X) and tall (1080x1920, for vertical feeds). Every screen shown is a real
// capture of the app; the map is the community map bundled with the app (GTADB.org, CC BY 4.0).
const Q = new URLSearchParams(location.search);
const FMT = Q.get('fmt') || 'wide', CTA = Q.get('cta') || 'now', LINK = Q.get('link') || '';
const L = FMT === 'wide';
const W = L ? 1920 : 1080, H = L ? 1080 : 1920;
// Where the device stands, and where the words go.
const BOX = L ? { cx: 1390, cy: 520, w: 900, h: 840 } : { cx: 540, cy: 1190, w: 950, h: 1000 };
const TXT = L ? { x: 110, w: 790, cy: 505, size: 132 } : { x: 60, w: 960, top: 150, size: 124 };

const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const lerp = (a, b, k) => a + (b - a) * k;
const eo = k => 1 - Math.pow(1 - clamp(k), 3);
const eio = k => { k = clamp(k); return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2; };
const back = k => { k = clamp(k); const c = 1.9; return 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2); };
function hash(i, s = 0) { let x = (Math.imul(i + 1, 2654435761) + Math.imul(s + 1, 40503) + 97) >>> 0; x = (x ^ (x >>> 13)) >>> 0; x = Math.imul(x, 0x5bd1e995) >>> 0; x = (x ^ (x >>> 15)) >>> 0; return (x % 10000) / 10000; }
function el(tag, cls, parent, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; if (parent) parent.appendChild(e); return e; }
const stage = document.getElementById('stage');
stage.style.width = W + 'px'; stage.style.height = H + 'px';
if (DATA.dark) stage.classList.add('dark');
const COLORS = { flamingo: '#FF4F8B', sunset: '#FF8A3D', sun: '#FFC94A', palm: '#14B08A', sky: '#4BA3FF', violet: '#7B5CFF' };

// ---------------------------------------------------------------- background: the map of Leonida, then the night
const bgc = document.getElementById('bg'); bgc.width = W; bgc.height = H;
const bg = bgc.getContext('2d');
const MAP = new Image(); MAP.src = 'map.jpg';
const KIND = { landmark: COLORS.flamingo, hotel: '#D6336C', food: COLORS.sunset, shop: COLORS.sky, transport: '#5B6CFF', activity: COLORS.palm,
  nature: '#2FA36B', public: COLORS.violet, gas: COLORS.sun, property: COLORS.sun, other: '#EAF6F5' };
// The first scenes, whose times the background follows: the hook, the introduction, the map, then the rest.
const AT = name => CUES.scenes.find(s => s[0] === name)[1];
const T1 = AT('intro'), T2 = AT('map'), T3 = AT('missions'), TEND = CUES.scenes[CUES.scenes.length - 1][2];
const PINS = DATA.places.map((p, i) => ({ x: p[0], y: p[1], kind: p[2], at: 0.4 + (T2 + 1.2) * hash(i, 3) }));
// The camera over the map: [time, centre x, centre y (0-1 on the map), screen pixels per map pixel].
const CAM = L
  ? [[0, 0.74, 0.5, 1.45], [T1, 0.6, 0.5, 0.62], [T2, 0.5, 0.49, 0.5], [T3, 0.42, 0.47, 0.56], [TEND, 0.5, 0.42, 0.7]]
  : [[0, 0.745, 0.5, 1.5], [T1, 0.62, 0.52, 0.66], [T2, 0.5, 0.5, 0.47], [T3, 0.5, 0.42, 0.52], [TEND, 0.5, 0.4, 0.66]];
const DIM = [[0, 0.2], [T1 - 0.15, 0.24], [T1 + 0.3, 0.66], [T2, 0.6], [T2 + 0.4, 0.46], [T3 - 0.2, 0.5], [T3 + 0.25, 0.9], [TEND, 0.9]];
function key(keys, t, n) {
  for (let i = 1; i < keys.length; i++) if (t <= keys[i][0]) {
    const a = keys[i - 1], b = keys[i], k = eio((t - a[0]) / (b[0] - a[0]));
    return n === 1 ? lerp(a[1], b[1], k) : a.slice(1).map((v, j) => lerp(v, b[j + 1], k));
  }
  return n === 1 ? keys[keys.length - 1][1] : keys[keys.length - 1].slice(1);
}
function drawBg(t) {
  const [cx, cy, sc] = key(CAM, t);
  const dim = key(DIM, t, 1);
  bg.setTransform(1, 0, 0, 1, 0, 0);
  bg.fillStyle = '#2C67A4'; bg.fillRect(0, 0, W, H);
  const ox = W / 2 - cx * MAP.width * sc, oy = H / 2 - cy * MAP.height * sc;
  bg.imageSmoothingQuality = 'high';
  bg.drawImage(MAP, ox, oy, MAP.width * sc, MAP.height * sc);
  if (t < T3 + 1) {
    const fade = 1 - clamp((t - T3) / 0.6);
    for (const p of PINS) {
      const k = back((t - p.at) / 0.35);
      if (k <= 0) continue;
      const x = ox + p.x * MAP.width * sc, y = oy + p.y * MAP.height * sc;
      if (x < -20 || x > W + 20 || y < -20 || y > H + 20) continue;
      const small = p.kind === 'other', r = (small ? 5 : 10) * k * (L ? 1 : 0.95);
      bg.globalAlpha = fade * (small ? 0.85 : 1);
      bg.beginPath(); bg.arc(x, y, r + (small ? 1.5 : 3), 0, 6.283); bg.fillStyle = small ? 'rgba(14,27,43,.55)' : '#fff'; bg.fill();
      bg.beginPath(); bg.arc(x, y, r, 0, 6.283); bg.fillStyle = KIND[p.kind] || '#fff'; bg.fill();
    }
    bg.globalAlpha = 1;
  }
  // Night falls on the map; the side with the words is darker.
  bg.fillStyle = `rgba(9,20,34,${dim})`; bg.fillRect(0, 0, W, H);
  const side = clamp((t - (T2 - 0.3)) / 0.5) * (1 - clamp((t - T3) / 0.4)) * 0.78 + (t < T2 ? clamp((t - T1) / 0.3) * 0.2 : 0);
  if (side > 0.01) {
    const g = L ? bg.createLinearGradient(0, 0, W * 0.62, 0) : bg.createLinearGradient(0, 0, 0, H * 0.5);
    g.addColorStop(0, `rgba(9,20,34,${side})`); g.addColorStop(0.55, `rgba(9,20,34,${side * 0.85})`); g.addColorStop(1, 'rgba(9,20,34,0)');
    bg.fillStyle = g; bg.fillRect(0, 0, W, H);
  }
  if (t < T1 + 0.2) {
    const a = 0.62 * (1 - clamp((t - (T1 - 0.1)) / 0.3));
    const g = bg.createRadialGradient(W / 2, H * 0.48, 0, W / 2, H * 0.48, Math.min(W, H) * 0.75);
    g.addColorStop(0, `rgba(9,20,34,${a})`); g.addColorStop(1, 'rgba(9,20,34,0)');
    bg.fillStyle = g; bg.fillRect(0, 0, W, H);
  }
  // Sunset glows, slowly moving.
  const glow = clamp((t - (T1 - 0.1)) / 0.6) * 0.9 + 0.1;
  bg.globalCompositeOperation = 'lighter';
  const R = Math.max(W, H);
  const spots = [[W * (0.92 + 0.04 * Math.sin(t * 0.5)), H * -0.05, R * 0.75, '255,138,61', 0.3], [W * (0.02 + 0.05 * Math.cos(t * 0.4)), H * 1.05, R * 0.7, '255,79,139', 0.3],
    [W * 0.55, H * (0.5 + 0.1 * Math.sin(t * 0.3)), R * 0.6, '91,69,219', 0.14]];
  for (const [x, y, r, c, a] of spots) {
    const g = bg.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `rgba(${c},${a * glow})`); g.addColorStop(1, `rgba(${c},0)`);
    bg.fillStyle = g; bg.fillRect(0, 0, W, H);
  }
  bg.globalCompositeOperation = 'source-over';
  // A soft frame so the eye stays in the middle.
  const v = bg.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.45, W / 2, H / 2, R * 0.75);
  v.addColorStop(0, 'rgba(4,10,20,0)'); v.addColorStop(1, 'rgba(4,10,20,.6)');
  bg.fillStyle = v; bg.fillRect(0, 0, W, H);
}

// ---------------------------------------------------------------- words
// A headline is a list of lines; *stars* mark the words in sunset colours; numbers count up as they arrive.
function textBlock(parent, o) {
  const root = el('div', 'txt' + (o.center ? ' center' : ''), parent);
  const kick = o.kicker ? el('div', 'kicker', root) : null;
  if (kick) { el('span', '', kick, o.kicker); if (o.pro) el('b', 'pro', kick, 'PRO'); }
  const head = el('div', 'head', root);
  const words = [];
  o.lines.forEach((line, li) => {
    const ln = el('div', 'line', head);
    let acc = false;
    line.split('*').forEach(part => {
      part.split(' ').filter(Boolean).forEach(wd => {
        const s = el('span', 'w' + (acc ? ' acc' : ''), ln, wd);
        const m = wd.match(/^(\D*)(\d{2,})(.*)$/);
        words.push({ s, li, text: wd, num: m && !o.still ? { pre: m[1], n: +m[2], post: m[3] } : null });
        ln.appendChild(document.createTextNode(' '));
      });
      acc = !acc;
    });
  });
  const sub = o.sub ? el('div', 'sub', root) : null;
  if (sub) sub.innerHTML = o.sub;
  // Size: the widest line fills the column.
  const maxW = o.width || (o.center ? (L ? 1560 : 980) : TXT.w);
  const base = o.size || (o.center ? (L ? 300 : 230) : TXT.size);
  head.style.fontSize = base + 'px';
  root.style.width = '6000px';
  let widest = 0;
  head.querySelectorAll('.line').forEach(ln => { const r = document.createRange(); r.selectNodeContents(ln); widest = Math.max(widest, r.getBoundingClientRect().width); });
  const size = Math.min(base, base * maxW / widest);
  head.style.fontSize = size + 'px';
  root.style.width = maxW + 'px';
  for (const w of words) if (w.num) { w.s.style.width = w.s.getBoundingClientRect().width + 1 + 'px'; w.s.style.textAlign = 'left'; }
  if (o.center) { root.style.left = (W - maxW) / 2 + 'px'; root.style.top = (o.cy != null ? o.cy : H * (L ? 0.5 : 0.42)) - root.offsetHeight / 2 + 'px'; }
  else if (L && !o.top) { root.style.left = TXT.x + 'px'; root.style.top = TXT.cy - root.offsetHeight / 2 + 'px'; }
  else { root.style.left = (W - maxW) / 2 + 'px'; root.style.top = (o.top != null ? o.top : TXT.top) + 'px'; root.classList.add('center'); }
  const at = o.at || 0, step = o.lineStep || 0;
  return {
    root,
    update(u, dur) {
      const end = o.until != null ? o.until : dur, v = u - at;
      const out = clamp((u - (end - 0.14)) / 0.14);
      root.style.opacity = v < 0 || u >= end ? 0 : 1 - out;
      root.style.display = v < -0.05 || u >= end ? 'none' : 'block';
      if (kick) { const k = eo(v / 0.45); kick.style.opacity = k; kick.style.transform = `translateY(${(1 - k) * 18}px)`; }
      words.forEach((w, i) => {
        const t0 = step ? w.li * step : 0.1 + i * 0.08;
        const k = eo((v - t0) / 0.5);
        w.s.style.transform = `translateY(${(1 - k) * 105}%)`;
        if (w.num) w.s.textContent = w.num.pre + Math.round(w.num.n * eo((v - t0) / 1.0)) + w.num.post;
      });
      if (sub) { const k = eo((v - 0.7 - (step ? step * 2.6 : 0)) / 0.5); sub.style.opacity = k; sub.style.transform = `translateY(${(1 - k) * 22}px)`; }
    },
  };
}

// ---------------------------------------------------------------- devices
// A real capture in a dark frame. The iPhone Duo is two halves around its hinge, so it can open.
function device(parent, shot, o = {}) {
  const kind = shot.split('-')[0], [sw, sh] = DATA.sizes[shot];
  const bw = o.w || BOX.w, bh = o.h || BOX.h;
  const k = Math.min(bw / sw, bh / sh), w = sw * k, h = sh * k;
  const cx = o.cx != null ? o.cx : BOX.cx, cy = o.cy != null ? o.cy : BOX.cy;
  const root = el('div', 'dev ' + kind, parent);
  Object.assign(root.style, { left: cx - w / 2 + 'px', top: cy - h / 2 + 'px', width: w + 'px', height: h + 'px' });
  const r = w * (kind === 'iphone' ? 0.085 : 0.062), bz = Math.max(7, w * 0.014);
  root.style.setProperty('--r', r + 'px'); root.style.setProperty('--bz', bz + 'px');
  const d = { root, kind, w, h, cx, cy, seed: hash(shot.length + shot.charCodeAt(shot.length - 1)) * 6 };
  const src = shot + '.png', alts = [];
  // A second screen can take the place of the first (setAlt(0..1)).
  d.setAlt = k => alts.forEach(im => { im.style.opacity = k; });
  if (kind === 'duo') {
    const mk = side => {
      const half = el('div', 'half ' + side, root);
      const face = el('div', 'face', half);
      const img = el('img', '', face); img.src = src; img.style.width = w + 'px'; img.style.height = h + 'px';
      if (side === 'right') img.style.marginLeft = -w / 2 + 'px';
      if (o.alt) { const im2 = el('img', 'alt', face); im2.src = o.alt + '.png'; im2.style.width = w + 'px'; im2.style.height = h + 'px'; if (side === 'right') im2.style.left = -w / 2 + 'px'; alts.push(im2); }
      el('div', 'backface', half);
      return half;
    };
    d.right = mk('right'); d.left = mk('left');
    d.hinge = el('div', 'hinge', root);
    d.fold = a => {
      d.left.style.transform = `rotateY(${a}deg)`;
      d.hinge.style.opacity = a > 60 ? 0 : 1;
      d.shadow.style.left = Math.min(50, a / 180 * 52) + '%';
    };
  } else {
    const face = el('div', 'face', root);
    d.img = el('img', '', face); d.img.src = src; d.face = face;
    if (o.alt) { const im2 = el('img', 'alt', face); im2.src = o.alt + '.png'; alts.push(im2); }
  }
  d.shadow = el('div', 'shadow', root);
  return d;
}
function devPose(d, u, dur, o = {}) {
  const dir = o.dir || 1, delay = o.delay || 0, v = u - delay;
  const kin = back((v - 0.05) / 0.85), ko = clamp((u - (dur - 0.14)) / 0.14);
  const fl = Math.sin((u + d.seed) * 1.0);
  const ry = (o.ry != null ? o.ry : -11) * dir - (1 - eo(v / 1.0)) * 30 * dir + fl * 2;
  const rx = (o.rx != null ? o.rx : 5) + Math.cos((u + d.seed) * 1.05) * 1.3;
  const tx = (1 - kin) * (L ? 560 : 0) * dir, ty = (1 - kin) * (L ? 40 : 700) + fl * 7;
  const s = lerp(0.86, 1, eo(v / 0.8)) * (1 + 0.03 * u / dur);
  d.root.style.transform = `translate3d(${tx}px,${ty}px,${o.z || 0}px) rotateY(${ry}deg) rotateX(${rx}deg) rotateZ(${(o.rz || 0)}deg) scale(${s})`;
  d.root.style.opacity = clamp(v / 0.12) * (1 - ko);
}
// A small label that pops next to the device. fx, fy: position from the centre of the stage box, in half-boxes.
function chip(parent, text, color, fx, fy, at) {
  const c = el('div', 'chip', parent);
  if (color) { const dot = el('i', '', c); dot.style.background = color; }
  el('span', '', c, text);
  c.style.left = BOX.cx + fx * BOX.w / 2 + 'px'; c.style.top = BOX.cy + fy * BOX.h / 2 + 'px';
  return { c, at, update(u, dur) {
    const k = back((u - at) / 0.5), ko = clamp((u - (dur - 0.14)) / 0.14);
    c.style.transform = `translate3d(-50%,-50%,150px) translateY(${Math.sin(u * 1.6 + at * 9) * 5}px) scale(${Math.max(0, k)})`;
    c.style.opacity = clamp((u - at) / 0.1) * (1 - ko);
  } };
}

// ---------------------------------------------------------------- scenes
const SC = {};
// Two devices in the same picture (iPhone, iPad and Duo all get their turn): where the main one and the one in
// front of it stand, for the wide film and for the tall one.
const LAY = L ? {
  ipadPhone: { main: { cx: 1280, cy: 520, w: 620, h: 800 }, side: { cx: 1685, cy: 630, w: 300, h: 600 } },
  duoPhone: { main: { cx: 1305, cy: 465, w: 790, h: 600 }, side: { cx: 1700, cy: 640, w: 270, h: 550 } },
  phoneIpad: { main: { cx: 1500, cy: 520, w: 600, h: 790 }, side: { cx: 1125, cy: 620, w: 300, h: 600 } },
  phoneFront: { main: { cx: 1300, cy: 520, w: 600, h: 820 }, side: { cx: 1690, cy: 650, w: 350, h: 500 } },
} : {
  ipadPhone: { main: { cx: 455, cy: 1160, w: 720, h: 920 }, side: { cx: 850, cy: 1395, w: 300, h: 600 } },
  duoPhone: { main: { cx: 540, cy: 1000, w: 940, h: 700 }, side: { cx: 800, cy: 1420, w: 300, h: 580 } },
  phoneIpad: { main: { cx: 455, cy: 1160, w: 720, h: 920 }, side: { cx: 850, cy: 1395, w: 300, h: 600 } },
};
// The usual scene: words on one side, a device on the other, a few labels around it.
function feature(name, cfg) {
  SC[name] = {
    build(root) {
      this.t = cfg.texts.map(tc => textBlock(root, tc));
      this.stage = el('div', 'persp', root);
      const alt = cfg.alt && DATA.sizes[cfg.alt[L ? 0 : 1]] ? { alt: cfg.alt[L ? 0 : 1] } : {};
      const lay = cfg.lay && cfg.lay[L ? 0 : 1] ? LAY[cfg.lay[L ? 0 : 1]] : null;
      if (cfg.shot) this.d = device(this.stage, L ? cfg.shot[0] : cfg.shot[1], Object.assign(alt, lay ? lay.main : {}, cfg.dev || {}));
      if (lay && cfg.side) this.d2 = device(this.stage, cfg.side[L ? 0 : 1], lay.side);
      this.chips = (cfg.chips || []).map(c => { const p = L ? c.slice(2, 4) : c.slice(4, 6); return chip(this.stage, c[0], c[1], p[0], p[1], c[6]); });
      if (cfg.build) cfg.build.call(this, root);
    },
    update(u, dur) {
      this.t.forEach(tb => tb.update(u, dur));
      if (this.d) { devPose(this.d, u, dur, cfg.pose || {}); this.d.setAlt(eio((u - dur / 2 + 0.1) / 0.3)); }
      if (this.d2) devPose(this.d2, u, dur, { ry: 8, rx: 4, delay: 0.25, z: 130 });
      this.chips.forEach(c => c.update(u, dur));
      if (cfg.update) cfg.update.call(this, u, dur);
    },
  };
}
const N = DATA.counts;
const LOCK = '<svg viewBox="0 0 24 24"><path d="M7 10V7a5 5 0 0 1 10 0v3h1.5A1.5 1.5 0 0 1 20 11.5v8A1.5 1.5 0 0 1 18.500 21h-13A1.5 1.5 0 0 1 4 19.500v-8A1.5 1.5 0 0 1 5.500 10Zm2 0h6V7a3 3 0 0 0-6 0Z" fill="#fff"/></svg>';

feature('hook', { texts: [{ center: true, lines: ['LEONIDA', 'IS *HUGE.*'], cy: L ? H * 0.48 : H * 0.46 }] });

feature('intro', {
  texts: [{ kicker: 'Guide for GTA VI: Leonida', lines: ["DON'T PLAY", 'IT *BLIND.*'], sub: 'Your companion for GTA VI.' }],
  shot: ['ipad-home', 'ipad-home'], side: ['iphone-home', 'iphone-home'], lay: ['ipadPhone', 'ipadPhone'], pose: { ry: -9 },
});

feature('map', {
  texts: [{ kicker: 'The map', lines: [`*${N.places - 10} PLACES.*`, 'YOUR OWN PINS.'] }],
  shot: ['duo-mappins', 'duo-mappins'], side: ['iphone-mappins', 'iphone-mappins'], lay: ['duoPhone', 'duoPhone'], pose: { ry: -8 },
  chips: [['Landmarks', COLORS.flamingo, -0.84, -0.86, -0.62, -0.92, 1.4], ['My pins', COLORS.sun, -0.66, 0.66, 0.5, -0.9, 2.0]],
});

// The rare vehicles: where each one is parked, then the players' votes.
feature('cars', {
  texts: [{ kicker: 'Rare vehicles', lines: [`*${Math.floor((N.rare || 400) / 100) * 100}+ RARE CARS.*`, 'ON THE MAP.'], sub: 'Every one pinned where it is parked.' }],
  shot: ['duo-cars', 'duo-cars'], side: ['iphone-cars', 'iphone-cars'], lay: ['duoPhone', 'duoPhone'], pose: { ry: -8 },
});

feature('votes', {
  texts: [{ kicker: 'By the players', lines: ['SEEN IT?', '*VOTE. ADD YOURS.*'], sub: 'Players confirm every spot.' }],
  // The iPhone in front: the card with the two vote buttons has to be readable.
  shot: ['iphone-car', 'iphone-car'], side: ['ipad-car', 'ipad-car'], lay: ['phoneFront', 'ipadPhone'], pose: { ry: -9 },
  chips: [["It's here", COLORS.palm, -0.84, -0.86, -0.6, -0.96, 1.25], ['Not here', COLORS.sunset, -0.86, 0.9, 0.5, -0.84, 1.875]],
});

feature('missions', {
  texts: [{ kicker: 'Walkthroughs', lines: [`ALL *${N.missions} MISSIONS.*`, 'STEP BY STEP.'] }],
  shot: ['ipad-mission', 'ipad-mission'], side: ['iphone-mission', 'iphone-mission'], lay: ['ipadPhone', 'ipadPhone'], pose: { ry: -9 },
});

feature('spoiler', {
  texts: [{ kicker: 'No spoilers', lines: ['*SPOILER-FREE*', 'BY DEFAULT.'], sub: 'Later chapters stay hidden.' }],
  shot: ['ipad-mission', 'ipad-mission'], side: ['iphone-mission', 'iphone-mission'], lay: ['ipadPhone', 'ipadPhone'], pose: { ry: -9 },
  build() {
    // The lower part of the screens blurs: what comes later in the story stays hidden.
    this.blurs = [this.d, this.d2].filter(Boolean).map(d => { const b = el('div', 'blur', d.face); el('img', '', b).src = d.img.src; return b; });
    this.lock = el('div', 'lock', this.d.face);
    this.lock.innerHTML = LOCK + '<span>Hidden until you get there</span>';
  },
  update(u) {
    const a = CUES.spoiler - AT('spoiler'), k = eio((u - a) / 0.6);
    this.blurs.forEach(b => { b.style.clipPath = `inset(${lerp(100, 44, k)}% 0 0 0)`; });
    const p = back((u - a - 0.35) / 0.45);
    this.lock.style.transform = `translate(-50%,-50%) scale(${Math.max(0, p)})`;
    this.lock.style.opacity = clamp((u - a - 0.35) / 0.1);
  },
});

feature('tracker', {
  texts: [{ kicker: '100% tracker', lines: ['YOUR ROAD', 'TO *100%.*'], still: true, sub: 'Every collectible. Every challenge.' }],
  shot: ['ipad-collectibles', 'duo-collectibles'], side: ['iphone-collectibles', null], lay: ['ipadPhone', null], pose: { ry: -9 },
  build() {
    // The ring fills up to 100% and lands on a beat.
    const card = el('div', 'ringcard', this.stage);
    const S = L ? 330 : 360;
    Object.assign(card.style, { width: S + 'px', height: S + 'px', left: BOX.cx + (L ? -BOX.w * 0.4 : BOX.w * 0.2) + 'px', top: BOX.cy + (L ? BOX.h * 0.33 : BOX.h * 0.38) + 'px' });
    const C = 2 * Math.PI * 42;
    card.innerHTML = `<svg viewBox="0 0 100 100"><defs><linearGradient id="rg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFC94A"/><stop offset=".5" stop-color="#FF8A3D"/><stop offset="1" stop-color="#FF4F8B"/></linearGradient></defs>
      <circle cx="50" cy="50" r="42" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="9"/>
      <circle id="ringArc" cx="50" cy="50" r="42" fill="none" stroke="url(#rg)" stroke-width="9" stroke-linecap="round" stroke-dasharray="${C}" transform="rotate(-90 50 50)"/></svg>
      <div class="pct"><b id="ringPct">45%</b><span>of Leonida done</span></div>`;
    this.card = card; this.C = C;
    this.burst = el('div', 'burst', card);
    for (let i = 0; i < 18; i++) { const s = el('i', '', this.burst); s.style.background = [COLORS.sun, COLORS.flamingo, COLORS.sunset, COLORS.palm, COLORS.sky][i % 5]; }
  },
  update(u, dur) {
    const a = CUES.ringStart - AT('tracker'), b = CUES.ringFull - AT('tracker');
    const p = lerp(0.45, 1, eio((u - a) / (b - a)));
    this.card.querySelector('#ringArc').setAttribute('stroke-dashoffset', this.C * (1 - p));
    this.card.querySelector('#ringPct').textContent = Math.round(p * 100) + '%';
    const kin = back((u - 0.5) / 0.6), hit = clamp((u - b) / 0.5), ko = clamp((u - (dur - 0.14)) / 0.14);
    const pulse = u >= b ? 1 + 0.16 * Math.exp(-hit * 5) * Math.cos(hit * 9) : 1;
    this.card.style.transform = `translate3d(-50%,-50%,160px) rotate(${L ? -5 : 4}deg) scale(${Math.max(0, kin) * pulse})`;
    this.card.style.opacity = clamp((u - 0.5) / 0.1) * (1 - ko);
    this.card.classList.toggle('full', u >= b);
    [...this.burst.children].forEach((s, i) => {
      const ang = i / 18 * 6.283 + hash(i) * 0.3, dist = eo(hit) * (150 + hash(i, 2) * 150);
      s.style.transform = `translate(${Math.cos(ang) * dist}px,${Math.sin(ang) * dist}px) scale(${u >= b ? 1 - hit : 0})`;
    });
  },
});

feature('eggs', {
  texts: [{ kicker: 'Secrets', lines: [`*${N.eggs} EASTER EGGS.*`, 'ON THE MAP.'] }],
  shot: ['duo-eggs', 'ipad-eggs'], side: ['iphone-eggs', 'iphone-eggs'], lay: ['duoPhone', 'ipadPhone'], pose: { ry: -8 },
  chips: [['The jet ski dog', COLORS.sky, -0.84, -0.86, -0.6, -0.96, 1.3], ['The Skunk Ape', COLORS.palm, -0.5, 0.7, 0.5, -0.84, 1.9]],
});

// A cheat code typed button after button, in time with the music.
SC.cheats = {
  build(root) {
    this.t = textBlock(root, { kicker: 'Cheat codes', lines: [`*${N.cheats} CHEATS.*`, 'PS5 & XBOX.'] });
    this.stage = el('div', 'persp', root);
    const wrap = el('div', 'cheatwrap', this.stage);
    const cw = L ? 860 : 940;
    Object.assign(wrap.style, { left: BOX.cx - cw / 2 + 'px', top: BOX.cy - (L ? 190 : 250) + 'px', width: cw + 'px' });
    const c = el('div', 'cheat main', wrap);
    const top = el('div', 'ctop', c);
    const tt = el('div', '', top); el('b', '', tt, DATA.cheats[0][0]); el('span', '', tt, 'Money');
    const seg = el('div', 'seg', top); el('i', 'on', seg, 'PlayStation'); el('i', '', seg, 'Xbox');
    const keys = el('div', 'keys', c);
    this.keys = DATA.cheats[0][1].split(/[ ·]+/).filter(Boolean).map(kx => el('div', 'key' + (kx.length > 1 ? ' wide' : ''), keys, kx));
    this.card = c; this.wrap = wrap;
  },
  update(u, dur) {
    this.t.update(u, dur);
    const a = AT('cheats'), kin = back((u - 0.05) / 0.7), ko = clamp((u - (dur - 0.14)) / 0.14);
    this.wrap.style.transform = `translate3d(${(1 - kin) * (L ? 420 : 0)}px,${(1 - kin) * (L ? 0 : 520)}px,0) rotateY(${L ? -9 + Math.sin(u * 1.2) * 2 : 0}deg) rotateX(${4 + Math.cos(u) * 1.2}deg)`;
    this.wrap.style.opacity = clamp(u / 0.12) * (1 - ko);
    this.keys.forEach((kx, i) => {
      const v = u - (CUES.cheatKeys[i] - a), k = back(v / 0.2);
      kx.style.transform = `scale(${Math.max(0, k)})`;
      kx.style.opacity = v > 0 ? 1 : 0;
      kx.classList.toggle('hot', v > 0 && v < 0.22);
    });
    const done = u - (CUES.cheatKeys[CUES.cheatKeys.length - 1] - a) - 0.2;
    this.card.classList.toggle('done', done > 0);
    this.card.style.transform = `scale(${1 + (done > 0 ? 0.05 * Math.exp(-done * 9) : 0)})`;
  },
};

feature('community', {
  texts: [{ kicker: 'Community', lines: ['STUCK?', '*ASK THE PLAYERS.*'] }],
  shot: ['duo-thread', 'iphone-thread'], side: ['iphone-thread', null], lay: ['duoPhone', null], pose: { ry: -8 },
});

feature('widgets', {
  texts: [{ kicker: 'Widgets · iCloud', pro: true, lines: ['YOUR PROGRESS,', '*EVERYWHERE.*'], sub: 'Widgets and iCloud sync.' }],
  shot: ['ipad-widgets', 'iphone-widgets'], side: ['iphone-widgets', null], lay: ['phoneIpad', null], pose: L ? { ry: -9 } : { ry: -14 },
});

// Three devices side by side; the iPhone Duo opens.
SC.devices = {
  build(root) {
    this.t = textBlock(root, { kicker: 'One app, three screens', lines: L ? ['iPHONE. *iPHONE DUO.* iPAD.'] : ['iPHONE. iPAD.', '*iPHONE DUO.*'], top: L ? 90 : 150, width: L ? 1500 : 900, size: L ? 124 : 132 });
    this.stage = el('div', 'persp', root);
    this.stage.style.perspectiveOrigin = L ? `${W / 2}px 650px` : `${W / 2}px 1200px`;
    const P = L
      ? { ipad: { cx: 400, cy: 650, w: 440, h: 540 }, duo: { cx: 970, cy: 650, w: 680, h: 540 }, iphone: { cx: 1530, cy: 650, w: 300, h: 540 } }
      : { duo: { cx: 540, cy: 900, w: 760, h: 600 }, ipad: { cx: 340, cy: 1480, w: 480, h: 440 }, iphone: { cx: 790, cy: 1480, w: 300, h: 440 } };
    this.ipad = device(this.stage, 'ipad-home', P.ipad);
    this.duo = device(this.stage, 'duo-mappins', P.duo);
    this.iphone = device(this.stage, 'iphone-mission', P.iphone);
    this.labels = [[this.ipad, 'iPad'], [this.duo, 'iPhone Duo'], [this.iphone, 'iPhone']].map(([d, name]) => {
      const lb = el('div', 'devlabel', this.stage, name);
      const low = d === this.duo && !L ? d : this.ipad;
      lb.style.left = d.cx + 'px'; lb.style.top = Math.max(low.cy + low.h / 2, d.cy + d.h / 2) + (L ? 40 : 32) + 'px';
      return lb;
    });
  },
  update(u, dur) {
    this.t.update(u, dur);
    const ko = clamp((u - (dur - 0.14)) / 0.14);
    const open = CUES.unfold - AT('devices');
    this.duo.fold(lerp(178, 0, eio((u - open) / 1.1)));
    const kd = back((u - 0.02) / 0.6);
    // Closed, the Duo is one half wide: it sits in the middle, then slides as it opens.
    const shift = lerp(-this.duo.w / 4, 0, eio((u - open) / 1.1));
    this.duo.root.style.transform = `translate3d(${shift}px,${(1 - kd) * 500 + Math.sin(u * 1.0) * 5}px,60px) rotateX(${7}deg) rotateY(${Math.sin(u * 0.8) * 3}deg)`;
    this.duo.root.style.opacity = clamp(u / 0.12) * (1 - ko);
    [[this.ipad, 1.9, -1, 6], [this.iphone, 2.3, 1, -6]].forEach(([d, at, dir, ry]) => {
      const k = back((u - at) / 0.7);
      d.root.style.transform = `translate3d(${(1 - k) * (L ? 300 : 500) * dir}px,${Math.sin(u * 1.0 + at * 3) * 5}px,0) rotateY(${ry + Math.sin(u * 0.8 + at) * 2}deg) rotateX(5deg) scale(${lerp(0.8, 1, eo((u - at) / 0.6))})`;
      d.root.style.opacity = clamp((u - at) / 0.12) * (1 - ko);
    });
    this.labels.forEach((lb, i) => { const k = eo((u - [2.2, 1.8, 2.6][i]) / 0.4); lb.style.opacity = k * (1 - ko); lb.style.transform = `translate(-50%,${(1 - k) * 14}px)`; });
  },
};

// What it does not do: no account, no ads, no tracking. One line per beat, then two promises.
SC.trust = {
  build(root) {
    this.t = textBlock(root, { kicker: 'Private by design', lines: ['NO ACCOUNT.', 'NO ADS.', '*NO TRACKING.*'], lineStep: CUES.beat, size: L ? 150 : 132 });
    this.stage = el('div', 'persp', root);
    const grid = el('div', 'trust', this.stage);
    const gw = L ? 760 : 900, gh = L ? 520 : 520;
    Object.assign(grid.style, { left: BOX.cx - gw / 2 + 'px', top: (L ? BOX.cy + 20 : BOX.cy + 60) - gh / 2 + 'px', width: gw + 'px', height: gh + 'px', gridTemplateColumns: '1fr' });
    this.cards = [['WORKS OFFLINE', 'The whole guide, no network needed'], ['EVERY GUIDE IS FREE', 'Pro is optional']].map(([a, b], i) => {
      const c = el('div', 'tcard', grid);
      c.innerHTML = `<svg viewBox="0 0 48 48"><defs><linearGradient id="tg${i}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFC94A"/><stop offset=".5" stop-color="#FF8A3D"/><stop offset="1" stop-color="#FF4F8B"/></linearGradient></defs><circle cx="24" cy="24" r="24" fill="url(#tg${i})"/><path d="M13.500 24.500l7 7 14-15" fill="none" stroke="#fff" stroke-width="4.500" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
      el('b', '', c, a); el('span', '', c, b);
      return c;
    });
  },
  update(u, dur) {
    this.t.update(u, dur);
    const ko = clamp((u - (dur - 0.14)) / 0.14);
    this.cards.forEach((c, i) => {
      const v = u - (CUES.trustCards[i] - AT('trust')), k = back(v / 0.5);
      c.style.transform = `translateY(${(1 - eo(v / 0.5)) * 60}px) scale(${Math.max(0, k)})`;
      c.style.opacity = clamp(v / 0.1) * (1 - ko);
    });
  },
};

// The end: the icon, the name, where to get it.
SC.end = {
  build(root) {
    const wrap = el('div', 'endwrap', root);
    this.icon = el('img', 'endicon', wrap); this.icon.src = 'icon.png';
    this.halo = el('div', 'halo', wrap);
    this.name = el('div', 'endname', wrap);
    this.name.innerHTML = '<div><span>GUIDE FOR GTA VI:</span></div><div><span class="acc">LEONIDA</span></div>';
    this.tag = el('div', 'endtag', wrap, 'Map · rare cars · 100% tracker · all cheats · spoiler-free');
    this.cta = el('div', 'cta', wrap);
    this.cta.innerHTML = CTA === 'soon' ? '<small>Coming soon to the</small><b>App Store</b>' : '<small>Download on the</small><b>App Store</b>';
    this.devs = el('div', 'enddevs', wrap, 'iPhone  ·  iPhone Duo  ·  iPad');
    // The App Store link, once the app is live (python3 build.py <work> wide now --link <url>).
    this.link = LINK ? el('div', 'endlink', wrap, LINK.replace(/^https?:\/\//, '')) : null;
    this.legal = el('div', 'legal', root);
    this.legal.innerHTML = 'Unofficial fan guide. Not affiliated with, endorsed or approved by Rockstar Games or Take-Two Interactive. Game names are trademarks of their owners.<br>Map: GTA VI Community Map by Yanis &amp; the mapping community, via GTADB.org, CC BY 4.0. Rare vehicles: Open GTA 6 Map, CC BY 4.0. Some features need Vicefold Pro.';
    this.wrap = wrap;
  },
  update(u, dur) {
    const ki = back((u - 0.05) / 0.7);
    this.icon.style.transform = `scale(${Math.max(0, ki) * (1 + 0.012 * Math.sin(u * 2.4))}) rotate(${(1 - eo(u / 0.7)) * -14}deg)`;
    this.icon.style.opacity = clamp(u / 0.1);
    this.halo.style.opacity = clamp(u / 0.4) * (0.75 + 0.25 * Math.sin(u * 2.4));
    this.halo.style.transform = `translate(-50%,-50%) scale(${lerp(0.5, 1, eo(u / 0.8))})`;
    [...this.name.querySelectorAll('span')].forEach((s, i) => { s.style.transform = `translateY(${(1 - eo((u - 0.6 - i * 0.2) / 0.5)) * 105}%)`; });
    const kt = eo((u - 1.3) / 0.5); this.tag.style.opacity = kt; this.tag.style.transform = `translateY(${(1 - kt) * 18}px)`;
    const v = u - (CUES.endCta - AT('end')), kc = back(v / 0.5);
    this.cta.style.transform = `scale(${Math.max(0, kc) * (1 + 0.02 * Math.sin(Math.max(0, v) * 4))})`; this.cta.style.opacity = clamp(v / 0.1);
    const kd = eo((v - 0.4) / 0.5); this.devs.style.opacity = kd;
    if (this.link) { const kl = back((v - 0.7) / 0.5); this.link.style.opacity = clamp((v - 0.7) / 0.1); this.link.style.transform = `scale(${Math.max(0, kl)})`; }
    this.legal.style.opacity = eo((u - 1.6) / 0.5) * 0.62;
    const fade = clamp((u - (dur - 0.6)) / 0.6);
    document.getElementById('fade').style.opacity = fade;
  },
};

// ---------------------------------------------------------------- putting it together
const scenes = CUES.scenes.map(([name, a, b]) => {
  const root = el('div', 'scene s-' + name, stage);
  return { name, a, b, root, sc: SC[name] };
});
const swipe = el('div', 'swipe', stage);
const foot = el('div', 'foot', stage);
foot.innerHTML = '<span><img src="icon.png">Guide for GTA VI: Leonida</span><span>Unofficial fan guide · Map © GTADB.org · Yanis · CC BY 4.0</span>';
el('div', '', stage).id = 'fade';

async function ready() {
  await document.fonts.load('100px Anton'); await document.fonts.load('800 30px Inter'); await document.fonts.ready;
  await MAP.decode();
  for (const s of scenes) { s.sc.build(s.root); s.root.style.display = 'none'; }
  await Promise.all([...document.images].map(i => i.decode().catch(() => 0)));
  return true;
}
function render(t) {
  drawBg(t);
  for (const s of scenes) {
    const on = t >= s.a && t < s.b;
    s.root.style.display = on ? 'block' : 'none';
    if (on) s.sc.update(t - s.a, s.b - s.a);
  }
  // A band of sunset crosses the picture at each change of scene.
  let band = 0, any = false;
  for (const s of scenes) { if (s.a === 0) continue; const k = (t - (s.a - 0.14)) / 0.42; if (k > 0 && k < 1) { band = k; any = true; } }
  swipe.style.display = any ? 'block' : 'none';
  if (any) swipe.style.transform = `translateX(${lerp(-110, 190, band)}%) skewX(-24deg)`;
  const endA = CUES.scenes[CUES.scenes.length - 1][1];
  foot.style.opacity = clamp((t - (T1 + 0.2)) / 0.5) * (1 - clamp((t - (endA - 0.2)) / 0.2));
}
