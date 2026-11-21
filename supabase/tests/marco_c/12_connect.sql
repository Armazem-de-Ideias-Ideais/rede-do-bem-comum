-- Marco C, teste 12: Conectar. Pedido mediado; contatos só aparecem para os dois lados depois do aceite.
begin;
select plan(31);

-- preparação: A gere E1, B gere E2; E3 sem gestor; F gere E4 e não aceita pedidos
select tests.as_owner();
insert into app.entity_managers(entity_id, account_id, status, verified_at) values
  (tests.id('E1'), tests.id('A'), 'active', now()), (tests.id('E2'), tests.id('B'), 'active', now()),
  (tests.id('E4'), tests.id('F'), 'active', now());
update app.entities set accepts_connections = false where id = tests.id('E4');
select app._project_entity(tests.id(k)) from unnest(array['E1','E2','E4']) k;

-- visitante não conecta
select tests.as_anon();
select throws_ok(format('select api.connect_request(%L, %L, %L, %L)', tests.id('E1'), tests.id('E2'), 'Mensagem de teste longa', 'contato'),
                 '42501', null, 'anon não pode pedir conexão');

-- conta que não gere a ficha de origem
select tests.as_user(tests.id('C'));
select throws_ok(format('select api.connect_request(%L, %L, %L, %L)', tests.id('E1'), tests.id('E2'), 'Mensagem de teste longa', 'c@example.org'),
                 'P0002', null, 'só gestor ativo da ficha de origem pede conexão');

-- A pede conexão a B
select tests.as_user(tests.id('A'));
select lives_ok(format('select api.connect_request(%L, %L, %L, %L)', tests.id('E1'), tests.id('E2'),
                'Queremos trocar experiências sobre a horta comunitária.', 'a-contato@example.org'), 'A pede conexão E1 → E2');
select throws_ok(format('select api.connect_request(%L, %L, %L, %L)', tests.id('E1'), tests.id('E2'), 'Outra mensagem repetida', 'a-contato@example.org'),
                 'P0001', null, 'um pedido pendente por par');
select throws_ok('select count(*) from app.connect_requests', '42501', null, 'A não lê a tabela de pedidos diretamente');
select is((select count(*)::int from api.my_connections() where direction = 'out' and status = 'pending'), 1, 'A vê o próprio pedido pendente');
select is((select other_contact from api.my_connections() where direction = 'out'), null, 'A não vê contato de B antes do aceite');
select is((select my_contact from api.my_connections() where direction = 'out'), 'a-contato@example.org', 'A vê o próprio contato');
select throws_ok(format('select api.connect_respond((select request_id from api.my_connections() where direction = %L), true, %L)', 'out', 'aceito eu mesmo'),
                 'P0002', null, 'A não responde o próprio pedido');

select tests.as_owner();
select is((select count(*)::int from app.notification_outbox where kind = 'connect_received' and recipient_account = tests.id('B')), 1,
          'B recebe e-mail de pedido');
insert into tests.fx(key, id) select 'REQ1', id from app.connect_requests where from_entity = tests.id('E1') and to_entity = tests.id('E2');

-- B vê o pedido, mas não o contato de A
select tests.as_user(tests.id('B'));
select is((select count(*)::int from api.my_connections() where direction = 'in' and status = 'pending'), 1, 'B vê o pedido recebido');
select is((select message from api.my_connections() where direction = 'in'), 'Queremos trocar experiências sobre a horta comunitária.', 'B lê a mensagem');
select is((select other_contact from api.my_connections() where direction = 'in'), null, 'B NÃO vê o contato de A antes de aceitar');
select throws_ok(format('select api.connect_respond(%L, true, null)', tests.id('REQ1')), '22023', null, 'aceitar exige contato');

-- terceiro não vê nada
select tests.as_user(tests.id('C'));
select is((select count(*)::int from api.my_connections()), 0, 'C não vê pedidos alheios');
select throws_ok(format('select api.connect_respond(%L, true, %L)', tests.id('REQ1'), 'c-contato@example.org'), 'P0002', null,
                 'C não responde pedido alheio');

-- B aceita
select tests.as_user(tests.id('B'));
select lives_ok(format('select api.connect_respond(%L, true, %L)', tests.id('REQ1'), 'b-contato@example.org'), 'B aceita');
select is((select other_contact from api.my_connections() where direction = 'in'), 'a-contato@example.org', 'após aceite: B vê contato de A');
select tests.as_user(tests.id('A'));
select is((select other_contact from api.my_connections() where direction = 'out'), 'b-contato@example.org', 'após aceite: A vê contato de B');
select is((select status from api.my_connections() where direction = 'out'), 'accepted', 'status aceito');
select tests.as_user(tests.id('C'));
select is((select count(*)::int from api.my_connections()), 0, 'após aceite: C continua sem ver nada');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox where kind = 'connect_accepted' and recipient_account = tests.id('A')), 1,
          'A recebe e-mail de aceite');

-- pedido para ficha sem gestor: fica guardado e é entregue na reivindicação
select tests.as_user(tests.id('A'));
select lives_ok(format('select api.connect_request(%L, %L, %L, %L)', tests.id('E1'), tests.id('E3'), 'Pedido para ficha ainda não reivindicada.', 'a-contato@example.org'),
                'pedido para ficha sem gestor é aceito');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox o join app.connect_requests r on r.id = o.ref_id
            where o.kind = 'connect_received' and r.to_entity = tests.id('E3')), 0, 'sem gestor: ninguém é notificado ainda');
select tests.as_user(tests.id('C'));
select lives_ok(format('select api.claim_start(%L, %L, %L)', tests.id('E3'), 'manual', 'Sou da coordenação desta iniciativa.'), 'C reivindica E3');
select tests.as_user(tests.id('MOD'));
select lives_ok(format('select api.mod_decide_claim((select c.id from app.claims c where c.entity_id = %L and c.status = %L), true, %L)',
                tests.id('E3'), 'pending', 'Vínculo confirmado por telefone institucional.'), 'moderação aprova a reivindicação de E3');
select tests.as_owner();
select is((select count(*)::int from app.notification_outbox o join app.connect_requests r on r.id = o.ref_id
            where o.kind = 'connect_received' and r.to_entity = tests.id('E3') and o.recipient_account = tests.id('C')), 1,
          'pedido guardado é entregue ao novo gestor');
select tests.as_user(tests.id('C'));
select is((select other_contact from api.my_connections() where direction = 'in'), null, 'novo gestor também não vê contato antes do aceite');

-- ficha que não aceita pedidos: resposta igual, nunca entregue
select tests.as_user(tests.id('A'));
select lives_ok(format('select api.connect_request(%L, %L, %L, %L)', tests.id('E1'), tests.id('E4'), 'Pedido para quem não aceita pedidos.', 'a-contato@example.org'),
                'pedido para ficha que recusa conexões responde igual');
select is((select status from api.my_connections() where direction = 'out' and other_entity_id = tests.id('E4')), 'pending',
          'solicitante vê "pendente" (não revela a configuração)');
select tests.as_user(tests.id('F'));
select is((select count(*)::int from api.my_connections() where direction = 'in'), 0, 'gestor de E4 não recebe o pedido');

select tests.as_owner();
select * from finish();
rollback;
