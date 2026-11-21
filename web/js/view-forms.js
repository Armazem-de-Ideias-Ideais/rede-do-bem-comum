/* Formulários sem login: Contato, Retirar do mapa, Corrigir, Indicar iniciativa e Convite.
   Também: tela honesta "em breve" (modo static), seleção de ficha, mensagens de erro do contrato e envio com antispam.
   Nenhum envio é simulado: sem backend, a tela diz que a função ainda não está ativa. */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon, ui = RBC.ui;
  var F = RBC.forms = {};

  /* ---------- mensagens de erro (API_CONTRATO §1.1) ---------- */
  F.errMsg = function (err) {
    var c = err && err.code ? String(err.code) : '';
    if (c === '28000') return t('err.login');
    if (c === '42501') return t('err.forbidden');
    if (c === 'P0002') return t('err.notfound');
    if (c === '22023') return t('err.invalid');
    if (c === '54000') return t('err.rate');
    if (c === 'P0001') return t('err.state');
    if (c === '40001') return t('err.conflict');
    if (c === 'network') return t('err.network');
    return t('err.generic');
  };

  /* ---------- tela honesta "em breve" (sem backend) ---------- */
  F.soon = function (titleKey, opts) {
    opts = opts || {};
    var contact = !opts.isContact && RBC.db.caps.write;
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('soon.eyebrow'), title: t(titleKey), back: opts.back }) +
      ui.state('soon', { title: t('soon.title'), html: '<p>' + esc(t(opts.isContact ? 'soon.contact_text' : 'soon.text')) + '</p>' + (opts.extra || ''),
        actions: (contact ? ui.btn(t('soon.use_contact'), { href: RBC.href('contact'), icon: 'letter' }) : '') + ui.btn(t('nav.about'), { href: RBC.href('about'), kind: 'secondary', icon: 'info' }) + ui.btn(t('nav.explore'), { href: RBC.href('explore'), kind: 'ghost', icon: 'search' }) }) + '</div>';
  };

  /* ---------- escolha de ficha (quando a rota vem sem slug) ---------- */
  F.picker = function (routeId) {
    return '<section class="psec" aria-labelledby="pick-h"><h2 id="pick-h">' + esc(t('pick.title')) + '</h2>' +
      '<div class="field"><label for="pick-q">' + esc(t('pick.label')) + '</label><div class="inputic">' + icon('search') + '<input id="pick-q" type="search" autocomplete="off" data-pick="' + routeId + '" aria-describedby="pick-hint"></div><p class="hint" id="pick-hint">' + esc(t('pick.hint')) + '</p></div>' +
      '<ul class="picklist" id="pick-list" aria-live="polite"></ul></section>';
  };
  F.mountPicker = function (el) {
    var q = RBC.qs('#pick-q', el); if (!q) return;
    var list = RBC.qs('#pick-list', el), routeId = q.getAttribute('data-pick');
    q.addEventListener('input', RBC.debounce(function () {
      var toks = RBC.norm(q.value).split(' ').filter(Boolean);
      if (!toks.length) { list.innerHTML = ''; return; }
      var hits = RBC.data.items.filter(function (e) { return toks.every(function (tk) { return e._name.indexOf(tk) >= 0 || (e.city && RBC.norm(e.city).indexOf(tk) >= 0); }); }).slice(0, 8);
      list.innerHTML = hits.length ? hits.map(function (e) { return '<li><a href="' + RBC.href(routeId, e.slug) + '">' + esc(e.name) + '</a> <span class="muted">· ' + esc(RBC.where(e)) + '</span></li>'; }).join('') : '<li class="muted">' + esc(t('pick.none')) + '</li>';
    }, 200));
  };
  F.entityHead = function (e) {
    return '<div class="entbox">' + icon(e.categories[0] || 'sprout') + '<div><p class="entbox__name"><a href="' + RBC.href('profile', e.slug) + '">' + esc(e.name) + '</a></p><p class="muted">' + esc(t('kind.' + e.kind)) + ' · ' + esc(RBC.where(e)) + '</p></div></div>';
  };

  /* ---------- envio: estados de pendência, erro e sucesso ---------- */
  F.result = function (zone, kind, title, html) {
    zone.innerHTML = '<div class="result result--' + kind + '" role="' + (kind === 'error' ? 'alert' : 'status') + '">' + icon(kind === 'error' ? 'alert' : 'check-circle') +
      '<div><h2 class="h3" tabindex="-1">' + esc(title) + '</h2>' + (html || '') + '</div></div>';
    RBC.focusEl(RBC.qs('h2', zone));
  };
  /* run: () => Promise; onOk(data) devolve [titulo, html] */
  F.submit = function (form, btn, run, onOk, onErr) {
    var out = RBC.qs('.formout', form.parentNode) || RBC.qs('.formout', form);
    btn.disabled = true; btn.setAttribute('aria-busy', 'true');
    var lbl = RBC.qs('span', btn), orig = lbl ? lbl.textContent : '';
    if (lbl) lbl.textContent = t('form.sending');
    RBC.announce(t('form.sending'));
    return run().then(function (data) {
      var r = onOk(data); form.hidden = true;
      F.result(out, 'ok', r[0], r[1]);
    }, function (err) {
      btn.disabled = false; btn.removeAttribute('aria-busy'); if (lbl) lbl.textContent = orig;
      var custom = onErr ? onErr(err) : null;   /* onErr devolve [titulo, html] para erros que têm tela própria */
      if (custom) { form.hidden = true; F.result(out, 'ok', custom[0], custom[1]); return; }
      F.result(out, 'error', t('err.title'), '<p>' + esc(F.errMsg(err)) + '</p>');
    });
  };
  F.len = function (v, min, max) { v = v || ''; return v.length >= min && v.length <= max; };
  F.spamGuard = function (form, started) {
    var s = ui.spamCheck(form, started, 3000);
    if (s === 'too_fast') { ui.showErrors(form, [[RBC.qs('[data-field]', form).getAttribute('data-field'), t('form.too_fast')]]); return false; }
    return true;
  };
  F.hp = function (form) { var h = RBC.qs('[name="website"]', form); return h && h.value ? h.value : null; };

  /* ---------- lista ISO de países (via Intl, sem tabela própria) ---------- */
  var isoCache = {};
  F.countryOptions = function () {
    var L = RBC.state.lang; if (isoCache[L]) return isoCache[L];
    var out = [], A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', skip = { EU: 1, EZ: 1, UN: 1, ZZ: 1, QO: 1, XA: 1, XB: 1, AN: 1, BU: 1, CS: 1, DD: 1, FX: 1, NT: 1, QU: 1, SU: 1, TP: 1, YD: 1, YU: 1, ZR: 1, AC: 1, CP: 1, DG: 1, EA: 1, IC: 1, TA: 1, CQ: 1 }, dn;
    try { dn = new Intl.DisplayNames([L === 'pt' ? 'pt-BR' : 'en'], { type: 'region', fallback: 'none' }); } catch (e) { dn = null; }
    if (dn) for (var i = 0; i < 26; i++) for (var j = 0; j < 26; j++) { var c = A[i] + A[j]; if (skip[c]) continue; var n; try { n = dn.of(c); } catch (e) { n = null; } if (n && n !== c) out.push([c, n]); }
    else Object.keys(RBC.data ? RBC.data.countries : {}).filter(Boolean).forEach(function (c) { out.push([c, c]); });
    out.sort(function (a, b) { return a[1].localeCompare(b[1], L === 'pt' ? 'pt-BR' : 'en'); });
    return (isoCache[L] = out);
  };

  function needsEntity(routeId, titleKey, r, body) {
    var e = r.param ? RBC.data.bySlug[r.param] : null;
    if (r.param && !e) return '<div class="view--narrow">' + ui.state('hidden', { h: 'h1', focus: true, title: t('profile.unavailable'), text: t('profile.unavailable_text'), actions: ui.btn(t('pick.other'), { href: RBC.href(routeId), kind: 'secondary' }) }) + '</div>';
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('care.eyebrow'), title: t(titleKey), lead: t(titleKey + '.lead'), back: e ? { href: RBC.href('profile', e.slug), label: t('form.back_profile') } : null }) +
      (e ? F.entityHead(e) + body(e) : F.picker(routeId)) + '</div>';
  }

  /* ---------- Retirar do mapa (sem login; com e-mail a ficha sai do ar quando o link é confirmado; sem e-mail vai para a fila) ---------- */
  var W = RBC.views.withdraw = { needsData: true };
  W.title = function () { return t('withdraw'); };
  W.render = function (r) {
    if (!RBC.db.caps.write) return F.soon('withdraw', { extra: '<p>' + esc(t('withdraw.soon_extra')) + '</p>' });
    return needsEntity('withdraw', 'withdraw', r, function () {
      return ui.notice('care', '<p>' + esc(t('withdraw.what')) + '</p>') +
        '<form id="wform" class="careform" novalidate>' + ui.errsum() +
        ui.group({ name: 'relation', type: 'radio', label: t('withdraw.relation'), required: true, options: ['representative', 'member', 'mentioned', 'other'].map(function (k) { return [k, t('withdraw.rel.' + k)]; }) }) +
        ui.input({ name: 'reason', label: t('withdraw.reason'), multiline: true, required: true, maxlength: 2000, hint: esc(t('withdraw.reason_hint')) }) +
        ui.input({ name: 'contact', label: t('withdraw.contact'), maxlength: 200, hint: esc(t('withdraw.contact_hint')) }) +
        ui.input({ name: 'email', type: 'email', label: t('withdraw.email'), maxlength: 200, autocomplete: 'email', hint: esc(t('withdraw.email_hint')) }) +
        ui.honeypot() + '<p class="actions">' + ui.btn(t('withdraw.send'), { type: 'submit', icon: 'eye-off', kind: 'danger' }) + '</p></form><div class="formout"></div>';
    });
  };
  W.mount = function (el, r) {
    F.mountPicker(el);
    var form = RBC.qs('#wform', el); if (!form) return;
    var started = Date.now(), e = RBC.data.bySlug[r.param];
    form.addEventListener('submit', function (ev) {
      ev.preventDefault(); var v = ui.read(form), errs = [];
      if (!v.relation) errs.push(['relation', t('withdraw.err.relation')]);
      if (!F.len(v.reason, 10, 2000)) errs.push(['reason', t('form.err.len', { min: 10, max: 2000 })]);
      var email = (v.email || '').trim();
      if (email && (email.length > 200 || !/^[^@\s<>"]+@[^@\s<>"]+\.[A-Za-z]{2,}$/.test(email))) errs.push(['email', t('form.err.email')]);
      if (!ui.showErrors(form, errs) || !F.spamGuard(form, started)) return;
      var back = '<p>' + ui.btn(t('nav.explore'), { href: RBC.href('explore'), kind: 'secondary', icon: 'search' }) + '</p>';
      F.submit(form, RBC.qs('[type=submit]', form), function () {
        return RBC.db.call('request_takedown', { p_entity: e.id, p_reason: v.reason, p_relation: v.relation, p_contact: v.contact || null, p_locale: RBC.state.lang, p_hp: F.hp(form), p_email: email || null });
      }, function (data) {
        /* O pedido nunca oculta a ficha: nada some deste navegador até a confirmação pelo link (rota confirmWithdraw). */
        var confirm = data && data.needs_confirmation === true;
        return [t(confirm ? 'withdraw.ok_confirm' : 'withdraw.ok_queued'), '<p>' + esc(t(confirm ? 'withdraw.ok_confirm_text' : 'withdraw.ok_queued_text')) + '</p>' + back];
      }, function (err) {
        if (err && String(err.code) === '54000') return [t('withdraw.limit'), '<p>' + esc(t('withdraw.limit_text')) + '</p><p>' + ui.btn(t('soon.use_contact'), { href: RBC.href('contact'), icon: 'letter' }) + '</p>'];
        return null;
      });
    });
  };

  /* ---------- Confirmar a retirada (link enviado por e-mail: #confirmar-retirada-<token>) ---------- */
  var CW = RBC.views.confirmWithdraw = { needsData: false }, cwDone = {}, cwBusy = {};
  CW.title = function () { return t('confirmwd'); };
  function cwBox(kind, title, text, withNew) {
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('care.eyebrow'), title: t('confirmwd') }) +
      '<div class="result result--' + kind + '" role="' + (kind === 'error' ? 'alert' : 'status') + '">' + icon(kind === 'error' ? 'alert' : 'check-circle') +
      '<div><h2 class="h3" id="page-title" tabindex="-1">' + esc(title) + '</h2><p>' + esc(text) + '</p><p>' +
      (withNew ? ui.btn(t('confirmwd.new'), { href: RBC.href('withdraw'), icon: 'eye-off' }) + ' ' : '') + ui.btn(t('nav.explore'), { href: RBC.href('explore'), kind: 'secondary', icon: 'search' }) + '</p></div></div></div>';
  }
  CW.render = function (r) {
    if (!RBC.db.caps.write) return F.soon('withdraw', { extra: '<p>' + esc(t('withdraw.soon_extra')) + '</p>' });
    var res = cwDone[r.param];
    if (res) return res.html();
    if (cwBusy[r.param]) return '<div class="view--narrow"><h1 id="page-title" tabindex="-1" class="sr">' + esc(t('confirmwd.loading')) + '</h1>' + ui.loading(2) + '</div>';
    /* Abrir o link não confirma nada: antivírus e filtros de e-mail visitam links sozinhos. Só o clique confirma. */
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('care.eyebrow'), title: t('confirmwd'), lead: t('confirmwd.ask_text') }) +
      '<p class="actions">' + ui.btn(t('confirmwd.go'), { attrs: 'id="cw-go"', icon: 'eye-off' }) + ' ' +
      ui.btn(t('nav.explore'), { href: RBC.href('explore'), kind: 'secondary', icon: 'search' }) + '</p></div>';
  };
  CW.mount = function (el, r) {
    if (!RBC.db.caps.write || cwDone[r.param]) return;
    var token = r.param;
    function finish(res) { cwDone[token] = res; if (RBC.current && RBC.current.route && RBC.current.route.id === 'confirmWithdraw' && RBC.current.route.param === token) RBC.render({ focus: true }); }
    var invalid = { html: function () { return cwBox('error', t('confirmwd.invalid'), t('confirmwd.invalid_text'), true); } };
    if (!/^[0-9a-f]{64}$/.test(token)) { finish(invalid); return; }   /* formato errado: nem chama o servidor */
    var go = el.querySelector('#cw-go');
    if (!go || cwBusy[token]) return;
    go.addEventListener('click', function () {
      if (cwBusy[token]) return;
      cwBusy[token] = true; RBC.render({ focus: true });
      confirmNow();
    });
    function confirmNow() { RBC.db.call('confirm_takedown', { p_token: token }).then(function (data) {
      if (data && data.hidden === true) {
        RBC.reloadData();   /* a ficha some das listas deste navegador */
        finish({ html: function () { return cwBox('ok', t('confirmwd.ok'), t('confirmwd.ok_text')); } });
      } else if (data && data.queued === true) finish({ html: function () { return cwBox('ok', t('confirmwd.queued'), t('confirmwd.queued_text')); } });
      else finish(invalid);
    }, function (err) {
      var c = err && String(err.code);
      if (c === 'network') finish({ html: function () { return cwBox('error', t('err.title'), t('err.network')); } });
      else if (c === '54000') finish({ html: function () { return cwBox('error', t('err.title'), t('err.rate')); } });
      else finish(invalid);   /* qualquer outra falha: erro genérico, sem dizer o motivo */
    }); }
  };

  /* ---------- Corrigir (e relatar exposição ou abuso) ---------- */
  var C = RBC.views.correct = { needsData: true };
  C.title = function () { return t('correct'); };
  C.render = function (r) {
    if (!RBC.db.caps.write) return F.soon('correct');
    return needsEntity('correct', 'correct', r, function () {
      return '<form id="cform" class="careform" novalidate>' + ui.errsum() +
        ui.group({ name: 'kind', type: 'radio', label: t('correct.kind'), required: true, value: 'correction', options: ['correction', 'exposure', 'abuse', 'other'].map(function (k) { return [k, t('correct.kind.' + k), t('correct.kind.' + k + '_d')]; }) }) +
        ui.input({ name: 'body', label: t('correct.body'), multiline: true, required: true, maxlength: 5000, hint: esc(t('correct.body_hint')) }) +
        ui.input({ name: 'contact', label: t('withdraw.contact'), maxlength: 200, hint: esc(t('withdraw.contact_hint')) }) +
        ui.honeypot() + '<p class="actions">' + ui.btn(t('correct.send'), { type: 'submit', icon: 'send' }) + '</p></form><div class="formout"></div>';
    });
  };
  C.mount = function (el, r) {
    F.mountPicker(el);
    var form = RBC.qs('#cform', el); if (!form) return;
    var started = Date.now(), e = RBC.data.bySlug[r.param];
    form.addEventListener('submit', function (ev) {
      ev.preventDefault(); var v = ui.read(form), errs = [];
      if (!F.len(v.body, 5, 5000)) errs.push(['body', t('form.err.len', { min: 5, max: 5000 })]);
      if (!ui.showErrors(form, errs) || !F.spamGuard(form, started)) return;
      F.submit(form, RBC.qs('[type=submit]', form), function () {
        return RBC.db.call('report', { p_kind: v.kind || 'correction', p_entity: e.id, p_body: v.body, p_contact: v.contact || null, p_hp: F.hp(form) });
      }, function () { return [t('correct.ok'), '<p>' + esc(t('correct.ok_text')) + '</p>']; });
    });
  };

  /* ---------- Indicar uma iniciativa (fila editorial; nunca publica direto) ---------- */
  var S = RBC.views.suggest = { needsData: true };
  S.title = function () { return t('suggest'); };
  S.render = function () {
    if (!RBC.db.caps.write) return F.soon('suggest');
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('join.eyebrow'), title: t('suggest'), lead: t('suggest.lead') }) +
      ui.notice('care', '<p>' + esc(t('suggest.care')) + '</p>') +
      '<form id="sform" class="careform" novalidate>' + ui.errsum() +
      ui.input({ name: 'name', label: t('suggest.name'), required: true, maxlength: 180 }) +
      ui.input({ name: 'site', label: t('suggest.site'), type: 'url', maxlength: 300, hint: esc(t('suggest.site_hint')) }) +
      ui.select({ name: 'country', label: t('suggest.country'), placeholder: t('suggest.country_none'), options: F.countryOptions() }) +
      ui.input({ name: 'city', label: t('suggest.city'), maxlength: 120, hint: esc(t('suggest.city_hint')) }) +
      ui.group({ name: 'families', label: t('suggest.families'), hint: esc(t('suggest.families_hint')), compact: true, cols: true, options: RBC.FAMILIES.map(function (f) { return [f, RBC.famLabel(f), '', '', f]; }) }) +
      ui.input({ name: 'description', label: t('suggest.description'), multiline: true, required: true, maxlength: 2000 }) +
      ui.input({ name: 'why', label: t('suggest.why'), multiline: true, rows: 3, maxlength: 2000 }) +
      ui.input({ name: 'contact', label: t('suggest.contact'), maxlength: 200, hint: esc(t('suggest.contact_hint')) }) +
      ui.honeypot() + '<p class="actions">' + ui.btn(t('suggest.send'), { type: 'submit', icon: 'send' }) + '</p></form><div class="formout"></div></div>';
  };
  S.mount = function (el) {
    var form = RBC.qs('#sform', el); if (!form) return;
    var started = Date.now();
    form.addEventListener('submit', function (ev) {
      ev.preventDefault(); var v = ui.read(form), errs = [];
      if (!F.len(v.name, 2, 180)) errs.push(['name', t('form.err.len', { min: 2, max: 180 })]);
      if (v.site && !RBC.safeUrl(v.site)) errs.push(['site', t('form.err.url')]);
      if ((v.families || []).length > 5) errs.push(['families', t('suggest.err.families')]);
      if (!F.len(v.description, 10, 2000)) errs.push(['description', t('form.err.len', { min: 10, max: 2000 })]);
      if (!ui.showErrors(form, errs) || !F.spamGuard(form, started)) return;
      F.submit(form, RBC.qs('[type=submit]', form), function () {
        return RBC.db.call('suggest_initiative', { p_name: v.name, p_website: v.site || null, p_country: v.country || null, p_city: v.city || null, p_families: v.families || [], p_description: v.description, p_why: v.why || null, p_contact: v.contact || null, p_locale: RBC.state.lang, p_hp: F.hp(form) });
      }, function () { return [t('suggest.ok'), '<p>' + esc(t('suggest.ok_text')) + '</p>']; });
    });
  };

  /* ---------- Contato (gravado no banco; o servidor avisa a moderação) ---------- */
  var K = RBC.views.contact = { needsData: false };
  K.title = function () { return t('nav.contact'); };
  K.render = function () {
    if (!RBC.db.caps.write) return F.soon('nav.contact', { isContact: true });
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('care.eyebrow'), title: t('nav.contact'), lead: t('contact.lead') }) +
      ui.notice('care', '<p>' + esc(t('contact.privacy')) + '</p>') +
      '<form id="kform" class="careform" novalidate>' + ui.errsum() +
      ui.input({ name: 'name', label: t('contact.name'), required: true, maxlength: 120, autocomplete: 'name' }) +
      ui.input({ name: 'email', label: t('contact.email'), type: 'email', required: true, maxlength: 200, autocomplete: 'email', hint: esc(t('contact.email_hint')) }) +
      ui.input({ name: 'subject', label: t('contact.subject'), required: true, maxlength: 150 }) +
      ui.input({ name: 'body', label: t('contact.body'), multiline: true, rows: 6, required: true, maxlength: 5000 }) +
      ui.honeypot() + '<p class="actions">' + ui.btn(t('contact.send'), { type: 'submit', icon: 'send' }) + '</p></form><div class="formout"></div></div>';
  };
  K.mount = function (el) {
    var form = RBC.qs('#kform', el); if (!form) return;
    var started = Date.now();
    form.addEventListener('submit', function (ev) {
      ev.preventDefault(); var v = ui.read(form), errs = [];
      if (!F.len(v.name, 1, 120)) errs.push(['name', t('form.err.required')]);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email || '')) errs.push(['email', t('form.err.email')]);
      if (!F.len(v.subject, 3, 150)) errs.push(['subject', t('form.err.len', { min: 3, max: 150 })]);
      if (!F.len(v.body, 10, 5000)) errs.push(['body', t('form.err.len', { min: 10, max: 5000 })]);
      if (!ui.showErrors(form, errs) || !F.spamGuard(form, started)) return;
      F.submit(form, RBC.qs('[type=submit]', form), function () {
        return RBC.db.call('send_contact_message', { p_name: v.name, p_email: v.email, p_subject: v.subject, p_body: v.body, p_locale: RBC.state.lang, p_hp: F.hp(form) });
      }, function () { return [t('contact.ok'), '<p>' + esc(t('contact.ok_text')) + '</p>']; });
    });
  };

  /* ---------- Convite (iniciativas de exposição alta): prévia, aceite com login, recusa ---------- */
  var I = RBC.views.invite = { needsData: false };
  I.title = function () { return t('invite'); };
  I.render = function (r) {
    if (!RBC.db.caps.write) return F.soon('invite');
    if (!/^[a-f0-9]{64}$/.test(r.param || '')) return '<div class="view--narrow">' + ui.state('hidden', { h: 'h1', focus: true, title: t('invite.invalid'), text: t('invite.invalid_text') }) + '</div>';
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('invite.eyebrow'), title: t('invite'), lead: t('invite.lead') }) + '<div id="invbox">' + ui.loading(1) + '</div></div>';
  };
  I.mount = function (el, r) {
    var box = RBC.qs('#invbox', el); if (!box) return;
    RBC.db.call('invite_preview', { p_token: r.param }).then(function (p) {
      if (!document.body.contains(box)) return;
      var session = RBC.state.session;
      box.innerHTML = '<section class="psec"><h2>' + esc(t('invite.preview')) + '</h2>' +
        ui.dl([[t('suggest.name'), esc(p.name)], [t('profile.kind'), esc(t('kind.' + p.kind))], [t('profile.where'), esc((p.city ? p.city + ', ' : '') + RBC.countryName(p.country_code))],
          [t('profile.families'), (p.families || []).map(function (f) { return esc(RBC.famLabel(f)); }).join(', ')], [t('profile.summary_pt'), '<span lang="pt">' + esc(p.summary_pt || '') + '</span>'],
          p.website_url ? [t('profile.own_site'), ui.extLink(p.website_url)] : null, [t('invite.expires'), esc(RBC.fmtDate(p.expires_at))]]) + '</section>' +
        '<form id="iform" class="careform" novalidate>' + ui.errsum() +
        ui.group({ name: 'location', type: 'radio', label: t('invite.location'), required: true, value: 'city', options: [['city', t('invite.loc.city'), t('invite.loc.city_d')], ['none', t('invite.loc.none'), t('invite.loc.none_d')]] }) +
        ui.input({ name: 'summary', label: t('invite.summary'), multiline: true, rows: 3, maxlength: 200, value: p.summary_pt || '', hint: esc(t('invite.summary_hint')) }) +
        ui.check({ name: 'consent', label: t('invite.consent'), required: true, hint: esc(t('invite.consent_hint')) + ' <a href="' + RBC.href('privacy') + '">' + esc(t('nav.privacy')) + '</a>' }) +
        '<p class="actions actions--wrap">' + ui.btn(session ? t('invite.accept') : t('invite.accept_login'), { type: 'submit', icon: 'check' }) + ui.btn(t('invite.decline'), { kind: 'ghost', attrs: 'data-decline', icon: 'close' }) + '</p></form><div class="formout"></div>';
      var form = RBC.qs('#iform', box);
      form.addEventListener('submit', function (ev) {
        ev.preventDefault(); var v = ui.read(form), errs = [];
        if (!v.consent) errs.push(['consent', t('invite.err.consent')]);
        if (v.summary && !F.len(v.summary, 10, 200)) errs.push(['summary', t('form.err.len', { min: 10, max: 200 })]);
        if (!ui.showErrors(form, errs)) return;
        if (!RBC.state.session) { RBC.account.intent(window.location.hash); RBC.go('login'); return; }
        F.submit(form, RBC.qs('[type=submit]', form), function () {
          return RBC.db.call('invite_accept', { p_token: r.param, p_consent_text_version: 'convite-2026-11', p_location: v.location || 'city', p_summary_pt: v.summary && v.summary !== p.summary_pt ? v.summary : null });
        }, function (d) { RBC.reloadData(); return [t('invite.ok'), '<p>' + esc(t('invite.ok_text')) + '</p><p>' + ui.btn(t('invite.see'), { href: RBC.href('profile', d.slug), icon: 'arrow-right' }) + '</p>']; });
      });
      RBC.qs('[data-decline]', form).addEventListener('click', function () {
        if (!window.confirm(t('invite.decline_confirm'))) return;
        F.submit(form, RBC.qs('[data-decline]', form), function () { return RBC.db.call('invite_decline', { p_token: r.param, p_reason: null }); },
          function () { return [t('invite.declined'), '<p>' + esc(t('invite.declined_text')) + '</p>']; });
      });
    }, function (err) {
      if (!document.body.contains(box)) return;
      box.innerHTML = ui.state('hidden', { title: t('invite.invalid'), text: err && err.code === 'P0002' ? t('invite.invalid_text') : F.errMsg(err) });
    });
  };
})();
