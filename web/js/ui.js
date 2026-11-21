/* Componentes compartilhados: botões, cabeçalhos, selos de atividade, cartões, estados, formulários. */
(function () {
  'use strict';
  var RBC = window.RBC, t = RBC.t, esc = RBC.esc, icon = RBC.icon;
  var ui = RBC.ui = {};

  ui.btn = function (label, opts) {
    opts = opts || {};
    var cls = 'btn' + (opts.kind ? ' btn--' + opts.kind : ' btn--primary') + (opts.small ? ' btn--sm' : '');
    var ic = opts.icon ? icon(opts.icon) : '', ic2 = opts.iconAfter ? icon(opts.iconAfter) : '';
    if (opts.href) return '<a class="' + cls + '" href="' + esc(opts.href) + '"' + (opts.attrs ? ' ' + opts.attrs : '') + '>' + ic + '<span>' + esc(label) + '</span>' + ic2 + '</a>';
    return '<button type="' + (opts.type || 'button') + '" class="' + cls + '"' + (opts.attrs ? ' ' + opts.attrs : '') + '>' + ic + '<span>' + esc(label) + '</span>' + ic2 + '</button>';
  };
  ui.pageHead = function (o) {
    return '<header class="page-head' + (o.narrow ? ' page-head--narrow' : '') + '">' +
      (o.back ? '<p class="page-head__back"><a class="backlink" href="' + esc(o.back.href) + '">' + icon('arrow-left') + '<span>' + esc(o.back.label) + '</span></a></p>' : '') +
      (o.eyebrow ? '<p class="eyebrow">' + esc(o.eyebrow) + '</p>' : '') +
      '<h1 id="page-title" tabindex="-1">' + esc(o.title) + '</h1>' +
      (o.lead ? '<p class="lead">' + esc(o.lead) + '</p>' : '') + '</header>';
  };

  /* ---------- selo de atividade: diz exatamente o que foi conferido ---------- */
  ui.stamp = function (kind, text) {
    var ic = { source: 'source', activity: 'check-circle', managed: 'key', unconfirmed: 'hourglass', pending: 'clock', hidden: 'eye-off', published: 'eye', correction: 'flag' }[kind] || 'info';
    return '<span class="stamp stamp--' + kind + '">' + icon(ic) + '<span>' + esc(text) + '</span></span>';
  };
  ui.badgeText = function (e) {
    if (e.activity_badge === 'active_recent') return t('badge.active', { year: String(e.last_activity || '2026').slice(0, 4) });
    if (e.activity_badge === 'source_checked') return t('badge.source', { date: RBC.fmtMonthShort((RBC.dataMeta && RBC.dataMeta.source_checked_month) || '2026-11') });
    return t('badge.confirm');
  };
  ui.badge = function (e) {
    var k = e.activity_badge === 'active_recent' ? 'activity' : e.activity_badge === 'source_checked' ? 'source' : 'unconfirmed';
    return ui.stamp(k, ui.badgeText(e));
  };
  ui.famChip = function (id, link) {
    var inner = icon(id) + '<span>' + esc(RBC.famLabel(id)) + '</span>';
    return link ? '<a class="chip chip--fam" href="' + RBC.href('explore') + '" data-fam-link="' + id + '">' + inner + '</a>' : '<span class="chip chip--fam">' + inner + '</span>';
  };
  ui.precision = function (e) {
    var p = e.location_precision === 'city' ? 'city' : 'none';
    return '<span class="prec prec--' + p + '">' + icon(p === 'city' ? 'ring' : 'nomap') + '<span>' + esc(t('precision.' + p)) + '</span></span>';
  };
  /* resumo no idioma da interface; EN é tradução automática e diz isso */
  ui.summary = function (e) {
    if (RBC.state.lang === 'en' && e.summary_en) return { text: e.summary_en, lang: 'en', note: t('tr.machine_short') };
    if (RBC.state.lang === 'en') return { text: e.summary_pt, lang: 'pt', note: t('tr.only_pt') };
    return { text: e.summary_pt || '', lang: 'pt', note: null };
  };
  ui.card = function (e, opts) {
    opts = opts || {};
    var H = opts.h || 'h3', s = ui.summary(e), main = e.categories[0] || 'sprout';
    var fams = e.categories.slice(0, 2).map(function (f) { return '<li>' + ui.famChip(f) + '</li>'; }).join('') +
      (e.categories.length > 2 ? '<li><span class="chip chip--more">' + esc(t('card.more_areas', { n: e.categories.length - 2 })) + '</span></li>' : '');
    return '<article class="card fcard">' +
      '<div class="fcard__top"><span class="blob blob--' + (e.name.length % 4) + '" aria-hidden="true">' + icon(main) + '</span>' +
      '<div class="fcard__head"><p class="eyebrow">' + esc(t('kind.' + e.kind)) + ' · ' + esc(RBC.where(e)) + '</p>' +
      '<' + H + ' class="fcard__name"><a href="' + RBC.href('profile', e.slug) + '">' + esc(e.name) + '</a></' + H + '></div></div>' +
      (s.text ? '<p class="fcard__text" lang="' + s.lang + '">' + esc(s.text) + '</p>' : '') +
      (s.note ? '<p class="trnote">' + icon('translate') + '<span>' + esc(s.note) + '</span></p>' : '') +
      (fams ? '<ul class="chips">' + fams + '</ul>' : '') +
      '<p class="fcard__meta">' + ui.precision(e) + '</p>' +
      '<ul class="stamps" aria-label="' + esc(t('badge.group')) + '"><li>' + ui.badge(e) + '</li></ul>' +
      '</article>';
  };
  ui.cards = function (list, opts) { return '<ul class="cards' + (opts && opts.cls ? ' ' + opts.cls : '') + '">' + list.map(function (e) { return '<li>' + ui.card(e, opts) + '</li>'; }).join('') + '</ul>'; };

  /* ---------- paginação em janela ---------- */
  ui.pager = function (page, pages) {
    if (pages < 2) return '';
    var nums = [], i, b = '';
    for (i = 1; i <= pages; i++) if (i === 1 || i === pages || Math.abs(i - page) <= 1) nums.push(i);
    b += '<li><button type="button" class="btn btn--quiet btn--sm" data-page="' + (page - 1) + '"' + (page === 1 ? ' disabled' : '') + '>' + icon('chev-left') + '<span>' + esc(t('pager.prev')) + '</span></button></li>';
    nums.forEach(function (n, k) {
      if (k && n - nums[k - 1] > 1) b += '<li class="pager__gap" aria-hidden="true">…</li>';
      b += '<li><button type="button" class="pgnum" data-page="' + n + '"' + (n === page ? ' aria-current="page"' : '') + ' aria-label="' + esc(t('pager.page', { n: n, total: pages })) + '">' + n + '</button></li>';
    });
    b += '<li><button type="button" class="btn btn--quiet btn--sm" data-page="' + (page + 1) + '"' + (page === pages ? ' disabled' : '') + '><span>' + esc(t('pager.next')) + '</span>' + icon('chev-right') + '</button></li>';
    return '<nav class="pager" aria-label="' + esc(t('pager.label')) + '"><ul>' + b + '</ul></nav>';
  };

  /* ---------- estados ---------- */
  ui.state = function (kind, o) {
    o = o || {};
    var ic = { empty: 'sprout', noresults: 'search', error: 'alert', forbidden: 'lock', pending: 'hourglass', soon: 'clock', ok: 'check-circle', hidden: 'eye-off', notfound: 'compass' }[kind] || 'info';
    return '<div class="state state--' + kind + '"' + (kind === 'error' ? ' role="alert"' : '') + '>' +
      '<span class="blob blob--2 state__ic" aria-hidden="true">' + icon(ic) + '</span>' +
      '<div class="state__body"><' + (o.h || 'h2') + ' class="state__title"' + (o.focus ? ' id="page-title" tabindex="-1"' : '') + '>' + esc(o.title || '') + '</' + (o.h || 'h2') + '>' +
      (o.html || (o.text ? '<p>' + esc(o.text) + '</p>' : '')) + (o.extra || '') +
      (o.actions ? '<div class="actions">' + o.actions + '</div>' : '') + '</div></div>';
  };
  ui.loading = function (n, label) {
    var cards = ''; for (var i = 0; i < (n || 6); i++) cards += '<li class="card skel" aria-hidden="true"><span class="skel__blob"></span><span class="skel__l skel__l--s"></span><span class="skel__l skel__l--t"></span><span class="skel__l"></span><span class="skel__l"></span><span class="skel__l skel__l--m"></span></li>';
    return '<div class="loading" role="status" aria-busy="true"><p class="loading__label"><span class="spinner" aria-hidden="true"></span>' + esc(label || t('state.loading')) + '</p><ul class="cards cards--skel">' + cards + '</ul></div>';
  };
  ui.notice = function (kind, html, ic) { return '<div class="notice notice--' + kind + '">' + icon(ic || (kind === 'care' ? 'shield' : kind === 'warn' ? 'alert' : 'info')) + '<div>' + html + '</div></div>'; };
  ui.dl = function (rows) { return '<dl class="dl">' + rows.filter(Boolean).map(function (r) { return '<div><dt>' + esc(r[0]) + '</dt><dd>' + r[1] + '</dd></div>'; }).join('') + '</dl>'; };
  ui.ul = function (items, cls) { return '<ul class="' + (cls || 'bullets') + '">' + items.map(function (i) { return '<li>' + i + '</li>'; }).join('') + '</ul>'; };
  ui.extLink = function (url, label) { var u = RBC.safeUrl(url); return u ? '<a class="url" href="' + esc(u) + '" rel="noopener noreferrer" target="_blank">' + esc(label || u) + '<span class="sr"> ' + esc(t('a11y.new_tab')) + '</span></a>' : ''; };

  /* antispam simples: campo-isca invisível + tempo mínimo de preenchimento */
  ui.honeypot = function () {
    return '<div class="hp" aria-hidden="true"><label for="f-website">Website</label><input type="text" id="f-website" name="website" tabindex="-1" autocomplete="off"></div>';
  };
  ui.spamCheck = function (form, startedAt, minMs) {
    var hp = RBC.qs('[name="website"]', form);
    if (hp && hp.value) return 'honeypot';
    if (Date.now() - startedAt < (minMs || 3000)) return 'too_fast';
    return null;
  };
  /* ---------- formulários ---------- */
  function hintErr(id, hint) { return (hint ? '<p class="hint" id="' + id + '-hint">' + hint + '</p>' : '') ; }
  function describedBy(id, hint) { return ' aria-describedby="' + (hint ? id + '-hint ' : '') + id + '-err"'; }
  function reqTag(req) { return req ? ' <span class="req">' + esc(t('form.required')) + '</span>' : ' <span class="opt-tag">' + esc(t('form.optional')) + '</span>'; }
  ui.input = function (o) {
    var id = 'f-' + o.name, tag = o.multiline ? 'textarea' : 'input';
    var attrs = ' id="' + id + '" name="' + o.name + '"' + describedBy(id, o.hint) + (o.required ? ' aria-required="true"' : '') + (o.attrs ? ' ' + o.attrs : '') + (o.maxlength ? ' maxlength="' + o.maxlength + '"' : '');
    var ctl = o.multiline ? '<textarea rows="' + (o.rows || 4) + '"' + attrs + '>' + esc(o.value || '') + '</textarea>' : '<input type="' + (o.type || 'text') + '"' + attrs + ' value="' + esc(o.value || '') + '"' + (o.list ? ' list="' + o.list + '"' : '') + (o.autocomplete ? ' autocomplete="' + o.autocomplete + '"' : ' autocomplete="off"') + '>';
    return '<div class="field" data-field="' + o.name + '"><label for="' + id + '">' + esc(o.label) + (o.noTag ? '' : reqTag(o.required)) + '</label>' + hintErr(id, o.hint) + ctl + '<p class="err" id="' + id + '-err" hidden></p></div>';
  };
  ui.select = function (o) {
    var id = 'f-' + o.name;
    var opts = (o.placeholder ? '<option value="">' + esc(o.placeholder) + '</option>' : '') + o.options.map(function (op) { return '<option value="' + esc(op[0]) + '"' + (String(o.value) === String(op[0]) ? ' selected' : '') + '>' + esc(op[1]) + '</option>'; }).join('');
    return '<div class="field" data-field="' + o.name + '"><label for="' + id + '">' + esc(o.label) + (o.noTag ? '' : reqTag(o.required)) + '</label>' + hintErr(id, o.hint) +
      '<div class="selectwrap"><select id="' + id + '" name="' + o.name + '"' + describedBy(id, o.hint) + (o.required ? ' aria-required="true"' : '') + (o.attrs ? ' ' + o.attrs : '') + '>' + opts + '</select>' + icon('chev-down') + '</div><p class="err" id="' + id + '-err" hidden></p></div>';
  };
  /* grupo de opções (checkbox ou radio) */
  ui.group = function (o) {
    var id = 'f-' + o.name, type = o.type || 'checkbox', vals = o.value == null ? [] : [].concat(o.value);
    var items = o.options.map(function (op, i) {
      var v = op[0], oid = id + '-' + i, checked = vals.indexOf(v) >= 0;
      return '<label class="opt' + (o.compact ? ' opt--compact' : '') + '" for="' + oid + '"><input type="' + type + '" id="' + oid + '" name="' + o.name + '" value="' + esc(v) + '"' + (checked ? ' checked' : '') + (op[3] ? ' ' + op[3] : '') + '>' +
        (op[4] ? icon(op[4]) : '') + '<span class="opt__body"><span class="opt__label">' + esc(op[1]) + '</span>' + (op[2] ? '<span class="opt__hint">' + esc(op[2]) + '</span>' : '') + '</span></label>';
    }).join('');
    return '<fieldset class="field field--group" data-field="' + o.name + '" aria-describedby="' + (o.hint ? id + '-hint ' : '') + id + '-err"><legend>' + esc(o.label) + (o.noTag ? '' : reqTag(o.required)) + '</legend>' + hintErr(id, o.hint) +
      '<div class="opts' + (o.cols ? ' opts--cols' : '') + (o.compact ? ' opts--compact' : '') + '">' + items + '</div><p class="err" id="' + id + '-err" hidden></p></fieldset>';
  };
  ui.check = function (o) {
    var id = 'f-' + o.name;
    return '<div class="field field--check" data-field="' + o.name + '"><label class="opt opt--consent" for="' + id + '"><input type="checkbox" id="' + id + '" name="' + o.name + '"' + (o.value ? ' checked' : '') + ' aria-describedby="' + id + '-err"' + (o.required ? ' aria-required="true"' : '') + '>' +
      '<span class="opt__body"><span class="opt__label">' + esc(o.label) + (o.required ? ' <span class="req">' + esc(t('form.required')) + '</span>' : '') + '</span>' + (o.hint ? '<span class="opt__hint">' + o.hint + '</span>' : '') + '</span></label><p class="err" id="' + id + '-err" hidden></p></div>';
  };

  ui.clearErrors = function (root) {
    RBC.qsa('.err', root).forEach(function (p) { p.hidden = true; p.textContent = ''; });
    RBC.qsa('[aria-invalid]', root).forEach(function (el) { el.removeAttribute('aria-invalid'); });
    RBC.qsa('.field--bad', root).forEach(function (el) { el.classList.remove('field--bad'); });
    var s = RBC.qs('.errsum', root); if (s) { s.hidden = true; s.innerHTML = ''; }
  };
  /* errors: [[nomeDoCampo, mensagem]] */
  ui.showErrors = function (root, errors) {
    ui.clearErrors(root);
    if (!errors.length) return true;
    var items = '';
    errors.forEach(function (er) {
      var f = RBC.qs('[data-field="' + er[0] + '"]', root); if (!f) return;
      f.classList.add('field--bad');
      var p = RBC.qs('.err', f); if (p) { p.hidden = false; p.innerHTML = icon('alert') + '<span>' + esc(er[1]) + '</span>'; }
      var ctl = RBC.qs('input,select,textarea', f); if (ctl) { RBC.qsa('input,select,textarea', f).forEach(function (c) { c.setAttribute('aria-invalid', 'true'); }); }
      items += '<li><a href="#" data-goto="' + (ctl ? ctl.id : '') + '">' + esc(er[1]) + '</a></li>';
    });
    var s = RBC.qs('.errsum', root);
    if (s) {
      s.hidden = false;
      s.innerHTML = '<h2 tabindex="-1">' + icon('alert') + '<span>' + esc(t(errors.length === 1 ? 'form.errsum.one' : 'form.errsum.many', { n: errors.length })) + '</span></h2><ul>' + items + '</ul>';
      RBC.qsa('[data-goto]', s).forEach(function (a) { a.addEventListener('click', function (ev) { ev.preventDefault(); var el = document.getElementById(a.getAttribute('data-goto')); if (el) el.focus(); }); });
      RBC.focusEl(RBC.qs('h2', s));
    }
    return false;
  };
  ui.errsum = function () { return '<div class="errsum" role="alert" hidden></div>'; };

  /* leitura genérica de um formulário */
  ui.read = function (form) {
    var out = {};
    RBC.qsa('input,select,textarea', form).forEach(function (el) {
      if (!el.name) return;
      if (el.type === 'checkbox') {
        var same = RBC.qsa('input[type=checkbox][name="' + el.name + '"]', form);
        if (same.length > 1 || el.hasAttribute('data-multi')) { out[el.name] = out[el.name] || []; if (el.checked) out[el.name].push(el.value); }
        else out[el.name] = el.checked;
      } else if (el.type === 'radio') { if (el.checked) out[el.name] = el.value; else if (!(el.name in out)) out[el.name] = ''; }
      else out[el.name] = el.value.trim();
    });
    return out;
  };

})();
