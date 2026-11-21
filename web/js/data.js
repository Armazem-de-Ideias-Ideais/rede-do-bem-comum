/* Camada de dados: vocabulário, adaptador "static" (data/public.json), índice, busca, filtros e iniciativas-irmãs.
   Os dois adaptadores (static e supabase) expõem a mesma interface:
     name, caps{auth,write}, init(), listInitiatives(), sources(); opcionais: getPage(slug), siblings(rec); e — só no supabase — as operações com conta.
   A busca, os filtros e os contadores rodam no cliente sobre a lista pública carregada (≈1.500 registros). */
(function () {
  'use strict';
  var RBC = window.RBC;

  RBC.FAMILIES = ['agroecology', 'food_solidarity', 'consumer_coops', 'worker_coops', 'solidarity_finance', 'housing_communities', 'autonomous_spaces',
    'mutual_aid', 'health_care', 'conflict_care', 'free_education', 'books_libraries', 'publishing_print', 'independent_media', 'arts_culture',
    'repair_reuse', 'libraries_things', 'gift_exchange', 'shared_mobility', 'commons_infrastructure', 'ecology_land', 'digital_commons',
    'community_connectivity', 'labour_organising'];
  RBC.KINDS = ['cooperative', 'collective', 'network', 'community', 'organization', 'library', 'bookshop', 'publisher', 'movement', 'archive', 'resource', 'school'];
  RBC.PRESENCES = ['physical', 'territorial', 'hybrid', 'online', 'nonspatial'];
  RBC.BADGES = ['active_recent', 'source_checked', 'to_confirm'];
  RBC.FILTER_GROUPS = ['fam', 'pres', 'country', 'badge'];
  RBC.emptyFilters = function () { return { fam: [], pres: [], country: [], badge: [] }; };
  /* lista branca: o cliente descarta qualquer campo fora dela, venha de onde vier */
  RBC.PUBLIC_FIELDS = ['id', 'slug', 'name', 'aliases', 'kind', 'presence', 'country', 'city', 'region', 'categories', 'summary_pt', 'summary_en',
    'summary_en_status', 'own_url', 'source_url', 'source_name', 'activity_badge', 'last_activity', 'city_lat', 'city_lng', 'location_precision', 'licence_note'];
  RBC.PUBLIC_EXTRAS = ['is_managed', 'has_offers', 'area_id']; // vêm só da API (entity_list)

  /* ---------- nomes de países via Intl (sem tabela própria) ---------- */
  var dn = {};
  RBC.countryName = function (cc, lang) {
    lang = lang || RBC.state.lang;
    if (!cc) return RBC.t('country.none');
    try { if (!dn[lang]) dn[lang] = new Intl.DisplayNames([lang === 'pt' ? 'pt-BR' : 'en'], { type: 'region' }); return dn[lang].of(cc) || cc; } catch (e) { return cc; }
  };
  RBC.famLabel = function (id) { return RBC.t('fam.' + id); };
  RBC.where = function (e, long) {
    var c = RBC.countryName(e.country);
    if (e.city) return e.city + ', ' + c;
    return long ? c + ' · ' + RBC.t('where.no_city') : c;
  };

  /* ---------- adaptador static ---------- */
  RBC.adapters = RBC.adapters || {};
  RBC.adapters.static = {
    name: 'static',
    caps: { auth: false, write: false },
    init: function () { return Promise.resolve(); },
    listInitiatives: function () {
      return window.fetch('data/public.json', { cache: 'no-cache' }).then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status); return r.json();
      }).then(function (d) { RBC.dataMeta = d.meta || {}; return d.initiatives || []; });
    },
    sources: function () { return Promise.resolve(RBC.computeSources()); },
    /* sem backend: nenhuma gravação é simulada; as telas consultam caps antes e mostram "em breve" */
    call: function () { var e = new Error('indisponível no modo static'); e.code = 'unavailable'; return Promise.reject(e); },
    offersFeed: function () { return Promise.resolve([]); },
    signIn: function () { return this.call(); }, signOut: function () { return Promise.resolve(); }
  };

  /* ---------- índice ---------- */
  function clean(r) {
    var o = {}; RBC.PUBLIC_FIELDS.concat(RBC.PUBLIC_EXTRAS).forEach(function (k) { o[k] = r[k] == null ? null : r[k]; });
    o.aliases = o.aliases || []; o.categories = (o.categories || []).filter(function (c) { return RBC.FAMILIES.indexOf(c) >= 0; });
    if (o.location_precision !== 'city' || o.city_lat == null || o.city_lng == null) { o.city_lat = o.city_lng = null; o.location_precision = 'none'; }
    return o;
  }
  function index(list) {
    var D = { items: [], bySlug: {}, byId: {}, cities: {}, countries: {}, kinds: {}, fams: {} };
    list.forEach(function (raw) {
      if (!raw || !raw.slug || !/^[a-z0-9-]+$/.test(raw.slug)) return;
      var e = clean(raw);
      e._cityKey = e.city_lat != null ? (e.area_id || (e.country || '-') + '|' + Number(e.city_lat).toFixed(3) + '|' + Number(e.city_lng).toFixed(3)) : null;
      e._placeKey = e.city ? (e.country || '-') + '|' + RBC.norm(e.city) : null;
      e._rank = e.activity_badge === 'active_recent' ? 0 : e.activity_badge === 'source_checked' ? 1 : 2;
      var hay = [e.name].concat(e.aliases, [e.city, e.region, e.country, RBC.countryName(e.country, 'pt'), RBC.countryName(e.country, 'en'), e.summary_pt, e.summary_en, e.source_name]);
      e.categories.forEach(function (c) { hay.push(RBC.I18N.pt['fam.' + c], RBC.I18N.en['fam.' + c]); D.fams[c] = (D.fams[c] || 0) + 1; });
      hay.push(RBC.I18N.pt['kind.' + e.kind], RBC.I18N.en['kind.' + e.kind]);
      e._hay = ' ' + RBC.norm(hay.filter(Boolean).join(' ')) + ' ';
      e._name = ' ' + RBC.norm([e.name].concat(e.aliases).join(' ')) + ' ';
      D.items.push(e); D.bySlug[e.slug] = e; D.byId[e.id] = e;
      D.kinds[e.kind] = (D.kinds[e.kind] || 0) + 1;
      D.countries[e.country || ''] = (D.countries[e.country || ''] || 0) + 1;
      if (e._cityKey) {
        var c = D.cities[e._cityKey] || (D.cities[e._cityKey] = { key: e._cityKey, city: e.city, country: e.country, lat: +e.city_lat, lng: +e.city_lng, n: 0 });
        c.n++;
      }
    });
    D.counts = {
      total: D.items.length, countries: Object.keys(D.countries).filter(Boolean).length, cities: Object.keys(D.cities).length,
      active: D.items.filter(function (e) { return e.activity_badge === 'active_recent'; }).length,
      noMap: D.items.filter(function (e) { return !e._cityKey; }).length
    };
    return D;
  }
  RBC._index = index;

  var loading = null;
  RBC.loadData = function () {
    if (RBC.data) return Promise.resolve(RBC.data);
    if (!loading) {
      loading = RBC.db.listInitiatives().then(function (list) { RBC.data = index(list); RBC.dataError = null; return RBC.data; });
      loading.catch(function (err) { loading = null; RBC.dataError = err || true; if (window.console) console.warn('dados:', err && err.message); });
    }
    return loading;
  };
  RBC.reloadData = function () { loading = null; var keep = RBC.data; RBC.data = null; return RBC.loadData().then(null, function (e) { RBC.data = keep; return keep; }); };
  /* depois de uma retirada feita pela própria gestora (login): some na hora de lista, mapa, busca e contadores deste navegador */
  RBC.dropLocal = function (slug) {
    if (!RBC.data) return;
    RBC.data = index(RBC.data.items.filter(function (e) { return e.slug !== slug; }));
  };

  /* ---------- busca e filtros ---------- */
  RBC.exploreState = function () {
    if (!RBC.state.explore) RBC.state.explore = { q: '', filters: RBC.emptyFilters(), page: 1, mode: 'list', sort: 'auto', sel: null, filtersOpen: false, open: {} };
    return RBC.state.explore;
  };
  function val(e, g) { return g === 'fam' ? e.categories : g === 'pres' ? [e.presence] : g === 'country' ? [e.country || ''] : [e.activity_badge]; }
  function passes(e, f, skip) {
    for (var i = 0; i < RBC.FILTER_GROUPS.length; i++) {
      var g = RBC.FILTER_GROUPS[i]; if (g === skip || !f[g].length) continue;
      var v = val(e, g), ok = false;
      for (var j = 0; j < v.length; j++) if (f[g].indexOf(v[j]) >= 0) { ok = true; break; }
      if (!ok) return false;
    }
    return true;
  }
  RBC.search = function (x) {
    var D = RBC.data, toks = RBC.norm(x.q).split(' ').filter(Boolean);
    var base = D.items.filter(function (e) { for (var i = 0; i < toks.length; i++) if (e._hay.indexOf(toks[i]) < 0) return false; return true; });
    var facets = {};
    RBC.FILTER_GROUPS.forEach(function (g) {
      var c = facets[g] = {};
      base.forEach(function (e) { if (passes(e, x.filters, g)) val(e, g).forEach(function (v) { c[v] = (c[v] || 0) + 1; }); });
    });
    var items = base.filter(function (e) { return passes(e, x.filters); });
    var sort = x.sort === 'auto' ? (toks.length ? 'relevance' : 'activity') : x.sort;
    var score = function (e) {
      var s = 0, q = ' ' + toks.join(' ') + ' ';
      if (toks.length && e._name.indexOf(q) >= 0) s += 10;
      toks.forEach(function (tk) { if (e._name.indexOf(' ' + tk) >= 0) s += 3; else if (e._name.indexOf(tk) >= 0) s += 2; });
      return s;
    };
    var byName = function (a, b) { return a.name.localeCompare(b.name, RBC.state.lang === 'pt' ? 'pt-BR' : 'en', { sensitivity: 'base' }); };
    var byAct = function (a, b) { return a._rank - b._rank || String(b.last_activity || '').localeCompare(String(a.last_activity || '')) || byName(a, b); };
    if (sort === 'relevance') { items.forEach(function (e) { e._s = score(e); }); items.sort(function (a, b) { return b._s - a._s || byAct(a, b); }); }
    else if (sort === 'name') items.sort(byName);
    else items.sort(byAct);
    var cities = {}, noMap = 0;
    items.forEach(function (e) {
      if (!e._cityKey) { noMap++; return; }
      var c = cities[e._cityKey] || (cities[e._cityKey] = { key: e._cityKey, city: e.city, country: e.country, lat: +e.city_lat, lng: +e.city_lng, n: 0 });
      c.n++;
    });
    return { items: items, facets: facets, cities: Object.keys(cities).map(function (k) { return cities[k]; }), noMap: noMap, sort: sort };
  };

  /* ---------- iniciativas-irmãs (cálculo no cliente; mesma regra de api.sister_initiatives) ----------
     (1) same: compartilha >= 1 família e está em outro país; (2) comp: mesma cidade e nenhuma família em comum.
     Ordem: mais famílias em comum, depois "ativa", depois pseudoaleatória estável por ficha. Sem cidade, sem grupo (2). */
  function h(s) { var x = 0; for (var i = 0; i < s.length; i++) x = (x * 31 + s.charCodeAt(i)) | 0; return x; }
  RBC.computeSiblings = function (rec, n) {
    n = n || 6; var mine = rec.categories, same = [], comp = [];
    RBC.data.items.forEach(function (e) {
      if (e.id === rec.id) return;
      var shared = e.categories.filter(function (c) { return mine.indexOf(c) >= 0; }).length;
      var act = e.activity_badge === 'active_recent' ? 1 : 0, tie = h(rec.id + '|' + e.id);
      if (shared && e.country && e.country !== rec.country) same.push({ e: e, s: shared, a: act, t: tie });
      if (!shared && rec.city && ((rec._cityKey && e._cityKey === rec._cityKey) || (rec._placeKey && e._placeKey === rec._placeKey))) comp.push({ e: e, s: 0, a: act, t: tie });
    });
    var srt = function (a, b) { return b.s - a.s || b.a - a.a || a.t - b.t; };
    same.sort(srt); comp.sort(srt);
    return { same: same.slice(0, n).map(function (x) { return x.e; }), comp: comp.slice(0, n).map(function (x) { return x.e; }) };
  };

  /* ---------- fontes (página de atribuição) ---------- */
  RBC.computeSources = function () {
    var by = {};
    RBC.data.items.forEach(function (e) {
      var k = e.source_name || '—', s = by[k] || (by[k] = { name: k, n: 0, licence: {} });
      s.n++; if (e.licence_note) s.licence[e.licence_note] = 1;
    });
    return Object.keys(by).map(function (k) { var s = by[k]; s.licence = Object.keys(s.licence); return s; })
      .sort(function (a, b) { return b.n - a.n || a.name.localeCompare(b.name); });
  };
})();
