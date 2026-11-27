// Images du film : node frames.js DOSSIER LANGUE LARGEUR HAUTEUR tout | instant…
// film.html reçoit le format et la langue dans window.FILM, puis est placé à chaque instant par window.seek.
const { chromium } = require('playwright');
const path = require('path'), fs = require('fs');
const FPS = 30, DURATION = 39.5;
(async () => {
  const [folder, lang, w, h, ...args] = process.argv.slice(2);
  const times = args[0] === 'tout' ? Array.from({ length: Math.floor(DURATION * FPS) }, (_, i) => i / FPS) : args.map(Number);
  const dict = lang === 'fr' ? {} : JSON.parse(fs.readFileSync(path.join(__dirname, '..', lang + '.json'), 'utf8'));
  fs.mkdirSync(folder, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: +w, height: +h } });
  await page.addInitScript(film => { window.FILM = film; }, { w: +w, h: +h, lang, dict });
  await page.goto('file://' + path.join(__dirname, 'film.html'));
  await page.waitForFunction('window.ready === true');
  for (let i = 0; i < times.length; i++) {
    await page.evaluate(t => window.seek(t), times[i]);
    await page.screenshot({ path: path.join(folder, 'f' + String(i).padStart(5, '0') + '.jpg'), type: 'jpeg', quality: 92 });
  }
  await browser.close();
})();
