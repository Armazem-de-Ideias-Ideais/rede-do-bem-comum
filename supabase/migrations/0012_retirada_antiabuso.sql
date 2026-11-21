-- 0012 UP — Retirada com proteção contra abuso (decisão do gestor, 21/11/2026)
--
-- Antes: qualquer pessoa, sem login, ocultava uma ficha na hora (teto global de 30 por hora). Um script com vários IPs
-- podia ocultar centenas de fichas por dia e o moderador só restaurava uma de cada vez.
-- Agora: a retirada continua sem login, mas a ficha só sai do ar DEPOIS que quem pediu confirma por um link enviado
-- ao e-mail informado. Sem e-mail, o pedido vai para a fila da moderação (resposta em até 72 h) e a ficha fica no ar.
--
--   app.request_takedown(... , p_email)   nunca oculta; com e-mail válido cria token de uso único (24 h) e enfileira o e-mail
--   app.confirm_takedown(p_token)         consome o token e oculta, se o disjuntor permitir
--   app.mod_restore_auto_hidden(...)      desfaz em lote as ocultações automáticas de uma janela / ip_hash / email_hash
--   app.mod_takedown_overview(p_hours)    visão agrupada por ip_hash e email_hash, com o estado do disjuntor
--
-- Privacidade: o e-mail só existe em app.takedown_requests (sem acesso de anon/authenticated) e, durante o envio, em
-- app.notification_secrets (apagado ao enviar). O token em claro nunca é gravado: só o sha256 em app.takedown_tokens;
-- o valor em claro viaja em app.notification_secrets (tabela separada, apagada quando o e-mail é enviado, depois de
-- 5 tentativas ou em até 1 dia pelo purge_expired), nunca no payload do webhook nem na auditoria.

-- ======================================================================
-- Configurações novas (padrões da decisão)
-- ======================================================================
insert into app.settings(key, value) values
  ('takedown_autohide_per_day', '50'),               -- disjuntor global: ocultações automáticas por 24 h
  ('takedown_autohide_per_email_day', '3'),          -- disjuntor por e-mail: ocultações automáticas por 24 h
  ('takedown_confirm_per_email_day', '3'),           -- e-mails de confirmação por endereço, por 24 h
  ('takedown_confirm_emails_per_day', '40'),         -- e-mails de confirmação no total, por 24 h (cota gratuita da Resend: 100/dia, dividida com o link de login)
  ('takedown_mod_emails_per_day', '20')              -- e-mails à moderação do tipo takedown_request, por 24 h
on conflict (key) do nothing;
-- novo padrão do disjuntor por hora: 15 (era 30). Só troca se ainda estiver no padrão antigo.
update app.settings set value = '15' where key = 'takedown_autohide_per_hour' and value = '30';

-- ======================================================================
-- Modelo: pedidos, tokens e tipos de notificação
-- ======================================================================
alter table app.takedown_requests
  add column email                text check (char_length(email) <= 200),
  add column email_hash           text check (email_hash ~ '^[0-9a-f]{64}$'),
  add column email_domain         text check (char_length(email_domain) <= 200),
  add column email_domain_matches boolean,                  -- domínio do e-mail = domínio do site da ficha (orienta a moderação; não muda o fluxo)
  add column confirm_sent_at      timestamptz,              -- quando o e-mail de confirmação foi enfileirado
  add column confirmed_at         timestamptz,              -- quando o link foi usado
  add column hidden_at            timestamptz,              -- quando a ocultação automática aconteceu
  add column contained            boolean not null default false;  -- barrado pelo disjuntor: ficou na fila, ficha no ar

alter table app.takedown_requests drop constraint takedown_requests_status_check;
alter table app.takedown_requests add constraint takedown_requests_status_check
  check (status in ('awaiting_confirmation','open','confirmed','restored','closed_kept_hidden','expired'));

create index on app.takedown_requests (email_hash, hidden_at) where email_hash is not null;
create index on app.takedown_requests (hidden_at) where auto_hidden;
create index on app.takedown_requests (confirm_sent_at) where confirm_sent_at is not null;
create index on app.takedown_requests (ip_hash) where ip_hash is not null;

create table app.takedown_tokens (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null references app.takedown_requests(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),   -- sha256 do token; o token em claro não é gravado aqui
  expires_at timestamptz not null,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);
create index on app.takedown_tokens (request_id);
alter table app.takedown_tokens enable row level security;
revoke all on app.takedown_tokens from public, anon, authenticated;
grant select, insert, update, delete on app.takedown_tokens to service_role;

alter table app.notification_outbox drop constraint notification_outbox_kind_check;
alter table app.notification_outbox add constraint notification_outbox_kind_check
  check (kind in ('connect_received','connect_accepted','claim_code','claim_pending','claim_approved','claim_rejected',
                  'takedown_request','contact_message','invite_accepted','takedown_confirm','takedown_containment'));

-- ======================================================================
-- Utilitários
-- ======================================================================
create function app._setting_int(p_key text, p_default integer) returns integer
language sql stable set search_path = '' as $$
  select coalesce((select value::integer from app.settings where key = p_key), p_default)
$$;

-- Hash do e-mail (minúsculas, sal fixo do servidor) para limites e filtros. Não reversível sem o sal.
create function app._email_hash(p_email text) returns text
language sql stable set search_path = '' as $$
  select app._sha('takedown-email|' || lower(btrim(p_email)) || '|' || coalesce((select value from app.settings where key = 'ip_salt'), ''))
$$;

-- E-mail à moderação sobre um pedido, com teto diário (acima dele só o painel e o alerta de contenção avisam).
create function app._notify_mod_takedown(p_request uuid, p_entity uuid) returns void
language plpgsql set search_path = '' as $$
begin
  if (select count(*) from app.notification_outbox
       where kind = 'takedown_request' and created_at > now() - interval '24 hours')
     < app._setting_int('takedown_mod_emails_per_day', 20) then
    perform app._notify('takedown_request', null, true, p_request, p_entity, null, 'pt');
  end if;
end $$;

-- ======================================================================
-- Pedido de retirada: nunca oculta
-- ======================================================================
drop function api.request_takedown(uuid, text, text, text, text, text);
drop function app.request_takedown(uuid, text, text, text, text, text);

create function app.request_takedown(p_entity uuid, p_reason text, p_relation text, p_contact text default null,
  p_locale text default 'pt', p_hp text default null, p_email text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_ip text; v_exists boolean; v_pub boolean; v_id uuid; v_email text; v_hash text; v_dom text; v_site text;
        v_match boolean := false; v_locale text; v_tok text; v_status text; v_need_conf boolean := false;
begin
  v_locale := app._norm_locale(p_locale);
  v_email := nullif(lower(btrim(coalesce(p_email, ''))), '');
  if app._hp_tripped(p_hp) then
    -- robô: resposta de sucesso no mesmo formato, nada é gravado
    return jsonb_build_object('request_id', gen_random_uuid(), 'hidden', false,
                              'needs_confirmation', v_email is not null, 'queued', v_email is null);
  end if;
  perform app._check_len(p_reason, 10, 2000, 'motivo');
  if p_relation is null or p_relation not in ('representative','member','mentioned','other') then
    raise exception 'relação inválida' using errcode = '22023';
  end if;
  if p_contact is not null and char_length(p_contact) > 200 then
    raise exception 'contato deve ter até 200 caracteres' using errcode = '22023';
  end if;
  if v_email is not null and (char_length(v_email) > 200 or v_email !~ '^[^@\s<>"]+@[^@\s<>"]+\.[a-z]{2,}$') then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  v_ip := app._antispam('takedown', 5, 20, 20);
  v_exists := exists (select 1 from app.entities where id = p_entity);
  v_pub := exists (select 1 from pub.entities where id = p_entity);

  if v_email is not null then
    v_hash := app._email_hash(v_email);
    v_dom := split_part(v_email, '@', 2);
    select app.url_domain(e.website_url) into v_site from app.entities e where e.id = p_entity;
    -- mesma regra da reivindicação por domínio: domínio compartilhado (gmail etc.) nunca "coincide"
    v_match := v_site is not null and not app._is_shared_domain(v_dom) and not app._is_shared_domain(v_site)
               and (v_site = v_dom or v_site like '%.' || v_dom);
  end if;

  if v_email is not null and v_pub then
    perform pg_advisory_xact_lock(7210001);   -- serializa a contagem dos limites de e-mail
    if (select count(*) from app.takedown_requests where email_hash = v_hash and confirm_sent_at > now() - interval '24 hours')
         < app._setting_int('takedown_confirm_per_email_day', 3)
       and (select count(*) from app.takedown_requests where confirm_sent_at > now() - interval '24 hours')
         < app._setting_int('takedown_confirm_emails_per_day', 40) then
      v_need_conf := true;
    end if;
  end if;

  v_status := case when v_need_conf then 'awaiting_confirmation'
                   when v_email is not null and not v_pub then 'expired'   -- nada a ocultar: sem e-mail de confirmação, mesma resposta
                   else 'open' end;
  insert into app.takedown_requests(entity_id, reason, relation, contact, locale, account_id, ip_hash, status,
                                    email, email_hash, email_domain, email_domain_matches, confirm_sent_at)
  values (case when v_exists then p_entity end, p_reason, p_relation, nullif(btrim(p_contact), ''), v_locale, auth.uid(), v_ip,
          v_status, case when v_status = 'expired' then null else v_email end, v_hash, v_dom,
          case when v_email is not null then v_match end, case when v_need_conf then now() end)
  returning id into v_id;

  if v_need_conf then
    -- 32 bytes aleatórios em hex (dois UUID v4 do gerador forte do servidor, sem pgcrypto)
    v_tok := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into app.takedown_tokens(request_id, token_hash, expires_at)
    values (v_id, app._sha(v_tok), now() + interval '24 hours');
    perform app._notify('takedown_confirm', null, false, v_id, p_entity,
                        jsonb_build_object('email', v_email, 'token', v_tok), v_locale);
  elsif v_status = 'open' and v_pub then
    perform app._notify_mod_takedown(v_id, p_entity);    -- fila da moderação (e-mail sujeito ao teto diário)
  end if;
  -- a resposta não distingue ficha inexistente, não publicada ou publicada
  return jsonb_build_object('request_id', v_id, 'hidden', false,
                            'needs_confirmation', v_email is not null and v_status <> 'open',
                            'queued', v_status = 'open');
end $$;

-- ======================================================================
-- Confirmação por link: oculta (se o disjuntor permitir)
-- ======================================================================
create function app.confirm_takedown(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tk app.takedown_tokens; r app.takedown_requests; v_tok text := lower(btrim(coalesce(p_token, '')));
        v_hour integer; v_day integer; v_mail integer;
begin
  perform app._antispam('takedown_confirm', 30, 100, 100);
  if v_tok !~ '^[0-9a-f]{64}$' then raise exception 'link inválido ou vencido' using errcode = 'P0002'; end if;
  perform pg_advisory_xact_lock(7210002);       -- serializa o disjuntor
  select * into tk from app.takedown_tokens
   where token_hash = app._sha(v_tok) and used_at is null and expires_at > now() for update;
  if not found then raise exception 'link inválido ou vencido' using errcode = 'P0002'; end if;
  select * into r from app.takedown_requests where id = tk.request_id and status = 'awaiting_confirmation' for update;
  if not found then raise exception 'link inválido ou vencido' using errcode = 'P0002'; end if;
  update app.takedown_tokens set used_at = now() where id = tk.id;

  -- ficha que já não está no ar (ocultada por outro pedido, arquivada, inexistente): o pedido segue para a fila
  if r.entity_id is null or not exists (select 1 from pub.entities where id = r.entity_id) then
    update app.takedown_requests set status = 'open', confirmed_at = now() where id = r.id;
    return jsonb_build_object('hidden', false, 'queued', true);
  end if;

  select count(*) into v_hour from app.takedown_requests where auto_hidden and hidden_at > now() - interval '1 hour';
  select count(*) into v_day  from app.takedown_requests where auto_hidden and hidden_at > now() - interval '24 hours';
  select count(*) into v_mail from app.takedown_requests
   where auto_hidden and email_hash = r.email_hash and hidden_at > now() - interval '24 hours';

  if v_hour < app._setting_int('takedown_autohide_per_hour', 15)
     and v_day < app._setting_int('takedown_autohide_per_day', 50)
     and v_mail < app._setting_int('takedown_autohide_per_email_day', 3) then
    update app.entities set publication_state = 'hidden', updated_at = now() where id = r.entity_id;
    perform app._project_entity(r.entity_id);                 -- some de lista, mapa, busca, contadores e exportação
    perform app._outbox(r.entity_id, 'takedown_preventive');  -- invalidação de cache
    update app.takedown_requests set status = 'open', auto_hidden = true, confirmed_at = now(), hidden_at = now() where id = r.id;
    perform app._audit('entity.hidden_preventive', 'entities', r.entity_id::text, jsonb_build_object('request', r.id));
    perform app._notify_mod_takedown(r.id, r.entity_id);
    return jsonb_build_object('hidden', true, 'queued', false);
  end if;

  -- disjuntor: o pedido fica na fila, a ficha continua no ar, e a moderação recebe UM alerta por janela de 24 h
  update app.takedown_requests set status = 'open', contained = true, confirmed_at = now() where id = r.id;
  if not exists (select 1 from app.notification_outbox where kind = 'takedown_containment' and created_at > now() - interval '24 hours') then
    perform app._notify('takedown_containment', null, true, r.id, r.entity_id, null, 'pt');
  end if;
  return jsonb_build_object('hidden', false, 'queued', true);
end $$;

-- ======================================================================
-- Moderação: desfazer em lote e visão agrupada
-- ======================================================================
create function app.mod_restore_auto_hidden(p_since timestamptz, p_until timestamptz, p_ip_hash text default null,
  p_email_hash text default null, p_rationale text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := app._require_uid(); r record; v_state app.publication_state; v_n integer := 0;
begin
  if not app.has_role('moderator') then perform app._not_found(); end if;
  if p_since is null or p_until is null or p_since >= p_until then
    raise exception 'janela inválida' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_rationale, ''))) < 10 then
    raise exception 'justificativa obrigatória (10+ caracteres)' using errcode = '22023';
  end if;
  for r in select distinct t.entity_id from app.takedown_requests t
            where t.auto_hidden and t.status = 'open' and t.entity_id is not null
              and t.hidden_at >= p_since and t.hidden_at <= p_until
              and (p_ip_hash is null or t.ip_hash = p_ip_hash)
              and (p_email_hash is null or t.email_hash = p_email_hash)
            order by t.entity_id loop
    select publication_state into v_state from app.entities where id = r.entity_id for update;
    -- só restaura o que ainda está oculto de forma reversível (não arquivada, sem tombstone)
    if v_state = 'hidden' and not app._is_suppressed(r.entity_id) then
      update app.entities set publication_state = 'published', updated_at = now() where id = r.entity_id;
      perform app._project_entity(r.entity_id);
      perform app._outbox(r.entity_id, 'restored');
      update app.takedown_requests set status = 'restored', decided_by = v_uid, decided_at = now(), rationale = left(p_rationale, 2000)
       where entity_id = r.entity_id and auto_hidden and status = 'open'
         and hidden_at >= p_since and hidden_at <= p_until
         and (p_ip_hash is null or ip_hash = p_ip_hash) and (p_email_hash is null or email_hash = p_email_hash);
      perform app._audit('entity.restored_batch', 'entities', r.entity_id::text,
                         jsonb_build_object('rationale', left(p_rationale, 500)));
      v_n := v_n + 1;
    end if;
  end loop;
  perform app._audit('takedown.batch_restored', 'takedown_requests', null,
                     jsonb_build_object('restored', v_n, 'since', p_since, 'until', p_until, 'ip_hash', p_ip_hash,
                                        'email_hash', p_email_hash, 'rationale', left(p_rationale, 500)));
  return v_n;
end $$;

-- Painel: ocultações e pedidos recentes por ip_hash e email_hash. Nenhum e-mail em claro: só domínio e hash.
create function app.mod_takedown_overview(p_hours integer default 48) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_h integer := least(greatest(coalesce(p_hours, 48), 1), 720); v_since timestamptz;
        v_hour integer; v_day integer; v_lim_hour integer; v_lim_day integer; v_alert timestamptz;
begin
  perform app._require_uid();
  if not app.has_role('moderator') then perform app._not_found(); end if;
  v_since := now() - make_interval(hours => v_h);
  v_lim_hour := app._setting_int('takedown_autohide_per_hour', 15);
  v_lim_day := app._setting_int('takedown_autohide_per_day', 50);
  select count(*) into v_hour from app.takedown_requests where auto_hidden and hidden_at > now() - interval '1 hour';
  select count(*) into v_day from app.takedown_requests where auto_hidden and hidden_at > now() - interval '24 hours';
  select max(created_at) into v_alert from app.notification_outbox where kind = 'takedown_containment';
  return jsonb_build_object(
    'window_hours', v_h,
    'breaker', jsonb_build_object(
      'hidden_last_hour', v_hour, 'limit_per_hour', v_lim_hour,
      'hidden_last_24h', v_day, 'limit_per_day', v_lim_day,
      'limit_per_email_day', app._setting_int('takedown_autohide_per_email_day', 3),
      'tripped', v_hour >= v_lim_hour or v_day >= v_lim_day,
      'contained_last_24h', (select count(*) from app.takedown_requests where contained and confirmed_at > now() - interval '24 hours'),
      'last_containment_alert_at', v_alert,
      'confirm_emails_last_24h', (select count(*) from app.takedown_requests where confirm_sent_at > now() - interval '24 hours'),
      'confirm_emails_limit_per_day', app._setting_int('takedown_confirm_emails_per_day', 40)),
    'by_ip', coalesce((select jsonb_agg(x order by (x->>'requests')::int desc, x->>'ip_hash') from (
        select jsonb_build_object('ip_hash', t.ip_hash, 'requests', count(*), 'hidden', count(*) filter (where t.auto_hidden),
               'contained', count(*) filter (where t.contained), 'awaiting', count(*) filter (where t.status = 'awaiting_confirmation'),
               'first_at', min(t.created_at), 'last_at', max(t.created_at)) as x
          from app.takedown_requests t where t.created_at >= v_since and t.ip_hash is not null
         group by t.ip_hash order by count(*) desc limit 50) s), '[]'),
    'by_email', coalesce((select jsonb_agg(x order by (x->>'requests')::int desc, x->>'email_hash') from (
        select jsonb_build_object('email_hash', t.email_hash, 'email_domain', max(t.email_domain), 'requests', count(*),
               'hidden', count(*) filter (where t.auto_hidden), 'contained', count(*) filter (where t.contained),
               'awaiting', count(*) filter (where t.status = 'awaiting_confirmation'),
               'domain_matches', bool_or(coalesce(t.email_domain_matches, false)),
               'first_at', min(t.created_at), 'last_at', max(t.created_at)) as x
          from app.takedown_requests t where t.created_at >= v_since and t.email_hash is not null
         group by t.email_hash order by count(*) desc limit 50) s), '[]'));
end $$;

-- ======================================================================
-- Funções existentes ajustadas (CREATE OR REPLACE mantém os GRANTs)
-- ======================================================================
create or replace function app.mod_list(p_queue text, p_status text default null, p_limit integer default 50,
  p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_lim integer := least(greatest(coalesce(p_limit, 50), 1), 200); v_off integer := greatest(coalesce(p_offset, 0), 0);
begin
  perform app._require_uid();
  if not app.has_role('moderator') then perform app._not_found(); end if;
  if p_queue = 'takedowns' then
    return coalesce((select jsonb_agg(x) from (
      select t.id, t.entity_id, e.original_name as entity_name, e.slug as entity_slug, e.publication_state as entity_state,
             t.reason, t.relation, t.contact, t.locale, t.auto_hidden, t.contained, t.status, t.created_at, t.decided_at, t.rationale,
             t.email, t.email_domain, t.email_domain_matches, t.email_hash, t.ip_hash, t.confirmed_at, t.hidden_at
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

create or replace function app.notification_claim(p_id bigint) returns jsonb
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
                                 'auto_hidden', v_tk.auto_hidden, 'contained', v_tk.contained, 'locale', v_tk.locale,
                                 'has_email', v_tk.email_hash is not null, 'email_domain_matches', v_tk.email_domain_matches);
  elsif n.kind = 'takedown_confirm' then
    -- o token em claro só existe em notification_secrets; sem ele (ou com o pedido já vencido) não há o que enviar
    select * into v_tk from app.takedown_requests where id = n.ref_id;
    if v_secret is null or v_secret->>'token' is null or v_tk.status is distinct from 'awaiting_confirmation' then
      update app.notification_outbox set attempts = 5, claimed_at = null, last_error = 'descartada: sem token ou pedido vencido' where id = p_id;
      delete from app.notification_secrets where outbox_id = p_id;
      return null;
    end if;
    v_data := jsonb_build_object('token', v_secret->>'token', 'locale', n.locale);
  elsif n.kind = 'takedown_containment' then
    v_data := jsonb_build_object(
      'hidden_last_hour', (select count(*) from app.takedown_requests where auto_hidden and hidden_at > now() - interval '1 hour'),
      'hidden_last_24h', (select count(*) from app.takedown_requests where auto_hidden and hidden_at > now() - interval '24 hours'),
      'contained_last_24h', (select count(*) from app.takedown_requests where contained and confirmed_at > now() - interval '24 hours'),
      'limit_per_hour', app._setting_int('takedown_autohide_per_hour', 15),
      'limit_per_day', app._setting_int('takedown_autohide_per_day', 50));
  elsif n.kind = 'contact_message' then
    select * into v_cm from app.contact_messages where id = n.ref_id;
    v_data := jsonb_build_object('sender_name', v_cm.sender_name, 'reply_to', v_cm.sender_email, 'subject', v_cm.subject,
                                 'body', v_cm.body, 'locale', v_cm.locale);
  end if;
  return jsonb_build_object('id', n.id, 'kind', n.kind, 'locale', n.locale, 'to', v_to, 'entity', v_entity,
                            'data', v_data, 'created_at', n.created_at);
end $$;

create or replace function app.purge_expired() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a integer; b integer; c integer; d integer; e integer;
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
  -- retiradas que ninguém confirmou em 24 h: encerra e apaga o e-mail em claro (fica o hash para os limites)
  update app.takedown_requests set status = 'expired', email = null
   where status = 'awaiting_confirmation' and created_at < now() - interval '1 day';
  get diagnostics e = row_count;
  update app.takedown_requests set email = null where status = 'expired' and email is not null;
  delete from app.takedown_tokens where expires_at < now() - interval '2 days';
  -- ofertas vencidas saem da projeção (as views já filtram por data; isto só limpa)
  delete from pub.offers_needs where valid_until < current_date;
  return jsonb_build_object('rate_limits', a, 'secrets', b, 'connect_expired', c, 'invites_expired', d, 'takedowns_expired', e);
end $$;

-- ======================================================================
-- Wrappers da API e EXECUTE
-- ======================================================================
create function api.request_takedown(p_entity uuid, p_reason text, p_relation text, p_contact text default null,
  p_locale text default 'pt', p_hp text default null, p_email text default null) returns jsonb
language sql security invoker set search_path = '' as
$$ select app.request_takedown(p_entity, p_reason, p_relation, p_contact, p_locale, p_hp, p_email) $$;
create function api.confirm_takedown(p_token text) returns jsonb
language sql security invoker set search_path = '' as $$ select app.confirm_takedown(p_token) $$;
create function api.mod_restore_auto_hidden(p_since timestamptz, p_until timestamptz, p_ip_hash text default null,
  p_email_hash text default null, p_rationale text default null) returns integer
language sql security invoker set search_path = '' as
$$ select app.mod_restore_auto_hidden(p_since, p_until, p_ip_hash, p_email_hash, p_rationale) $$;
create function api.mod_takedown_overview(p_hours integer default 48) returns jsonb
language sql security invoker set search_path = '' as $$ select app.mod_takedown_overview(p_hours) $$;

revoke all on function app._setting_int(text, integer), app._email_hash(text), app._notify_mod_takedown(uuid, uuid),
  app.request_takedown(uuid, text, text, text, text, text, text), app.confirm_takedown(text),
  app.mod_restore_auto_hidden(timestamptz, timestamptz, text, text, text), app.mod_takedown_overview(integer),
  api.request_takedown(uuid, text, text, text, text, text, text), api.confirm_takedown(text),
  api.mod_restore_auto_hidden(timestamptz, timestamptz, text, text, text), api.mod_takedown_overview(integer) from public;

grant execute on function app.request_takedown(uuid, text, text, text, text, text, text), app.confirm_takedown(text),
  api.request_takedown(uuid, text, text, text, text, text, text), api.confirm_takedown(text) to anon, authenticated;
grant execute on function app.mod_restore_auto_hidden(timestamptz, timestamptz, text, text, text), app.mod_takedown_overview(integer),
  api.mod_restore_auto_hidden(timestamptz, timestamptz, text, text, text), api.mod_takedown_overview(integer) to authenticated;
