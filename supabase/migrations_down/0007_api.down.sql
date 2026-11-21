-- 0007 DOWN — o schema api contém somente objetos desta migração
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'api' loop
    execute format('drop function %s', r.sig);
  end loop;
  for r in select viewname from pg_views where schemaname = 'api' loop
    execute format('drop view api.%I', r.viewname);
  end loop;
end $$;
