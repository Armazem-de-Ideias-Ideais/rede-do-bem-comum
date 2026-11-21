-- Teste de aceite 1: visitante e conta A não leem dados privados de conta B
-- (tabela, view, função, "armazenamento"/fila e cache no nível do banco).
\ir _ids.psql
begin;
select plan(46);

-- ===== Visitante (anon) =====
select tests.as_anon();
select is((select count(*)::int from pg_tables t where t.schemaname = 'app'
            and has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'SELECT')), 0,
          'anon: nenhuma tabela de app tem SELECT');
select is((select count(*)::int from pg_tables t where t.schemaname = 'app'
            and (has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'INSERT')
              or has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'UPDATE')
              or has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'DELETE'))), 0,
          'anon: nenhuma tabela de app aceita escrita');
select throws_ok($$ select * from app.entities $$, '42501', null, 'anon: app.entities negado');
select throws_ok($$ select * from app.consent_records $$, '42501', null, 'anon: app.consent_records negado');
select throws_ok($$ select * from app.entity_versions $$, '42501', null, 'anon: app.entity_versions negado');
select throws_ok($$ select * from app.places $$, '42501', null, 'anon: app.places (coordenada privada) negado');
select throws_ok($$ select * from app.reports $$, '42501', null, 'anon: app.reports negado');
select throws_ok($$ select * from auth.users $$, '42501', null, 'anon: auth.users negado');
select throws_ok($$ select * from pub.export_set $$, '42501', null, 'anon: conjunto de exportação negado');
select throws_ok($$ select * from app.cache_invalidation_outbox $$, '42501', null, 'anon: fila de cache negada');
select throws_ok($$ select * from app.translation_tasks $$, '42501', null, 'anon: fila de tradução negada');
select is(api.entity_detail(:E9), null, 'anon: detalhe do rascunho de B é nulo');
select is((select count(*)::int from api.search_entities('Rascunho')), 0, 'anon: rascunhos fora da busca');
select is((select count(*)::int from api.entities where id in (:E9, :E10, :E12)), 0, 'anon: rascunhos fora da view pública');
select ok(not has_function_privilege('anon', 'app.import_source_record(uuid,text,text,text,char,app.entity_kind,app.presence_type,jsonb)', 'EXECUTE'),
          'anon: não executa importador');
select ok(not has_function_privilege('anon', 'app.publish_entity(uuid,text)', 'EXECUTE'), 'anon: não executa publicação');
select ok(not has_function_privilege('anon', 'api.export_institutional(integer,uuid)', 'EXECUTE'), 'anon: não executa exportação');

-- Nenhuma coluna privada existe na superfície pública (RLS não protege colunas)
select tests.as_owner();
select is((select count(*)::int from information_schema.columns
            where table_schema in ('api','pub')
              and column_name in ('geom_exact','address_private','email','account_id','created_by','author_id',
                                  'reporter_contact','reporter_account','export_permission','rights_basis','claimant_id',
                                  'consent_id','key_hash','payload','statement')), 0,
          'nenhuma coluna privada em api/pub');
select is((select count(*)::int from pg_views v join pg_class c on c.relname = v.viewname
             join pg_namespace n on n.oid = c.relnamespace and n.nspname = v.schemaname
            where v.schemaname = 'api'
              and not coalesce((select option_value = 'on' from pg_options_to_table(c.reloptions) where option_name = 'security_invoker'), false)), 0,
          'todas as views de api têm security_invoker=on');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'api' and p.prosecdef), 0, 'nenhuma função SECURITY DEFINER no schema exposto');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.prosecdef
              and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), 0,
          'toda função DEFINER em app fixa search_path');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('app','api') and has_function_privilege('public', p.oid, 'EXECUTE')), 0,
          'nenhuma função de app/api executável por PUBLIC');

-- ===== Conta A =====
select tests.as_user(:A);
select is((select count(*)::int from app.entities where id = :E9), 0, 'A: não vê entidade-rascunho de B');
select is((select count(*)::int from app.entity_versions where id = :VER_B), 0, 'A: não vê versão de B');
select is((select count(*)::int from app.entity_texts where entity_id = :E9), 0, 'A: não vê textos do rascunho de B');
select is((select count(*)::int from app.consent_records where account_id <> :A), 0, 'A: não vê autorizações alheias');
select is((select count(*)::int from app.entity_managers where account_id <> :A), 0, 'A: não vê gestores alheios');
select is((select count(*)::int from app.reports), 0, 'A: não vê relatos (nem o de B)');
select is((select count(*)::int from app.evidence), 0, 'A: não vê evidências');
select is((select count(*)::int from app.role_grants), 0, 'A: não vê papéis alheios');
select is((select count(*)::int from app.audit_log), 0, 'A: não vê auditoria');
select is((select count(*)::int from app.profiles where account_id <> :A), 0, 'A: não vê perfis privados alheios');
select is((select count(*)::int from app.places where id = :P2), 0, 'A: não vê coordenada privada de local alheio');
select throws_ok($$ select * from auth.users $$, '42501', null, 'A: auth.users negado');
select throws_ok($$ select * from app.cache_invalidation_outbox $$, '42501', null, 'A: fila de cache negada');
select is((select count(*)::int from app.entities where id = :E10), 1, 'A: vê o próprio rascunho');
select is((select count(*)::int from app.claims where claimant_id = :A), 1, 'A: vê a própria reivindicação');

-- ===== Conta B =====
select tests.as_user(:B);
select is((select count(*)::int from app.entity_versions where id = :VER_A), 0, 'B: não vê versão de A');
select is((select count(*)::int from app.claims), 0, 'B: não vê reivindicação de A');
select is((select count(*)::int from app.reports), 1, 'B: vê somente o próprio relato');

-- ===== Papéis internos com mandato =====
select tests.as_user(:CUR_XX);
select ok((select count(*) from app.evidence where entity_id = :E3) > 0, 'curador XX: vê evidência do seu mandato');
select is((select count(*)::int from app.evidence where entity_id = :E11), 0, 'curador XX: não vê evidência fora do mandato (XY)');
select is((select count(*)::int from app.consent_records), 0, 'curador: não lê autorizações de pessoas');

select tests.as_user(:MOD);
select is((select count(*)::int from app.reports), 2, 'moderador: vê relatos');
select is((select count(*)::int from app.evidence), 0, 'moderador: não lê evidências');

select tests.as_user(:GEST);
select is((select count(*)::int from app.evidence where entity_id = :E1), 0, 'gestor: não lê evidências de terceiros da própria ficha');

select tests.as_owner();
select * from finish();
rollback;
