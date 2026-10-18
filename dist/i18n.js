'use strict';
(() => {
  const language = document.documentElement.lang === 'en' ? 'en' : 'fr';
  const dictionary = window.AstraTranslations || {};
  const t = (text, ...values) => {
    const translated = language === 'en' && Object.hasOwn(dictionary, text) ? dictionary[text] : text;
    return values.length ? translated.replace(/\{(\d+)\}/g, (_, index) => String(values[index] ?? '')) : translated;
  };
  const translateText = text => text.replace(/^(\s*)([\s\S]*?)(\s*)$/, (_, before, content, after) => before + t(content) + after);
  const html = source => {
    if (language === 'fr') return source;
    const template = document.createElement('template'); template.innerHTML = source;
    const walker = document.createTreeWalker(template.content, NodeFilter.SHOW_TEXT);
    let node; while ((node = walker.nextNode())) node.nodeValue = translateText(node.nodeValue);
    template.content.querySelectorAll('[aria-label],[placeholder],[title]').forEach(element => {
      ['aria-label','placeholder','title'].forEach(attribute => { if (element.hasAttribute(attribute)) element.setAttribute(attribute,t(element.getAttribute(attribute))); });
    });
    return template.innerHTML;
  };
  const pathFor = lang => `${lang === 'en' ? '/en' : ''}${location.pathname.endsWith('guide.html') ? '/guide.html' : '/'}`;
  const selectors = [...document.querySelectorAll('[data-language-selector]')];
  selectors.forEach(select => {
    select.value=language;
    select.addEventListener('change', () => {
      const next=select.value; if(!['fr','en'].includes(next)) return;
      try { localStorage.setItem('astra-language',next); } catch { /* Browsing remains usable when storage is blocked. */ }
      location.assign(pathFor(next)+location.hash);
    });
  });
  window.AstraI18n = {language,t,html};
  try {
    const saved=localStorage.getItem('astra-language');
    if (['fr','en'].includes(saved) && saved!==language) location.replace(pathFor(saved)+location.hash);
  } catch { /* Storage is optional. */ }
})();
