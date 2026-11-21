-- Teste de aceite 2: conta A não edita ficha B trocando identificador, corpo ou papel no cliente.
-- Inclui RBC-013: edição pendente preserva a publicada, congelamento e detecção de conflito.
\ir _ids.psql
begin;
select plan(33);

select tests.as_user(:A);
select throws_ok(format('select api.update_draft(%L, %L::jsonb, 1)', :VER_B, '{"name":"tomada"}'),
                 'P0002', null, 'A: update_draft com id da versão de B → não encontrado');
select is(tests.rows_affected(format('update app.entity_versions set payload = %L where id = %L', '{"name":"tomada"}', :VER_B)), 0, 'A: UPDATE direto na versão de B afeta 0 linhas (RLS)');
select throws_ok(format('update app.entity_versions set status = %L where id = %L', 'approved', :VER_A),
                 '42501', null, 'A: não altera status da própria versão (privilégio de coluna)');
select throws_ok(format('update app.entity_versions set author_id = %L where id = %L', :B, :VER_A),
                 '42501', null, 'A: não troca autor da versão');
select throws_ok(format('update app.entities set original_name = %L where id = %L', 'x', :E9),
                 '42501', null, 'A: UPDATE direto em entidade de B negado');
select throws_ok($$ insert into app.entities(kind, presence_type, original_name) values ('collective','physical','burla') $$,
                 '42501', null, 'A: INSERT direto em entidades negado');
select throws_ok(format('insert into app.role_grants(account_id, role) values (%L, %L)', :A, 'curator'),
                 '42501', null, 'A: não se autoatribui papel por INSERT');
select throws_ok(format('select api.grant_role(%L, %L)', :A, 'curator'), '42501', null, 'A: não se autoatribui papel por RPC');
select throws_ok($$ insert into pub.entities(id, kind, presence_type, counter_class, name, name_lang, name_norm,
                    verification_label, is_synthetic, search_doc) values (gen_random_uuid(),'collective','physical','initiative',
                    'x','pt','x','found',true,''::tsvector) $$, '42501', null, 'A: não escreve na projeção pública');
select throws_ok(format('select api.propose_edit(%L, %L::jsonb)', :E1, '{"name":"sequestro"}'),
                 'P0002', null, 'A: não propõe edição em ficha que não gere');
select throws_ok(format('select api.hide_entity(%L, %L)', :E1, 'burla'), 'P0002', null, 'A: não oculta ficha alheia');
select throws_ok(format('select api.withdraw_entity(%L, %L)', :E1, 'burla'), 'P0002', null, 'A: não retira ficha alheia');
select throws_ok(format('select api.update_draft(%L, %L::jsonb, 1)', :VER_A, '{"publication_state":"published"}'),
                 '22023', null, 'A: campo não permitido no corpo é rejeitado');

-- Papel forjado no JWT do cliente não concede nada (papéis vêm de app.role_grants)
select tests.as_user(:A, 'authenticated', '{"app_role":"curator","user_role":"admin","is_admin":true}');
select is(app.has_role('curator'), false, 'A com JWT forjado: has_role(curator) = false');
select throws_ok(format('select api.publish_entity(%L, %L)', :E10, 'autopublicação forjada'),
                 'P0002', null, 'A com JWT forjado: não publica o próprio rascunho');
select throws_ok(format('select api.review_version(%L, %L, %L, %L)', :VER_A, 'approve', 'source', 'aprovação forjada'),
                 'P0002', null, 'A com JWT forjado: não revisa a própria versão');

-- Curador não aprova o próprio cadastro
select tests.as_user(:CUR_XX);
select lives_ok($$ select api.create_entity_draft('collective','physical','[SINTÉTICO] Ficha do curador','pt','{"country_code":"XX"}') $$,
                'curador cria rascunho próprio');
select lives_ok($$ select api.submit_version((select id from app.entity_versions where author_id = auth.uid() order by created_at desc limit 1)) $$,
                'curador submete rascunho próprio');
select throws_ok($$ select api.review_version((select id from app.entity_versions where author_id = auth.uid() order by created_at desc limit 1),
                    'approve','source','tentativa de autoaprovação') $$, '42501', null, 'curador não aprova o próprio cadastro');

-- Admin não se autoatribui papel
select tests.as_user(:ADM);
select throws_ok(format('select api.grant_role(%L, %L)', :ADM, 'curator'), '42501', null, 'admin não se autoatribui papel');

-- ===== Versões: pendente preserva publicada; congelamento; conflito =====
select tests.as_user(:GEST);
select lives_ok(format('select api.propose_edit(%L, %L::jsonb)', :E1, '{"name":"[SINTÉTICO] Centro Social Aurora — v2"}'), 'gestor propõe v2');
select lives_ok(format('select api.propose_edit(%L, %L::jsonb)', :E1, '{"name":"[SINTÉTICO] Centro Social Aurora — v3"}'), 'gestor propõe v3 sobre a mesma base');
select lives_ok($$ select api.submit_version(id) from app.entity_versions where author_id = auth.uid() and status = 'draft' $$,
                'gestor submete v2 e v3');
select throws_ok($$ select api.update_draft((select id from app.entity_versions where author_id = auth.uid() order by version_no limit 1),
                    '{"name":"mudança tardia"}', 1) $$, 'P0001', null, 'versão submetida está congelada');
select tests.as_anon();
select is((select name from api.entities where id = :E1), '[SINTÉTICO] Centro Social Aurora', 'publicada inalterada enquanto proposta pende');
select tests.as_user(:CUR_XY);
select throws_ok($$ select api.review_version((select id from app.entity_versions where version_no = 1
                     and entity_id = '00000000-0000-4000-e000-000000000001'), 'approve','source','fora do mandato') $$,
                 'P0002', null, 'curador XY não revisa ficha XX');
select tests.as_user(:CUR_XX);
select is(api.review_version((select id from app.entity_versions where entity_id = :E1 order by version_no limit 1),
                             'approve', 'representation', 'Representação confirmada (fictícia).'), 'approved', 'curador aprova v2');
select is(api.review_version((select id from app.entity_versions where entity_id = :E1 order by version_no desc limit 1),
                             'approve', 'representation', 'Tentativa sobre base antiga (fictícia).'), 'conflict', 'v3 sobre base antiga → conflito detectado');
select tests.as_anon();
select is((select name from api.entities where id = :E1), '[SINTÉTICO] Centro Social Aurora — v2', 'após aprovação, pública reflete v2');

-- Concorrência otimista em rascunho
select tests.as_user(:A);
select is(api.update_draft(:VER_A, '{"name":"[SINTÉTICO] Rascunho A editado"}', 1), 2, 'A edita o próprio rascunho (row_version 1→2)');
select throws_ok(format('select api.update_draft(%L, %L::jsonb, 1)', :VER_A, '{"name":"edição obsoleta"}'),
                 '40001', null, 'edição com row_version obsoleto → conflito');
-- Trigger de congelamento vale até para o owner
select tests.as_owner();
select throws_ok($$ update app.entity_versions set payload = '{"name":"owner"}'
                    where entity_id = '00000000-0000-4000-e000-000000000001' and status = 'approved' $$,
                 'P0001', null, 'payload aprovado é imutável mesmo para o owner');
select is((select count(*)::int from app.audit_log where action = 'version.reviewed'), 2, 'revisões auditadas');

select * from finish();
rollback;
