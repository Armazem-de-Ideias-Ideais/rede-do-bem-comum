-- Marco C, teste 13: os 173 de exposição alta, carregados com --private-invites, não aparecem em NENHUMA
-- superfície pública; convite tem token de uso único, expira, pode ser revogado ou recusado (tombstone).
begin;
select plan(36);

select tests.as_owner();
select is((select count(*)::int from app.invite_candidates), 173, 'os 173 estão carregados na tabela privada');
select is((select count(*)::int from app.entities e join app.invite_candidates c on c.id = e.id or c.research_id = e.research_id), 0,
          'nenhum candidato virou entidade');
select is((select count(*)::int from pub.entities pe join app.invite_candidates c
             on c.id = pe.id or pe.name_norm = pub.norm(c.data->>'name')), 0, 'nenhum candidato na projeção pub (por id ou nome)');
select is((select (select count(*) from pub.entity_places ep join app.invite_candidates c on c.id = ep.entity_id)
               + (select count(*) from pub.entity_texts t join app.invite_candidates c on c.id = t.entity_id)
               + (select count(*) from pub.export_set x join app.invite_candidates c on c.id = x.entity_id))::int, 0,
          'nenhuma linha de candidato em locais, textos ou exportação');
-- listas para checar as views como visitante
insert into tests.fx(key, txt) select 'CAND_IDS', string_agg(id::text, ',') from app.invite_candidates;
insert into tests.fx(key, txt) select 'CAND_NAMES', string_agg(data->>'name', '|') from app.invite_candidates;
insert into tests.fx(key, txt) select 'CAND_SLUGS', string_agg(app.slugify(data->>'name'), '|') from app.invite_candidates;
insert into tests.fx(key, txt) select 'K1_NAME', data->>'name' from app.invite_candidates where id = tests.id('K1');
select is(app.seed_load_record(c.data), 'skipped_private_candidate', 'seed público recusa registro de candidato')
  from app.invite_candidates c where c.id = tests.id('K4');

select tests.as_anon();
select is((select count(*)::int from api.entity_list where id::text = any (string_to_array(tests.txt('CAND_IDS'), ','))), 0,
          'anon: nenhum dos 173 na lista/mapa');
select is((select count(*)::int from api.entities where id::text = any (string_to_array(tests.txt('CAND_IDS'), ','))), 0,
          'anon: nenhum dos 173 na view entities');
select is((select count(*)::int from api.entity_list where name = any (string_to_array(tests.txt('CAND_NAMES'), '|'))), 0,
          'anon: nenhum nome dos 173 na lista');
select is((select count(*)::int from unnest(string_to_array(tests.txt('CAND_NAMES'), '|')) n, lateral api.search_entities(n, 100) s
            where s.entity_id::text = any (string_to_array(tests.txt('CAND_IDS'), ','))), 0, 'anon: busca por cada nome não acha candidato');
select is((select count(*)::int from unnest(string_to_array(tests.txt('CAND_SLUGS'), '|')) s where api.entity_page(s) is not null
            and (api.entity_page(s)->>'name') = any (string_to_array(tests.txt('CAND_NAMES'), '|'))), 0, 'anon: slug de candidato não abre ficha');
select is((select count(*)::int from unnest(string_to_array(tests.txt('CAND_IDS'), ',')) i where api.entity_page(null, i::uuid) is not null), 0,
          'anon: id de candidato não abre ficha');
select is((select entities_total::int from api.public_stats), (select count(*)::int from api.entity_list), 'contador = só fichas públicas');
select is((select count(*)::int from api.sitemap where entity_id::text = any (string_to_array(tests.txt('CAND_IDS'), ','))), 0, 'anon: fora do sitemap');
select ok(exists (select 1 from api.attribution_sources where attribution = 'Contém dados da Karte von Morgen / OpenFairDB, disponíveis sob ODbL'
                   and licence = 'ODbL-1.0'), 'página de atribuição: frase obrigatória da Karte von Morgen');

-- moderação cria convite
select tests.as_user(tests.id('A'));
select throws_ok(format('select api.mod_create_invite(%L)', tests.id('K1')), 'P0002', null, 'conta comum não cria convite');
select throws_ok('select api.mod_list(''invite_candidates'')', 'P0002', null, 'conta comum não lista candidatos');
select tests.as_user(tests.id('MOD'));
select is(jsonb_array_length(api.mod_list('invite_candidates', null, 200)), 173, 'moderador lista os candidatos');
insert into tests.fx(key, txt) select 'TOK1', api.mod_create_invite(tests.id('K1'), 30)->>'token';
select ok(tests.txt('TOK1') ~ '^[0-9a-f]{64}$', 'token de 64 hex devolvido uma única vez');

select tests.as_owner();
select is((select count(*)::int from app.invitations where token_hash = tests.txt('TOK1')), 0, 'banco guarda só o hash do token');
select is((select count(*)::int from app.audit_log where details::text like '%' || tests.txt('TOK1') || '%'), 0, 'token fora da auditoria');

-- prévia e aceite
select tests.as_anon();
select is(api.invite_preview(tests.txt('TOK1'))->>'name', tests.txt('K1_NAME'), 'prévia mostra a ficha proposta');
select throws_ok(format('select api.invite_accept(%L, %L)', tests.txt('TOK1'), 'convite-2026-11'), '42501', null, 'aceitar exige login');
select tests.as_user(tests.id('E'));
select throws_ok(format('select api.invite_accept(%L, %L)', tests.txt('TOK1'), 'versão inválida!'), '22023', null, 'aceite exige versão do texto');
select lives_ok(format('select api.invite_accept(%L, %L, %L)', tests.txt('TOK1'), 'convite-2026-11', 'city'), 'conta E aceita o convite');
select tests.as_anon();
select is((select count(*)::int from api.entity_list where id = tests.id('K1') and is_managed and verification_label = 'holder_confirmed'), 1,
          'após aceite: ficha publicada e gerida pela iniciativa');
select tests.as_owner();
select is((select count(*)::int from app.consent_records where entity_id = tests.id('K1') and account_id = tests.id('E')
            and purpose = 'public_presentation' and decision = 'granted' and text_version = 'convite-2026-11'), 1, 'autorização registrada com versão do texto');

-- uso único
select tests.as_user(tests.id('F'));
select throws_ok(format('select api.invite_accept(%L, %L)', tests.txt('TOK1'), 'convite-2026-11'), 'P0002', null, 'token usado não vale de novo');
select tests.as_anon();
select throws_ok(format('select api.invite_preview(%L)', tests.txt('TOK1')), 'P0002', null, 'token usado não mostra prévia');

-- expiração
select tests.as_user(tests.id('MOD'));
insert into tests.fx(key, txt) select 'TOK2', api.mod_create_invite(tests.id('K2'), 7)->>'token';
select tests.as_owner();
update app.invitations set expires_at = now() - interval '1 second' where candidate_id = tests.id('K2') and status = 'pending';
select tests.as_user(tests.id('F'));
select throws_ok(format('select api.invite_accept(%L, %L)', tests.txt('TOK2'), 'convite-2026-11'), 'P0002', null, 'token expirado não vale');
select tests.as_anon();
select is((select count(*)::int from api.entity_list where id = tests.id('K2')), 0, 'expirado: nada publicado');

-- revogação por novo convite
select tests.as_user(tests.id('MOD'));
insert into tests.fx(key, txt) select 'TOK3a', api.mod_create_invite(tests.id('K3'), 30)->>'token';
insert into tests.fx(key, txt) select 'TOK3b', api.mod_create_invite(tests.id('K3'), 30)->>'token';
select tests.as_anon();
select throws_ok(format('select api.invite_preview(%L)', tests.txt('TOK3a')), 'P0002', null, 'convite anterior revogado pelo novo');

-- recusa: tombstone e nunca publica
select lives_ok(format('select api.invite_decline(%L, %L)', tests.txt('TOK3b'), 'Preferimos não aparecer.'), 'iniciativa recusa');
select throws_ok(format('select api.invite_preview(%L)', tests.txt('TOK3b')), 'P0002', null, 'token recusado não vale mais');
select tests.as_owner();
select is((select status from app.invite_candidates where id = tests.id('K3')), 'declined', 'candidato marcado como recusado');
select is(app.seed_load_candidate(data), 'blocked_by_tombstone', 'recusado: recarga privada bloqueada') from app.invite_candidates where id = tests.id('K3');
select is(app.seed_load_record(data || jsonb_build_object('id', gen_random_uuid(), 'research_id', 'RBC-T9100')), 'blocked_by_tombstone',
          'recusado: mesmo nome+país pelo seed público bloqueado') from app.invite_candidates where id = tests.id('K3');

select * from finish();
rollback;
