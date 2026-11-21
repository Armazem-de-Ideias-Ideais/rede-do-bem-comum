-- 0004 UP — PROJEÇÃO PÚBLICA (schema pub)
-- As tabelas de pub contêm APENAS colunas publicáveis. Não existe coluna de coordenada
-- exata, endereço, conta, email, gestor, evidência ou autorização em pub.
-- São preenchidas exclusivamente por funções internas (owner) a partir de app.
-- Ocultar/retirar = apagar as linhas de pub (efeito imediato em todas as superfícies).

-- Normalização sem acentos, IMMUTABLE (dicionário explícito) para índices.
create function pub.norm(p text) returns text
language sql immutable parallel safe strict set search_path = '' as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, p))
$$;

-- Classe de contador: disjunta por construção (Plano §7).
create function app.counter_class(p_kind app.entity_kind, p_presence app.presence_type) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case
    when p_kind = 'person' then 'person'
    when p_kind in ('network','movement') then 'network'
    when p_kind = 'resource' or p_presence in ('online','nonspatial') then 'online_resource'
    when p_presence = 'territorial' then 'territorial_group'
    else 'initiative'
  end
$$;

create function app.key_hash(p text) returns text
language sql immutable parallel safe strict set search_path = '' as $$
  select encode(sha256(convert_to(lower(btrim(p)), 'UTF8')), 'hex')
$$;

create function app.url_domain(p_url text) returns text
language sql immutable parallel safe strict set search_path = '' as $$
  select regexp_replace(lower(substring(p_url from '^[a-zA-Z]+://([^/:?#]+)')), '^www\.', '')
$$;

-- ---------- Tabelas públicas ----------
create table pub.entities (
  id                 uuid primary key,
  kind               text not null,
  presence_type      text not null,
  counter_class      text not null,
  name               text not null,
  name_lang          text not null,
  name_norm          text not null,
  country_code       char(2),
  area_id            text,
  public_contact_url text,
  access_conditions  jsonb not null default '{}'::jsonb,
  verification_label text not null,
  activity_checked_month date,   -- só mês/ano
  source_accessed_at date,
  political_identity text[],     -- NULL salvo autodeclaração autorizada e vigente
  is_synthetic       boolean not null,
  search_doc         tsvector not null,
  published_at       timestamptz not null default now()
);
create index pub_entities_search_gin on pub.entities using gin (search_doc);
create index pub_entities_name_trgm on pub.entities using gin (name_norm extensions.gin_trgm_ops);
create index on pub.entities (counter_class);
create index on pub.entities (country_code);

create table pub.entity_texts (
  entity_id uuid not null,
  field     text not null,
  lang      text not null,
  body      text not null,
  state     text not null,
  primary key (entity_id, field, lang)
);

create table pub.entity_categories (
  entity_id   uuid not null,
  category_id text not null,
  is_primary  boolean not null default false,
  primary key (entity_id, category_id)
);
create index on pub.entity_categories (category_id);

create table pub.entity_practices (
  entity_id      uuid not null,
  practice_id    text not null,
  evidence_state text not null,
  primary key (entity_id, practice_id)
);

-- geom já GENERALIZADA: ponto do local (precisão exata em local público) ou label_point
-- da cidade/região. NULL quando precisão = none.
create table pub.places (
  id           uuid primary key,
  kind         text not null,
  precision    text not null,
  area_id      text,
  country_code char(2),
  geom         extensions.geometry(Point, 4326),
  is_synthetic boolean not null
);
create index pub_places_geom_gix on pub.places using gist (geom);

create table pub.entity_places (
  entity_id uuid not null,
  place_id  uuid not null,
  primary key (entity_id, place_id)
);
create index on pub.entity_places (place_id);

create table pub.relationships (
  id          uuid primary key,
  from_entity uuid not null,
  to_entity   uuid not null,
  kind        text not null
);

create table pub.profiles (
  public_id          uuid primary key,   -- ≠ id da conta
  pseudonym          text,
  bio                text,
  area_id            text,
  precision          text not null,
  political_identity text[],
  is_synthetic       boolean not null,
  published_at       timestamptz not null default now()
);

create table pub.offers_needs (
  id          uuid primary key,
  entity_id   uuid not null,
  kind        text not null,
  title       text not null,
  description text,
  valid_until date not null
);

create table pub.entity_aliases (
  old_id    uuid primary key,
  entity_id uuid not null
);

create table pub.entity_sources (
  entity_id   uuid not null,
  source_name text not null,
  url         text,
  accessed_at date,
  licence     text
);
create index on pub.entity_sources (entity_id);

-- Conjunto exportável: somente instituições com permissão específica; nunca pessoas.
create table pub.export_set (
  entity_id uuid primary key,
  licence   text
);

-- ---------- Funções internas de projeção (sem EXECUTE para ninguém além do owner) ----------
create function app._is_suppressed(p_entity uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from app.suppression_tombstones t
                 where t.key_type = 'entity_id' and t.key_hash = app.key_hash(p_entity::text))
$$;

create function app._public_point(p_place app.places) returns extensions.geometry
language plpgsql stable set search_path = '' as $$
declare v_level text; v_parent text; v_pt extensions.geometry;
begin
  if p_place.precision = 'exact_public_venue' then
    return p_place.geom_exact;
  elsif p_place.precision = 'none' or p_place.area_id is null then
    return null;
  end if;
  select level, parent_id, label_point into v_level, v_parent, v_pt from pub.areas where id = p_place.area_id;
  if p_place.precision = 'city' then
    return v_pt;          -- ponto de rótulo da cidade (gazetteer), não da sede
  end if;
  -- region: se a área for cidade, sobe para a região-mãe
  if v_level = 'city' and v_parent is not null then
    select label_point into v_pt from pub.areas where id = v_parent;
  end if;
  return v_pt;
end $$;

create function app._refresh_place(p_place uuid) returns void
language plpgsql set search_path = '' as $$
declare v app.places;
begin
  delete from pub.places where id = p_place;
  select * into v from app.places where id = p_place;
  if not found or v.publication_state <> 'published' or v.activity_state in ('closed','historical','inactive') then
    delete from pub.entity_places where place_id = p_place;
    return;
  end if;
  if exists (select 1 from pub.entity_places where place_id = p_place) then
    insert into pub.places(id, kind, precision, area_id, country_code, geom, is_synthetic)
    values (v.id, v.kind::text, v.precision::text,
            case when v.precision = 'none' then null else v.area_id end,
            (select coalesce(a.country_code, p.country_code) from pub.areas a
               left join pub.areas p on p.id = a.parent_id where a.id = v.area_id),
            app._public_point(v), v.is_synthetic);
  end if;
end $$;

create function app._unproject_entity(p_entity uuid) returns uuid[]
language plpgsql set search_path = '' as $$
declare v_places uuid[];
begin
  select coalesce(array_agg(place_id), '{}') into v_places from pub.entity_places where entity_id = p_entity;
  delete from pub.entity_places    where entity_id = p_entity;
  delete from pub.entity_texts     where entity_id = p_entity;
  delete from pub.entity_categories where entity_id = p_entity;
  delete from pub.entity_practices where entity_id = p_entity;
  delete from pub.relationships    where from_entity = p_entity or to_entity = p_entity;
  delete from pub.offers_needs     where entity_id = p_entity;
  delete from pub.entity_aliases   where entity_id = p_entity or old_id = p_entity;
  delete from pub.entity_sources   where entity_id = p_entity;
  delete from pub.export_set       where entity_id = p_entity;
  delete from pub.entities         where id = p_entity;
  return v_places;
end $$;

create function app._project_entity(p_entity uuid) returns void
language plpgsql set search_path = '' as $$
declare
  e app.entities;
  v_places uuid[];
  v_pid uuid;
  v_identity text[];
  v_texts text;
begin
  v_places := app._unproject_entity(p_entity);
  select * into e from app.entities where id = p_entity;
  if found and e.publication_state = 'published' and not app._is_suppressed(p_entity) then
    -- identidade política: somente declaração ativa com consentimento vigente
    select d.labels into v_identity
      from app.political_identity_declarations d
      join app.consent_records c on c.id = d.consent_id
     where d.entity_id = e.id and d.status = 'active'
       and c.purpose = 'political_identity_public' and c.decision = 'granted' and c.withdrawn_at is null
     order by d.created_at desc limit 1;

    select string_agg(t.body, ' ') into v_texts from app.entity_texts t where t.entity_id = e.id;

    insert into pub.entities(id, kind, presence_type, counter_class, name, name_lang, name_norm,
      country_code, area_id, public_contact_url, access_conditions, verification_label,
      activity_checked_month, source_accessed_at, political_identity, is_synthetic, search_doc)
    values (e.id, e.kind::text, e.presence_type::text, app.counter_class(e.kind, e.presence_type),
      e.original_name, e.original_lang, pub.norm(e.original_name),
      e.country_code, e.area_id, e.public_contact_url, e.access_conditions, e.verification_label::text,
      date_trunc('month', e.last_activity_verified_at)::date, e.source_accessed_at, v_identity, e.is_synthetic,
      -- identidade política NÃO entra no índice de busca
      setweight(to_tsvector('simple'::regconfig, pub.norm(e.original_name)), 'A')
        || to_tsvector('simple'::regconfig, coalesce(pub.norm(v_texts), '')));

    insert into pub.entity_texts(entity_id, field, lang, body, state)
      select entity_id, field, lang, body, state::text from app.entity_texts where entity_id = e.id;
    insert into pub.entity_categories(entity_id, category_id, is_primary)
      select entity_id, category_id, is_primary from app.entity_categories where entity_id = e.id;
    insert into pub.entity_practices(entity_id, practice_id, evidence_state)
      select entity_id, practice_id, evidence_state from app.entity_practices where entity_id = e.id;

    insert into pub.entity_places(entity_id, place_id)
      select ep.entity_id, ep.place_id from app.entity_places ep
        join app.places p on p.id = ep.place_id
       where ep.entity_id = e.id and ep.public_link and p.publication_state = 'published'
         and p.activity_state not in ('closed','historical','inactive');

    insert into pub.relationships(id, from_entity, to_entity, kind)
      select r.id, r.from_entity, r.to_entity, r.kind::text from app.entity_relationships r
       where r.public_authorised and (r.from_entity = e.id or r.to_entity = e.id)
         and exists (select 1 from pub.entities x where x.id = case when r.from_entity = e.id then r.to_entity else r.from_entity end)
      on conflict (id) do nothing;

    insert into pub.offers_needs(id, entity_id, kind, title, description, valid_until)
      select id, entity_id, kind, title, description, valid_until from app.offers_needs
       where entity_id = e.id and visibility = 'public' and publication_state = 'published'
         and valid_until >= current_date;

    insert into pub.entity_aliases(old_id, entity_id)
      select old_id, entity_id from app.entity_aliases where entity_id = e.id;

    insert into pub.entity_sources(entity_id, source_name, url, accessed_at, licence)
      select sr.entity_id, s.name, case when sr.public_ref_safe then sr.url end, sr.accessed_at, sr.licence
        from app.source_records sr join app.sources s on s.id = sr.source_id where sr.entity_id = e.id;

    if e.export_permission and e.kind <> 'person' then
      insert into pub.export_set(entity_id, licence) values (e.id, e.rights_basis);
    end if;

    select array_agg(place_id) into v_places from (
      select unnest(v_places) as place_id union select place_id from pub.entity_places where entity_id = e.id) s;
  end if;

  foreach v_pid in array coalesce(v_places, '{}') loop
    perform app._refresh_place(v_pid);
  end loop;
end $$;

create function app._project_profile(p_account uuid) returns void
language plpgsql set search_path = '' as $$
declare pr app.profiles; v_identity text[]; v_loc boolean;
begin
  select * into pr from app.profiles where account_id = p_account;
  if not found then return; end if;
  delete from pub.profiles where public_id = pr.public_id;
  if not exists (select 1 from app.consent_records c where c.account_id = p_account
                 and c.purpose = 'public_presentation' and c.decision = 'granted' and c.withdrawn_at is null) then
    return;
  end if;
  v_loc := exists (select 1 from app.consent_records c where c.account_id = p_account
                 and c.purpose = 'location_city_region' and c.decision = 'granted' and c.withdrawn_at is null);
  select d.labels into v_identity
    from app.political_identity_declarations d join app.consent_records c on c.id = d.consent_id
   where d.profile_account_id = p_account and d.status = 'active'
     and c.purpose = 'political_identity_public' and c.decision = 'granted' and c.withdrawn_at is null
   order by d.created_at desc limit 1;
  insert into pub.profiles(public_id, pseudonym, bio, area_id, precision, political_identity, is_synthetic)
  values (pr.public_id, pr.pseudonym, pr.bio,
          case when v_loc and pr.precision <> 'none' then pr.area_id end,
          case when v_loc then pr.precision::text else 'none' end,
          v_identity, pr.is_synthetic);
end $$;

revoke all on function app._is_suppressed(uuid), app._public_point(app.places), app._refresh_place(uuid),
  app._unproject_entity(uuid), app._project_entity(uuid), app._project_profile(uuid) from public;
