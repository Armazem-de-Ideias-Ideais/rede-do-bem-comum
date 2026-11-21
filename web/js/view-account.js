/* Telas com conta (adaptador supabase): Entrar por link mágico, Meu espaço, Reivindicação (3 caminhos),
   Editar ficha, Conectar, Ofertas e necessidades e Painel editorial. No modo static, todas mostram "em breve". */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon, ui = RBC.ui, F = RBC.forms;
  var A = RBC.account = {};

  /* intenção pendente: o link mágico (PKCE) volta com ?code= e sem a rota; guardamos para retomar depois */
  A.intent = function (hash) { try { window.sessionStorage.setItem('rbc.intent', hash || ''); } catch (e) { RBC.store.set('intent', hash || ''); } };
  A.takeIntent = function () {
    var v = null; try { v = window.sessionStorage.getItem('rbc.intent'); window.sessionStorage.removeItem('rbc.intent'); } catch (e) { v = RBC.store.get('intent'); RBC.store.del('intent'); }
    return v && /^#[a-z0-9-]+$/.test(v) ? v : null;
  };
  A.peekIntent = function () { var v = null; try { v = window.sessionStorage.getItem('rbc.intent'); } catch (e) { v = RBC.store.get('intent'); } return v && /^#[a-z0-9-]+$/.test(v) ? v : null; };
  A.me = null;
  A.loadMe = function (force) {
    if (A.me && !force) return Promise.resolve(A.me);
    return RBC.db.call('my_account', {}).then(function (m) { A.me = m || { roles: [], managed: [], claims: [], connections: {} }; return A.me; });
  };
  A.isMod = function () { return !!(A.me && (A.me.roles || []).indexOf('moderator') >= 0); };
  A.manages = function (entityId) { return !!(A.me && (A.me.managed || []).some(function (m) { return m.entity_id === entityId; })); };

  function loginBox(reasonKey) {
    return '<section class="psec loginbox" aria-labelledby="lg-h"><h2 id="lg-h">' + esc(t('login.need')) + '</h2>' + (reasonKey ? '<p>' + esc(t(reasonKey)) + '</p>' : '') +
      '<form id="lgform" class="careform" novalidate>' + ui.errsum() +
      ui.input({ name: 'email', type: 'email', label: t('login.email'), required: true, autocomplete: 'email', maxlength: 200, hint: esc(t('login.email_hint')) }) +
      '<p class="actions">' + ui.btn(t('login.send'), { type: 'submit', icon: 'send' }) + '</p></form><div class="formout"></div>' +
      '<p class="hint">' + esc(t('login.same_browser')) + '</p></section>';
  }
  function mountLogin(el, intent) {
    var form = RBC.qs('#lgform', el); if (!form) return;
    form.addEventListener('submit', function (ev) {
      ev.preventDefault(); var v = ui.read(form);
      if (!ui.showErrors(form, /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email || '') ? [] : [['email', t('form.err.email')]])) return;
      A.intent(intent || A.peekIntent() || RBC.href('mySpace'));
      F.submit(form, RBC.qs('[type=submit]', form), function () { return RBC.db.signIn(v.email); },
        function () { return [t('login.sent'), '<p>' + esc(t('login.sent_text')) + '</p>']; });
    });
  }
  /* guarda de rota: sem backend → em breve; sem sessão → caixa de login; senão segue */
  function gate(titleKey, r, reasonKey) {
    if (!RBC.db.caps.auth) return F.soon(titleKey);
    if (!RBC.state.session) return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('account.eyebrow'), title: t(titleKey) }) + loginBox(reasonKey) + '</div>';
    return null;
  }
  function gateMount(el) { if (!RBC.state.session) { mountLogin(el, window.location.hash); return false; } return true; }
  function shell(titleKey, lead, back) {
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('account.eyebrow'), title: t(titleKey), lead: lead, back: back }) + '<div id="acbox">' + ui.loading(1) + '</div></div>';
  }
  function fail(box) { return function (err) { if (box && document.body.contains(box)) box.innerHTML = ui.state('error', { title: t('err.title'), text: F.errMsg(err), actions: ui.btn(t('state.retry'), { icon: 'refresh', attrs: 'data-reload' }) }); var b = box && RBC.qs('[data-reload]', box); if (b) b.addEventListener('click', function () { RBC.render(); }); }; }

  /* ---------- Entrar ---------- */
  var L = RBC.views.login = { needsData: false };
  L.title = function () { return t('login'); };
  L.render = function () {
    if (!RBC.db.caps.auth) return F.soon('login');
    if (RBC.state.session) return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('account.eyebrow'), title: t('login') }) + ui.state('ok', { title: t('login.already'), actions: ui.btn(t('nav.space'), { href: RBC.href('mySpace'), icon: 'user' }) }) + '</div>';
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('account.eyebrow'), title: t('login'), lead: t('login.lead') }) + loginBox() +
      ui.notice('care', '<p>' + esc(t('login.private')) + '</p>') + '</div>';
  };
  L.mount = function (el) { mountLogin(el, null); };

  /* ---------- Meu espaço ---------- */
  var M = RBC.views.mySpace = { needsData: true };
  M.title = function () { return t('nav.space'); };
  M.render = function (r) { return gate('nav.space', r) || shell('nav.space', t('space.lead')); };
  M.mount = function (el) {
    if (!gateMount(el)) return;
    var box = RBC.qs('#acbox', el);
    Promise.all([A.loadMe(true), RBC.db.call('my_connections', {})]).then(function (res) {
      var me = res[0], cons = res[1] || [];
      var managed = (me.managed || []).map(function (m) {
        return '<li class="space-card"><h3 class="h4"><a href="' + RBC.href('profile', m.slug) + '">' + esc(m.name) + '</a></h3><p class="actions actions--wrap">' +
          ui.btn(t('space.edit'), { href: RBC.href('edit', m.slug), small: true, icon: 'edit' }) + ui.btn(t('space.offers'), { href: RBC.href('offers', m.slug), small: true, kind: 'secondary', icon: 'offer' }) + '</p>' +
          '<label class="opt opt--compact" for="acc-' + esc(m.entity_id) + '"><input type="checkbox" id="acc-' + esc(m.entity_id) + '" data-accept="' + esc(m.entity_id) + '"' + (m.accepts_connections ? ' checked' : '') + '><span class="opt__body"><span class="opt__label">' + esc(t('space.accepts')) + '</span></span></label></li>';
      }).join('');
      var claims = (me.claims || []).map(function (c) {
        return '<li class="space-card"><h3 class="h4"><a href="' + RBC.href('profile', c.slug) + '">' + esc(c.name) + '</a></h3><p>' + ui.stamp(c.status === 'approved' ? 'managed' : c.status === 'rejected' || c.status === 'failed' ? 'correction' : 'pending', t('claim.status.' + c.status)) + ' <span class="muted">' + esc(t('claim.method.' + c.method)) + '</span></p>' +
          (/^awaiting_/.test(c.status) ? '<p>' + ui.btn(t('space.continue'), { href: RBC.href('claim', c.slug), small: true, icon: 'arrow-right' }) + '</p>' : '') + '</li>';
      }).join('');
      var conRows = cons.map(function (c) {
        var pend = c.status === 'pending';
        return '<li class="space-card"><p class="eyebrow">' + esc(t(c.direction === 'in' ? 'con.in' : 'con.out')) + ' · ' + esc(t('con.status.' + c.status)) + '</p>' +
          '<h3 class="h4">' + esc(c.my_entity_name) + ' ↔ <a href="' + RBC.href('profile', c.other_entity_slug) + '">' + esc(c.other_entity_name) + '</a></h3>' +
          (c.message ? '<blockquote class="proto__msg">' + esc(c.message) + '</blockquote>' : '') +
          (c.status === 'accepted' ? ui.dl([[t('con.their_contact'), esc(c.other_contact || '—')], [t('con.my_contact'), esc(c.my_contact || '—')]]) : '') +
          (pend && c.direction === 'in' ? '<form class="conform" data-req="' + esc(c.request_id) + '" novalidate>' + ui.input({ name: 'contact_' + c.request_id, label: t('con.reply_contact'), maxlength: 300, hint: esc(t('con.reply_hint')) }) +
            '<p class="actions actions--wrap">' + ui.btn(t('con.accept'), { type: 'submit', small: true, icon: 'check' }) + ui.btn(t('con.decline'), { small: true, kind: 'ghost', attrs: 'data-decline="' + esc(c.request_id) + '"' }) + '</p></form>' : '') +
          (pend && c.direction === 'out' ? '<p>' + ui.btn(t('con.cancel'), { small: true, kind: 'ghost', attrs: 'data-cancel="' + esc(c.request_id) + '"' }) + '</p>' : '') + '</li>';
      }).join('');
      box.innerHTML = ui.notice('care', '<p>' + esc(t('space.private')) + '</p>') +
        (A.isMod() ? '<p>' + ui.btn(t('nav.moderation'), { href: RBC.href('moderation'), icon: 'shield', kind: 'secondary' }) + '</p>' : '') +
        '<section class="psec"><h2>' + esc(t('space.managed')) + '</h2>' + (managed ? '<ul class="mlist">' + managed + '</ul>' : '<p class="muted">' + esc(t('space.managed_none')) + '</p><p>' + ui.btn(t('act.claim'), { href: RBC.href('claim'), icon: 'key', kind: 'secondary' }) + '</p>') + '</section>' +
        '<section class="psec"><h2>' + esc(t('space.claims')) + '</h2>' + (claims ? '<ul class="mlist">' + claims + '</ul>' : '<p class="muted">' + esc(t('space.claims_none')) + '</p>') + '</section>' +
        '<section class="psec"><h2>' + esc(t('space.connections')) + '</h2>' + (conRows ? '<ul class="mlist">' + conRows + '</ul>' : '<p class="muted">' + esc(t('space.connections_none')) + '</p>') + '</section>' +
        '<section class="psec"><h2>' + esc(t('space.settings')) + '</h2><p>' + esc(t('space.locale', { lang: RBC.state.lang === 'pt' ? 'Português' : 'English' })) + '</p><p class="actions actions--wrap">' +
        ui.btn(t('space.set_locale'), { small: true, kind: 'secondary', attrs: 'data-locale', icon: 'globe' }) + ui.btn(t('login.out'), { small: true, kind: 'ghost', attrs: 'data-signout', icon: 'arrow-left' }) + '</p><div class="formout" id="setout"></div></section>';
      box.addEventListener('change', function (ev) {
        var c = ev.target; if (!c.hasAttribute('data-accept')) return;
        RBC.db.call('set_accepts_connections', { p_entity: c.getAttribute('data-accept'), p_accept: c.checked }).then(function () { RBC.announce(t('form.saved')); }, function (err) { c.checked = !c.checked; RBC.announce(F.errMsg(err)); });
      });
      box.addEventListener('submit', function (ev) {
        var f = ev.target; if (!f.hasAttribute('data-req')) return; ev.preventDefault();
        var id = f.getAttribute('data-req'), v = RBC.qs('input', f).value.trim();
        if (!ui.showErrors(f, F.len(v, 5, 300) ? [] : [['contact_' + id, t('form.err.len', { min: 5, max: 300 })]])) return;
        RBC.db.call('connect_respond', { p_request: id, p_accept: true, p_contact: v }).then(function () { RBC.render(); RBC.announce(t('con.accepted')); }, function (err) { ui.showErrors(f, [['contact_' + id, F.errMsg(err)]]); });
      });
      box.addEventListener('click', function (ev) {
        var b = ev.target.closest('[data-decline],[data-cancel],[data-signout],[data-locale]'); if (!b) return;
        if (b.hasAttribute('data-decline')) RBC.db.call('connect_respond', { p_request: b.getAttribute('data-decline'), p_accept: false, p_contact: null }).then(function () { RBC.render(); }, function (err) { RBC.announce(F.errMsg(err)); });
        else if (b.hasAttribute('data-cancel')) RBC.db.call('connect_cancel', { p_request: b.getAttribute('data-cancel') }).then(function () { RBC.render(); }, function (err) { RBC.announce(F.errMsg(err)); });
        else if (b.hasAttribute('data-signout')) RBC.db.signOut().then(function () { A.me = null; RBC.go('home'); });
        else RBC.db.call('set_locale', { p_locale: RBC.state.lang }).then(function () { F.result(RBC.qs('#setout', box), 'ok', t('form.saved')); }, function (err) { F.result(RBC.qs('#setout', box), 'error', F.errMsg(err)); });
      });
    }, fail(box));
  };

  /* ---------- Reivindicação: (a) e-mail do domínio, (b) código publicado, (c) aprovação manual ---------- */
  var R = RBC.views.claim = { needsData: true };
  R.title = function () { return t('claim'); };
  R.render = function (r) {
    if (!RBC.db.caps.auth) return F.soon('claim', { extra: '<p>' + esc(t('claim.soon_extra')) + '</p>' });
    var e = r.param ? RBC.data.bySlug[r.param] : null;
    if (!r.param) return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('account.eyebrow'), title: t('claim'), lead: t('claim.lead') }) + F.picker('claim') + '</div>';
    if (!e) return '<div class="view--narrow">' + ui.state('hidden', { h: 'h1', focus: true, title: t('profile.unavailable'), text: t('profile.unavailable_text') }) + '</div>';
    var g = gate('claim', r, 'claim.login_reason'); if (g) return g.replace('</header>', '</header>' + F.entityHead(e));
    return '<div class="view--narrow">' + ui.pageHead({ eyebrow: t('account.eyebrow'), title: t('claim'), lead: t('claim.lead'), back: { href: RBC.href('profile', e.slug), label: t('form.back_profile') } }) + F.entityHead(e) + '<div id="acbox">' + ui.loading(1) + '</div></div>';
  };
  R.mount = function (el, r) {
    F.mountPicker(el); if (!r.param || !RBC.data.bySlug[r.param] || !RBC.db.caps.auth) return;
    if (!gateMount(el)) return;
    var e = RBC.data.bySlug[r.param], box = RBC.qs('#acbox', el);
    A.loadMe(true).then(function (me) {
      if (A.manages(e.id)) { box.innerHTML = ui.state('ok', { title: t('claim.already'), actions: ui.btn(t('space.edit'), { href: RBC.href('edit', e.slug), icon: 'edit' }) }); return; }
      var open = (me.claims || []).filter(function (c) { return c.entity_id === e.id && /^(awaiting_code|awaiting_evidence|pending)$/.test(c.status); })[0];
      if (open) { step(box, e, open); return; }
      var methods = [['published_code', t('claim.method.published_code'), t('claim.m.b_d')], ['manual', t('claim.method.manual'), t('claim.m.c_d')]];
      if (e.own_url) methods.unshift(['domain_email', t('claim.method.domain_email'), t('claim.m.a_d', { domain: (e.own_url.split('/')[2] || '').replace(/^www\./, '') })]);
      box.innerHTML = '<form id="clform" class="careform" novalidate>' + ui.errsum() +
        ui.group({ name: 'method', type: 'radio', label: t('claim.method'), required: true, value: methods[0][0], options: methods }) +
        '<div id="cl-email">' + ui.input({ name: 'email', type: 'email', label: t('claim.email'), maxlength: 200, autocomplete: 'email', hint: esc(t('claim.email_hint')) }) + '</div>' +
        ui.input({ name: 'statement', label: t('claim.statement'), multiline: true, required: true, maxlength: 2000, hint: esc(t('claim.statement_hint')) }) +
        '<p class="actions">' + ui.btn(t('claim.send'), { type: 'submit', icon: 'key' }) + '</p></form><div class="formout"></div>';
      var form = RBC.qs('#clform', box), em = RBC.qs('#cl-email', box);
      var sync = function () { em.hidden = ui.read(form).method !== 'domain_email'; }; sync();
      form.addEventListener('change', sync);
      form.addEventListener('submit', function (ev) {
        ev.preventDefault(); var v = ui.read(form), errs = [];
        if (!F.len(v.statement, 10, 2000)) errs.push(['statement', t('form.err.len', { min: 10, max: 2000 })]);
        if (v.method === 'domain_email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email || '')) errs.push(['email', t('form.err.email')]);
        if (!ui.showErrors(form, errs)) return;
        var btn = RBC.qs('[type=submit]', form); btn.disabled = true;
        RBC.db.call('claim_start', { p_entity: e.id, p_method: v.method, p_statement: v.statement, p_email: v.method === 'domain_email' ? v.email : null }).then(function (res) {
          step(box, e, { id: res.claim_id, method: res.method, status: res.status, published_code: res.published_code, code_expires_at: res.code_expires_at });
        }, function (err) { btn.disabled = false; ui.showErrors(form, [[err && err.code === '22023' && v.method === 'domain_email' ? 'email' : 'statement', err && err.code === '22023' && v.method === 'domain_email' ? t('claim.err.domain') : F.errMsg(err)]]); });
      });
    }, fail(box));
  };
  function step(box, e, c) {
    if (c.status === 'approved') { A.me = null; RBC.reloadData(); F.result(box, 'ok', t('claim.ok_approved'), '<p>' + ui.btn(t('space.edit'), { href: RBC.href('edit', e.slug), icon: 'edit' }) + '</p>'); return; }
    if (c.status === 'pending') { F.result(box, 'ok', t('claim.ok_pending'), '<p>' + esc(t('claim.ok_pending_text')) + '</p>'); return; }
    if (c.status === 'awaiting_code') {
      box.innerHTML = '<form id="cvform" class="careform" novalidate>' + ui.errsum() + '<p>' + esc(t('claim.code_sent')) + '</p>' +
        ui.input({ name: 'code', label: t('claim.code'), required: true, maxlength: 6, attrs: 'inputmode="numeric" pattern="[0-9]{6}"', autocomplete: 'one-time-code' }) +
        '<p class="actions actions--wrap">' + ui.btn(t('claim.verify'), { type: 'submit', icon: 'check' }) + ui.btn(t('claim.resend'), { kind: 'ghost', small: true, attrs: 'data-resend' }) + ui.btn(t('claim.cancel'), { kind: 'ghost', small: true, attrs: 'data-cancel-claim' }) + '</p></form><div class="formout"></div>';
      var f = RBC.qs('#cvform', box);
      f.addEventListener('submit', function (ev) {
        ev.preventDefault(); var v = ui.read(f);
        if (!ui.showErrors(f, /^\d{6}$/.test(v.code) ? [] : [['code', t('claim.err.code')]])) return;
        RBC.db.call('claim_verify_code', { p_claim: c.id, p_code: v.code }).then(function (res) {
          if (res.status === 'approved') step(box, e, { status: 'approved' });
          else ui.showErrors(f, [['code', res.status === 'failed' ? t('claim.failed') : t('claim.wrong_code', { n: res.attempts_left })]]);
        }, function (err) { ui.showErrors(f, [['code', F.errMsg(err)]]); });
      });
      RBC.qs('[data-resend]', f).addEventListener('click', function () { RBC.db.call('claim_resend_code', { p_claim: c.id }).then(function () { RBC.announce(t('claim.resent')); }, function (err) { ui.showErrors(f, [['code', F.errMsg(err)]]); }); });
      RBC.qs('[data-cancel-claim]', f).addEventListener('click', function () { RBC.db.call('claim_cancel', { p_claim: c.id }).then(function () { RBC.render(); }); });
      return;
    }
    if (c.status === 'awaiting_evidence') {
      box.innerHTML = '<form id="ceform" class="careform" novalidate>' + ui.errsum() + '<p>' + esc(t('claim.publish_code')) + '</p><p class="codebox"><code>' + esc(c.published_code || '') + '</code></p>' +
        (c.code_expires_at ? '<p class="hint">' + esc(t('claim.code_valid', { date: RBC.fmtDate(c.code_expires_at) })) + '</p>' : '') +
        ui.input({ name: 'url', type: 'url', label: t('claim.evidence_url'), required: true, maxlength: 500, hint: esc(t('claim.evidence_hint')) }) +
        '<p class="actions actions--wrap">' + ui.btn(t('claim.send_evidence'), { type: 'submit', icon: 'send' }) + ui.btn(t('claim.cancel'), { kind: 'ghost', small: true, attrs: 'data-cancel-claim' }) + '</p></form><div class="formout"></div>';
      var g = RBC.qs('#ceform', box);
      g.addEventListener('submit', function (ev) {
        ev.preventDefault(); var v = ui.read(g);
        if (!ui.showErrors(g, /^https:\/\/\S+$/.test(v.url) ? [] : [['url', t('form.err.https')]])) return;
        F.submit(g, RBC.qs('[type=submit]', g), function () { return RBC.db.call('claim_submit_evidence', { p_claim: c.id, p_url: v.url }); }, function () { return [t('claim.ok_pending'), '<p>' + esc(t('claim.ok_pending_text')) + '</p>']; });
      });
      RBC.qs('[data-cancel-claim]', g).addEventListener('click', function () { RBC.db.call('claim_cancel', { p_claim: c.id }).then(function () { RBC.render(); }); });
      return;
    }
    F.result(box, 'error', t('claim.status.' + c.status));
  }

  /* ---------- Editar ficha (gestor ativo) ---------- */
  var E = RBC.views.edit = { needsData: true };
  E.title = function () { return t('edit'); };
  E.render = function (r) {
    var e = RBC.data.bySlug[r.param];
    if (!RBC.db.caps.auth) return F.soon('edit');
    if (!e) return '<div class="view--narrow">' + ui.state('hidden', { h: 'h1', focus: true, title: t('profile.unavailable'), text: t('profile.unavailable_text') }) + '</div>';
    return gate('edit', r) || shell('edit', t('edit.lead'), { href: RBC.href('profile', e.slug), label: t('form.back_profile') });
  };
  E.mount = function (el, r) {
    var e = RBC.data.bySlug[r.param]; if (!e || !RBC.db.caps.auth || !gateMount(el)) return;
    var box = RBC.qs('#acbox', el);
    A.loadMe(true).then(function () {
      if (!A.manages(e.id)) { box.innerHTML = ui.state('forbidden', { title: t('edit.not_manager'), text: t('edit.not_manager_text'), actions: ui.btn(t('act.claim'), { href: RBC.href('claim', e.slug), icon: 'key' }) }); return; }
      box.innerHTML = F.entityHead(e) + '<form id="edform" class="careform" novalidate>' + ui.errsum() +
        '<h2 class="h3">' + esc(t('edit.direct')) + '</h2><p class="hint">' + esc(t('edit.direct_hint')) + '</p>' +
        ui.input({ name: 'desc_pt', label: t('edit.desc_pt'), multiline: true, rows: 3, maxlength: 2000, value: e.summary_pt || '' }) +
        ui.input({ name: 'desc_en', label: t('edit.desc_en'), multiline: true, rows: 3, maxlength: 2000, value: e.summary_en || '' }) +
        ui.input({ name: 'website', label: t('profile.own_site'), type: 'url', maxlength: 300, value: e.own_url || '' }) +
        ui.input({ name: 'contact_url', label: t('edit.contact_url'), type: 'url', maxlength: 300, hint: esc(t('edit.contact_url_hint')) }) +
        ui.group({ name: 'categories', label: t('profile.families'), compact: true, cols: true, value: e.categories, options: RBC.FAMILIES.map(function (f) { return [f, RBC.famLabel(f), '', '', f]; }) }) +
        ui.select({ name: 'primary', label: t('edit.primary'), value: e.categories[0] || '', options: RBC.FAMILIES.map(function (f) { return [f, RBC.famLabel(f)]; }) }) +
        '<h2 class="h3">' + esc(t('edit.review')) + '</h2><p class="hint">' + esc(t('edit.review_hint')) + '</p>' +
        ui.input({ name: 'name', label: t('suggest.name'), maxlength: 180, value: e.name }) +
        ui.select({ name: 'country', label: t('suggest.country'), value: e.country || '', placeholder: t('suggest.country_none'), options: F.countryOptions() }) +
        '<p class="actions">' + ui.btn(t('edit.save'), { type: 'submit', icon: 'check' }) + '</p></form><div class="formout"></div>' +
        '<section class="psec"><h2 class="h3">' + esc(t('edit.withdraw')) + '</h2><p>' + esc(t('edit.withdraw_text')) + '</p><p>' + ui.btn(t('edit.withdraw_btn'), { kind: 'danger', small: true, attrs: 'data-self-withdraw', icon: 'eye-off' }) + '</p></section>';
      var form = RBC.qs('#edform', box);
      form.addEventListener('submit', function (ev) {
        ev.preventDefault(); var v = ui.read(form), p = {}, errs = [];
        if ((v.desc_pt || '') !== (e.summary_pt || '') || (v.desc_en || '') !== (e.summary_en || '')) { p.descriptions = {}; if (v.desc_pt) p.descriptions.pt = v.desc_pt; if (v.desc_en) p.descriptions.en = v.desc_en; }
        if ((v.website || '') !== (e.own_url || '')) { if (v.website && !RBC.safeUrl(v.website)) errs.push(['website', t('form.err.url')]); p.website_url = v.website || null; }
        if (v.contact_url) { if (!/^https:\/\/\S+$/.test(v.contact_url)) errs.push(['contact_url', t('form.err.https')]); p.contact_url = v.contact_url; }
        var cats = v.categories || [];
        if (cats.join() !== e.categories.join() || v.primary !== e.categories[0]) {
          if (!cats.length) errs.push(['categories', t('edit.err.cats')]);
          else { if (cats.indexOf(v.primary) < 0) cats.unshift(v.primary); p.categories = cats; p.primary_category = v.primary; }
        }
        if (v.name && v.name !== e.name) p.name = v.name;
        if ((v.country || '') !== (e.country || '')) p.country_code = v.country || null;
        if (!ui.showErrors(form, errs)) return;
        if (!Object.keys(p).length) { F.result(RBC.qs('.formout', box), 'ok', t('edit.nothing')); return; }
        F.submit(form, RBC.qs('[type=submit]', form), function () { return RBC.db.call('manager_update', { p_entity: e.id, p_payload: p }); }, function (res) {
          RBC.reloadData();
          return [t('edit.ok'), '<p>' + esc(t('edit.ok_applied', { list: (res.applied || []).join(', ') || '—' })) + '</p>' + (res.pending_version_id ? '<p>' + esc(t('edit.ok_pending')) + '</p>' : '')];
        });
      });
      RBC.qs('[data-self-withdraw]', box).addEventListener('click', function (ev) {
        if (!window.confirm(t('edit.withdraw_confirm'))) return;
        var b = ev.currentTarget; b.disabled = true;
        RBC.db.call('withdraw_entity', { p_entity: e.id, p_reason_code: 'holder_request' }).then(function () { RBC.dropLocal(e.slug); F.result(RBC.qs('.formout', box), 'ok', t('withdraw.ok_hidden')); }, function (err) { b.disabled = false; F.result(RBC.qs('.formout', box), 'error', F.errMsg(err)); });
      });
    }, fail(box));
  };

  /* ---------- Conectar (pedido mediado; contatos só depois do aceite) ---------- */
  var N = RBC.views.connect = { needsData: true };
  N.title = function () { return t('connect'); };
  N.render = function (r) {
    var e = RBC.data.bySlug[r.param];
    if (!RBC.db.caps.auth) return F.soon('connect');
    if (!e) return '<div class="view--narrow">' + ui.state('hidden', { h: 'h1', focus: true, title: t('profile.unavailable'), text: t('profile.unavailable_text') }) + '</div>';
    return gate('connect', r, 'connect.login_reason') || shell('connect', t('connect.lead'), { href: RBC.href('profile', e.slug), label: t('form.back_profile') });
  };
  N.mount = function (el, r) {
    var e = RBC.data.bySlug[r.param]; if (!e || !RBC.db.caps.auth || !gateMount(el)) return;
    var box = RBC.qs('#acbox', el);
    A.loadMe(true).then(function (me) {
      var mine = (me.managed || []).filter(function (m) { return m.entity_id !== e.id; });
      if (!mine.length) { box.innerHTML = ui.state('forbidden', { title: t('connect.need_managed'), text: t('connect.need_managed_text'), actions: ui.btn(t('act.claim'), { href: RBC.href('claim'), icon: 'key' }) }); return; }
      box.innerHTML = F.entityHead(e) + ui.notice('care', '<p>' + esc(t('connect.privacy')) + '</p>') + '<form id="cnform" class="careform" novalidate>' + ui.errsum() +
        ui.select({ name: 'from', label: t('connect.from'), required: true, value: mine[0].entity_id, options: mine.map(function (m) { return [m.entity_id, m.name]; }) }) +
        ui.input({ name: 'message', label: t('connect.message'), multiline: true, required: true, maxlength: 1000 }) +
        ui.input({ name: 'contact', label: t('connect.contact'), required: true, maxlength: 300, hint: esc(t('connect.contact_hint')) }) +
        '<p class="actions">' + ui.btn(t('connect.send'), { type: 'submit', icon: 'send' }) + '</p></form><div class="formout"></div>';
      var form = RBC.qs('#cnform', box);
      form.addEventListener('submit', function (ev) {
        ev.preventDefault(); var v = ui.read(form), errs = [];
        if (!F.len(v.message, 10, 1000)) errs.push(['message', t('form.err.len', { min: 10, max: 1000 })]);
        if (!F.len(v.contact, 5, 300)) errs.push(['contact', t('form.err.len', { min: 5, max: 300 })]);
        if (!ui.showErrors(form, errs)) return;
        F.submit(form, RBC.qs('[type=submit]', form), function () { return RBC.db.call('connect_request', { p_from_entity: v.from, p_to_entity: e.id, p_message: v.message, p_contact: v.contact }); },
          function () { return [t('connect.ok'), '<p>' + esc(t('connect.ok_text')) + '</p>']; });
      });
    }, fail(box));
  };

  /* ---------- Ofertas e necessidades: mural público + gestão pelas fichas reivindicadas ---------- */
  var O = RBC.views.offers = { needsData: true };
  O.title = function () { return t('offers'); };
  O.render = function (r) {
    if (!RBC.db.caps.write) return F.soon('offers', { extra: '<p>' + esc(t('offers.soon_extra')) + '</p>' });
    return '<div>' + ui.pageHead({ eyebrow: t('join.eyebrow'), title: t('offers'), lead: t('offers.lead') }) +
      '<div class="twocol"><section class="psec" aria-labelledby="of-feed"><h2 id="of-feed">' + esc(t('offers.feed')) + '</h2><div id="offeed">' + ui.loading(1) + '</div></section>' +
      '<section class="psec" aria-labelledby="of-mine"><h2 id="of-mine">' + esc(t('offers.mine')) + '</h2><div id="ofmine">' + (RBC.state.session ? ui.loading(1) : loginBox('offers.login_reason')) + '</div></section></div></div>';
  };
  O.mount = function (el, r) {
    if (!RBC.db.caps.write) return;
    var feed = RBC.qs('#offeed', el), mine = RBC.qs('#ofmine', el);
    RBC.db.offersFeed().then(function (list) {
      feed.innerHTML = list.length ? '<ul class="cooplist">' + list.map(function (o) {
        return '<li class="coop coop--' + (o.kind === 'offer' ? 'offer' : 'need') + '"><p class="eyebrow">' + esc(t('offer.kind.' + o.kind)) + ' · ' + esc(t('offer.topic.' + o.topic)) + '</p><h3 class="h4">' + esc(o.title) + '</h3>' +
          (o.description ? '<p>' + esc(o.description) + '</p>' : '') + '<p class="hint"><a href="' + RBC.href('profile', o.entity_slug) + '">' + esc(o.entity_name) + '</a> · ' + esc((o.city ? o.city + ', ' : '') + RBC.countryName(o.country_code)) + ' · ' + esc(t('offer.until', { date: RBC.fmtDate(o.valid_until) })) + '</p></li>';
      }).join('') + '</ul>' : '<p class="muted">' + esc(t('offers.feed_none')) + '</p>';
    }, fail(feed));
    if (!RBC.state.session) { mountLogin(el, window.location.hash); return; }
    Promise.all([A.loadMe(true), RBC.db.call('my_offers_needs', {})]).then(function (res) {
      var managed = res[0].managed || [], items = res[1] || [];
      if (!managed.length) { mine.innerHTML = '<p class="muted">' + esc(t('offers.need_managed')) + '</p><p>' + ui.btn(t('act.claim'), { href: RBC.href('claim'), icon: 'key', kind: 'secondary' }) + '</p>'; return; }
      var pre = r.param && RBC.data.bySlug[r.param] ? RBC.data.bySlug[r.param].id : managed[0].entity_id;
      var d90 = new Date(Date.now() + 90 * 864e5).toISOString().slice(0, 10), today = new Date().toISOString().slice(0, 10), max = new Date(Date.now() + 365 * 864e5).toISOString().slice(0, 10);
      mine.innerHTML = (items.length ? '<ul class="cooplist">' + items.map(function (o) {
        return '<li class="coop coop--' + (o.kind === 'offer' ? 'offer' : 'need') + '"><p class="eyebrow">' + esc(t('offer.kind.' + o.kind)) + ' · ' + esc(t('offer.topic.' + o.topic)) + (o.expired ? ' · ' + esc(t('offer.expired')) : '') + '</p><h3 class="h4">' + esc(o.title) + '</h3><p class="hint">' + esc(t('offer.until', { date: RBC.fmtDate(o.valid_until) })) + '</p>' +
          '<p>' + ui.btn(t('offer.remove'), { small: true, kind: 'ghost', attrs: 'data-remove="' + esc(o.id) + '"', icon: 'trash' }) + '</p></li>';
      }).join('') + '</ul>' : '<p class="muted">' + esc(t('offers.mine_none')) + '</p>') +
        '<form id="ofform" class="careform" novalidate><h3>' + esc(t('offers.new')) + '</h3>' + ui.errsum() +
        ui.select({ name: 'entity', label: t('offers.entity'), required: true, value: pre, options: managed.map(function (m) { return [m.entity_id, m.name]; }) }) +
        ui.group({ name: 'kind', type: 'radio', label: t('offers.kind'), required: true, value: 'offer', options: [['offer', t('offer.kind.offer')], ['need', t('offer.kind.need')]] }) +
        ui.select({ name: 'topic', label: t('offers.topic'), required: true, value: 'tools', options: ['tools', 'space', 'volunteering', 'knowledge', 'materials', 'other'].map(function (k) { return [k, t('offer.topic.' + k)]; }) }) +
        ui.input({ name: 'title', label: t('offers.title_f'), required: true, maxlength: 140 }) +
        ui.input({ name: 'description', label: t('offers.description'), multiline: true, rows: 3, maxlength: 2000 }) +
        ui.input({ name: 'valid_until', label: t('offers.valid_until'), type: 'date', required: true, value: d90, attrs: 'min="' + today + '" max="' + max + '"', hint: esc(t('offers.valid_hint')) }) +
        '<p class="actions">' + ui.btn(t('offers.publish'), { type: 'submit', icon: 'plus' }) + '</p></form><div class="formout"></div>';
      var form = RBC.qs('#ofform', mine);
      form.addEventListener('submit', function (ev) {
        ev.preventDefault(); var v = ui.read(form), errs = [];
        if (!F.len(v.title, 3, 140)) errs.push(['title', t('form.err.len', { min: 3, max: 140 })]);
        if (!v.valid_until || v.valid_until < today || v.valid_until > max) errs.push(['valid_until', t('offers.err.date')]);
        if (!ui.showErrors(form, errs)) return;
        F.submit(form, RBC.qs('[type=submit]', form), function () { return RBC.db.call('offer_need_upsert', { p_id: null, p_entity: v.entity, p_kind: v.kind, p_topic: v.topic, p_title: v.title, p_description: v.description || null, p_valid_until: v.valid_until }); },
          function () { return [t('offers.ok'), '<p>' + ui.btn(t('state.reload'), { attrs: 'data-reload-view', small: true, icon: 'refresh' }) + '</p>']; });
      });
      mine.addEventListener('click', function (ev) {
        var b = ev.target.closest('[data-remove],[data-reload-view]'); if (!b) return;
        if (b.hasAttribute('data-reload-view')) { RBC.render(); return; }
        RBC.db.call('offer_need_remove', { p_id: b.getAttribute('data-remove') }).then(function () { RBC.render(); }, function (err) { RBC.announce(F.errMsg(err)); });
      });
    }, fail(mine));
  };

  /* ---------- Painel editorial (moderador) ---------- */
  var QUEUES = ['takedowns', 'claims', 'reports', 'suggestions', 'contact', 'edits', 'invite_candidates', 'invitations'];
  var DECIDE = {
    takedowns: { opts: ['confirm', 'restore', 'reject_keep_hidden'], call: function (id, d, note) { return ['mod_decide_takedown', { p_request: id, p_decision: d, p_rationale: note }]; } },
    claims: { opts: ['approve', 'reject'], call: function (id, d, note) { return ['mod_decide_claim', { p_claim: id, p_approve: d === 'approve', p_rationale: note }]; } },
    reports: { opts: ['triaged', 'actioned', 'closed'], call: function (id, d, note) { return ['triage_report', { p_report: id, p_status: d, p_note: note }]; } },
    suggestions: { opts: ['accepted', 'rejected', 'duplicate'], call: function (id, d, note) { return ['mod_decide_suggestion', { p_id: id, p_status: d, p_note: note }]; } },
    contact: { opts: ['read', 'answered', 'spam'], call: function (id, d) { return ['mod_mark_contact', { p_id: id, p_status: d }]; } },
    edits: { opts: ['approve', 'reject', 'request_changes'], call: function (id, d, note) { return ['review_version', { p_version: id, p_decision: d, p_kind: 'publication', p_rationale: note }]; } },
    invite_candidates: { opts: ['create_invite'], call: function (id) { return ['mod_create_invite', { p_candidate: id, p_days: 30 }]; } },
    invitations: { opts: ['revoke'], call: function (id) { return ['mod_revoke_invite', { p_invitation: id }]; } }
  };
  var mq = { queue: 'takedowns', offset: 0 };
  var P = RBC.views.moderation = { needsData: false };
  P.title = function () { return t('nav.moderation'); };
  P.render = function (r) { return gate('nav.moderation', r) || '<div>' + ui.pageHead({ eyebrow: t('account.eyebrow'), title: t('nav.moderation'), lead: t('mod.lead') }) + '<div id="acbox">' + ui.loading(1) + '</div></div>'; };
  function fmtVal(v) {
    if (v == null || v === '') return '—';
    if (Array.isArray(v)) return v.map(fmtVal).join(', ');
    if (typeof v === 'object') return esc(JSON.stringify(v));
    if (/^\d{4}-\d{2}-\d{2}T/.test(String(v))) return esc(RBC.fmtDateTime(v));
    if (RBC.safeUrl(v)) return ui.extLink(v);
    return esc(String(v));
  }
  P.mount = function (el) {
    if (!gateMount(el)) return;
    var box = RBC.qs('#acbox', el);
    A.loadMe(true).then(function () {
      if (!A.isMod()) { box.innerHTML = ui.state('forbidden', { title: t('mod.forbidden'), text: t('mod.forbidden_text') }); return; }
      return RBC.db.call('mod_queue_counts', {}).then(function (counts) {
        box.innerHTML = '<div class="seg seg--wrap" role="group" aria-label="' + esc(t('mod.queues')) + '">' + QUEUES.map(function (q) {
          var n = counts && counts[q] != null ? counts[q] : (q === 'invitations' ? (counts && counts.invites_pending) : null);
          return '<button type="button" data-queue="' + q + '" aria-pressed="' + (mq.queue === q) + '"><span>' + esc(t('mod.q.' + q)) + (n != null ? ' (' + n + ')' : '') + '</span></button>';
        }).join('') + '</div><div id="mqbox" aria-live="polite"></div>';
        box.addEventListener('click', function (ev) { var b = ev.target.closest('[data-queue]'); if (!b) return; mq.queue = b.getAttribute('data-queue'); mq.offset = 0; RBC.qsa('[data-queue]', box).forEach(function (x) { x.setAttribute('aria-pressed', x === b ? 'true' : 'false'); }); loadQueue(RBC.qs('#mqbox', box)); });
        loadQueue(RBC.qs('#mqbox', box));
      });
    }).then(null, fail(box));
  };
  function loadQueue(qb) {
    qb.innerHTML = ui.loading(1);
    RBC.db.call('mod_list', { p_queue: mq.queue, p_status: null, p_limit: 50, p_offset: mq.offset }).then(function (items) {
      items = items || [];
      var dec = DECIDE[mq.queue];
      qb.innerHTML = '<h2 class="h3" tabindex="-1" id="mq-h">' + esc(t('mod.q.' + mq.queue)) + ' · ' + esc(t('mod.n', { n: items.length })) + '</h2>' +
        (items.length ? '<ul class="mlist">' + items.map(function (it, i) {
          var id = it.id || it.request_id || it.claim_id || it.version_id || it.invitation_id || it.candidate_id;
          var rows = Object.keys(it).filter(function (k) { return !/^(id|request_id|claim_id|version_id|invitation_id|candidate_id)$/.test(k); }).map(function (k) { return [k, fmtVal(it[k])]; });
          return '<li class="qitem"><div class="qitem__grid">' + ui.dl(rows) + '</div>' +
            '<form class="decform" data-id="' + esc(id) + '" novalidate>' +
            ui.select({ name: 'decision_' + i, label: t('mod.decision'), noTag: true, options: dec.opts.map(function (o) { return [o, t('mod.d.' + o)]; }) }) +
            (mq.queue === 'contact' || mq.queue === 'invite_candidates' || mq.queue === 'invitations' ? '' : ui.input({ name: 'note_' + i, label: t('mod.rationale'), multiline: true, rows: 2, maxlength: 2000, noTag: true })) +
            '<p class="actions">' + ui.btn(t('mod.apply'), { type: 'submit', small: true, icon: 'check' }) + '</p><div class="formout"></div></form></li>';
        }).join('') + '</ul>' : '<p class="muted">' + esc(t('mod.empty')) + '</p>') +
        '<p class="actions actions--wrap">' + (mq.offset ? ui.btn(t('pager.prev'), { small: true, kind: 'quiet', attrs: 'data-mq-prev' }) : '') + (items.length === 50 ? ui.btn(t('pager.next'), { small: true, kind: 'quiet', attrs: 'data-mq-next' }) : '') + '</p>';
      qb.onclick = function (ev) { var b = ev.target.closest('[data-mq-prev],[data-mq-next]'); if (!b) return; mq.offset = Math.max(0, mq.offset + (b.hasAttribute('data-mq-next') ? 50 : -50)); loadQueue(qb); };
      qb.onsubmit = function (ev) {
        var f = ev.target; if (!f.hasAttribute('data-id')) return; ev.preventDefault();
        var sel = RBC.qs('select', f), ta = RBC.qs('textarea', f), note = ta ? ta.value.trim() : null, d = sel.value;
        if (ta && /restore|approve|reject|request_changes/.test(d) && note.length < 10) { ui.showErrors(f, [[ta.name, t('mod.err.rationale')]]); return; }
        var c = dec.call(f.getAttribute('data-id'), d, note), out = RBC.qs('.formout', f), btn = RBC.qs('[type=submit]', f); btn.disabled = true;
        RBC.db.call(c[0], c[1]).then(function (res) {
          F.result(out, 'ok', t('mod.done'), res && res.token ? '<p>' + esc(t('mod.invite_link')) + '</p><p class="codebox"><code>' + esc(RBC.cfg.siteUrl.replace(/\/$/, '') + '/' + (res.path || '#convite-' + res.token)) + '</code></p><p class="hint">' + esc(t('mod.invite_once')) + '</p>' : '');
          if (c[0] === 'mod_decide_takedown') RBC.reloadData();
        }, function (err) { btn.disabled = false; F.result(out, 'error', F.errMsg(err)); });
      };
      RBC.focusEl(RBC.qs('#mq-h', qb));
    }, fail(qb));
  }
})();
