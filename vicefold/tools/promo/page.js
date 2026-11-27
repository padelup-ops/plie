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
const PINS = DATA.places.map((p, i) => ({ x: p[0], y: p[1], kind: p[2], at: 0.35 + 3.0 * hash(i, 3) }));
// The camera over the map: [time, centre x, centre y (0-1 on the map), screen pixels per map pixel].
const CAM = L
  ? [[0, 0.74, 0.5, 1.45], [2, 0.6, 0.5, 0.62], [4, 0.5, 0.49, 0.5], [8, 0.42, 0.47, 0.56], [42, 0.5, 0.42, 0.7]]
  : [[0, 0.745, 0.5, 1.5], [2, 0.62, 0.52, 0.66], [4, 0.5, 0.5, 0.47], [8, 0.5, 0.42, 0.52], [42, 0.5, 0.4, 0.66]];
const DIM = [[0, 0.2], [1.85, 0.24], [2.25, 0.66], [4, 0.6], [4.4, 0.46], [7.8, 0.5], [8.2, 0.9], [42, 0.9]];
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
  if (t < 9) {
    const fade = 1 - clamp((t - 8) / 0.6);
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
  const side = clamp((t - 3.7) / 0.5) * (1 - clamp((t - 8) / 0.4)) * 0.78 + (t < 4 ? clamp((t - 2) / 0.3) * 0.2 : 0);
  if (side > 0.01) {
    const g = L ? bg.createLinearGradient(0, 0, W * 0.62, 0) : bg.createLinearGradient(0, 0, 0, H * 0.5);
    g.addColorStop(0, `rgba(9,20,34,${side})`); g.addColorStop(0.55, `rgba(9,20,34,${side * 0.85})`); g.addColorStop(1, 'rgba(9,20,34,0)');
    bg.fillStyle = g; bg.fillRect(0, 0, W, H);
  }
  if (t < 2.2) {
    const a = 0.62 * (1 - clamp((t - 1.9) / 0.3));
    const g = bg.createRadialGradient(W / 2, H * 0.48, 0, W / 2, H * 0.48, Math.min(W, H) * 0.75);
    g.addColorStop(0, `rgba(9,20,34,${a})`); g.addColorStop(1, 'rgba(9,20,34,0)');
    bg.fillStyle = g; bg.fillRect(0, 0, W, H);
  }
  // Sunset glows, slowly moving.
  const glow = clamp((t - 1.9) / 0.6) * 0.9 + 0.1;
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
      if (kick) { const k = eo(v / 0.3); kick.style.opacity = k; kick.style.transform = `translateY(${(1 - k) * 18}px)`; }
      words.forEach((w, i) => {
        const t0 = step ? w.li * step : 0.05 + i * 0.05;
        const k = eo((v - t0) / 0.36);
        w.s.style.transform = `translateY(${(1 - k) * 105}%)`;
        if (w.num) w.s.textContent = w.num.pre + Math.round(w.num.n * eo((v - t0) / 0.75)) + w.num.post;
      });
      if (sub) { const k = eo((v - 0.3 - (step ? step * 2.2 : 0)) / 0.4); sub.style.opacity = k; sub.style.transform = `translateY(${(1 - k) * 22}px)`; }
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
  const kin = back((v - 0.04) / 0.62), ko = clamp((u - (dur - 0.14)) / 0.14);
  const fl = Math.sin((u + d.seed) * 1.25);
  const ry = (o.ry != null ? o.ry : -11) * dir - (1 - eo(v / 0.75)) * 34 * dir + fl * 2.2;
  const rx = (o.rx != null ? o.rx : 5) + Math.cos((u + d.seed) * 1.05) * 1.3;
  const tx = (1 - kin) * (L ? 560 : 0) * dir, ty = (1 - kin) * (L ? 40 : 700) + fl * 7;
  const s = lerp(0.84, 1, eo(v / 0.6)) * (1 + 0.035 * u / dur);
  d.root.style.transform = `translate3d(${tx}px,${ty}px,0) rotateY(${ry}deg) rotateX(${rx}deg) rotateZ(${(o.rz || 0)}deg) scale(${s})`;
  d.root.style.opacity = clamp(v / 0.12) * (1 - ko);
}
// A small label that pops next to the device. fx, fy: position from the centre of the stage box, in half-boxes.
function chip(parent, text, color, fx, fy, at) {
  const c = el('div', 'chip', parent);
  if (color) { const dot = el('i', '', c); dot.style.background = color; }
  el('span', '', c, text);
  c.style.left = BOX.cx + fx * BOX.w / 2 + 'px'; c.style.top = BOX.cy + fy * BOX.h / 2 + 'px';
  return { c, at, update(u, dur) {
    const k = back((u - at) / 0.4), ko = clamp((u - (dur - 0.14)) / 0.14);
    c.style.transform = `translate3d(-50%,-50%,150px) translateY(${Math.sin(u * 1.6 + at * 9) * 5}px) scale(${Math.max(0, k)})`;
    c.style.opacity = clamp((u - at) / 0.1) * (1 - ko);
  } };
}

// ---------------------------------------------------------------- scenes
const SC = {};
// The usual scene: words on one side, a device on the other, a few labels around it.
function feature(name, cfg) {
  SC[name] = {
    build(root) {
      this.t = cfg.texts.map(tc => textBlock(root, tc));
      this.stage = el('div', 'persp', root);
      const alt = cfg.alt && DATA.sizes[cfg.alt[L ? 0 : 1]] ? { alt: cfg.alt[L ? 0 : 1] } : {};
      if (cfg.shot) this.d = device(this.stage, L ? cfg.shot[0] : cfg.shot[1], Object.assign(alt, cfg.dev || {}));
      this.chips = (cfg.chips || []).map(c => { const p = L ? c.slice(2, 4) : c.slice(4, 6); return chip(this.stage, c[0], c[1], p[0], p[1], c[6]); });
      if (cfg.build) cfg.build.call(this, root);
    },
    update(u, dur) {
      this.t.forEach(tb => tb.update(u, dur));
      if (this.d) { devPose(this.d, u, dur, cfg.pose || {}); this.d.setAlt(eio((u - dur / 2 + 0.1) / 0.3)); }
      this.chips.forEach(c => c.update(u, dur));
      if (cfg.update) cfg.update.call(this, u, dur);
    },
  };
}
const N = DATA.counts;

feature('hook', { texts: [{ center: true, lines: ['LEONIDA', 'IS *HUGE.*'], cy: L ? H * 0.48 : H * 0.46 }] });

feature('intro', {
  texts: [{ kicker: 'Guide for GTA VI: Leonida', lines: ["DON'T PLAY", 'IT *BLIND.*'], sub: 'The fan-made companion.<br>Missions, map, 100%, secrets, cheats.' }],
  shot: ['ipad-home', 'iphone-home'],
});

feature('map', {
  texts: [{ kicker: 'The map', lines: [`*${N.places - 10} PLACES.*`, 'YOUR OWN PINS.'], sub: 'Layers, search, visited places.<br>Name, note, icon and colour for every pin.' }],
  shot: ['duo-mappins', 'iphone-mappins'],
  chips: [['Landmarks', COLORS.flamingo, -0.8, -0.74, -0.56, -0.93, 0.7], ['Hotels', '#D6336C', 0.84, -0.8, 0.6, -0.86, 0.88], ['Food & drink', COLORS.sunset, 0.8, 0.02, 0.62, 0.16, 1.06],
    ['Shops', COLORS.sky, -0.86, 0.3, -0.64, 0.36, 1.24], ['Transport', '#5B6CFF', 0.7, 0.76, 0.56, 0.9, 1.42], ['My pins', COLORS.sun, -0.62, 0.8, -0.56, 0.88, 1.6]],
});

feature('missions', {
  texts: [
    { kicker: 'Walkthroughs', lines: [`ALL *${N.missions} MISSIONS.*`, 'STEP BY STEP.'], sub: 'Who gives it, where to go, objectives, tips.<br>Tick them off as you play.', until: 2 },
    { kicker: 'No spoilers', lines: ['*SPOILER-FREE*', 'BY DEFAULT.'], sub: 'Later chapters stay hidden<br>until you get there.', at: 2 },
  ],
  shot: ['ipad-mission', 'iphone-mission'],
  build() {
    // The lower part of the screen blurs: what comes later in the story stays hidden.
    const blur = el('div', 'blur', this.d.face);
    const img = el('img', '', blur); img.src = this.d.img.src;
    this.blur = blur;
    this.lock = el('div', 'lock', this.d.face);
    this.lock.innerHTML = '<svg viewBox="0 0 24 24"><path d="M7 10V7a5 5 0 0 1 10 0v3h1.5A1.5 1.5 0 0 1 20 11.5v8A1.5 1.5 0 0 1 18.500 21h-13A1.5 1.5 0 0 1 4 19.500v-8A1.5 1.5 0 0 1 5.500 10Zm2 0h6V7a3 3 0 0 0-6 0Z" fill="#fff"/></svg><span>Hidden until you get there</span>';
  },
  update(u) {
    const k = eio((u - 2.0) / 0.5);
    this.blur.style.clipPath = `inset(${lerp(100, 44, k)}% 0 0 0)`;
    const p = back((u - 2.3) / 0.4);
    this.lock.style.transform = `translate(-50%,-50%) scale(${Math.max(0, p)})`;
    this.lock.style.opacity = clamp((u - 2.3) / 0.1);
  },
});

feature('tracker', {
  texts: [{ kicker: '100% tracker', lines: ['YOUR ROAD', 'TO *100%.*'], still: true,
    sub: `${DATA.collectibles.length} collectible categories with counters.<br>Challenges, trophy roadmap, route to 100%.` }],
  shot: ['duo-collectibles', 'duo-collectibles'],
  build() {
    // The ring fills up to 100% and lands on a beat.
    const card = el('div', 'ringcard', this.stage);
    const S = L ? 330 : 360;
    Object.assign(card.style, { width: S + 'px', height: S + 'px', left: BOX.cx + (L ? -BOX.w * 0.43 : BOX.w * 0.2) + 'px', top: BOX.cy + (L ? BOX.h * 0.31 : BOX.h * 0.38) + 'px' });
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
    const a = CUES.ringStart - 12, b = CUES.ringFull - 12;
    const p = lerp(0.45, 1, eio((u - a) / (b - a)));
    this.card.querySelector('#ringArc').setAttribute('stroke-dashoffset', this.C * (1 - p));
    this.card.querySelector('#ringPct').textContent = Math.round(p * 100) + '%';
    const kin = back((u - 0.35) / 0.5), hit = clamp((u - b) / 0.5), ko = clamp((u - (dur - 0.14)) / 0.14);
    const pulse = u >= b ? 1 + 0.16 * Math.exp(-hit * 5) * Math.cos(hit * 9) : 1;
    this.card.style.transform = `translate3d(-50%,-50%,160px) rotate(${L ? -5 : 4}deg) scale(${Math.max(0, kin) * pulse})`;
    this.card.style.opacity = clamp((u - 0.35) / 0.1) * (1 - ko);
    this.card.classList.toggle('full', u >= b);
    [...this.burst.children].forEach((s, i) => {
      const ang = i / 18 * 6.283 + hash(i) * 0.3, dist = eo(hit) * (150 + hash(i, 2) * 150);
      s.style.transform = `translate(${Math.cos(ang) * dist}px,${Math.sin(ang) * dist}px) scale(${u >= b ? 1 - hit : 0})`;
    });
  },
});

feature('eggs', {
  texts: [{ kicker: 'Secrets', lines: [`*${N.eggs} EASTER EGGS.*`, 'ON THE MAP.'], sub: 'How to find each one stays hidden<br>until you ask.' }],
  shot: ['duo-eggs', 'iphone-eggs'], pose: { ry: -9 },
  chips: [['The jet ski dog', COLORS.sky, -0.8, -0.72, -0.56, -0.9, 0.5], ['The Skunk Ape', COLORS.palm, 0.78, -0.4, 0.6, -0.5, 0.68], ['Lights in the sky', COLORS.violet, -0.82, 0.5, -0.58, 0.5, 0.86], ['A giant crab', COLORS.sunset, 0.72, 0.74, 0.58, 0.9, 1.04]],
});

// A cheat code typed button after button, in time with the music.
SC.cheats = {
  build(root) {
    this.t = textBlock(root, { kicker: 'Cheat codes', lines: [`*${N.cheats} CHEATS.*`, 'PS5 & XBOX.'], sub: 'By category, with how to unlock each one.' });
    this.stage = el('div', 'persp', root);
    const wrap = el('div', 'cheatwrap', this.stage);
    const cw = L ? 860 : 940;
    Object.assign(wrap.style, { left: BOX.cx - cw / 2 + 'px', top: BOX.cy - (L ? 250 : 330) + 'px', width: cw + 'px' });
    const mk = (name, effect, cls) => {
      const c = el('div', 'cheat ' + cls, wrap);
      const top = el('div', 'ctop', c);
      const tt = el('div', '', top); el('b', '', tt, name); el('span', '', tt, effect);
      const seg = el('div', 'seg', top); el('i', 'on', seg, 'PlayStation'); el('i', '', seg, 'Xbox');
      return c;
    };
    this.card = mk(DATA.cheats[0][0], 'Money', 'main');
    const keys = el('div', 'keys', this.card);
    this.keys = DATA.cheats[0][1].split(/[ ·]+/).filter(Boolean).map(kx => el('div', 'key' + (kx.length > 1 ? ' wide' : ''), keys, kx));
    const more = el('div', 'more', wrap);
    this.more = [4, 5, 3, 1].map(i => el('span', '', more, DATA.cheats[i][0]));
    this.wrap = wrap;
  },
  update(u, dur) {
    this.t.update(u, dur);
    const kin = back((u - 0.05) / 0.5), ko = clamp((u - (dur - 0.14)) / 0.14);
    this.more.forEach((m, i) => { const k = back((u - 0.5 - i * 0.25) / 0.35); m.style.transform = `scale(${Math.max(0, k)})`; });
    this.wrap.style.transform = `translate3d(${(1 - kin) * (L ? 420 : 0)}px,${(1 - kin) * (L ? 0 : 520)}px,0) rotateY(${L ? -9 + Math.sin(u * 1.4) * 2 : 0}deg) rotateX(${4 + Math.cos(u) * 1.2}deg)`;
    this.wrap.style.opacity = clamp(u / 0.12) * (1 - ko);
    this.keys.forEach((kx, i) => {
      const v = u - (CUES.cheatKeys[i] - 18);
      const k = back(v / 0.16);
      kx.style.transform = `scale(${Math.max(0, k)})`;
      kx.style.opacity = v > 0 ? 1 : 0;
      kx.classList.toggle('hot', v > 0 && v < 0.14);
    });
    const done = u - (CUES.cheatKeys[9] - 18) - 0.12;
    this.card.classList.toggle('done', done > 0);
    this.card.style.transform = `scale(${1 + (done > 0 ? 0.05 * Math.exp(-done * 9) : 0)})`;
  },
};

// The radio: an equaliser that moves with the beat, and the stations going by.
SC.radio = {
  build(root) {
    this.t = textBlock(root, { kicker: 'The radio', lines: [`*${N.stations} STATIONS.*`, 'EVERY TRACK.'], sub: '30-second previews,<br>and a link to Apple Music.' });
    this.stage = el('div', 'persp', root);
    const wrap = el('div', 'radio', this.stage);
    const rw = L ? 860 : 940, rh = L ? 620 : 700;
    Object.assign(wrap.style, { left: BOX.cx - rw / 2 + 'px', top: BOX.cy - rh / 2 + 'px', width: rw + 'px', height: rh + 'px' });
    const eq = el('div', 'eq', wrap);
    this.bars = Array.from({ length: 26 }, () => el('i', '', eq));
    this.rows = [0, 1, 2].map(r => {
      const row = el('div', 'stations', wrap);
      const names = DATA.stations.filter((_, i) => i % 3 === r);
      [...names, ...names, ...names].forEach(n => el('span', '', row, n));
      return row;
    });
    this.wrap = wrap;
  },
  update(u, dur) {
    this.t.update(u, dur);
    const kin = back((u - 0.05) / 0.5), ko = clamp((u - (dur - 0.14)) / 0.14);
    this.wrap.style.transform = `translate3d(${(1 - kin) * (L ? 420 : 0)}px,${(1 - kin) * (L ? 0 : 520)}px,0) rotateY(${L ? -8 : 0}deg) rotateX(4deg)`;
    this.wrap.style.opacity = clamp(u / 0.12) * (1 - ko);
    const beat = Math.exp(-((u * 2) % 1) * 3.2);
    this.bars.forEach((b, i) => {
      const n = 0.5 + 0.5 * Math.sin(u * (5 + hash(i) * 7) + i * 1.7), shape = 0.45 + 0.55 * Math.sin((i / 25) * Math.PI);
      b.style.transform = `scaleY(${clamp(0.12 + (0.3 + 0.7 * beat) * shape * (0.35 + 0.65 * n), 0.08, 1) * eo(u / 0.4)})`;
    });
    this.rows.forEach((row, r) => { row.style.transform = `translateX(${(r % 2 ? -1 : 1) * (u * 90 + r * 60) - (r % 2 ? 0 : 520)}px)`; });
  },
};

feature('cast', {
  texts: [{ kicker: 'Characters · Vehicles', lines: ["*WHO'S WHO.*", `${N.vehicles} VEHICLES.`], sub: 'Your notes on every character.<br>Every vehicle, by class.' }],
  shot: ['duo-characters', 'iphone-characters'], alt: ['duo-vehicles', 'iphone-vehicles'], pose: { ry: -9 },
  chips: [['42 boats', COLORS.sky, -0.84, -0.72, -0.58, -0.9, 0.5], ['33 sports cars', COLORS.flamingo, 0.78, -0.76, 0.6, -0.56, 0.66], ['21 motorcycles', COLORS.sunset, -0.82, 0.52, -0.6, 0.56, 0.82], ['13 helicopters', COLORS.palm, 0.74, 0.76, 0.58, 0.9, 0.98]],
});

feature('community', {
  texts: [{ kicker: 'Community', lines: ['STUCK?', '*ASK THE PLAYERS.*'], sub: 'Questions and answers on every mission.<br>See how far your friends are.' }],
  shot: ['duo-thread', 'iphone-thread'], pose: { ry: -9 },
  chips: [['Helpful answers', COLORS.palm, 0.74, -0.76, 0.58, -0.66, 0.55], ['Game Center friends', COLORS.sky, -0.74, 0.74, -0.5, 0.9, 0.8]],
});

feature('widgets', {
  texts: [{ kicker: 'Widgets · iCloud', pro: true, lines: ['YOUR PROGRESS,', '*EVERYWHERE.*'], sub: 'Home and Lock Screen widgets, iCloud sync,<br>your PlayStation play time.' }],
  shot: ['iphone-widgets', 'iphone-widgets'], pose: { ry: -14 },
  chips: [['Home Screen', COLORS.flamingo, -0.6, -0.62, -0.62, -0.86, 0.5], ['Lock Screen', COLORS.violet, 0.6, -0.3, 0.62, -0.46, 0.66], ['iCloud sync', COLORS.sky, -0.62, 0.3, -0.62, 0.44, 0.82], ['PlayStation play time', COLORS.sun, 0.56, 0.72, 0.42, 0.9, 0.98]],
});

// Three devices side by side; the iPhone Duo opens.
SC.devices = {
  build(root) {
    this.t = textBlock(root, { kicker: 'One app, three screens', lines: L ? ['iPHONE. *iPHONE DUO.* iPAD.'] : ['iPHONE. iPAD.', '*iPHONE DUO.*'], top: L ? 70 : 130, width: L ? 1500 : 900, size: L ? 124 : 132,
      sub: L ? 'Open the Duo: the list on one side of the fold, the map on the other.' : 'Open the Duo: the list on one side of the fold,<br>the map on the other.' });
    this.stage = el('div', 'persp', root);
    this.stage.style.perspectiveOrigin = L ? `${W / 2}px 665px` : `${W / 2}px 1200px`;
    const P = L
      ? { ipad: { cx: 400, cy: 665, w: 430, h: 510 }, duo: { cx: 970, cy: 665, w: 660, h: 510 }, iphone: { cx: 1530, cy: 665, w: 300, h: 510 } }
      : { duo: { cx: 540, cy: 965, w: 720, h: 560 }, ipad: { cx: 340, cy: 1515, w: 480, h: 410 }, iphone: { cx: 790, cy: 1515, w: 300, h: 410 } };
    this.ipad = device(this.stage, 'ipad-home', P.ipad);
    this.duo = device(this.stage, 'duo-mappins', P.duo);
    this.iphone = device(this.stage, 'iphone-mission', P.iphone);
    this.labels = [[this.ipad, 'iPad'], [this.duo, 'iPhone Duo'], [this.iphone, 'iPhone']].map(([d, name]) => {
      const lb = el('div', 'devlabel', this.stage, name);
      const low = d === this.duo && !L ? d : (L ? this.ipad : this.ipad);
      lb.style.left = d.cx + 'px'; lb.style.top = Math.max(low.cy + low.h / 2, d.cy + d.h / 2) + (L ? 40 : 32) + 'px';
      return lb;
    });
  },
  update(u, dur) {
    this.t.update(u, dur);
    const ko = clamp((u - (dur - 0.14)) / 0.14);
    const open = CUES.unfold - 28;
    this.duo.fold(lerp(178, 0, eio((u - open) / 0.9)));
    const kd = back((u - 0.02) / 0.5);
    // Closed, the Duo is one half wide: it sits in the middle, then slides as it opens.
    const shift = lerp(-this.duo.w / 4, 0, eio((u - open) / 0.9));
    this.duo.root.style.transform = `translate3d(${shift}px,${(1 - kd) * 500 + Math.sin(u * 1.2) * 5}px,60px) rotateX(${7}deg) rotateY(${Math.sin(u * 0.9) * 3}deg)`;
    this.duo.root.style.opacity = clamp(u / 0.12) * (1 - ko);
    [[this.ipad, 1.25, -1, 6], [this.iphone, 1.45, 1, -6]].forEach(([d, at, dir, ry]) => {
      const k = back((u - at) / 0.55);
      d.root.style.transform = `translate3d(${(1 - k) * (L ? 300 : 500) * dir}px,${Math.sin(u * 1.2 + at * 3) * 5}px,0) rotateY(${ry + Math.sin(u + at) * 2}deg) rotateX(5deg) scale(${lerp(0.8, 1, eo((u - at) / 0.5))})`;
      d.root.style.opacity = clamp((u - at) / 0.12) * (1 - ko);
    });
    this.labels.forEach((lb, i) => { const k = eo((u - [1.5, 1.15, 1.7][i]) / 0.3); lb.style.opacity = k * (1 - ko); lb.style.transform = `translate(-50%,${(1 - k) * 14}px)`; });
  },
};

// What it does not do: no account, no ads, no tracking. One line per beat, then four promises.
SC.trust = {
  build(root) {
    this.t = textBlock(root, { kicker: 'Private by design', lines: ['NO ACCOUNT.', 'NO ADS.', '*NO TRACKING.*'], lineStep: 0.5, size: L ? 150 : 132 });
    this.stage = el('div', 'persp', root);
    const grid = el('div', 'trust', this.stage);
    const gw = L ? 860 : 940, gh = L ? 560 : 640;
    Object.assign(grid.style, { left: BOX.cx - gw / 2 + 'px', top: (L ? BOX.cy + 20 : BOX.cy + 40) - gh / 2 + 'px', width: gw + 'px', height: gh + 'px' });
    const items = [['WORKS OFFLINE', 'The whole guide, no network needed'], ['6 LANGUAGES', 'EN · FR · ES · DE · IT · PT'], ['EVERY GUIDE IS FREE', 'Pro is optional'], ['YOUR DATA STAYS YOURS', 'Progress is kept on your devices']];
    this.cards = items.map(([a, b], i) => {
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
      const v = u - (CUES.trustCards[i] - 32), k = back(v / 0.4);
      c.style.transform = `translateY(${(1 - eo(v / 0.4)) * 60}px) scale(${Math.max(0, k)})`;
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
    this.tag = el('div', 'endtag', wrap, 'Map · 100% tracker · all cheats · spoiler-free');
    this.cta = el('div', 'cta', wrap);
    this.cta.innerHTML = CTA === 'soon' ? '<small>Coming soon to the</small><b>App Store</b>' : '<small>Download on the</small><b>App Store</b>';
    this.devs = el('div', 'enddevs', wrap, 'iPhone  ·  iPhone Duo  ·  iPad');
    // The App Store link, once the app is live (python3 build.py <work> wide now --link <url>).
    this.link = LINK ? el('div', 'endlink', wrap, LINK.replace(/^https?:\/\//, '')) : null;
    this.legal = el('div', 'legal', root);
    this.legal.innerHTML = 'Unofficial fan guide. Not affiliated with, endorsed or approved by Rockstar Games or Take-Two Interactive. Game names are trademarks of their owners.<br>Map: GTA VI Community Map by Yanis &amp; the mapping community, via GTADB.org, CC BY 4.0. Some features need Vicefold Pro.';
    this.wrap = wrap;
  },
  update(u, dur) {
    const ki = back((u - 0.05) / 0.6);
    this.icon.style.transform = `scale(${Math.max(0, ki) * (1 + 0.012 * Math.sin(u * 2.4))}) rotate(${(1 - eo(u / 0.6)) * -14}deg)`;
    this.icon.style.opacity = clamp(u / 0.1);
    this.halo.style.opacity = clamp(u / 0.4) * (0.75 + 0.25 * Math.sin(u * 2.4));
    this.halo.style.transform = `translate(-50%,-50%) scale(${lerp(0.5, 1, eo(u / 0.8))})`;
    [...this.name.querySelectorAll('span')].forEach((s, i) => { s.style.transform = `translateY(${(1 - eo((u - 0.45 - i * 0.14) / 0.4)) * 105}%)`; });
    const kt = eo((u - 0.95) / 0.4); this.tag.style.opacity = kt; this.tag.style.transform = `translateY(${(1 - kt) * 18}px)`;
    const v = u - (CUES.endCta - 36), kc = back(v / 0.45);
    this.cta.style.transform = `scale(${Math.max(0, kc) * (1 + 0.02 * Math.sin(Math.max(0, v) * 5))})`; this.cta.style.opacity = clamp(v / 0.1);
    const kd = eo((v - 0.3) / 0.4); this.devs.style.opacity = kd;
    if (this.link) { const kl = back((v - 0.5) / 0.45); this.link.style.opacity = clamp((v - 0.5) / 0.1); this.link.style.transform = `scale(${Math.max(0, kl)})`; }
    this.legal.style.opacity = eo((u - 1.2) / 0.5) * 0.62;
    const fade = clamp((u - (dur - 0.5)) / 0.5);
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
  for (const s of scenes) { if (s.a === 0) continue; const k = (t - (s.a - 0.1)) / 0.3; if (k > 0 && k < 1) { band = k; any = true; } }
  swipe.style.display = any ? 'block' : 'none';
  if (any) swipe.style.transform = `translateX(${lerp(-110, 190, band)}%) skewX(-24deg)`;
  const endA = CUES.scenes[CUES.scenes.length - 1][1];
  foot.style.opacity = clamp((t - 2.2) / 0.5) * (1 - clamp((t - (endA - 0.2)) / 0.2));
}
