/* Adaptador "supabase": supabase-js v2 (vendor/supabase.js, carregado só neste modo) conforme docs/API_CONTRATO.md.
   Mesma interface do adaptador static (listInitiatives, sources, getPage, siblings) + conta e ações. */
(function () {
  'use strict';
  var RBC = window.RBC;
  var sb = null;
  var LIST_COLS = 'id,slug,name,alt_names,kind,presence_type,families,country_code,city,area_id,lon,lat,location_precision,world_region,activity_badge,activity_month,summary_pt,summary_en,summary_en_state,website_url,is_managed,has_offers';

  function wrap(p) {
    return Promise.resolve(p).then(function (r) {
      if (r && r.error) { var e = new Error(r.error.message || 'erro'); e.code = r.error.code || (r.error.status ? String(r.error.status) : ''); throw e; }
      return r ? r.data : null;
    }, function (err) { var e = new Error(err && err.message || 'rede'); e.code = 'network'; throw e; });
  }
  function trState(s) { return s === 'machine_unreviewed' ? 'machine' : s === 'human_reviewed' ? 'human' : s === 'original' ? 'human' : null; }
  /* entity_list → registro interno (mesmo formato de data/public.json) */
  function fromList(r) {
    return {
      id: r.id, slug: r.slug, name: r.name, aliases: r.alt_names || [], kind: r.kind, presence: r.presence_type,
      country: r.country_code, city: r.city, region: r.world_region, categories: r.families || [],
      summary_pt: r.summary_pt, summary_en: r.summary_en, summary_en_status: r.summary_en ? trState(r.summary_en_state) : null,
      own_url: r.website_url, source_url: null, source_name: null, activity_badge: r.activity_badge,
      last_activity: r.activity_month ? String(r.activity_month).slice(0, 7) : null,
      city_lat: r.lat, city_lng: r.lon, location_precision: r.location_precision, licence_note: null,
      is_managed: !!r.is_managed, has_offers: !!r.has_offers, area_id: r.area_id
    };
  }

  var A = RBC.adapters.supabase = {
    name: 'supabase',
    caps: { auth: true, write: true },
    init: function () {
      return RBC.loadScript('vendor/supabase.js').then(function () {
        if (!window.supabase || !window.supabase.createClient) throw new Error('supabase-js indisponível');
        sb = window.supabase.createClient(RBC.cfg.supabaseUrl, RBC.cfg.supabaseKey, {
          db: { schema: 'api' },
          auth: { flowType: 'pkce', persistSession: true, detectSessionInUrl: true, autoRefreshToken: true }
        });
        sb.auth.onAuthStateChange(function (ev, session) {
          var had = !!RBC.state.session; RBC.state.session = session || null;
          if (RBC.account) RBC.account.me = null;
          if (ev === 'SIGNED_IN' && !had) RBC.afterLogin();
          else if (ev === 'SIGNED_OUT' && had) RBC.render();
        });
        return sb.auth.getSession().then(function (r) { RBC.state.session = r && r.data ? r.data.session : null; });
      });
    },
    listInitiatives: function () {
      var out = [], PAGE = 1000;
      function page(after) {
        var q = sb.from('entity_list').select(LIST_COLS).order('slug').limit(PAGE);
        if (after) q = q.gt('slug', after);
        return wrap(q).then(function (rows) {
          rows = rows || []; rows.forEach(function (r) { out.push(fromList(r)); });
          return rows.length < PAGE ? out : page(rows[rows.length - 1].slug);
        });
      }
      return page(null);
    },
    getPage: function (slug) {
      return wrap(sb.rpc('entity_page', { p_slug: slug })).then(function (p) {
        if (!p) return null;
        return {
          canonical_slug: p.canonical_slug || p.slug, is_managed: !!p.is_managed, attribution: p.attribution || null,
          sources: (p.sources || []).map(function (s) { return { name: s.name, url: s.url, accessed_at: s.accessed_at, licence: s.licence }; }),
          offers_needs: p.offers_needs || []
        };
      });
    },
    siblings: function (rec) {
      return wrap(sb.rpc('sister_initiatives', { p_entity: rec.id, p_limit: 6 })).then(function (rows) {
        var D = RBC.data, s = { same: [], comp: [] };
        (rows || []).forEach(function (r) {
          var e = D && D.bySlug[r.slug]; if (!e) return;
          (r.relation === 'complementary_same_city' ? s.comp : s.same).push(e);
        });
        return s;
      });
    },
    sources: function () {
      return wrap(sb.from('attribution_sources').select('source_name,licence,attribution,entities').order('source_name')).then(function (rows) {
        return (rows || []).map(function (r) { return { name: r.source_name, n: r.entities || 0, licence: [r.attribution, r.licence].filter(Boolean) }; })
          .sort(function (a, b) { return b.n - a.n || String(a.name).localeCompare(String(b.name)); });
      });
    },
    offersFeed: function () { return wrap(sb.from('offers_needs_feed').select('id,entity_id,entity_slug,entity_name,country_code,city,kind,topic,title,description,valid_until,published_at').order('valid_until').limit(200)); },
    call: function (fn, params) { return wrap(sb.rpc(fn, params || {})); },
    signIn: function (email) {
      return wrap(sb.auth.signInWithOtp({ email: email, options: { emailRedirectTo: RBC.cfg.siteUrl.replace(/\/?$/, '/'), shouldCreateUser: true } }));
    },
    signOut: function () { return wrap(sb.auth.signOut()).then(function () { RBC.state.session = null; }); }
  };
})();
