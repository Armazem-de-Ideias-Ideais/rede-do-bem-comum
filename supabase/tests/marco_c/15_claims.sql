-- Marco C, teste 15: reivindicação pelos três caminhos — (a) e-mail no domínio do site, (b) código publicado,
-- (c) aprovação manual — sem revelar gestores e sem expor o código.
begin;
select plan(33);

select tests.as_owner();
-- conta cujo próprio e-mail está no domínio do site de DA (posse provada pelo link mágico)
insert into auth.users(id, email) values ('c0000000-0000-4000-a000-0000000000aa', 'coord@' || tests.txt('DA'));
insert into tests.fx(key, id) values ('U', 'c0000000-0000-4000-a000-0000000000aa');

select tests.as_anon();
select throws_ok(format('select api.claim_start(%L, %L, %L)', tests.id('DA'), 'manual', 'Sou da coordenação.'), '42501', null,
                 'reivindicar exige conta');

-- (a) validações de domínio
select tests.as_user(tests.id('B'));
select throws_ok(format('select api.claim_start(%L, %L, %L, %L)', tests.id('DA'), 'domain_email', 'Sou da coordenação.', 'alguem@gmail.com'),
                 '22023', null, '(a) e-mail de plataforma compartilhada não vale');
select throws_ok(format('select api.claim_start(%L, %L, %L, %L)', tests.id('DA'), 'domain_email', 'Sou da coordenação.', 'alguem@outro-dominio.org'),
                 '22023', null, '(a) domínio diferente do site não vale');
select throws_ok(format('select api.claim_start(%L, %L, %L, %L)', tests.id('DN'), 'domain_email', 'Sou da coordenação.', 'x@exemplo.org'),
                 '22023', null, '(a) ficha sem site: use outro caminho');
select throws_ok(format('select api.claim_start(%L, %L, %L)', gen_random_uuid(), 'manual', 'Sou da coordenação.'), 'P0002', null,
                 'ficha inexistente → não encontrado');

-- (a) com código enviado ao e-mail do domínio
insert into tests.fx(key, txt) select 'CLA', api.claim_start(tests.id('DA'), 'domain_email', 'Sou da coordenação desta iniciativa.',
                                                             'contato@' || tests.txt('DA'))::text;
select is((tests.txt('CLA')::jsonb)->>'status', 'awaiting_code', '(a) código enviado, aguardando');
select tests.as_owner();
insert into tests.fx(key, id) values ('CLA_ID', ((tests.txt('CLA')::jsonb)->>'claim_id')::uuid);
select is((select count(*)::int from app.notification_outbox o join app.notification_secrets s on s.outbox_id = o.id
            where o.kind = 'claim_code' and o.ref_id = tests.id('CLA_ID') and s.data->>'email' = 'contato@' || tests.txt('DA')
              and s.data->>'code' ~ '^[0-9]{6}$'), 1, '(a) e-mail com código de 6 dígitos na fila; segredo em tabela separada');
select is((select count(*)::int from app.claims where id = tests.id('CLA_ID') and code_hash ~ '^[0-9a-f]{64}$'), 1, '(a) banco guarda só o hash do código');
insert into tests.fx(key, txt) select 'CODE', s.data->>'code' from app.notification_outbox o join app.notification_secrets s on s.outbox_id = o.id
  where o.ref_id = tests.id('CLA_ID');
select tests.as_user(tests.id('B'));
select throws_ok('select code_hash from app.claims', '42501', null, '(a) a conta não lê o hash');
select is(api.claim_verify_code(tests.id('CLA_ID'), case when tests.txt('CODE') = '000000' then '000001' else '000000' end)->>'attempts_left',
          '4', '(a) código errado consome tentativa');
select is(api.claim_verify_code(tests.id('CLA_ID'), tests.txt('CODE'))->>'status', 'approved', '(a) código certo aprova');
select is(jsonb_array_length(api.my_account()->'managed'), 1, '(a) B agora gere DA');
select tests.as_anon();
select is((select is_managed from api.entity_list where id = tests.id('DA')), true, '(a) ficha aparece como gerida');
select is((select verification_label from api.entity_list where id = tests.id('DA')), 'holder_confirmed', '(a) selo de representação confirmada');
select tests.as_owner();
select is((select count(*)::int from app.claims where id = tests.id('CLA_ID') and verify_email is null and code_hash is null), 1,
          '(a) e-mail e hash apagados ao concluir');
select is((select count(*)::int from app.notification_outbox where kind = 'claim_approved' and recipient_account = tests.id('B')), 1,
          '(a) confirmação por e-mail para a conta');

-- (a) e-mail da própria conta no domínio: aprovação imediata
select tests.as_user(tests.id('U'));
select is(api.claim_start(tests.id('DA'), 'domain_email', 'Também coordeno esta iniciativa.', 'coord@' || tests.txt('DA'))->>'status',
          'approved', '(a) e-mail da conta no domínio: aprovado na hora, sem revelar o gestor anterior');

-- tentativas esgotadas
select tests.as_user(tests.id('C'));
insert into tests.fx(key, id) select 'CLA2', (api.claim_start(tests.id('DA'), 'domain_email', 'Tentativa de terceiro.', 'x@' || tests.txt('DA'))->>'claim_id')::uuid;
select is((select min((api.claim_verify_code(tests.id('CLA2'), 'zzzzzz')->>'attempts_left')::int) from generate_series(1, 4)), 1,
          '(a) quatro erros seguidos: resta 1 tentativa');
select is(api.claim_verify_code(tests.id('CLA2'), 'zzzzzz')->>'status', 'failed', '(a) quinto erro: reivindicação falha');
select is(api.claim_verify_code(tests.id('CLA2'), 'zzzzzz')->>'status', 'failed', '(a) depois de falhar, nada muda');

-- (b) código publicado no site ou rede social
select tests.as_user(tests.id('E'));
insert into tests.fx(key, txt) select 'CLB', api.claim_start(tests.id('DB'), 'published_code', 'Publicamos o código no nosso site oficial.')::text;
select ok(((tests.txt('CLB')::jsonb)->>'published_code') ~ '^rbc-[a-z2-9]{10}$', '(b) código para publicar no formato rbc-xxxxxxxxxx');
select is((tests.txt('CLB')::jsonb)->>'status', 'awaiting_evidence', '(b) aguardando evidência');
select throws_ok(format('select api.claim_submit_evidence(%L, %L)', (tests.txt('CLB')::jsonb)->>'claim_id', 'http://sem-https.example.org'),
                 '22023', null, '(b) evidência exige https');
select is(api.claim_submit_evidence(((tests.txt('CLB')::jsonb)->>'claim_id')::uuid, 'https://example.org/noticia-com-codigo')->>'status',
          'pending', '(b) evidência enviada → fila do moderador');
select tests.as_user(tests.id('MOD'));
select ok(exists (select 1 from jsonb_array_elements(api.mod_list('claims')) x
                   where x->>'id' = (tests.txt('CLB')::jsonb)->>'claim_id' and x->>'evidence_url' = 'https://example.org/noticia-com-codigo'
                     and x->>'published_code' = (tests.txt('CLB')::jsonb)->>'published_code'), '(b) moderador vê código e URL para conferir');
select lives_ok(format('select api.mod_decide_claim(%L, true, %L)', (tests.txt('CLB')::jsonb)->>'claim_id', 'Código conferido na página indicada.'),
                '(b) moderador aprova');
select tests.as_anon();
select is((select is_managed from api.entity_list where id = tests.id('DB')), true, '(b) ficha gerida');

-- (c) aprovação manual (aqui, recusada)
select tests.as_user(tests.id('F'));
insert into tests.fx(key, txt) select 'CLC', api.claim_start(tests.id('DC'), 'manual', 'Fui fundadora do coletivo em 2019.')::text;
select is((tests.txt('CLC')::jsonb)->>'status', 'pending', '(c) pedido manual pendente');
select tests.as_user(tests.id('F'));
select throws_ok(format('select api.mod_decide_claim(%L, true, %L)', (tests.txt('CLC')::jsonb)->>'claim_id', 'Aprovo a mim mesma, claro.'),
                 'P0002', null, '(c) quem reivindica não decide');
select tests.as_user(tests.id('MOD'));
select throws_ok(format('select api.mod_decide_claim(%L, false, %L)', (tests.txt('CLC')::jsonb)->>'claim_id', 'curta'), '22023', null,
                 '(c) decisão exige justificativa');
select lives_ok(format('select api.mod_decide_claim(%L, false, %L)', (tests.txt('CLC')::jsonb)->>'claim_id', 'Sem vínculo atual com a iniciativa.'),
                '(c) moderador recusa com justificativa');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox where kind = 'claim_rejected' and recipient_account = tests.id('F')), 1,
          '(c) recusa avisada por e-mail');
select is((select count(*)::int from app.notification_outbox where kind = 'claim_pending' and to_moderator), 2,
          'moderador avisado de (b) e (c)');

select * from finish();
rollback;
