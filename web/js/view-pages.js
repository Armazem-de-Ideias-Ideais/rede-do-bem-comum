/* Páginas de texto (Sobre, Privacidade, Termos, Atribuição, Carta de convivência, Por que estou aqui)
   geradas de docs/textos/*.md por scripts/build_public_json.py (js/texts.js). As marcações de MINUTA são mantidas. */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon, ui = RBC.ui;
  var TOC = ['about', 'charter', 'why', 'attribution', 'privacy', 'terms'];

  function doc(id) { var d = (window.RBC_TEXTS || {})[id]; return d ? (d[RBC.state.lang] || d.pt) : null; }
  function links(html) {
    return html.replace(/href="#" data-route="([a-z]+)"/g, function (m, r) { return RBC.routeById[r] ? 'href="' + RBC.href(r) + '"' : m; })
      .replace(/<a href="(https?:[^"]+)" rel="noopener noreferrer"/g, '<a href="$1" rel="noopener noreferrer" target="_blank"');
  }

  TOC.forEach(function (id) {
    var V = RBC.views[id] = { needsData: id === 'attribution' };
    V.title = function () { var d = doc(id); return d ? d.title : id; };
    V.render = function () {
      var d = doc(id); if (!d) return ui.state('error', { h: 'h1', focus: true, title: t('state.error'), text: t('state.error_text') });
      var html = links(d.html);
      if (id === 'attribution') html = html.replace('<div data-sources-auto></div>', '<div id="sources-auto">' + ui.loading(1) + '</div>');
      return '<div class="view--text">' + ui.pageHead({ eyebrow: t('pages.eyebrow'), title: d.title }) +
        (d.draft ? ui.notice('warn', '<div class="draftnote">' + d.draft + '</div>', 'alert') : '') +
        '<nav class="toc" aria-label="' + esc(t('pages.toc')) + '"><ul>' + TOC.map(function (k) { return '<li><a href="' + RBC.href(k) + '"' + (k === id ? ' aria-current="page"' : '') + '>' + esc(t('nav.' + k)) + '</a></li>'; }).join('') + '</ul></nav>' +
        '<div class="prose">' + html + '</div></div>';
    };
    if (id === 'attribution') V.mount = function (el) {
      var box = RBC.qs('#sources-auto', el); if (!box) return;
      RBC.db.sources().then(function (list) {
        if (!document.body.contains(box)) return;
        var total = list.reduce(function (s, x) { return s + x.n; }, 0);
        box.innerHTML = '<p>' + esc(t('attr.summary', { n: RBC.num(list.length), total: RBC.num(total) })) + '</p>' +
          '<div class="tablewrap" tabindex="0" role="region" aria-label="' + esc(t('attr.table')) + '"><table class="table"><caption class="sr">' + esc(t('attr.table')) + '</caption><thead><tr><th scope="col">' + esc(t('attr.col.source')) + '</th><th scope="col">' + esc(t('attr.col.n')) + '</th><th scope="col">' + esc(t('attr.col.licence')) + '</th></tr></thead><tbody>' +
          list.map(function (s) {
            var name = /^[a-z0-9.-]+\.[a-z]{2,}$/i.test(s.name) ? ui.extLink('https://' + s.name, s.name) : esc(s.name);
            return '<tr><th scope="row">' + name + '</th><td>' + RBC.num(s.n) + '</td><td>' + (s.licence.length ? s.licence.map(function (l) { return '<span lang="pt">' + esc(l) + '</span>'; }).join('<br>') : '<span class="muted">' + esc(t('attr.public')) + '</span>') + '</td></tr>';
          }).join('') + '</tbody></table></div>';
      }, function () { box.innerHTML = '<p class="muted">' + esc(t('state.error_text')) + '</p>'; });
    };
  });

  var N = RBC.views.notfound = { needsData: false };
  N.title = function () { return t('notfound.title'); };
  N.render = function () {
    return '<div class="view--narrow">' + ui.state('notfound', { h: 'h1', focus: true, title: t('notfound.title'), text: t('notfound.text'),
      actions: ui.btn(t('nav.home'), { href: RBC.href('home'), icon: 'arrow-left' }) + ui.btn(t('nav.explore'), { href: RBC.href('explore'), kind: 'secondary', icon: 'search' }) }) + '</div>';
  };
})();
