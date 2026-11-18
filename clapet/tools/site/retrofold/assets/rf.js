// RetroFold site: a playable Snake cartridge in the hero console, skins, screens and the cartridge shelf.
(() => {
  const T = window.RF_TEXT || {};
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------- skins and screens (colors from the app) ----------
  const SKINS = {
    classic:  { name: 'Classic Grey', shell: '#c9c8c4', lo: '#a9a8a3', bezel: '#2a2d33', blo: '#1c1e22', btn: '#a8325e', dpad: '#2f2f32', etch: '#56545b', edge: 'transparent', led: '#ff3b3b' },
    purple:   { name: 'Atomic Purple', shell: '#8a4fd0', lo: '#5e2a99', bezel: '#2a1540', blo: '#150a22', btn: '#e040fb', dpad: '#4a0e78', etch: '#e9d7ff', edge: 'transparent', led: '#7cff6b' },
    neon:     { name: 'Cyberpunk Neon', shell: '#151519', lo: '#0b0b0e', bezel: '#0b0b14', blo: '#050508', btn: '#ff2e88', dpad: '#1a1a2e', etch: '#ff1493', edge: '#00ffff', led: '#00ffff' },
    arcade:   { name: "90's Arcade Cabinet", shell: '#6b4a3a', lo: '#4a3022', bezel: '#1a1a1a', blo: '#0a0a0a', btn: '#e53935', dpad: '#141414', etch: '#ffd700', edge: 'transparent', led: '#ffb300' },
    ice:      { name: 'Clear Ice', shell: '#a8dadc', lo: '#7fb7bb', bezel: '#1d3557', blo: '#0b1a2e', btn: '#90e0ef', dpad: '#e8f4f8', etch: '#023e8a', edge: 'transparent', led: '#48cae4' },
    crimson:  { name: 'Crimson & Cream', shell: '#f1e9da', lo: '#d9cfbb', bezel: '#8e1b22', blo: '#5c0f14', btn: '#b5121b', dpad: '#3a3a3a', etch: '#b5121b', edge: 'transparent', led: '#ffd166' },
    yellow:   { name: 'Electric Yellow', shell: '#ffd60a', lo: '#e0b400', bezel: '#2a2d33', blo: '#1c1e22', btn: '#1d3557', dpad: '#1d3557', etch: '#3d2c00', edge: 'transparent', led: '#e63946' },
    gold:     { name: 'Gold Edition', shell: '#d9b445', lo: '#a8831c', bezel: '#2a2410', blo: '#15120a', btn: '#2b2b2b', dpad: '#2b2b2b', etch: '#3b2f0b', edge: 'transparent', led: '#ffe8a3' },
  };
  const SCREENS = {
    lcd:       { bg: '#9fb33a', fg: '#2b3a10', mid: '#5d7420', food: '#2b3a10', text: '#2b3a10' },
    crt:       { bg: '#0d1410', fg: '#5cf07a', mid: '#2c7a3e', food: '#ff5c5c', text: '#d8ffd8' },
    trinitron: { bg: '#10131c', fg: '#7fd3ff', mid: '#2f5d8a', food: '#ffd166', text: '#e6f3ff' },
    arcade:    { bg: '#06060a', fg: '#ff2e88', mid: '#7a1546', food: '#00ffff', text: '#ffe3f0' },
  };

  const con = document.querySelector('.console');
  if (con) {
    const setSkin = (k) => {
      const s = SKINS[k]; if (!s) return;
      const st = con.style;
      st.setProperty('--shell', s.shell); st.setProperty('--shell-lo', s.lo); st.setProperty('--bezel', s.bezel); st.setProperty('--bezel-lo', s.blo);
      st.setProperty('--btn', s.btn); st.setProperty('--dpad', s.dpad); st.setProperty('--etch', s.etch); st.setProperty('--edge', s.edge); st.setProperty('--led', s.led);
      document.querySelectorAll('[data-skin]').forEach(b => b.setAttribute('aria-pressed', b.dataset.skin === k ? 'true' : 'false'));
      const out = document.getElementById('skin-name'); if (out) out.textContent = s.name;
    };
    document.querySelectorAll('[data-skin]').forEach(b => {
      const s = SKINS[b.dataset.skin]; b.style.setProperty('--c', s.shell); b.style.setProperty('--c2', s.btn); b.title = s.name; b.setAttribute('aria-label', s.name);
      b.addEventListener('click', () => setSkin(b.dataset.skin));
    });
    const modeEl = con.querySelector('.mode');
    const setScreen = (k) => {
      con.dataset.screen = k; pal = SCREENS[k]; draw();
      document.querySelectorAll('[data-screen-pick]').forEach(b => b.setAttribute('aria-pressed', b.dataset.screenPick === k ? 'true' : 'false'));
      const b = document.querySelector(`[data-screen-pick="${k}"]`); if (modeEl && b) modeEl.textContent = b.dataset.tag || '';
    };
    document.querySelectorAll('[data-screen-pick]').forEach(b => b.addEventListener('click', () => setScreen(b.dataset.screenPick)));

    // ---------- Snake ----------
    const cv = con.querySelector('canvas'), ctx = cv.getContext('2d');
    const CW = 24, CH = 16, S = 8; cv.width = CW * S; cv.height = CH * S;
    const scoreEl = con.querySelector('.score');
    let pal = SCREENS[con.dataset.screen || 'lcd'];
    let snake, dir, nextDir, food, state = 'attract', score = 0, best = 0, tick = 0, timer = null, visible = true, blink = true;
    try { best = +localStorage.getItem('rf-snake-best') || 0; } catch (e) {}

    const eq = (a, b) => a.x === b.x && a.y === b.y;
    function reset() {
      snake = [{ x: 10, y: 8 }, { x: 9, y: 8 }, { x: 8, y: 8 }, { x: 7, y: 8 }]; dir = { x: 1, y: 0 }; nextDir = dir; score = 0; placeFood();
    }
    function placeFood() {
      do { food = { x: Math.floor(Math.random() * CW), y: Math.floor(Math.random() * CH) }; } while (snake.some(p => eq(p, food)));
    }
    function free(p) { return p.x >= 0 && p.y >= 0 && p.x < CW && p.y < CH && !snake.slice(0, -1).some(q => eq(q, p)); }
    function pilot() { // attract mode: head for the food, never into itself
      const h = snake[0];
      const opts = [{ x: 1, y: 0 }, { x: -1, y: 0 }, { x: 0, y: 1 }, { x: 0, y: -1 }].filter(d => !(d.x === -dir.x && d.y === -dir.y));
      const ok = opts.filter(d => free({ x: h.x + d.x, y: h.y + d.y }));
      if (!ok.length) return;
      ok.sort((a, b) => (Math.abs(h.x + a.x - food.x) + Math.abs(h.y + a.y - food.y)) - (Math.abs(h.x + b.x - food.x) + Math.abs(h.y + b.y - food.y)));
      nextDir = ok[0];
    }
    function step() {
      tick++;
      if (state === 'over') { blink = tick % 8 < 5; draw(); return; }
      if (state === 'attract') { pilot(); blink = tick % 8 < 5; }
      dir = nextDir;
      const h = { x: snake[0].x + dir.x, y: snake[0].y + dir.y };
      if (!free(h)) {
        if (state === 'attract') { reset(); draw(); return; }
        state = 'over'; if (score > best) { best = score; try { localStorage.setItem('rf-snake-best', best); } catch (e) {} }
        draw(); return;
      }
      snake.unshift(h);
      if (eq(h, food)) { score += 10; placeFood(); } else snake.pop();
      draw();
    }
    function cell(x, y, c, inset = 1) { ctx.fillStyle = c; ctx.fillRect(x * S + inset, y * S + inset, S - inset * 2, S - inset * 2); }
    function text(t, y, size = 8) {
      ctx.fillStyle = pal.text; ctx.font = `700 ${size}px Pix, monospace`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(t, cv.width / 2, y);
    }
    function draw() {
      if (!snake) return;
      ctx.fillStyle = pal.bg; ctx.fillRect(0, 0, cv.width, cv.height);
      if (con.dataset.screen === 'lcd') { ctx.fillStyle = 'rgba(43,58,16,.06)'; for (let x = 0; x < CW; x++) for (let y = 0; y < CH; y++) ctx.fillRect(x * S + 1, y * S + 1, S - 2, S - 2); }
      cell(food.x, food.y, pal.food, 2);
      snake.forEach((p, i) => cell(p.x, p.y, i === 0 ? pal.fg : pal.mid === pal.bg ? pal.fg : (i % 2 ? pal.fg : pal.mid), i === 0 ? 0 : 1));
      if (state === 'attract' && blink) { ctx.fillStyle = pal.bg; ctx.fillRect(16, 50, cv.width - 32, 26); text(T.press || 'PRESS START', 63); }
      if (state === 'over') { ctx.fillStyle = pal.bg; ctx.fillRect(24, 40, cv.width - 48, 46); text(T.over || 'GAME OVER', 54); if (blink) text(T.again || 'START: AGAIN', 72, 7); }
      if (scoreEl) scoreEl.textContent = `${T.score || 'SCORE'} ${String(score).padStart(4, '0')}  ${T.hi || 'HI'} ${String(Math.max(best, score)).padStart(4, '0')}`;
    }
    function run() {
      clearInterval(timer); timer = null;
      if (!visible) return;
      if (reduce && state !== 'play') return;
      timer = setInterval(step, state === 'play' ? Math.max(70, 130 - Math.floor(score / 50) * 8) : 140);
    }
    function start() { reset(); state = 'play'; tick = 0; draw(); run(); con.focus({ preventScroll: true }); }
    function turn(d) {
      if (state !== 'play') { start(); }
      if (d.x === -dir.x && d.y === -dir.y) return;
      nextDir = d;
    }
    const DIRS = { u: { x: 0, y: -1 }, d: { x: 0, y: 1 }, l: { x: -1, y: 0 }, r: { x: 1, y: 0 } };
    con.querySelectorAll('.dpad button').forEach(b => b.addEventListener('pointerdown', e => { e.preventDefault(); turn(DIRS[b.dataset.d]); }));
    con.querySelectorAll('[data-start]').forEach(b => b.addEventListener('click', () => {
      if (state === 'play') { state = 'paused'; clearInterval(timer); text(T.pause || 'PAUSE', 64); return; }
      if (state === 'paused') { state = 'play'; run(); return; }
      start();
    }));
    const KEYS = { ArrowUp: 'u', ArrowDown: 'd', ArrowLeft: 'l', ArrowRight: 'r', w: 'u', s: 'd', a: 'l', d: 'r', z: 'u', q: 'l' };
    con.addEventListener('keydown', e => {
      const k = KEYS[e.key];
      if (k) { e.preventDefault(); turn(DIRS[k]); const b = con.querySelector(`.dpad [data-d="${k}"]`); b && (b.classList.add('on'), setTimeout(() => b.classList.remove('on'), 120)); }
      else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); con.querySelector('[data-start]').click(); }
    });
    // swipe on the screen
    let t0 = null;
    cv.addEventListener('pointerdown', e => { t0 = { x: e.clientX, y: e.clientY }; });
    cv.addEventListener('pointerup', e => {
      if (!t0) return; const dx = e.clientX - t0.x, dy = e.clientY - t0.y; t0 = null;
      if (Math.max(Math.abs(dx), Math.abs(dy)) < 18) { if (state !== 'play') start(); return; }
      turn(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? DIRS.r : DIRS.l) : (dy > 0 ? DIRS.d : DIRS.u));
    });
    new IntersectionObserver(es => { visible = es[0].isIntersecting; if (state !== 'paused') run(); }).observe(con);
    reset(); setSkin('classic'); setScreen(con.dataset.screen || 'lcd');
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => { draw(); run(); });
  }

  // ---------- cartridge labels: 8x8 pixel art ----------
  const ART = {
    brick: ['11011011', '11011011', '00000000', '11011011', '00000000', '00010000', '00000000', '00111100'],
    racer: ['00011000', '00111100', '01111110', '00111100', '00111100', '01111110', '01111110', '00100100'],
    snake: ['01111100', '01000000', '01111100', '00000100', '00111100', '00000000', '00000010', '00000000'],
    blocks: ['00011000', '00111100', '00000000', '00000000', '11000011', '11100111', '11111111', '11111111'],
    invaders: ['00100100', '01111110', '11011011', '11111111', '10111101', '10100101', '00100100', '00000000'],
    mines: ['00010000', '01011010', '00111100', '01101110', '11111111', '00111100', '01011010', '00010000'],
    maze: ['00111100', '01111110', '11111100', '11111000', '11111000', '11111100', '01111110', '00111100'],
    frog: ['01100110', '11111111', '10111101', '01111110', '00111100', '01111110', '11000011', '10000001'],
    lunar: ['00011000', '00111100', '01111110', '01011010', '01111110', '00100100', '01000010', '11000011'],
    paddle: ['00000000', '10000000', '10000000', '10000100', '10000001', '00000001', '00000001', '00000000'],
    astro: ['00010000', '00010000', '00111000', '00101000', '01101100', '01000100', '11000110', '00000000'],
    tower: ['00000000', '00111100', '00111100', '00011110', '00011110', '01111000', '01111000', '11111111'],
  };
  document.querySelectorAll('canvas[data-art]').forEach(c => {
    const a = ART[c.dataset.art]; if (!a) return;
    c.width = 10; c.height = 10; const x = c.getContext('2d');
    x.fillStyle = getComputedStyle(c.closest('.label')).getPropertyValue('--lc').trim() || '#fff';
    a.forEach((row, j) => [...row].forEach((v, i) => { if (v === '1') x.fillRect(i + 1, j + 1, 1, 1); }));
  });
})();
