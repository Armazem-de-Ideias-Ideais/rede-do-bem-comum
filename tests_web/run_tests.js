/* Testes do site público (modo static) — Playwright + Chrome do sistema, servidor local com a CSP de web/_headers.
   Uso: node tests_web/run_tests.js   → tests_web/results.json e capturas em shots/ */
const { chromium } = require('/opt/npm-tools/node_modules/playwright');
const fs = require('fs'), path = require('path');
const start = require('./serve.js'), routeFonts = require('./fontroute.js');
const ROOT = path.resolve(__dirname, '..'), WEB = path.join(ROOT, 'web'), SHOTS = path.join(ROOT, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });

const PUB = JSON.parse(fs.readFileSync(path.join(WEB, 'data', 'public.json'), 'utf8'));
const ITEMS = PUB.initiatives;
const PRIV = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'convite_alta_exposicao_PRIVADO.json'), 'utf8'));
const TRIAGE = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'triagem_resultado.json'), 'utf8'));
const ALLOWED = ['id', 'slug', 'name', 'aliases', 'kind', 'presence', 'country', 'city', 'region', 'categories', 'summary_pt', 'summary_en', 'summary_en_status', 'own_url', 'source_url', 'source_name', 'activity_badge', 'last_activity', 'city_lat', 'city_lng', 'location_precision', 'licence_note'];
const FORBIDDEN = ['research_notes', 'lot', 'exposure', 'audit', 'approved', 'evidence', 'network_of'];
const norm = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

const R = { started: new Date().toISOString(), checks: [], sweep: [], keyboard: [], profiles: [], consoleErrors: [], cspViolations: [], postRequests: [], glNoise: 0, shots: [] };
function check(name, ok, detail) { R.checks.push({ name, ok: !!ok, detail: detail === undefined ? null : detail }); console.log((ok ? 'ok   ' : 'FAIL ') + name + (ok || detail === undefined ? '' : ' → ' + JSON.stringify(detail).slice(0, 400))); }

/* ---------- 1. auditoria do public.json e dos arquivos (sem navegador) ---------- */
(function audit() {
  const keysOk = ITEMS.every(x => Object.keys(x).length === ALLOWED.length && ALLOWED.every(k => k in x));
  check('public.json: cada registro tem exatamente os 22 campos públicos', keysOk);
  const raw = fs.readFileSync(path.join(WEB, 'data', 'public.json'), 'utf8');
  const forb = FORBIDDEN.filter(k => raw.indexOf('"' + k + '"') >= 0);
  check('public.json: nenhum campo proibido (research_notes, lot, exposure, audit, approved…)', forb.length === 0, forb);
  const privIds = new Set(PRIV.map(x => x.id)), privNames = new Set(PRIV.map(x => x.name));
  const leak = ITEMS.filter(x => privIds.has(x.id)).map(x => x.id);
  check('public.json: nenhum id da lista privada de exposição alta (' + privIds.size + ' ids)', leak.length === 0, leak);
  const leakRaw = [...privIds].filter(id => raw.indexOf('"' + id + '"') >= 0);
  check('public.json: nenhum id privado em parte alguma do arquivo (busca textual)', leakRaw.length === 0, leakRaw);
  const nameLeak = ITEMS.filter(x => privNames.has(x.name) && !privIds.has(x.id)).map(x => x.name);
  R.privateNameCoincidences = nameLeak;
  const hold = new Set(TRIAGE.filter(x => x.decisao === 'segurar').map(x => x.id));
  check('public.json: nenhum registro "segurar" da triagem (' + hold.size + ')', ITEMS.every(x => !hold.has(x.id)));
  const CLOSED = ['RBC-C0105', 'RBC-C0403'];  // indício de encerramento: mesma regra do seed (build_seed.py)
  check('public.json: 1.717 − ' + hold.size + ' (segurar) − ' + CLOSED.length + ' (encerramento) = ' + ITEMS.length + ' registros', ITEMS.length === 1717 - hold.size - CLOSED.length && !ITEMS.some(x => CLOSED.includes(x.id)), ITEMS.length);
  check('public.json: coordenadas só com precisão "city"', ITEMS.every(x => (x.location_precision === 'city') === (x.city_lat != null && x.city_lng != null)));
  check('public.json: summary_en_status = "machine" sempre que há resumo EN', ITEMS.every(x => x.summary_en ? x.summary_en_status === 'machine' : x.summary_en_status === null));
  check('public.json: slugs únicos no formato da API', new Set(ITEMS.map(x => x.slug)).size === ITEMS.length && ITEMS.every(x => /^[a-z0-9]+(-[a-z0-9]+)*$/.test(x.slug) && x.slug.length <= 80));
  check('public.json: frase da Karte von Morgen literal', ITEMS.filter(x => x.licence_note).every(x => x.licence_note === 'Contém dados da Karte von Morgen / OpenFairDB, disponíveis sob ODbL'));
  // nenhum e-mail em arquivos do site (exceto bibliotecas de terceiros, verificadas à parte)
  const emailRe = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]*[A-Za-z]{2,}/g, found = [];
  (function walk(d) { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); if (fs.statSync(p).isDirectory()) { walk(p); continue; } if (!/\.(js|json|html|css|md|txt|geojson|_headers)$|_headers$/.test(f)) continue; const s = fs.readFileSync(p, 'utf8'); const m = s.match(emailRe); if (m) found.push([path.relative(WEB, p), [...new Set(m)].slice(0, 5)]); } })(WEB);
  const own = found.filter(f => !/^vendor\//.test(f[0]));
  R.emailsInVendor = found.filter(f => /^vendor\//.test(f[0]));
  check('Nenhum endereço de e-mail nos arquivos do site (fora de vendor/)', own.length === 0, own);
  check('Nenhum e-mail pessoal do moderador em lugar algum de web/ (vendor incluído)', !found.some(f => f[1].some(e => /reinehr|rafael/i.test(e))), found);
})();

/* ---------- chaves de interface PT/EN ---------- */
{
  let out = '', ok = false;
  try { out = require('child_process').execFileSync(process.execPath, [path.join(__dirname, 'check_i18n.js')], { encoding: 'utf8' }); ok = true; } catch (e) { out = String(e.stdout || e.message); }
  const j = (() => { try { return JSON.parse(out); } catch (e) { return {}; } })();
  check('i18n: ' + (j.used || '?') + ' chaves usadas, ' + (j.pt || '?') + ' em PT e ' + (j.en || '?') + ' em EN, nenhuma ausente', ok, j);
}

/* ---------- referências independentes para conferir a interface ---------- */
const famCount = f => ITEMS.filter(x => x.categories.includes(f)).length;
const kinds = {}; ITEMS.forEach(x => { kinds[x.kind] = (kinds[x.kind] || 0) + 1; });
const countries = new Set(ITEMS.map(x => x.country).filter(Boolean)).size;
const cities = new Set(ITEMS.filter(x => x.city_lat != null).map(x => (x.country || '-') + '|' + x.city_lat.toFixed(3) + '|' + x.city_lng.toFixed(3))).size;
const sources = new Set(ITEMS.map(x => x.source_name || '—')).size;
const pick = {
  active: ITEMS.find(x => x.activity_badge === 'active_recent' && x.own_url && x.city && x.last_activity && x.last_activity.startsWith('2026')),
  source: ITEMS.filter(x => x.activity_badge === 'source_checked' && x.city)[3],
  kvm: ITEMS.filter(x => x.licence_note)[5],
  nocity: ITEMS.filter(x => !x.city && x.activity_badge === 'to_confirm')[2],
  saopaulo: ITEMS.find(x => x.country === 'BR' && norm(x.city) === 'sao paulo')
};

const TOKEN = 'a1b2c3d4'.repeat(8);   // 64 hex: formato do token de confirmação da retirada
const PT_ROUTES = ['inicio', 'explorar', 'i-' + pick.active.slug, 'participar', 'sobre', 'privacidade', 'termos', 'atribuicao', 'carta-de-convivencia', 'por-que-estou-aqui', 'contato', 'indicar', 'retirar-' + pick.active.slug, 'confirmar-retirada-' + TOKEN, 'corrigir-' + pick.active.slug, 'reivindicar-' + pick.active.slug, 'conectar-' + pick.active.slug, 'editar-' + pick.active.slug, 'entrar', 'meu-espaco', 'ofertas-e-necessidades', 'painel-editorial', 'convite-' + 'a'.repeat(64), 'retirar', 'i-nao-existe-xyz', 'rota-inexistente'];
const EN_ROUTES = ['home', 'explore', 'i-' + pick.active.slug, 'take-part', 'about', 'privacy', 'terms', 'attribution', 'community-charter', 'why-am-i-here', 'contact', 'suggest', 'withdraw-' + pick.active.slug, 'confirm-withdrawal-' + TOKEN, 'correct-' + pick.active.slug, 'claim-' + pick.active.slug, 'connect-' + pick.active.slug, 'edit-' + pick.active.slug, 'sign-in', 'my-space', 'offers-and-needs', 'editorial-panel', 'invite-' + 'a'.repeat(64), 'withdraw', 'i-does-not-exist-xyz', 'no-such-route'];

(async () => {
  const srv = await start(0), BASE = 'http://127.0.0.1:' + srv.address().port + '/';
  const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  async function ctxFor(lang, w, h) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, locale: lang === 'pt' ? 'pt-BR' : 'en-GB', reducedMotion: 'reduce' });
    await routeFonts(ctx);
    await ctx.addInitScript(l => { try { localStorage.setItem('rbc.lang', JSON.stringify(l)); } catch (e) {} window.__csp = []; document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI)); }, lang);
    return ctx;
  }
  function watch(page, tag) {
    page.on('console', m => {
      const tx = m.text();
      if (/GL Driver Message/.test(tx)) { R.glNoise++; return; }
      // respostas 400/404/429 do servidor simulado são deliberadas (link inválido, limite); o navegador as registra como erro de rede
      if (/^supabase-mock/.test(tag) && /Failed to load resource: the server responded with a status of (400|404|429)/.test(tx)) { R.mockHttpErrors = (R.mockHttpErrors || 0) + 1; return; }
      if (m.type() === 'error' || (m.type() === 'warning' && /i18n|Content Security Policy/i.test(tx))) R.consoleErrors.push(tag + ': ' + m.type() + ': ' + tx);
      if (/Content Security Policy/i.test(tx)) R.cspViolations.push(tag + ': ' + tx);
    });
    page.on('pageerror', e => R.consoleErrors.push(tag + ': pageerror: ' + e.message));
    page.on('request', rq => { if (!['GET', 'HEAD', 'OPTIONS'].includes(rq.method()) && !/^supabase-mock/.test(tag)) R.postRequests.push(tag + ': ' + rq.method() + ' ' + rq.url()); });
  }
  async function ready(page) { await page.waitForFunction(() => !!document.getElementById('page-title') && !document.querySelector('main > .view > .loading'), null, { timeout: 15000 }).catch(() => {}); await page.waitForTimeout(250); }
  async function measure(page) {
    return page.evaluate(() => {
      const vw = window.innerWidth, sw = document.documentElement.scrollWidth;
      const wide = [...document.querySelectorAll('body *')].filter(el => { const r = el.getBoundingClientRect(); return r.width && r.right > vw + 1 && getComputedStyle(el).position !== 'fixed' && !el.closest('.maplibregl-map,.tablewrap,.hp,.sr'); }).slice(0, 3).map(el => el.tagName + '.' + el.className);
      return { overflow: sw > vw, sw, vw, wide, h1: document.querySelectorAll('h1').length, docLang: document.documentElement.lang, title: document.title,
        landmarks: !!document.querySelector('header') && !!document.querySelector('main') && !!document.querySelector('footer') && !!document.querySelector('nav'),
        demo: /demonstra|demo band|protótipo/i.test(document.body.innerText) || !!document.querySelector('.demoband,.seal'), csp: window.__csp.slice(), forms: document.querySelectorAll('main textarea, main input[type=email]').length };
    });
  }

  /* ---------- 2. varredura: rotas PT/EN em 360 e 1280 ---------- */
  for (const [lang, routes] of [['pt', PT_ROUTES], ['en', EN_ROUTES]]) {
    for (const [w, h] of [[360, 740], [1280, 800]]) {
      const ctx = await ctxFor(lang, w, h), page = await ctx.newPage(), tag = lang + '@' + w; watch(page, tag);
      for (const r of routes) {
        await page.goto(BASE + '#' + r); await ready(page);
        const m = await measure(page);
        R.sweep.push(Object.assign({ lang, vp: w + 'x' + h, route: r }, m));
      }
      // modo mapa
      await page.goto(BASE + '#' + (lang === 'pt' ? 'explorar' : 'explore')); await ready(page);
      await page.click('[data-mode=map]'); await page.waitForSelector('.mk', { timeout: 20000 }).catch(() => {}); await page.waitForTimeout(800);
      const mm = await measure(page), mk = await page.locator('.mk').count(), legend = await page.locator('.legend').innerText();
      R.sweep.push(Object.assign({ lang, vp: w + 'x' + h, route: 'explore-map', markers: mk, legendCity: /centro da cidade|city centre/i.test(legend) }, mm));
      if (w === 1280 && lang === 'pt') { await page.screenshot({ path: path.join(SHOTS, 'explorar_mapa_pt_1280.png') }); R.shots.push('explorar_mapa_pt_1280.png'); }
      if (w === 360 && lang === 'en') { await page.click('[data-mode=list]'); await page.waitForTimeout(200); await page.screenshot({ path: path.join(SHOTS, 'explore_list_en_360.png') }); R.shots.push('explore_list_en_360.png'); }
      await ctx.close();
    }
  }
  const sw = R.sweep;
  check('Varredura: ' + sw.length + ' telas (26 rotas + mapa) × PT/EN × 360/1280 sem rolagem horizontal', sw.every(s => !s.overflow), sw.filter(s => s.overflow).map(s => s.lang + s.vp + s.route + ' sw=' + s.sw + ' ' + s.wide.join(',')));
  check('Varredura: exatamente 1 h1 por tela', sw.every(s => s.h1 === 1), sw.filter(s => s.h1 !== 1).map(s => s.lang + s.vp + s.route + ':' + s.h1));
  check('Varredura: lang do documento correto (pt-BR / en)', sw.every(s => s.docLang === (s.lang === 'pt' ? 'pt-BR' : 'en')), sw.filter(s => s.docLang !== (s.lang === 'pt' ? 'pt-BR' : 'en')).map(s => s.lang + s.route));
  check('Varredura: landmarks header/nav/main/footer em todas', sw.every(s => s.landmarks));
  check('Varredura: nenhuma faixa ou selo de "demonstração"', sw.every(s => !s.demo), sw.filter(s => s.demo).map(s => s.route));
  check('Modo static: nenhuma tela com conta mostra formulário de envio (tela honesta "em breve")', sw.filter(s => /^(contato|contact|indicar|suggest|retirar|withdraw|confirmar-retirada|confirm-withdrawal|corrigir|correct|reivindicar|claim|conectar|connect|editar|edit|entrar|sign-in|meu-espaco|my-space|ofertas|offers|painel|editorial|convite|invite)/.test(s.route)).every(s => s.forms === 0));
  check('Mapa: marcadores por cidade visíveis nas 4 combinações', sw.filter(s => s.route === 'explore-map').every(s => s.markers > 0), sw.filter(s => s.route === 'explore-map').map(s => s.markers));
  check('Mapa: legenda diz "posição = centro da cidade"', sw.filter(s => s.route === 'explore-map').every(s => s.legendCity));

  /* ---------- 3. dados na interface: contadores, filtros, busca, paginação ---------- */
  {
    const ctx = await ctxFor('pt', 1280, 800), page = await ctx.newPage(); watch(page, 'pt-data');
    const mlReq = []; page.on('request', rq => { if (/maplibre|world\.geojson/.test(rq.url())) mlReq.push(rq.url()); });
    await page.goto(BASE + '#inicio'); await ready(page);
    const counters = await page.$$eval('.counts__grid--main dd', d => d.map(x => x.textContent.replace(/\D/g, '')));
    check('Início: contadores reais (fichas, países, cidades) batem com public.json', counters[0] == ITEMS.length && counters[1] == countries && counters[2] == cities, { ui: counters, ref: [ITEMS.length, countries, cities] });
    const kindUi = await page.$$eval('.counts__grid--kinds .counter', d => d.map(x => +x.querySelector('dd').textContent.replace(/\D/g, '')));
    check('Início: contadores por tipo somam o total e batem por tipo', kindUi.reduce((a, b) => a + b, 0) === ITEMS.length && kindUi.length === Object.keys(kinds).length, { ui: kindUi, ref: kinds });
    await page.screenshot({ path: path.join(SHOTS, 'inicio_pt_1280.png'), fullPage: false }); R.shots.push('inicio_pt_1280.png');
    await page.goto(BASE + '#explorar'); await ready(page);
    check('Lista sem mapa: modo lista não baixa MapLibre nem world.geojson', mlReq.length === 0, mlReq);
    const count = async () => +(await page.textContent('#xres-h')).replace(/\D/g, '');
    check('Explorar: contagem inicial = ' + ITEMS.length, (await count()) === ITEMS.length, await count());
    // família
    await page.click('#xfilters-btn').catch(() => {});
    const fam = 'agroecology';
    await page.evaluate(() => { const d = document.querySelector('details[data-group="fam"]'); if (d) d.open = true; });
    await page.check('#xf-fam-' + fam);
    await page.waitForTimeout(150);
    check('Filtro família (agroecology) = ' + famCount(fam), (await count()) === famCount(fam), await count());
    // + país
    await page.evaluate(() => { const d = document.querySelector('details[data-group="country"]'); if (d) d.open = true; });
    await page.check('#xf-country-BR'); await page.waitForTimeout(150);
    const famBR = ITEMS.filter(x => x.categories.includes(fam) && x.country === 'BR').length;
    check('Filtro família + país (BR) = ' + famBR, (await count()) === famBR, await count());
    // + selo
    await page.evaluate(() => { const d = document.querySelector('details[data-group="badge"]'); if (d) d.open = true; });
    await page.check('#xf-badge-to_confirm'); await page.waitForTimeout(150);
    const famBRb = ITEMS.filter(x => x.categories.includes(fam) && x.country === 'BR' && x.activity_badge === 'to_confirm').length;
    check('Filtro família + país + selo = ' + famBRb, (await count()) === famBRb, await count());
    // presença isolada
    await page.click('#xclear'); await page.waitForTimeout(100);
    await page.evaluate(() => { const d = document.querySelector('details[data-group="pres"]'); if (d) d.open = true; });
    await page.check('#xf-pres-territorial'); await page.waitForTimeout(150);
    check('Filtro presença (territorial) = ' + ITEMS.filter(x => x.presence === 'territorial').length, (await count()) === ITEMS.filter(x => x.presence === 'territorial').length, await count());
    await page.click('#xclear'); await page.waitForTimeout(100);
    // busca sem acento
    await page.fill('#xq', 'sao paulo'); await page.press('#xq', 'Enter'); await page.waitForTimeout(200); const a = await count();
    await page.fill('#xq', 'São Paulo'); await page.press('#xq', 'Enter'); await page.waitForTimeout(200); const b = await count();
    check('Busca ignora acentos ("sao paulo" = "São Paulo", ' + a + ' resultados)', a === b && a > 0, { a, b });
    const firstName = await page.textContent('.fcard__name a');
    check('Busca: primeiro resultado contém São Paulo no texto do cartão', /s[aã]o paulo/i.test(await page.textContent('.cards li:first-child')), firstName);
    // paginação
    await page.fill('#xq', ''); await page.press('#xq', 'Enter'); await page.waitForTimeout(200);
    const p1 = await page.textContent('.fcard__name a');
    await page.click('.pager button[data-page="2"]'); await page.waitForTimeout(200);
    const p2 = await page.textContent('.fcard__name a'), cur = await page.getAttribute('.pgnum[aria-current="page"]', 'data-page');
    check('Paginação: página 2 mostra outros cartões e marca aria-current', p1 !== p2 && cur === '2', { p1, p2, cur });
    const pagerBtns = await page.locator('.pager .pgnum').count();
    check('Paginação em janela (no máximo 5 números visíveis)', pagerBtns <= 5, pagerBtns);
    // atribuição
    await page.goto(BASE + '#atribuicao'); await ready(page); await page.waitForSelector('#sources-auto table');
    const rows = await page.locator('#sources-auto tbody tr').count();
    check('Atribuição: lista de fontes gerada dos dados (' + sources + ' fontes)', rows === sources, rows);
    check('Atribuição: frase da Karte von Morgen presente', /Contém dados da Karte von Morgen \/ OpenFairDB, disponíveis sob ODbL/.test(await page.innerText('main')));
    for (const [r, re] of [['privacidade', /MINUTA PARA REVISÃO JURÍDICA/], ['termos', /MINUTA PARA REVISÃO JURÍDICA/]]) { await page.goto(BASE + '#' + r); await ready(page); check('Marcação de MINUTA mantida em #' + r, re.test(await page.innerText('main'))); }
    await ctx.close();
    const ctxE = await ctxFor('en', 1280, 800), pe = await ctxE.newPage(); watch(pe, 'en-data');
    await pe.goto(BASE + '#privacy'); await ready(pe); check('DRAFT marker kept in #privacy (EN)', /DRAFT FOR LEGAL REVIEW/.test(await pe.innerText('main')));
    await ctxE.close();
  }

  /* ---------- 4. fichas de 5 iniciativas reais ---------- */
  {
    for (const [lang, w] of [['pt', 1280], ['en', 360]]) {
      const ctx = await ctxFor(lang, w, 800), page = await ctx.newPage(); watch(page, 'profiles-' + lang);
      for (const [k, e] of Object.entries(pick)) {
        await page.goto(BASE + '#i-' + e.slug); await ready(page);
        await page.waitForFunction(() => !document.querySelector('#psis .loading'), null, { timeout: 8000 }).catch(() => {});
        const info = await page.evaluate(() => ({
          h1: document.querySelector('h1').textContent, badge: document.querySelector('.phead .stamp') && document.querySelector('.phead .stamp').textContent,
          trs: [...document.querySelectorAll('.tr')].map(x => ({ label: x.querySelector('.tr__label').textContent, lang: x.querySelector('.tr__text').getAttribute('lang'), text: x.querySelector('.tr__text').textContent })),
          src: [...document.querySelectorAll('#psrc a.url')].map(a => a.getAttribute('href')), attr: document.querySelector('.attrnote') && document.querySelector('.attrnote').textContent,
          sib: document.querySelectorAll('#psis h3').length, sibCards: document.querySelectorAll('#psis .fcard').length,
          acts: [...document.querySelectorAll('.actlist a')].map(a => a.getAttribute('href')), own: [...document.querySelectorAll('#p-web ~ * a.url, .psec a.url')].map(a => a.getAttribute('href'))
        }));
        const expBadge = e.activity_badge === 'active_recent' ? (lang === 'pt' ? 'ativa em ' : 'active in ') + e.last_activity.slice(0, 4) : e.activity_badge === 'source_checked' ? (lang === 'pt' ? 'fonte consultada em nov/2026' : 'source checked Nov 2026') : (lang === 'pt' ? 'atividade a confirmar' : 'activity to be confirmed');
        const ptBlock = info.trs.find(t => t.lang === 'pt'), enBlock = info.trs.find(t => t.lang === 'en');
        const res = {
          name: info.h1 === e.name, badge: info.badge === expBadge,
          pt: !!ptBlock && ptBlock.text === e.summary_pt, en: !!enBlock && enBlock.text === e.summary_en && /tradução automática|machine translation/i.test(enBlock.label),
          enFirst: lang === 'en' ? info.trs[0].lang === 'en' : info.trs[0].lang === 'pt',
          source: info.src.includes(e.source_url), licence: e.licence_note ? info.attr === e.licence_note : !info.attr,
          siblings: info.sib === 2, actions: info.acts.length === 3 && info.acts.every(h => h.endsWith(e.slug)), ownSite: !e.own_url || info.own.includes(e.own_url)
        };
        R.profiles.push({ lang, key: k, slug: e.slug, res, badge: info.badge, sibCards: info.sibCards });
        if (k === 'kvm' && lang === 'pt') { await page.screenshot({ path: path.join(SHOTS, 'ficha_kvm_pt_1280.png') }); R.shots.push('ficha_kvm_pt_1280.png'); }
        if (k === 'saopaulo' && lang === 'en') { await page.screenshot({ path: path.join(SHOTS, 'profile_en_360.png'), fullPage: true }); R.shots.push('profile_en_360.png'); }
      }
      await ctx.close();
    }
    const bad = R.profiles.filter(p => Object.values(p.res).some(v => !v));
    check('Fichas de 5 iniciativas reais (PT 1280 e EN 360): nome, selo, resumo PT, EN com aviso de tradução automática, ordem por idioma, fonte, licença, irmãs, 3 botões, site', bad.length === 0, bad.map(p => p.lang + ':' + p.slug + ':' + Object.keys(p.res).filter(k => !p.res[k]).join(',')));
    check('Irmãs calculadas no cliente aparecem nas fichas com cidade', R.profiles.filter(p => p.key !== 'nocity').every(p => p.sibCards > 0), R.profiles.map(p => p.slug + ':' + p.sibCards));
  }

  /* ---------- 5. teclado, foco visível e troca de idioma ---------- */
  async function focusInfo(page) {
    // foco visível no próprio elemento ou no cartão que o contém (o cartão inteiro ganha contorno via :has)
    return page.evaluate(() => { const el = document.activeElement; if (!el || el === document.body) return null; const vis = n => { if (!n) return false; const cs = getComputedStyle(n); return (cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0) || (cs.boxShadow && cs.boxShadow !== 'none'); }; return { tag: el.tagName, id: el.id, text: (el.textContent || el.value || '').trim().slice(0, 30), visible: vis(el) || vis(el.closest('.fcard')) }; });
  }
  async function tabTo(page, pred, max) { const stops = []; for (let i = 0; i < (max || 60); i++) { await page.keyboard.press('Tab'); const f = await focusInfo(page); stops.push(f); if (f && pred(f)) return { ok: true, stops }; } return { ok: false, stops }; }
  for (const w of [360, 1280]) {
    const ctx = await ctxFor('pt', w, 800), page = await ctx.newPage(); watch(page, 'kbd@' + w);
    const J = (name, ok, stops) => { const vis = (stops || []).filter(Boolean); R.keyboard.push({ vp: w, name, ok: !!ok, focusVisible: vis.every(s => s.visible), stops: vis.length, invisible: vis.filter(s => !s.visible).slice(0, 5) }); };
    // a) pular para o conteúdo → busca da Início → Explorar
    await page.goto(BASE + '#inicio'); await ready(page);
    await page.keyboard.press('Tab'); let f = await focusInfo(page);
    await page.keyboard.press('Enter'); const afterSkip = await page.evaluate(() => document.activeElement.id);
    let r1 = await tabTo(page, x => x.id === 'hq');
    await page.keyboard.type('biblioteca'); await page.keyboard.press('Enter'); await ready(page);
    const onExplore = /#explorar$/.test(page.url()) && (await page.inputValue('#xq')) === 'biblioteca';
    J('pular para o conteúdo + buscar na Início', f && f.id === 'skip-link' && afterSkip === 'page-title' && r1.ok && onExplore, [f].concat(r1.stops));
    // b) abrir a primeira ficha pelo teclado
    const firstHref = await page.getAttribute('.fcard__name a', 'href');
    await page.focus('#xq');
    let found = false, stops = [];
    for (let i = 0; i < 80 && !found; i++) { await page.keyboard.press('Tab'); const fi = await focusInfo(page); stops.push(fi); found = await page.evaluate(h => document.activeElement && document.activeElement.getAttribute('href') === h, firstHref); }
    await page.keyboard.press('Enter'); await ready(page);
    J('abrir ficha a partir da lista com Tab + Enter', found && page.url().endsWith(firstHref) && (await page.evaluate(() => document.activeElement.id)) === 'page-title', stops);
    // c) filtro com foco preservado (começa sem busca)
    await page.goto(BASE + '#explorar'); await ready(page);
    await page.fill('#xq', ''); await page.press('#xq', 'Enter'); await page.waitForTimeout(150);
    if (w === 360) { await page.focus('#xfilters-btn'); await page.keyboard.press('Enter'); }
    await page.evaluate(() => { const d = document.querySelector('details[data-group="badge"]'); if (d) d.open = true; });
    await page.focus('#xf-badge-active_recent'); await page.keyboard.press('Space'); await page.waitForTimeout(200);
    const keep = await page.evaluate(() => document.activeElement.id), cnt = +(await page.textContent('#xres-h')).replace(/\D/g, '');
    J('marcar filtro com Espaço mantém o foco no filtro', keep === 'xf-badge-active_recent' && cnt === ITEMS.filter(x => x.activity_badge === 'active_recent').length, [await focusInfo(page)]);
    // d) troca de idioma preserva contexto (Explorar: busca, filtro e modo)
    await page.fill('#xq', 'coop'); await page.press('#xq', 'Enter'); await page.waitForTimeout(200);
    const before = await page.textContent('#xres-h');
    if (w === 360) { /* idioma fica no cabeçalho também no celular */ }
    await page.focus('#lang-en'); await page.keyboard.press('Enter'); await page.waitForTimeout(300);
    const st = await page.evaluate(() => ({ hash: location.hash, q: document.getElementById('xq').value, checked: document.getElementById('xf-badge-active_recent') && document.getElementById('xf-badge-active_recent').checked, focus: document.activeElement.id, lang: document.documentElement.lang, head: document.getElementById('xres-h').textContent }));
    J('troca PT→EN em Explorar preserva busca, filtro e contagem; foco volta ao botão', st.hash === '#explore' && st.q === 'coop' && st.checked && st.focus === 'lang-en' && st.lang === 'en' && before.replace(/\D/g, '') === st.head.replace(/\D/g, ''), [await focusInfo(page)]);
    // e) troca na ficha preserva a ficha
    await page.goto(BASE + '#i-' + pick.kvm.slug); await ready(page);
    await page.focus('#lang-pt'); await page.keyboard.press('Enter'); await page.waitForTimeout(300);
    const st2 = await page.evaluate(() => ({ hash: location.hash, h1: document.querySelector('h1').textContent, lang: document.documentElement.lang, first: document.querySelector('.tr__text').getAttribute('lang') }));
    J('troca EN→PT na ficha mantém a ficha e reordena os resumos', st2.hash === '#i-' + pick.kvm.slug && st2.h1 === pick.kvm.name && st2.lang === 'pt-BR' && st2.first === 'pt', []);
    // f) menu móvel com Esc (360)
    if (w === 360) {
      await page.focus('#menubtn'); await page.keyboard.press('Enter'); await page.waitForTimeout(100);
      const open = await page.getAttribute('#menubtn', 'aria-expanded');
      await page.keyboard.press('Escape'); await page.waitForTimeout(100);
      const closed = await page.getAttribute('#menubtn', 'aria-expanded'), fo = await page.evaluate(() => document.activeElement.id);
      J('menu móvel abre com Enter e fecha com Esc devolvendo o foco', open === 'true' && closed === 'false' && fo === 'menubtn', [await focusInfo(page)]);
    }
    // g) mapa por teclado: marcador abre painel da cidade
    await page.goto(BASE + '#explorar'); await ready(page);
    await page.focus('[data-mode=map]'); await page.keyboard.press('Enter');
    await page.waitForSelector('.mk--city', { timeout: 20000 }).catch(() => {});
    const anyCity = await page.locator('.mk--city').count();
    if (!anyCity) { await page.locator('.mk--cluster').first().click(); await page.waitForTimeout(800); await page.waitForSelector('.mk--city', { timeout: 10000 }).catch(() => {}); }
    await page.locator('.mk--city').first().focus(); await page.keyboard.press('Enter'); await page.waitForTimeout(300);
    const sel = await page.evaluate(() => ({ focus: document.activeElement.id, h: document.getElementById('xsel-h') && document.getElementById('xsel-h').textContent, cards: document.querySelectorAll('#xsel .fcard').length }));
    J('marcador de cidade (botão) abre o painel da cidade pelo teclado', sel.focus === 'xsel-h' && sel.cards > 0, [await focusInfo(page)]);
    // h) tela "em breve" acessível pelo botão da ficha
    await page.goto(BASE + '#i-' + pick.active.slug); await ready(page);
    await page.focus('.actlist a[href$="' + pick.active.slug + '"]'); await page.keyboard.press('Enter'); await ready(page);
    const soon = await page.evaluate(() => ({ hash: location.hash, state: !!document.querySelector('.state--soon'), forms: document.querySelectorAll('main form').length }));
    J('"É sua? Reivindique" (modo static) abre a tela honesta "em breve", sem formulário', /#reivindicar-/.test(soon.hash) && soon.state && soon.forms === 0, []);
    await ctx.close();
  }
  check('Teclado: ' + R.keyboard.length + ' jornadas aprovadas (360 e 1280)', R.keyboard.every(k => k.ok), R.keyboard.filter(k => !k.ok));
  check('Teclado: foco visível em todas as paradas registradas', R.keyboard.every(k => k.focusVisible), R.keyboard.filter(k => !k.focusVisible).map(k => k.vp + ':' + k.name + ' ' + JSON.stringify(k.invisible)));

  /* ---------- 7. modo supabase com API simulada (interceptação; nenhum recurso em nuvem) ----------
     Confere o adaptador supabase contra o contrato: paginação por chave em entity_list (2 páginas),
     entity_page, sister_initiatives, attribution_sources, request_takedown (nunca oculta: link por e-mail ou fila),
     confirm_takedown (rota de confirmação) e honeypot. */
  {
    const SB = 'https://mock.supabase.co';
    const uuid = i => '00000000-0000-4000-8000-' + String(i).padStart(12, '0');
    const sorted = ITEMS.slice().sort((a, b) => a.slug < b.slug ? -1 : 1);
    const rows = sorted.map((x, i) => ({ id: uuid(i + 1), slug: x.slug, name: x.name, alt_names: x.aliases, kind: x.kind, presence_type: x.presence, families: x.categories, country_code: x.country, city: x.city,
      area_id: x.city_lat != null ? (x.country || 'xx').toLowerCase() + '-' + norm(x.city).replace(/[^a-z0-9]+/g, '-') : null, lon: x.city_lng, lat: x.city_lat, location_precision: x.location_precision, world_region: x.region,
      activity_badge: x.activity_badge, activity_month: x.last_activity ? x.last_activity + '-01' : null, summary_pt: x.summary_pt, summary_en: x.summary_en, summary_en_state: x.summary_en ? 'machine_unreviewed' : null,
      website_url: x.own_url, is_managed: false, has_offers: false }));
    const hidden = new Set(), calls = [];
    const TOK_OK = 'c0ffee00'.repeat(8), TOK_Q = 'feedface'.repeat(8), TOK_BAD = '0123abcd'.repeat(8);
    const H = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS', 'access-control-expose-headers': '*', 'content-type': 'application/json' };
    const ctx = await ctxFor('pt', 1280, 800);
    await ctx.route(/\/config\.js$/, r => r.fulfill({ status: 200, contentType: 'text/javascript', body: "window.RBC_CONFIG={MODE:'supabase',SUPABASE_URL:'" + SB + "',SUPABASE_ANON_KEY:'anon-test-key',SITE_URL:''};" }));
    await ctx.route(SB + '/**', async r => {
      const rq = r.request(), u = new URL(rq.url());
      if (rq.method() === 'OPTIONS') return r.fulfill({ status: 204, headers: H });
      const json = (b, st) => r.fulfill({ status: st || 200, headers: H, body: JSON.stringify(b) });
      if (u.pathname === '/rest/v1/entity_list') {
        const lim = +(u.searchParams.get('limit') || 1000), gt = (u.searchParams.get('slug') || '').replace(/^gt\./, '');
        return json(rows.filter(x => !hidden.has(x.slug) && (!gt || x.slug > gt)).slice(0, lim));
      }
      if (u.pathname === '/rest/v1/attribution_sources') { const m = {}; ITEMS.forEach(x => { const k = x.source_name || '—'; m[k] = m[k] || { source_name: k, licence: null, attribution: x.licence_note, entities: 0 }; m[k].entities++; }); return json(Object.values(m)); }
      if (u.pathname === '/rest/v1/offers_needs_feed') return json([{ id: uuid(9001), entity_id: rows[0].id, entity_slug: rows[0].slug, entity_name: rows[0].name, country_code: rows[0].country_code, city: rows[0].city, kind: 'offer', topic: 'tools', title: 'Furadeira para emprestar', description: 'Teste', valid_until: '2027-01-31', published_at: '2026-11-21T00:00:00Z' }]);
      const fn = u.pathname.replace('/rest/v1/rpc/', ''), body = rq.postDataJSON() || {};
      calls.push({ fn, body });
      if (fn === 'entity_page') { const x = rows.find(y => y.slug === body.p_slug && !hidden.has(y.slug)); if (!x) return json(null); const src = ITEMS.find(y => y.slug === x.slug);
        return json({ id: x.id, slug: x.slug, canonical_slug: x.slug, sources: [{ name: src.source_name, url: src.source_url, accessed_at: '2026-11-01', licence: null }], attribution: src.licence_note, offers_needs: [{ id: uuid(9002), kind: 'need', topic: 'space', title: 'Sala para oficina', description: 'Teste de necessidade', valid_until: '2027-02-28' }], is_managed: false }); }
      if (fn === 'sister_initiatives') return json(rows.slice(5, 8).map(x => ({ relation: 'same_family_other_country', entity_id: x.id, slug: x.slug, name: x.name, country_code: x.country_code, city: x.city, families: x.families, shared_families: x.families.slice(0, 1), activity_badge: x.activity_badge })));
      if (fn === 'request_takedown') {   // contrato 1.2: nunca oculta; com e-mail pede confirmação, sem e-mail vai para a fila; limite → 54000
        if (/LIMITE/.test(body.p_reason || '')) return json({ code: '54000', message: 'limite de envios excedido; tente mais tarde' }, 429);
        return json(body.p_email ? { request_id: uuid(7001), hidden: false, needs_confirmation: true, queued: false } : { request_id: uuid(7001), hidden: false, needs_confirmation: false, queued: true });
      }
      if (fn === 'confirm_takedown') {
        if (body.p_token === TOK_OK) { hidden.add(pick.active.slug); return json({ hidden: true, queued: false }); }
        if (body.p_token === TOK_Q) return json({ hidden: false, queued: true });
        return json({ code: 'P0002', message: 'link inválido ou vencido' }, 404);
      }
      if (fn === 'send_contact_message') return json(uuid(7002));
      return json({ code: 'PGRST202', message: 'mock: função não simulada ' + fn }, 404);
    });
    const page = await ctx.newPage(); watch(page, 'supabase-mock');
    await page.goto(BASE + '#explorar'); await ready(page);
    const c0 = +(await page.textContent('#xres-h')).replace(/\D/g, '');
    check('Supabase (simulado): lista completa por paginação de chave (1000 + ' + (ITEMS.length - 1000) + ')', c0 === ITEMS.length, c0);
    const target = pick.active, tRow = rows.find(x => x.slug === target.slug);
    await page.goto(BASE + '#i-' + target.slug); await ready(page);
    await page.waitForFunction(() => !document.querySelector('#poffers .loading') && !document.querySelector('#psis .loading'), null, { timeout: 8000 }).catch(() => {});
    const pinfo = await page.evaluate(() => ({ offers: document.getElementById('poffers').innerText, sis: document.querySelectorAll('#psis .fcard').length, src: document.getElementById('psrc').innerText, connect: !!document.querySelector('.actlist a[href^="#conectar-"]') }));
    check('Supabase (simulado): ficha usa entity_page (ofertas/necessidades, fonte com data) e sister_initiatives', /Sala para oficina/.test(pinfo.offers) && pinfo.sis === 3 && /consultada em nov\/2026/.test(pinfo.src) && pinfo.connect, pinfo);
    /* --- Retirar do mapa: o pedido nunca oculta; com e-mail pede confirmação, sem e-mail vai para a fila --- */
    const send = async (reason, email, rel) => {
      await page.goto(BASE + '#sobre'); await ready(page);   // sai da rota para o formulário ser montado de novo
      await page.goto(BASE + '#retirar-' + target.slug); await ready(page);
      await page.check('#f-relation-' + (rel || 0)); await page.fill('#f-reason', reason);
      if (email) await page.fill('#f-email', email);
      await page.waitForTimeout(3200); await page.click('#wform [type=submit]');
      await page.waitForSelector('.result, #wform .err:not([hidden])', { timeout: 8000 }).catch(() => {});
      return page.textContent('main').catch(() => '');
    };
    await page.goto(BASE + '#retirar-' + target.slug); await ready(page);
    const hasForm = await page.locator('#wform textarea').count(), hasEmail = await page.locator('#wform input[type=email]').count();
    const formText = await page.textContent('main');
    check('Supabase (simulado): formulário de retirada tem o campo e-mail (opcional) com o texto exato da decisão, sem prometer retirada imediata',
      hasForm === 1 && hasEmail === 1 && formText.includes('Com e-mail, a ficha sai do ar assim que você clicar no link que vamos enviar. Sem e-mail, o pedido vai para a moderação, que responde em até 72 horas.') && !/na hora|imediat/i.test(formText), { hasForm, hasEmail });
    const resMail = await send('Pedimos a retirada desta ficha, por favor.', 'pessoa@example.org');
    const tk = calls.find(c => c.fn === 'request_takedown');
    check('Supabase (simulado): com e-mail, chama request_takedown(uuid, p_email, honeypot vazio) e mostra "Enviamos um link para o seu e-mail"',
      tk && tk.body.p_entity === tRow.id && tk.body.p_relation === 'representative' && tk.body.p_hp === null && tk.body.p_email === 'pessoa@example.org' && /Enviamos um link para o seu e-mail/.test(resMail) && /continua no ar até você confirmar/.test(resMail), { tk, resMail: resMail.slice(0, 300) });
    const resQ = await send('Pedimos a retirada desta ficha, sem e-mail.', '');
    const tk2 = calls.filter(c => c.fn === 'request_takedown')[1];
    check('Supabase (simulado): sem e-mail, p_email = null e a tela diz "Pedido na fila da moderação" (resposta em até 72 horas, ficha no ar)',
      tk2 && tk2.body.p_email === null && /Pedido na fila da moderação/.test(resQ) && /72 horas/.test(resQ) && /continua no ar/.test(resQ), { tk2, resQ: resQ.slice(0, 300) });
    const nReq = calls.filter(c => c.fn === 'request_takedown').length;
    await page.goto(BASE + '#sobre'); await ready(page);
    await page.goto(BASE + '#retirar-' + target.slug); await ready(page);
    await page.check('#f-relation-0'); await page.fill('#f-reason', 'Pedimos a retirada desta ficha, por favor.'); await page.fill('#f-email', 'sem-arroba');
    await page.waitForTimeout(3200); await page.click('#wform [type=submit]'); await page.waitForTimeout(400);
    check('Supabase (simulado): e-mail inválido é barrado no formulário, sem chamar o servidor', calls.filter(c => c.fn === 'request_takedown').length === nReq && (await page.locator('#f-email-err:not([hidden])').count()) === 1);
    const resLim = await send('LIMITE: pedido que o servidor recusa por excesso.', 'pessoa@example.org');
    check('Supabase (simulado): limite atingido (54000) tem tela própria "Limite de pedidos atingido"', /Limite de pedidos atingido/.test(resLim) && /formulário de contato/.test(resLim), resLim.slice(0, 300));
    await page.goto(BASE + '#explorar'); await ready(page);
    const c1 = +(await page.textContent('#xres-h')).replace(/\D/g, '');
    await page.goto(BASE + '#i-' + target.slug); await ready(page); await page.waitForTimeout(600);
    const still = await page.textContent('h1');
    check('Supabase (simulado): depois dos pedidos (link enviado, fila, limite) a ficha continua na lista e a rota abre normalmente', c1 === ITEMS.length && !/indisponível ou retirada/.test(still), { c1, still });

    /* --- rota de confirmação #confirmar-retirada-<token> --- */
    const cwOpened = [];   /* abrir o link não pode chamar o servidor; só o clique em "Confirmar a retirada" */
    const cw = async (hash, wait) => {
      await page.goto(BASE + hash); await page.waitForTimeout(500);
      const n0 = calls.filter(c => c.fn === 'confirm_takedown').length;
      if (await page.locator('#cw-go').count()) {
        await page.waitForTimeout(800); cwOpened.push(calls.filter(c => c.fn === 'confirm_takedown').length === n0);
        await page.click('#cw-go');
      }
      await page.waitForSelector('.result', { timeout: 8000 }).catch(() => {}); await page.waitForTimeout(300); return page.textContent('main');
    };
    const nConf0 = calls.filter(c => c.fn === 'confirm_takedown').length;
    const tBad = await cw('#confirmar-retirada-' + TOK_BAD);
    check('Supabase (simulado): link desconhecido ou vencido → "Link inválido ou vencido" (erro genérico) com atalho para novo pedido', /Link inválido ou vencido/.test(tBad) && (await page.locator('main a[href^="#retirar"]').count()) === 1, tBad.slice(0, 200));
    const nBefore = calls.filter(c => c.fn === 'confirm_takedown').length;
    const tMal = await cw('#confirmar-retirada-' + 'z'.repeat(64));
    const tMal2 = await cw('#confirmar-retirada-abc123');
    check('Supabase (simulado): token malformado → "Link inválido ou vencido" sem chamar o servidor', /Link inválido ou vencido/.test(tMal) && /Link inválido ou vencido/.test(tMal2) && calls.filter(c => c.fn === 'confirm_takedown').length === nBefore, { tMal: tMal.slice(0, 120) });
    const tQ = await cw('#confirmar-retirada-' + TOK_Q);
    check('Supabase (simulado): confirmação barrada pelo disjuntor → "Pedido na fila da moderação"', /Pedido na fila da moderação/.test(tQ) && /72 horas/.test(tQ), tQ.slice(0, 200));
    await page.goto(BASE + '#explorar'); await ready(page);
    check('Supabase (simulado): pedido na fila não tira a ficha da lista', +(await page.textContent('#xres-h')).replace(/\D/g, '') === ITEMS.length);
    const tOk = await cw('#confirmar-retirada-' + TOK_OK);
    const cc = calls.filter(c => c.fn === 'confirm_takedown').pop();
    check('Supabase (simulado): link válido chama confirm_takedown(p_token) e mostra "Ficha retirada"', /Ficha retirada/.test(tOk) && cc && cc.body.p_token === TOK_OK && calls.filter(c => c.fn === 'confirm_takedown').length > nConf0, tOk.slice(0, 200));
    await page.screenshot({ path: path.join(SHOTS, 'retirada_confirmada_pt.png') }); R.shots.push('retirada_confirmada_pt.png');
    await page.goto(BASE + '#explorar'); await ready(page);
    const c2 = +(await page.textContent('#xres-h')).replace(/\D/g, '');
    await page.goto(BASE + '#i-' + target.slug); await ready(page); await page.waitForTimeout(600);
    const gone = await page.textContent('h1');
    check('Supabase (simulado): ficha confirmada some da lista e dos contadores, e a rota antiga diz "indisponível ou retirada"', c2 === ITEMS.length - 1 && /indisponível ou retirada/.test(gone), { c2, gone });
    /* --- inglês --- */
    check('Supabase (simulado): abrir o link de confirmação não confirma sozinho (só o botão chama confirm_takedown)', cwOpened.length >= 3 && cwOpened.every(Boolean), cwOpened);
    await page.goto(BASE + '#confirm-withdrawal-' + TOK_Q); await page.waitForTimeout(500); if (await page.locator('#cw-go').count()) await page.click('#cw-go'); await page.waitForSelector('.result', { timeout: 8000 }).catch(() => {});
    await page.click('#lang-en'); await page.waitForTimeout(500);
    const tEn = await page.textContent('main');
    await page.goto(BASE + '#confirm-withdrawal-' + TOK_BAD); await page.waitForTimeout(500); if (await page.locator('#cw-go').count()) await page.click('#cw-go'); await page.waitForSelector('.result', { timeout: 8000 }).catch(() => {});
    const tEnBad = await page.textContent('main');
    await page.goto(BASE + '#withdraw-' + pick.source.slug); await page.waitForTimeout(600);
    const tEnForm = await page.textContent('main').catch(() => '');
    check('Supabase (simulado): inglês — confirmação na fila, link inválido e dica do formulário (72 hours)', /Request queued for moderation/.test(tEn) && /Invalid or expired link/.test(tEnBad) && tEnForm.includes('Without one, the request goes to the moderators, who reply within 72 hours.') && !/immediate|right away|at once/i.test(tEnForm), { tEn: tEn.slice(0, 120), tEnBad: tEnBad.slice(0, 120) });
    await page.click('#lang-pt'); await page.waitForTimeout(400);
    await page.goto(BASE + '#contato'); await ready(page);
    await page.fill('#f-name', 'Teste'); await page.fill('#f-email', 'teste@example.org'); await page.fill('#f-subject', 'Assunto'); await page.fill('#f-body', 'Mensagem de teste com mais de dez caracteres.');
    await page.evaluate(() => { document.getElementById('f-website').value = 'spam'; });
    await page.waitForTimeout(3200); await page.click('#kform [type=submit]'); await page.waitForSelector('.result', { timeout: 8000 }).catch(() => {});
    const cm = calls.find(c => c.fn === 'send_contact_message');
    check('Supabase (simulado): formulário de contato envia p_hp do campo-isca (o servidor finge sucesso e não grava)', cm && cm.body.p_hp === 'spam' && cm.body.p_locale === 'pt', cm);
    await page.goto(BASE + '#reivindicar-' + pick.kvm.slug); await ready(page);
    check('Supabase (simulado): reivindicar sem sessão pede o link mágico (e-mail), sem simular nada', (await page.locator('#lgform input[type=email]').count()) === 1);
    await page.screenshot({ path: path.join(SHOTS, 'reivindicar_login_supabase_simulado.png') }); R.shots.push('reivindicar_login_supabase_simulado.png');
    R.supabaseMockCalls = calls.map(c => c.fn);
    await ctx.close();
  }

  /* ---------- 7b. painel de moderação: "Retiradas automáticas" (API simulada; contrato 1.2) ---------- */
  {
    const SB = 'https://mock.supabase.co', HX = c => c.repeat(64).slice(0, 64);
    const IP1 = HX('a1b2c3d4'), IP2 = HX('0f0f1e1e'), EM1 = HX('deadbeef'), EM2 = HX('cafe1234');
    const H = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS', 'access-control-expose-headers': '*', 'content-type': 'application/json' };
    const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url'), exp = Math.floor(Date.now() / 1000) + 86400 * 30;
    const jwt = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64({ sub: '00000000-0000-4000-8000-0000000000aa', aud: 'authenticated', role: 'authenticated', exp }) + '.sig';
    const SESSION = { access_token: jwt, refresh_token: 'r-test', token_type: 'bearer', expires_in: 86400 * 30, expires_at: exp, user: { id: '00000000-0000-4000-8000-0000000000aa', aud: 'authenticated', role: 'authenticated', email: 'mod@example.org', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } };
    const overview = (h, restored) => ({ window_hours: h,
      breaker: { hidden_last_hour: restored ? 0 : 12, limit_per_hour: 15, hidden_last_24h: restored ? 0 : 31, limit_per_day: 50, limit_per_email_day: 3, tripped: false, contained_last_24h: 4, last_containment_alert_at: '2026-11-21T22:10:00Z', confirm_emails_last_24h: 9, confirm_emails_limit_per_day: 40 },
      by_ip: restored ? [] : [{ ip_hash: IP1, requests: 7, hidden: 3, contained: 2, awaiting: 1, first_at: '2026-11-21T20:00:00Z', last_at: '2026-11-21T20:40:00Z' }, { ip_hash: IP2, requests: 2, hidden: 1, contained: 0, awaiting: 0, first_at: '2026-11-21T09:00:00Z', last_at: '2026-11-21T09:05:00Z' }],
      by_email: restored ? [] : [{ email_hash: EM1, email_domain: 'example.org', requests: 4, hidden: 2, contained: 1, awaiting: 0, domain_matches: false, first_at: '2026-11-21T20:00:00Z', last_at: '2026-11-21T20:30:00Z' }, { email_hash: EM2, email_domain: null, requests: 1, hidden: 1, contained: 0, awaiting: 0, domain_matches: true, first_at: '2026-11-21T10:00:00Z', last_at: '2026-11-21T10:00:00Z' }] });
    async function modCtx(roles, w, lang) {
      const ctx = await browser.newContext({ viewport: { width: w, height: 900 }, locale: lang === 'en' ? 'en-GB' : 'pt-BR', timezoneId: 'America/Sao_Paulo', reducedMotion: 'reduce' });
      await routeFonts(ctx);
      await ctx.addInitScript(a => { try { localStorage.setItem('rbc.lang', JSON.stringify(a.l)); localStorage.setItem('sb-mock-auth-token', JSON.stringify(a.s)); } catch (e) {} }, { l: lang || 'pt', s: SESSION });
      await ctx.route(/\/config\.js$/, r => r.fulfill({ status: 200, contentType: 'text/javascript', body: "window.RBC_CONFIG={MODE:'supabase',SUPABASE_URL:'" + SB + "',SUPABASE_ANON_KEY:'anon-test-key',SITE_URL:''};" }));
      const st = { calls: [], restored: false, entityLists: 0 };
      await ctx.route(SB + '/**', async r => {
        const rq = r.request(), u = new URL(rq.url());
        if (rq.method() === 'OPTIONS') return r.fulfill({ status: 204, headers: H });
        const json = (b, code) => r.fulfill({ status: code || 200, headers: H, body: JSON.stringify(b) });
        if (u.pathname === '/rest/v1/entity_list') { st.entityLists++; return json([]); }
        if (u.pathname.indexOf('/rest/v1/rpc/') !== 0) return json([]);
        const fn = u.pathname.replace('/rest/v1/rpc/', ''), body = rq.postDataJSON() || {};
        st.calls.push({ fn, body });
        if (fn === 'my_account') return json({ roles, managed: [], claims: [], connections: {} });
        if (fn === 'mod_queue_counts') return json({ takedowns: 3, claims: 0, reports: 0, suggestions: 0, contact: 0, edits: 0, invite_candidates: 0, invites_pending: 0 });
        if (fn === 'mod_list') return json([]);
        if (fn === 'mod_takedown_overview') return json(overview(body.p_hours, st.restored));
        if (fn === 'mod_restore_auto_hidden') {
          if (String(body.p_rationale || '').trim().length < 10) return json({ code: '22023', message: 'justificativa obrigatória' }, 400);
          if (/FALHA/.test(body.p_rationale)) return json({ code: '22023', message: 'janela inválida' }, 400);
          st.restored = true; return json(body.p_ip_hash ? 3 : body.p_email_hash ? 1 : 5);
        }
        return json({ code: 'PGRST202', message: 'mock: função não simulada ' + fn }, 404);
      });
      return { ctx, st };
    }
    const lastCall = (st, fn) => st.calls.filter(c => c.fn === fn).pop();
    const nCalls = (st, fn) => st.calls.filter(c => c.fn === fn).length;
    const waitAuto = async page => { await page.waitForSelector('#mqauto:not([hidden]) .autohide__group', { timeout: 10000 }).catch(() => {}); await page.waitForTimeout(200); };

    /* conta comum: a seção não existe */
    { const { ctx, st } = await modCtx([], 1280, 'pt'); const page = await ctx.newPage(); watch(page, 'supabase-mock');
      await page.goto(BASE + '#painel-editorial'); await ready(page); await page.waitForTimeout(800);
      check('Painel (simulado): conta comum não vê "Retiradas automáticas" e não chama as funções de moderador', (await page.locator('#mqauto').count()) === 0 && !/Retiradas automáticas/.test(await page.textContent('main')) && nCalls(st, 'mod_takedown_overview') === 0 && nCalls(st, 'mod_restore_auto_hidden') === 0);
      await ctx.close(); }

    /* moderador, 1280 px */
    const { ctx, st } = await modCtx(['moderator'], 1280, 'pt'); const page = await ctx.newPage(); watch(page, 'supabase-mock');
    await page.goto(BASE + '#painel-editorial'); await ready(page); await waitAuto(page);
    const txt = await page.textContent('#mqauto');
    check('Painel (simulado): moderador vê a seção "Retiradas automáticas" na fila Retiradas e a visão é pedida com p_hours = 48', (await page.locator('#mqauto:not([hidden]) #auto-h').count()) === 1 && /Retiradas automáticas/.test(txt) && lastCall(st, 'mod_takedown_overview').body.p_hours === 48, lastCall(st, 'mod_takedown_overview'));
    check('Painel (simulado): disjuntor mostra 12 de 15 (hora) e 31 de 50 (24 h)', /12 de 15/.test(txt) && /31 de 50/.test(txt) && /Disjuntor normal/.test(txt), txt.slice(0, 400));
    const ng = await page.evaluate(() => ({ g: document.querySelectorAll('.autohide__group').length, codes: [...document.querySelectorAll('.autohide__group code')].map(c => c.textContent) }));
    check('Painel (simulado): 2 grupos por IP e 2 por e-mail, cada um com os 8 primeiros caracteres do hash', ng.g === 4 && ng.codes.join(',') === [IP1, IP2, EM1, EM2].map(h => h.slice(0, 8)).join(','), ng);
    check('Painel (simulado): mostra o domínio, as contagens e o intervalo; nenhum e-mail em claro nem hash completo na tela', /example\.org/.test(txt) && /Aguardando confirmação/.test(txt) && !/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\./.test(txt) && ![IP1, IP2, EM1, EM2].some(h => txt.includes(h)) && !(await page.content()).includes(IP1.slice(0, 20) + IP1.slice(20, 30)));
    const w0 = nCalls(st, 'mod_takedown_overview');
    await page.click('[data-auto-hours="168"]'); await page.waitForTimeout(500); const h168 = lastCall(st, 'mod_takedown_overview').body.p_hours;
    await page.click('[data-auto-hours="24"]'); await page.waitForTimeout(500); const h24 = lastCall(st, 'mod_takedown_overview').body.p_hours;
    check('Painel (simulado): seletor de janela 24 h / 48 h / 7 dias chama a visão com 24, 48 e 168', h168 === 168 && h24 === 24 && nCalls(st, 'mod_takedown_overview') === w0 + 2 && (await page.getAttribute('[data-auto-hours="24"]', 'aria-pressed')) === 'true');
    await page.click('[data-auto-hours="48"]'); await page.waitForTimeout(500); await waitAuto(page);
    await page.screenshot({ path: path.join(SHOTS, 'retiradas_automaticas_1280.png') }); R.shots.push('retiradas_automaticas_1280.png');
    await page.locator('#mqauto').screenshot({ path: path.join(SHOTS, 'retiradas_automaticas_1280_secao.png') }); R.shots.push('retiradas_automaticas_1280_secao.png');

    /* desfazer grupo: sem justificativa → erro e nenhuma chamada */
    const li0 = page.locator('.autohide__group').nth(0);
    await li0.locator('[data-auto-undo]').click(); await page.waitForTimeout(300);
    const errNo = await li0.locator('.err:not([hidden])').count();
    await li0.locator('textarea').fill('curta'); await li0.locator('[data-auto-undo]').click(); await page.waitForTimeout(300);
    check('Painel (simulado): "Desfazer este grupo" exige justificativa de 10+ caracteres (sem texto e com texto curto: erro, nenhuma chamada, sem confirmação)', errNo === 1 && (await li0.locator('.err:not([hidden])').count()) === 1 && (await li0.locator('[data-auto-yes]').count()) === 0 && nCalls(st, 'mod_restore_auto_hidden') === 0);
    await li0.locator('textarea').fill('Pedidos em massa do mesmo endereço.'); await li0.locator('[data-auto-undo]').click(); await page.waitForTimeout(300);
    const conf = await li0.locator('.autohide__confirm').textContent();
    check('Painel (simulado): com justificativa pede confirmação explícita "Restaurar 3 fichas?" e ainda não chama a função', /Restaurar 3 fichas\?/.test(conf) && (await li0.locator('[data-auto-yes]').count()) === 1 && nCalls(st, 'mod_restore_auto_hidden') === 0, conf);
    await li0.locator('[data-auto-cancel]').click(); await page.waitForTimeout(200);
    check('Painel (simulado): "Cancelar" fecha a confirmação sem chamar a função', (await li0.locator('[data-auto-yes]').count()) === 0 && nCalls(st, 'mod_restore_auto_hidden') === 0);
    await li0.locator('[data-auto-undo]').click(); await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SHOTS, 'retiradas_automaticas_confirmar_1280.png') }); R.shots.push('retiradas_automaticas_confirmar_1280.png');
    const ov0 = nCalls(st, 'mod_takedown_overview'), el0 = st.entityLists;
    const before = Date.now(); await li0.locator('[data-auto-yes]').click(); await page.waitForSelector('#auto-result .result', { timeout: 8000 }).catch(() => {}); await page.waitForTimeout(700);
    const rc = lastCall(st, 'mod_restore_auto_hidden'), resTxt = await page.textContent('#auto-result').catch(() => '');
    check('Painel (simulado): confirmar chama mod_restore_auto_hidden com p_ip_hash completo, p_email_hash nulo, janela do grupo (início = first_at) e a justificativa',
      rc && rc.body.p_ip_hash === IP1 && rc.body.p_email_hash === null && rc.body.p_since === '2026-11-21T20:00:00Z' && new Date(rc.body.p_until).getTime() >= new Date('2026-11-21T20:40:00Z').getTime() && Math.abs(new Date(rc.body.p_until).getTime() - before) < 60000 && rc.body.p_rationale === 'Pedidos em massa do mesmo endereço.' && nCalls(st, 'mod_restore_auto_hidden') === 1, rc);
    check('Painel (simulado): mostra "3 fichas restauradas", recarrega a visão (nova chamada) e os dados (entity_list de novo) e a mensagem permanece', /3 fichas restauradas/.test(resTxt) && nCalls(st, 'mod_takedown_overview') === ov0 + 1 && st.entityLists > el0 && (await page.locator('.autohide__group').count()) === 0 && /Nenhum pedido/.test(await page.textContent('#auto-view')), { resTxt, ov: nCalls(st, 'mod_takedown_overview') - ov0, el: st.entityLists - el0 });

    /* desfazer grupo de e-mail e por período (visão volta com grupos) */
    st.restored = false; await page.click('[data-auto-hours="24"]'); await page.waitForTimeout(400); await page.click('[data-auto-hours="48"]'); await waitAuto(page);
    const liE = page.locator('.autohide__group').nth(2);
    await liE.locator('[data-auto-undo]').click(); await page.waitForTimeout(200);
    await liE.locator('textarea').fill('Mesmo e-mail pedindo várias retiradas.'); await liE.locator('[data-auto-undo]').click(); await page.waitForTimeout(200); const confE = await liE.locator('.autohide__confirm').textContent();
    await liE.locator('[data-auto-yes]').click(); await page.waitForSelector('#auto-result .result', { timeout: 8000 }).catch(() => {}); await page.waitForTimeout(500);
    const rcE = lastCall(st, 'mod_restore_auto_hidden');
    check('Painel (simulado): grupo de e-mail chama com p_email_hash (e p_ip_hash nulo); confirmação "Restaurar 2 fichas?" e resultado "1 ficha restaurada"', /Restaurar 2 fichas\?/.test(confE) && rcE.body.p_email_hash === EM1 && rcE.body.p_ip_hash === null && /1 ficha restaurada/.test(await page.textContent('#auto-result')), rcE);
    st.restored = false; await page.click('[data-auto-hours="24"]'); await page.waitForTimeout(400); await page.click('[data-auto-hours="48"]'); await waitAuto(page);
    const pf = page.locator('#auto-period');
    await pf.locator('#f-auto_since').fill('2026-11-21T10:00'); await pf.locator('#f-auto_until').fill('2026-11-21T09:00'); await pf.locator('#f-auto_why').fill('Justificativa suficiente.'); await pf.locator('[type=submit]').click(); await page.waitForTimeout(300);
    const badWin = await pf.locator('#f-auto_until-err:not([hidden])').count() + await pf.locator('.errsum:not([hidden])').count();
    await pf.locator('#f-auto_until').fill('2026-11-21T18:00'); await pf.locator('#f-auto_why').fill('curta'); await pf.locator('[type=submit]').click(); await page.waitForTimeout(300);
    const shortWhy = await pf.locator('#f-auto_why-err:not([hidden])').count();
    check('Painel (simulado): "Desfazer por período" barra janela invertida e justificativa curta, sem chamar a função', badWin > 0 && shortWhy === 1 && nCalls(st, 'mod_restore_auto_hidden') === 2 && (await pf.locator('[data-auto-yes]').count()) === 0, { badWin, shortWhy });
    await pf.locator('#f-auto_why').fill('Ataque em massa de 21/11, conferido nos registros.'); await pf.locator('[type=submit]').click(); await page.waitForTimeout(300);
    const confP = await pf.locator('.autohide__confirm').textContent(), nBeforeP = nCalls(st, 'mod_restore_auto_hidden');
    await pf.locator('[data-auto-yes]').click(); await page.waitForSelector('#auto-result .result', { timeout: 8000 }).catch(() => {}); await page.waitForTimeout(500);
    const rcP = lastCall(st, 'mod_restore_auto_hidden');
    check('Painel (simulado): por período pede confirmação e chama com início/fim em ISO (fuso de São Paulo) e hashes nulos; resultado "5 fichas restauradas"',
      /^Restaurar as fichas ocultadas automaticamente entre/.test(confP.trim()) && nBeforeP === 2 && rcP.body.p_since === '2026-11-21T13:00:00.000Z' && rcP.body.p_until === '2026-11-21T21:00:00.000Z' && rcP.body.p_ip_hash === null && rcP.body.p_email_hash === null && rcP.body.p_rationale === 'Ataque em massa de 21/11, conferido nos registros.' && /5 fichas restauradas/.test(await page.textContent('#auto-result')), { confP, rcP });
    await pf.locator('#f-auto_why').fill('FALHA simulada pelo servidor.'); await pf.locator('[type=submit]').click(); await page.waitForTimeout(300); await pf.locator('[data-auto-yes]').click(); await page.waitForSelector('#auto-result .result--error', { timeout: 8000 }).catch(() => {});
    check('Painel (simulado): erro do servidor (22023) aparece como mensagem de erro, sem derrubar a seção', (await page.locator('#auto-result .result--error').count()) === 1 && (await page.locator('#auto-h').count()) === 1);
    /* outras filas escondem a seção */
    await page.click('[data-queue="claims"]'); await page.waitForTimeout(300);
    const hiddenOther = await page.locator('#mqauto').isHidden(); await page.click('[data-queue="takedowns"]'); await page.waitForTimeout(300);
    check('Painel (simulado): a seção só aparece na fila Retiradas', hiddenOther && !(await page.locator('#mqauto').isHidden()));
    await ctx.close();

    /* 360 px: sem rolagem horizontal, teclado e captura */
    { const { ctx, st } = await modCtx(['moderator'], 360, 'pt'); const pg = await ctx.newPage(); watch(pg, 'supabase-mock');
      await pg.goto(BASE + '#painel-editorial'); await ready(pg); await waitAuto(pg);
      const ov = await pg.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, wide: [...document.querySelectorAll('#mqauto *')].filter(e => e.getBoundingClientRect().right > document.documentElement.clientWidth + 1).map(e => e.tagName + '.' + e.className).slice(0, 5) }));
      check('Painel (360 px): sem rolagem horizontal na seção (documento e elementos dentro da largura)', ov.sw <= ov.cw && ov.wide.length === 0, ov);
      await pg.locator('#mqauto').screenshot({ path: path.join(SHOTS, 'retiradas_automaticas_360.png') }); R.shots.push('retiradas_automaticas_360.png');
      await pg.locator('.autohide__group').nth(0).locator('[data-auto-undo]').click(); await pg.waitForTimeout(200);
      await pg.locator('.autohide__group').nth(0).locator('textarea').fill('Pedidos em massa do mesmo endereço.'); await pg.locator('.autohide__group').nth(0).locator('[data-auto-undo]').click(); await pg.waitForTimeout(300);
      await pg.locator('#mqauto').screenshot({ path: path.join(SHOTS, 'retiradas_automaticas_360_confirmar.png') }); R.shots.push('retiradas_automaticas_360_confirmar.png');
      const ov2 = await pg.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth);
      await pg.locator('[data-auto-cancel]').click();
      await pg.focus('[data-auto-hours="24"]'); let reached = null;
      for (let i = 0; i < 12 && !reached; i++) { await pg.keyboard.press('Tab'); reached = await pg.evaluate(() => { const a = document.activeElement; if (!a || !a.hasAttribute('data-auto-undo')) return null; const cs = getComputedStyle(a); return { outline: cs.outlineStyle, w: parseFloat(cs.outlineWidth) }; }); }
      check('Painel (360 px): teclado chega ao botão "Desfazer este grupo" com foco visível; a confirmação também cabe na largura', reached && reached.outline !== 'none' && reached.w >= 2 && ov2, { reached, ov2 });
      await ctx.close(); }

    /* inglês */
    { const { ctx } = await modCtx(['moderator'], 1280, 'en'); const pg = await ctx.newPage(); watch(pg, 'supabase-mock');
      await pg.goto(BASE + '#editorial-panel'); await ready(pg); await waitAuto(pg);
      const e = await pg.textContent('#mqauto');
      check('Painel (simulado): inglês — "Automatic withdrawals", "Undo this group", "Undo by period" e disjuntor "12 of 15"', /Automatic withdrawals/.test(e) && /Undo this group/.test(e) && /Undo by period/.test(e) && /12 of 15/.test(e), e.slice(0, 200));
      await ctx.close(); }

    /* modo static: a seção não aparece */
    { const ctx = await ctxFor('pt', 1280, 800), pg = await ctx.newPage(); watch(pg, 'static-painel');
      await pg.goto(BASE + '#painel-editorial'); await ready(pg); await pg.waitForTimeout(500);
      check('Modo static: o painel editorial não mostra "Retiradas automáticas" (tela "em breve")', (await pg.locator('#mqauto').count()) === 0 && !/Retiradas automáticas/.test(await pg.textContent('main')));
      await ctx.close(); }
  }

  /* ---------- 6. console, CSP e rede ---------- */
  check('Console: 0 erros (avisos "GL Driver Message" do SwiftShader contados à parte: ' + R.glNoise + ')', R.consoleErrors.length === 0, R.consoleErrors.slice(0, 8));
  check('CSP: 0 violações', R.cspViolations.length === 0 && R.sweep.every(s => !s.csp.length), R.cspViolations.slice(0, 5));
  check('Rede: 0 requisições POST/PUT/PATCH/DELETE no modo static', R.postRequests.length === 0, R.postRequests.slice(0, 5));

  await browser.close(); srv.close();
  R.finished = new Date().toISOString();
  R.total = R.checks.length; R.passed = R.checks.filter(c => c.ok).length;
  fs.writeFileSync(path.join(__dirname, 'results.json'), JSON.stringify(R, null, 1));
  console.log('\n' + R.passed + '/' + R.total + ' verificações aprovadas · ' + R.sweep.length + ' telas · ' + R.keyboard.length + ' jornadas de teclado · capturas: ' + R.shots.join(', '));
  process.exit(R.passed === R.total ? 0 : 1);
})().catch(e => { console.error(e); process.exit(2); });
