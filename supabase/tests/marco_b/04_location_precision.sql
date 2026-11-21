-- Teste de aceite 4: precisão cidade/região não vaza coordenada exata (JSON, view, função, consulta por área).
\ir _ids.psql
begin;
select plan(17);

select tests.as_anon();
select is((select array[lon, lat] from api.places where id = :P2), array[-24.00000, -4.00000]::numeric[],
          'P2 (cidade) publica o ponto de rótulo da cidade');
select is((select array[lon, lat] from api.areas where id = 'xx-vila-brisa'), array[-24.0000, -4.0000]::numeric[],
          'ponto público = label_point do gazetteer, não da sede');
select is((select precision from api.places where id = :P4), 'region', 'local sensível publicado só por região');
select is((select array[lon, lat] from api.places where id = :P4), array[-24.50000, -4.50000]::numeric[], 'P4 recebe ponto da região');
-- Nenhuma superfície contém os dígitos das coordenadas privadas
select is((select count(*)::int from api.places where lon::text like '%24.0314%' or lat::text like '%4.0271%'
            or lon::text like '%25.1111%' or lat::text like '%5.2222%'), 0, 'view de locais sem coordenada privada');
select ok(api.entity_detail(:E3)::text !~ '(24\.031|4\.027)', 'JSON do detalhe de E3 sem coordenada privada');
select ok(api.entity_detail(:E7)::text !~ '(25\.111|5\.222)', 'JSON do detalhe do local sensível sem coordenada privada');
select ok((select coalesce(string_agg(t::text, ''), '') from api.places_in_bbox(-26, -6, -23, -3) t) !~ '(24\.031|4\.027|25\.111|5\.222)',
          'resposta da consulta por área sem coordenada privada');
-- Não dá para triangular: caixa minúscula em torno do ponto privado não retorna o local
select is((select count(*)::int from api.places_in_bbox(-24.0315, -4.0272, -24.0313, -4.0271)), 0, 'caixa no ponto privado de P2 → vazio');
select is((select count(*)::int from api.places_in_bbox(-25.1112, -5.2223, -25.1110, -5.2221)), 0, 'caixa no ponto privado de P4 → vazio');
-- Determinismo (sem ruído aleatório renovado por consulta)
select is((select array_agg(array[lon, lat]) from (select lon, lat from api.places where id = :P2 union all
           select lon, lat from api.places where id = :P2) s), array[array[-24.00000, -4.00000], array[-24.00000, -4.00000]]::numeric[],
          'ponto público é determinístico');
-- Estrutura: colunas privadas não existem na projeção
select tests.as_owner();
select is((select array_agg(column_name::text order by ordinal_position) from information_schema.columns
            where table_schema = 'api' and table_name = 'places'),
          array['id','kind','precision','area_id','country_code','lon','lat','is_synthetic'], 'lista explícita de colunas de api.places');
select hasnt_column('pub', 'places', 'geom_exact', 'pub.places não tem coordenada exata');
select hasnt_column('app', 'profiles', 'address_private', 'perfil de pessoa não tem campo de endereço');
-- Restrições de integridade
select throws_ok(format('insert into app.entity_places(entity_id, place_id) values (%L, %L)', :E12, :P1),
                 '23514', null, 'pessoa não pode ser vinculada a local exato');
select throws_ok($$ update app.places set is_sensitive = true, precision = 'exact_public_venue'
                    where id = '00000000-0000-4000-c000-000000000004' $$, '23514', null, 'local sensível não aceita precisão exata');
select tests.as_user(:PRES);
select throws_ok($$ select api.upsert_profile('x pessoa', null, 'xx-vila-brisa', 'exact_public_venue') $$, '23514', null,
                 'perfil de pessoa não aceita precisão exata');
select tests.as_owner();
select * from finish();
rollback;
