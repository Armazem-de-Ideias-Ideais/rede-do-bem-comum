-- Marco C, teste 16: fila de e-mail (service_role), formulário de contato, indicação, relato,
-- edição pelo gestor (direta x revisão), slug antigo redireciona, iniciativas-irmãs.
begin;
select plan(37);

-- formulário de contato (sem login)
select tests.as_anon();
select tests.ip('198.51.100.20');
select throws_ok(format('select api.send_contact_message(%L, %L, %L, %L)', 'Ana', 'sem-arroba', 'Assunto', 'Mensagem longa o bastante'),
                 '22023', null, 'contato: e-mail inválido → 22023');
select ok(api.send_contact_message('Ana', 'ana@example.org', 'Dúvida', 'Como faço para corrigir uma ficha?', 'pt', 'preenchido') is not null,
          'contato: honeypot responde sucesso');
insert into tests.fx(key, id) select 'MSG', api.send_contact_message('Ana', 'Ana@Example.org', 'Dúvida', 'Como faço para corrigir uma ficha?');
select lives_ok($$ select api.send_contact_message('Ana', 'ana@example.org', 'Outra', 'Segunda mensagem de teste.') from generate_series(1, 2) $$,
                'contato: até 3 por hora por IP');
select throws_ok($$ select api.send_contact_message('Ana', 'ana@example.org', 'Outra', 'Quarta mensagem de teste.') $$, '54000', null,
                 'contato: 4ª na hora → 54000');
select tests.as_owner();
select is((select count(*)::int from app.contact_messages), 3, 'contato: honeypot não gravou; 3 mensagens reais');
select is((select sender_email from app.contact_messages where id = tests.id('MSG')), 'ana@example.org', 'contato: e-mail normalizado e privado');
select is((select count(*)::int from app.notification_outbox where kind = 'contact_message' and to_moderator), 3, 'contato: moderador notificado');

-- fila de e-mail: só service_role; contexto sem o e-mail do moderador; reserva idempotente
insert into tests.fx(key, txt) select 'NID', id::text from app.notification_outbox where ref_id = tests.id('MSG');
select tests.as_user(tests.id('A'));
select throws_ok(format('select api.notification_claim(%s)', tests.txt('NID')), '42501', null, 'conta comum não consome a fila');
select tests.as_service();
select ok(tests.txt('NID')::bigint in (select * from api.notification_pending(200)), 'service_role lista pendentes');
insert into tests.fx(key, txt) select 'CTX', api.notification_claim(tests.txt('NID')::bigint)::text;
select is((tests.txt('CTX')::jsonb)->'to'->>'type', 'moderator', 'destino "moderator" (endereço só na Edge Function)');
select is((tests.txt('CTX')::jsonb)->'to'->>'email', null, 'contexto não contém e-mail do moderador');
select is((tests.txt('CTX')::jsonb)->'data'->>'reply_to', 'ana@example.org', 'contexto traz o responder-para do remetente');
select is(api.notification_claim(tests.txt('NID')::bigint), null, 'segunda reserva imediata devolve null (sem envio duplo)');
select lives_ok(format('select api.notification_done(%s, true)', tests.txt('NID')), 'marcar como enviado');
select ok(tests.txt('NID')::bigint not in (select * from api.notification_pending(200)), 'enviado sai da fila');

-- indicação de iniciativa (fila editorial, nunca publica)
select tests.as_anon();
select tests.ip('198.51.100.21');
select throws_ok($$ select api.suggest_initiative('Horta X', null, 'BR', 'Recife', array['familia_inexistente'], 'Descrição suficiente da horta.') $$,
                 '22023', null, 'indicação: família inválida → 22023');
insert into tests.fx(key, id) select 'SUG', api.suggest_initiative('Horta Comunitária Teste', 'https://horta.example.org', 'br', 'Recife',
  array['agroecology'], 'Horta comunitária com mutirões aos sábados.', 'Vi no bairro.', null, 'pt', null);
select is((select count(*)::int from api.entity_list where name = 'Horta Comunitária Teste'), 0, 'indicação não publica direto');
select tests.as_user(tests.id('MOD'));
select is((select count(*)::int from jsonb_array_elements(api.mod_list('suggestions')) x where (x->>'id')::uuid = tests.id('SUG')
            and x->>'country_code' = 'BR'), 1, 'indicação na fila do moderador');
select lives_ok(format('select api.mod_decide_suggestion(%L, %L, %L)', tests.id('SUG'), 'accepted', 'Vai para pesquisa.'), 'moderador decide indicação');

-- relato de correção
select tests.as_anon();
select ok(api.report('correction', tests.id('E1'), 'O site mudou de endereço.', null, null) is not null, 'relato de correção aceito sem login');
select throws_ok($$ select api.report('withdrawal_request', null, 'Use o outro caminho.') $$, '22023', null,
                 'retirada não passa por relato (usa request_takedown)');

-- edição pelo gestor: campos diretos x campos sensíveis
select tests.as_owner();
insert into app.entity_managers(entity_id, account_id, status, verified_at) values (tests.id('E2'), tests.id('B'), 'active', now());
select app._project_entity(tests.id('E2'));
insert into tests.fx(key, txt) select 'E2_SLUG', slug from app.entities where id = tests.id('E2');
insert into tests.fx(key, txt) select 'E2_NAME', original_name from app.entities where id = tests.id('E2');
select tests.as_user(tests.id('C'));
select throws_ok(format('select api.manager_update(%L, %L::jsonb)', tests.id('E2'), '{"website_url":"https://x.example.org"}'), 'P0002', null,
                 'não gestor não edita');
select tests.as_user(tests.id('B'));
select throws_ok(format('select api.manager_update(%L, %L::jsonb)', tests.id('E2'), '{"research_notes":"x"}'), '22023', null,
                 'campo fora da lista → 22023');
insert into tests.fx(key, txt) select 'UPD', api.manager_update(tests.id('E2'),
  jsonb_build_object('descriptions', jsonb_build_object('pt', 'Resumo novo escrito pela própria iniciativa.'),
                     'website_url', 'https://novo-site.example.org', 'name', 'Nome Novo Proposto Pela Iniciativa'))::text;
select ok(((tests.txt('UPD')::jsonb)->'applied') ?& array['descriptions','website_url'], 'resumo e site aplicados na hora');
select isnt((tests.txt('UPD')::jsonb)->>'pending_version_id', null, 'nome vai para revisão (versão congelada)');
select tests.as_anon();
select is(api.entity_page(tests.txt('E2_SLUG'))->'summary'->'pt'->>'body', 'Resumo novo escrito pela própria iniciativa.', 'resumo novo publicado');
select is(api.entity_page(tests.txt('E2_SLUG'))->'summary'->'en', 'null'::jsonb, 'tradução automática antiga removida');
select is(api.entity_page(tests.txt('E2_SLUG'))->>'name', tests.txt('E2_NAME'), 'nome público não muda antes da revisão');

-- curadoria aprova o nome → novo slug; slug antigo redireciona
select tests.as_user(tests.id('MOD'));
select is(api.review_version(((tests.txt('UPD')::jsonb)->>'pending_version_id')::uuid, 'approve', 'representation',
          'Nome confirmado no site da iniciativa.'), 'approved', 'curadoria aprova o novo nome');
select tests.as_anon();
select is(api.entity_page(tests.txt('E2_SLUG'))->>'name', 'Nome Novo Proposto Pela Iniciativa', 'slug antigo abre a ficha renomeada');
select is(api.entity_page(tests.txt('E2_SLUG'))->>'canonical_slug', 'nome-novo-proposto-pela-iniciativa', 'resposta traz o slug canônico');

-- iniciativas-irmãs
select is((select count(*)::int from api.sister_initiatives(tests.id('X'), 6) s
            where s.relation = 'same_family_other_country' and (cardinality(s.shared_families) = 0
               or s.country_code = (select country_code from api.entity_list where id = tests.id('X')))), 0,
          'irmãs: mesma família e sempre outro país');
select is((select count(*)::int from api.sister_initiatives(tests.id('X'), 6) s
            where s.relation = 'complementary_same_city' and s.families && (select families from api.entity_list where id = tests.id('X'))), 0,
          'complementares: mesma cidade e nenhuma família em comum');
select ok((select count(*) from api.sister_initiatives(tests.id('X'), 50) where relation = 'same_family_other_country') <= 12,
          'irmãs: limite máximo de 12 por grupo');
select results_eq(format('select entity_id from api.sister_initiatives(%L, 6)', tests.id('X')),
                  format('select entity_id from api.sister_initiatives(%L, 6)', tests.id('X')), 'irmãs: ordem estável entre chamadas');

-- correção do Marco B: bloqueios de publicação voltam como lista (antes: erro "malformed array literal")
select tests.as_owner();
insert into app.entities(id, kind, presence_type, original_name) values ('c1600000-0000-4000-a000-000000000001', 'collective', 'physical', 'Rascunho de teste');
select ok(app.publication_blockers('c1600000-0000-4000-a000-000000000001') @> array['fonte','atividade_atual','direitos'],
          'publication_blockers devolve a lista de bloqueios');
select tests.as_user(tests.id('MOD'));
select throws_ok($$ select api.publish_entity('c1600000-0000-4000-a000-000000000001', 'Tentativa de publicar sem requisitos.') $$,
                 'P0001', null, 'publicar rascunho sem requisitos → P0001 "publicação bloqueada"');

select tests.as_owner();
select * from finish();
rollback;
