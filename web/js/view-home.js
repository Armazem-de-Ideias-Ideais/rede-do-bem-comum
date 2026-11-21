/* Início (propósito, busca, contadores reais, famílias, convite) e Participar. */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon, ui = RBC.ui;

  function art(name, alt) {
    /* As ilustrações são faixas 3:1 com papel em branco à esquerda (feitas para cabeçalho).
       Mostramos a parte ilustrada, sem distorcer: proporção 9:4, recorte pela direita. */
    return '<picture><img class="art art--banner" src="assets/ilustracao-' + name + '-900.webp" srcset="assets/ilustracao-' + name + '-900.webp 900w, assets/ilustracao-' + name + '.webp 1600w" sizes="(min-width: 960px) 52vw, 100vw" width="900" height="400" alt="' + esc(alt) + '" loading="lazy" decoding="async"></picture>';
  }
  function action(href, ic, title, text, attrs) {
    return '<li><a class="action" href="' + href + '"' + (attrs || '') + '><span class="blob blob--' + (title.length % 4) + '" aria-hidden="true">' + icon(ic) + '</span><span class="action__t">' + esc(title) + '</span><span class="action__d">' + esc(text) + '</span><span class="action__go" aria-hidden="true">' + icon('arrow-right') + '</span></a></li>';
  }
  RBC.homeAction = action;

  var H = RBC.views.home = { needsData: true };
  H.title = function () { return t('home.title'); };
  H.render = function () {
    var D = RBC.data, c = D.counts, x = RBC.exploreState();
    var kinds = RBC.KINDS.filter(function (k) { return D.kinds[k]; });
    return '<section class="hero" aria-labelledby="page-title"><div class="hero__text">' +
      '<p class="eyebrow">' + esc(t('home.eyebrow')) + '</p><h1 id="page-title" tabindex="-1">' + esc(t('home.title')) + '</h1><p class="lead">' + esc(t('home.lead')) + '</p>' +
      '<form class="homesearch" id="hsearch" role="search" aria-label="' + esc(t('search.form')) + '" novalidate><label for="hq">' + esc(t('search.label')) + '</label>' +
      '<div class="homesearch__row"><div class="inputic">' + icon('search') + '<input id="hq" type="search" autocomplete="off" value="' + esc(x.q) + '" placeholder="' + esc(t('home.search_ph')) + '" aria-describedby="hq-hint"></div>' + ui.btn(t('search.btn'), { type: 'submit' }) + '</div>' +
      '<p class="hint" id="hq-hint">' + esc(t('search.hint')) + '</p></form></div>' +
      '<figure class="hero__art">' + art('comunidade', t('art.community')) + '</figure></section>' +
      '<section class="acts" aria-labelledby="h-acts"><h2 id="h-acts" class="sr">' + esc(t('home.actions')) + '</h2><ul class="actions3">' +
      action(RBC.href('explore'), 'map', t('home.act.map'), t('home.act.map_d'), ' data-explore-map') +
      action(RBC.href('explore'), 'list', t('home.act.list'), t('home.act.list_d'), ' data-explore-list') +
      action(RBC.href('participate'), 'sprout', t('home.act.join'), t('home.act.join_d')) + '</ul></section>' +
      '<section class="counts" aria-labelledby="h-counts"><div class="counts__head"><h2 id="h-counts">' + esc(t('home.counts')) + '</h2></div>' +
      '<dl class="counts__grid counts__grid--main">' +
      counter('total', c.total, 'counts.total') + counter('countries', c.countries, 'counts.countries') + counter('cities', c.cities, 'counts.cities') + counter('active', c.active, 'counts.active') + '</dl>' +
      '<h3 class="counts__sub">' + esc(t('home.by_kind')) + '</h3>' +
      '<dl class="counts__grid counts__grid--kinds">' + kinds.map(function (k) { return counter('kind', D.kinds[k], 'kindp.' + k); }).join('') + '</dl>' +
      '<p class="hint">' + esc(t('home.counts_note', { nomap: RBC.num(c.noMap) })) + '</p></section>' +
      '<section class="areas" aria-labelledby="h-areas"><p class="eyebrow">' + esc(t('home.areas_eyebrow')) + '</p><h2 id="h-areas">' + esc(t('home.areas')) + '</h2><ul class="areagrid">' +
      RBC.FAMILIES.filter(function (f) { return D.fams[f]; }).map(function (f) { return '<li><a href="' + RBC.href('explore') + '" data-fam-link="' + f + '"><span class="areagrid__ic" aria-hidden="true">' + icon(f) + '</span><span class="areagrid__l">' + esc(RBC.famLabel(f)) + '</span><span class="areagrid__n">' + esc(t('home.area_n', { n: RBC.num(D.fams[f]) })) + '</span></a></li>'; }).join('') + '</ul></section>' +
      '<section class="intro" aria-labelledby="h-intro"><div class="intro__text"><h2 id="h-intro">' + esc(t('home.invite.title')) + '</h2>' +
      '<p>' + esc(t('home.invite.p1')) + '</p><p>' + esc(t('home.invite.p2')) + '</p>' +
      '<p class="actions actions--wrap">' + ui.btn(t('home.invite.join'), { href: RBC.href('participate'), icon: 'sprout' }) + ui.btn(t('home.invite.why'), { href: RBC.href('why'), kind: 'secondary', icon: 'info' }) + ui.btn(t('nav.charter'), { href: RBC.href('charter'), kind: 'ghost', icon: 'doc' }) + '</p></div>' +
      '<figure class="intro__art">' + art('cultura', t('art.culture')) + '</figure></section>';
    function counter(cls, n, key) { return '<div class="counter counter--' + cls + '"><dt>' + esc(t(key)) + '</dt><dd>' + RBC.num(n) + '</dd></div>'; }
  };
  H.mount = function (el) {
    RBC.qs('#hsearch', el).addEventListener('submit', function (ev) { ev.preventDefault(); var x = RBC.exploreState(); x.q = RBC.qs('#hq', el).value; x.page = 1; x.mode = 'list'; x.sort = 'auto'; RBC.go('explore'); });
    var m = RBC.qs('[data-explore-map]', el); if (m) m.addEventListener('click', function () { RBC.exploreState().mode = 'map'; });
    var l = RBC.qs('[data-explore-list]', el); if (l) l.addEventListener('click', function () { RBC.exploreState().mode = 'list'; });
  };

  /* ---------- Participar ---------- */
  var P = RBC.views.participate = { needsData: false };
  P.title = function () { return t('join.title'); };
  P.render = function () {
    var live = RBC.db.caps.write;
    return ui.pageHead({ eyebrow: t('join.eyebrow'), title: t('join.title'), lead: t('join.lead') }) +
      (live ? '' : ui.notice('warn', '<p>' + esc(t('soon.banner')) + '</p>', 'clock')) +
      '<ul class="actions3 actions3--four">' +
      action(RBC.href('claim'), 'key', t('join.claim.t'), t('join.claim.d')) +
      action(RBC.href('suggest'), 'plus', t('join.suggest.t'), t('join.suggest.d')) +
      action(RBC.href('offers'), 'offer', t('join.offers.t'), t('join.offers.d')) +
      action(RBC.href('mySpace'), 'user', t('join.space.t'), t('join.space.d')) + '</ul>' +
      '<div class="twocol"><section class="psec" aria-labelledby="j-care"><h2 id="j-care">' + esc(t('join.care')) + '</h2>' +
      ui.ul(['<a href="' + RBC.href('correct') + '">' + esc(t('act.correct')) + '</a> — ' + esc(t('join.care.correct')),
        '<a href="' + RBC.href('withdraw') + '">' + esc(t('act.withdraw')) + '</a> — ' + esc(t('join.care.withdraw')),
        '<a href="' + RBC.href('contact') + '">' + esc(t('nav.contact')) + '</a> — ' + esc(t('join.care.contact'))]) + '</section>' +
      '<section class="psec" aria-labelledby="j-ch"><h2 id="j-ch">' + esc(t('join.charter')) + '</h2><p>' + esc(t('join.charter_d')) + '</p>' +
      '<p>' + ui.btn(t('nav.charter'), { href: RBC.href('charter'), kind: 'secondary', icon: 'doc' }) + '</p></section></div>';
  };
})();
