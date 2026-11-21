-- Teste de aceite 3: perfil pessoal e vínculo restritos não aparecem em autocomplete,
-- facetas, contadores, busca, exportação ou sitemap.
\ir _ids.psql
begin;
select plan(22);

select tests.as_anon();
-- Perfis
select is((select count(*)::int from api.profiles), 1, 'somente 1 perfil com adesão expressa é público');
select is((select count(*)::int from api.profiles where public_id = :PROFILE_RES_PUBLIC_ID), 0, 'perfil reservado ausente da view');
select is((select count(*)::int from api.profiles where public_id in (:PPUB, :PRES)), 0,
          'perfil público não expõe id da conta') ;
select is((select public_profiles::int from api.public_counters), 1, 'contador de perfis públicos ignora o reservado');
select is((select count(*)::int from api.autocomplete('Pseud')), 0, 'perfis fora do autocomplete');
select is((select count(*)::int from api.search_entities('Pseudônimo')), 0, 'perfis fora da busca');
-- Entidade pessoal sem adesão
select is((select count(*)::int from api.entities where id = :E12), 0, 'pessoa sem adesão fora da view');
select is((select count(*)::int from api.autocomplete('Pessoa')), 0, 'pessoa sem adesão fora do autocomplete');
select is((select count(*)::int from api.sitemap where entity_id = :E12), 0, 'pessoa fora do sitemap');
select is((select count(*)::int from api.sitemap), 8, 'sitemap = 8 fichas institucionais publicadas');
-- Vínculo restrito (E3 → E4 sem autorização)
select is((select count(*)::int from api.relationships), 1, 'somente o vínculo autorizado é público');
select is((select count(*)::int from api.relationships where from_entity = :E3), 0, 'vínculo restrito E3→E4 ausente');
select is(jsonb_array_length(api.entity_detail(:E3)->'relationships'), 0, 'detalhe de E3 sem vínculo restrito');
select is(jsonb_array_length(api.entity_detail(:E4)->'relationships'), 1, 'detalhe da rede mostra só o nó autorizado');
-- Facetas: ficha oculta (E8, mutual_aid) não conta
select is((select entities::int from api.category_facets() where category_id = 'mutual_aid'), 1, 'faceta ignora ficha oculta');
select is((select count(*)::int from api.search_entities('Oculta')), 0, 'ficha oculta fora da busca');
-- Identidade política não é pesquisável
select is((select count(*)::int from api.search_entities('autogestão')), 0, 'identidade política não é indexada na busca');
-- Ofertas: restrita e vencida não aparecem
select is((select count(*)::int from api.offers_needs), 1, 'somente oferta pública e vigente aparece');
-- Exportação
select throws_ok($$ select * from api.export_institutional() $$, '42501', null, 'anon não exporta');
select tests.as_user(:A);
select is((select count(*)::int from api.export_institutional()), 2, 'exportação só com permissão específica (E1, E4)');
select is((select count(*)::int from api.export_institutional() where entity_id in (:E12, :E3)), 0, 'exportação sem pessoas nem fichas sem permissão');
-- Gestores nunca aparecem na superfície pública
select tests.as_owner();
select is((select count(*)::int from information_schema.columns where table_schema = 'api'
            and (column_name ilike '%manager%' or column_name ilike '%member%')), 0, 'nenhuma coluna de gestores/membros em api');
select * from finish();
rollback;
