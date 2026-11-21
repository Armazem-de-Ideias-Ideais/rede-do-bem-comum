-- =====================================================================
-- local_shim.sql  —  SOMENTE PARA AMBIENTE LOCAL / CI
-- Reproduz o mínimo do ambiente Supabase de que as migrações dependem:
--   * papéis anon, authenticated, service_role, authenticator
--   * schema auth com auth.users, auth.uid(), auth.role(), auth.jwt()
--   * schema extensions (onde o Supabase instala PostGIS, unaccent etc.)
-- NÃO aplicar em projeto Supabase: lá estes objetos já existem.
-- Idempotente: pode ser rodado várias vezes.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator noinherit login password null;
  end if;
end $$;

grant anon, authenticated, service_role to authenticator;

create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id         uuid primary key,
  email      text unique,
  created_at timestamptz not null default now()
);
revoke all on auth.users from anon, authenticated;

-- Mesma semântica do Supabase: lê o claim "sub" do JWT repassado pelo PostgREST.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

grant execute on function auth.uid(), auth.role(), auth.jwt() to anon, authenticated, service_role;

-- pgTAP fica no schema public localmente; os papéis precisam enxergá-lo nos testes.
grant usage on schema public to anon, authenticated, service_role;
