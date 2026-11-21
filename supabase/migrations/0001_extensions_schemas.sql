-- 0001 UP — extensões e schemas
-- app  : estruturas PRIVADAS (nunca listado em "Exposed schemas" do Supabase)
-- pub  : PROJEÇÃO PÚBLICA materializada, só colunas publicáveis (não exposto; lido via api)
-- api  : ÚNICA superfície exposta ao Data API (views security_invoker + funções)
create extension if not exists postgis  with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

create schema app;
create schema pub;
create schema api;

revoke all on schema app, pub, api from public;
-- usage em app é necessário para avaliar políticas RLS/funções auxiliares;
-- sem GRANT em tabela, nada é legível (ver 0005).
grant usage on schema app to authenticated, service_role, anon;
grant usage on schema pub to anon, authenticated, service_role;
grant usage on schema api to anon, authenticated, service_role;

-- Nenhum objeto novo nestes schemas nasce executável/legível por PUBLIC/anon/authenticated.
alter default privileges in schema app, pub, api revoke execute on functions from public;
alter default privileges in schema app, pub, api revoke all on tables from public, anon, authenticated;
alter default privileges in schema app, pub, api revoke all on sequences from public, anon, authenticated;
