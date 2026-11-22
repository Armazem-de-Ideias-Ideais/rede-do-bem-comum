-- 0013 — Ligação banco → Edge Function "notify" (webhook por linha, drenagem periódica e limpeza diária).
-- Nenhum segredo neste arquivo: o segredo do webhook é gerado dentro do banco e guardado no Vault.
-- Depois de aplicar, copie o valor do Vault (Integrations → Vault → notify_webhook_secret) para o
-- segredo NOTIFY_WEBHOOK_SECRET da função. Sem esse segredo na função, as chamadas recebem 401 e
-- os e-mails ficam na fila (nada se perde).
-- Projeto: wjrvygacpdrnqstsqjmv (troque a URL abaixo se o projeto mudar).

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'notify_webhook_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'notify_webhook_secret',
                                'Rede do Bem Comum: segredo do webhook da função notify');
  end if;
end $$;

create or replace function app._notify_call(p_body jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'notify_webhook_secret';
  if v_secret is null then return null; end if;
  return net.http_post(
    url := 'https://wjrvygacpdrnqstsqjmv.supabase.co/functions/v1/notify',
    body := p_body,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    timeout_milliseconds := 5000);
end $$;
revoke all on function app._notify_call(jsonb) from public, anon, authenticated;

create or replace function app._notify_outbox_trigger() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- pg_net enfileira a chamada dentro da transação: se ela for desfeita, nada é enviado.
  perform app._notify_call(jsonb_build_object('type', 'INSERT', 'schema', 'app', 'table', 'notification_outbox',
                                              'record', jsonb_build_object('id', new.id)));
  return new;
end $$;
revoke all on function app._notify_outbox_trigger() from public, anon, authenticated;

drop trigger if exists notify_outbox_webhook on app.notification_outbox;
create trigger notify_outbox_webhook after insert on app.notification_outbox
  for each row execute function app._notify_outbox_trigger();

-- Rede de segurança: a cada 10 min drena o que tiver ficado na fila; limpeza diária às 03:17 UTC.
select cron.schedule('rbc-notify-drain', '*/10 * * * *', $c$ select app._notify_call('{"drain": true}'::jsonb) $c$);
select cron.schedule('rbc-purge', '17 3 * * *', $c$ select app.purge_expired() $c$);
