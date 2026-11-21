-- 0009 DOWN — restaura as funções de projeção e de tombstone do Marco B e remove a carga do Marco C
drop function if exists app.seed_load_candidate(jsonb), app.seed_load_record(jsonb), app._upsert_record(jsonb, text),
  app._validate_record(jsonb), app._record_tombstoned(jsonb);

-- versões originais (copiadas literalmente de 0004 e 0006)
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
  delete from pub.entities         where id = p_entity;
  return v_places;
end $$;

create or replace function app._project_entity(p_entity uuid) returns void
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

create or replace function app._tombstone(p_entity uuid, p_reason text) returns void
language plpgsql set search_path = '' as $$
declare e app.entities;
begin
  select * into e from app.entities where id = p_entity;
  insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
  values (p_entity, 'entity_id', app.key_hash(p_entity::text), p_reason, auth.uid())
  on conflict do nothing;
  insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
  select p_entity, 'name_country', app.key_hash(pub.norm(e.original_name) || '|' || coalesce(e.country_code, '')), p_reason, auth.uid()
  on conflict do nothing;
  if e.public_contact_url is not null then
    insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
    values (p_entity, 'domain', app.key_hash(app.url_domain(e.public_contact_url)), p_reason, auth.uid())
    on conflict do nothing;
  end if;
  insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code, created_by)
  select p_entity, 'source_external', app.key_hash(sr.source_id::text || '|' || sr.external_id), p_reason, auth.uid()
    from app.source_records sr where sr.entity_id = p_entity
  on conflict do nothing;
end $$;

create or replace function app.publication_blockers(p_entity uuid) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare e app.entities; b text[] := '{}';
begin
  select * into e from app.entities where id = p_entity;
  if not found then return array['inexistente']; end if;
  if e.original_name is null or char_length(e.original_name) < 2 then b := b || 'nome'; end if;
  if not exists (select 1 from app.source_records where entity_id = e.id)
     and not exists (select 1 from app.evidence where entity_id = e.id and url is not null) then
    b := b || 'fonte';
  end if;
  if e.activity_state <> 'active' or e.last_activity_verified_at is null then b := b || 'atividade_atual'; end if;
  if not exists (select 1 from app.evidence where entity_id = e.id and level in ('E2','E3')) then
    b := b || 'evidencia_E2'; end if;
  if not exists (select 1 from app.reviews where entity_id = e.id and decision = 'approve'
                 and kind in ('source','activity','representation')) then
    b := b || 'revisao_registrada'; end if;
  if e.rights_basis is null then b := b || 'direitos'; end if;
  if app._is_suppressed(e.id) then b := b || 'suprimida'; end if;
  if e.kind = 'person' and not exists (select 1 from app.consent_records c where c.entity_id = e.id
       and c.purpose = 'public_presentation' and c.decision = 'granted' and c.withdrawn_at is null) then
    b := b || 'adesao_pessoal'; end if;
  return b;
end $$;

drop function if exists app._project_offers(uuid), app._is_shared_domain(text), app._source_uuid(text);

-- fontes fixas da carga (os registros de origem dessas fontes saem junto)
delete from app.source_records where source_id in ('b0b0b0b0-0000-4000-8000-000000000001','b0b0b0b0-0000-4000-8000-000000000002');
delete from app.sources where id in ('b0b0b0b0-0000-4000-8000-000000000001','b0b0b0b0-0000-4000-8000-000000000002');
