-- Marco C, teste 14: ofertas/necessidades com validade (expiram sozinhas) e contadores distintos
-- (um local com várias iniciativas conta uma vez; redes, territórios e online fora dos locais físicos).
begin;
select plan(30);

select tests.as_owner();
insert into app.entity_managers(entity_id, account_id, status, verified_at) values (tests.id('E5'), tests.id('A'), 'active', now());
select app._project_entity(tests.id('E5'));
create temp table s0 as select * from api.public_stats;
grant select on s0 to anon, authenticated;

-- só gestor de ficha reivindicada publica
select tests.as_user(tests.id('B'));
select throws_ok(format('select api.offer_need_upsert(null, %L, %L, %L, %L, null, %L)', tests.id('E5'), 'offer', 'tools', 'Furadeira emprestada',
                 current_date + 30), 'P0002', null, 'não gestor não publica oferta');
select tests.as_user(tests.id('A'));
select throws_ok(format('select api.offer_need_upsert(null, %L, %L, %L, %L, null, %L)', tests.id('E5'), 'offer', 'tools', 'Furadeira emprestada',
                 current_date + 400), '22023', null, 'validade acima de 365 dias → 22023');
select throws_ok(format('select api.offer_need_upsert(null, %L, %L, %L, %L, null, %L)', tests.id('E5'), 'offer', 'tools', 'Furadeira emprestada',
                 current_date - 1), '22023', null, 'validade no passado → 22023');
select throws_ok(format('select api.offer_need_upsert(null, %L, %L, %L, %L, null, %L)', tests.id('E5'), 'offer', 'carros', 'Furadeira emprestada',
                 current_date + 30), '22023', null, 'tema fora da lista → 22023');
insert into tests.fx(key, id) select 'OF1', api.offer_need_upsert(null, tests.id('E5'), 'offer', 'tools', 'Furadeira emprestada', 'Às terças.', current_date + 30);
insert into tests.fx(key, id) select 'ND1', api.offer_need_upsert(null, tests.id('E5'), 'need', 'volunteering', 'Voluntários para mutirão', null, current_date);
select is((select count(*)::int from api.my_offers_needs()), 2, 'gestor vê seus itens');

select tests.as_anon();
select is((select count(*)::int from api.offers_needs_feed where entity_id = tests.id('E5')), 2, 'feed mostra oferta e necessidade vigentes');
select is(jsonb_array_length(api.entity_page(null, tests.id('E5'))->'offers_needs'), 2, 'ficha mostra os itens vigentes');
select is((select has_offers from api.entity_list where id = tests.id('E5')), true, 'lista marca has_offers');
select is((select offers_active from api.public_stats), (select offers_active + 1 from s0), 'contador de ofertas +1');
select is((select needs_active from api.public_stats), (select needs_active + 1 from s0), 'contador de necessidades +1');

-- passagem do tempo: a necessidade vence hoje; amanhã some sem nenhuma tarefa agendada
select tests.as_owner();
update pub.offers_needs set valid_until = current_date - 1 where id = tests.id('ND1');   -- simula o dia seguinte na projeção
select tests.as_anon();
select is((select count(*)::int from api.offers_needs_feed where id = tests.id('ND1')), 0, 'vencida some do feed');
select is((select count(*)::int from api.offers_needs where id = tests.id('ND1')), 0, 'vencida some da view do Marco B');
select is((select count(*)::int from jsonb_array_elements(api.entity_page(null, tests.id('E5'))->'offers_needs') o
            where (o->>'id')::uuid = tests.id('ND1')), 0, 'vencida some da ficha');
select is((select needs_active from api.public_stats), (select needs_active from s0), 'vencida sai do contador');
select tests.as_owner();
update app.offers_needs set valid_from = current_date - 40, valid_until = current_date - 1 where id in (tests.id('OF1'), tests.id('ND1'));
select app._project_offers(tests.id('E5'));
select tests.as_anon();
select is((select has_offers from api.entity_list where id = tests.id('E5')), false, 'sem itens vigentes: has_offers falso');
select tests.as_user(tests.id('A'));
select is((select expired from api.my_offers_needs() where id = tests.id('OF1')), true, 'gestor vê o item como expirado');
select lives_ok(format('select api.offer_need_upsert(%L, %L, %L, %L, %L, null, %L)', tests.id('OF1'), tests.id('E5'), 'offer', 'tools',
                'Furadeira emprestada', current_date + 60), 'gestor renova a validade');
select tests.as_anon();
select is((select count(*)::int from api.offers_needs_feed where id = tests.id('OF1')), 1, 'renovada volta ao feed');
select tests.as_user(tests.id('A'));
select lives_ok(format('select api.offer_need_remove(%L)', tests.id('OF1')), 'gestor remove a oferta');
select tests.as_anon();
select is((select count(*)::int from api.offers_needs_feed where entity_id = tests.id('E5')), 0, 'removida some do feed');

-- contadores distintos
select tests.as_anon();
select is((select physical_places from api.public_stats),
          (select count(distinct p.id) from api.places p where p.kind = 'physical_venue'), 'locais físicos = locais distintos');
select is((select initiatives + territorial_groups + networks + online_resources from api.public_stats),
          (select entities_total from api.public_stats), 'classes de contador são disjuntas e cobrem o total');
select is((select count(*)::int from api.entity_places ep join api.entities e on e.id = ep.entity_id
             join api.places p on p.id = ep.place_id where p.kind = 'physical_venue' and e.counter_class <> 'initiative'), 0,
          'redes, territórios e recursos online não geram local físico');
select is((select cities from api.public_stats), (select count(distinct area_id) from api.entity_list where location_precision = 'city'),
          'cidades = áreas distintas com ponto');
select is((select countries from api.public_stats), (select count(*) from api.country_counts), 'países = linhas de country_counts');

-- PB passa a funcionar no mesmo local de PA (local compartilhado): conta uma vez
select tests.as_owner();
insert into tests.fx(key, id) select 'PA_PLACE', place_id from app.entity_places where entity_id = tests.id('PA') limit 1;
insert into tests.fx(key, id) select 'PB_PLACE', place_id from app.entity_places where entity_id = tests.id('PB') limit 1;
delete from app.entity_places where entity_id = tests.id('PB');
insert into app.entity_places(entity_id, place_id, role) values (tests.id('PB'), tests.id('PA_PLACE'), 'shared');
select app._project_entity(tests.id('PB'));
select tests.as_anon();
select is((select physical_places from api.public_stats), (select physical_places - 1 from s0),
          'local compartilhado: PA+PB contam 1 local (o antigo de PB saiu)');
select is((select initiatives from api.public_stats), (select initiatives from s0), 'iniciativas continuam as mesmas');
select is((select count(*)::int from api.entity_places where place_id = tests.id('PA_PLACE')), 2, 'um local com duas iniciativas');
select is((select count(*)::int from api.places where id = tests.id('PB_PLACE')), 0, 'local antigo de PB saiu da projeção');
select is((select cardinality(b.entity_ids) from api.places p,
             lateral api.places_in_bbox((p.lon - 0.001)::float8, (p.lat - 0.001)::float8, (p.lon + 0.001)::float8, (p.lat + 0.001)::float8, 500) b
            where p.id = tests.id('PA_PLACE') and b.place_id = p.id), 2, 'mapa: um ponto com as duas iniciativas');

select tests.as_owner();
select * from finish();
rollback;
