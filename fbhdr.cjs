// node fbhdr.cjs lang layout w h out fps  -> out/f_00000.jpg ; TEST=t1,t2 : quelques images
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const [lang, layout, w, h, out, fps] = process.argv.slice(2); const W = +w, H = +h, F = +fps || 30;
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch({ args: ['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 2 });
  p.on('pageerror', e => console.log('error:', e.message));
  await p.goto(`http://127.0.0.1:8766/fbheader.html?w=${W}&h=${H}&dpr=2&lang=${lang}&layout=${layout}`);
  await p.waitForFunction(() => window.ready, null, { timeout: 120000 }); await p.evaluate(() => window.ready);
  const times = process.env.TEST ? process.env.TEST.split(',').map(Number) : null;
  const n = Math.round(12 * F); const t0 = Date.now();
  const list = times ? times.map(t => Math.round(t * F)) : [...Array(n).keys()];
  for (const i of list) {
    const f = `${out}/f_${String(i).padStart(5, '0')}.jpg`; if (!times && fs.existsSync(f)) continue;
    await p.evaluate(t => window.frame(t), i / F);
    await p.screenshot({ path: f, type: 'jpeg', quality: 92 });
    if (i % 60 === 0) console.log(i, '/', n, Math.round((Date.now() - t0) / 1000) + 's');
  }
  await b.close(); console.log('fini');
})();
