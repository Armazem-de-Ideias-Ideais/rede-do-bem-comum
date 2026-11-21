-- Fotografia determinística do esquema (somente teste): funções (definição + EXECUTE), colunas, restrições,
-- índices, configurações (sem o sal) e privilégios de tabela dos schemas app/api/pub. Usada para provar que
-- 0012 UP + 0012 DOWN devolve exatamente o estado do 0011.
select 'func ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) || ' ' || coalesce(p.proacl::text, '-')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('app','api','pub') and p.prokind = 'f'
union all
select 'col ' || table_schema || '.' || table_name || '.' || column_name || ' ' || data_type || ' ' || is_nullable || ' ' || coalesce(column_default, '-')
  from information_schema.columns where table_schema in ('app','api','pub')
union all
select 'con ' || conrelid::regclass::text || ' ' || conname || ' ' || pg_get_constraintdef(oid)
  from pg_constraint where connamespace in ('app'::regnamespace, 'api'::regnamespace, 'pub'::regnamespace)
union all
select 'idx ' || schemaname || '.' || indexname || ' ' || indexdef from pg_indexes where schemaname in ('app','api','pub')
union all
select 'set ' || key || '=' || case when key = 'ip_salt' then '(sal)' else value end from app.settings
union all
select 'tab ' || c.oid::regclass::text || ' ' || coalesce(c.relacl::text, '-') || ' rls=' || c.relrowsecurity
  from pg_class c where c.relnamespace in ('app'::regnamespace, 'api'::regnamespace, 'pub'::regnamespace) and c.relkind in ('r','v')
order by 1;
