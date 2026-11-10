// node render.cjs fps from to   -> frames/f_00000.jpg (reprend là où il s'est arrêté)
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const fps = +process.argv[2] || 30, from = +process.argv[3] || 0;
  const OUT = process.env.OUT || 'frames', CONF = process.env.CONF || 'film-conf.js'; fs.mkdirSync(OUT, { recursive: true });
  const b = await chromium.launch({ args: ['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: +(process.env.VW||1200), height: +(process.env.VH||1200) } });
  p.on('pageerror', e => console.log('error:', e.message));
  await p.goto('http://localhost:8766/' + (process.env.PAGE || 'film.html') + '?conf=' + CONF); await p.waitForFunction(() => window.ready, null, {timeout: 120000}); await p.evaluate(() => window.ready);
  const dur = await p.evaluate(() => window.FILM.duration); const to = +process.argv[4] || Math.ceil(dur * fps);
  const t0 = Date.now();
  for (let i = from; i < to; i++) {
    const f = `${OUT}/f_${String(i).padStart(5, '0')}.jpg`; if (fs.existsSync(f)) continue;
    await p.evaluate(t => window.frame(t), i / fps);
    await p.screenshot({ path: f + '.tmp', type: 'jpeg', quality: 92 }); fs.renameSync(f + '.tmp', f);
    if (i % 60 === 0) console.log(i, '/', to, Math.round((Date.now() - t0) / 1000) + 's');
  }
  await b.close(); console.log('fini');
})();
