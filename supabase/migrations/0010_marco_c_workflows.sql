-- 0010 UP — Marco C: fluxos (funções SECURITY DEFINER em app, não exposto)
-- Mesmas regras do Marco B: search_path = '', nomes qualificados, EXECUTE revogado de PUBLIC,
-- "não encontrado" idêntico para inexistente e sem permissão.

-- ======================================================================
-- Utilitários: hash de IP, antispam, notificações
-- ======================================================================

-- Hash do IP do cliente com sal secreto e rotação diária. O IP nunca é gravado em claro.
-- Ordem: cf-connecting-ip (Cloudflare, na frente do Supabase), x-real-ip, primeiro x-forwarded-for.
create function app._client_ip_hash() returns text
language plpgsql stable set search_path = '' as $$
declare h jsonb; v_ip text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then h := null;
  end;
  v_ip := coalesce(nullif(h->>'cf-connecting-ip', ''), nullif(h->>'x-real-ip', ''),
                   nullif(btrim(split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1)), ''));
  if v_ip is null then return null; end if;
  return encode(sha256(convert_to(v_ip || '|' || coalesce((select value from app.settings where key = 'ip_salt'), '')
                                  || '|' || current_date::text, 'UTF8')), 'hex');
end $$;

-- Limites por IP (hora e dia) e por conta (dia). Sem cabeçalho de IP, usa um balde comum (disjuntor global).
create function app._antispam(p_scope text, p_ip_hour integer, p_ip_day integer, p_account_day integer) returns text
language plpgsql set search_path = '' as $$
declare v_ip text := app._client_ip_hash(); v_uid uuid := auth.uid();
begin
  if v_ip is not null then
    perform app._rate_limit(p_scope || ':ip:' || v_ip, p_ip_hour, interval '1 hour');
    perform app._rate_limit(p_scope || ':ipd:' || v_ip, p_ip_day, interval '1 day');
  else
    perform app._rate_limit(p_scope || ':sem-ip', p_ip_day * 10, interval '1 hour');
  end if;
  if v_uid is not null then
    perform app._rate_limit(p_scope || ':conta:' || v_uid, p_account_day, interval '1 day');
  end if;
  return v_ip;
end $$;

create function app._hp_tripped(p_hp text) returns boolean
language sql immutable set search_path = '' as $$ select coalesce(btrim(p_hp), '') <> '' $$;

create function app._check_len(p text, p_min integer, p_max integer, p_label text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p is null or char_length(btrim(p)) < p_min or char_length(p) > p_max then
    raise exception '% deve ter entre % e % caracteres', p_label, p_min, p_max using errcode = '22023';
  end if;
end $$;

create function app._norm_locale(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p in ('pt','en','es') then p else 'pt' end
$$;

create function app._random_digits(p_n integer) returns text
language sql volatile set search_path = '' as $$
  -- gen_random_uuid usa gerador forte; os 8 primeiros hex do UUID v4 são aleatórios
  select lpad((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % (10 ^ p_n)::bigint)::text, p_n, '0')
$$;

create function app._random_code(p_n integer) returns text
language plpgsql volatile set search_path = '' as $$
declare v_alpha text := 'abcdefghijkmnpqrstuvwxyz23456789'; v text := ''; v_hex text; i integer;
begin
  v_hex := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  for i in 1..p_n loop
    -- usa pares de hex fora das posições de versão/variante do UUID v4
    v := v || substr(v_alpha, (('x' || substr(v_hex, (i * 2) + case when i >= 6 then 6 else 0 end, 2))::bit(8)::integer % 32) + 1, 1);
  end loop;
  return v;
end $$;

create function app._sha(p text) returns text
language sql immutable strict set search_path = '' as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;

-- Enfileira notificação. Dados de vida curta vão para notification_secrets (não trafegam no webhook).
create function app._notify(p_kind text, p_account uuid, p_to_moderator boolean, p_ref uuid, p_entity uuid,
  p_secret jsonb default null, p_locale text default null) returns bigint
language plpgsql set search_path = '' as $$
declare v_id bigint;
begin
  insert into app.notification_outbox(kind, recipient_account, to_moderator, ref_id, entity_id, locale)
  values (p_kind, p_account, p_to_moderator, p_ref, p_entity,
          app._norm_locale(coalesce(p_locale, (select a.locale from app.accounts a where a.id = p_account), 'pt')))
  returning id into v_id;
  if p_secret is not null then
    insert into app.notification_secrets(outbox_id, data) values (v_id, p_secret);
  end if;
  return v_id;
end $$;

create function app._account_email(p_account uuid) returns text
language sql stable security definer set search_path = '' as $$
  select u.email::text from auth.users u where u.id = p_account
$$;

-- ======================================================================
-- Retirada preventiva
-- ======================================================================
create function app.request_takedown(p_entity uuid, p_reason text, p_relation text, p_contact text default null,
  p_locale text default 'pt', p_hp text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_ip text; v_pub boolean; v_exists boolean; v_auto boolean := false; v_id uuid; v_max integer;
begin
  if app._hp_tripped(p_hp) then
    return jsonb_build_object('request_id', gen_random_uuid(), 'hidden', true);
  end if;
  perform app._check_len(p_reason, 10, 2000, 'motivo');
  if p_relation is null or p_relation not in ('representative','member','mentioned','other') then
    raise exception 'relação inválida' using errcode = '22023';
  end if;
  if p_contact is not null and char_length(p_contact) > 200 then
    raise exception 'contato deve ter até 200 caracteres' using errcode = '22023';
  end if;
  v_ip := app._antispam('takedown', 5, 20, 20);
  v_exists := exists (select 1 from app.entities where id = p_entity);
  v_pub := exists (select 1 from pub.entities where id = p_entity);
  v_max := coalesce((select value::integer from app.settings where key = 'takedown_autohide_per_hour'), 30);
  if v_pub then
    v_auto := (select count(*) from app.takedown_requests
                where auto_hidden and created_at > now() - interval '1 hour') < v_max;
  end if;
  insert into app.takedown_requests(entity_id, reason, relation, contact, locale, account_id, ip_hash, auto_hidden)
  values (case when v_exists then p_entity end, p_reason, p_relation, nullif(btrim(p_contact), ''),
          app._norm_locale(p_locale), auth.uid(), v_ip, v_auto)
  returning id into v_id;
  if v_auto then
    update app.entities set publication_state = 'hidden', updated_at = now() where id = p_entity;
    perform app._project_entity(p_entity);                 -- some de lista, mapa, busca, contadores e exportação
    perform app._outbox(p_entity, 'takedown_preventive');  -- invalidação de cache
    perform app._audit('entity.hidden_preventive', 'entities', p_entity::text, jsonb_build_object('request', v_id));
  end if;
  if v_pub then
    perform app._notify('takedown_request', null, true, v_id, p_entity, null, 'pt');
  end if;
  return jsonb_build_object('request_id', v_id, 'hidden', v_auto);
end $$;

create function app.mod_decide_takedown(p_request uuid, p_decision text, p_rationale text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); r app.takedown_requests; v_state app.publication_state;
begin
  if not app.has_role('moderator') then perform app._not_found(); end if;
  select * into r from app.takedown_requests where id = p_request for update;
  if not found then perform app._not_found(); end if;
  if r.status <> 'open' then raise exception 'pedido já decidido' using errcode = 'P0001'; end if;
  if p_decision not in ('confirm','restore','reject_keep_hidden') then
    raise exception 'decisão inválida' using errcode = '22023';
  end if;
  if p_decision = 'restore' and char_length(coalesce(p_rationale, '')) < 10 then
    raise exception 'justificativa obrigatória para restaurar' using errcode = '22023';
  end if;
  if r.entity_id is not null then
    select publication_state into v_state from app.entities where id = r.entity_id for update;
    if p_decision = 'confirm' then
      update app.entities set publication_state = 'archived', participation_state = 'withdrawn', updated_at = now()
       where id = r.entity_id;
      perform app._tombstone(r.entity_id, 'takedown_confirmed');
      perform app._project_entity(r.entity_id);
      perform app._outbox(r.entity_id, 'withdrawn');
    elsif p_decision = 'restore' then
      if v_state <> 'hidden' or app._is_suppressed(r.entity_id) then
        raise exception 'a ficha não está oculta de forma reversível' using errcode = 'P0001';
      end if;
      update app.entities set publication_state = 'published', updated_at = now() where id = r.entity_id;
      perform app._project_entity(r.entity_id);
      perform app._outbox(r.entity_id, 'restored');
    end if;
    -- a decisão vale para todos os pedidos abertos da mesma ficha
    update app.takedown_requests set status = case p_decision when 'confirm' then 'confirmed'
             when 'restore' then 'restored' else 'closed_kept_hidden' end,
           decided_by = v_uid, decided_at = now(), rationale = p_rationale
     where entity_id = r.entity_id and status = 'open';
  else
    update app.takedown_requests set status = 'closed_kept_hidden', decided_by = v_uid, decided_at = now(),
           rationale = p_rationale where id = r.id;
  end if;
  perform app._audit('takedown.decided', 'takedown_requests', p_request::text,
                     jsonb_build_object('decision', p_decision, 'entity', r.entity_id, 'rationale', left(p_rationale, 500)));
end $$;

-- ======================================================================
-- Relatos, indicações e contato
-- ======================================================================
create function app.report(p_kind text, p_entity uuid, p_body text, p_contact text default null, p_hp text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if app._hp_tripped(p_hp) then return gen_random_uuid(); end if;
  if p_kind is null or p_kind not in ('correction','exposure','abuse','other') then
    raise exception 'tipo de relato inválido' using errcode = '22023';
  end if;
  perform app._check_len(p_body, 5, 5000, 'relato');
  if p_contact is not null and char_length(p_contact) > 200 then
    raise exception 'contato deve ter até 200 caracteres' using errcode = '22023';
  end if;
  perform app._antispam('report', 10, 50, 50);
  insert into app.reports(kind, entity_id, body, reporter_account, reporter_contact, priority)
  values (p_kind::app.report_kind, (select id from app.entities where id = p_entity), p_body, auth.uid(),
          nullif(btrim(p_contact), ''),
          case when p_kind = 'exposure' then 1 when p_kind = 'abuse' then 2 else 3 end)
  returning id into v_id;
  return v_id;
end $$;

create function app.suggest_initiative(p_name text, p_website text, p_country text, p_city text, p_families text[],
  p_description text, p_why text default null, p_contact text default null, p_locale text default 'pt',
  p_hp text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_ip text; v_id uuid;
begin
  if app._hp_tripped(p_hp) then return gen_random_uuid(); end if;
  perform app._check_len(p_name, 2, 180, 'nome');
  perform app._check_len(p_description, 10, 2000, 'descrição');
  if nullif(btrim(p_website), '') is not null and (p_website !~ '^https?://[^\s<>"]+$' or char_length(p_website) > 500) then
    raise exception 'site deve começar com http:// ou https://' using errcode = '22023';
  end if;
  if nullif(btrim(p_country), '') is not null and upper(p_country) !~ '^[A-Z]{2}$' then
    raise exception 'país inválido (use código de 2 letras)' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_families, '{}')) > 5
     or exists (select 1 from unnest(coalesce(p_families, '{}')) f where not exists (select 1 from pub.categories c where c.id = f)) then
    raise exception 'famílias inválidas' using errcode = '22023';
  end if;
  if (p_city is not null and char_length(p_city) > 120) or (p_why is not null and char_length(p_why) > 2000)
     or (p_contact is not null and char_length(p_contact) > 200) then
    raise exception 'campo longo demais' using errcode = '22023';
  end if;
  v_ip := app._antispam('suggest', 5, 20, 20);
  insert into app.suggestions(name, website, country_code, city, families, description, why, contact, locale, account_id, ip_hash)
  values (btrim(p_name), nullif(btrim(p_website), ''), upper(nullif(btrim(p_country), '')), nullif(btrim(p_city), ''),
          coalesce(p_families, '{}'), p_description, nullif(btrim(p_why), ''), nullif(btrim(p_contact), ''),
          app._norm_locale(p_locale), auth.uid(), v_ip)
  returning id into v_id;
  return v_id;
end $$;

create function app.send_contact_message(p_name text, p_email text, p_subject text, p_body text,
  p_locale text default 'pt', p_hp text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_ip text; v_id uuid;
begin
  if app._hp_tripped(p_hp) then return gen_random_uuid(); end if;
  perform app._check_len(p_name, 2, 120, 'nome');
  perform app._check_len(p_subject, 3, 150, 'assunto');
  perform app._check_len(p_body, 10, 5000, 'mensagem');
  if p_email is null or char_length(p_email) > 254 or p_email !~* '^[^@\s<>"]+@[^@\s<>"]+\.[a-z]{2,}$' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  v_ip := app._antispam('contact', 3, 10, 10);
  insert into app.contact_messages(sender_name, sender_email, subject, body, locale, account_id, ip_hash)
  values (btrim(p_name), lower(btrim(p_email)), btrim(p_subject), p_body, app._norm_locale(p_locale), auth.uid(), v_ip)
  returning id into v_id;
  perform app._notify('contact_message', null, true, v_id, null, null, 'pt');
  return v_id;
end $$;

-- ======================================================================
-- Reivindicação (três caminhos)
-- ======================================================================
create function app._approve_claim(p_claim uuid, p_decider uuid, p_basis text) returns void
language plpgsql set search_path = '' as $$
declare c app.claims; r record;
begin
  select * into c from app.claims where id = p_claim;
  update app.claims set status = 'approved', decided_by = p_decider, decided_at = now(), verified_at = now(),
         rationale = coalesce(rationale, p_basis), verify_email = null, code_hash = null
   where id = p_claim;
  insert into app.entity_managers(entity_id, account_id, status, verified_by, verified_at)
  values (c.entity_id, c.claimant_id, 'active', p_decider, now())
  on conflict (entity_id, account_id) do update set status = 'active', verified_by = p_decider, verified_at = now();
  update app.entities set participation_state = 'representative_confirmed', verification_label = 'holder_confirmed',
         updated_at = now() where id = c.entity_id;
  perform app._project_entity(c.entity_id);
  perform app._outbox(c.entity_id, 'claimed');
  -- pedidos de conexão guardados até a reivindicação são entregues agora
  for r in select id from app.connect_requests
            where to_entity = c.entity_id and status = 'pending' and expires_at > now() loop
    perform app._notify('connect_received', c.claimant_id, false, r.id, c.entity_id);
    update app.connect_requests set delivered_at = coalesce(delivered_at, now()) where id = r.id;
  end loop;
  perform app._notify('claim_approved', c.claimant_id, false, p_claim, c.entity_id);
  perform app._audit('claim.approved', 'claims', p_claim::text, jsonb_build_object('basis', p_basis, 'method', c.method));
end $$;

create function app.claim_start(p_entity uuid, p_method text, p_statement text, p_email text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := app._require_uid(); v_id uuid; v_site text; v_site_dom text; v_mail_dom text; v_code text;
  v_status text; v_pub_code text; v_exp timestamptz;
begin
  if p_method is null or p_method not in ('domain_email','published_code','manual') then
    raise exception 'caminho de verificação inválido' using errcode = '22023';
  end if;
  perform app._check_len(p_statement, 10, 2000, 'declaração');
  perform app._rate_limit('claim:' || v_uid, 5, interval '1 day');
  if not exists (select 1 from pub.entities where id = p_entity) then perform app._not_found(); end if;
  if app.is_entity_manager(p_entity) then
    raise exception 'você já gere esta ficha' using errcode = 'P0001';
  end if;
  -- uma reivindicação aberta por conta e ficha: a nova substitui a anterior
  update app.claims set status = 'withdrawn', verify_email = null, code_hash = null
   where entity_id = p_entity and claimant_id = v_uid and status in ('awaiting_code','awaiting_evidence','pending');

  if p_method = 'domain_email' then
    select coalesce(website_url, public_contact_url) into v_site from app.entities where id = p_entity;
    v_site_dom := app.url_domain(v_site);
    if v_site_dom is null then
      raise exception 'a ficha não tem site próprio; use o código publicado ou a aprovação manual' using errcode = '22023';
    end if;
    if p_email is null or char_length(p_email) > 254 or p_email !~* '^[^@\s<>"]+@[^@\s<>"]+\.[a-z]{2,}$' then
      raise exception 'e-mail inválido' using errcode = '22023';
    end if;
    v_mail_dom := lower(split_part(p_email, '@', 2));
    if app._is_shared_domain(v_mail_dom) or app._is_shared_domain(v_site_dom)
       or not (v_site_dom = v_mail_dom or v_site_dom like '%.' || v_mail_dom) then
      raise exception 'o e-mail precisa ser do domínio do site da iniciativa' using errcode = '22023';
    end if;
    insert into app.claims(entity_id, claimant_id, statement, status, method, verify_domain, verify_email)
    values (p_entity, v_uid, p_statement, 'awaiting_code', 'domain_email', v_mail_dom, lower(p_email))
    returning id into v_id;
    if lower(p_email) = lower(coalesce(app._account_email(v_uid), '')) then
      -- a posse do e-mail já foi provada pelo link mágico
      perform app._approve_claim(v_id, null, 'domain_email:conta');
      v_status := 'approved';
    else
      perform app._rate_limit('claimcode:' || v_uid, 3, interval '1 day');
      v_code := app._random_digits(6);
      v_exp := now() + interval '30 minutes';
      update app.claims set code_hash = app._sha(v_id::text || ':' || v_code), code_expires_at = v_exp where id = v_id;
      perform app._notify('claim_code', null, false, v_id, p_entity,
                          jsonb_build_object('email', lower(p_email), 'code', v_code),
                          (select locale from app.accounts where id = v_uid));
      v_status := 'awaiting_code';
    end if;
  elsif p_method = 'published_code' then
    v_pub_code := 'rbc-' || app._random_code(10);
    v_exp := now() + interval '14 days';
    insert into app.claims(entity_id, claimant_id, statement, status, method, published_code, code_expires_at)
    values (p_entity, v_uid, p_statement, 'awaiting_evidence', 'published_code', v_pub_code, v_exp)
    returning id into v_id;
    v_status := 'awaiting_evidence';
  else
    insert into app.claims(entity_id, claimant_id, statement, status, method)
    values (p_entity, v_uid, p_statement, 'pending', 'manual') returning id into v_id;
    perform app._notify('claim_pending', null, true, v_id, p_entity, null, 'pt');
    v_status := 'pending';
  end if;
  perform app._audit('claim.started', 'claims', v_id::text, jsonb_build_object('method', p_method));
  return jsonb_build_object('claim_id', v_id, 'method', p_method, 'status', v_status,
                            'published_code', v_pub_code,
                            'code_expires_at', case when v_status in ('awaiting_code','awaiting_evidence') then v_exp end);
end $$;

-- Sem exceção depois de gravar tentativa (uma exceção desfaria o contador).
create function app.claim_verify_code(p_claim uuid, p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); c app.claims; v_left integer;
begin
  select * into c from app.claims where id = p_claim and claimant_id = v_uid for update;
  if not found or c.method <> 'domain_email' then perform app._not_found(); end if;
  if c.status <> 'awaiting_code' then
    return jsonb_build_object('status', c.status, 'attempts_left', 0);
  end if;
  if c.code_expires_at is null or c.code_expires_at < now() then
    raise exception 'código expirado; peça um novo' using errcode = 'P0001';
  end if;
  if c.code_hash = app._sha(c.id::text || ':' || btrim(coalesce(p_code, ''))) then
    perform app._approve_claim(c.id, null, 'domain_email:codigo');
    return jsonb_build_object('status', 'approved', 'attempts_left', 5 - c.code_attempts);
  end if;
  v_left := 5 - (c.code_attempts + 1);
  update app.claims set code_attempts = code_attempts + 1,
         status = case when v_left <= 0 then 'failed' else status end,
         code_hash = case when v_left <= 0 then null else code_hash end,
         verify_email = case when v_left <= 0 then null else verify_email end
   where id = c.id;
  return jsonb_build_object('status', case when v_left <= 0 then 'failed' else 'awaiting_code' end,
                            'attempts_left', greatest(v_left, 0));
end $$;

create function app.claim_resend_code(p_claim uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); c app.claims; v_code text; v_exp timestamptz := now() + interval '30 minutes';
begin
  select * into c from app.claims where id = p_claim and claimant_id = v_uid for update;
  if not found or c.method <> 'domain_email' then perform app._not_found(); end if;
  if c.status <> 'awaiting_code' or c.verify_email is null then
    raise exception 'esta reivindicação não aguarda código' using errcode = 'P0001';
  end if;
  perform app._rate_limit('claimcode:' || v_uid, 3, interval '1 day');
  v_code := app._random_digits(6);
  update app.claims set code_hash = app._sha(c.id::text || ':' || v_code), code_expires_at = v_exp, code_attempts = 0
   where id = c.id;
  perform app._notify('claim_code', null, false, c.id, c.entity_id,
                      jsonb_build_object('email', c.verify_email, 'code', v_code),
                      (select locale from app.accounts where id = v_uid));
  return jsonb_build_object('code_expires_at', v_exp);
end $$;

create function app.claim_submit_evidence(p_claim uuid, p_url text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); c app.claims;
begin
  select * into c from app.claims where id = p_claim and claimant_id = v_uid for update;
  if not found or c.method <> 'published_code' then perform app._not_found(); end if;
  if c.status not in ('awaiting_evidence','pending') then
    raise exception 'esta reivindicação não aguarda evidência' using errcode = 'P0001';
  end if;
  if c.code_expires_at < now() then raise exception 'código expirado; comece de novo' using errcode = 'P0001'; end if;
  if p_url is null or p_url !~ '^https://[^\s<>"]+$' or char_length(p_url) > 500 then
    raise exception 'informe a URL https onde o código foi publicado' using errcode = '22023';
  end if;
  update app.claims set evidence_url = p_url, status = 'pending' where id = c.id;
  if c.status = 'awaiting_evidence' then
    perform app._notify('claim_pending', null, true, c.id, c.entity_id, null, 'pt');
  end if;
  return jsonb_build_object('status', 'pending');
end $$;

create function app.claim_cancel(p_claim uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  update app.claims set status = 'withdrawn', verify_email = null, code_hash = null
   where id = p_claim and claimant_id = v_uid and status in ('awaiting_code','awaiting_evidence','pending');
  if not found then perform app._not_found(); end if;
end $$;

create function app.mod_decide_claim(p_claim uuid, p_approve boolean, p_rationale text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); c app.claims;
begin
  select * into c from app.claims where id = p_claim for update;
  if not found or not (app.has_role('moderator') or app.curator_can(c.entity_id)) then perform app._not_found(); end if;
  if c.claimant_id = v_uid then raise exception 'conflito de interesse' using errcode = '42501'; end if;
  if c.status not in ('pending','awaiting_evidence','awaiting_code') then
    raise exception 'pedido já decidido' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_rationale, '')) < 10 then raise exception 'justificativa obrigatória' using errcode = '22023'; end if;
  update app.claims set rationale = p_rationale where id = p_claim;
  if p_approve then
    perform app._approve_claim(p_claim, v_uid, 'moderacao');
  else
    update app.claims set status = 'rejected', decided_by = v_uid, decided_at = now(), verify_email = null, code_hash = null
     where id = p_claim;
    perform app._notify('claim_rejected', c.claimant_id, false, p_claim, c.entity_id);
  end if;
  perform app._audit('claim.decided', 'claims', p_claim::text, jsonb_build_object('approved', p_approve));
end $$;

-- ======================================================================
-- Gestão da ficha
-- ======================================================================
create function app.manager_update(p_entity uuid, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := app._require_uid(); k text; v_applied text[] := '{}'; v_sensitive jsonb := '{}'::jsonb;
  v_version uuid; l text; b text; c text; i integer := 0; v_primary text; v_pt_changed boolean := false;
begin
  if not app.is_entity_manager(p_entity) then perform app._not_found(); end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'payload inválido' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_payload) loop
    if k not in ('descriptions','website_url','contact_url','access_conditions','categories','primary_category',
                 'name','country_code','area_id') then
      raise exception 'campo não permitido: %', left(k, 40) using errcode = '22023';
    end if;
  end loop;
  perform app._rate_limit('mupd:' || v_uid, 50, interval '1 day');

  if p_payload ? 'descriptions' then
    if jsonb_typeof(p_payload->'descriptions') <> 'object' then raise exception 'descrições devem ser objeto idioma→texto' using errcode = '22023'; end if;
    for l, b in select key, value from jsonb_each_text(p_payload->'descriptions') loop
      if l not in ('pt','en','es') then raise exception 'idioma inválido' using errcode = '22023'; end if;
      perform app._check_len(b, 10, 2000, 'descrição');
      if l = 'pt' then v_pt_changed := true; end if;
      insert into app.entity_texts(entity_id, field, lang, body, state)
      values (p_entity, 'description', l, b, case when l = 'pt' then 'original' else 'human_reviewed' end::app.text_state)
      on conflict (entity_id, field, lang) do update set body = excluded.body, state = excluded.state, updated_at = now();
    end loop;
    -- tradução automática antiga não acompanha o novo original
    if v_pt_changed and not (p_payload->'descriptions' ? 'en') then
      delete from app.entity_texts where entity_id = p_entity and field = 'description' and lang = 'en' and state = 'machine_unreviewed';
    end if;
    v_applied := v_applied || 'descriptions'::text;
  end if;
  if p_payload ? 'website_url' then
    if nullif(p_payload->>'website_url', '') is not null and (p_payload->>'website_url' !~ '^https?://[^\s<>"]+$'
       or char_length(p_payload->>'website_url') > 500) then
      raise exception 'site inválido' using errcode = '22023';
    end if;
    update app.entities set website_url = nullif(p_payload->>'website_url', '') where id = p_entity;
    v_applied := v_applied || 'website_url'::text;
  end if;
  if p_payload ? 'contact_url' then
    if nullif(p_payload->>'contact_url', '') is not null and p_payload->>'contact_url' !~ '^https://[^\s<>"]+$' then
      raise exception 'URL de contato deve ser https' using errcode = '22023';
    end if;
    update app.entities set public_contact_url = nullif(p_payload->>'contact_url', '') where id = p_entity;
    v_applied := v_applied || 'contact_url'::text;
  end if;
  if p_payload ? 'access_conditions' then
    if jsonb_typeof(p_payload->'access_conditions') <> 'object' then raise exception 'condições de acesso inválidas' using errcode = '22023'; end if;
    update app.entities set access_conditions = p_payload->'access_conditions' where id = p_entity;
    v_applied := v_applied || 'access_conditions'::text;
  end if;
  if p_payload ? 'categories' then
    if jsonb_typeof(p_payload->'categories') <> 'array' or jsonb_array_length(p_payload->'categories') not between 1 and 5
       or exists (select 1 from jsonb_array_elements_text(p_payload->'categories') x
                   where not exists (select 1 from pub.categories pc where pc.id = x)) then
      raise exception 'famílias inválidas (1 a 5)' using errcode = '22023';
    end if;
    v_primary := coalesce(p_payload->>'primary_category', p_payload->'categories'->>0);
    if not (p_payload->'categories') ? v_primary then raise exception 'família primária fora da lista' using errcode = '22023'; end if;
    delete from app.entity_categories where entity_id = p_entity;
    insert into app.entity_categories(entity_id, category_id, is_primary, basis)
      select distinct p_entity, x, x = v_primary, 'declared' from jsonb_array_elements_text(p_payload->'categories') x;
    v_applied := v_applied || 'categories'::text;
  end if;

  -- campos sensíveis: proposta congelada para revisão; a ficha pública não muda até a aprovação
  for k in select unnest(array['name','country_code','area_id']) loop
    if p_payload ? k then v_sensitive := v_sensitive || jsonb_build_object(k, p_payload->k); end if;
  end loop;
  if v_sensitive <> '{}'::jsonb then
    v_version := app.propose_edit(p_entity, v_sensitive);
    perform app.submit_version(v_version);
  end if;

  if cardinality(v_applied) > 0 then
    update app.entities set updated_at = now() where id = p_entity;
    perform app._project_entity(p_entity);
    perform app._outbox(p_entity, 'manager_update');
  end if;
  perform app._audit('entity.manager_update', 'entities', p_entity::text,
                     jsonb_build_object('applied', v_applied, 'pending_version', v_version));
  return jsonb_build_object('applied', to_jsonb(v_applied), 'pending_version_id', v_version);
end $$;

create function app.set_accepts_connections(p_entity uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not app.is_entity_manager(p_entity) then perform app._not_found(); end if;
  update app.entities set accepts_connections = coalesce(p_accept, true) where id = p_entity;
end $$;

create function app.set_locale(p_locale text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  if p_locale not in ('pt','en') then raise exception 'idioma inválido' using errcode = '22023'; end if;
  update app.accounts set locale = p_locale where id = v_uid;
end $$;

-- ======================================================================
-- Conectar (pedido mediado; contatos só após aceite)
-- ======================================================================
create function app.connect_request(p_from_entity uuid, p_to_entity uuid, p_message text, p_contact text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_id uuid; v_status text; m record;
begin
  if not app.is_entity_manager(p_from_entity) then perform app._not_found(); end if;
  if p_from_entity = p_to_entity then raise exception 'escolha outra iniciativa' using errcode = '22023'; end if;
  if not exists (select 1 from pub.entities where id = p_from_entity)
     or not exists (select 1 from pub.entities where id = p_to_entity) then
    perform app._not_found();
  end if;
  perform app._check_len(p_message, 10, 1000, 'mensagem');
  perform app._check_len(p_contact, 5, 300, 'contato');
  perform app._rate_limit('connect:' || v_uid, 10, interval '1 day');
  if exists (select 1 from app.connect_requests where from_entity = p_from_entity and to_entity = p_to_entity
              and status in ('pending','blocked') and expires_at > now()) then
    raise exception 'já existe um pedido pendente entre estas iniciativas' using errcode = 'P0001';
  end if;
  update app.connect_requests set status = 'expired'
   where from_entity = p_from_entity and to_entity = p_to_entity and status in ('pending','blocked') and expires_at <= now();
  v_status := case when (select accepts_connections from app.entities where id = p_to_entity) then 'pending' else 'blocked' end;
  insert into app.connect_requests(from_entity, to_entity, from_account, message, from_contact, status)
  values (p_from_entity, p_to_entity, v_uid, p_message, btrim(p_contact), v_status) returning id into v_id;
  if v_status = 'pending' then
    for m in select account_id from app.entity_managers where entity_id = p_to_entity and status = 'active' loop
      perform app._notify('connect_received', m.account_id, false, v_id, p_to_entity);
      update app.connect_requests set delivered_at = coalesce(delivered_at, now()) where id = v_id;
    end loop;
  end if;
  perform app._audit('connect.requested', 'connect_requests', v_id::text);
  return v_id;
end $$;

create function app.connect_respond(p_request uuid, p_accept boolean, p_contact text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); r app.connect_requests;
begin
  select * into r from app.connect_requests where id = p_request for update;
  if not found or r.status = 'blocked' or not app.is_entity_manager(r.to_entity) then perform app._not_found(); end if;
  if r.status <> 'pending' or r.expires_at <= now() then
    raise exception 'pedido não está mais pendente' using errcode = 'P0001';
  end if;
  if p_accept then perform app._check_len(p_contact, 5, 300, 'contato'); end if;
  update app.connect_requests set status = case when p_accept then 'accepted' else 'declined' end,
         to_contact = case when p_accept then btrim(p_contact) end, decided_at = now(), decided_by = v_uid
   where id = p_request;
  if p_accept and r.from_account is not null then
    perform app._notify('connect_accepted', r.from_account, false, p_request, r.from_entity);
  end if;
  perform app._audit('connect.responded', 'connect_requests', p_request::text, jsonb_build_object('accepted', p_accept));
end $$;

create function app.connect_cancel(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  update app.connect_requests set status = 'cancelled', decided_at = now()
   where id = p_request and from_account = v_uid and status in ('pending','blocked');
  if not found then perform app._not_found(); end if;
end $$;

-- Lista do próprio usuário. other_contact só existe depois do aceite.
create function app.my_connections() returns table (
  request_id uuid, direction text, status text, my_entity_id uuid, my_entity_slug text, my_entity_name text,
  other_entity_id uuid, other_entity_slug text, other_entity_name text, message text, my_contact text,
  other_contact text, created_at timestamptz, decided_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  return query
  select r.id, 'out'::text,
         case when r.status = 'blocked' then (case when r.expires_at > now() then 'pending' else 'expired' end)
              when r.status = 'pending' and r.expires_at <= now() then 'expired' else r.status end,
         r.from_entity, ef.slug, ef.original_name, r.to_entity, et.slug, et.original_name, r.message,
         r.from_contact, case when r.status = 'accepted' then r.to_contact end, r.created_at, r.decided_at
    from app.connect_requests r
    join app.entities ef on ef.id = r.from_entity join app.entities et on et.id = r.to_entity
   where r.from_account = v_uid
  union all
  select r.id, 'in'::text,
         case when r.status = 'pending' and r.expires_at <= now() then 'expired' else r.status end,
         r.to_entity, et.slug, et.original_name, r.from_entity, ef.slug, ef.original_name, r.message,
         r.to_contact, case when r.status = 'accepted' then r.from_contact end, r.created_at, r.decided_at
    from app.connect_requests r
    join app.entities ef on ef.id = r.from_entity join app.entities et on et.id = r.to_entity
   where r.status <> 'blocked'
     and exists (select 1 from app.entity_managers m where m.entity_id = r.to_entity and m.account_id = v_uid and m.status = 'active')
     and r.from_account is distinct from v_uid
  order by 13 desc;
end $$;

-- ======================================================================
-- Ofertas e necessidades (só fichas reivindicadas; validade própria)
-- ======================================================================
create function app.offer_need_upsert(p_id uuid, p_entity uuid, p_kind text, p_topic text, p_title text,
  p_description text, p_valid_until date) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_id uuid := p_id;
begin
  if not app.is_entity_manager(p_entity) or not exists (select 1 from pub.entities where id = p_entity) then
    perform app._not_found();
  end if;
  if p_kind is null or p_kind not in ('offer','need') then raise exception 'tipo inválido' using errcode = '22023'; end if;
  if p_topic is null or p_topic not in ('tools','space','volunteering','knowledge','materials','other') then
    raise exception 'tema inválido' using errcode = '22023';
  end if;
  perform app._check_len(p_title, 3, 140, 'título');
  if p_description is not null and char_length(p_description) > 2000 then
    raise exception 'descrição deve ter até 2000 caracteres' using errcode = '22023';
  end if;
  if p_valid_until is null or p_valid_until < current_date or p_valid_until > current_date + 365 then
    raise exception 'validade deve ficar entre hoje e 365 dias' using errcode = '22023';
  end if;
  perform app._rate_limit('offer:' || v_uid, 30, interval '1 day');
  if v_id is null then
    if (select count(*) from app.offers_needs where entity_id = p_entity and publication_state = 'published'
         and valid_until >= current_date) >= 20 then
      raise exception 'máximo de 20 itens vigentes por iniciativa' using errcode = 'P0001';
    end if;
    insert into app.offers_needs(entity_id, kind, topic, title, description, valid_from, valid_until, visibility,
                                 publication_state, created_by)
    values (p_entity, p_kind, p_topic, btrim(p_title), nullif(btrim(p_description), ''), current_date, p_valid_until,
            'public', 'published', v_uid)
    returning id into v_id;
  else
    update app.offers_needs set kind = p_kind, topic = p_topic, title = btrim(p_title),
           description = nullif(btrim(p_description), ''), valid_from = current_date, valid_until = p_valid_until,
           publication_state = 'published', updated_at = now()
     where id = v_id and entity_id = p_entity;
    if not found then perform app._not_found(); end if;
  end if;
  perform app._project_offers(p_entity);
  perform app._outbox(p_entity, 'offers');
  return v_id;
end $$;

create function app.offer_need_remove(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_entity uuid;
begin
  perform app._require_uid();
  select entity_id into v_entity from app.offers_needs where id = p_id;
  if v_entity is null or not app.is_entity_manager(v_entity) then perform app._not_found(); end if;
  update app.offers_needs set publication_state = 'archived', updated_at = now() where id = p_id;
  perform app._project_offers(v_entity);
  perform app._outbox(v_entity, 'offers');
end $$;

create function app.my_offers_needs() returns table (id uuid, entity_id uuid, entity_slug text, kind text, topic text,
  title text, description text, valid_until date, expired boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  return query
  select o.id, o.entity_id, e.slug, o.kind, o.topic, o.title, o.description, o.valid_until, o.valid_until < current_date
    from app.offers_needs o join app.entities e on e.id = o.entity_id
   where o.publication_state = 'published'
     and exists (select 1 from app.entity_managers m where m.entity_id = o.entity_id and m.account_id = v_uid and m.status = 'active')
   order by o.valid_until desc;
end $$;

-- ======================================================================
-- Convites (fichas de exposição alta)
-- ======================================================================
create function app._invitation_by_token(p_token text) returns app.invitations
language plpgsql set search_path = '' as $$
declare i app.invitations;
begin
  if p_token is null or lower(btrim(p_token)) !~ '^[0-9a-f]{64}$' then
    raise exception 'convite inválido ou expirado' using errcode = 'P0002';
  end if;
  select * into i from app.invitations
   where token_hash = app._sha(lower(btrim(p_token))) and status = 'pending' and expires_at > now()
   for update;
  if not found then raise exception 'convite inválido ou expirado' using errcode = 'P0002'; end if;
  return i;
end $$;

create function app.mod_create_invite(p_candidate uuid, p_days integer default 30) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); v_status text; v_token text; v_id uuid; v_exp timestamptz;
begin
  if not app.has_role('moderator') then perform app._not_found(); end if;
  select status into v_status from app.invite_candidates where id = p_candidate for update;
  if v_status is null then perform app._not_found(); end if;
  if v_status not in ('pending','invited') then raise exception 'candidato já decidido' using errcode = 'P0001'; end if;
  if p_days is null or p_days not between 1 and 90 then raise exception 'validade de 1 a 90 dias' using errcode = '22023'; end if;
  update app.invitations set status = 'revoked' where candidate_id = p_candidate and status = 'pending';
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_exp := now() + make_interval(days => p_days);
  insert into app.invitations(candidate_id, token_hash, expires_at, created_by)
  values (p_candidate, app._sha(v_token), v_exp, v_uid) returning id into v_id;
  update app.invite_candidates set status = 'invited', updated_at = now() where id = p_candidate;
  perform app._audit('invite.created', 'invitations', v_id::text);   -- o token NÃO vai para a auditoria
  return jsonb_build_object('invitation_id', v_id, 'token', v_token, 'expires_at', v_exp, 'path', '/#convite-' || v_token);
end $$;

create function app.mod_revoke_invite(p_invitation uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_cand uuid;
begin
  perform app._require_uid();
  if not app.has_role('moderator') then perform app._not_found(); end if;
  update app.invitations set status = 'revoked' where id = p_invitation and status = 'pending' returning candidate_id into v_cand;
  if v_cand is null then perform app._not_found(); end if;
  update app.invite_candidates set status = 'pending', updated_at = now() where id = v_cand and status = 'invited';
  perform app._audit('invite.revoked', 'invitations', p_invitation::text);
end $$;

create function app.invite_preview(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i app.invitations; d jsonb;
begin
  perform app._antispam('invite', 30, 100, 100);
  i := app._invitation_by_token(p_token);
  select data into d from app.invite_candidates where id = i.candidate_id;
  return jsonb_build_object('name', d->>'name', 'alt_names', coalesce(d->'alt_names', '[]'::jsonb), 'kind', d->>'kind',
    'presence_type', d->>'presence', 'families', coalesce(d->'categories', '[]'::jsonb), 'country_code', d->>'country',
    'city', d->>'city', 'summary_pt', d->>'summary_pt', 'website_url', d->>'own_url', 'source_url', d->>'source_url',
    'expires_at', i.expires_at);
end $$;

create function app.invite_decline(p_token text, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare i app.invitations; d jsonb; v_dom text;
begin
  perform app._antispam('invite', 30, 100, 100);
  i := app._invitation_by_token(p_token);
  select data into d from app.invite_candidates where id = i.candidate_id;
  update app.invitations set status = 'declined', used_at = now(), used_by = auth.uid() where id = i.id;
  update app.invite_candidates set status = 'declined', updated_at = now() where id = i.candidate_id;
  -- tombstones: nunca importar nem publicar
  insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code)
  values (i.candidate_id, 'entity_id', app.key_hash(i.candidate_id::text), 'invite_declined'),
         (i.candidate_id, 'name_country', app.key_hash(pub.norm(d->>'name') || '|' || coalesce(d->>'country', '')), 'invite_declined'),
         (i.candidate_id, 'source_external', app.key_hash(app._source_uuid(coalesce(d->>'source_key', 'research'))::text
                                                           || '|' || (d->>'research_id')), 'invite_declined')
  on conflict do nothing;
  v_dom := app.url_domain(d->>'own_url');
  if v_dom is not null and not app._is_shared_domain(v_dom) then
    insert into app.suppression_tombstones(entity_id, key_type, key_hash, reason_code)
    values (i.candidate_id, 'domain', app.key_hash(v_dom), 'invite_declined') on conflict do nothing;
  end if;
  perform app._audit('invite.declined', 'invitations', i.id::text,
                     jsonb_build_object('has_reason', nullif(btrim(coalesce(p_reason, '')), '') is not null));
end $$;

create function app.invite_accept(p_token text, p_consent_text_version text, p_location text default 'city',
  p_summary_pt text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); i app.invitations; d jsonb; v_res text; v_slug text;
begin
  if p_consent_text_version is null or p_consent_text_version !~ '^[a-z0-9._-]{1,40}$' then
    raise exception 'versão do texto de autorização obrigatória' using errcode = '22023';
  end if;
  if p_location is null or p_location not in ('city','none') then raise exception 'localização inválida' using errcode = '22023'; end if;
  if p_summary_pt is not null then perform app._check_len(p_summary_pt, 10, 200, 'resumo'); end if;
  i := app._invitation_by_token(p_token);
  select data into d from app.invite_candidates where id = i.candidate_id for update;
  if p_location = 'none' then
    d := d - 'city' - 'city_lat' - 'city_lng' - 'area_id' || jsonb_build_object('location_precision', 'none');
  end if;
  if p_summary_pt is not null then
    d := d || jsonb_build_object('summary_pt', btrim(p_summary_pt), 'summary_en', null);
  end if;
  v_res := app._upsert_record(d, 'invite');
  if v_res not in ('inserted','updated') then
    raise exception 'esta ficha não pode ser publicada (%)', v_res using errcode = 'P0001';
  end if;
  insert into app.consent_records(account_id, purpose, decision, text_version, entity_id, scope)
  values (v_uid, 'public_presentation', 'granted', p_consent_text_version, i.candidate_id,
          jsonb_build_object('via', 'invitation', 'invitation', i.id, 'location', p_location));
  insert into app.entity_managers(entity_id, account_id, status, verified_at)
  values (i.candidate_id, v_uid, 'active', now())
  on conflict (entity_id, account_id) do update set status = 'active', verified_at = now();
  update app.entities set participation_state = 'representative_confirmed', verification_label = 'holder_confirmed'
   where id = i.candidate_id;
  perform app._project_entity(i.candidate_id);
  update app.invitations set status = 'accepted', used_at = now(), used_by = v_uid where id = i.id;
  update app.invite_candidates set status = 'accepted', entity_id = i.candidate_id, updated_at = now() where id = i.candidate_id;
  perform app._notify('invite_accepted', null, true, i.id, i.candidate_id, null, 'pt');
  perform app._audit('invite.accepted', 'invitations', i.id::text, jsonb_build_object('location', p_location));
  select slug into v_slug from app.entities where id = i.candidate_id;
  return jsonb_build_object('entity_id', i.candidate_id, 'slug', v_slug);
end $$;

-- ======================================================================
-- Conta e painel do moderador
-- ======================================================================
create function app.my_account() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  return jsonb_build_object(
    'locale', (select locale from app.accounts where id = v_uid),
    'roles', coalesce((select jsonb_agg(distinct g.role) from app.role_grants g where g.account_id = v_uid and g.revoked_at is null), '[]'),
    'managed', coalesce((select jsonb_agg(jsonb_build_object('entity_id', e.id, 'slug', e.slug, 'name', e.original_name,
                                  'accepts_connections', e.accepts_connections, 'publication_state', e.publication_state) order by e.original_name)
                         from app.entity_managers m join app.entities e on e.id = m.entity_id
                        where m.account_id = v_uid and m.status = 'active'), '[]'),
    'claims', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'entity_id', c.entity_id, 'slug', e.slug, 'name', e.original_name,
                                 'method', c.method, 'status', c.status, 'code_expires_at', c.code_expires_at,
                                 'published_code', c.published_code, 'created_at', c.created_at) order by c.created_at desc)
                        from app.claims c join app.entities e on e.id = c.entity_id where c.claimant_id = v_uid), '[]'),
    'connections', jsonb_build_object(
      'incoming_pending', (select count(*) from app.connect_requests r where r.status = 'pending' and r.expires_at > now()
                             and exists (select 1 from app.entity_managers m where m.entity_id = r.to_entity
                                          and m.account_id = v_uid and m.status = 'active')),
      'outgoing_pending', (select count(*) from app.connect_requests r where r.from_account = v_uid
                             and r.status in ('pending','blocked') and r.expires_at > now())));
end $$;

create function app.mod_queue_counts() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app._require_uid();
  if not app.has_role('moderator') then perform app._not_found(); end if;
  return jsonb_build_object(
    'takedowns', (select count(*) from app.takedown_requests where status = 'open'),
    'claims', (select count(*) from app.claims where status in ('pending','awaiting_evidence')),
    'reports', (select count(*) from app.reports where status = 'open'),
    'suggestions', (select count(*) from app.suggestions where status = 'new'),
    'contact', (select count(*) from app.contact_messages where status = 'new'),
    'edits', (select count(*) from app.entity_versions where status = 'submitted'),
    'invites_pending', (select count(*) from app.invitations where status = 'pending' and expires_at > now()));
end $$;

create function app.mod_list(p_queue text, p_status text default null, p_limit integer default 50,
  p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_lim integer := least(greatest(coalesce(p_limit, 50), 1), 200); v_off integer := greatest(coalesce(p_offset, 0), 0);
begin
  perform app._require_uid();
  if not app.has_role('moderator') then perform app._not_found(); end if;
  if p_queue = 'takedowns' then
    return coalesce((select jsonb_agg(x) from (
      select t.id, t.entity_id, e.original_name as entity_name, e.slug as entity_slug, e.publication_state as entity_state,
             t.reason, t.relation, t.contact, t.locale, t.auto_hidden, t.status, t.created_at, t.decided_at, t.rationale
        from app.takedown_requests t left join app.entities e on e.id = t.entity_id
       where t.status = coalesce(p_status, 'open') order by t.created_at limit v_lim offset v_off) x), '[]');
  elsif p_queue = 'claims' then
    return coalesce((select jsonb_agg(x) from (
      select c.id, c.entity_id, e.original_name as entity_name, e.slug as entity_slug, e.website_url, c.method, c.status,
             c.statement as claim_statement, c.verify_domain, c.published_code, c.evidence_url,
             app._account_email(c.claimant_id) as claimant_email, c.created_at, c.decided_at, c.rationale
        from app.claims c join app.entities e on e.id = c.entity_id
       where (p_status is null and c.status in ('pending','awaiting_evidence')) or c.status = p_status
       order by c.created_at limit v_lim offset v_off) x), '[]');
  elsif p_queue = 'reports' then
    return coalesce((select jsonb_agg(x) from (
      select r.id, r.kind, r.entity_id, e.original_name as entity_name, e.slug as entity_slug, r.body, r.reporter_contact,
             r.priority, r.status, r.created_at, r.referral_note
        from app.reports r left join app.entities e on e.id = r.entity_id
       where r.status = coalesce(p_status, 'open') order by r.priority, r.created_at limit v_lim offset v_off) x), '[]');
  elsif p_queue = 'suggestions' then
    return coalesce((select jsonb_agg(x) from (
      select s.id, s.name, s.website, s.country_code, s.city, s.families, s.description, s.why, s.contact, s.locale,
             s.status, s.note, s.created_at
        from app.suggestions s where s.status = coalesce(p_status, 'new')
       order by s.created_at limit v_lim offset v_off) x), '[]');
  elsif p_queue = 'contact' then
    return coalesce((select jsonb_agg(x) from (
      select m.id, m.sender_name, m.sender_email, m.subject, m.body, m.locale, m.status, m.created_at
        from app.contact_messages m where m.status = coalesce(p_status, 'new')
       order by m.created_at limit v_lim offset v_off) x), '[]');
  elsif p_queue = 'edits' then
    return coalesce((select jsonb_agg(x) from (
      select v.id as version_id, v.entity_id, e.original_name as entity_name, e.slug as entity_slug, v.payload as proposal,
             v.base_version_no, e.current_version_no, v.status, v.submitted_at
        from app.entity_versions v join app.entities e on e.id = v.entity_id
       where v.status::text = coalesce(p_status, 'submitted') order by v.submitted_at limit v_lim offset v_off) x), '[]');
  elsif p_queue = 'invite_candidates' then
    return coalesce((select jsonb_agg(x) from (
      select c.id, c.research_id, c.data->>'name' as name, c.data->>'kind' as kind, c.data->>'country' as country_code,
             c.data->>'city' as city, c.data->>'own_url' as website_url, c.data->>'source_url' as source_url,
             c.data->>'summary_pt' as summary_pt, c.status, c.entity_id,
             (select jsonb_build_object('id', i.id, 'status', i.status, 'expires_at', i.expires_at)
                from app.invitations i where i.candidate_id = c.id order by i.created_at desc limit 1) as last_invitation
        from app.invite_candidates c where c.status = coalesce(p_status, 'pending')
       order by c.research_id limit v_lim offset v_off) x), '[]');
  elsif p_queue = 'invitations' then
    return coalesce((select jsonb_agg(x) from (
      select i.id, i.candidate_id, c.data->>'name' as name, i.status, i.expires_at, i.used_at, i.created_at
        from app.invitations i join app.invite_candidates c on c.id = i.candidate_id
       where i.status = coalesce(p_status, 'pending') order by i.created_at desc limit v_lim offset v_off) x), '[]');
  end if;
  raise exception 'fila inválida' using errcode = '22023';
end $$;

create function app.mod_decide_suggestion(p_id uuid, p_status text, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  if not app.has_role('moderator') then perform app._not_found(); end if;
  if p_status not in ('accepted','rejected','duplicate') then raise exception 'estado inválido' using errcode = '22023'; end if;
  update app.suggestions set status = p_status, note = p_note, handled_by = v_uid, handled_at = now() where id = p_id;
  if not found then perform app._not_found(); end if;
  perform app._audit('suggestion.decided', 'suggestions', p_id::text, jsonb_build_object('status', p_status));
end $$;

create function app.mod_mark_contact(p_id uuid, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid();
begin
  if not app.has_role('moderator') then perform app._not_found(); end if;
  if p_status not in ('read','answered','spam') then raise exception 'estado inválido' using errcode = '22023'; end if;
  update app.contact_messages set status = p_status, handled_by = v_uid, handled_at = now() where id = p_id;
  if not found then perform app._not_found(); end if;
end $$;

-- ======================================================================
-- Notificações (somente service_role, chamado pela Edge Function)
-- ======================================================================
create function app.notification_pending(p_limit integer default 50) returns setof bigint
language sql stable security definer set search_path = '' as $$
  select id from app.notification_outbox
   where sent_at is null and attempts < 5 and (claimed_at is null or claimed_at < now() - interval '5 minutes')
   order by id limit least(greatest(coalesce(p_limit, 50), 1), 200)
$$;

-- Reserva o item (idempotente) e devolve o contexto para montar o e-mail. null = já enviado ou em envio.
create function app.notification_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n app.notification_outbox; v_secret jsonb; v_to jsonb; v_entity jsonb; v_data jsonb := '{}'::jsonb;
        v_cr app.connect_requests; v_cl app.claims; v_tk app.takedown_requests; v_cm app.contact_messages;
begin
  select * into n from app.notification_outbox where id = p_id for update skip locked;
  if not found or n.sent_at is not null or n.attempts >= 5
     or (n.claimed_at is not null and n.claimed_at > now() - interval '5 minutes') then
    return null;
  end if;
  update app.notification_outbox set attempts = attempts + 1, claimed_at = now() where id = p_id;
  select data into v_secret from app.notification_secrets where outbox_id = p_id;
  v_to := case
    when n.to_moderator then jsonb_build_object('type', 'moderator')
    when n.recipient_account is not null then jsonb_build_object('type', 'account', 'email', app._account_email(n.recipient_account))
    else jsonb_build_object('type', 'address', 'email', v_secret->>'email') end;
  select jsonb_build_object('id', e.id, 'name', e.original_name, 'slug', e.slug) into v_entity
    from app.entities e where e.id = n.entity_id;

  if n.kind in ('connect_received','connect_accepted') then
    select * into v_cr from app.connect_requests where id = n.ref_id;
    v_data := jsonb_build_object(
      'from_entity', (select jsonb_build_object('name', original_name, 'slug', slug) from app.entities where id = v_cr.from_entity),
      'to_entity', (select jsonb_build_object('name', original_name, 'slug', slug) from app.entities where id = v_cr.to_entity),
      'message', case when n.kind = 'connect_received' then v_cr.message end,
      'contact', case when n.kind = 'connect_accepted' and v_cr.status = 'accepted' then v_cr.to_contact end);
  elsif n.kind in ('claim_code','claim_pending','claim_approved','claim_rejected') then
    select * into v_cl from app.claims where id = n.ref_id;
    v_data := jsonb_build_object('method', v_cl.method, 'status', v_cl.status,
      'code', case when n.kind = 'claim_code' then v_secret->>'code' end,
      'statement', case when n.kind = 'claim_pending' then v_cl.statement end,
      'evidence_url', case when n.kind = 'claim_pending' then v_cl.evidence_url end,
      'published_code', case when n.kind = 'claim_pending' then v_cl.published_code end,
      'claimant_email', case when n.kind = 'claim_pending' then app._account_email(v_cl.claimant_id) end,
      'rationale', case when n.kind = 'claim_rejected' then v_cl.rationale end);
  elsif n.kind = 'takedown_request' then
    select * into v_tk from app.takedown_requests where id = n.ref_id;
    v_data := jsonb_build_object('reason', v_tk.reason, 'relation', v_tk.relation, 'contact', v_tk.contact,
                                 'auto_hidden', v_tk.auto_hidden, 'locale', v_tk.locale);
  elsif n.kind = 'contact_message' then
    select * into v_cm from app.contact_messages where id = n.ref_id;
    v_data := jsonb_build_object('sender_name', v_cm.sender_name, 'reply_to', v_cm.sender_email, 'subject', v_cm.subject,
                                 'body', v_cm.body, 'locale', v_cm.locale);
  end if;
  return jsonb_build_object('id', n.id, 'kind', n.kind, 'locale', n.locale, 'to', v_to, 'entity', v_entity,
                            'data', v_data, 'created_at', n.created_at);
end $$;

create function app.notification_done(p_id bigint, p_ok boolean, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update app.notification_outbox set sent_at = case when p_ok then now() end, claimed_at = null,
         last_error = case when p_ok then null else left(p_error, 500) end
   where id = p_id;
  if p_ok or (select attempts from app.notification_outbox where id = p_id) >= 5 then
    delete from app.notification_secrets where outbox_id = p_id;
  end if;
end $$;

-- Limpeza periódica (pg_cron opcional; ver README_DEPLOY): baldes de limite, segredos, prazos.
create function app.purge_expired() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a integer; b integer; c integer; d integer;
begin
  delete from app.rate_limits where bucket_start < now() - interval '2 days';
  get diagnostics a = row_count;
  delete from app.notification_secrets where created_at < now() - interval '1 day';
  get diagnostics b = row_count;
  update app.connect_requests set status = 'expired' where status in ('pending','blocked') and expires_at <= now();
  get diagnostics c = row_count;
  update app.invitations set status = 'expired' where status = 'pending' and expires_at <= now();
  get diagnostics d = row_count;
  update app.invite_candidates ic set status = 'pending', updated_at = now()
   where status = 'invited' and not exists (select 1 from app.invitations i where i.candidate_id = ic.id and i.status = 'pending');
  update app.claims set status = 'failed', verify_email = null, code_hash = null
   where status in ('awaiting_code','awaiting_evidence') and code_expires_at < now() - interval '1 day';
  -- ofertas vencidas saem da projeção (as views já filtram por data; isto só limpa)
  delete from pub.offers_needs where valid_until < current_date;
  return jsonb_build_object('rate_limits', a, 'secrets', b, 'connect_expired', c, 'invites_expired', d);
end $$;

-- ======================================================================
-- EXECUTE: revoga de PUBLIC e concede por papel
-- ======================================================================
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.prokind = 'f' loop
    execute format('revoke all on function %s from public', r.sig);
  end loop;
end $$;

grant execute on function
  app.request_takedown(uuid, text, text, text, text, text),
  app.report(text, uuid, text, text, text),
  app.suggest_initiative(text, text, text, text, text[], text, text, text, text, text),
  app.send_contact_message(text, text, text, text, text, text),
  app.invite_preview(text),
  app.invite_decline(text, text)
to anon, authenticated;

grant execute on function
  app.claim_start(uuid, text, text, text), app.claim_verify_code(uuid, text), app.claim_resend_code(uuid),
  app.claim_submit_evidence(uuid, text), app.claim_cancel(uuid), app.mod_decide_claim(uuid, boolean, text),
  app.mod_decide_takedown(uuid, text, text), app.manager_update(uuid, jsonb), app.set_accepts_connections(uuid, boolean),
  app.set_locale(text), app.connect_request(uuid, uuid, text, text), app.connect_respond(uuid, boolean, text),
  app.connect_cancel(uuid), app.my_connections(), app.offer_need_upsert(uuid, uuid, text, text, text, text, date),
  app.offer_need_remove(uuid), app.my_offers_needs(), app.mod_create_invite(uuid, integer), app.mod_revoke_invite(uuid),
  app.invite_accept(text, text, text, text), app.my_account(), app.mod_queue_counts(),
  app.mod_list(text, text, integer, integer), app.mod_decide_suggestion(uuid, text, text), app.mod_mark_contact(uuid, text)
to authenticated;

grant execute on function app.notification_pending(integer), app.notification_claim(bigint),
  app.notification_done(bigint, boolean, text), app.purge_expired() to service_role;

-- auxiliares de RLS continuam executáveis (o loop acima revogou de PUBLIC; reconcede como no Marco B)
grant execute on function app.has_role(app.staff_role), app.is_entity_manager(uuid), app.is_entity_creator(uuid),
  app.curator_can(uuid), app.can_view_entity_private(uuid) to authenticated, service_role;
grant execute on function app.slugify(text), app._slug_taken(text, uuid), app._unique_slug(text, text, uuid, text[])
  to service_role;
grant execute on function app.seed_load_record(jsonb), app.seed_load_candidate(jsonb) to service_role;
