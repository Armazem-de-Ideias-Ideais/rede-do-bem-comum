-- 0007 UP — superfície exposta (único schema a listar em "Exposed schemas" do Supabase)
-- Views: security_invoker = on, lista EXPLÍCITA de colunas, somente sobre pub.
-- Funções de leitura: SECURITY INVOKER, search_path vazio, limites e cursor.
-- Funções de escrita: wrappers INVOKER que chamam funções DEFINER do schema app (não exposto).

create view api.categories with (security_invoker = on) as
  select id, label_pt, label_en, subcategories_pt from pub.categories;

create view api.practices with (security_invoker = on) as
  select id, label_pt, label_en from pub.practices;

create view api.areas with (security_invoker = on) as
  select id, level, parent_id, country_code, name,
         round(extensions.st_x(label_point)::numeric, 4) as lon,
         round(extensions.st_y(label_point)::numeric, 4) as lat, is_synthetic
    from pub.areas;

create view api.entities with (security_invoker = on) as
  select id, kind, presence_type, counter_class, name, name_lang, country_code, area_id,
         public_contact_url, access_conditions, verification_label, activity_checked_month,
         source_accessed_at, political_identity, is_synthetic, published_at
    from pub.entities;

create view api.entity_texts with (security_invoker = on) as
  select entity_id, field, lang, body, state from pub.entity_texts;

create view api.entity_categories with (security_invoker = on) as
  select entity_id, category_id, is_primary from pub.entity_categories;

create view api.entity_practices with (security_invoker = on) as
  select entity_id, practice_id, evidence_state from pub.entity_practices;

create view api.entity_places with (security_invoker = on) as
  select entity_id, place_id from pub.entity_places;

-- Coordenadas já generalizadas em pub; arredondadas a 5 casas (~1 m) para local público exato.
create view api.places with (security_invoker = on) as
  select id, kind, precision, area_id, country_code,
         round(extensions.st_x(geom)::numeric, 5) as lon,
         round(extensions.st_y(geom)::numeric, 5) as lat, is_synthetic
    from pub.places;

create view api.relationships with (security_invoker = on) as
  select id, from_entity, to_entity, kind from pub.relationships;

create view api.profiles with (security_invoker = on) as
  select public_id, pseudonym, bio, area_id, precision, political_identity, is_synthetic, published_at
    from pub.profiles;

create view api.offers_needs with (security_invoker = on) as
  select id, entity_id, kind, title, description, valid_until
    from pub.offers_needs where valid_until >= current_date;

create view api.entity_sources with (security_invoker = on) as
  select entity_id, source_name, url, accessed_at, licence from pub.entity_sources;

-- Contadores DISTINTOS; categorias nunca somadas.
create view api.public_counters with (security_invoker = on) as
  select
    (select count(*) from pub.places where kind = 'physical_venue')                 as physical_places,
    (select count(*) from pub.entities where counter_class = 'initiative')           as initiatives,
    (select count(*) from pub.entities where counter_class = 'territorial_group')    as territorial_groups,
    (select count(*) from pub.entities where counter_class = 'network')              as networks,
    (select count(*) from pub.entities where counter_class = 'online_resource')      as online_resources,
    (select count(*) from pub.profiles)
      + (select count(*) from pub.entities where counter_class = 'person')           as public_profiles,
    coalesce((select bool_or(is_synthetic) from pub.entities), false)
      or coalesce((select bool_or(is_synthetic) from pub.places), false)             as includes_synthetic_data;

-- Sitemap: somente fichas institucionais publicadas; perfis pessoais nunca entram.
create view api.sitemap with (security_invoker = on) as
  select id as entity_id, published_at from pub.entities where counter_class <> 'person';

-- ---------- Funções de leitura ----------
create function api.places_in_bbox(p_west double precision, p_south double precision,
  p_east double precision, p_north double precision, p_limit integer default 200,
  p_after uuid default null, p_category text default null)
returns table (place_id uuid, kind text, "precision" text, area_id text, lon numeric, lat numeric, entity_ids uuid[])
language sql stable security invoker set search_path = '' as $$
  select p.id, p.kind, p.precision, p.area_id,
         round(extensions.st_x(p.geom)::numeric, 5), round(extensions.st_y(p.geom)::numeric, 5),
         array(select ep.entity_id from pub.entity_places ep where ep.place_id = p.id order by 1)
    from pub.places p
   where p.geom operator(extensions.&&) extensions.st_makeenvelope(
           greatest(p_west, -180), greatest(p_south, -90), least(p_east, 180), least(p_north, 90), 4326)
     and (p_after is null or p.id > p_after)
     and (p_category is null or exists (
           select 1 from pub.entity_places ep join pub.entity_categories c on c.entity_id = ep.entity_id
            where ep.place_id = p.id and c.category_id = p_category))
   order by p.id
   limit least(greatest(coalesce(p_limit, 200), 1), 500)
$$;

create function api.search_entities(p_query text, p_limit integer default 20, p_after uuid default null)
returns table (entity_id uuid, name text, kind text, presence_type text, country_code char(2), area_id text, rank real)
language sql stable security invoker set search_path = '' as $$
  select e.id, e.name, e.kind, e.presence_type, e.country_code, e.area_id,
         ts_rank(e.search_doc, q)
    from pub.entities e,
         websearch_to_tsquery('simple'::regconfig, pub.norm(left(coalesce(p_query, ''), 200))) q
   where e.search_doc @@ q
     and e.counter_class <> 'person'
     and (p_after is null or e.id > p_after)
   order by e.id
   limit least(greatest(coalesce(p_limit, 20), 1), 100)
$$;

create function api.autocomplete(p_prefix text, p_limit integer default 10)
returns table (entity_id uuid, name text)
language sql stable security invoker set search_path = '' as $$
  select e.id, e.name
    from pub.entities e
   where char_length(coalesce(p_prefix, '')) >= 2
     and e.counter_class <> 'person'
     and e.name_norm like '%' || replace(replace(replace(pub.norm(left(p_prefix, 60)), '\', '\\'), '%', '\%'), '_', '\_') || '%'
   order by e.name_norm
   limit least(greatest(coalesce(p_limit, 10), 1), 25)
$$;

create function api.category_facets(p_country char(2) default null)
returns table (category_id text, entities bigint)
language sql stable security invoker set search_path = '' as $$
  select c.category_id, count(distinct c.entity_id)
    from pub.entity_categories c join pub.entities e on e.id = c.entity_id
   where (p_country is null or e.country_code = p_country) and e.counter_class <> 'person'
   group by c.category_id order by c.category_id
$$;

-- Detalhe: respeita ocultação também para identificadores antigos (aliases).
create function api.entity_detail(p_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  with target as (
    select coalesce((select a.entity_id from pub.entity_aliases a where a.old_id = p_id), p_id) as id)
  select jsonb_build_object(
    'id', e.id, 'kind', e.kind, 'presence_type', e.presence_type, 'name', e.name, 'name_lang', e.name_lang,
    'country_code', e.country_code, 'area_id', e.area_id, 'public_contact_url', e.public_contact_url,
    'access_conditions', e.access_conditions, 'verification_label', e.verification_label,
    'activity_checked_month', e.activity_checked_month, 'source_accessed_at', e.source_accessed_at,
    'political_identity', e.political_identity, 'is_synthetic', e.is_synthetic,
    'texts', coalesce((select jsonb_agg(jsonb_build_object('field', t.field, 'lang', t.lang, 'body', t.body, 'state', t.state)
                                        order by t.field, t.lang) from pub.entity_texts t where t.entity_id = e.id), '[]'),
    'categories', coalesce((select jsonb_agg(c.category_id order by c.category_id) from pub.entity_categories c where c.entity_id = e.id), '[]'),
    'practices', coalesce((select jsonb_agg(x.practice_id order by x.practice_id) from pub.entity_practices x where x.entity_id = e.id), '[]'),
    'places', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'precision', p.precision, 'area_id', p.area_id,
                                         'lon', round(extensions.st_x(p.geom)::numeric, 5), 'lat', round(extensions.st_y(p.geom)::numeric, 5)))
                        from pub.entity_places ep join pub.places p on p.id = ep.place_id where ep.entity_id = e.id), '[]'),
    'sources', coalesce((select jsonb_agg(jsonb_build_object('name', s.source_name, 'url', s.url, 'accessed_at', s.accessed_at, 'licence', s.licence))
                         from pub.entity_sources s where s.entity_id = e.id), '[]'),
    'relationships', coalesce((select jsonb_agg(jsonb_build_object('from', r.from_entity, 'to', r.to_entity, 'kind', r.kind))
                               from pub.relationships r where r.from_entity = e.id or r.to_entity = e.id), '[]'),
    'offers_needs', coalesce((select jsonb_agg(jsonb_build_object('kind', o.kind, 'title', o.title, 'valid_until', o.valid_until))
                              from pub.offers_needs o where o.entity_id = e.id and o.valid_until >= current_date), '[]'))
  from target t join pub.entities e on e.id = t.id
$$;

-- Exportação institucional autorizada: só com permissão específica; nunca pessoas/perfis.
create function api.export_institutional(p_limit integer default 1000, p_after uuid default null)
returns table (entity_id uuid, name text, kind text, presence_type text, country_code char(2), area_id text,
               public_contact_url text, licence text, categories text[])
language sql stable security invoker set search_path = '' as $$
  select e.id, e.name, e.kind, e.presence_type, e.country_code, e.area_id, e.public_contact_url, x.licence,
         array(select c.category_id from pub.entity_categories c where c.entity_id = e.id order by 1)
    from pub.export_set x join pub.entities e on e.id = x.entity_id
   where e.counter_class <> 'person' and (p_after is null or e.id > p_after)
   order by e.id limit least(greatest(coalesce(p_limit, 1000), 1), 5000)
$$;

-- ---------- Wrappers de escrita (INVOKER → DEFINER em app) ----------
create function api.create_entity_draft(p_kind text, p_presence text, p_name text, p_lang text, p_payload jsonb default '{}')
returns jsonb language sql security invoker set search_path = '' as
$$ select app.create_entity_draft(p_kind::app.entity_kind, p_presence::app.presence_type, p_name, p_lang, p_payload) $$;
create function api.update_draft(p_version uuid, p_payload jsonb, p_expected_row_version integer)
returns integer language sql security invoker set search_path = '' as
$$ select app.update_draft(p_version, p_payload, p_expected_row_version) $$;
create function api.propose_edit(p_entity uuid, p_payload jsonb)
returns uuid language sql security invoker set search_path = '' as $$ select app.propose_edit(p_entity, p_payload) $$;
create function api.submit_version(p_version uuid)
returns void language sql security invoker set search_path = '' as $$ select app.submit_version(p_version) $$;
create function api.review_version(p_version uuid, p_decision text, p_kind text, p_rationale text)
returns text language sql security invoker set search_path = '' as
$$ select app.review_version(p_version, p_decision::app.review_decision, p_kind::app.review_kind, p_rationale) $$;
create function api.publication_blockers(p_entity uuid)
returns text[] language sql security invoker set search_path = '' as
$$ select case when app.curator_can(p_entity) then app.publication_blockers(p_entity) end $$;
create function api.publish_entity(p_entity uuid, p_rationale text)
returns void language sql security invoker set search_path = '' as $$ select app.publish_entity(p_entity, p_rationale) $$;
create function api.publish_place(p_place uuid)
returns void language sql security invoker set search_path = '' as $$ select app.publish_place(p_place) $$;
create function api.hide_entity(p_entity uuid, p_reason_code text)
returns void language sql security invoker set search_path = '' as $$ select app.hide_entity(p_entity, p_reason_code) $$;
create function api.withdraw_entity(p_entity uuid, p_reason_code text)
returns void language sql security invoker set search_path = '' as $$ select app.withdraw_entity(p_entity, p_reason_code) $$;
create function api.submit_claim(p_entity uuid, p_statement text)
returns uuid language sql security invoker set search_path = '' as $$ select app.submit_claim(p_entity, p_statement) $$;
create function api.decide_claim(p_claim uuid, p_approve boolean, p_rationale text)
returns void language sql security invoker set search_path = '' as $$ select app.decide_claim(p_claim, p_approve, p_rationale) $$;
create function api.grant_consent(p_purpose text, p_decision text, p_text_version text, p_entity uuid default null)
returns uuid language sql security invoker set search_path = '' as
$$ select app.grant_consent(p_purpose::app.consent_purpose, p_decision::app.consent_decision, p_text_version, p_entity) $$;
create function api.withdraw_consent(p_consent uuid)
returns void language sql security invoker set search_path = '' as $$ select app.withdraw_consent(p_consent) $$;
create function api.set_political_identity(p_labels text[], p_consent uuid, p_entity uuid default null)
returns uuid language sql security invoker set search_path = '' as
$$ select app.set_political_identity(p_labels, p_consent, p_entity) $$;
create function api.upsert_profile(p_pseudonym text, p_bio text, p_area text, p_precision text)
returns uuid language sql security invoker set search_path = '' as
$$ select app.upsert_profile(p_pseudonym, p_bio, p_area, p_precision::app.location_precision) $$;
create function api.submit_report(p_kind text, p_entity uuid, p_body text, p_contact text default null, p_client_key text default null)
returns uuid language sql security invoker set search_path = '' as
$$ select app.submit_report(p_kind::app.report_kind, p_entity, p_body, p_contact, p_client_key) $$;
create function api.triage_report(p_report uuid, p_status text, p_note text)
returns void language sql security invoker set search_path = '' as $$ select app.triage_report(p_report, p_status, p_note) $$;
create function api.grant_role(p_account uuid, p_role text, p_scope_country text default null, p_scope_category text default null)
returns uuid language sql security invoker set search_path = '' as
$$ select app.grant_role(p_account, p_role::app.staff_role, p_scope_country::char(2), p_scope_category) $$;
create function api.add_evidence(p_entity uuid, p_kind text, p_level text, p_url text, p_observed date, p_note text default null)
returns uuid language sql security invoker set search_path = '' as
$$ select app.add_evidence(p_entity, p_kind::app.evidence_kind, p_level, p_url, p_observed, p_note) $$;
create function api.set_editorial_facts(p_entity uuid, p_activity text, p_verified date, p_rights_basis text)
returns void language sql security invoker set search_path = '' as
$$ select app.set_editorial_facts(p_entity, p_activity::app.activity_state, p_verified, p_rights_basis) $$;
create function api.create_place(p_entity uuid, p_kind text, p_area text, p_lon double precision, p_lat double precision,
  p_precision text, p_sensitive boolean default false)
returns uuid language sql security invoker set search_path = '' as
$$ select app.create_place(p_entity, p_kind::app.place_kind, p_area, p_lon, p_lat, p_precision::app.location_precision, p_sensitive) $$;
create function api.link_place(p_entity uuid, p_place uuid, p_role text default 'shared')
returns void language sql security invoker set search_path = '' as $$ select app.link_place(p_entity, p_place, p_role) $$;
create function api.revoke_role(p_grant uuid)
returns void language sql security invoker set search_path = '' as $$ select app.revoke_role(p_grant) $$;

-- ---------- GRANTs da superfície ----------
grant select on all tables in schema api to anon, authenticated;
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'api' loop
    execute format('revoke all on function %s from public', r.sig);
  end loop;
end $$;
grant execute on function api.places_in_bbox(double precision, double precision, double precision, double precision, integer, uuid, text),
  api.search_entities(text, integer, uuid), api.autocomplete(text, integer), api.category_facets(char),
  api.entity_detail(uuid), api.submit_report(text, uuid, text, text, text) to anon, authenticated;
grant execute on function api.export_institutional(integer, uuid) to authenticated, service_role;
grant execute on function api.create_entity_draft(text, text, text, text, jsonb), api.update_draft(uuid, jsonb, integer),
  api.propose_edit(uuid, jsonb), api.submit_version(uuid), api.review_version(uuid, text, text, text),
  api.publication_blockers(uuid), api.publish_entity(uuid, text), api.publish_place(uuid),
  api.hide_entity(uuid, text), api.withdraw_entity(uuid, text), api.submit_claim(uuid, text),
  api.decide_claim(uuid, boolean, text), api.grant_consent(text, text, text, uuid), api.withdraw_consent(uuid),
  api.set_political_identity(text[], uuid, uuid), api.upsert_profile(text, text, text, text),
  api.triage_report(uuid, text, text), api.grant_role(uuid, text, text, text), api.revoke_role(uuid),
  api.add_evidence(uuid, text, text, text, date, text), api.set_editorial_facts(uuid, text, date, text),
  api.create_place(uuid, text, text, double precision, double precision, text, boolean),
  api.link_place(uuid, uuid, text)
to authenticated;
