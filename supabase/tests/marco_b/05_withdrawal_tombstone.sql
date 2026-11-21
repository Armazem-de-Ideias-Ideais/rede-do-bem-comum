-- Teste de aceite 5: ficha retirada some de todas as superfícies (URL direta, busca, mapa,
-- contadores, sitemap, exportação, alias antigo) e a importação não a republica.
-- Inclui parte do teste 8 (importador: domínio/URL) e do teste 12 (reaplicar retiradas após restauração).
\ir _ids.psql
begin;
select plan(31);

select tests.as_anon();
select isnt(api.entity_detail(:E3), null, 'antes: E3 visível por URL direta');
select is((select count(*)::int from api.search_entities('Brisa')), 1, 'antes: E3 na busca');
select is((select physical_places::int from api.public_counters), 4, 'antes: 4 locais físicos');
select isnt(api.entity_detail(:ALIAS_E1), null, 'antes: identificador antigo (alias) resolve E1');

select tests.as_user(:MOD);
select lives_ok(format('select api.withdraw_entity(%L, %L)', :E3, 'exposure_risk'), 'moderação retira E3');

select tests.as_anon();
select is(api.entity_detail(:E3), null, 'depois: URL direta → nada');
select is((select count(*)::int from api.search_entities('Brisa')), 0, 'depois: fora da busca');
select is((select count(*)::int from api.autocomplete('Brisa')), 0, 'depois: fora do autocomplete');
select is((select count(*)::int from api.places_in_bbox(-26, -6, -23, -3) where :P2 = place_id), 0, 'depois: local some do mapa');
select is((select count(*)::int from api.places where id = :P2), 0, 'depois: fora da view de locais');
select is((select physical_places::int from api.public_counters), 3, 'depois: contador de locais = 3');
select is((select initiatives::int from api.public_counters), 4, 'depois: contador de iniciativas = 4');
select is((select count(*)::int from api.sitemap where entity_id = :E3), 0, 'depois: fora do sitemap');
select is((select entities::int from api.category_facets() where category_id = 'worker_coops'), 1, 'depois: faceta recalculada');

select tests.as_owner();
select is((select (select count(*) from pub.entities where id = :E3) + (select count(*) from pub.entity_places where entity_id = :E3)
              + (select count(*) from pub.entity_texts where entity_id = :E3) + (select count(*) from pub.entity_categories where entity_id = :E3)
              + (select count(*) from pub.relationships where from_entity = :E3 or to_entity = :E3)
              + (select count(*) from pub.entity_sources where entity_id = :E3))::int, 0, 'nenhuma linha de E3 em pub');
select is((select count(*)::int from app.cache_invalidation_outbox where entity_id = :E3 and reason = 'withdrawn'
             and :P2 = any(place_ids)), 1, 'invalidação de cache enfileirada com o local');
select ok((select count(*) >= 3 and bool_and(key_hash ~ '^[0-9a-f]{64}$') from app.suppression_tombstones where entity_id = :E3),
          'tombstones criados apenas com hashes');
select is((select count(*)::int from app.suppression_tombstones where key_hash ilike '%brisa%'), 0, 'tombstone não guarda nome em claro');

-- Reimportação bloqueada
select tests.as_service();
select is(app.import_source_record(:SRC, 'ext-003', 'https://diretorio.exemplo.invalid/item/003', 'Outro nome',
          'XX', 'cooperative', 'physical'), 'blocked_by_tombstone', 'mesma fonte+id externo → bloqueado');
select is(app.import_source_record(:SRC, 'ext-novo-1', 'https://diretorio.exemplo.invalid/item/novo1', '[SINTÉTICO] Cooperativa Brisa',
          'XX', 'cooperative', 'physical'), 'blocked_by_tombstone', 'mesmo nome normalizado+país → bloqueado');
select is(app.import_source_record(:SRC, 'ext-novo-2', 'https://diretorio.exemplo.invalid/item/novo2', 'Nome diferente',
          'XX', 'cooperative', 'physical', '{"website":"https://www.brisa.exemplo.invalid/contato"}'),
          'blocked_by_tombstone', 'mesmo domínio do site → bloqueado');
select is(app.import_source_record(:SRC, 'ext-novo-3', 'https://diretorio.exemplo.invalid/item/novo3', '[SINTÉTICO] Iniciativa Nova',
          'XX', 'collective', 'physical'), 'draft_created', 'registro não suprimido entra como rascunho');
select throws_ok(format('select app.import_source_record(%L, %L, %L, %L, %L, %L, %L)', :SRC, 'x1',
          'https://169.254.169.254/latest/meta-data', 'x', 'XX', 'collective', 'physical'), '22023', null,
          'URL fora do domínio autorizado (metadados de nuvem) → rejeitada');
select throws_ok(format('select app.import_source_record(%L, %L, %L, %L, %L, %L, %L)', :SRC, 'x2',
          'http://diretorio.exemplo.invalid/item/x2', 'x', 'XX', 'collective', 'physical'), '22023', null, 'URL sem https → rejeitada');
select throws_ok(format('select app.import_source_record(%L, %L, %L, %L, %L, %L, %L)', :SRC, 'x3',
          'https://diretorio.exemplo.invalid/p/x3', 'x', 'XX', 'person', 'nonspatial'), '22023', null, 'importar pessoa → rejeitado');
select tests.as_anon();
select is((select count(*)::int from api.search_entities('Iniciativa Nova')), 0, 'importado não é publicado automaticamente');
select tests.as_owner();
select throws_like(format('select app._publish_entity(%L)', :E3), '%suprimida%', 'publicação de ficha suprimida é bloqueada');

-- Ocultação também vale para identificador antigo
select tests.as_user(:MOD);
select lives_ok(format('select api.hide_entity(%L, %L)', :E1, 'preventive'), 'moderação oculta E1 preventivamente');
select tests.as_anon();
select is(api.entity_detail(:ALIAS_E1), null, 'alias antigo de ficha oculta → nada');

-- Restauração de backup: linhas antigas reaparecem em pub e são removidas antes de expor
select tests.as_owner();
insert into pub.entities(id, kind, presence_type, counter_class, name, name_lang, name_norm, verification_label, is_synthetic, search_doc)
values ('00000000-0000-4000-e000-000000000003','cooperative','physical','initiative','[SINTÉTICO] Cooperativa Brisa','pt',
        'cooperativa brisa','activity_checked', true, to_tsvector('simple','brisa'));
select tests.as_service();
select ok(app.reapply_suppressions() >= 1, 'reaplicar supressões remove linha restaurada');
select tests.as_anon();
select is(api.entity_detail(:E3), null, 'após reaplicar: E3 continua fora');
select tests.as_owner();
select * from finish();
rollback;
