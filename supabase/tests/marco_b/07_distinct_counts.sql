-- Teste de aceite 7: cadastro com várias categorias mantém um local; local compartilhado não duplica;
-- contadores distintos (locais físicos / iniciativas / territoriais / redes / online / perfis).
-- Exercita o fluxo completo pela API: rascunho → submissão → revisão → evidência → publicação.
\ir _ids.psql
begin;
select plan(19);

select tests.as_anon();
select results_eq($$ select physical_places::int, initiatives::int, territorial_groups::int, networks::int, online_resources::int, public_profiles::int
                     from api.public_counters $$, $$ values (4, 5, 1, 1, 1, 1) $$, 'contadores iniciais distintos');
select is((select count(*)::int from api.places where id = :P1), 1, 'local compartilhado P1 aparece uma vez');
select is((select count(*)::int from api.entity_places where place_id = :P1), 2, 'P1 tem 2 entidades vinculadas');
select is((select cardinality(entity_ids) from api.places_in_bbox(-25.1, -5.1, -24.9, -4.9) where place_id = :P1), 2, 'mapa: 1 ponto com 2 entidades');
select is((select count(*)::int from api.entity_categories where entity_id = :E1), 3, 'E1 tem 3 categorias e 1 local');
select ok((select sum(entities) from api.category_facets()) <> (select physical_places from api.public_counters),
          'soma de categorias não é usada como total de locais');

-- Novo cadastro com 3 categorias que compartilha P1
select tests.as_user(:B);
select lives_ok($$ select api.create_entity_draft('collective','physical','[SINTÉTICO] Oficina de Reparo Partilhada','pt',
                   '{"country_code":"XX","categories":["repair_reuse","libraries_things","gift_exchange"],"primary_category":"repair_reuse",
                     "descriptions":{"pt":"Oficina fictícia que ocupa o mesmo centro social."}}') $$, 'B cria rascunho com 3 categorias');
select lives_ok($$ select api.submit_version((select id from app.entity_versions where author_id = auth.uid() order by created_at desc limit 1)) $$,
                'B submete');
select tests.as_user(:CUR_XX);
select is(api.review_version((select v.id from app.entity_versions v join app.entities e on e.id = v.entity_id
                               where e.original_name like '%Oficina de Reparo%'), 'approve', 'source', 'Fonte própria fictícia conferida.'),
          'approved', 'curadoria aprova a versão');
select lives_ok($$ select api.add_evidence(e.id, 'primary_page_read', 'E2', 'https://oficina.exemplo.invalid', current_date, 'fictícia')
                     from app.entities e where e.original_name like '%Oficina de Reparo%' $$, 'curadoria registra evidência E2');
select lives_ok($$ select api.set_editorial_facts(e.id, 'active', current_date, 'autodeclaração (fictícia)')
                     from app.entities e where e.original_name like '%Oficina de Reparo%' $$, 'curadoria registra atividade e direitos');
select lives_ok($$ select api.link_place(e.id, '00000000-0000-4000-c000-000000000001')
                     from app.entities e where e.original_name like '%Oficina de Reparo%' $$, 'curadoria vincula ao local compartilhado P1');
select lives_ok($$ select api.publish_entity(e.id, 'Publicação após revisão de fonte e atividade (fictícia).')
                     from app.entities e where e.original_name like '%Oficina de Reparo%' $$, 'curadoria publica');

select tests.as_anon();
select is((select physical_places::int from api.public_counters), 4, 'locais físicos continuam 4 (P1 não duplica)');
select is((select initiatives::int from api.public_counters), 6, 'iniciativas sobem para 6');
select is((select count(*)::int from api.entity_places where place_id = :P1), 3, 'P1 agora tem 3 entidades');
select is((select count(*)::int from api.places where id = :P1), 1, 'P1 continua um único local');
select is((select count(*)::int from api.entity_categories c join api.entities e on e.id = c.entity_id
            where e.name like '%Oficina de Reparo%'), 3, 'nova ficha com 3 categorias');
-- Rede e recurso online não entram na meta de locais físicos
select is((select count(*)::int from api.entity_places where entity_id in (:E4, :E5)), 0, 'rede e recurso online sem local físico');
select tests.as_owner();
select * from finish();
rollback;
