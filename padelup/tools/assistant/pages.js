// Pages factices qui imitent les parcours réels (structure plausible, pas une copie).
const cookie = `<div id="cb" style="position:fixed;bottom:0;left:0;right:0;background:#eee;padding:10px;z-index:9"><p>Nous utilisons des cookies</p><button onclick="this.parentNode.remove()">Tout accepter</button></div>`;
exports.playtomicClub = `<!doctype html><html><head><meta name=viewport content="width=device-width"><style>
.card{border:1px solid #ccc;border-radius:8px;padding:14px;margin:10px;cursor:pointer}.dlg{position:fixed;inset:0;background:#fff;z-index:5;padding:10px}
.opt{display:block;width:100%;padding:12px;margin:6px 0}</style></head><body>
<header><a href="/search">Réserver un terrain</a> <a href="/payments-info">Moyens de paiement</a></header>
<img style="height:300px;width:100%;display:block">
<h2>Terrains disponibles</h2><div>Padel <button>‹</button> 28 nov. 2026 sam. 28 nov. <button>›</button></div>
<div id="courts"></div>
<script>self.__next_f=[];self.__next_f.push([1,"{\\"resources\\":[{\\"resource_id\\":\\"r1\\",\\"name\\":\\"Piste CARCE TOITURE\\"},{\\"resource_id\\":\\"r2\\",\\"name\\":\\"Piste Agence DIX Communication Digitale\\"}]}"]);</script>
<script>
const courts=[{id:'r1',name:'Piste CARCE TOITURE',range:'04:30 jusqu\\'à 21:00',times:['18:00','21:00']},{id:'r2',name:'Piste Agence DIX Communication Digitale',range:'04:00 jusqu\\'à 20:30',times:['18:00','19:30']}];
const host=document.getElementById('courts');
courts.forEach(c=>{const d=document.createElement('div');d.className='card';d.innerHTML='<div><span>'+c.name+'</span><span> › </span></div><div>12 options • À partir de '+c.range+'</div>';
 d.addEventListener('click',()=>openDlg(c));host.appendChild(d);});
function openDlg(c){const g=document.createElement('div');g.className='dlg';g.setAttribute('role','dialog');g.setAttribute('aria-modal','true');
 let sel=null;
 g.innerHTML='<button aria-label="Fermer">✕</button><h3>'+c.name+'</h3>';
 c.times.forEach(t=>{[60,90].forEach(du=>{const h=parseInt(t), m=parseInt(t.split(':')[1])+du; const end=String(h+Math.floor(m/60)).padStart(2,'0')+':'+String(m%60).padStart(2,'0');
   const b=document.createElement('button');b.className='opt';b.innerHTML='<span>'+t+' - '+end+'</span> <span>'+du+' min</span> <span>'+(du==90?36:24)+' €</span>';
   b.onclick=()=>{g.querySelectorAll('.opt').forEach(x=>x.setAttribute('aria-pressed','false'));b.setAttribute('aria-pressed','true');sel={t,du};go.disabled=false;go.textContent='Réserver · '+(du==90?36:24)+' €';};g.appendChild(b);});});
 const go=document.createElement('button');go.textContent='Réserver';go.disabled=true;go.onclick=()=>{location.href='/payments?type=CUSTOMER_MATCH&t='+sel.t+'&d='+sel.du;};g.appendChild(go);
 g.querySelector('[aria-label=Fermer]').onclick=()=>g.remove();document.body.appendChild(g);}
</script>${cookie}</body></html>`;
exports.payment = `<!doctype html><html><body><div id=app>Chargement…</div><script>setTimeout(()=>{document.getElementById('app').innerHTML='<h2>Paiement</h2><p>'+decodeURIComponent(location.search)+'</p><p>Total 36,00 €</p><label><input type=radio name=m> Carte</label><button>Payer 36 €</button>'},800)</script></body></html>`;
exports.login = `<!doctype html><html><body><h2>Connexion</h2><input type=email><input type=password><button>Se connecter</button></body></html>`;
exports.anybuddyClub = `<!doctype html><html><head><style>.chip{padding:8px;margin:4px}.sheet{position:fixed;inset:20% 0 0 0;background:#fff;z-index:5}</style></head><body>
<nav><a href="/fr/aide/paiement">Paiement sécurisé</a></nav><h1>Border Padel Lille</h1>
<div>${['18:00','19:00','19:30','20:00'].map(t=>`<button class="chip" aria-label="${t}, dès 36 €, 3 choix disponibles"><span>${t}</span><small>36 €</small></button>`).join('')}</div>
<script>document.querySelectorAll('.chip').forEach(b=>b.onclick=()=>{const s=document.createElement('div');s.className='sheet';s.setAttribute('role','dialog');
 s.innerHTML='<h3>'+b.querySelector('span').textContent+'</h3><div role="radiogroup"><div role="radio" aria-checked="false" tabindex="0">1h</div><div role="radio" aria-checked="false" tabindex="0">1h30</div></div><button disabled id=c>Continuer</button>';
 s.querySelectorAll('[role=radio]').forEach(r=>r.onclick=()=>{s.querySelectorAll('[role=radio]').forEach(x=>x.setAttribute('aria-checked','false'));r.setAttribute('aria-checked','true');s.querySelector('#c').disabled=false;});
 s.querySelector('#c').onclick=()=>{location.href='/fr/checkout/abc';};document.body.appendChild(s);});</script></body></html>`;
// Variante : le terrain se déplie sur place, heures et durées séparées, bouton « Continuer », fenêtre « télécharge l'app ».
exports.inlineClub = `<!doctype html><html><head><meta charset=utf-8><style>.row{cursor:pointer;border:1px solid #ccc;margin:8px;padding:12px}.chip{margin:4px}
.promo{position:fixed;inset:30% 10%;background:#fff;border:1px solid;z-index:9}</style></head><body>
<div class="promo" role="dialog"><p>Télécharge l'application Playtomic</p><button>Plus tard</button></div>
<h2>Terrains disponibles</h2>
<div class="row" id="a"><b>Piste 1</b><div>8 options • À partir de 09:00 jusqu'à 22:00</div><div class="slots"></div></div>
<div class="row" id="b"><b>Piste 2</b><div>8 options • À partir de 09:00 jusqu'à 22:00</div><div class="slots"></div></div>
<script>
document.querySelector('.promo button').onclick=()=>document.querySelector('.promo').remove();
const data={a:['10:00','12:00'],b:['19:30','21:00']};
document.querySelectorAll('.row').forEach(r=>r.addEventListener('click',e=>{ if(e.target.closest('.slots'))return; const s=r.querySelector('.slots'); if(s.innerHTML){s.innerHTML='';return;}
 s.innerHTML=data[r.id].map(t=>'<button class=chip data-t='+t+'>'+t+'</button>').join('')+'<div class=durs></div>';
 s.querySelectorAll('.chip').forEach(c=>c.onclick=()=>{ s.querySelectorAll('.chip').forEach(x=>x.setAttribute('aria-pressed','false')); c.setAttribute('aria-pressed','true');
   s.querySelector('.durs').innerHTML='<button class=d>60 min · 24 €</button><button class=d>90 min · 36 €</button><button class=d>120 min · 48 €</button><button id=go disabled>Continuer</button>';
   s.querySelectorAll('.d').forEach(d=>d.onclick=()=>{s.querySelector('#go').disabled=false;});
   s.querySelector('#go').onclick=()=>{location.href='/checkout?slot='+c.dataset.t;};});}));
</script></body></html>`;
