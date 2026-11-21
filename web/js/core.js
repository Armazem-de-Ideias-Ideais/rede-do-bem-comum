/* Rede do Bem Comum · Common Good Network — site público (Fase 1)
   Núcleo: configuração, estado, idioma, armazenamento tolerante a falhas, rotas por #nome e utilitários. */
(function () {
  'use strict';
  var cfg = window.RBC_CONFIG || {};
  var RBC = window.RBC = { views: {}, I18N: { pt: {}, en: {} }, state: {}, data: null };
  RBC.cfg = {
    mode: cfg.MODE === 'supabase' && cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY ? 'supabase' : 'static',
    wantedMode: cfg.MODE || 'static',
    supabaseUrl: cfg.SUPABASE_URL || '', supabaseKey: cfg.SUPABASE_ANON_KEY || '',
    siteUrl: cfg.SITE_URL || (window.location.origin + window.location.pathname.replace(/index\.html$/, ''))
  };

  /* ---------- armazenamento local (pode faltar ou lançar erro) ---------- */
  RBC.store = {
    get: function (k) { try { var v = window.localStorage.getItem('rbc.' + k); return v == null ? null : JSON.parse(v); } catch (e) { return null; } },
    set: function (k, v) { try { window.localStorage.setItem('rbc.' + k, JSON.stringify(v)); return true; } catch (e) { return false; } },
    del: function (k) { try { window.localStorage.removeItem('rbc.' + k); return true; } catch (e) { return false; } }
  };

  /* ---------- estado ---------- */
  var storedLang = RBC.store.get('lang');
  var navLang = (navigator.language || 'pt').toLowerCase();
  RBC.state = {
    lang: storedLang === 'pt' || storedLang === 'en' ? storedLang : (navLang.indexOf('en') === 0 ? 'en' : 'pt'),
    explore: null, menuOpen: false, session: null, forms: {}
  };

  /* ---------- texto ---------- */
  RBC.t = function (key, vars) {
    var d = RBC.I18N[RBC.state.lang], s = d[key];
    if (s == null) { s = RBC.I18N.pt[key]; if (s == null) { if (window.console) console.warn('i18n: chave ausente', key); return key; } }
    if (vars && typeof s === 'string') s = s.replace(/\{(\w+)\}/g, function (m, k) { return vars[k] != null ? vars[k] : m; });
    return s;
  };
  var ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  RBC.esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return ESC[c]; }); };
  RBC.norm = function (s) { return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[’'`´]/g, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim(); };
  RBC.safeUrl = function (u) { return /^https?:\/\/[^\s"'<>]+$/i.test(String(u || '')) ? u : null; };

  var MONTHS = {
    pt: { s: ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'], l: ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'] },
    en: { s: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], l: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'] }
  };
  /* "2026-11" -> "nov/2026" (pt) ou "Nov 2026" (en) */
  RBC.fmtMonthShort = function (ym) {
    if (!ym) return ''; var p = String(ym).split('-'); if (!p[1]) return p[0];
    var m = MONTHS[RBC.state.lang].s[+p[1] - 1]; return RBC.state.lang === 'pt' ? m + '/' + p[0] : m + ' ' + p[0];
  };
  RBC.fmtDateTime = function (iso) {
    if (!iso) return ''; var d = new Date(iso); if (isNaN(d)) return '';
    try { return d.toLocaleString(RBC.state.lang === 'pt' ? 'pt-BR' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' }); } catch (e) { return d.toISOString().slice(0, 16).replace('T', ' '); }
  };
  RBC.fmtDate = function (iso) {
    if (!iso) return ''; var d = new Date(iso); if (isNaN(d)) return String(iso);
    try { return d.toLocaleDateString(RBC.state.lang === 'pt' ? 'pt-BR' : 'en-GB', { dateStyle: 'medium' }); } catch (e) { return String(iso).slice(0, 10); }
  };
  RBC.num = function (n) { try { return Number(n).toLocaleString(RBC.state.lang === 'pt' ? 'pt-BR' : 'en-GB'); } catch (e) { return String(n); } };

  /* ---------- rotas: somente #nome simples (letras ASCII, dígitos e hífens) ----------
     A ficha usa #i-<slug> nas duas línguas (endereço estável para compartilhar). */
  RBC.routes = [
    { id: 'home', pt: 'inicio', en: 'home' },
    { id: 'explore', pt: 'explorar', en: 'explore' },
    { id: 'profile', pt: 'i', en: 'i', param: true, paramOnly: true },
    { id: 'participate', pt: 'participar', en: 'take-part' },
    { id: 'about', pt: 'sobre', en: 'about' },
    { id: 'privacy', pt: 'privacidade', en: 'privacy' },
    { id: 'terms', pt: 'termos', en: 'terms' },
    { id: 'attribution', pt: 'atribuicao', en: 'attribution' },
    { id: 'charter', pt: 'carta-de-convivencia', en: 'community-charter' },
    { id: 'why', pt: 'por-que-estou-aqui', en: 'why-am-i-here' },
    { id: 'contact', pt: 'contato', en: 'contact' },
    { id: 'suggest', pt: 'indicar', en: 'suggest' },
    { id: 'withdraw', pt: 'retirar', en: 'withdraw', param: true },
    { id: 'correct', pt: 'corrigir', en: 'correct', param: true },
    { id: 'claim', pt: 'reivindicar', en: 'claim', param: true },
    { id: 'connect', pt: 'conectar', en: 'connect', param: true },
    { id: 'edit', pt: 'editar', en: 'edit', param: true },
    { id: 'login', pt: 'entrar', en: 'sign-in' },
    { id: 'mySpace', pt: 'meu-espaco', en: 'my-space' },
    { id: 'offers', pt: 'ofertas-e-necessidades', en: 'offers-and-needs', param: true },
    { id: 'moderation', pt: 'painel-editorial', en: 'editorial-panel' },
    { id: 'invite', pt: 'convite', en: 'invite', param: true, paramOnly: true }
  ];
  RBC.routeById = {}; RBC.routes.forEach(function (r) { RBC.routeById[r.id] = r; });
  RBC.href = function (id, param) { var r = RBC.routeById[id]; return '#' + r[RBC.state.lang] + (param ? '-' + param : ''); };
  RBC.parse = function (hash) {
    var h = String(hash || '').replace(/^#/, '').toLowerCase();
    if (!h) return { id: 'home', param: null };
    if (!/^[a-z0-9-]+$/.test(h)) return { id: 'notfound', param: null };
    var i, r;
    for (i = 0; i < RBC.routes.length; i++) { r = RBC.routes[i]; if (!r.paramOnly && (h === r.pt || h === r.en)) return { id: r.id, param: null }; }
    var best = null;
    for (i = 0; i < RBC.routes.length; i++) {
      r = RBC.routes[i]; if (!r.param) continue;
      ['pt', 'en'].forEach(function (L) { if (h.indexOf(r[L] + '-') === 0 && h.length > r[L].length + 1 && (!best || r[L].length > best.len)) best = { id: r.id, param: h.slice(r[L].length + 1), len: r[L].length }; });
    }
    return best ? { id: best.id, param: best.param } : { id: 'notfound', param: null };
  };
  RBC.go = function (id, param) { var h = RBC.href(id, param); if (window.location.hash === h) RBC.render({ focus: true }); else window.location.hash = h; };

  /* ---------- região viva para leitores de tela ---------- */
  var liveTimer = null;
  RBC.announce = function (msg) {
    var el = document.getElementById('live'); if (!el) return;
    window.clearTimeout(liveTimer); el.textContent = '';
    liveTimer = window.setTimeout(function () { el.textContent = msg; }, 60);
  };

  RBC.reducedMotion = function () { try { return window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; } };
  RBC.debounce = function (fn, ms) { var tm; return function () { var a = arguments, c = this; window.clearTimeout(tm); tm = window.setTimeout(function () { fn.apply(c, a); }, ms); }; };
  RBC.qs = function (sel, root) { return (root || document).querySelector(sel); };
  RBC.qsa = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };
  RBC.focusEl = function (el) { if (!el) return; if (!el.hasAttribute('tabindex') && !/^(A|BUTTON|INPUT|SELECT|TEXTAREA|SUMMARY)$/.test(el.tagName)) el.setAttribute('tabindex', '-1'); try { el.focus({ preventScroll: false }); } catch (e) { el.focus(); } };
  var scripts = {};
  RBC.loadScript = function (src) {
    if (!scripts[src]) {
      scripts[src] = new Promise(function (res, rej) {
        var s = document.createElement('script'); s.src = src; s.async = true;
        s.onload = function () { res(); }; s.onerror = function () { delete scripts[src]; rej(new Error('falha ao carregar ' + src)); };
        document.head.appendChild(s);
      });
    }
    return scripts[src];
  };
})();
