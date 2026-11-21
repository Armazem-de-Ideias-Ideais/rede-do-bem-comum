-- 0009 UP — Marco C: projeção pública ampliada, tombstones ampliados e carga de registros
-- Substitui app._project_entity / app._unproject_entity / app._tombstone (o DOWN restaura as versões do Marco B).

-- ---------- Fontes fixas da carga inicial ----------
insert into app.sources(id, name, base_url, domain, licence, terms_url, adapter_allowed, notes) values
  ('b0b0b0b0-0000-4000-8000-000000000001', 'Pesquisa Rede do Bem Comum',
   'https://github.com/Armazem-de-Ideias-Ideais/rede-do-bem-comum', 'github.com', null, null, false, 'key:research'),
  ('b0b0b0b0-0000-4000-8000-000000000002', 'Karte von Morgen / OpenFairDB',
   'https://kartevonmorgen.org', 'kartevonmorgen.org', 'ODbL-1.0', 'https://opendatacommons.org/licenses/odbl/1-0/', false, 'key:kvm')
on conflict (id) do nothing;

create function app._source_uuid(p_key text) returns uuid
language sql immutable parallel safe set search_path = '' as $$
  select case p_key when 'kvm' then 'b0b0b0b0-0000-4000-8000-000000000002'::uuid
                    else 'b0b0b0b0-0000-4000-8000-000000000001'::uuid end
$$;

create function app._is_shared_domain(p_domain text) returns boolean
language sql stable set search_path = '' as $$
  select p_domain is null or p_domain !~ '\.' or exists (
    select 1 from app.shared_domains s where p_domain = s.domain or p_domain like '%.' || s.domain)
$$;

-- ---------- Projeção (versão Marco C) ----------
create or replace function app._unproject_entity(p_entity uuid) returns uuid[]
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
  delete from pub.slug_redirects   where entity_id = p_entity;
  delete from pub.entities         where id = p_entity;
  return v_places;
end $$;

create function app._project_offers(p_entity uuid) returns void
language plpgsql set search_path = '' as $$
begin
  delete from pub.offers_needs where entity_id = p_entity;
  if exists (select 1 from pub.entities where id = p_entity) then
    insert into pub.offers_needs(id, entity_id, kind, title, description, valid_until, topic, published_at)
      select id, entity_id, kind, title, description, valid_until, topic, updated_at from app.offers_needs
       where entity_id = p_entity and visibility = 'public' and publication_state = 'published'
         and valid_until >= current_date;
  end if;
end $$;

create or replace function app._project_entity(p_entity uuid) returns void
language plpgsql set search_path = '' as $$
declare
  e app.entities;
  v_places uuid[];
  v_pid uuid;
  v_identity text[];
  v_texts text;
  v_level text;
  v_pt extensions.geometry;
begin
  v_places := app._unproject_entity(p_entity);
  select * into e from app.entities where id = p_entity;
  if found and e.publication_state = 'published' and not app._is_suppressed(p_entity) then
    select d.labels into v_identity
      from app.political_identity_declarations d
      join app.consent_records c on c.id = d.consent_id
     where d.entity_id = e.id and d.status = 'active'
       and c.purpose = 'political_identity_public' and c.decision = 'granted' and c.withdrawn_at is null
     order by d.created_at desc limit 1;

    select string_agg(t.body, ' ') into v_texts from app.entity_texts t where t.entity_id = e.id;
    select a.level, a.label_point into v_level, v_pt from pub.areas a where a.id = e.area_id;

    insert into pub.entities(id, kind, presence_type, counter_class, name, name_lang, name_norm,
      country_code, area_id, public_contact_url, access_conditions, verification_label,
      activity_checked_month, source_accessed_at, political_identity, is_synthetic, search_doc,
      slug, website_url, city, world_region, activity_badge, network_of, alt_names, attribution,
      is_managed, location_precision, lon, lat, search_text)
    values (e.id, e.kind::text, e.presence_type::text, app.counter_class(e.kind, e.presence_type),
      e.original_name, e.original_lang, pub.norm(e.original_name),
      e.country_code, e.area_id, e.public_contact_url, e.access_conditions, e.verification_label::text,
      date_trunc('month', e.last_activity_verified_at)::date, e.source_accessed_at, v_identity, e.is_synthetic,
      -- identidade política NÃO entra no índice de busca
      setweight(to_tsvector('simple'::regconfig, pub.norm(e.original_name)), 'A')
        || setweight(to_tsvector('simple'::regconfig, coalesce(pub.norm(array_to_string(e.alt_names, ' ')), '')), 'A')
        || to_tsvector('simple'::regconfig, coalesce(pub.norm(concat_ws(' ', e.city, v_texts)), '')),
      e.slug, e.website_url, e.city, e.world_region, e.activity_badge, e.network_of, e.alt_names, e.attribution,
      exists (select 1 from app.entity_managers m where m.entity_id = e.id and m.status = 'active'),
      case when v_pt is null then 'none' else coalesce(v_level, 'none') end,
      round(extensions.st_x(v_pt)::numeric, 4), round(extensions.st_y(v_pt)::numeric, 4),
      coalesce(pub.norm(concat_ws(' ', e.original_name, array_to_string(e.alt_names, ' '), e.city)), ''));

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

    perform app._project_offers(e.id);

    insert into pub.entity_aliases(old_id, entity_id)
      select old_id, entity_id from app.entity_aliases where entity_id = e.id;

    insert into pub.slug_redirects(slug, entity_id)
      select h.slug, h.entity_id from app.entity_slug_history h where h.entity_id = e.id
      on conflict (slug) do update set entity_id = excluded.entity_id;

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

-- ---------- Tombstones: também o domínio do site próprio (exceto plataformas compartilhadas) ----------
create or replace function app._tombstone(p_entity uuid, p_reason text) returns void
language plpgsql set search_path = '' as $$
declare e app.entities; v_dom text;
begin
  select * into e from app.entities where id = p_entity;
  insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
  values (p_entity, 'entity_id', app.key_hash(p_entity::text), p_reason, auth.uid())
  on conflict do nothing;
  insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
  select p_entity, 'name_country', app.key_hash(pub.norm(e.original_name) || '|' || coalesce(e.country_code, '')), p_reason, auth.uid()
  on conflict do nothing;
  foreach v_dom in array array[app.url_domain(e.public_contact_url), app.url_domain(e.website_url)] loop
    if v_dom is not null and not app._is_shared_domain(v_dom) then
      insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
      values (p_entity, 'domain', app.key_hash(v_dom), p_reason, auth.uid())
      on conflict do nothing;
    end if;
  end loop;
  insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
  select p_entity, 'source_external', app.key_hash(sr.source_id::text || '|' || sr.external_id), p_reason, auth.uid()
    from app.source_records sr where sr.entity_id = p_entity
  on conflict do nothing;
end $$;

-- ---------- Correção do Marco B: publication_blockers ----------
-- Em 0006, `b := b || 'nome'` tenta ler 'nome' como literal de array e falha ("malformed array literal")
-- sempre que existe algum bloqueio. A versão abaixo só acrescenta ::text. O DOWN restaura a original.
create or replace function app.publication_blockers(p_entity uuid) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare e app.entities; b text[] := '{}';
begin
  select * into e from app.entities where id = p_entity;
  if not found then return array['inexistente']; end if;
  if e.original_name is null or char_length(e.original_name) < 2 then b := b || 'nome'::text; end if;
  if not exists (select 1 from app.source_records where entity_id = e.id)
     and not exists (select 1 from app.evidence where entity_id = e.id and url is not null) then
    b := b || 'fonte'::text;
  end if;
  if e.activity_state <> 'active' or e.last_activity_verified_at is null then b := b || 'atividade_atual'::text; end if;
  if not exists (select 1 from app.evidence where entity_id = e.id and level in ('E2','E3')) then
    b := b || 'evidencia_E2'::text; end if;
  if not exists (select 1 from app.reviews where entity_id = e.id and decision = 'approve'
                 and kind in ('source','activity','representation')) then
    b := b || 'revisao_registrada'::text; end if;
  if e.rights_basis is null then b := b || 'direitos'::text; end if;
  if app._is_suppressed(e.id) then b := b || 'suprimida'::text; end if;
  if e.kind = 'person' and not exists (select 1 from app.consent_records c where c.entity_id = e.id
       and c.purpose = 'public_presentation' and c.decision = 'granted' and c.withdrawn_at is null) then
    b := b || 'adesao_pessoal'::text; end if;
  return b;
end $$;

-- ---------- Carga de registros (seed público e aceite de convite) ----------
-- Registro = JSON com lista FECHADA de chaves (ver seed/build_seed.py). Campos internos da pesquisa não entram.
create function app._record_tombstoned(p jsonb) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from app.suppression_tombstones t where
       (t.key_type = 'entity_id' and t.key_hash = app.key_hash(p->>'id'))
    or (t.key_type = 'source_external' and t.key_hash in (
          app.key_hash(app._source_uuid('research')::text || '|' || coalesce(p->>'research_id', '')),
          app.key_hash(app._source_uuid('kvm')::text || '|' || coalesce(p->>'research_id', ''))))
    or (t.key_type = 'name_country' and t.key_hash = app.key_hash(pub.norm(p->>'name') || '|' || coalesce(p->>'country', '')))
    or (p->>'own_url' is not null and t.key_type = 'domain'
        and t.key_hash = app.key_hash(app.url_domain(p->>'own_url'))))
$$;

create function app._validate_record(p jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare k text;
begin
  if jsonb_typeof(p) <> 'object' then raise exception 'registro inválido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('id','research_id','name','alt_names','kind','presence','country','city','region','categories',
                 'summary_pt','summary_en','own_url','source_url','source_key','evidence','last_activity','activity_badge',
                 'network_of','area_id','city_lat','city_lng','location_precision','attribution','collected_on') then
      raise exception 'campo não permitido no registro: %', left(k, 40) using errcode = '22023';
    end if;
  end loop;
  if coalesce(p->>'id', '') !~ '^[0-9a-f-]{36}$' or coalesce(p->>'research_id', '') !~ '^[A-Z0-9-]{3,40}$' then
    raise exception 'identificadores do registro inválidos' using errcode = '22023';
  end if;
end $$;

create function app._upsert_record(p jsonb, p_mode text default 'seed') returns text
language plpgsql set search_path = '' as $$
declare
  v_id    uuid := (p->>'id')::uuid;
  e       app.entities;
  v_src   uuid := app._source_uuid(coalesce(p->>'source_key', 'research'));
  v_area  text := nullif(p->>'area_id', '');
  v_kind  app.entity_kind := (p->>'kind')::app.entity_kind;
  v_pres  app.presence_type := (p->>'presence')::app.presence_type;
  v_badge text := coalesce(p->>'activity_badge', 'to_confirm');
  v_last  date := case when p->>'last_activity' ~ '^\d{4}-\d{2}$' then (p->>'last_activity' || '-01')::date end;
  v_coll  date := coalesce((p->>'collected_on')::date, current_date);
  v_place uuid := md5(v_id::text || ':place')::uuid;
  v_pkind app.place_kind;
  v_site  text := nullif(p->>'own_url', '');
  v_res   text;
  c       text;
  i       integer := 0;
begin
  perform app._validate_record(p);
  if v_kind = 'person' then raise exception 'pessoas não entram por carga' using errcode = '22023'; end if;
  if app._record_tombstoned(p) then return 'blocked_by_tombstone'; end if;
  select * into e from app.entities where id = v_id;
  if found then
    if e.publication_state <> 'published' then return 'kept_unpublished'; end if;   -- nunca desfaz ocultação/retirada
    if exists (select 1 from app.entity_managers m where m.entity_id = v_id and m.status = 'active') then
      return 'kept_managed';                                                       -- gestão da iniciativa tem precedência
    end if;
  end if;
  if v_site is not null and (v_site !~ '^https?://[^\s<>"]+$' or char_length(v_site) > 500) then v_site := null; end if;

  -- área = cidade; ponto público = centro da cidade informado na pesquisa (nunca a sede)
  if v_area is not null and (p->>'city_lat') is not null and (p->>'city_lng') is not null
     and p->>'location_precision' = 'city' then
    insert into pub.areas(id, level, country_code, name, label_point)
    values (v_area, 'city', nullif(p->>'country', ''), p->>'city',
            extensions.st_setsrid(extensions.st_makepoint((p->>'city_lng')::float8, (p->>'city_lat')::float8), 4326))
    on conflict (id) do nothing;
  else
    v_area := null;
  end if;

  if e.id is null then
    insert into app.entities(id, kind, presence_type, original_name, original_lang, country_code, area_id,
      research_state, activity_state, participation_state, publication_state, verification_label,
      last_activity_verified_at, source_accessed_at, rights_basis, research_id, website_url, city, world_region,
      activity_badge, network_of, alt_names, attribution)
    values (v_id, v_kind, v_pres, p->>'name', 'und', nullif(p->>'country', ''), v_area,
      case when v_badge = 'to_confirm' then 'verifying' else 'sufficient_evidence' end::app.research_state,
      case when v_badge = 'active_recent' then 'active' else 'unconfirmed' end::app.activity_state,
      'not_requested', 'draft',
      case v_badge when 'active_recent' then 'activity_checked' when 'source_checked' then 'source_checked' else 'found' end::app.verification_label,
      v_last, v_coll, 'publicacao_com_aviso_e_retirada_2026-11-21', p->>'research_id', v_site, nullif(p->>'city', ''),
      nullif(p->>'region', ''), v_badge, nullif(p->>'network_of', ''),
      coalesce(array(select jsonb_array_elements_text(coalesce(p->'alt_names', '[]'::jsonb)) limit 10), '{}'),
      nullif(p->>'attribution', ''));
    v_res := 'inserted';
  else
    update app.entities set kind = v_kind, presence_type = v_pres, original_name = p->>'name',
      country_code = nullif(p->>'country', ''), area_id = v_area,
      activity_state = case when v_badge = 'active_recent' then 'active' else 'unconfirmed' end::app.activity_state,
      verification_label = case v_badge when 'active_recent' then 'activity_checked' when 'source_checked' then 'source_checked' else 'found' end::app.verification_label,
      last_activity_verified_at = v_last, source_accessed_at = v_coll, website_url = v_site, city = nullif(p->>'city', ''),
      world_region = nullif(p->>'region', ''), activity_badge = v_badge, network_of = nullif(p->>'network_of', ''),
      alt_names = coalesce(array(select jsonb_array_elements_text(coalesce(p->'alt_names', '[]'::jsonb)) limit 10), '{}'),
      attribution = nullif(p->>'attribution', ''), updated_at = now()
     where id = v_id;
    v_res := 'updated';
  end if;

  -- textos: resumo PT original; EN tradução automática sem revisão (ou nenhum)
  delete from app.entity_texts where entity_id = v_id and field = 'description';
  if nullif(p->>'summary_pt', '') is not null then
    insert into app.entity_texts(entity_id, field, lang, body, state) values (v_id, 'description', 'pt', p->>'summary_pt', 'original');
  end if;
  if nullif(p->>'summary_en', '') is not null then
    insert into app.entity_texts(entity_id, field, lang, body, state) values (v_id, 'description', 'en', p->>'summary_en', 'machine_unreviewed');
  end if;

  -- famílias: a primeira é a primária
  delete from app.entity_categories where entity_id = v_id;
  for c in select jsonb_array_elements_text(coalesce(p->'categories', '[]'::jsonb)) loop
    if exists (select 1 from pub.categories where id = c)
       and not exists (select 1 from app.entity_categories where entity_id = v_id and category_id = c) then
      insert into app.entity_categories(entity_id, category_id, is_primary, basis) values (v_id, c, i = 0, 'editorial');
      i := i + 1;
    end if;
  end loop;

  -- fonte e proveniência (URL da fonte é pública; licença por registro)
  delete from app.source_records where entity_id = v_id and source_id <> v_src;
  insert into app.source_records(source_id, external_id, url, accessed_at, licence, payload, entity_id, status, public_ref_safe)
  values (v_src, p->>'research_id', p->>'source_url', v_coll,
          case when coalesce(p->>'source_key', 'research') = 'kvm' then 'ODbL-1.0' end, '{}'::jsonb, v_id, 'draft_created', true)
  on conflict (source_id, external_id) do update set url = excluded.url, accessed_at = excluded.accessed_at,
     licence = excluded.licence, entity_id = excluded.entity_id, public_ref_safe = true;
  if not exists (select 1 from app.field_provenance where entity_id = v_id and field_name = 'name') then
    insert into app.field_provenance(entity_id, field_name, origin, source_record_id, licence)
    select v_id, 'name', 'source', sr.id, sr.licence from app.source_records sr where sr.entity_id = v_id limit 1;
  end if;
  if not exists (select 1 from app.evidence where entity_id = v_id) then
    insert into app.evidence(entity_id, kind, level, url, observed_at, note)
    values (v_id, coalesce(nullif(p->>'evidence', ''), 'directory_reference')::app.evidence_kind,
            case when p->>'evidence' = 'primary_page_read' then 'E2' else 'E1' end,
            case when p->>'source_url' ~ '^https?://' then p->>'source_url' end, coalesce(v_last, v_coll),
            'carga ' || p_mode);
  end if;

  -- local: um por ficha, no centro da cidade. Só iniciativas físicas/híbridas são "locais físicos";
  -- grupos territoriais viram área; redes, movimentos e recursos não geram local (aparecem pela cidade).
  v_pkind := case
    when v_area is null then null
    when v_pres in ('physical','hybrid') and v_kind not in ('network','movement','resource') then 'physical_venue'
    when v_pres = 'territorial' and v_kind not in ('network','movement','resource') then 'territorial_area'
    else null end::app.place_kind;
  if v_pkind is null then
    delete from app.entity_places where entity_id = v_id and place_id = v_place;
    delete from app.places p2 where p2.id = v_place and not exists (select 1 from app.entity_places x where x.place_id = v_place);
  else
    insert into app.places(id, kind, area_id, precision, activity_state, publication_state)
    values (v_place, v_pkind, v_area, 'city',
            case when v_badge = 'active_recent' then 'active' else 'unconfirmed' end::app.activity_state, 'published')
    on conflict (id) do update set kind = excluded.kind, area_id = excluded.area_id, precision = 'city',
       activity_state = excluded.activity_state, publication_state = 'published', updated_at = now();
    insert into app.entity_places(entity_id, place_id, role) values (v_id, v_place, 'venue') on conflict do nothing;
  end if;

  -- publicação: decisão editorial de 21/11/2026 (publicar com aviso e retirada fácil). Não usa
  -- publication_blockers de propósito: a atividade pode estar "a confirmar", e isso é mostrado na ficha.
  update app.entities set publication_state = 'published' where id = v_id;
  perform app._project_entity(v_id);
  if v_res = 'inserted' then
    perform app._audit('entity.published_batch', 'entities', v_id::text, jsonb_build_object('mode', p_mode));
  end if;
  return v_res;
end $$;

-- Ponto de entrada do seed público (somente servidor/owner).
create function app.seed_load_record(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from app.invite_candidates where research_id = p->>'research_id' or id = (p->>'id')::uuid) then
    return 'skipped_private_candidate';
  end if;
  return app._upsert_record(p, 'seed');
end $$;

-- Ponto de entrada da carga PRIVADA de candidatos a convite (somente servidor/owner). Nunca projeta.
create function app.seed_load_candidate(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_status text;
begin
  perform app._validate_record(p);
  v_id := (p->>'id')::uuid;
  if app._record_tombstoned(p) then return 'blocked_by_tombstone'; end if;
  if exists (select 1 from app.entities where id = v_id or research_id = p->>'research_id') then
    return 'skipped_already_entity';
  end if;
  select status into v_status from app.invite_candidates where id = v_id;
  if v_status is null then
    insert into app.invite_candidates(id, research_id, data) values (v_id, p->>'research_id', p);
    return 'inserted';
  elsif v_status in ('pending','invited') then
    update app.invite_candidates set data = p, updated_at = now() where id = v_id;
    return 'updated';
  end if;
  return 'kept_' || v_status;
end $$;

revoke all on function app._source_uuid(text), app._is_shared_domain(text), app._project_offers(uuid),
  app._record_tombstoned(jsonb), app._validate_record(jsonb), app._upsert_record(jsonb, text),
  app.seed_load_record(jsonb), app.seed_load_candidate(jsonb) from public;
grant execute on function app.seed_load_record(jsonb), app.seed_load_candidate(jsonb) to service_role;
