-- 0011 UP — Marco C: superfície exposta (schema api). Ver docs/API_CONTRATO.md.
-- Views security_invoker com colunas explícitas, só sobre pub. Funções INVOKER; as que escrevem chamam DEFINER em app.

-- ---------- Views públicas ----------
create view api.entity_list with (security_invoker = on) as
  select e.id, e.slug, e.name, e.alt_names, e.kind, e.presence_type, e.counter_class,
         array(select c.category_id from pub.entity_categories c where c.entity_id = e.id
                order by not c.is_primary, c.category_id) as families,
         (select c.category_id from pub.entity_categories c where c.entity_id = e.id and c.is_primary limit 1) as primary_family,
         e.country_code::text as country_code, e.city, e.area_id, e.lon, e.lat, e.location_precision, e.world_region,
         e.activity_badge, e.activity_checked_month as activity_month, e.verification_label,
         (select t.body from pub.entity_texts t where t.entity_id = e.id and t.field = 'description' and t.lang = 'pt') as summary_pt,
         (select t.body from pub.entity_texts t where t.entity_id = e.id and t.field = 'description' and t.lang = 'en') as summary_en,
         (select t.state from pub.entity_texts t where t.entity_id = e.id and t.field = 'description' and t.lang = 'en') as summary_en_state,
         e.website_url, e.is_managed,
         exists (select 1 from pub.offers_needs o where o.entity_id = e.id and o.valid_until >= current_date) as has_offers,
         e.search_text, e.published_at
    from pub.entities e
   where e.counter_class <> 'person';

-- Contadores distintos (nunca somar na interface).
create view api.public_stats with (security_invoker = on) as
  select
    (select count(*) from pub.entities where counter_class <> 'person')                                    as entities_total,
    (select count(distinct country_code) from pub.entities where counter_class <> 'person' and country_code is not null) as countries,
    (select count(distinct area_id) from pub.entities where counter_class <> 'person' and location_precision = 'city') as cities,
    (select count(*) from pub.places where kind = 'physical_venue')                                         as physical_places,
    (select count(*) from pub.entities where counter_class = 'initiative')                                  as initiatives,
    (select count(*) from pub.entities where counter_class = 'territorial_group')                           as territorial_groups,
    (select count(*) from pub.entities where counter_class = 'network')                                     as networks,
    (select count(*) from pub.entities where counter_class = 'online_resource')                             as online_resources,
    (select count(*) from pub.offers_needs where kind = 'offer' and valid_until >= current_date)            as offers_active,
    (select count(*) from pub.offers_needs where kind = 'need' and valid_until >= current_date)             as needs_active;

create view api.country_counts with (security_invoker = on) as
  select e.country_code::text as country_code, count(*) as entities
    from pub.entities e where e.counter_class <> 'person' and e.country_code is not null
   group by e.country_code;

create view api.offers_needs_feed with (security_invoker = on) as
  select o.id, o.entity_id, e.slug as entity_slug, e.name as entity_name, e.country_code::text as country_code, e.city,
         o.kind, o.topic, o.title, o.description, o.valid_until, o.published_at
    from pub.offers_needs o join pub.entities e on e.id = o.entity_id
   where o.valid_until >= current_date and e.counter_class <> 'person';

create view api.attribution_sources with (security_invoker = on) as
  select s.source_name, s.licence, max(e.attribution) as attribution, count(distinct s.entity_id) as entities
    from pub.entity_sources s join pub.entities e on e.id = s.entity_id
   where e.counter_class <> 'person'
   group by s.source_name, s.licence;

-- ---------- Funções de leitura ----------
create function api.entity_page(p_slug text default null, p_id uuid default null) returns jsonb
language sql stable security invoker set search_path = '' as $$
  with target as (
    select coalesce(
      (select e.id from pub.entities e where p_slug is not null and e.slug = lower(btrim(p_slug))),
      (select r.entity_id from pub.slug_redirects r where p_slug is not null and r.slug = lower(btrim(p_slug))),
      (select a.entity_id from pub.entity_aliases a where p_id is not null and a.old_id = p_id),
      p_id) as id)
  select jsonb_build_object(
    'id', e.id, 'slug', e.slug, 'canonical_slug', e.slug, 'name', e.name, 'alt_names', to_jsonb(e.alt_names),
    'kind', e.kind, 'presence_type', e.presence_type, 'counter_class', e.counter_class,
    'families', coalesce((select jsonb_agg(jsonb_build_object('id', c.category_id, 'is_primary', c.is_primary)
                                           order by not c.is_primary, c.category_id)
                            from pub.entity_categories c where c.entity_id = e.id), '[]'),
    'country_code', e.country_code, 'city', e.city, 'area_id', e.area_id, 'lon', e.lon, 'lat', e.lat,
    'location_precision', e.location_precision, 'world_region', e.world_region, 'network_of', e.network_of,
    'activity_badge', e.activity_badge, 'activity_month', e.activity_checked_month, 'source_accessed_at', e.source_accessed_at,
    'verification_label', e.verification_label, 'website_url', e.website_url, 'public_contact_url', e.public_contact_url,
    'summary', jsonb_build_object(
       'pt', (select jsonb_build_object('body', t.body, 'state', t.state) from pub.entity_texts t
               where t.entity_id = e.id and t.field = 'description' and t.lang = 'pt'),
       'en', (select jsonb_build_object('body', t.body, 'state', t.state) from pub.entity_texts t
               where t.entity_id = e.id and t.field = 'description' and t.lang = 'en')),
    'sources', coalesce((select jsonb_agg(jsonb_build_object('name', s.source_name, 'url', s.url, 'accessed_at', s.accessed_at,
                                                             'licence', s.licence) order by s.source_name)
                           from pub.entity_sources s where s.entity_id = e.id), '[]'),
    'attribution', e.attribution,
    'offers_needs', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'kind', o.kind, 'topic', o.topic, 'title', o.title,
                                                                  'description', o.description, 'valid_until', o.valid_until)
                                               order by o.valid_until)
                                from pub.offers_needs o where o.entity_id = e.id and o.valid_until >= current_date), '[]'),
    'is_managed', e.is_managed, 'published_at', e.published_at)
  from target t join pub.entities e on e.id = t.id
  where e.counter_class <> 'person'
$$;

-- Iniciativas-irmãs: mesmas famílias em outros países + complementares (sem família em comum) na mesma cidade.
create function api.sister_initiatives(p_entity uuid, p_limit integer default 6)
returns table (relation text, entity_id uuid, slug text, name text, country_code text, city text, families text[],
               shared_families text[], activity_badge text)
language sql stable security invoker set search_path = '' as $$
  with me as (
    select e.id, e.country_code::text as cc, e.area_id, e.location_precision,
           array(select c.category_id from pub.entity_categories c where c.entity_id = e.id) as fams
      from pub.entities e where e.id = p_entity and e.counter_class <> 'person'),
  lim as (select least(greatest(coalesce(p_limit, 6), 1), 12) as n),
  cand as (
    select o.id, o.slug, o.name, o.country_code::text as cc, o.city, o.activity_badge, o.area_id,
           array(select c.category_id from pub.entity_categories c where c.entity_id = o.id
                  order by not c.is_primary, c.category_id) as fams
      from pub.entities o, me where o.id <> me.id and o.counter_class <> 'person')
  (select 'same_family_other_country'::text, c.id, c.slug, c.name, c.cc, c.city, c.fams,
          array(select x from unnest(c.fams) x where x = any (me.fams) order by x), c.activity_badge
     from cand c, me
    where c.fams && me.fams and c.cc is not null and c.cc is distinct from me.cc
    order by cardinality(array(select x from unnest(c.fams) x where x = any (me.fams))) desc,
             (c.activity_badge = 'active_recent') desc, md5(c.id::text || p_entity::text)
    limit (select n from lim))
  union all
  (select 'complementary_same_city'::text, c.id, c.slug, c.name, c.cc, c.city, c.fams, '{}'::text[], c.activity_badge
     from cand c, me
    where me.area_id is not null and me.location_precision = 'city' and c.area_id = me.area_id and not (c.fams && me.fams)
    order by (c.activity_badge = 'active_recent') desc, md5(c.id::text || p_entity::text)
    limit (select n from lim))
$$;

-- ---------- Wrappers (INVOKER → DEFINER em app) ----------
create function api.request_takedown(p_entity uuid, p_reason text, p_relation text, p_contact text default null,
  p_locale text default 'pt', p_hp text default null) returns jsonb
language sql security invoker set search_path = '' as
$$ select app.request_takedown(p_entity, p_reason, p_relation, p_contact, p_locale, p_hp) $$;
create function api.report(p_kind text, p_entity uuid, p_body text, p_contact text default null, p_hp text default null)
returns uuid language sql security invoker set search_path = '' as
$$ select app.report(p_kind, p_entity, p_body, p_contact, p_hp) $$;
create function api.suggest_initiative(p_name text, p_website text, p_country text, p_city text, p_families text[],
  p_description text, p_why text default null, p_contact text default null, p_locale text default 'pt', p_hp text default null)
returns uuid language sql security invoker set search_path = '' as
$$ select app.suggest_initiative(p_name, p_website, p_country, p_city, p_families, p_description, p_why, p_contact, p_locale, p_hp) $$;
create function api.send_contact_message(p_name text, p_email text, p_subject text, p_body text,
  p_locale text default 'pt', p_hp text default null) returns uuid
language sql security invoker set search_path = '' as
$$ select app.send_contact_message(p_name, p_email, p_subject, p_body, p_locale, p_hp) $$;
create function api.invite_preview(p_token text) returns jsonb
language sql security invoker set search_path = '' as $$ select app.invite_preview(p_token) $$;
create function api.invite_decline(p_token text, p_reason text default null) returns void
language sql security invoker set search_path = '' as $$ select app.invite_decline(p_token, p_reason) $$;

create function api.my_account() returns jsonb
language sql security invoker set search_path = '' as $$ select app.my_account() $$;
create function api.set_locale(p_locale text) returns void
language sql security invoker set search_path = '' as $$ select app.set_locale(p_locale) $$;
create function api.claim_start(p_entity uuid, p_method text, p_statement text, p_email text default null) returns jsonb
language sql security invoker set search_path = '' as $$ select app.claim_start(p_entity, p_method, p_statement, p_email) $$;
create function api.claim_verify_code(p_claim uuid, p_code text) returns jsonb
language sql security invoker set search_path = '' as $$ select app.claim_verify_code(p_claim, p_code) $$;
create function api.claim_resend_code(p_claim uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select app.claim_resend_code(p_claim) $$;
create function api.claim_submit_evidence(p_claim uuid, p_url text) returns jsonb
language sql security invoker set search_path = '' as $$ select app.claim_submit_evidence(p_claim, p_url) $$;
create function api.claim_cancel(p_claim uuid) returns void
language sql security invoker set search_path = '' as $$ select app.claim_cancel(p_claim) $$;
create function api.manager_update(p_entity uuid, p_payload jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select app.manager_update(p_entity, p_payload) $$;
create function api.set_accepts_connections(p_entity uuid, p_accept boolean) returns void
language sql security invoker set search_path = '' as $$ select app.set_accepts_connections(p_entity, p_accept) $$;
create function api.connect_request(p_from_entity uuid, p_to_entity uuid, p_message text, p_contact text) returns uuid
language sql security invoker set search_path = '' as $$ select app.connect_request(p_from_entity, p_to_entity, p_message, p_contact) $$;
create function api.connect_respond(p_request uuid, p_accept boolean, p_contact text default null) returns void
language sql security invoker set search_path = '' as $$ select app.connect_respond(p_request, p_accept, p_contact) $$;
create function api.connect_cancel(p_request uuid) returns void
language sql security invoker set search_path = '' as $$ select app.connect_cancel(p_request) $$;
create function api.my_connections()
returns table (request_id uuid, direction text, status text, my_entity_id uuid, my_entity_slug text, my_entity_name text,
               other_entity_id uuid, other_entity_slug text, other_entity_name text, message text, my_contact text,
               other_contact text, created_at timestamptz, decided_at timestamptz)
language sql security invoker set search_path = '' as $$ select * from app.my_connections() $$;
create function api.offer_need_upsert(p_id uuid, p_entity uuid, p_kind text, p_topic text, p_title text,
  p_description text, p_valid_until date) returns uuid
language sql security invoker set search_path = '' as
$$ select app.offer_need_upsert(p_id, p_entity, p_kind, p_topic, p_title, p_description, p_valid_until) $$;
create function api.offer_need_remove(p_id uuid) returns void
language sql security invoker set search_path = '' as $$ select app.offer_need_remove(p_id) $$;
create function api.my_offers_needs()
returns table (id uuid, entity_id uuid, entity_slug text, kind text, topic text, title text, description text,
               valid_until date, expired boolean)
language sql security invoker set search_path = '' as $$ select * from app.my_offers_needs() $$;
create function api.invite_accept(p_token text, p_consent_text_version text, p_location text default 'city',
  p_summary_pt text default null) returns jsonb
language sql security invoker set search_path = '' as
$$ select app.invite_accept(p_token, p_consent_text_version, p_location, p_summary_pt) $$;

create function api.mod_queue_counts() returns jsonb
language sql security invoker set search_path = '' as $$ select app.mod_queue_counts() $$;
create function api.mod_list(p_queue text, p_status text default null, p_limit integer default 50, p_offset integer default 0)
returns jsonb language sql security invoker set search_path = '' as $$ select app.mod_list(p_queue, p_status, p_limit, p_offset) $$;
create function api.mod_decide_takedown(p_request uuid, p_decision text, p_rationale text) returns void
language sql security invoker set search_path = '' as $$ select app.mod_decide_takedown(p_request, p_decision, p_rationale) $$;
create function api.mod_decide_claim(p_claim uuid, p_approve boolean, p_rationale text) returns void
language sql security invoker set search_path = '' as $$ select app.mod_decide_claim(p_claim, p_approve, p_rationale) $$;
create function api.mod_decide_suggestion(p_id uuid, p_status text, p_note text) returns void
language sql security invoker set search_path = '' as $$ select app.mod_decide_suggestion(p_id, p_status, p_note) $$;
create function api.mod_mark_contact(p_id uuid, p_status text) returns void
language sql security invoker set search_path = '' as $$ select app.mod_mark_contact(p_id, p_status) $$;
create function api.mod_create_invite(p_candidate uuid, p_days integer default 30) returns jsonb
language sql security invoker set search_path = '' as $$ select app.mod_create_invite(p_candidate, p_days) $$;
create function api.mod_revoke_invite(p_invitation uuid) returns void
language sql security invoker set search_path = '' as $$ select app.mod_revoke_invite(p_invitation) $$;

-- somente servidor (Edge Function notify, pg_cron)
create function api.notification_pending(p_limit integer default 50) returns setof bigint
language sql security invoker set search_path = '' as $$ select app.notification_pending(p_limit) $$;
create function api.notification_claim(p_id bigint) returns jsonb
language sql security invoker set search_path = '' as $$ select app.notification_claim(p_id) $$;
create function api.notification_done(p_id bigint, p_ok boolean, p_error text default null) returns void
language sql security invoker set search_path = '' as $$ select app.notification_done(p_id, p_ok, p_error) $$;
create function api.purge_expired() returns jsonb
language sql security invoker set search_path = '' as $$ select app.purge_expired() $$;

-- ---------- GRANTs ----------
grant select on api.entity_list, api.public_stats, api.country_counts, api.offers_needs_feed, api.attribution_sources
  to anon, authenticated;
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'api' loop
    execute format('revoke all on function %s from public', r.sig);
  end loop;
end $$;
grant execute on function api.entity_page(text, uuid), api.sister_initiatives(uuid, integer),
  api.request_takedown(uuid, text, text, text, text, text), api.report(text, uuid, text, text, text),
  api.suggest_initiative(text, text, text, text, text[], text, text, text, text, text),
  api.send_contact_message(text, text, text, text, text, text), api.invite_preview(text), api.invite_decline(text, text)
to anon, authenticated;
grant execute on function api.my_account(), api.set_locale(text), api.claim_start(uuid, text, text, text),
  api.claim_verify_code(uuid, text), api.claim_resend_code(uuid), api.claim_submit_evidence(uuid, text),
  api.claim_cancel(uuid), api.manager_update(uuid, jsonb), api.set_accepts_connections(uuid, boolean),
  api.connect_request(uuid, uuid, text, text), api.connect_respond(uuid, boolean, text), api.connect_cancel(uuid),
  api.my_connections(), api.offer_need_upsert(uuid, uuid, text, text, text, text, date), api.offer_need_remove(uuid),
  api.my_offers_needs(), api.invite_accept(text, text, text, text), api.mod_queue_counts(),
  api.mod_list(text, text, integer, integer), api.mod_decide_takedown(uuid, text, text),
  api.mod_decide_claim(uuid, boolean, text), api.mod_decide_suggestion(uuid, text, text), api.mod_mark_contact(uuid, text),
  api.mod_create_invite(uuid, integer), api.mod_revoke_invite(uuid)
to authenticated;
grant execute on function api.notification_pending(integer), api.notification_claim(bigint),
  api.notification_done(bigint, boolean, text), api.purge_expired() to service_role;
