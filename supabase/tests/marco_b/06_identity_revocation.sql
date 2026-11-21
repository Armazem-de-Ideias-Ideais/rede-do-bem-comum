-- Teste de aceite 6: revogar autorização de identidade remove a informação das superfícies
-- públicas e das filas derivadas. Também: nada pré-selecionado e autorização específica.
\ir _ids.psql
begin;
select plan(19);

select tests.as_anon();
select is((select political_identity from api.entities where id = :E1), array['[SINTÉTICO] autogestão'], 'antes: identidade institucional autodeclarada visível');
select is((select political_identity from api.profiles where pseudonym like '%Público%'), array['[SINTÉTICO] ecossocialismo'], 'antes: identidade do perfil visível');
select tests.as_owner();
select is((select count(*)::int from app.translation_tasks where field_name = 'political_identity'), 2, 'antes: 2 tarefas derivadas na fila');

-- Outra conta não revoga nem usa a autorização alheia
select tests.as_user(:A);
select throws_ok(format('select api.withdraw_consent(%L)', :CONS_E1_PI), 'P0002', null, 'A não revoga autorização de outra conta');
select throws_ok(format('select api.set_political_identity(array[%L], %L, %L)', 'x', :CONS_E1_PI, :E1), '42501', null,
                 'A não usa autorização alheia para declarar identidade');

-- Gestão de E1 revoga
select tests.as_user(:GEST);
select lives_ok(format('select api.withdraw_consent(%L)', :CONS_E1_PI), 'gestão revoga a autorização de identidade de E1');
select tests.as_anon();
select is((select political_identity from api.entities where id = :E1), null, 'depois: identidade some da view');
select is(api.entity_detail(:E1)->'political_identity', 'null'::jsonb, 'depois: identidade some do JSON de detalhe');
select tests.as_owner();
select is((select count(*)::int from app.translation_tasks where field_name = 'political_identity' and entity_id = :E1), 0, 'fila de tradução do campo esvaziada');
select is((select count(*)::int from app.cache_invalidation_outbox where entity_id = :E1 and reason = 'identity_withdrawn'), 1, 'invalidação de cache enfileirada');
select is((select status from app.political_identity_declarations where consent_id = :CONS_E1_PI), 'withdrawn', 'declaração marcada como retirada');

-- Pessoa revoga
select tests.as_user(:PPUB);
select lives_ok(format('select api.withdraw_consent(%L)', :CONS_P_PI), 'pessoa revoga identidade do perfil');
select tests.as_anon();
select is((select political_identity from api.profiles where pseudonym like '%Público%'), null, 'perfil sem identidade após revogação');
select tests.as_owner();
select is((select count(*)::int from app.translation_tasks where field_name = 'political_identity'), 0, 'nenhuma tarefa derivada restante');

-- Autorização revogada não pode ser reutilizada
select tests.as_user(:PPUB);
select throws_ok(format('select api.set_political_identity(array[%L], %L)', 'x', :CONS_P_PI), '42501', null, 'autorização revogada não vale');
-- Nunca pré-selecionado: decisão explícita obrigatória
select throws_ok($$ select api.grant_consent('political_identity_public', null, 'pi-2026-11') $$, '22023', null, 'consentimento sem decisão explícita é rejeitado');
select tests.as_owner();
select is((select column_default from information_schema.columns where table_schema = 'app' and table_name = 'consent_records'
            and column_name = 'decision'), null, 'coluna decision sem valor padrão');
-- Retirar apresentação pública remove o perfil inteiro
select tests.as_user(:PPUB);
select lives_ok(format('select api.withdraw_consent(%L)', :CONS_P_PP), 'pessoa retira apresentação pública');
select tests.as_anon();
select is((select public_profiles::int from api.public_counters), 0, 'perfil sai da view e do contador');
select tests.as_owner();
select * from finish();
rollback;
