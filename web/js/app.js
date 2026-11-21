/* Moldura (cabeçalho, rodapé), roteador, troca de idioma e inicialização. */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon, ui = RBC.ui;
  var chromeKey = '';
  RBC.db = RBC.adapters[RBC.cfg.mode] || RBC.adapters.static;

  function navItem(id, label, cur) { return '<li><a href="' + RBC.href(id) + '"' + (cur ? ' aria-current="page"' : '') + '>' + esc(label) + '</a></li>'; }
  var NAV_GROUP = { explore: 'explore', profile: 'explore', participate: 'participate', claim: 'participate', suggest: 'participate', offers: 'participate', connect: 'participate',
    about: 'about', charter: 'about', why: 'about', attribution: 'about', privacy: 'about', terms: 'about', contact: 'about', correct: 'about', withdraw: 'about', confirmWithdraw: 'about',
    login: 'space', mySpace: 'space', edit: 'space', moderation: 'space' };

  function renderChrome(routeId) {
    var s = RBC.state, group = NAV_GROUP[routeId] || routeId, auth = RBC.db.caps.auth;
    var key = [s.lang, s.menuOpen, group, !!s.session, auth].join('|');
    if (key === chromeKey) return; chromeKey = key;
    var active = document.activeElement && document.activeElement.id;
    document.getElementById('skip-link').textContent = t('a11y.skip');
    var brand = t('brand');
    document.getElementById('site-head').innerHTML =
      '<div class="site-head__in">' +
      '<a class="brand" href="' + RBC.href('home') + '"' + (routeId === 'home' ? ' aria-current="page"' : '') + '><img src="assets/logo-' + s.lang + '.png" width="640" height="213" alt="' + esc(brand) + ' — ' + esc(t('nav.home')) + '"></a>' +
      '<button type="button" class="menubtn" id="menubtn" aria-expanded="' + (s.menuOpen ? 'true' : 'false') + '" aria-controls="nav">' + icon(s.menuOpen ? 'close' : 'menu') + '<span>' + esc(t('nav.menu')) + '</span></button>' +
      '<nav id="nav" class="nav' + (s.menuOpen ? ' nav--open' : '') + '" aria-label="' + esc(t('nav.main')) + '"><ul>' +
      navItem('explore', t('nav.explore'), group === 'explore') + navItem('participate', t('nav.participate'), group === 'participate') +
      navItem('about', t('nav.about'), group === 'about') +
      (auth ? '<li class="nav__space"><a href="' + RBC.href(s.session ? 'mySpace' : 'login') + '"' + (group === 'space' ? ' aria-current="page"' : '') + '>' + icon('user') + esc(t(s.session ? 'nav.space' : 'nav.login')) + '</a></li>' : '') +
      '</ul></nav>' +
      '<div class="langsw" role="group" aria-label="' + esc(t('lang.label')) + '">' +
      '<button type="button" id="lang-pt" data-lang="pt" lang="pt" aria-pressed="' + (s.lang === 'pt') + '"><span aria-hidden="true">PT</span><span class="sr">Português</span></button>' +
      '<button type="button" id="lang-en" data-lang="en" lang="en" aria-pressed="' + (s.lang === 'en') + '"><span aria-hidden="true">EN</span><span class="sr">English</span></button>' +
      '</div></div>';
    document.getElementById('site-foot').innerHTML =
      '<div class="site-foot__in">' +
      '<div class="site-foot__brand"><img src="assets/simbolo.png" width="256" height="256" alt="" class="site-foot__symbol"><div><p class="site-foot__name">' + esc(brand) + '</p><p>' + esc(t('descriptor')) + '</p><p class="site-foot__motto">' + esc(t('foot.motto')) + '</p></div></div>' +
      '<nav aria-label="' + esc(t('foot.network')) + '"><h2>' + esc(t('foot.network')) + '</h2><ul>' +
      ['about', 'charter', 'why', 'attribution'].map(function (k) { return '<li><a href="' + RBC.href(k) + '">' + esc(t('nav.' + k)) + '</a></li>'; }).join('') + '</ul></nav>' +
      '<nav aria-label="' + esc(t('foot.care')) + '"><h2>' + esc(t('foot.care')) + '</h2><ul>' +
      [['contact', 'nav.contact'], ['suggest', 'suggest'], ['correct', 'act.correct'], ['withdraw', 'act.withdraw'], ['privacy', 'nav.privacy'], ['terms', 'nav.terms']].map(function (k) { return '<li><a href="' + RBC.href(k[0]) + '">' + esc(t(k[1])) + '</a></li>'; }).join('') + '</ul></nav>' +
      '<div class="site-foot__note"><p>' + esc(t('foot.licence')) + '</p><p>' + esc(t('foot.controllers')) + '</p>' +
      (RBC.db.name === 'static' ? '<p class="muted">' + esc(t('foot.static')) + '</p>' : '') + '</div></div>';
    if (active) { var el = document.getElementById(active); if (el && el !== document.activeElement && /^(lang-|menubtn)/.test(active)) el.focus(); }
  }

  RBC.render = function (opts) {
    opts = opts || {};
    var r = RBC.parse(window.location.hash), main = document.getElementById('main');
    if (RBC.current && RBC.current.view && RBC.current.view.unmount) { try { RBC.current.view.unmount(); } catch (e) { /* segue */ } }
    document.documentElement.lang = RBC.state.lang === 'pt' ? 'pt-BR' : 'en';
    renderChrome(r.id);
    var view = RBC.views[r.id] || RBC.views.notfound;
    if (view.needsData !== false && !RBC.data) {
      if (RBC.dataError) {
        main.innerHTML = '<div class="view view--narrow">' + ui.state('error', { h: 'h1', focus: true, title: t('state.error'), text: t('state.error_data'), actions: ui.btn(t('state.retry'), { icon: 'refresh', attrs: 'data-retry-data' }) + ui.btn(t('nav.about'), { kind: 'ghost', href: RBC.href('about') }) }) + '</div>';
        RBC.qs('[data-retry-data]', main).addEventListener('click', function () { RBC.boot(); });
      } else main.innerHTML = '<div class="view"><h1 id="page-title" tabindex="-1" class="sr">' + esc(t('state.loading')) + '</h1>' + ui.loading(6) + '</div>';
      RBC.current = { route: r, view: null };
      document.title = t('brand');
      return;
    }
    main.innerHTML = '<div class="view view--' + r.id + '">' + view.render(r) + '</div>';
    var root = main.firstChild;
    RBC.current = { route: r, view: view, root: root };
    if (view.mount) view.mount(root, r);
    var vt = view.title(r); document.title = vt === t('brand') ? vt : vt + ' · ' + t('brand');
    if (opts.focus) {
      window.scrollTo(0, 0);
      var h = document.getElementById('page-title') || main;
      try { h.focus({ preventScroll: true }); } catch (e) { h.focus(); }
    }
  };

  function setLang(l) {
    if (l === RBC.state.lang) return;
    var r = RBC.parse(window.location.hash);
    RBC.state.lang = l; RBC.store.set('lang', l);
    var target = r.id === 'notfound' ? window.location.hash : RBC.href(r.id, r.param);
    RBC._langSwitch = true;
    if (window.location.hash && window.location.hash !== target) { try { window.location.replace(target); } catch (e) { window.location.hash = target; } }
    else { RBC._langSwitch = false; RBC.render(); }
    var b = document.getElementById('lang-' + l); if (b) b.focus();
    RBC.announce(t('lang.changed'));
  }
  RBC.setLang = setLang;

  /* volta do link mágico: limpa ?code= da URL e retoma a intenção guardada */
  RBC.afterLogin = function () {
    try { if (window.location.search) window.history.replaceState(null, '', window.location.pathname + window.location.hash); } catch (e) { /* segue */ }
    var go = RBC.account && RBC.account.takeIntent();
    chromeKey = '';
    if (go && go !== window.location.hash) window.location.hash = go; else RBC.render({ focus: true });
  };

  window.addEventListener('hashchange', function () {
    RBC.state.menuOpen = false;
    if (RBC._langSwitch) { RBC._langSwitch = false; RBC.render(); var b = document.getElementById('lang-' + RBC.state.lang); if (b) b.focus(); }
    else RBC.render({ focus: true });
  });
  document.addEventListener('click', function (ev) {
    var el = ev.target.closest ? ev.target.closest('[data-lang],[data-skip],#menubtn,[data-fam-link],a[href="#"]') : null;
    if (!el) return;
    if (el.hasAttribute('data-lang')) { setLang(el.getAttribute('data-lang')); return; }
    if (el.hasAttribute('data-skip')) { ev.preventDefault(); var h = document.getElementById('page-title') || document.getElementById('main'); RBC.focusEl(h); h.scrollIntoView(); return; }
    if (el.id === 'menubtn') { RBC.state.menuOpen = !RBC.state.menuOpen; renderChrome(RBC.current ? RBC.current.route.id : 'home'); document.getElementById('menubtn').focus(); return; }
    if (el.hasAttribute('data-fam-link')) { var x = RBC.exploreState(); x.filters = RBC.emptyFilters(); x.filters.fam = [el.getAttribute('data-fam-link')]; x.q = ''; x.page = 1; x.sel = null; return; }
    if (el.getAttribute('href') === '#') ev.preventDefault();
  });
  document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape' && RBC.state.menuOpen) { RBC.state.menuOpen = false; renderChrome(RBC.current ? RBC.current.route.id : 'home'); var b = document.getElementById('menubtn'); if (b) b.focus(); } });
  document.addEventListener('submit', function (ev) { ev.preventDefault(); });

  /* Sem queda silenciosa para a base estática no modo supabase: ela poderia mostrar fichas já retiradas. */
  var initP = null;
  function boot() {
    RBC.dataError = null; RBC.render();
    if (!initP) { initP = RBC.db.init(); initP.catch(function () { initP = null; }); }
    initP.then(function () { return RBC.loadData(); }).then(function () { chromeKey = ''; RBC.render(); }, function (err) {
      if (window.console) console.warn('dados indisponíveis:', err && err.message);
      RBC.dataError = err || true; RBC.render();
    });
  }
  RBC.boot = boot;
  boot();
})();
