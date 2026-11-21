-- 0012 DOWN — volta ao comportamento anterior da retirada (ocultação imediata, disjuntor global de 30/h)
-- Pedidos ainda sem confirmação ou vencidos (que nunca ocultaram nada) e as notificações novas são descartados.
drop function api.mod_takedown_overview(integer);
drop function api.mod_restore_auto_hidden(timestamptz, timestamptz, text, text, text);
drop function api.confirm_takedown(text);
drop function api.request_takedown(uuid, text, text, text, text, text, text);
drop function app.mod_takedown_overview(integer);
drop function app.mod_restore_auto_hidden(timestamptz, timestamptz, text, text, text);
drop function app.confirm_takedown(text);
drop function app.request_takedown(uuid, text, text, text, text, text, text);

delete from app.notification_outbox where kind in ('takedown_confirm', 'takedown_containment');   -- segredos saem em cascata
delete from app.takedown_requests where status in ('awaiting_confirmation', 'expired');
drop table app.takedown_tokens;
alter table app.notification_outbox drop constraint notification_outbox_kind_check;
alter table app.notification_outbox add constraint notification_outbox_kind_check
  check (kind in ('connect_received','connect_accepted','claim_code','claim_pending','claim_approved','claim_rejected',
                  'takedown_request','contact_message','invite_accepted'));
alter table app.takedown_requests drop constraint takedown_requests_status_check;
alter table app.takedown_requests add constraint takedown_requests_status_check
  check (status in ('open','confirmed','restored','closed_kept_hidden'));
drop index if exists app.takedown_requests_email_hash_hidden_at_idx, app.takedown_requests_hidden_at_idx,
  app.takedown_requests_confirm_sent_at_idx, app.takedown_requests_ip_hash_idx;
alter table app.takedown_requests
  drop column email, drop column email_hash, drop column email_domain, drop column email_domain_matches,
  drop column confirm_sent_at, drop column confirmed_at, drop column hidden_at, drop column contained;

drop function app._notify_mod_takedown(uuid, uuid);
drop function app._email_hash(text);

delete from app.settings where key in ('takedown_autohide_per_day', 'takedown_autohide_per_email_day',
  'takedown_confirm_per_email_day', 'takedown_confirm_emails_per_day', 'takedown_mod_emails_per_day');
update app.settings set value = '30' where key = 'takedown_autohide_per_hour' and value = '15';

-- Funções ajustadas pelo 0012: volta às definições do 0010 / 0011 (mod_list, notification_claim, purge_expired)
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
                                 'auto_hidden', v_tk.auto_hidden, 'locale', v_tk.locale);
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

drop function app._setting_int(text, integer);

-- Pedido de retirada anterior (oculta na hora quando o disjuntor permite)
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

create function api.request_takedown(p_entity uuid, p_reason text, p_relation text, p_contact text default null,
  p_locale text default 'pt', p_hp text default null) returns jsonb
language sql security invoker set search_path = '' as
$$ select app.request_takedown(p_entity, p_reason, p_relation, p_contact, p_locale, p_hp) $$;

revoke all on function app.request_takedown(uuid, text, text, text, text, text), api.request_takedown(uuid, text, text, text, text, text) from public;
grant execute on function app.request_takedown(uuid, text, text, text, text, text), api.request_takedown(uuid, text, text, text, text, text)
  to anon, authenticated;
