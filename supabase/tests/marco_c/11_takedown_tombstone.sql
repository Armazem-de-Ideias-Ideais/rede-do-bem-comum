-- Marco C, teste 11: depois da confirmação por e-mail (0012), a retirada preventiva some de TODAS as superfícies na mesma
-- transação; moderação restaura ou confirma; tombstone bloqueia reimportação; seed não desfaz ocultação.
-- (O comportamento antigo, ocultar direto no pedido, não existe mais: ver 17_takedown_abuse.sql.)
begin;
select plan(52);

-- preparação (owner): uma oferta vigente para X, para checar o feed
select tests.as_owner();
insert into app.offers_needs(id, entity_id, kind, topic, title, valid_until, visibility, publication_state)
values ('c1000000-0000-4000-a000-000000000001', tests.id('X'), 'offer', 'tools', 'Ferramentas de teste', current_date + 30, 'public', 'published');
select app._project_offers(tests.id('X'));
insert into tests.fx(key, id, txt) select 'X_SLUG', null, slug from app.entities where id = tests.id('X');
insert into tests.fx(key, id, txt) select 'X_NAME', null, original_name from app.entities where id = tests.id('X');
insert into tests.fx(key, id) select 'X_PLACE', place_id from pub.entity_places where entity_id = tests.id('X') limit 1;
insert into tests.fx(key, id, txt) select 'X_BBOX', null, concat_ws(',', lon - 0.01, lat - 0.01, lon + 0.01, lat + 0.01)
  from pub.entities where id = tests.id('X');
create temp table s0 as select * from api.public_stats;
grant select on s0 to anon, authenticated;

-- antes: X visível em todas as superfícies
select tests.as_anon();
select tests.ip('203.0.113.10');
select is((select count(*)::int from api.entity_list where id = tests.id('X')), 1, 'antes: X na lista/mapa');
select isnt(api.entity_page(tests.txt('X_SLUG')), null, 'antes: X por slug');
select ok((select count(*) from api.search_entities(tests.txt('X_NAME')) where entity_id = tests.id('X')) = 1, 'antes: X na busca');
select ok((select count(*) from api.places_in_bbox(split_part(tests.txt('X_BBOX'), ',', 1)::float8, split_part(tests.txt('X_BBOX'), ',', 2)::float8,
            split_part(tests.txt('X_BBOX'), ',', 3)::float8, split_part(tests.txt('X_BBOX'), ',', 4)::float8)
           where place_id = tests.id('X_PLACE')) = 1, 'antes: local de X no mapa por área');
select is((select count(*)::int from api.sister_initiatives(tests.id('Y'), 12) where entity_id = tests.id('X')
            and relation = 'complementary_same_city'), 1, 'antes: X é irmã complementar de Y');
select is((select count(*)::int from api.offers_needs_feed where entity_id = tests.id('X')), 1, 'antes: oferta de X no feed');

-- pedido sem login: honeypot não grava nada
select is(api.request_takedown(tests.id('X'), 'Pedido de robô preenchendo tudo', 'other', null, 'pt', 'http://spam') - 'request_id',
          '{"hidden":false,"needs_confirmation":false,"queued":true}'::jsonb, 'honeypot: resposta de sucesso no formato normal, sem ocultar');
select is((select count(*)::int from api.entity_list where id = tests.id('X')), 1, 'honeypot: nada foi ocultado');
select tests.as_owner();
select is((select count(*)::int from app.takedown_requests), 0, 'honeypot: nada foi gravado');
select tests.as_anon();
select throws_ok(format('select api.request_takedown(%L, %L, %L)', tests.id('X'), 'curto', 'other'), '22023', null,
                 'motivo curto demais → 22023');
select throws_ok(format('select api.request_takedown(%L, %L, %L, null, %L, null, %L)', tests.id('X'), 'Motivo suficiente para o teste.', 'other', 'pt', 'sem-arroba'),
                 '22023', null, 'e-mail inválido → 22023');

-- pedido real com e-mail: NÃO oculta; só o clique no link enviado ao e-mail oculta
select is(api.request_takedown(tests.id('X'), 'Somos a iniciativa e não autorizamos a publicação.', 'representative',
           'contato@exemplo.invalid', 'pt', null, 'Pessoa@Exemplo.invalid') - 'request_id',
          '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'pedido com e-mail: pede confirmação e não oculta');
select is((select count(*)::int from api.entity_list where id = tests.id('X')), 1, 'pedido com e-mail: a ficha continua no ar até confirmar');
select tests.as_owner();
insert into tests.fx(key, txt) select 'X_TOKEN', s.data->>'token' from app.notification_secrets s
  join app.notification_outbox o on o.id = s.outbox_id where o.kind = 'takedown_confirm' and o.entity_id = tests.id('X');
select tests.as_anon();
select is(api.confirm_takedown(tests.txt('X_TOKEN')), '{"hidden":true,"queued":false}'::jsonb, 'link confirmado: ficha oculta na hora');
select is((select count(*)::int from api.entity_list where id = tests.id('X')), 0, 'depois: fora da lista e do mapa');
select is(api.entity_page(tests.txt('X_SLUG')), null, 'depois: slug não abre');
select is(api.entity_page(null, tests.id('X')), null, 'depois: id não abre');
select is(api.entity_detail(tests.id('X')), null, 'depois: detalhe do Marco B vazio');
select is((select count(*)::int from api.entities where id = tests.id('X')), 0, 'depois: fora da view entities');
select is((select count(*)::int from api.search_entities(tests.txt('X_NAME')) where entity_id = tests.id('X')), 0, 'depois: fora da busca');
select is((select count(*)::int from api.autocomplete(left(tests.txt('X_NAME'), 20)) where entity_id = tests.id('X')), 0, 'depois: fora do autocomplete');
select is((select count(*)::int from api.places where id = tests.id('X_PLACE')), 0, 'depois: local fora da view de locais');
select is((select count(*)::int from api.places_in_bbox(split_part(tests.txt('X_BBOX'), ',', 1)::float8, split_part(tests.txt('X_BBOX'), ',', 2)::float8,
            split_part(tests.txt('X_BBOX'), ',', 3)::float8, split_part(tests.txt('X_BBOX'), ',', 4)::float8)
           where place_id = tests.id('X_PLACE')), 0, 'depois: fora do mapa por área');
select is((select count(*)::int from api.sister_initiatives(tests.id('Y'), 12) where entity_id = tests.id('X')), 0, 'depois: fora das irmãs');
select is((select count(*)::int from api.offers_needs_feed where entity_id = tests.id('X')), 0, 'depois: oferta fora do feed');
select is((select count(*)::int from api.sitemap where entity_id = tests.id('X')), 0, 'depois: fora do sitemap');
select is((select entities_total from api.public_stats), (select entities_total - 1 from s0), 'depois: total cai 1');
select is((select physical_places from api.public_stats), (select physical_places - 1 from s0), 'depois: locais físicos caem 1');
select is((select initiatives from api.public_stats), (select initiatives - 1 from s0), 'depois: iniciativas caem 1');
select is((select offers_active from api.public_stats), (select offers_active - 1 from s0), 'depois: ofertas vigentes caem 1');

select tests.as_owner();
select is((select count(*)::int from app.takedown_requests where entity_id = tests.id('X') and status = 'open' and auto_hidden
            and ip_hash ~ '^[0-9a-f]{64}$' and email = 'pessoa@exemplo.invalid' and email_hash ~ '^[0-9a-f]{64}$'), 1,
          'pedido na fila, IP só como hash, e-mail normalizado só na tabela privada');
select is((select count(*)::int from app.notification_outbox where kind = 'takedown_request' and to_moderator
            and entity_id = tests.id('X')), 1, 'moderador notificado');
select is((select count(*)::int from app.cache_invalidation_outbox where entity_id = tests.id('X') and reason = 'takedown_preventive'), 1,
          'invalidação de cache enfileirada');
select is(app.seed_load_record(jsonb_build_object('id', tests.id('X'), 'research_id', (select research_id from app.entities where id = tests.id('X')),
          'name', tests.txt('X_NAME'), 'kind', 'collective', 'presence', 'physical', 'country', 'ZZ', 'categories', '[]'::jsonb,
          'source_url', 'https://exemplo.invalid/x', 'source_key', 'research')),
          'kept_unpublished', 'recarga do seed NÃO republica ficha oculta preventivamente');

-- limites: 5 por hora por IP (pedidos sem e-mail vão para a fila e não ocultam)
select tests.as_anon();
select tests.ip('203.0.113.77');
select lives_ok(format('select api.request_takedown(%L, %L, %L) from generate_series(1, 5)', tests.id('E5'), 'Pedido repetido para testar limite', 'other'),
                '5 pedidos do mesmo IP passam');
select throws_ok(format('select api.request_takedown(%L, %L, %L)', tests.id('E5'), 'Pedido repetido para testar limite', 'other'),
                 '54000', null, '6º pedido do mesmo IP na hora → 54000');

-- disjuntor: com limite global zerado, o pedido é registrado mas não oculta
select tests.as_owner();
update app.settings set value = '0' where key = 'takedown_autohide_per_hour';
select tests.as_anon();
select tests.ip('203.0.113.78');
select is(api.request_takedown(tests.id('E4'), 'Pedido com disjuntor acionado.', 'mentioned', null, 'pt', null, 'e4@exemplo.invalid') - 'request_id',
          '{"hidden":false,"needs_confirmation":true,"queued":false}'::jsonb, 'disjuntor: pedido com e-mail aceito');
select tests.as_owner();
insert into tests.fx(key, txt) select 'E4_TOKEN', s.data->>'token' from app.notification_secrets s
  join app.notification_outbox o on o.id = s.outbox_id where o.kind = 'takedown_confirm' and o.entity_id = tests.id('E4');
select tests.as_anon();
select is(api.confirm_takedown(tests.txt('E4_TOKEN')), '{"hidden":false,"queued":true}'::jsonb, 'disjuntor: confirmação barrada, pedido na fila');
select is((select count(*)::int from api.entity_list where id = tests.id('E4')), 1, 'disjuntor: ficha continua no ar');

-- moderação: restaurar X exige justificativa
select tests.as_user(tests.id('A'));
select throws_ok(format('select api.mod_decide_takedown(id, %L, %L) from (select 1) s, lateral (select gen_random_uuid() as id) x', 'restore', 'justificativa longa'),
                 'P0002', null, 'conta sem papel não decide retirada');
select tests.as_user(tests.id('MOD'));
select throws_ok(format('select api.mod_decide_takedown((select (x->>''id'')::uuid from jsonb_array_elements(api.mod_list(''takedowns'')) x where x->>''entity_id'' = %L), %L, %L)',
                 tests.id('X'), 'restore', 'curta'), '22023', null, 'restaurar sem justificativa → 22023');
select lives_ok(format('select api.mod_decide_takedown((select (x->>''id'')::uuid from jsonb_array_elements(api.mod_list(''takedowns'')) x where x->>''entity_id'' = %L), %L, %L)',
                tests.id('X'), 'restore', 'Pedido sem vínculo comprovado com a iniciativa.'), 'moderação restaura X');
select tests.as_anon();
select is((select count(*)::int from api.entity_list where id = tests.id('X')), 1, 'restaurada: X volta à lista');
select is((select entities_total from api.public_stats), (select entities_total from s0),
          'restaurada: total volta ao inicial (os pedidos sem e-mail de E5 não ocultam nada)');

-- retirada confirmada de W → tombstone (hashes) e reimportação bloqueada
select tests.as_anon();
select tests.ip('203.0.113.11');
select is((api.request_takedown(tests.id('W'), 'Pedimos a retirada definitiva da nossa ficha.', 'representative')->>'queued')::boolean,
          true, 'W: sem e-mail o pedido entra na fila e a ficha fica no ar até a decisão da moderação');
select tests.as_user(tests.id('MOD'));
select lives_ok(format('select api.mod_decide_takedown((select (x->>''id'')::uuid from jsonb_array_elements(api.mod_list(''takedowns'')) x where x->>''entity_id'' = %L), %L, %L)',
                tests.id('W'), 'confirm', 'Retirada a pedido da própria iniciativa.'), 'moderação confirma retirada de W');
select tests.as_anon();
select is((select count(*)::int from api.entity_list where id = tests.id('W')), 0, 'W fora do ar após confirmação');
select tests.as_owner();
select ok((select count(*) >= 4 and bool_and(key_hash ~ '^[0-9a-f]{64}$') from app.suppression_tombstones where entity_id = tests.id('W')),
          'tombstones de W: id, nome+país, domínio e fonte — só hashes');
select is(app.seed_load_record(jsonb_build_object('id', tests.id('W'), 'research_id', (select research_id from app.entities where id = tests.id('W')),
          'name', 'Nome trocado', 'kind', 'collective', 'presence', 'physical', 'country', 'ZZ', 'categories', '[]'::jsonb,
          'source_url', 'https://exemplo.invalid/w', 'source_key', 'research')), 'blocked_by_tombstone', 'reimportar W (mesmo id) → bloqueado');
select is(app.seed_load_record(jsonb_build_object('id', gen_random_uuid(), 'research_id', 'RBC-T9001',
          'name', (select original_name from app.entities where id = tests.id('W')), 'kind', 'collective', 'presence', 'physical',
          'country', (select country_code from app.entities where id = tests.id('W')), 'categories', '[]'::jsonb,
          'source_url', 'https://exemplo.invalid/w2', 'source_key', 'research')), 'blocked_by_tombstone', 'mesmo nome+país com outro código → bloqueado');
select is(app.seed_load_record(jsonb_build_object('id', gen_random_uuid(), 'research_id', 'RBC-T9002', 'name', 'Nome completamente novo',
          'kind', 'collective', 'presence', 'physical', 'country', 'ZZ', 'categories', '[]'::jsonb,
          'own_url', 'https://www.' || tests.txt('W') || '/sobre', 'source_url', 'https://exemplo.invalid/w3', 'source_key', 'research')),
          'blocked_by_tombstone', 'mesmo domínio do site → bloqueado');
select is(app.seed_load_record(jsonb_build_object('id', gen_random_uuid(), 'research_id', 'RBC-T9003', 'name', 'Iniciativa sem relação',
          'kind', 'collective', 'presence', 'online', 'country', 'ZZ', 'categories', '["mutual_aid"]'::jsonb,
          'source_url', 'https://exemplo.invalid/w4', 'source_key', 'research')), 'inserted', 'registro não suprimido entra normalmente');

select * from finish();
rollback;
