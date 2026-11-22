-- 0014 — Prazos de guarda aprovados em 22/11/2026 (política de privacidade, seção 6).
-- Complementa app.purge_expired() (limpezas de curto prazo). Roda todo dia pelo pg_cron.
--   * pedidos de retirada resolvidos, mensagens do formulário, relatos, sugestões e pedidos de conexão
--     encerrados: apagados 12 meses depois de resolvidos (o registro mínimo de retirada fica em
--     app.suppression_tombstones, que não é tocado);
--   * registros de consentimento: apagados 5 anos depois da revogação.

create or replace function app.purge_retention() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  n_takedown int; n_contact int; n_reports int; n_suggestions int; n_connect int; n_consent int;
begin
  delete from app.takedown_requests
   where status not in ('open', 'awaiting_confirmation')
     and coalesce(decided_at, hidden_at, confirmed_at, created_at) < now() - interval '12 months';
  get diagnostics n_takedown = row_count;

  delete from app.contact_messages where created_at < now() - interval '12 months';
  get diagnostics n_contact = row_count;

  delete from app.reports where handled_at is not null and handled_at < now() - interval '12 months';
  get diagnostics n_reports = row_count;

  delete from app.suggestions where handled_at is not null and handled_at < now() - interval '12 months';
  get diagnostics n_suggestions = row_count;

  delete from app.connect_requests
   where status not in ('pending', 'blocked')
     and coalesce(decided_at, expires_at, created_at) < now() - interval '12 months';
  get diagnostics n_connect = row_count;

  delete from app.consent_records where withdrawn_at is not null and withdrawn_at < now() - interval '5 years';
  get diagnostics n_consent = row_count;

  return jsonb_build_object('takedown_requests', n_takedown, 'contact_messages', n_contact, 'reports', n_reports,
                            'suggestions', n_suggestions, 'connect_requests', n_connect, 'consent_records', n_consent);
end $$;
revoke all on function app.purge_retention() from public, anon, authenticated;

select cron.schedule('rbc-retention', '47 3 * * *', $c$ select app.purge_retention() $c$);
