/* Ficha pública: /#i-<slug>. Selo de atividade, resumo PT e EN (com estado da tradução), fonte e atribuição,
   iniciativas-irmãs, ofertas e necessidades, e as ações "É sua? Reivindique", "Corrigir" e "Retirar do mapa". */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon, ui = RBC.ui;

  var V = RBC.views.profile = { needsData: true };
  V.title = function (r) { var e = RBC.data && RBC.data.bySlug[r.param]; return e ? e.name : t('profile.unavailable'); };

  function trBlock(kind, label, text, lang) {
    return '<div class="tr tr--' + kind + '"><p class="tr__label">' + icon(kind === 'auto' ? 'translate' : 'doc') + '<span>' + esc(label) + '</span></p><p class="tr__text" lang="' + lang + '">' + esc(text) + '</p></div>';
  }
  function summaries(e) {
    var pt = e.summary_pt ? trBlock('orig', t('profile.summary_pt'), e.summary_pt, 'pt') : '';
    var enLabel = e.summary_en_status === 'human' ? t('profile.summary_en_reviewed') : t('profile.summary_en_machine');
    var en = e.summary_en ? trBlock(e.summary_en_status === 'human' ? 'orig' : 'auto', enLabel, e.summary_en, 'en') : trBlock('none', t('profile.summary_en_none'), '—', RBC.state.lang);
    return RBC.state.lang === 'en' ? en + pt : pt + en;
  }

  V.render = function (r) {
    var e = RBC.data.bySlug[r.param];
    if (!e) {
      return '<div class="view--narrow"><p class="page-head__back"><a class="backlink" href="' + RBC.href('explore') + '">' + icon('arrow-left') + '<span>' + esc(t('profile.back')) + '</span></a></p>' +
        '<div id="pmissing">' + (RBC.db.getPage && RBC.db.name === 'supabase' ? ui.loading(1) + '<h1 id="page-title" tabindex="-1" class="sr">' + esc(t('state.loading')) + '</h1>' :
        ui.state('hidden', { h: 'h1', focus: true, title: t('profile.unavailable'), text: t('profile.unavailable_text'), actions: ui.btn(t('profile.back'), { href: RBC.href('explore'), icon: 'arrow-left', kind: 'secondary' }) })) + '</div></div>';
    }
    var main = e.categories[0] || 'sprout';
    var aliases = e.aliases && e.aliases.length ? '<p class="muted">' + esc(t('profile.aliases')) + ' ' + e.aliases.map(esc).join(' · ') + '</p>' : '';
    var where = e.city ? RBC.where(e) : RBC.where(e, true);
    var canAct = RBC.db.caps.write;
    return '<article class="profile" aria-labelledby="page-title">' +
      '<p class="page-head__back"><a class="backlink" href="' + RBC.href('explore') + '">' + icon('arrow-left') + '<span>' + esc(t('profile.back')) + '</span></a></p>' +
      '<header class="phead"><div class="phead__badge blob blob--' + (e.name.length % 4) + '" aria-hidden="true">' + icon(main) + '</div><div>' +
      '<p class="eyebrow">' + esc(t('kind.' + e.kind)) + ' · ' + esc(t('pres.' + e.presence)) + '</p>' +
      '<h1 id="page-title" tabindex="-1" class="phead__name">' + esc(e.name) + '</h1>' + aliases +
      '<p class="phead__where">' + icon(e.city_lat != null ? 'pin' : 'globe') + '<span>' + esc(where) + '</span></p>' +
      '<ul class="stamps" aria-label="' + esc(t('badge.group')) + '"><li>' + ui.badge(e) + '</li>' + (e.is_managed ? '<li>' + ui.stamp('managed', t('profile.managed')) + '</li>' : '') + '</ul>' +
      /* atalhos no celular: as ações ficam ao alcance sem rolar até o fim da ficha */
      '<ul class="pquick" aria-label="' + esc(t('profile.actions')) + '"><li><a href="' + RBC.href('claim', e.slug) + '">' + esc(t('act.claim')) + '</a></li><li><a href="' + RBC.href('correct', e.slug) + '">' + esc(t('act.correct')) + '</a></li><li><a href="' + RBC.href('withdraw', e.slug) + '">' + esc(t('act.withdraw')) + '</a></li></ul></div></header>' +
      '<div class="pgrid"><div class="pgrid__main">' +
      '<section class="psec" aria-labelledby="p-about"><h2 id="p-about">' + esc(t('profile.about')) + '</h2>' + summaries(e) + '</section>' +
      '<section class="psec" aria-labelledby="p-fams"><h2 id="p-fams">' + esc(t('profile.families')) + '</h2><ul class="chips">' + e.categories.map(function (f) { return '<li>' + ui.famChip(f, true) + '</li>'; }).join('') + '</ul></section>' +
      '<section class="psec" aria-labelledby="p-offers"><h2 id="p-offers">' + esc(t('profile.offers')) + '</h2><div id="poffers">' + ui.loading(1) + '</div></section>' +
      '<section class="psec" aria-labelledby="p-sis"><h2 id="p-sis">' + esc(t('profile.siblings')) + '</h2><p class="hint">' + esc(t('profile.siblings_hint')) + '</p><div id="psis">' + ui.loading(2) + '</div></section>' +
      '</div><aside class="pgrid__side" aria-label="' + esc(t('profile.side')) + '">' +
      '<section class="psec psec--actions" aria-labelledby="p-act"><h2 id="p-act">' + esc(t('profile.actions')) + '</h2>' +
      '<ul class="actlist">' +
      '<li>' + ui.btn(t('act.claim'), { href: RBC.href('claim', e.slug), icon: 'key' }) + '</li>' +
      (canAct ? '<li>' + ui.btn(t('act.connect'), { href: RBC.href('connect', e.slug), icon: 'people', kind: 'secondary' }) + '</li>' : '') +
      '<li>' + ui.btn(t('act.correct'), { href: RBC.href('correct', e.slug), icon: 'edit', kind: 'secondary' }) + '</li>' +
      '<li>' + ui.btn(t('act.withdraw'), { href: RBC.href('withdraw', e.slug), icon: 'eye-off', kind: 'ghost' }) + '</li></ul>' +
      '<p class="hint">' + esc(t('profile.withdraw_hint')) + '</p>' +
      '<p><a href="' + RBC.href('why') + '">' + esc(t('profile.why')) + '</a></p></section>' +
      '<section class="psec" aria-labelledby="p-web"><h2 id="p-web">' + esc(t('profile.web')) + '</h2>' +
      (e.own_url ? ui.dl([[t('profile.own_site'), ui.extLink(e.own_url)]]) : '<p class="muted">' + esc(t('profile.no_site')) + '</p>') + '</section>' +
      '<section class="psec" aria-labelledby="p-where"><h2 id="p-where">' + esc(t('profile.where')) + '</h2>' +
      ui.dl([[t('profile.presence'), esc(t('pres.' + e.presence)) + '<br><span class="muted">' + esc(t('presd.' + e.presence)) + '</span>'],
        [t('profile.map_pos'), ui.precision(e) + (e.city_lat != null ? '<br><span class="muted">' + esc(t('profile.map_pos_city', { city: e.city || '' })) + '</span>' : '')]]) +
      (e._cityKey ? '<p>' + ui.btn(t('profile.see_map'), { href: RBC.href('explore'), icon: 'map', kind: 'quiet', small: true, attrs: 'data-see-map' }) + '</p>' : '') + '</section>' +
      '<section class="psec" aria-labelledby="p-src"><h2 id="p-src">' + esc(t('profile.source')) + '</h2><div id="psrc">' + sourceBlock(e, null) + '</div></section>' +
      '</aside></div></article>';
  };

  function sourceBlock(e, page) {
    var srcs = page && page.sources ? page.sources : (e.source_url ? [{ name: e.source_name, url: e.source_url, accessed_at: null, licence: null }] : []);
    var attr = page ? page.attribution : e.licence_note;
    var rows = srcs.map(function (s) {
      return '<li>' + (RBC.safeUrl(s.url) ? ui.extLink(s.url, s.name || s.url) : esc(s.name || '')) + (s.accessed_at ? ' <span class="muted">· ' + esc(t('profile.accessed', { date: RBC.fmtMonthShort(String(s.accessed_at).slice(0, 7)) })) + '</span>' : '') + (s.licence ? ' <span class="muted">· ' + esc(s.licence) + '</span>' : '') + '</li>';
    });
    return (rows.length ? '<ul class="bullets">' + rows.join('') + '</ul>' : '<p class="muted">' + esc(t('profile.no_source')) + '</p>') +
      (attr ? '<p class="attrnote" lang="pt">' + icon('source') + '<span>' + esc(attr) + '</span></p>' + (RBC.state.lang === 'en' ? '<p class="hint">' + esc(t('profile.kvm_en')) + '</p>' : '') : '') +
      '<p class="hint">' + esc(t('profile.licence')) + ' <a href="' + RBC.href('attribution') + '">' + esc(t('nav.attribution')) + '</a>.</p>';
  }

  function offersBlock(list) {
    if (list === null) return '<p class="muted">' + esc(t('profile.offers_soon')) + '</p>';
    if (!list.length) return '<p class="muted">' + esc(t('profile.offers_none')) + '</p>';
    return '<ul class="cooplist">' + list.map(function (o) {
      return '<li class="coop coop--' + (o.kind === 'offer' ? 'offer' : 'need') + '"><p class="eyebrow">' + esc(t('offer.kind.' + o.kind)) + ' · ' + esc(t('offer.topic.' + o.topic)) + '</p>' +
        '<h3 class="h4">' + esc(o.title) + '</h3>' + (o.description ? '<p>' + esc(o.description) + '</p>' : '') +
        '<p class="hint">' + esc(t('offer.until', { date: RBC.fmtDate(o.valid_until) })) + '</p></li>';
    }).join('') + '</ul>';
  }
  RBC.offersBlock = offersBlock;

  function sibBlock(s) {
    var out = '<h3 class="h4">' + esc(t('profile.sib_same')) + '</h3>' + (s.same.length ? ui.cards(s.same, { h: 'h4', cls: 'cards--sib' }) : '<p class="muted">' + esc(t('profile.sib_none')) + '</p>');
    out += '<h3 class="h4">' + esc(t('profile.sib_comp')) + '</h3>' + (s.comp.length ? ui.cards(s.comp, { h: 'h4', cls: 'cards--sib' }) : '<p class="muted">' + esc(t(s.noCity ? 'profile.sib_nocity' : 'profile.sib_none')) + '</p>');
    return out;
  }

  var token = 0;
  V.mount = function (el, r) {
    var my = ++token, e = RBC.data.bySlug[r.param];
    if (!e) {
      if (RBC.db.name !== 'supabase' || !RBC.db.getPage) return;
      RBC.db.getPage(r.param).then(function (page) {
        if (my !== token) return;
        if (page && page.canonical_slug && page.canonical_slug !== r.param && RBC.data.bySlug[page.canonical_slug]) {
          try { window.history.replaceState(null, '', '#i-' + page.canonical_slug); } catch (er) { /* segue */ }
          RBC.render({ focus: true }); return;
        }
        var box = RBC.qs('#pmissing', el); if (!box) return;
        box.innerHTML = ui.state('hidden', { h: 'h1', focus: true, title: t('profile.unavailable'), text: t('profile.unavailable_text'), actions: ui.btn(t('profile.back'), { href: RBC.href('explore'), icon: 'arrow-left', kind: 'secondary' }) });
        document.title = t('profile.unavailable') + ' · ' + t('brand');
      }, function () { var box = RBC.qs('#pmissing', el); if (box && my === token) box.innerHTML = ui.state('error', { h: 'h1', focus: true, title: t('state.error'), text: t('state.error_text') }); });
      return;
    }
    var see = RBC.qs('[data-see-map]', el);
    if (see) see.addEventListener('click', function () { var x = RBC.exploreState(); x.q = ''; x.filters = RBC.emptyFilters(); x.mode = 'map'; x.sel = e._cityKey; x.page = 1; });
    // irmãs
    var sib = RBC.db.siblings ? RBC.db.siblings(e) : Promise.resolve(RBC.computeSiblings(e));
    sib.then(function (s) { if (my !== token) return; s.noCity = !e.city; var b = RBC.qs('#psis', el); if (b) b.innerHTML = sibBlock(s); },
      function () { var b = RBC.qs('#psis', el); if (b && my === token) b.innerHTML = '<p class="muted">' + esc(t('state.error_text')) + '</p>'; });
    // detalhes (ofertas, fontes completas)
    var pg = RBC.db.getPage ? RBC.db.getPage(e.slug) : Promise.resolve(null);
    pg.then(function (page) {
      if (my !== token) return;
      var o = RBC.qs('#poffers', el); if (o) o.innerHTML = offersBlock(page ? page.offers_needs : null);
      if (page && (page.sources || page.attribution)) { var s = RBC.qs('#psrc', el); if (s) s.innerHTML = sourceBlock(e, page); }
    }, function () { var o = RBC.qs('#poffers', el); if (o && my === token) o.innerHTML = offersBlock(null); });
  };
  V.unmount = function () { token++; };
})();
