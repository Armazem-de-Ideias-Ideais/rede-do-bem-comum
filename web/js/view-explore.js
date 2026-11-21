/* Explorar: busca sem acento, filtros (família, presença, país, selo de atividade), lista paginada e mapa por cidade. */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon, ui = RBC.ui;
  var PAGE = 18;
  var GROUP_LABEL = { fam: 'filters.fam', pres: 'filters.pres', country: 'filters.country', badge: 'filters.badge' };

  function options(g) {
    var D = RBC.data;
    if (g === 'fam') return RBC.FAMILIES.filter(function (f) { return D.fams[f]; }).map(function (f) { return [f, RBC.famLabel(f), f]; });
    if (g === 'pres') return RBC.PRESENCES.map(function (p) { return [p, t('pres.' + p)]; });
    if (g === 'badge') return RBC.BADGES.map(function (b) { return [b, t('badgef.' + b)]; });
    return Object.keys(D.countries).map(function (c) { return [c, RBC.countryName(c || null)]; })
      .sort(function (a, b) { return a[1].localeCompare(b[1], RBC.state.lang === 'pt' ? 'pt-BR' : 'en'); });
  }
  function optLabel(g, v) { var o = options(g).filter(function (x) { return x[0] === v; })[0]; return o ? o[1] : v; }

  var V = RBC.views.explore = { needsData: true };
  V.title = function () { return t('explore.title'); };
  V.render = function () {
    var x = RBC.exploreState();
    return '<div class="explore">' +
      ui.pageHead({ eyebrow: t('explore.eyebrow'), title: t('explore.title'), lead: t('explore.lead') }) +
      '<form class="searchbar searchbar--one" id="xsearch" role="search" aria-label="' + esc(t('search.form')) + '" novalidate>' +
      '<div class="searchbar__f"><label for="xq">' + esc(t('search.label')) + '</label><div class="inputic">' + icon('search') + '<input id="xq" name="q" type="search" autocomplete="off" value="' + esc(x.q) + '" aria-describedby="xq-hint"></div>' +
      '<p class="hint" id="xq-hint">' + esc(t('search.hint')) + '</p></div>' +
      '<div class="searchbar__go">' + ui.btn(t('search.btn'), { type: 'submit', icon: 'search' }) + '</div></form>' +
      '<div class="xbar">' +
      '<div class="seg" role="group" aria-label="' + esc(t('explore.mode')) + '">' +
      '<button type="button" data-mode="list" aria-pressed="' + (x.mode === 'list') + '">' + icon('list') + '<span>' + esc(t('view.list')) + '</span></button>' +
      '<button type="button" data-mode="map" aria-pressed="' + (x.mode === 'map') + '">' + icon('map') + '<span>' + esc(t('view.map')) + '</span></button></div>' +
      '<button type="button" class="btn btn--quiet btn--sm xfilters-btn" id="xfilters-btn" aria-expanded="' + (x.filtersOpen ? 'true' : 'false') + '" aria-controls="xfilters">' + icon('filter') + '<span id="xfilters-btn-l"></span></button>' +
      '<div class="xsort"><label for="xsort">' + esc(t('explore.sort')) + '</label><div class="selectwrap"><select id="xsort"></select>' + icon('chev-down') + '</div></div>' +
      '</div>' +
      '<div class="xlayout xlayout--' + x.mode + '" id="xlayout">' +
      '<aside class="xfilters' + (x.filtersOpen ? ' is-open' : '') + '" id="xfilters" aria-labelledby="xfilters-h"><div class="xfilters__head"><h2 id="xfilters-h">' + esc(t('filters.title')) + '</h2>' +
      '<button type="button" class="linkbtn" id="xclear">' + esc(t('filters.clear')) + '</button></div><div id="xgroups"></div>' +
      '<p class="xfilters__close"><button type="button" class="btn btn--primary btn--sm" id="xfilters-done">' + esc(t('filters.done')) + '</button></p></aside>' +
      '<section class="xresults" aria-labelledby="xres-h">' +
      '<div class="xhead"><h2 id="xres-h" tabindex="-1" class="xcount"></h2></div>' +
      '<p id="xmeta" class="xmeta"></p><div id="xchips"></div>' +
      '<div id="xbody"></div></section>' +
      '<div class="xmapcol" id="xmapcol"' + (x.mode === 'map' ? '' : ' hidden') + '>' +
      '<p class="mapnote">' + icon('ring') + '<span>' + esc(t('map.position_note')) + '</span></p>' +
      '<div class="mapbox"><div id="xmap" class="map"></div><div id="xmap-state" class="map__state" hidden></div></div>' +
      '<div id="xsel" class="xsel" aria-live="polite"></div>' + RBC.mapLegend() +
      '<p class="hint">' + esc(t('map.privacy')) + '</p></div>' +
      '</div><div id="xlive" class="sr" aria-live="polite" aria-atomic="true"></div></div>';
  };

  var ctl = null, root = null, last = null;

  V.mount = function (el) {
    root = el; var x = RBC.exploreState();
    var form = RBC.qs('#xsearch', el), q = RBC.qs('#xq', el);
    form.addEventListener('submit', function (ev) { ev.preventDefault(); x.q = q.value; x.page = 1; run({ announce: true, focusHead: true }); });
    q.addEventListener('input', RBC.debounce(function () { if (!root || x.q === q.value) return; x.q = q.value; x.page = 1; run({ announce: true }); }, 300));
    RBC.qsa('[data-mode]', el).forEach(function (b) { b.addEventListener('click', function () { setMode(b.getAttribute('data-mode')); }); });
    RBC.qs('#xfilters-btn', el).addEventListener('click', function () { toggleFilters(!x.filtersOpen); });
    RBC.qs('#xfilters-done', el).addEventListener('click', function () { toggleFilters(false); RBC.qs('#xfilters-btn', el).focus(); });
    RBC.qs('#xclear', el).addEventListener('click', function () { x.filters = RBC.emptyFilters(); x.page = 1; run({ announce: true }); });
    RBC.qs('#xsort', el).addEventListener('change', function (ev) { x.sort = ev.target.value; x.page = 1; run({ announce: true }); });
    el.addEventListener('change', function (ev) {
      var c = ev.target; if (!c.hasAttribute('data-g')) return;
      var g = c.getAttribute('data-g'), arr = x.filters[g], i = arr.indexOf(c.value);
      if (c.checked && i < 0) arr.push(c.value); if (!c.checked && i >= 0) arr.splice(i, 1);
      x.page = 1; run({ announce: true, keepFocus: c.id });
    });
    el.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-unset],[data-page],[data-clear-all],[data-sel-close],[data-show-list]'); if (!b) return;
      if (b.hasAttribute('data-unset')) { var p = b.getAttribute('data-unset').split(':'), arr = x.filters[p[0]], k = arr.indexOf(p.slice(1).join(':')); if (k >= 0) arr.splice(k, 1); x.page = 1; run({ announce: true, focusHead: true }); }
      else if (b.hasAttribute('data-page')) { x.page = +b.getAttribute('data-page'); run({ focusHead: true }); var hd = RBC.qs('#xres-h', el); if (hd && hd.scrollIntoView) hd.scrollIntoView({ block: 'start' }); }
      else if (b.hasAttribute('data-clear-all')) { x.filters = RBC.emptyFilters(); x.q = ''; q.value = ''; x.page = 1; run({ announce: true, focusHead: true }); }
      else if (b.hasAttribute('data-sel-close')) { x.sel = null; if (ctl) ctl.select(null); renderSel(); }
      else if (b.hasAttribute('data-show-list')) { setMode('list'); }
    });
    el.addEventListener('toggle', function (ev) { var d = ev.target; if (d.hasAttribute && d.hasAttribute('data-group')) x.open[d.getAttribute('data-group')] = d.open; }, true);
    run({});
    if (x.mode === 'map') startMap();
  };
  V.unmount = function () { if (ctl) ctl.destroy(); ctl = null; root = null; };

  function toggleFilters(open) {
    var x = RBC.exploreState(); x.filtersOpen = open;
    RBC.qs('#xfilters', root).classList.toggle('is-open', open);
    RBC.qs('#xfilters-btn', root).setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) { var f = RBC.qs('#xgroups summary', root); if (f) f.focus(); }
  }
  function setMode(m) {
    var x = RBC.exploreState(); if (x.mode === m) return; x.mode = m;
    RBC.qsa('[data-mode]', root).forEach(function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-mode') === m ? 'true' : 'false'); });
    RBC.qs('#xlayout', root).className = 'xlayout xlayout--' + m;
    RBC.qs('#xmapcol', root).hidden = m !== 'map';
    if (m === 'map') startMap(); else if (ctl) { ctl.destroy(); ctl = null; }
    RBC.announce(t(m === 'map' ? 'explore.mode_map_on' : 'explore.mode_list_on', { n: last ? last.items.length : 0 }));
  }

  function startMap() {
    var x = RBC.exploreState(), st = RBC.qs('#xmap-state', root), box = RBC.qs('#xmap', root);
    if (ctl) return;
    st.hidden = false; st.innerHTML = '<p class="loading__label" role="status"><span class="spinner" aria-hidden="true"></span>' + esc(t('map.loading')) + '</p>';
    ctl = RBC.createMap({
      el: box, cities: last ? last.cities : [], focusKey: x.sel,
      onSelect: function (k, initial) { x.sel = k; renderSel(!initial); },
      onError: function () {
        if (ctl) ctl.destroy(); ctl = null;
        st.hidden = false;
        st.innerHTML = ui.state('error', { h: 'h3', title: t('map.error.title'), text: t('map.error.text'), actions: ui.btn(t('state.retry'), { icon: 'refresh', small: true, attrs: 'data-map-retry' }) + ui.btn(t('map.error.list'), { kind: 'ghost', small: true, icon: 'list', attrs: 'data-show-list' }) });
        RBC.qs('[data-map-retry]', st).addEventListener('click', function () { startMap(); });
        RBC.announce(t('map.error.title'));
      }
    });
    var tick = window.setInterval(function () { if (!ctl || !root) { window.clearInterval(tick); return; } if (ctl.map && ctl.map.loaded()) { st.hidden = true; st.innerHTML = ''; window.clearInterval(tick); } }, 150);
    renderSel();
  }

  function renderSel(focus) {
    var x = RBC.exploreState(), box = RBC.qs('#xsel', root); if (!box) return;
    var c = x.sel && last ? last.cities.filter(function (k) { return k.key === x.sel; })[0] : null;
    if (!c) { box.innerHTML = '<p class="hint">' + esc(t('map.select_hint')) + '</p>'; return; }
    var ents = last.items.filter(function (e) { return e._cityKey === c.key; });
    box.innerHTML = '<div class="selcard"><div class="selcard__head"><h3 tabindex="-1" id="xsel-h">' + esc(c.city + ', ' + RBC.countryName(c.country)) + '</h3>' +
      '<button type="button" class="iconbtn" data-sel-close aria-label="' + esc(t('map.sel_close')) + '">' + icon('close') + '</button></div>' +
      '<p class="selcard__meta">' + icon('ring') + ' <span>' + esc(t('map.sel_meta', { n: ents.length })) + '</span></p>' +
      ui.cards(ents.slice(0, 30), { h: 'h4', cls: 'cards--one' }) +
      (ents.length > 30 ? '<p class="hint">' + esc(t('map.sel_more', { n: ents.length - 30 })) + '</p>' : '') + '</div>';
    if (focus) RBC.focusEl(RBC.qs('#xsel-h', box));
  }

  function sortOptions(x, hasQ) {
    var o = [['auto', t(hasQ ? 'sort.relevance' : 'sort.activity')], ['name', t('sort.name')]];
    if (hasQ) o.push(['activity', t('sort.activity')]);
    if (!hasQ && x.sort === 'relevance') x.sort = 'auto';
    return o.map(function (s) { return '<option value="' + s[0] + '"' + (x.sort === s[0] ? ' selected' : '') + '>' + esc(s[1]) + '</option>'; }).join('');
  }

  function run(o) {
    var x = RBC.exploreState(), el = root, res = RBC.search(x); last = res;
    /* o foco que estava num filtro sobrevive à nova renderização dos grupos */
    var act = document.activeElement, groupsEl = RBC.qs('#xgroups', el);
    if (!o.keepFocus && act && act.id && groupsEl && groupsEl.contains(act)) o.keepFocus = act.id;
    var pages = Math.max(1, Math.ceil(res.items.length / PAGE)); if (x.page > pages) x.page = pages; if (x.page < 1) x.page = 1;
    var nSel = RBC.FILTER_GROUPS.reduce(function (s, g) { return s + x.filters[g].length; }, 0);
    RBC.qs('#xfilters-btn-l', el).textContent = nSel ? t('filters.btn_n', { n: nSel }) : t('filters.btn');
    RBC.qs('#xsort', el).innerHTML = sortOptions(x, !!RBC.norm(x.q));
    RBC.qs('#xres-h', el).textContent = res.items.length === 1 ? t('explore.count.one') : t('explore.count', { n: RBC.num(res.items.length) });
    RBC.qs('#xmeta', el).textContent = res.items.length ? t('explore.meta', { cities: RBC.num(res.cities.length), onmap: RBC.num(res.items.length - res.noMap), nomap: RBC.num(res.noMap) }) : '';
    var chips = [];
    RBC.FILTER_GROUPS.forEach(function (g) { x.filters[g].forEach(function (v) { chips.push('<li><button type="button" class="chip chip--on" data-unset="' + g + ':' + esc(v) + '" aria-label="' + esc(t('filters.remove', { label: optLabel(g, v) })) + '"><span>' + esc(optLabel(g, v)) + '</span>' + icon('close') + '</button></li>'); }); });
    RBC.qs('#xchips', el).innerHTML = chips.length ? '<ul class="chips chips--applied" aria-label="' + esc(t('filters.applied')) + '">' + chips.join('') + '<li><button type="button" class="linkbtn" data-clear-all>' + esc(t('filters.clear_all')) + '</button></li></ul>' : '';
    RBC.qs('#xgroups', el).innerHTML = RBC.FILTER_GROUPS.map(function (g) {
      var sel = x.filters[g], c = res.facets[g];
      var opts = options(g).filter(function (op) { return g !== 'country' || c[op[0]] || sel.indexOf(op[0]) >= 0; }).map(function (op) {
        var id = 'xf-' + g + '-' + (op[0] || 'none'), n = c[op[0]] || 0, on = sel.indexOf(op[0]) >= 0;
        return '<li><label class="fopt' + (n || on ? '' : ' fopt--zero') + '" for="' + id + '"><input type="checkbox" id="' + id + '" data-g="' + g + '" value="' + esc(op[0]) + '"' + (on ? ' checked' : '') + '>' +
          (op[2] ? icon(op[2]) : '') + '<span class="fopt__l">' + esc(op[1]) + '</span><span class="fopt__n"><span class="sr">(</span>' + n + '<span class="sr"> ' + esc(t('filters.count_unit')) + ')</span></span></label></li>';
      }).join('');
      return '<details class="fgroup" data-group="' + g + '"' + (x.open[g] || sel.length ? ' open' : '') + '><summary><span>' + esc(t(GROUP_LABEL[g])) + '</span>' + (sel.length ? '<span class="badge">' + sel.length + '</span>' : '') + icon('chev-down') + '</summary>' +
        '<fieldset><legend class="sr">' + esc(t(GROUP_LABEL[g])) + '</legend><ul class="fopts' + (g === 'fam' ? ' fopts--fam' : '') + (g === 'country' ? ' fopts--scroll' : '') + '">' + opts + '</ul></fieldset></details>';
    }).join('');
    var body;
    if (!res.items.length) body = ui.state('noresults', { h: 'h3', title: t('empty.title'), text: t('empty.results'), actions: ui.btn(t('filters.clear_all'), { icon: 'refresh', attrs: 'data-clear-all', kind: 'secondary' }) });
    else { var start = (x.page - 1) * PAGE; body = ui.cards(res.items.slice(start, start + PAGE)) + ui.pager(x.page, pages); }
    RBC.qs('#xbody', el).innerHTML = body;
    if (ctl) { ctl.update(res.cities); if (x.sel && !res.cities.some(function (k) { return k.key === x.sel; })) x.sel = null; renderSel(); }
    if (o.keepFocus) { var k = document.getElementById(o.keepFocus); if (k) k.focus(); }
    if (o.focusHead) RBC.focusEl(RBC.qs('#xres-h', el));
    if (o.announce) { var lv = RBC.qs('#xlive', el); lv.textContent = ''; window.setTimeout(function () { if (root) lv.textContent = RBC.qs('#xres-h', el).textContent; }, 80); }
  }
})();
