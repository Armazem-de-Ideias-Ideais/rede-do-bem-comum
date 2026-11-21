-- Marco C, teste 10: visitante (anon) e conta comum não leem nada privado; superfície exposta sem campos internos.
begin;
select plan(30);

select tests.as_owner();
-- introspecção (como owner)
select is((select count(*)::int from pg_tables t where t.schemaname = 'app'
            and (has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'SELECT')
              or has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'INSERT')
              or has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'UPDATE')
              or has_table_privilege('anon', format('%I.%I', t.schemaname, t.tablename), 'DELETE'))), 0,
          'anon: nenhum privilégio em tabela de app (inclui as novas do Marco C)');
select is((select count(*)::int from unnest(array['takedown_requests','connect_requests','contact_messages','suggestions',
            'invite_candidates','invitations','notification_outbox','notification_secrets','shared_domains','entity_slug_history']) t
            where has_table_privilege('authenticated', format('app.%I', t), 'SELECT')), 0,
          'authenticated: nenhuma leitura direta das tabelas novas (só por função verificada)');
select is((select count(*)::int from pg_tables where schemaname = 'app' and not rowsecurity), 0, 'RLS ligada em 100% das tabelas de app');
select is((select count(*)::int from information_schema.columns where table_schema in ('api','pub')
            and column_name in ('research_id','research_notes','lot','exposure','audit','email','sender_email','contact',
                                'from_contact','to_contact','token_hash','ip_hash','verify_email','code_hash','account_id',
                                'claimant_id','statement','payload','reason','body_private')), 0,
          'nenhuma coluna interna ou privada em api/pub');
select is((select count(*)::int from information_schema.columns where table_schema = 'app'
            and column_name in ('research_notes','lot','exposure','audit')), 0,
          'campos internos da pesquisa nem existem no banco');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'api' and p.prosecdef), 0, 'nenhuma função SECURITY DEFINER em api');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('app','api') and has_function_privilege('public', p.oid, 'EXECUTE')), 0,
          'nenhuma função de app/api executável por PUBLIC');
select is((select count(*)::int from pg_views v join pg_class c on c.relname = v.viewname
             join pg_namespace n on n.oid = c.relnamespace and n.nspname = v.schemaname
            where v.schemaname = 'api'
              and not coalesce((select option_value = 'on' from pg_options_to_table(c.reloptions) where option_name = 'security_invoker'), false)), 0,
          'todas as views de api com security_invoker');
select set_eq($$ select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'app' and has_function_privilege('anon', p.oid, 'EXECUTE') and p.proname !~ '^_' $$,
              $$ values ('request_takedown'),('report'),('suggest_initiative'),('send_contact_message'),('invite_preview'),
                        ('invite_decline'),('submit_report') $$,
              'anon executa somente as funções públicas previstas em app');
select ok(not has_function_privilege('authenticated', 'api.notification_claim(bigint)', 'EXECUTE')
          and not has_function_privilege('anon', 'api.notification_claim(bigint)', 'EXECUTE')
          and has_function_privilege('service_role', 'api.notification_claim(bigint)', 'EXECUTE'),
          'fila de e-mail só para service_role');
select ok(not has_function_privilege('anon', 'app.seed_load_record(jsonb)', 'EXECUTE')
          and not has_function_privilege('authenticated', 'app.seed_load_candidate(jsonb)', 'EXECUTE'),
          'carga de dados só pelo servidor');
select ok(not has_function_privilege('anon', 'app._account_email(uuid)', 'EXECUTE')
          and not has_function_privilege('authenticated', 'app._account_email(uuid)', 'EXECUTE'),
          'ninguém lê e-mail de conta por função direta');

-- anon: leituras diretas negadas
select tests.as_anon();
select throws_ok('select count(*) from app.invite_candidates', '42501', null, 'anon: candidatos a convite negados');
select throws_ok('select count(*) from app.contact_messages', '42501', null, 'anon: mensagens de contato negadas');
select throws_ok('select count(*) from app.connect_requests', '42501', null, 'anon: pedidos de conexão negados');
select throws_ok('select count(*) from app.takedown_requests', '42501', null, 'anon: pedidos de retirada negados');
select throws_ok('select count(*) from app.notification_secrets', '42501', null, 'anon: segredos de notificação negados');
select throws_ok('select api.mod_list(''claims'')', '42501', null, 'anon: painel do moderador negado');
select throws_ok('select * from api.my_connections()', '42501', null, 'anon: conexões exigem conta');
select throws_ok('select api.notification_claim(1)', '42501', null, 'anon: fila de e-mail negada');
select throws_ok('select api.invite_preview(repeat(''a'', 64))', 'P0002', null, 'anon: token inventado não revela nada');
select is((select count(*)::int from api.entity_list where search_text ~ 'rbc-c[0-9]'), 0, 'anon: código de pesquisa não aparece');
select is((select count(*)::int from api.entity_list), (select entities_total::int from api.public_stats),
          'lista e contador concordam');
select is((select count(*)::int from api.entity_list where lon is not null and location_precision <> 'city'), 0,
          'ponto no mapa só com precisão de cidade');

-- conta comum
select tests.as_user(tests.id('A'));
select throws_ok('select count(*) from app.invite_candidates', '42501', null, 'conta: candidatos a convite negados');
select throws_ok('select count(*) from app.contact_messages', '42501', null, 'conta: mensagens de contato negadas');
select throws_ok('select code_hash from app.claims', '42501', null, 'conta: hash de código de reivindicação ilegível');
select throws_ok('select api.mod_list(''takedowns'')', 'P0002', null, 'conta sem papel: painel responde "não encontrado"');
select throws_ok('select api.mod_create_invite(gen_random_uuid())', 'P0002', null, 'conta sem papel: não cria convite');
select is(jsonb_array_length(api.my_account()->'managed'), 0, 'conta nova é privada e não gere nada');

select tests.as_owner();
select * from finish();
rollback;
