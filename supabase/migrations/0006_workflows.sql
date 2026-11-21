-- 0006 UP — fluxos editoriais e de privacidade (funções SECURITY DEFINER em schema NÃO exposto)
-- Todas: search_path = '', nomes qualificados, EXECUTE revogado de PUBLIC e concedido por papel.
-- Mensagens de "não encontrado" são idênticas para inexistente e sem permissão (anti-enumeração).

-- ---------- utilitários ----------
create function app._require_uid() returns uuid
language plpgsql stable set search_path = '' as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'autenticação necessária' using errcode = '28000'; end if;
  return v;
end $$;

create function app._not_found() returns void
language plpgsql set search_path = '' as $$
begin
  raise exception 'registro não encontrado' using errcode = 'P0002';
end $$;

create function app._audit(p_action text, p_table text, p_id text, p_details jsonb default '{}'::jsonb) returns void
language sql set search_path = '' as $$
  insert into app.audit_log(actor, action, target_table, target_id, details)
  values (auth.uid(), p_action, p_table, p_id, coalesce(p_details, '{}'::jsonb))
$$;

create function app._rate_limit(p_key text, p_max integer, p_window interval) returns void
language plpgsql set search_path = '' as $$
declare v_bucket timestamptz := to_timestamp(floor(extract(epoch from now()) / extract(epoch from p_window)) * extract(epoch from p_window));
        v_hits integer;
begin
  insert into app.rate_limits(key, bucket_start, hits) values (p_key, v_bucket, 1)
  on conflict (key, bucket_start) do update set hits = app.rate_limits.hits + 1
  returning hits into v_hits;
  if v_hits > p_max then
    raise exception 'limite de envios excedido; tente mais tarde' using errcode = '54000';
  end if;
end $$;

create function app._outbox(p_entity uuid, p_reason text) returns void
language sql set search_path = '' as $$
  insert into app.cache_invalidation_outbox(entity_id, place_ids, reason)
  select p_entity, coalesce(array_agg(ep.place_id), '{}'), p_reason
    from app.entity_places ep where ep.entity_id = p_entity
$$;

-- Payload de versão: lista FECHADA de chaves (dados não confiáveis).
create function app._validate_payload(p jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare k text;
begin
  if jsonb_typeof(p) <> 'object' then raise exception 'payload inválido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('name','descriptions','categories','primary_category','practices','contact_url','access_conditions',
                 'country_code','area_id') then
      raise exception 'campo não permitido no payload: %', left(k, 40) using errcode = '22023';
    end if;
  end loop;
  if p ? 'name' and (jsonb_typeof(p->'name') <> 'string' or char_length(p->>'name') not between 2 and 180) then
    raise exception 'nome inválido' using errcode = '22023';
  end if;
  if p ? 'contact_url' and (p->>'contact_url') !~ '^https://[^\s<>"]+$' then
    raise exception 'URL de contato deve ser https e sem caracteres de marcação' using errcode = '22023';
  end if;
  if p ? 'country_code' and (p->>'country_code') !~ '^[A-Z]{2}$' then
    raise exception 'país inválido' using errcode = '22023';
  end if;
  if p ? 'categories' and jsonb_typeof(p->'categories') <> 'array' then
    raise exception 'categorias devem ser lista' using errcode = '22023';
  end if;
  if p ? 'practices' and jsonb_typeof(p->'practices') <> 'array' then
    raise exception 'práticas devem ser lista' using errcode = '22023';
  end if;
  if p ? 'descriptions' and jsonb_typeof(p->'descriptions') <> 'object' then
    raise exception 'descrições devem ser objeto idioma→texto' using errcode = '22023';
  end if;
end $$;

create function app._apply_payload(p_entity uuid, p jsonb) returns void
language plpgsql set search_path = '' as $$
declare v_lang text; k text; v text;
begin
  select original_lang into v_lang from app.entities where id = p_entity;
  update app.entities set
    original_name     = coalesce(p->>'name', original_name),
    public_contact_url = case when p ? 'contact_url' then p->>'contact_url' else public_contact_url end,
    access_conditions = case when p ? 'access_conditions' then p->'access_conditions' else access_conditions end,
    country_code      = coalesce(p->>'country_code', country_code),
    area_id           = coalesce(p->>'area_id', area_id),
    updated_at = now()
  where id = p_entity;
  if p ? 'descriptions' then
    delete from app.entity_texts where entity_id = p_entity and field = 'description';
    for k, v in select key, value from jsonb_each_text(p->'descriptions') loop
      insert into app.entity_texts(entity_id, field, lang, body, state)
      values (p_entity, 'description', k, v,
              case when k = v_lang then 'original'::app.text_state else 'machine_unreviewed'::app.text_state end);
    end loop;
  end if;
  if p ? 'categories' then
    delete from app.entity_categories where entity_id = p_entity;
    insert into app.entity_categories(entity_id, category_id, is_primary)
      select distinct p_entity, c, c = (p->>'primary_category') from jsonb_array_elements_text(p->'categories') c;
  end if;
  if p ? 'practices' then
    delete from app.entity_practices where entity_id = p_entity;
    insert into app.entity_practices(entity_id, practice_id)
      select distinct p_entity, x from jsonb_array_elements_text(p->'practices') x;
  end if;
end $$;

-- ---------- Rascunho, edição e submissão ----------
create function app.create_entity_draft(p_kind app.entity_kind, p_presence app.presence_type,
  p_name text, p_lang text, p_payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_entity uuid; v_version uuid;
begin
  perform app._rate_limit('draft:' || v_uid, 20, interval '1 day');
  if p_kind = 'person' then
    raise exception 'pessoas participam por perfil próprio, não por ficha de entidade' using errcode = '22023';
  end if;
  perform app._validate_payload(coalesce(p_payload, '{}'::jsonb));
  insert into app.entities(kind, presence_type, original_name, original_lang, created_by, research_state, publication_state,
                           country_code, area_id)
  values (p_kind, p_presence, p_name, coalesce(p_lang, 'und'), v_uid, 'triage', 'draft',
          p_payload->>'country_code', p_payload->>'area_id')
  returning id into v_entity;
  insert into app.entity_managers(entity_id, account_id, status) values (v_entity, v_uid, 'pending_verification');
  insert into app.entity_versions(entity_id, version_no, base_version_no, author_id, payload)
  values (v_entity, 1, 0, v_uid, coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('name', p_name))
  returning id into v_version;
  insert into app.field_provenance(entity_id, field_name, origin, participant_managed)
  values (v_entity, 'name', 'participant', true);
  perform app._audit('entity.draft_created', 'entities', v_entity::text);
  return jsonb_build_object('entity_id', v_entity, 'version_id', v_version);
end $$;

create function app.update_draft(p_version uuid, p_payload jsonb, p_expected_row_version integer) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v app.entity_versions;
begin
  select * into v from app.entity_versions where id = p_version for update;
  if not found or v.author_id is distinct from v_uid then perform app._not_found(); end if;
  if v.status <> 'draft' then
    raise exception 'versão já submetida está congelada' using errcode = 'P0001';
  end if;
  if v.row_version <> p_expected_row_version then
    raise exception 'conflito de edição: versão alterada em outra sessão' using errcode = '40001';
  end if;
  perform app._validate_payload(p_payload);
  update app.entity_versions set payload = p_payload, row_version = row_version + 1 where id = p_version;
  return v.row_version + 1;
end $$;

create function app.propose_edit(p_entity uuid, p_payload jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); e app.entities; v_id uuid;
begin
  select * into e from app.entities where id = p_entity for update;
  if not found or not (app.is_entity_manager(p_entity)
                       or (e.created_by = v_uid and e.publication_state in ('draft','in_review'))) then
    perform app._not_found();
  end if;
  perform app._rate_limit('edit:' || v_uid, 50, interval '1 day');
  perform app._validate_payload(p_payload);
  insert into app.entity_versions(entity_id, version_no, base_version_no, author_id, payload)
  values (p_entity, (select coalesce(max(version_no), 0) + 1 from app.entity_versions where entity_id = p_entity),
          e.current_version_no, v_uid, p_payload)
  returning id into v_id;
  return v_id;
end $$;

create function app.submit_version(p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v app.entity_versions;
begin
  select * into v from app.entity_versions where id = p_version for update;
  if not found or v.author_id is distinct from v_uid then perform app._not_found(); end if;
  if v.status <> 'draft' then raise exception 'versão não está em rascunho' using errcode = 'P0001'; end if;
  update app.entity_versions
     set status = 'submitted', submitted_at = now(),
         payload_hash = encode(sha256(convert_to(v.payload::text, 'UTF8')), 'hex')
   where id = p_version;
  -- ficha publicada continua publicada: a proposta não toca na projeção pública
  update app.entities set publication_state = 'in_review'
   where id = v.entity_id and publication_state = 'draft';
  perform app._audit('version.submitted', 'entity_versions', p_version::text);
end $$;

create function app.review_version(p_version uuid, p_decision app.review_decision,
  p_kind app.review_kind, p_rationale text) returns text
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v app.entity_versions; e app.entities; v_status app.version_status;
begin
  select * into v from app.entity_versions where id = p_version for update;
  if not found or not app.curator_can(v.entity_id) then perform app._not_found(); end if;
  select * into e from app.entities where id = v.entity_id for update;
  if v.author_id = v_uid or e.created_by = v_uid or app.is_entity_manager(e.id) then
    raise exception 'conflito de interesse: não é possível revisar a própria proposta ou ficha' using errcode = '42501';
  end if;
  if v.status <> 'submitted' then raise exception 'versão não está submetida' using errcode = 'P0001'; end if;
  insert into app.reviews(entity_id, version_id, reviewer_id, kind, decision, rationale)
  values (e.id, v.id, v_uid, p_kind, p_decision, p_rationale);
  if p_decision = 'approve' then
    if v.base_version_no <> e.current_version_no then
      v_status := 'conflict';      -- outra versão foi aplicada depois que esta foi criada
    else
      perform app._apply_payload(e.id, v.payload);
      update app.entities set current_version_no = v.version_no where id = e.id;
      v_status := 'approved';
    end if;
  elsif p_decision = 'reject' then v_status := 'rejected';
  else v_status := 'changes_requested';
  end if;
  update app.entity_versions set status = v_status where id = v.id;
  if v_status = 'approved' and e.publication_state = 'published' then
    perform app._project_entity(e.id);
    perform app._outbox(e.id, 'version_approved');
  end if;
  perform app._audit('version.reviewed', 'entity_versions', v.id::text,
                     jsonb_build_object('decision', p_decision, 'result', v_status, 'kind', p_kind));
  return v_status::text;
end $$;

-- ---------- Regras de publicação ----------
create function app.publication_blockers(p_entity uuid) returns text[]
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

-- Núcleo de publicação (sem checagem de papel) — usado pelas funções com papel e pelo seed.
create function app._publish_entity(p_entity uuid) returns void
language plpgsql set search_path = '' as $$
declare b text[] := app.publication_blockers(p_entity);
begin
  if cardinality(b) > 0 then
    raise exception 'publicação bloqueada: %', array_to_string(b, ', ') using errcode = 'P0001';
  end if;
  update app.entities set publication_state = 'published', updated_at = now() where id = p_entity;
  perform app._project_entity(p_entity);
  perform app._outbox(p_entity, 'published');
end $$;

create function app.publish_entity(p_entity uuid, p_rationale text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  if not app.curator_can(p_entity) then perform app._not_found(); end if;
  if app.is_entity_creator(p_entity) or app.is_entity_manager(p_entity) then
    raise exception 'conflito de interesse: não é possível publicar ficha própria' using errcode = '42501';
  end if;
  insert into app.reviews(entity_id, reviewer_id, kind, decision, rationale)
  values (p_entity, v_uid, 'publication', 'approve', p_rationale);
  perform app._publish_entity(p_entity);
  perform app._audit('entity.published', 'entities', p_entity::text);
end $$;

create function app.publish_place(p_place uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not exists (select 1 from app.entity_places ep where ep.place_id = p_place and app.curator_can(ep.entity_id)) then
    perform app._not_found();
  end if;
  update app.places set publication_state = 'published', updated_at = now() where id = p_place;
  perform app._project_entity(ep.entity_id) from app.entity_places ep where ep.place_id = p_place;
  perform app._audit('place.published', 'places', p_place::text);
end $$;

-- ---------- Ocultação preventiva e retirada com tombstone ----------
create function app.hide_entity(p_entity uuid, p_reason_code text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not (app.has_role('moderator') or app.curator_can(p_entity)) then perform app._not_found(); end if;
  update app.entities set publication_state = 'hidden', updated_at = now() where id = p_entity;
  if not found then perform app._not_found(); end if;
  perform app._project_entity(p_entity);          -- remove de pub (busca, detalhe, mapa, contadores)
  perform app._outbox(p_entity, 'hidden');        -- invalidação de cache/CDN pelo worker
  perform app._audit('entity.hidden', 'entities', p_entity::text, jsonb_build_object('reason', p_reason_code));
end $$;

create function app._tombstone(p_entity uuid, p_reason text) returns void
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

create function app.withdraw_entity(p_entity uuid, p_reason_code text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not (app.has_role('moderator') or app.has_role('admin') or app.is_entity_manager(p_entity)) then
    perform app._not_found();
  end if;
  update app.entities set publication_state = 'archived', participation_state = 'withdrawn', updated_at = now()
   where id = p_entity;
  if not found then perform app._not_found(); end if;
  perform app._tombstone(p_entity, p_reason_code);
  perform app._project_entity(p_entity);
  perform app._outbox(p_entity, 'withdrawn');
  perform app._audit('entity.withdrawn', 'entities', p_entity::text, jsonb_build_object('reason', p_reason_code));
end $$;

-- Após restaurar backup: reaplicar supressões ANTES de qualquer retorno público.
create function app.reapply_suppressions() returns integer
language plpgsql security definer set search_path = '' as $$
declare v_count integer := 0; r record;
begin
  for r in select pe.id from pub.entities pe
            left join app.entities e on e.id = pe.id
           where e.id is null or e.publication_state <> 'published' or app._is_suppressed(pe.id) loop
    perform app._unproject_entity(r.id);
    v_count := v_count + 1;
  end loop;
  -- locais órfãos e perfis sem adesão vigente
  delete from pub.places p where not exists (select 1 from pub.entity_places ep where ep.place_id = p.id);
  delete from pub.profiles pp where not exists (
    select 1 from app.profiles pr join app.consent_records c on c.account_id = pr.account_id
     where pr.public_id = pp.public_id and c.purpose = 'public_presentation'
       and c.decision = 'granted' and c.withdrawn_at is null);
  perform app._audit('suppressions.reapplied', 'pub', null, jsonb_build_object('entities_removed', v_count));
  return v_count;
end $$;

-- ---------- Reivindicação ----------
create function app.submit_claim(p_entity uuid, p_statement text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_id uuid;
begin
  perform app._rate_limit('claim:' || v_uid, 5, interval '1 day');
  -- só fichas publicadas são reivindicáveis; resposta não revela gestores existentes
  if not exists (select 1 from pub.entities where id = p_entity) then perform app._not_found(); end if;
  select id into v_id from app.claims where entity_id = p_entity and claimant_id = v_uid and status = 'pending';
  if v_id is null then
    insert into app.claims(entity_id, claimant_id, statement) values (p_entity, v_uid, p_statement) returning id into v_id;
  end if;
  return v_id;
end $$;

create function app.decide_claim(p_claim uuid, p_approve boolean, p_rationale text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); c app.claims;
begin
  select * into c from app.claims where id = p_claim for update;
  if not found or not app.curator_can(c.entity_id) then perform app._not_found(); end if;
  if c.claimant_id = v_uid then raise exception 'conflito de interesse' using errcode = '42501'; end if;
  if c.status <> 'pending' then raise exception 'pedido já decidido' using errcode = 'P0001'; end if;
  if char_length(coalesce(p_rationale, '')) < 10 then raise exception 'justificativa obrigatória' using errcode = '22023'; end if;
  update app.claims set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = v_uid, decided_at = now(), rationale = p_rationale where id = p_claim;
  if p_approve then
    insert into app.entity_managers(entity_id, account_id, status, verified_by, verified_at)
    values (c.entity_id, c.claimant_id, 'active', v_uid, now())
    on conflict (entity_id, account_id) do update set status = 'active', verified_by = v_uid, verified_at = now();
    update app.entities set participation_state = 'representative_confirmed' where id = c.entity_id;
  end if;
  perform app._audit('claim.decided', 'claims', p_claim::text, jsonb_build_object('approved', p_approve));
end $$;

-- ---------- Autorizações ----------
-- p_decision é OBRIGATÓRIO (sem default): nada é pré-selecionado.
create function app.grant_consent(p_purpose app.consent_purpose, p_decision app.consent_decision,
  p_text_version text, p_entity uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_id uuid;
begin
  if p_decision is null then raise exception 'decisão explícita obrigatória' using errcode = '22023'; end if;
  if p_entity is not null and not app.is_entity_manager(p_entity) then perform app._not_found(); end if;
  insert into app.consent_records(account_id, purpose, decision, text_version, entity_id)
  values (v_uid, p_purpose, p_decision, p_text_version, p_entity) returning id into v_id;
  if p_purpose = 'institutional_export' and p_entity is not null then
    update app.entities set export_permission = (p_decision = 'granted') where id = p_entity and kind <> 'person';
    perform app._project_entity(p_entity);
  end if;
  if p_entity is null then perform app._project_profile(v_uid); end if;
  perform app._audit('consent.recorded', 'consent_records', v_id::text,
                     jsonb_build_object('purpose', p_purpose, 'decision', p_decision, 'text_version', p_text_version));
  return v_id;
end $$;

create function app.withdraw_consent(p_consent uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); c app.consent_records; r record;
begin
  select * into c from app.consent_records where id = p_consent for update;
  if not found or c.account_id <> v_uid then perform app._not_found(); end if;
  if c.withdrawn_at is not null then return; end if;
  update app.consent_records set withdrawn_at = now() where id = p_consent;
  if c.purpose = 'political_identity_public' then
    for r in update app.political_identity_declarations set status = 'withdrawn'
              where consent_id = p_consent and status = 'active'
              returning entity_id, profile_account_id loop
      -- filas derivadas: cancela traduções pendentes do campo
      delete from app.translation_tasks t where t.field_name = 'political_identity'
         and (t.entity_id = r.entity_id or t.profile_account_id = r.profile_account_id);
      if r.entity_id is not null then
        perform app._project_entity(r.entity_id);
        perform app._outbox(r.entity_id, 'identity_withdrawn');
      end if;
      if r.profile_account_id is not null then perform app._project_profile(r.profile_account_id); end if;
    end loop;
  elsif c.purpose = 'institutional_export' and c.entity_id is not null then
    update app.entities set export_permission = false where id = c.entity_id;
    perform app._project_entity(c.entity_id);
  elsif c.purpose in ('public_presentation','location_city_region') then
    perform app._project_profile(v_uid);
    if c.entity_id is not null then perform app._project_entity(c.entity_id); end if;
  end if;
  perform app._audit('consent.withdrawn', 'consent_records', p_consent::text, jsonb_build_object('purpose', c.purpose));
end $$;

create function app.set_political_identity(p_labels text[], p_consent uuid, p_entity uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); c app.consent_records; v_id uuid;
begin
  select * into c from app.consent_records where id = p_consent;
  if not found or c.account_id <> v_uid or c.purpose <> 'political_identity_public'
     or c.decision <> 'granted' or c.withdrawn_at is not null
     or c.entity_id is distinct from p_entity then
    raise exception 'autorização específica e vigente é obrigatória' using errcode = '42501';
  end if;
  if p_entity is not null and not app.is_entity_manager(p_entity) then perform app._not_found(); end if;
  if p_entity is null and not exists (select 1 from app.profiles where account_id = v_uid) then perform app._not_found(); end if;
  update app.political_identity_declarations set status = 'withdrawn'
   where status = 'active' and ((p_entity is not null and entity_id = p_entity)
                                or (p_entity is null and profile_account_id = v_uid));
  insert into app.political_identity_declarations(consent_id, entity_id, profile_account_id, labels)
  values (p_consent, p_entity, case when p_entity is null then v_uid end, p_labels) returning id into v_id;
  insert into app.translation_tasks(entity_id, profile_account_id, field_name, target_lang)
  select p_entity, case when p_entity is null then v_uid end, 'political_identity', l from unnest(array['pt','en']) l;
  if p_entity is not null then perform app._project_entity(p_entity); else perform app._project_profile(v_uid); end if;
  return v_id;
end $$;

create function app.upsert_profile(p_pseudonym text, p_bio text, p_area text, p_precision app.location_precision)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_public uuid;
begin
  insert into app.profiles(account_id, pseudonym, bio, area_id, precision)
  values (v_uid, p_pseudonym, p_bio, p_area, p_precision)
  on conflict (account_id) do update set pseudonym = excluded.pseudonym, bio = excluded.bio,
     area_id = excluded.area_id, precision = excluded.precision, updated_at = now()
  returning public_id into v_public;
  perform app._project_profile(v_uid);
  return v_public;
end $$;

-- ---------- Relatos ----------
create function app.submit_report(p_kind app.report_kind, p_entity uuid, p_body text,
  p_contact text default null, p_client_key text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  perform app._rate_limit(coalesce('report:' || v_uid::text,
                                   'report:anon:' || app.key_hash(coalesce(p_client_key, 'sem-chave'))),
                          10, interval '1 hour');
  insert into app.reports(kind, entity_id, body, reporter_account, reporter_contact, priority)
  values (p_kind,
          (select id from app.entities where id = p_entity),   -- id inexistente vira null; resposta igual
          p_body, v_uid, p_contact,
          case when p_kind in ('exposure','withdrawal_request') then 1 when p_kind = 'abuse' then 2 else 3 end)
  returning id into v_id;
  return v_id;
end $$;

create function app.triage_report(p_report uuid, p_status text, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  if not app.has_role('moderator') then perform app._not_found(); end if;
  update app.reports set status = p_status, referral_note = p_note, handled_by = v_uid, handled_at = now()
   where id = p_report;
  if not found then perform app._not_found(); end if;
  perform app._audit('report.triaged', 'reports', p_report::text, jsonb_build_object('status', p_status));
end $$;

-- ---------- Papéis (somente administração, nunca para si) ----------
create function app.grant_role(p_account uuid, p_role app.staff_role, p_scope_country char(2) default null,
  p_scope_category text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_id uuid;
begin
  if not app.has_role('admin') then raise exception 'sem permissão' using errcode = '42501'; end if;
  if p_account = v_uid then raise exception 'autoatribuição de papel proibida' using errcode = '42501'; end if;
  insert into app.role_grants(account_id, role, scope_country, scope_category, granted_by)
  values (p_account, p_role, p_scope_country, p_scope_category, v_uid) returning id into v_id;
  perform app._audit('role.granted', 'role_grants', v_id::text, jsonb_build_object('role', p_role));
  return v_id;
end $$;

create function app.revoke_role(p_grant uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not app.has_role('admin') then raise exception 'sem permissão' using errcode = '42501'; end if;
  update app.role_grants set revoked_at = now() where id = p_grant and revoked_at is null;
  perform app._audit('role.revoked', 'role_grants', p_grant::text);
end $$;

-- ---------- Importação em rascunho (somente servidor) ----------
create function app.import_source_record(p_source uuid, p_external_id text, p_url text, p_name text,
  p_country char(2), p_kind app.entity_kind, p_presence app.presence_type, p_payload jsonb default '{}'::jsonb)
returns text
language plpgsql security definer set search_path = '' as $$
declare s app.sources; v_entity uuid; v_existing uuid; v_site text;
begin
  select * into s from app.sources where id = p_source;
  if not found or not s.adapter_allowed then raise exception 'fonte não autorizada' using errcode = '42501'; end if;
  if p_url !~ '^https://' or app.url_domain(p_url) is distinct from s.domain
     and app.url_domain(p_url) not like '%.' || s.domain then
    raise exception 'URL fora do domínio autorizado da fonte' using errcode = '22023';
  end if;
  if p_kind = 'person' then raise exception 'importação de pessoas é proibida' using errcode = '22023'; end if;
  v_site := p_payload->>'website';
  -- tombstones: nada é criado, nada do conteúdo é guardado
  if exists (select 1 from app.suppression_tombstones t where
       (t.key_type = 'source_external' and t.key_hash = app.key_hash(p_source::text || '|' || p_external_id))
    or (t.key_type = 'name_country' and t.key_hash = app.key_hash(pub.norm(p_name) || '|' || coalesce(p_country, '')))
    or (v_site is not null and t.key_type = 'domain' and t.key_hash = app.key_hash(app.url_domain(v_site)))) then
    perform app._audit('import.blocked_by_tombstone', 'sources', p_source::text);
    return 'blocked_by_tombstone';
  end if;
  select id into v_existing from app.source_records where source_id = p_source and external_id = p_external_id;
  if v_existing is not null then
    -- nunca sobrescreve campos da ficha: só atualiza a sugestão
    update app.source_records set payload = p_payload, accessed_at = current_date, status = 'matched_suggestion'
     where id = v_existing;
    return 'updated_suggestion';
  end if;
  insert into app.entities(kind, presence_type, original_name, country_code, research_state, publication_state,
                           source_accessed_at)
  values (p_kind, p_presence, p_name, p_country, 'discovered', 'draft', current_date) returning id into v_entity;
  insert into app.source_records(source_id, external_id, url, accessed_at, licence, payload, entity_id)
  values (p_source, p_external_id, p_url, current_date, s.licence, p_payload, v_entity);
  insert into app.field_provenance(entity_id, field_name, origin, source_record_id, licence)
  select v_entity, 'name', 'source', id, s.licence from app.source_records
   where source_id = p_source and external_id = p_external_id;
  return 'draft_created';
end $$;

-- ---------- Curadoria: evidências, fatos editoriais e locais ----------
create function app.add_evidence(p_entity uuid, p_kind app.evidence_kind, p_level text, p_url text,
  p_observed date, p_note text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_id uuid;
begin
  if not app.curator_can(p_entity) then perform app._not_found(); end if;
  insert into app.evidence(entity_id, kind, level, url, observed_at, note, created_by)
  values (p_entity, p_kind, p_level, p_url, p_observed, p_note, v_uid) returning id into v_id;
  return v_id;
end $$;

create function app.set_editorial_facts(p_entity uuid, p_activity app.activity_state, p_verified date,
  p_rights_basis text, p_research app.research_state default 'sufficient_evidence') returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not app.curator_can(p_entity) then perform app._not_found(); end if;
  if app.is_entity_creator(p_entity) or app.is_entity_manager(p_entity) then
    raise exception 'conflito de interesse' using errcode = '42501';
  end if;
  update app.entities set activity_state = p_activity, last_activity_verified_at = p_verified,
         rights_basis = p_rights_basis, research_state = p_research, updated_at = now()
   where id = p_entity;
  perform app._audit('entity.editorial_facts', 'entities', p_entity::text);
end $$;

create function app.create_place(p_entity uuid, p_kind app.place_kind, p_area text, p_lon double precision,
  p_lat double precision, p_precision app.location_precision, p_sensitive boolean default false) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform app._require_uid();
  if not app.curator_can(p_entity) then perform app._not_found(); end if;
  insert into app.places(kind, area_id, geom_exact, precision, is_sensitive, activity_state, publication_state)
  values (p_kind, p_area,
          case when p_lon is not null and p_lat is not null
               then extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326) end,
          p_precision, p_sensitive, 'active', 'published')
  returning id into v_id;
  insert into app.entity_places(entity_id, place_id) values (p_entity, v_id);
  perform app._project_entity(p_entity);
  return v_id;
end $$;

create function app.link_place(p_entity uuid, p_place uuid, p_role text default 'shared') returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not app.curator_can(p_entity) or not exists (select 1 from app.places where id = p_place) then
    perform app._not_found();
  end if;
  insert into app.entity_places(entity_id, place_id, role) values (p_entity, p_place, p_role) on conflict do nothing;
  perform app._project_entity(p_entity);
end $$;

-- ---------- EXECUTE: revoga de PUBLIC e concede por papel ----------
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.prokind = 'f' loop
    execute format('revoke all on function %s from public', r.sig);
  end loop;
end $$;

grant execute on function
  app.create_entity_draft(app.entity_kind, app.presence_type, text, text, jsonb),
  app.update_draft(uuid, jsonb, integer),
  app.propose_edit(uuid, jsonb),
  app.submit_version(uuid),
  app.review_version(uuid, app.review_decision, app.review_kind, text),
  app.publication_blockers(uuid),
  app.publish_entity(uuid, text),
  app.publish_place(uuid),
  app.hide_entity(uuid, text),
  app.withdraw_entity(uuid, text),
  app.submit_claim(uuid, text),
  app.decide_claim(uuid, boolean, text),
  app.grant_consent(app.consent_purpose, app.consent_decision, text, uuid),
  app.withdraw_consent(uuid),
  app.set_political_identity(text[], uuid, uuid),
  app.upsert_profile(text, text, text, app.location_precision),
  app.submit_report(app.report_kind, uuid, text, text, text),
  app.triage_report(uuid, text, text),
  app.grant_role(uuid, app.staff_role, char, text),
  app.revoke_role(uuid),
  app.add_evidence(uuid, app.evidence_kind, text, text, date, text),
  app.set_editorial_facts(uuid, app.activity_state, date, text, app.research_state),
  app.create_place(uuid, app.place_kind, text, double precision, double precision, app.location_precision, boolean),
  app.link_place(uuid, uuid, text)
to authenticated;
grant execute on function app.submit_report(app.report_kind, uuid, text, text, text) to anon;
-- importação e reaplicação de supressões: apenas servidor
grant execute on function app.import_source_record(uuid, text, text, text, char, app.entity_kind, app.presence_type, jsonb),
  app.reapply_suppressions() to service_role;
-- auxiliares de RLS continuam executáveis (concedidos em 0005)
grant execute on function app.has_role(app.staff_role), app.is_entity_manager(uuid), app.is_entity_creator(uuid),
  app.curator_can(uuid), app.can_view_entity_private(uuid) to authenticated, service_role;
