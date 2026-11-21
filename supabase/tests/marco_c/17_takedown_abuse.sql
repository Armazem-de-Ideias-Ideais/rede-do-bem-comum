-- Marco C, teste 17 (migração 0012): retirada com proteção contra abuso.
-- Pedido nunca oculta; só o link enviado ao e-mail oculta; token de uso único e com validade; limites por e-mail;
-- disjuntor por hora/dia/e-mail com UM alerta por janela; limite de e-mails de confirmação; desfazer em lote;
-- visão agrupada sem e-mail em claro; anon e conta comum sem acesso a funções de moderação, e-mail, token ou hash.
begin;
select plan(135);

-- ---------- preparação (owner) ----------
select tests.as_owner();
insert into tests.fx(key, id)
select 'T' || n, id from (
  select e.id, row_number() over (order by e.slug) as n from pub.entities e
   where e.counter_class = 'initiative' and e.id not in (select id from tests.fx where id is not null)
   order by e.slug limit 14) s;
-- o token em claro só existe em notification_secrets; o teste o lê como owner (nunca por api)
create function tests.tok(p_entity uuid) returns text language sql security definer as $$
  select s.data->>'token' from app.notification_secrets s join app.notification_outbox o on o.id = s.outbox_id
   where o.kind = 'takedown_confirm' and o.entity_id = p_entity order by o.id desc limit 1 $$;
create function tests.listed(p_entity uuid) returns integer language sql as $$ select count(*)::int from api.entity_list where id = p_entity $$;
create function tests.req_email(p_entity uuid, p_email text) returns jsonb language sql as
$$ select api.request_takedown(p_entity, 'Não autorizamos a publicação desta ficha.', 'representative', null, 'pt', null, p_email) $$;
grant execute on function tests.tok(uuid), tests.listed(uuid), tests.req_email(uuid, text) to anon, authenticated, service_role;
select ok(tests.id('T14') is not null, 'preparação: 14 fichas extras para os cenários');

-- ======================================================================
-- A. O pedido nunca oculta; o link oculta
-- ======================================================================
select tests.as_anon();
select tests.ip('203.0.113.31');
select is(tests.req_email(tests.id('T1'), 'Alguem@Exemplo.invalid') - 'request_id',
          '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'com e-mail: pede confirmação, hidden=false');
select is(tests.listed(tests.id('T1')), 1, 'com e-mail: a ficha continua no ar');
select tests.as_owner();
select is((select status from app.takedown_requests where entity_id = tests.id('T1')), 'awaiting_confirmation', 'pedido aguardando confirmação');
select is((select count(*)::int from app.takedown_requests where entity_id = tests.id('T1') and not auto_hidden and hidden_at is null), 1, 'ainda não ocultou');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_confirm' and entity_id = tests.id('T1') and not to_moderator), 1,
          'e-mail de confirmação enfileirado para quem pediu');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id = tests.id('T1')), 0,
          'moderação ainda não é avisada (só depois da ocultação confirmada)');
select is((select count(*)::int from app.takedown_tokens where request_id = (select id from app.takedown_requests where entity_id = tests.id('T1'))
            and used_at is null and expires_at > now() + interval '23 hours' and expires_at <= now() + interval '24 hours'), 1, 'token com validade de 24 h');
select ok(length(tests.tok(tests.id('T1'))) = 64 and tests.tok(tests.id('T1')) ~ '^[0-9a-f]{64}$', 'token de 32 bytes em hexadecimal');
select is((select token_hash from app.takedown_tokens limit 1), encode(sha256(convert_to(tests.tok(tests.id('T1')), 'UTF8')), 'hex'),
          'só o sha256 do token fica na tabela de tokens');
select is((select count(*)::int from (
            select row_to_json(t)::text s from app.takedown_requests t union all select row_to_json(t)::text from app.takedown_tokens t
            union all select row_to_json(t)::text from app.notification_outbox t union all select row_to_json(t)::text from app.audit_log t) x
            where s like '%' || tests.tok(tests.id('T1')) || '%'), 0, 'token em claro não aparece em pedidos, tokens, fila nem auditoria');
select is((select count(*)::int from app.takedown_requests where email = 'alguem@exemplo.invalid' and email_domain = 'exemplo.invalid'
            and email_hash ~ '^[0-9a-f]{64}$' and email_hash <> 'alguem@exemplo.invalid'), 1, 'e-mail normalizado só na tabela privada, com hash');

-- a Edge Function recebe o token pelo contexto (service_role); depois do envio o segredo é apagado
select tests.as_service();
select is((api.notification_claim((select id from app.notification_outbox where kind = 'takedown_confirm' and entity_id = tests.id('T1')))::jsonb)->'to'->>'email',
          'alguem@exemplo.invalid', 'contexto traz o destinatário (quem pediu)');
select tests.as_owner();
select is((select count(*)::int from app.notification_secrets s join app.notification_outbox o on o.id = s.outbox_id
            where o.kind = 'takedown_confirm' and o.entity_id = tests.id('T1')), 1, 'segredo ainda existe antes do envio');
select tests.as_service();
select lives_ok(format('select api.notification_done(%s, true)', (select id from app.notification_outbox where kind = 'takedown_confirm' and entity_id = tests.id('T1'))),
                'envio marcado como concluído');
select tests.as_owner();
select is((select count(*)::int from app.notification_secrets s join app.notification_outbox o on o.id = s.outbox_id where o.kind = 'takedown_confirm'), 0,
          'depois do envio o token e o e-mail são apagados do payload');
-- o token de T1 já foi descartado do banco (só resta o hash); o fluxo de confirmação segue com T3
select tests.as_anon();
select tests.ip('203.0.113.31');
select is(tests.req_email(tests.id('T3'), 'alguem@exemplo.invalid') - 'request_id',
          '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'segundo pedido do mesmo e-mail (ficha T3)');
select is(api.confirm_takedown(tests.tok(tests.id('T3'))), '{"hidden":true,"queued":false}'::jsonb, 'confirmar o link oculta a ficha');
select is(tests.listed(tests.id('T3')), 0, 'T3 saiu da lista');
select is(api.entity_page(null, tests.id('T3')), null, 'T3 não abre por id');
select throws_ok(format('select api.confirm_takedown(%L)', (select tests.tok(tests.id('T3')))), 'P0002', 'link inválido ou vencido', 'segunda confirmação com o mesmo link → erro genérico');
select tests.as_owner();
select is((select count(*)::int from app.takedown_requests where entity_id = tests.id('T3') and status = 'open' and auto_hidden
            and hidden_at is not null and confirmed_at is not null), 1, 'pedido na fila, marcado como ocultação automática confirmada');
select is((select count(*)::int from app.takedown_tokens where used_at is not null), 1, 'token marcado como usado');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id = tests.id('T3') and to_moderator), 1,
          'moderação recebe e-mail pela ocultação confirmada');
select is((select count(*)::int from app.audit_log where action = 'entity.hidden_preventive' and target_id = tests.id('T3')::text), 1, 'auditoria da ocultação');

-- token de uso único
insert into tests.fx(key, txt) select 'T3_USED', token_hash from app.takedown_tokens where used_at is not null;
select tests.as_anon();
select tests.ip('203.0.113.31');
-- T2: pedido, vencimento do token, resposta genérica
select is(tests.req_email(tests.id('T2'), 'outra@exemplo.invalid') - 'request_id',
          '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'pedido para T2');
select tests.as_owner();
insert into tests.fx(key, txt) values ('T2_TOKEN', tests.tok(tests.id('T2')));
select tests.as_anon();
select tests.ip('203.0.113.31');
select is(api.confirm_takedown(tests.txt('T2_TOKEN')), '{"hidden":true,"queued":false}'::jsonb, 'T2 confirmada');
select throws_ok(format('select api.confirm_takedown(%L)', tests.txt('T2_TOKEN')), 'P0002', 'link inválido ou vencido', 'token usado de novo → erro genérico');
select is(tests.listed(tests.id('T2')), 0, 'T2 oculta (uma vez só)');

-- vencido, formato inválido e inexistente: mesmo erro genérico
select tests.ip('203.0.113.32');
select is(tests.req_email(tests.id('T4'), 'venc@exemplo.invalid') - 'request_id',
          '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'pedido para T4 (token vai vencer)');
select tests.as_owner();
insert into tests.fx(key, txt) values ('T4_TOKEN', tests.tok(tests.id('T4')));
update app.takedown_tokens set expires_at = now() - interval '1 second' where token_hash = app._sha(tests.txt('T4_TOKEN'));
select tests.as_anon();
select tests.ip('203.0.113.32');
select throws_ok(format('select api.confirm_takedown(%L)', tests.txt('T4_TOKEN')), 'P0002', 'link inválido ou vencido', 'token vencido → erro genérico');
select is(tests.listed(tests.id('T4')), 1, 'token vencido não oculta');
select throws_ok($$ select api.confirm_takedown('nao-e-token') $$, 'P0002', 'link inválido ou vencido', 'formato inválido → mesmo erro');
select throws_ok($$ select api.confirm_takedown(repeat('ab', 32)) $$, 'P0002', 'link inválido ou vencido', 'token inexistente → mesmo erro');
select throws_ok($$ select api.confirm_takedown(null) $$, 'P0002', 'link inválido ou vencido', 'token nulo → mesmo erro');

-- pedidos que ninguém confirmou expiram e o e-mail em claro é apagado
select tests.as_owner();
update app.takedown_requests set created_at = now() - interval '2 days' where entity_id = tests.id('T4');
select ok((app.purge_expired()->>'takedowns_expired')::int >= 1, 'purge: pedido não confirmado em 24 h expira');
select is((select status || ':' || coalesce(email, 'sem-email') from app.takedown_requests where entity_id = tests.id('T4')), 'expired:sem-email',
          'purge: e-mail em claro apagado (fica só o hash)');

-- ======================================================================
-- B. Sem e-mail: fila da moderação, ficha no ar
-- ======================================================================
select tests.as_anon();
select tests.ip('203.0.113.33');
select is(api.request_takedown(tests.id('T5'), 'Pedimos a retirada, mas sem e-mail.', 'member') - 'request_id',
          '{"hidden":false,"needs_confirmation":false,"queued":true}'::jsonb, 'sem e-mail: vai para a fila');
select is(tests.listed(tests.id('T5')), 1, 'sem e-mail: a ficha continua no ar');
select is(api.request_takedown(tests.id('T5'), 'Pedimos a retirada, e-mail vazio.', 'member', null, 'pt', null, '   ') - 'request_id',
          '{"hidden":false,"needs_confirmation":false,"queued":true}'::jsonb, 'e-mail só com espaços vale como ausente');
select tests.as_owner();
select is((select count(*)::int from app.takedown_requests where entity_id = tests.id('T5') and status = 'open' and not auto_hidden and email is null), 2,
          'pedidos sem e-mail abertos na fila');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id = tests.id('T5')), 2,
          'um e-mail à moderação por pedido sem e-mail');
select is((select count(*)::int from app.takedown_tokens t join app.takedown_requests r on r.id = t.request_id where r.entity_id = tests.id('T5')), 0,
          'sem e-mail não há token');

-- ======================================================================
-- C. Resposta idêntica para ficha inexistente, oculta ou publicada
-- ======================================================================
select tests.as_anon();
select tests.ip('203.0.113.34');
select is(tests.req_email(gen_random_uuid(), 'fantasma@exemplo.invalid') - 'request_id', tests.req_email(tests.id('T6'), 'real@exemplo.invalid') - 'request_id',
          'com e-mail: ficha inexistente e publicada recebem a mesma resposta');
select is(tests.req_email(tests.id('T3'), 'oculta@exemplo.invalid') - 'request_id', tests.req_email(tests.id('T6'), 'real2@exemplo.invalid') - 'request_id',
          'com e-mail: ficha já oculta e publicada recebem a mesma resposta');
select tests.ip('203.0.113.42');
select is(api.request_takedown(gen_random_uuid(), 'Pedido para uma ficha que não existe.', 'other') - 'request_id',
          api.request_takedown(tests.id('T7'), 'Pedido para uma ficha publicada.', 'other') - 'request_id', 'sem e-mail: mesma resposta');
select is((api.request_takedown(gen_random_uuid(), 'Pedido para uma ficha que não existe.', 'other', null, 'pt', 'preenchido', 'a@exemplo.invalid') - 'request_id'),
          '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'honeypot com e-mail: mesma forma de resposta');
select tests.as_owner();
select is((select count(*)::int from app.takedown_tokens t join app.takedown_requests r on r.id = t.request_id
            where r.email in ('fantasma@exemplo.invalid', 'oculta@exemplo.invalid')), 0, 'ficha inexistente ou já oculta: nenhum token e nenhum e-mail gasto');
select is((select count(*)::int from app.takedown_requests where email_hash is not null and email is null and status = 'expired'
            and email_hash = app._email_hash('fantasma@exemplo.invalid')), 1, 'o pedido foi registrado (expirado, sem e-mail em claro)');
select is((select count(*)::int from app.takedown_requests where reason = 'Pedido para uma ficha que não existe.' and entity_id is null), 1,
          'sem e-mail: pedido para ficha inexistente registrado sem entidade, sem aviso à moderação');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id not in (select id from app.entities)), 0,
          'nenhum e-mail à moderação para ficha inexistente');

-- ======================================================================
-- D. Limites de e-mail: 3 por endereço por dia
-- ======================================================================
select tests.as_anon();
select tests.ip('203.0.113.35');
select is(tests.req_email(tests.id('E1'), 'limite@exemplo.invalid') - 'request_id', '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, '1º e-mail de confirmação');
select is(tests.req_email(tests.id('E2'), 'LIMITE@exemplo.invalid') - 'request_id', '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, '2º (caixa alta não escapa do limite)');
select is(tests.req_email(tests.id('E3'), ' limite@exemplo.invalid ') - 'request_id', '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, '3º (espaços não escapam do limite)');
select is(tests.req_email(tests.id('E4'), 'limite@exemplo.invalid') - 'request_id', '{"hidden":false,"needs_confirmation":false,"queued":true}'::jsonb,
          '4º no dia: registrado na fila, sem e-mail de confirmação, queued=true');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_confirm' and entity_id in (tests.id('E1'), tests.id('E2'), tests.id('E3'), tests.id('E4'))), 3,
          'só 3 e-mails de confirmação saíram para o mesmo endereço');
select is((select count(*)::int from app.takedown_requests where entity_id = tests.id('E4') and status = 'open' and not auto_hidden), 1, 'o 4º está na fila da moderação');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id = tests.id('E4')), 1, 'e a moderação foi avisada dele');

-- ======================================================================
-- E. Disjuntor por e-mail: no máximo 3 ocultações por email_hash em 24 h
-- ======================================================================
update app.settings set value = '10' where key = 'takedown_confirm_per_email_day';   -- isola o disjuntor do limite de envio
update app.takedown_requests set hidden_at = now() - interval '5 days', confirmed_at = now() - interval '5 days' where auto_hidden;
select tests.as_anon();
select tests.ip('203.0.113.36');
select tests.req_email(tests.id('T8'), 'mesmo@exemplo.invalid');
select tests.req_email(tests.id('T9'), 'mesmo@exemplo.invalid');
select tests.req_email(tests.id('T10'), 'mesmo@exemplo.invalid');
select tests.req_email(tests.id('T11'), 'mesmo@exemplo.invalid');
select is(api.confirm_takedown(tests.tok(tests.id('T8')))->>'hidden', 'true', 'e-mail: 1ª ocultação');
select is(api.confirm_takedown(tests.tok(tests.id('T9')))->>'hidden', 'true', 'e-mail: 2ª ocultação');
select is(api.confirm_takedown(tests.tok(tests.id('T10')))->>'hidden', 'true', 'e-mail: 3ª ocultação');
select is(api.confirm_takedown(tests.tok(tests.id('T11'))), '{"hidden":false,"queued":true}'::jsonb, 'e-mail: 4ª barrada pelo disjuntor, vai para a fila');
select is(tests.listed(tests.id('T11')), 1, 'e-mail: a 4ª ficha continua no ar');
select tests.as_owner();
select is((select count(*)::int from app.takedown_requests where entity_id = tests.id('T11') and contained and status = 'open' and not auto_hidden), 1, 'e-mail: pedido marcado contained=true e aberto');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_containment'), 1, 'e-mail: moderação recebe o alerta de contenção');

-- ======================================================================
-- F. Disjuntor global por hora: um único alerta por janela de 24 h
-- ======================================================================
update app.takedown_requests set hidden_at = now() - interval '5 days', confirmed_at = now() - interval '5 days' where auto_hidden;
update app.notification_outbox set created_at = now() - interval '2 days' where kind = 'takedown_containment';   -- nova janela
update app.settings set value = '2' where key = 'takedown_autohide_per_hour';
select tests.as_anon();
select tests.ip('203.0.113.37');
select tests.req_email(tests.id('T12'), 'h1@exemplo.invalid');
select tests.req_email(tests.id('T13'), 'h2@exemplo.invalid');
select tests.req_email(tests.id('T14'), 'h3@exemplo.invalid');
select tests.req_email(tests.id('E5'), 'h4@exemplo.invalid');
select is(api.confirm_takedown(tests.tok(tests.id('T12')))->>'hidden', 'true', 'hora: 1ª ocultação');
select is(api.confirm_takedown(tests.tok(tests.id('T13')))->>'hidden', 'true', 'hora: 2ª ocultação (limite = 2)');
select is(api.confirm_takedown(tests.tok(tests.id('T14'))), '{"hidden":false,"queued":true}'::jsonb, 'hora: 3ª barrada');
select is(api.confirm_takedown(tests.tok(tests.id('E5'))), '{"hidden":false,"queued":true}'::jsonb, 'hora: 4ª também barrada');
select tests.as_owner();
select is((select count(*)::int from app.takedown_requests where contained and entity_id in (tests.id('T14'), tests.id('E5'))), 2, 'hora: os dois pedidos barrados ficam contained');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_containment' and created_at > now() - interval '1 day'), 1,
          'hora: um único alerta para os dois pedidos barrados');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id in (tests.id('T14'), tests.id('E5'))), 0,
          'hora: pedidos barrados não geram e-mail individual à moderação');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id in (tests.id('T12'), tests.id('T13'))), 2,
          'hora: cada ocultação confirmada gera um e-mail à moderação');

-- ======================================================================
-- G. Disjuntor global por dia
-- ======================================================================
update app.takedown_requests set hidden_at = now() - interval '2 hours', confirmed_at = now() - interval '2 hours' where auto_hidden and hidden_at > now() - interval '1 hour';
update app.notification_outbox set created_at = now() - interval '2 days' where kind = 'takedown_containment';
update app.settings set value = '100' where key = 'takedown_autohide_per_hour';
select is((select count(*)::int from app.takedown_requests where auto_hidden and hidden_at > now() - interval '24 hours'), 2,
          'dia: duas ocultações (as da hora anterior, agora 2 h atrás) contam na janela de 24 h');
update app.settings set value = '3' where key = 'takedown_autohide_per_day';
update app.settings set value = '100' where key = 'takedown_autohide_per_email_day';
select tests.as_anon();
select tests.ip('203.0.113.38');
select tests.req_email(tests.id('DB'), 'd1@exemplo.invalid');
select tests.req_email(tests.id('DC'), 'd2@exemplo.invalid');
select is(api.confirm_takedown(tests.tok(tests.id('DB')))->>'hidden', 'true', 'dia: 3ª ocultação (limite = 3)');
select is(api.confirm_takedown(tests.tok(tests.id('DC'))), '{"hidden":false,"queued":true}'::jsonb, 'dia: 4ª barrada pelo teto diário');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_containment' and created_at > now() - interval '1 day'), 1,
          'dia: novo alerta de contenção só porque a janela anterior já passou');
update app.settings set value = '50' where key = 'takedown_autohide_per_day';
update app.settings set value = '15' where key = 'takedown_autohide_per_hour';
update app.settings set value = '3' where key = 'takedown_autohide_per_email_day';
update app.settings set value = '3' where key = 'takedown_confirm_per_email_day';

-- ======================================================================
-- H. Limite global de e-mails de confirmação vira fila
-- ======================================================================
update app.settings set value = ((select count(*) from app.takedown_requests where confirm_sent_at > now() - interval '24 hours') + 1)::text
 where key = 'takedown_confirm_emails_per_day';
select tests.as_anon();
select tests.ip('203.0.113.39');
select is(tests.req_email(tests.id('DN'), 'g1@exemplo.invalid') - 'request_id', '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'cota global: ainda cabe um e-mail');
select is(tests.req_email(tests.id('PA'), 'g2@exemplo.invalid') - 'request_id', '{"hidden":false,"needs_confirmation":false,"queued":true}'::jsonb,
          'cota global esgotada: pedido registrado na fila, queued=true');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_confirm' and entity_id = tests.id('PA')), 0, 'cota global: nenhum e-mail de confirmação a mais');
select is((select count(*)::int from app.takedown_requests where entity_id = tests.id('PA') and status = 'open' and email_hash = app._email_hash('g2@exemplo.invalid')), 1,
          'cota global: pedido aberto na fila da moderação');
update app.settings set value = '40' where key = 'takedown_confirm_emails_per_day';

-- ======================================================================
-- I. Teto de e-mails à moderação (takedown_request) por dia
-- ======================================================================
update app.settings set value = ((select count(*) from app.notification_outbox where kind = 'takedown_request' and created_at > now() - interval '24 hours') + 1)::text
 where key = 'takedown_mod_emails_per_day';
select tests.as_anon();
select tests.ip('203.0.113.40');
select api.request_takedown(tests.id('PB'), 'Primeiro pedido sem e-mail depois do teto.', 'other');
select api.request_takedown(tests.id('X'), 'Segundo pedido sem e-mail depois do teto.', 'other');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and entity_id in (tests.id('PB'), tests.id('X'))), 1,
          'teto diário: só um dos dois pedidos gerou e-mail à moderação');
select is((select count(*)::int from app.takedown_requests where entity_id in (tests.id('PB'), tests.id('X')) and status = 'open'), 2,
          'teto diário: os dois pedidos estão na fila (o painel mostra tudo)');
update app.settings set value = '20' where key = 'takedown_mod_emails_per_day';

-- ======================================================================
-- J. email_domain_matches
-- ======================================================================
select tests.as_anon();
select tests.ip('203.0.113.41');
select tests.req_email(tests.id('W'), 'pessoa@' || tests.txt('W'));
select tests.req_email(tests.id('Y'), 'pessoa@gmail.com');
select tests.req_email(tests.id('A') , 'sem-ficha@exemplo.invalid');
select tests.as_owner();
select is((select email_domain_matches from app.takedown_requests where entity_id = tests.id('W') and email like 'pessoa@%'), true, 'domínio do e-mail = domínio do site da ficha → true');
select is((select email_domain_matches from app.takedown_requests where entity_id = tests.id('Y') and email like 'pessoa@%'), false, 'e-mail de domínio compartilhado → false');
select is((select email_domain_matches from app.takedown_requests where email = 'sem-ficha@exemplo.invalid' or email_hash = app._email_hash('sem-ficha@exemplo.invalid')), false,
          'ficha inexistente → false');
select is((select count(*)::int from app.takedown_requests where email is null and email_hash is null and email_domain_matches is null and status = 'open'), (select count(*)::int from app.takedown_requests where email_hash is null and status = 'open'),
          'sem e-mail: email_domain_matches fica nulo');
select tests.as_user(tests.id('MOD'));
select is((select (x->>'email_domain_matches')::boolean from jsonb_array_elements(api.mod_list('takedowns', 'awaiting_confirmation')) x where x->>'entity_id' = tests.id('W')::text), true,
          'moderação vê email_domain_matches (também nos pedidos aguardando confirmação)');
select is((select count(*)::int from jsonb_array_elements(api.mod_list('takedowns')) x where x->>'status' = 'awaiting_confirmation'), 0,
          'a fila aberta não mostra pedidos aguardando confirmação');
select is((api.mod_queue_counts()->>'takedowns')::int, (select count(*)::int from jsonb_array_elements(api.mod_list('takedowns', 'open', 200)) x), 'contador da fila bate com a fila aberta (sem pedidos aguardando)');
select tests.as_anon();

-- ======================================================================
-- K. Desfazer em lote (janela, ip_hash, email_hash) e visão agrupada
-- ======================================================================
select tests.as_owner();
-- tudo o que foi oculto até aqui passa para 5 dias atrás
update app.takedown_requests set hidden_at = now() - interval '5 days', confirmed_at = now() - interval '5 days' where auto_hidden;
select is((select count(*)::int from app.takedown_requests where auto_hidden and status = 'open'), 8, 'lote: 8 ocultações antigas (5 dias atrás) ainda abertas');
select tests.as_anon();
-- IP-B: m3 e m4; IP-A: m1 duas vezes
select tests.ip('203.0.113.51');
select tests.req_email(tests.id('PA'), 'm1@exemplo.invalid');
select tests.req_email(tests.id('PB'), 'm1@exemplo.invalid');
select api.confirm_takedown(tests.tok(tests.id('PA')));
select api.confirm_takedown(tests.tok(tests.id('PB')));
select tests.ip('203.0.113.52');
select tests.req_email(tests.id('X'), 'm3@exemplo.invalid');
select tests.req_email(tests.id('Y'), 'm4@exemplo.invalid');
select is(api.confirm_takedown(tests.tok(tests.id('X')))->>'hidden', 'true', 'lote: X oculta (IP-B, e-mail m3)');
select is(api.confirm_takedown(tests.tok(tests.id('Y')))->>'hidden', 'true', 'lote: Y oculta (IP-B, e-mail m4)');
select is((select count(*)::int from api.entity_list where id in (tests.id('PA'), tests.id('PB'), tests.id('X'), tests.id('Y'))), 0, 'lote: quatro fichas recentes fora do ar');
select tests.as_owner();
insert into tests.fx(key, txt) select 'IP_B', ip_hash from app.takedown_requests where entity_id = tests.id('X') and auto_hidden;
insert into tests.fx(key, txt) select 'EM_M4', email_hash from app.takedown_requests where entity_id = tests.id('Y') and auto_hidden;
insert into tests.fx(key, txt) select 'EM_M1', email_hash from app.takedown_requests where entity_id = tests.id('PA') and auto_hidden;
select ok(tests.txt('IP_B') ~ '^[0-9a-f]{64}$' and tests.txt('EM_M4') ~ '^[0-9a-f]{64}$' and tests.txt('EM_M1') ~ '^[0-9a-f]{64}$', 'hashes presentes nos pedidos');

-- visão agrupada (moderador): só domínio e hash
select tests.as_user(tests.id('MOD'));
insert into tests.fx(key, txt) select 'OVERVIEW', api.mod_takedown_overview(48)::text;
select tests.as_owner();
select ok((tests.txt('OVERVIEW')::jsonb)->'by_ip' @> jsonb_build_array(jsonb_build_object('ip_hash', tests.txt('IP_B'), 'requests', 2, 'hidden', 2)), 'visão: IP-B com 2 pedidos e 2 ocultações');
select ok((tests.txt('OVERVIEW')::jsonb)->'by_email' @> jsonb_build_array(jsonb_build_object('email_hash', tests.txt('EM_M1'), 'email_domain', 'exemplo.invalid', 'requests', 2, 'hidden', 2)),
          'visão: e-mail m1 com domínio e hash, 2 ocultações');
select ok(tests.txt('OVERVIEW') !~ '@', 'visão: nenhum e-mail em claro');
select is(((tests.txt('OVERVIEW')::jsonb)->'breaker'->>'limit_per_hour')::int, 15, 'visão: estado do disjuntor (limite por hora = 15)');
select is(((tests.txt('OVERVIEW')::jsonb)->'breaker'->>'limit_per_day')::int, 50, 'visão: limite por dia = 50');
select ok(((tests.txt('OVERVIEW')::jsonb)->'breaker'->>'contained_last_24h')::int >= 1 and (tests.txt('OVERVIEW')::jsonb)->'breaker'->>'last_containment_alert_at' is not null,
          'visão: pedidos contidos e data do último alerta');
select is(((tests.txt('OVERVIEW')::jsonb)->>'window_hours')::int, 48, 'visão: janela de 48 h por padrão');

-- tombstone: PB é confirmada pela moderação (arquivada) e não pode ser desfeita pelo lote
select tests.as_user(tests.id('MOD'));
select lives_ok(format('select api.mod_decide_takedown((select (x->>''id'')::uuid from jsonb_array_elements(api.mod_list(''takedowns'')) x where x->>''entity_id'' = %L and x->>''auto_hidden'' = ''true''), %L, %L)',
                tests.id('PB'), 'confirm', 'Retirada confirmada a pedido da iniciativa.'), 'moderação confirma a retirada de PB (arquivada)');

-- justificativa e janela inválidas
select throws_ok(format('select api.mod_restore_auto_hidden(now() - interval ''1 hour'', now(), null, null, %L)', 'curta'), '22023', null, 'lote: justificativa com menos de 10 caracteres → 22023');
select throws_ok($$ select api.mod_restore_auto_hidden(now() - interval '1 hour', now()) $$, '22023', null, 'lote: sem justificativa → 22023');
select throws_ok($$ select api.mod_restore_auto_hidden(now(), now() - interval '1 hour', null, null, 'Justificativa longa o bastante') $$, '22023', null, 'lote: janela invertida → 22023');
-- filtro por e-mail
select is(api.mod_restore_auto_hidden(now() - interval '1 hour', now() + interval '1 hour', null, tests.txt('EM_M4'), 'Pedido em massa do mesmo endereço.'), 1, 'lote por email_hash restaura 1 ficha (Y)');
select tests.as_anon();
select is((select count(*)::int from api.entity_list where id = tests.id('Y')), 1, 'Y voltou ao ar');
select is((select count(*)::int from api.entity_list where id = tests.id('X')), 0, 'X (outro e-mail) continua oculta');
-- filtro por IP
select tests.as_user(tests.id('MOD'));
select is(api.mod_restore_auto_hidden(now() - interval '1 hour', now() + interval '1 hour', tests.txt('IP_B'), null, 'Pedidos em massa do mesmo IP.'), 1, 'lote por ip_hash restaura o que sobrou do IP-B (X)');
select is((select count(*)::int from api.entity_list where id = tests.id('PA')), 0, 'PA (IP-A) continua oculta');
-- janela: só o passado distante
select is(api.mod_restore_auto_hidden(now() + interval '1 hour', now() + interval '2 hours', null, null, 'Janela no futuro, não deve achar nada.'), 0, 'lote com janela vazia restaura 0');
select is(api.mod_restore_auto_hidden(now() - interval '10 days', now() - interval '4 days', null, null, 'Janela dos pedidos antigos em massa.'), 8,
          'lote por janela restaura as 8 ocultações antigas');
select tests.as_anon();
select is((select count(*)::int from api.entity_list where id = tests.id('PA')), 0, 'a janela antiga não tocou nas fichas recentes (PA)');
select is((select count(*)::int from api.entity_list where id in (tests.id('T3'), tests.id('T2'), tests.id('T8'), tests.id('T12'), tests.id('DB'))), 5, 'fichas antigas voltaram ao ar');
select tests.as_user(tests.id('MOD'));
select is(api.mod_restore_auto_hidden(now() - interval '1 hour', now() + interval '1 hour', null, null, 'Desfazendo o que sobrou da janela recente.'), 1,
          'lote sem filtro restaura PA e não a arquivada (PB)');
select tests.as_anon();
select is((select count(*)::int from api.entity_list where id = tests.id('PB')), 0, 'PB arquivada continua fora do ar (confirmada, sem lote)');
select is((select count(*)::int from api.entity_list where id = tests.id('PA')), 1, 'PA voltou ao ar');
select tests.as_owner();
select is((select count(*)::int from app.audit_log where action = 'entity.restored_batch'), 11, 'auditoria: uma linha por ficha restaurada (1+1+0+8+1)');
select is((select count(*)::int from app.audit_log where action = 'takedown.batch_restored'), 5, 'auditoria: uma linha por lote concluído (inclui o lote vazio)');
select is((select count(*)::int from app.takedown_requests where status = 'restored' and decided_by = tests.id('MOD') and char_length(rationale) >= 10), 11,
          'pedidos marcados como restaurados, com justificativa');
select is((select count(*)::int from app.takedown_requests where auto_hidden and status = 'open'), 0, 'nenhum pedido automático ainda aberto (11 restaurados, PB confirmado)');
select is((select count(*)::int from app.entities where publication_state = 'hidden' and id in (select entity_id from app.takedown_requests where auto_hidden)), 0, 'nenhuma ficha ficou oculta sem pedido aberto');

-- ======================================================================
-- L. Permissões: anon e conta comum
-- ======================================================================
select tests.as_anon();
select throws_ok($$ select api.mod_takedown_overview() $$, '42501', null, 'anon: painel de retiradas negado');
select throws_ok($$ select api.mod_restore_auto_hidden(now() - interval '1 hour', now(), null, null, 'Justificativa suficiente.') $$, '42501', null, 'anon: lote negado');
select throws_ok($$ select app.mod_restore_auto_hidden(now() - interval '1 hour', now(), null, null, 'Justificativa suficiente.') $$, '42501', null, 'anon: função de app negada');
select throws_ok('select email from app.takedown_requests', '42501', null, 'anon: e-mail dos pedidos ilegível');
select throws_ok('select token_hash from app.takedown_tokens', '42501', null, 'anon: hash do token ilegível');
select throws_ok('select data from app.notification_secrets', '42501', null, 'anon: segredos de notificação ilegíveis');
select tests.as_user(tests.id('A'));
select throws_ok($$ select api.mod_takedown_overview() $$, 'P0002', null, 'conta comum: painel de retiradas responde "não encontrado"');
select throws_ok($$ select api.mod_restore_auto_hidden(now() - interval '1 hour', now(), null, null, 'Justificativa suficiente.') $$, 'P0002', null, 'conta comum: lote responde "não encontrado"');
select throws_ok('select email_hash from app.takedown_requests', '42501', null, 'conta comum: hash do e-mail ilegível');
select throws_ok('select ip_hash from app.takedown_requests', '42501', null, 'conta comum: hash do IP ilegível');
select tests.as_owner();
select is((select count(*)::int from information_schema.column_privileges where table_schema = 'app' and table_name in ('takedown_requests', 'takedown_tokens')
            and grantee in ('anon', 'authenticated', 'public')), 0, 'nenhum privilégio de coluna para anon/authenticated/public nas tabelas de retirada');
select ok(has_function_privilege('anon', 'api.confirm_takedown(text)', 'EXECUTE') and has_function_privilege('anon', 'api.request_takedown(uuid,text,text,text,text,text,text)', 'EXECUTE')
          and not has_function_privilege('anon', 'api.mod_restore_auto_hidden(timestamptz,timestamptz,text,text,text)', 'EXECUTE')
          and not has_function_privilege('anon', 'api.mod_takedown_overview(integer)', 'EXECUTE')
          and not has_function_privilege('authenticated', 'app._notify_mod_takedown(uuid,uuid)', 'EXECUTE'), 'matriz de EXECUTE da retirada');

select * from finish();
rollback;
