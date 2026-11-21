-- 0005 UP — funções auxiliares de autorização, RLS e GRANTs
-- Princípios:
--  * app nunca é exposto no Data API; mesmo assim cada tabela tem RLS + GRANT mínimo,
--    porque "não exposto" não é controle de acesso (defesa em profundidade).
--  * Funções SECURITY DEFINER: search_path = '' e nomes qualificados; EXECUTE revogado de PUBLIC.
--  * Papéis internos vêm de app.role_grants, NUNCA do JWT enviado pelo cliente.

create function app.has_role(p_role app.staff_role) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from app.role_grants g
                 where g.account_id = auth.uid() and g.role = p_role and g.revoked_at is null)
$$;

create function app.is_entity_manager(p_entity uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from app.entity_managers m
                 where m.entity_id = p_entity and m.account_id = auth.uid() and m.status = 'active')
$$;

create function app.is_entity_creator(p_entity uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from app.entities e where e.id = p_entity and e.created_by = auth.uid())
$$;

-- Mandato de curadoria: país e/ou categoria (nulo = global).
create function app.curator_can(p_entity uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app.role_grants g join app.entities e on e.id = p_entity
     where g.account_id = auth.uid() and g.role = 'curator' and g.revoked_at is null
       and (g.scope_country is null or g.scope_country = e.country_code)
       and (g.scope_category is null or exists (select 1 from app.entity_categories c
                                                where c.entity_id = e.id and c.category_id = g.scope_category)))
$$;

create function app.can_view_entity_private(p_entity uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.is_entity_manager(p_entity) or app.is_entity_creator(p_entity)
      or app.curator_can(p_entity) or app.has_role('moderator')
$$;

revoke all on function app.has_role(app.staff_role), app.is_entity_manager(uuid), app.is_entity_creator(uuid),
  app.curator_can(uuid), app.can_view_entity_private(uuid) from public;
grant execute on function app.has_role(app.staff_role), app.is_entity_manager(uuid), app.is_entity_creator(uuid),
  app.curator_can(uuid), app.can_view_entity_private(uuid) to authenticated, service_role;

-- ---------- RLS em TODAS as tabelas de app e pub ----------
do $$
declare r record;
begin
  for r in select schemaname, tablename from pg_tables where schemaname in ('app','pub') loop
    execute format('alter table %I.%I enable row level security', r.schemaname, r.tablename);
  end loop;
end $$;

-- service_role (somente servidor): acesso operacional; BYPASSRLS no Supabase.
grant select, insert, update, delete on all tables in schema app to service_role;
grant select, insert, update, delete on all tables in schema pub to service_role;
grant usage, select on all sequences in schema app to service_role;

-- ---------- pub: leitura pública, sem escrita ----------
grant select on pub.categories, pub.practices, pub.areas, pub.entities, pub.entity_texts,
  pub.entity_categories, pub.entity_practices, pub.places, pub.entity_places, pub.relationships,
  pub.profiles, pub.offers_needs, pub.entity_aliases, pub.entity_sources to anon, authenticated;
grant select on pub.export_set to authenticated;
grant execute on function pub.norm(text) to anon, authenticated, service_role;

do $$
declare t text;
begin
  foreach t in array array['categories','practices','areas','entities','entity_texts','entity_categories',
    'entity_practices','places','entity_places','relationships','profiles','offers_needs','entity_aliases','entity_sources'] loop
    execute format('create policy public_read on pub.%I for select to anon, authenticated using (true)', t);
  end loop;
end $$;
create policy export_read on pub.export_set for select to authenticated using (true);

-- ---------- app: somente authenticated, linha a linha ----------
grant select on app.accounts to authenticated;
grant update (locale) on app.accounts to authenticated;
create policy own_select on app.accounts for select to authenticated using (id = (select auth.uid()));
create policy own_update on app.accounts for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

grant select on app.profiles to authenticated;
grant insert (account_id, pseudonym, bio, area_id, precision) on app.profiles to authenticated;
grant update (pseudonym, bio, area_id, precision) on app.profiles to authenticated;
create policy own_select on app.profiles for select to authenticated using (account_id = (select auth.uid()));
create policy own_insert on app.profiles for insert to authenticated with check (account_id = (select auth.uid()));
create policy own_update on app.profiles for update to authenticated
  using (account_id = (select auth.uid())) with check (account_id = (select auth.uid()));

grant select on app.consent_records to authenticated;
create policy own_select on app.consent_records for select to authenticated using (account_id = (select auth.uid()));

grant select on app.political_identity_declarations to authenticated;
create policy own_select on app.political_identity_declarations for select to authenticated
  using (exists (select 1 from app.consent_records c where c.id = consent_id and c.account_id = (select auth.uid())));

grant select on app.role_grants to authenticated;
create policy own_or_admin on app.role_grants for select to authenticated
  using (account_id = (select auth.uid()) or (select app.has_role('admin')));

grant select on app.audit_log to authenticated;
create policy admin_only on app.audit_log for select to authenticated using ((select app.has_role('admin')));

grant select on app.entities to authenticated;
create policy scoped_select on app.entities for select to authenticated using (app.can_view_entity_private(id));

grant select on app.entity_texts, app.entity_categories, app.entity_practices, app.offers_needs to authenticated;
create policy scoped_select on app.entity_texts for select to authenticated using (app.can_view_entity_private(entity_id));
create policy scoped_select on app.entity_categories for select to authenticated using (app.can_view_entity_private(entity_id));
create policy scoped_select on app.entity_practices for select to authenticated using (app.can_view_entity_private(entity_id));
create policy scoped_select on app.offers_needs for select to authenticated using (app.can_view_entity_private(entity_id));

grant select on app.entity_places to authenticated;
create policy scoped_select on app.entity_places for select to authenticated using (app.can_view_entity_private(entity_id));
grant select on app.places to authenticated;
create policy scoped_select on app.places for select to authenticated using (
  exists (select 1 from app.entity_places ep where ep.place_id = id and app.can_view_entity_private(ep.entity_id)));

grant select on app.entity_relationships to authenticated;
create policy scoped_select on app.entity_relationships for select to authenticated
  using (app.can_view_entity_private(from_entity) or app.can_view_entity_private(to_entity));

-- Gestores: cada conta vê apenas os próprios vínculos (reivindicação não revela gestores).
grant select on app.entity_managers to authenticated;
create policy own_select on app.entity_managers for select to authenticated using (account_id = (select auth.uid()));

-- Versões: autor, gestores ativos e curadoria do mandato. Edição direta só do próprio rascunho.
grant select on app.entity_versions to authenticated;
grant update (payload) on app.entity_versions to authenticated;
create policy scoped_select on app.entity_versions for select to authenticated using (
  author_id = (select auth.uid()) or app.is_entity_manager(entity_id) or app.curator_can(entity_id));
create policy own_draft_update on app.entity_versions for update to authenticated
  using (author_id = (select auth.uid()) and status = 'draft')
  with check (author_id = (select auth.uid()) and status = 'draft');

grant select on app.reviews to authenticated;
create policy scoped_select on app.reviews for select to authenticated
  using (app.curator_can(entity_id) or app.is_entity_manager(entity_id));

grant select on app.claims to authenticated;
create policy scoped_select on app.claims for select to authenticated
  using (claimant_id = (select auth.uid()) or app.curator_can(entity_id));

-- Evidências: curadoria do mandato ou quem a registrou. Gestores não leem evidências de terceiros.
grant select on app.evidence to authenticated;
create policy scoped_select on app.evidence for select to authenticated
  using (app.curator_can(entity_id) or created_by = (select auth.uid()));

grant select on app.sources to authenticated;
create policy curator_select on app.sources for select to authenticated using ((select app.has_role('curator')));
grant select on app.source_records, app.field_provenance to authenticated;
create policy curator_select on app.source_records for select to authenticated
  using (entity_id is not null and app.curator_can(entity_id));
create policy curator_select on app.field_provenance for select to authenticated using (app.curator_can(entity_id));

-- Relatos: quem relatou vê o próprio; moderação vê todos.
grant select on app.reports to authenticated;
create policy own_or_moderator on app.reports for select to authenticated
  using (reporter_account = (select auth.uid()) or (select app.has_role('moderator')));

-- Sem GRANT para authenticated/anon (somente funções internas e service_role):
--   app.settings, app.entity_aliases, app.suppression_tombstones, app.rate_limits,
--   app.cache_invalidation_outbox, app.translation_tasks.
