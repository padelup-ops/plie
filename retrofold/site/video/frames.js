// Images du film : node frames.js DOSSIER tout | instant…  (film.html est placé à chaque instant par window.seek)
const { chromium } = require('playwright');
const path = require('path'), fs = require('fs');
const FPS = 30, DURATION = 39.5;
(async () => {
  const [folder, ...args] = process.argv.slice(2);
  const times = args[0] === 'tout' ? Array.from({ length: Math.floor(DURATION * FPS) }, (_, i) => i / FPS) : args.map(Number);
  fs.mkdirSync(folder, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
  await page.goto('file://' + path.join(__dirname, 'film.html'));
  await page.waitForFunction('window.ready === true');
  for (let i = 0; i < times.length; i++) {
    await page.evaluate(t => window.seek(t), times[i]);
    await page.screenshot({ path: path.join(folder, 'f' + String(i).padStart(5, '0') + '.jpg'), type: 'jpeg', quality: 92 });
  }
  await browser.close();
})();
