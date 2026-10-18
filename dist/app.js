'use strict';
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const L = window.AstraI18n;
const T = L.t;
const localizeTweak = tweak => ({...tweak,...Object.fromEntries(['title','category','description','impact','restart'].map(key=>[key,T(tweak[key])]))});
const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let catalog = [], selectedFilter = 'Tous', release = null;
const previews = {
  overview: `<div class="mini-overline"><span>CENTRE DE CONTRÔLE</span><span>LOCAL / BÊTA</span></div><h3>Prêt pour votre session.</h3><p class="mini-desc">Votre PC. Vos réglages. Vous gardez la main.</p><div class="mini-banner"><h4>Un système à votre rythme.</h4><p>Des préférences ciblées, une sauvegarde avant chaque opération.</p><span class="mini-chip">Explorer les optimisations →</span><svg><use href="#spark"/></svg></div><div class="mini-stats"><div class="mini-stat"><span>RÉGLAGES CIBLÉS</span><strong>12</strong><small>4 catégories</small></div><div class="mini-stat"><span>PROFILS POWER</span><strong>3</strong><small>À votre rythme</small></div><div class="mini-stat"><span>TRAITEMENT</span><strong>Local</strong><small>Aucun compte</small></div></div><div class="mini-line"><span>Sauvegarde avant modification</span><span>Intégrée ✓</span></div>`,
  tweaks: `<div class="mini-overline"><span>OPTIMISATIONS</span><span>APERÇU DU MODULE</span></div><h3>Chaque changement compte.</h3><p class="mini-desc">Examinez les préférences avant de confirmer.</p><div class="mini-banner"><h4>Mode Jeu Windows</h4><p>GAME-001 / GAMING<br>AutoGameModeEnabled → 1 (DWord)</p><span class="mini-chip">Valeur d'origine sauvegardée</span><svg><use href="#bolt"/></svg></div><div class="mini-line"><span>Réduire les conseils Windows</span><span>WIN-001 ↗</span></div><div class="mini-line"><span>Désactiver l'identifiant publicitaire</span><span>PRIV-001 ↗</span></div><div class="mini-line"><span>Voir les 12 préférences</span><span>Dans le logiciel</span></div>`,
  power: `<div class="mini-overline"><span>ASTRA POWER</span><span>APERÇU DU MODULE</span></div><h3>La puissance, à votre rythme.</h3><p class="mini-desc">Une copie de votre plan. Votre original reste intact.</p><div class="mini-banner"><h4>ASTRA PERFORMANCE</h4><p>CPU secteur 5–100 %<br>Préférence énergétique secteur : 25</p><span class="mini-chip">Plan précédent sauvegardé</span><svg><use href="#bolt"/></svg></div><div class="mini-stats"><div class="mini-stat"><span>PERFORMANCE</span><strong>25</strong><small>Préférence EPP</small></div><div class="mini-stat"><span>BALANCED</span><strong>50</strong><small>Préférence EPP</small></div><div class="mini-stat"><span>ECO</span><strong>80</strong><small>Préférence EPP</small></div></div><div class="mini-line"><span>Compatibilité du matériel</span><span>Vérifiée localement</span></div>`,
  restore: `<div class="mini-overline"><span>CENTRE DE RESTAURATION</span><span>APERÇU DU MODULE</span></div><h3>Un chemin de retour.</h3><p class="mini-desc">Les valeurs d'origine restent dans votre profil.</p><div class="mini-banner"><h4>Vos opérations, documentées.</h4><p>Journal avant écriture, vérification et restauration dans l'ordre inverse.</p><span class="mini-chip">Vous confirmez chaque opération</span><svg><use href="#restore"/></svg></div><div class="mini-line"><span>Valeurs et types d'origine</span><span>Sauvegardés ✓</span></div><div class="mini-line"><span>Changement externe détecté</span><span>Conflit signalé</span></div><div class="mini-line"><span>Emplacement des sauvegardes</span><span>LocalAppData</span></div>`
};

function selectPreview(name) {
  if (!previews[name]) return;
  $$('.preview-tabs button').forEach(button => { const active = button.dataset.preview === name; button.setAttribute('aria-selected', active); button.tabIndex = active ? 0 : -1; });
  $('#preview-content').innerHTML = L.html(previews[name]);
  $('#preview-content').setAttribute('aria-labelledby', `tab-${name}`);
}
$$('[data-preview]').forEach(button => button.addEventListener('click', () => selectPreview(button.dataset.preview)));
selectPreview('overview');

const profiles = {
  Performance: {index:'01',title:'Prêt pour votre prochaine partie.',description:'Sur secteur, favorisez la performance avec une préférence énergétique de 25 et un CPU autorisé de 5 à 100 %.',cpu:'5–100',epp:25},
  Balanced: {index:'02',title:'Le bon équilibre, au quotidien.',description:'Sur secteur, équilibrez réactivité et consommation avec une préférence énergétique de 50 et un CPU autorisé de 5 à 100 %.',cpu:'5–100',epp:50},
  Eco: {index:'03',title:'Ralentir, quand vous le décidez.',description:'Limitez le CPU à 80 % sur secteur et batterie. La préférence énergétique sur secteur passe à 80 pour favoriser les économies.',cpu:'5–80',epp:80}
};
function selectProfile(name) {
  const p = profiles[name];
  $$('[data-profile]').forEach(button => { const active = button.dataset.profile === name; button.setAttribute('aria-selected', active); button.tabIndex = active ? 0 : -1; });
  $('#profile-panel').setAttribute('aria-labelledby', `profile-${name.toLowerCase()}`);
  $('#profile-title').textContent=T(p.title); $('#profile-description').textContent=T(p.description);
  $('#power-name').textContent=name.toUpperCase(); $('#power-index').textContent=`${p.index} / 03`;
  $('#power-cpu').innerHTML=`${p.cpu} <small>%</small>`; $('#epp-bar').style.width=`${p.epp}%`; $('#epp-value').textContent=`${p.epp} / 100`;
}
$$('[data-profile]').forEach(button => button.addEventListener('click', () => selectProfile(button.dataset.profile)));
$$('[role="tablist"]').forEach(tablist => tablist.addEventListener('keydown', event => {
  const buttons=$$('[role="tab"]',tablist); const index=buttons.indexOf(document.activeElement); if(index<0) return;
  let next=null;
  if(event.key==='ArrowRight'||event.key==='ArrowDown') next=(index+1)%buttons.length;
  if(event.key==='ArrowLeft'||event.key==='ArrowUp') next=(index-1+buttons.length)%buttons.length;
  if(event.key==='Home') next=0; if(event.key==='End') next=buttons.length-1;
  if(next!==null){event.preventDefault();buttons[next].focus();buttons[next].click();}
}));

function renderCatalog() {
  const term=$('#tweak-search').value.trim().toLocaleLowerCase(L.language);
  const entries=catalog.filter(original=>{const tweak=localizeTweak(original);return (selectedFilter==='Tous'||original.category===selectedFilter)&&`${tweak.title} ${tweak.id} ${tweak.description} ${original.title}`.toLocaleLowerCase(L.language).includes(term);}).map(localizeTweak);
  $('#catalogue-count').textContent=T(entries.length!==1?'{0} réglages':'{0} réglage',entries.length);
  $('#catalogue-list').innerHTML=entries.length ? entries.map(tweak=>`<button class="catalogue-row" data-tweak="${escapeHTML(tweak.id)}" aria-label="${escapeHTML(T('Détails : '))}${escapeHTML(tweak.title)}"><span class="catalogue-id">${escapeHTML(tweak.id)}</span><span class="catalogue-name"><strong>${escapeHTML(tweak.title)}</strong><small>${escapeHTML(tweak.impact)}</small></span><span class="category-tag">${escapeHTML(tweak.category)}</span><span aria-hidden="true">↗</span></button>`).join('') : L.html('<p class="empty-result">Aucun réglage ne correspond à cette recherche.</p>');
}
$$('[data-filter]').forEach(button=>button.addEventListener('click',()=>{
  selectedFilter=button.dataset.filter;
  $$('[data-filter]').forEach(item=>{const active=item===button;item.classList.toggle('active',active);item.setAttribute('aria-pressed',active);});renderCatalog();
}));
$('#tweak-search').addEventListener('input',renderCatalog);
$('#catalogue-list').addEventListener('click',event=>{
  const button=event.target.closest('[data-tweak]'); if(!button) return;
  const original=catalog.find(item=>item.id===button.dataset.tweak); if(!original) return; const tweak=localizeTweak(original);
  $('#tweak-id').textContent=`${tweak.id} / ${tweak.category}`; $('#tweak-title').textContent=tweak.title; $('#tweak-description').textContent=tweak.description;
  $('#tweak-details').innerHTML=L.html(`<dt>Objectif</dt><dd>${escapeHTML(tweak.impact)}</dd><dt>Prise en compte</dt><dd>${escapeHTML(tweak.restart)}</dd><dt>Réglage Windows / utilisateur actuel</dt>${tweak.settings.map(s=>`<dd><code>${escapeHTML(['HKCU',s.path,s.name].join(String.fromCharCode(92)))}</code><br>Valeur cible : <strong>${escapeHTML(s.value)} (${escapeHTML(s.kind)})</strong></dd>`).join('')}<dt>Restauration</dt><dd>La valeur et le type d'origine sont conservés. Une valeur absente avant l'opération est retirée lors de la restauration.</dd>`);
  openModal($('#tweak-dialog'));
});

let dialogTrigger=null;
function openModal(dialog){dialogTrigger=document.activeElement;dialog.showModal();document.body.style.overflow='hidden';}
$$('dialog').forEach(dialog=>{
  $('.modal-close',dialog).addEventListener('click',()=>dialog.close());
  dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
  dialog.addEventListener('close',()=>{document.body.style.overflow='';dialogTrigger?.focus();});
});
$('#download-open').addEventListener('click',()=>openModal($('#download-dialog')));
$('#privacy-open').addEventListener('click',()=>openModal($('#privacy-dialog')));
$('#copy-sha').addEventListener('click',async()=>{
  if(!release) return;
  try{await navigator.clipboard.writeText(release.sha256);$('#download-status').textContent=T('Empreinte SHA-256 copiée.');}catch{$('#download-status').textContent=T('Copie indisponible. Sélectionnez l’empreinte affichée ou ouvrez le fichier de contrôle.');}
});
$('#download-link').addEventListener('click',()=>{$('#download-status').textContent=T('Téléchargement demandé. Extrayez tous les fichiers du ZIP avant le lancement.');});
const menu=$('.menu-toggle');menu.addEventListener('click',()=>{const open=menu.getAttribute('aria-expanded')!=='true';menu.setAttribute('aria-expanded',open);$('#navigation').classList.toggle('open',open);});
$$('#navigation a').forEach(link=>link.addEventListener('click',()=>{menu.setAttribute('aria-expanded','false');$('#navigation').classList.remove('open');}));

Promise.all([
  fetch('/catalog.json').then(response=>{if(!response.ok)throw new Error('catalog');return response.json();}).then(data=>{catalog=data;renderCatalog();}).catch(()=>{$('#catalogue-list').innerHTML=L.html('<p class="empty-result">Le catalogue est momentanément indisponible. Retrouvez les 12 réglages dans le logiciel et le guide.</p>');}),
  fetch('/downloads/release.json').then(response=>{if(!response.ok)throw new Error('release');return response.json();}).then(data=>{release=data;$('#checksum-value').textContent=data.sha256;$('#download-meta').textContent=`ZIP · ${new Intl.NumberFormat(L.language,{maximumFractionDigits:1}).format(data.bytes/1024)} ${T('Ko')} · ${T('Sources incluses')}`;$('#download-link').href=data.file;}).catch(()=>{$('#checksum-value').textContent=T('Consultez le fichier SHA256SUMS.txt.');$('#copy-sha').disabled=true;})
]);
