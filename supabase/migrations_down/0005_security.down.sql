-- 0005 DOWN — remove políticas, RLS e grants; depois as funções auxiliares
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname in ('app','pub') loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
  for r in select schemaname, tablename from pg_tables where schemaname in ('app','pub') loop
    execute format('alter table %I.%I disable row level security', r.schemaname, r.tablename);
    execute format('revoke all on %I.%I from anon, authenticated, service_role', r.schemaname, r.tablename);
  end loop;
end $$;
revoke all on all sequences in schema app from service_role;
revoke execute on function pub.norm(text) from anon, authenticated, service_role;
drop function if exists app.can_view_entity_private(uuid), app.curator_can(uuid), app.is_entity_creator(uuid),
  app.is_entity_manager(uuid), app.has_role(app.staff_role);
