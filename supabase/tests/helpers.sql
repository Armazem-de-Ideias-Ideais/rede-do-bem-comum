-- helpers.sql — utilitários de teste (somente ambiente local/CI; nunca em produção)
create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Troca o papel efetivo E o JWT simulado, como faria o PostgREST.
create or replace function tests.as_anon() returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  return '# papel: anon (visitante)';
end $$;

create or replace function tests.as_user(p_sub uuid, p_role text default 'authenticated',
  p_extra jsonb default '{}'::jsonb) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    (jsonb_build_object('sub', p_sub, 'role', p_role) || p_extra)::text, true);
  perform set_config('role', p_role, true);
  return '# papel: ' || p_role || ' sub=' || right(p_sub::text, 12);
end $$;

create or replace function tests.as_service() returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('role', 'service_role', true);
  return '# papel: service_role (servidor)';
end $$;

create or replace function tests.as_owner() returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'none', true);
  return '# papel: owner das migrações';
end $$;

-- Mede uma consulta N vezes no papel CORRENTE; devolve mediana, p95 e linhas.
create or replace function tests.time_query(p_sql text, p_runs integer default 20)
returns table (median_ms numeric, p95_ms numeric, max_ms numeric, row_count bigint)
language plpgsql as $$
declare t0 timestamptz; v_ms numeric[] := '{}'; v_rows bigint; i integer;
begin
  for i in 1..p_runs loop
    t0 := clock_timestamp();
    -- count(s::text) força avaliar todas as colunas (evita que o planejador descarte subconsultas)
    execute 'select count(s::text) from (' || p_sql || ') s' into v_rows;
    v_ms := v_ms || (extract(epoch from clock_timestamp() - t0) * 1000)::numeric;
  end loop;
  return query select round(percentile_cont(0.5) within group (order by x)::numeric, 2),
                      round(percentile_cont(0.95) within group (order by x)::numeric, 2),
                      round(max(x), 2), v_rows
                 from unnest(v_ms) x;
end $$;

-- Executa DML no papel corrente e devolve o número de linhas afetadas.
create or replace function tests.rows_affected(p_sql text) returns integer language plpgsql as $$
declare n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

-- Linhas de EXPLAIN (ANALYZE) para inspecionar planos.
create or replace function tests.explain_lines(p_sql text) returns setof text language plpgsql as $$
declare l text;
begin
  for l in execute 'explain (analyze, buffers off, costs off) ' || p_sql loop return next l; end loop;
end $$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
