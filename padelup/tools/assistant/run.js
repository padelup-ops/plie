// Banc d'essai de l'assistant de réservation (ios/App/ProviderWeb.swift) sur des pages factices qui imitent les
// parcours Playtomic et Anybuddy : terrains, fenêtre des heures, durées, bouton pour avancer, page de paiement.
// Lancer : node padelup/tools/assistant/run.js   (Playwright et Chromium installés)
// Chaque scénario doit finir sur « payment », « login » ou « missing », sans jamais toucher « Payer ».
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');
const P = require(path.join(__dirname, 'pages.js'));

const swift = fs.readFileSync(path.join(__dirname, '../../ios/App/ProviderWeb.swift'), 'utf8');
const DELIM = '"' + '""';
function raw(name) {
  const start = swift.indexOf('static let ' + name + ' = ');
  if (start < 0) throw new Error('script introuvable : ' + name);
  const open = swift.indexOf('#' + DELIM + '\n', start) + DELIM.length + 2;
  const end = swift.indexOf(DELIM + '#', open);
  return swift.slice(open, swift.lastIndexOf('\n', end));
}
const common = raw('commonJS'), step = raw('stepJS'), confirm = raw('confirmJS');
const body = common + '\n' + step;
let failures = 0;

async function scenario(name, start, args, routes, expect) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.route('**/*', r => {
    const u = new URL(r.request().url());
    for (const [re, html] of routes) if (re.test(u.pathname)) return r.fulfill({ contentType: 'text/html; charset=utf-8', body: html });
    return r.fulfill({ status: 404, body: 'not found' });
  });
  await page.goto(start);
  console.log('\n=== ' + name);
  let result = 'TIMEOUT', paid = false;
  page.on('framenavigated', () => {});
  for (let a = 1; a <= 60; a++) {
    let r;
    try {
      r = await page.evaluate(([src, args]) => new Function('time', 'duration', 'resource', 'attempt', src)(args.time, args.duration, args.resource, args.attempt),
                              [body, { ...args, attempt: a }]);
    } catch (e) { r = { state: 'err', note: e.message.slice(0, 160) }; }
    if (r.note || r.did) console.log(String(a).padStart(2), r.state, r.did, '·', r.note);
    if (/payer/i.test(r.note || '') && r.did) paid = true;   // l'assistant ne doit jamais « agir » sur un bouton Payer
    if (['payment', 'login', 'err', 'missing'].includes(r.state)) {
      const u = new URL(page.url());
      result = r.state + ' @ ' + u.pathname + u.search;
      break;
    }
    await page.waitForTimeout(r.did && r.did !== 'scroll' ? 400 : 200);
  }
  const ok = result.startsWith(expect) && !paid;
  if (!ok) failures++;
  console.log(ok ? 'OK ' : 'ÉCHEC', name, '→', result);
  await browser.close();
}

(async () => {
  const pt = [[/^\/clubs\//, P.playtomicClub], [/^\/payments$/, P.payment]];
  const club = 'https://playtomic.test/clubs/x?date=2026-11-28';
  await scenario('Playtomic 19:30 90 min, terrain connu', club, { time: '19:30', duration: 90, resource: 'r2' }, pt, 'payment @ /payments?type=CUSTOMER_MATCH&t=19:30&d=90');
  await scenario('Playtomic 19:30 90 min, terrain inconnu (essaie puis referme)', club, { time: '19:30', duration: 90, resource: '' }, pt, 'payment @ /payments?type=CUSTOMER_MATCH&t=19:30&d=90');
  await scenario('Playtomic 21:00 60 min', club, { time: '21:00', duration: 60, resource: '' }, pt, 'payment @ /payments?type=CUSTOMER_MATCH&t=21:00&d=60');
  await scenario('Playtomic heure absente 23:00', club, { time: '23:00', duration: 90, resource: '' }, pt, 'missing');
  await scenario('Anybuddy 19:30 90 min', 'https://www.anybuddy.test/fr/club/border-padel-lille', { time: '19:30', duration: 90, resource: '' },
    [[/^\/fr\/club\//, P.anybuddyClub], [/^\/fr\/checkout/, P.payment]], 'payment @ /fr/checkout/abc');
  await scenario('Terrain qui se déplie sur place + fenêtre promo', 'https://playtomic.test/clubs/y', { time: '19:30', duration: 90, resource: '' },
    [[/^\/clubs\//, P.inlineClub], [/^\/checkout$/, P.payment]], 'payment @ /checkout?slot=19:30');
  await scenario('Lien direct qui demande la connexion', 'https://app.playtomic.test/payments?x=1', { time: '19:30', duration: 90, resource: '' },
    [[/^\/payments$/, P.login]], 'login');
  // Confirmation : rien sur la page de paiement, « confirmé » une fois que le joueur a payé.
  {
    const browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await page.route('**/*', r => {
      const u = new URL(r.request().url());
      const html = /^\/payments$/.test(u.pathname) ? P.payment : /^\/matches\//.test(u.pathname) ? P.confirmed : null;
      return html ? r.fulfill({ contentType: 'text/html; charset=utf-8', body: html }) : r.fulfill({ status: 404, body: '' });
    });
    const check = () => page.evaluate(src => new Function(src)(), common + '\n' + confirm);
    await page.goto('https://app.playtomic.test/payments?type=CUSTOMER_MATCH');
    await page.waitForTimeout(1200);
    const before = await check();
    await page.click('#pay');   // le joueur paie lui-même
    await page.waitForTimeout(800);
    const after = await check();
    const ok = before.confirmed === false && before.pay === true && after.confirmed === true;
    if (!ok) failures++;
    console.log('\n=== Confirmation après paiement');
    console.log(ok ? 'OK ' : 'ÉCHEC', 'avant :', JSON.stringify(before), '· après :', JSON.stringify(after));
    await browser.close();
  }
  console.log(failures ? `\n${failures} scénario(s) en échec` : '\nTous les scénarios passent');
  process.exit(failures ? 1 : 0);
})();
