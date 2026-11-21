-- =====================================================================
-- seed_synthetic.sql — DADOS SINTÉTICOS DE DESENVOLVIMENTO
-- Tudo aqui é FICTÍCIO: nomes com prefixo [SINTÉTICO], país "XX"/"XY" (códigos ISO
-- reservados para uso privado), coordenadas em pleno Oceano Atlântico, domínios .invalid.
-- Nenhuma organização, pessoa ou lugar real. is_synthetic = true em todas as linhas.
-- PROIBIDO em produção (trigger no_synthetic_in_prod bloqueia se environment=production).
-- Executar como owner das migrações (postgres), após as migrações up.
-- =====================================================================
begin;

-- ---------- Contas fictícias (auth.users só existe localmente via shim; no Supabase use o seed do CLI) ----------
insert into auth.users(id, email) values
  ('00000000-0000-4000-a000-00000000000a', 'conta.a@exemplo.invalid'),
  ('00000000-0000-4000-a000-00000000000b', 'conta.b@exemplo.invalid'),
  ('00000000-0000-4000-a000-0000000000c1', 'curadoria.xx@exemplo.invalid'),
  ('00000000-0000-4000-a000-0000000000c2', 'curadoria.xy@exemplo.invalid'),
  ('00000000-0000-4000-a000-0000000000d1', 'moderacao@exemplo.invalid'),
  ('00000000-0000-4000-a000-0000000000e1', 'administracao@exemplo.invalid'),
  ('00000000-0000-4000-a000-0000000000f1', 'gestao.aurora@exemplo.invalid'),
  ('00000000-0000-4000-a000-000000000011', 'pessoa.publica@exemplo.invalid'),
  ('00000000-0000-4000-a000-000000000012', 'pessoa.reservada@exemplo.invalid');
-- app.accounts é criado pelo trigger on_auth_user_created_rbc.

-- Bootstrap de papéis (granted_by null = operador, auditado)
insert into app.role_grants(account_id, role, scope_country, granted_by) values
  ('00000000-0000-4000-a000-0000000000e1', 'admin',     null, null),
  ('00000000-0000-4000-a000-0000000000c1', 'curator',   'XX', '00000000-0000-4000-a000-0000000000e1'),
  ('00000000-0000-4000-a000-0000000000c2', 'curator',   'XY', '00000000-0000-4000-a000-0000000000e1'),
  ('00000000-0000-4000-a000-0000000000d1', 'moderator', null, '00000000-0000-4000-a000-0000000000e1');
insert into app.audit_log(actor, action, target_table, details)
values (null, 'role.bootstrap', 'role_grants', '{"note":"seed sintético"}');

-- ---------- Taxonomia (do kit) ----------
insert into pub.categories(id, label_pt, label_en) values
  ('autonomous_spaces','Espaços autônomos e centros sociais','Autonomous spaces and social centres'),
  ('books_libraries','Livrarias bibliotecas e arquivos','Bookshops libraries and archives'),
  ('publishing_print','Editoras gráficas e zines','Publishing print and zines'),
  ('independent_media','Mídias livres e comunicação','Independent media and communication'),
  ('worker_coops','Trabalho autogerido e cooperativas','Self managed work and worker coops'),
  ('consumer_coops','Consumo cooperativo e abastecimento','Consumer coops and food retail'),
  ('agroecology','Agroecologia e soberania alimentar','Agroecology and food sovereignty'),
  ('food_solidarity','Cozinhas solidárias e partilha de alimentos','Community kitchens and food sharing'),
  ('housing_communities','Moradia comunidades e ocupações','Housing communities and occupations'),
  ('repair_reuse','Reparo reúso e oficinas','Repair reuse and workshops'),
  ('libraries_things','Tudotecas e bibliotecas de ferramentas','Libraries of things and tool libraries'),
  ('gift_exchange','Doação troca e economia da dádiva','Gifting exchange and gift economy'),
  ('mutual_aid','Apoio mútuo e solidariedade','Mutual aid and solidarity'),
  ('health_care','Saúde cuidado e apoio psicossocial','Health care and psychosocial support'),
  ('free_education','Educação livre e aprendizagem','Free education and learning'),
  ('arts_culture','Arte cultura e convivialidade','Arts culture and conviviality'),
  ('shared_mobility','Mobilidade compartilhada e ciclismo','Shared mobility and cycling'),
  ('commons_infrastructure','Água energia resíduos e infraestrutura','Water energy waste and infrastructure'),
  ('digital_commons','Software livre e bens comuns digitais','Free software and digital commons'),
  ('community_connectivity','Internet comunitária e redes federadas','Community internet and federated networks'),
  ('solidarity_finance','Finanças solidárias e moedas sociais','Solidarity finance and community currencies'),
  ('conflict_care','Mediação e cuidado de conflitos','Mediation and conflict care'),
  ('labour_organising','Sindicalismo e organização do trabalho','Labour organising and syndicalism'),
  ('ecology_land','Ecologia territórios e bens comuns','Ecology land and commons')
on conflict do nothing;

insert into pub.practices(id, label_pt, label_en) values
  ('assembly_decisions','Decisão em assembleia','Assembly decision-making'),
  ('free_lending','Empréstimo gratuito','Free lending'),
  ('shared_meals','Refeições coletivas','Shared meals'),
  ('open_repair','Reparo aberto','Open repair')
on conflict do nothing;

-- ---------- Geografia fictícia (Atlântico, sem terra firme) ----------
insert into pub.areas(id, level, parent_id, country_code, name, label_point, is_synthetic) values
  ('xx',               'country', null,            'XX', '[SINTÉTICO] País Exemplar',     extensions.st_setsrid(extensions.st_makepoint(-25.0, -5.0), 4326), true),
  ('xx-regiao-norte',  'region',  'xx',            'XX', '[SINTÉTICO] Região Norte',      extensions.st_setsrid(extensions.st_makepoint(-24.5, -4.5), 4326), true),
  ('xx-vila-aurora',   'city',    'xx-regiao-norte','XX', '[SINTÉTICO] Vila Aurora',      extensions.st_setsrid(extensions.st_makepoint(-25.0, -5.0), 4326), true),
  ('xx-vila-brisa',    'city',    'xx-regiao-norte','XX', '[SINTÉTICO] Vila Brisa',       extensions.st_setsrid(extensions.st_makepoint(-24.0, -4.0), 4326), true),
  ('xy',               'country', null,            'XY', '[SINTÉTICO] Outro País',        extensions.st_setsrid(extensions.st_makepoint(-20.0, -8.0), 4326), true),
  ('xy-regiao-sul',    'region',  'xy',            'XY', '[SINTÉTICO] Região Sul',        extensions.st_setsrid(extensions.st_makepoint(-20.0, -8.5), 4326), true),
  ('xy-vila-coral',    'city',    'xy-regiao-sul', 'XY', '[SINTÉTICO] Vila Coral',        extensions.st_setsrid(extensions.st_makepoint(-20.2, -8.6), 4326), true);

-- ---------- Fonte fictícia ----------
insert into app.sources(id, name, base_url, domain, licence, adapter_allowed) values
  ('00000000-0000-4000-b000-000000000001', '[SINTÉTICO] Diretório Exemplar', 'https://diretorio.exemplo.invalid',
   'diretorio.exemplo.invalid', 'CC-BY-4.0 (fictícia)', true);

-- ---------- Locais ----------
insert into app.places(id, kind, area_id, geom_exact, address_private, precision, is_sensitive, activity_state, publication_state, is_synthetic) values
  -- P1: local público exato, COMPARTILHADO por E1 e E2
  ('00000000-0000-4000-c000-000000000001', 'physical_venue', 'xx-vila-aurora',
   extensions.st_setsrid(extensions.st_makepoint(-25.012345, -5.012345), 4326), 'Rua Fictícia, 1', 'exact_public_venue', false, 'active', 'published', true),
  -- P2: precisão CIDADE (ponto exato privado ≠ ponto público)
  ('00000000-0000-4000-c000-000000000002', 'physical_venue', 'xx-vila-brisa',
   extensions.st_setsrid(extensions.st_makepoint(-24.031415, -4.027182), 4326), 'Travessa Inventada, 77', 'city', false, 'active', 'published', true),
  -- P3: área territorial, precisão região
  ('00000000-0000-4000-c000-000000000003', 'territorial_area', 'xx-regiao-norte', null, null, 'region', false, 'active', 'published', true),
  -- P4: local SENSÍVEL (ocupação) — só região
  ('00000000-0000-4000-c000-000000000004', 'physical_venue', 'xx-vila-aurora',
   extensions.st_setsrid(extensions.st_makepoint(-25.111111, -5.222222), 4326), 'Endereço reservado', 'region', true, 'active', 'published', true),
  -- P5: local no país XY
  ('00000000-0000-4000-c000-000000000005', 'physical_venue', 'xy-vila-coral',
   extensions.st_setsrid(extensions.st_makepoint(-20.21, -8.61), 4326), null, 'exact_public_venue', false, 'active', 'published', true),
  -- P6: local da ficha oculta
  ('00000000-0000-4000-c000-000000000006', 'physical_venue', 'xx-vila-brisa',
   extensions.st_setsrid(extensions.st_makepoint(-24.1, -4.1), 4326), null, 'exact_public_venue', false, 'active', 'published', true);

-- ---------- Entidades ----------
insert into app.entities(id, kind, presence_type, original_name, original_lang, country_code, area_id, public_contact_url,
  access_conditions, research_state, activity_state, participation_state, verification_label,
  last_activity_verified_at, source_accessed_at, rights_basis, export_permission, created_by, is_synthetic) values
  ('00000000-0000-4000-e000-000000000001','collective','physical','[SINTÉTICO] Centro Social Aurora','pt','XX','xx-vila-aurora',
   'https://aurora.exemplo.invalid', '{"access":"open"}','sufficient_evidence','active','representative_confirmed','holder_confirmed',
   current_date - 20, current_date - 20, 'autodeclaração da iniciativa (fictícia)', true, null, true),
  ('00000000-0000-4000-e000-000000000002','library','physical','[SINTÉTICO] Biblioteca Comunitária Maré','pt','XX','xx-vila-aurora',
   'https://mare.exemplo.invalid', '{"access":"open"}','sufficient_evidence','active','not_requested','activity_checked',
   current_date - 40, current_date - 40, 'fonte institucional com licença compatível (fictícia)', false, null, true),
  ('00000000-0000-4000-e000-000000000003','cooperative','physical','[SINTÉTICO] Cooperativa Brisa','pt','XX','xx-vila-brisa',
   'https://brisa.exemplo.invalid', '{"access":"by_appointment"}','sufficient_evidence','active','not_requested','activity_checked',
   current_date - 10, current_date - 10, 'fonte institucional (fictícia)', false, null, true),
  ('00000000-0000-4000-e000-000000000004','network','nonspatial','[SINTÉTICO] Rede Exemplar de Apoio Mútuo','pt',null,null,
   'https://rede.exemplo.invalid', '{}','sufficient_evidence','active','not_requested','source_checked',
   current_date - 15, current_date - 15, 'fonte institucional (fictícia)', true, null, true),
  ('00000000-0000-4000-e000-000000000005','resource','online','[SINTÉTICO] Acervo Digital Livre','pt','XX',null,
   'https://acervo.exemplo.invalid', '{}','sufficient_evidence','active','not_requested','source_checked',
   current_date - 15, current_date - 15, 'fonte institucional (fictícia)', false, null, true),
  ('00000000-0000-4000-e000-000000000006','collective','territorial','[SINTÉTICO] Coletivo Territorial Norte','pt','XX','xx-regiao-norte',
   null, '{}','sufficient_evidence','active','not_requested','activity_checked',
   current_date - 30, current_date - 30, 'fonte institucional (fictícia)', false, null, true),
  ('00000000-0000-4000-e000-000000000007','community','physical','[SINTÉTICO] Ocupação Esperança','pt','XX','xx-regiao-norte',
   null, '{"access":"invitation"}','sufficient_evidence','active','representative_confirmed','holder_confirmed',
   current_date - 5, current_date - 5, 'acordo com responsáveis (fictício)', false, null, true),
  ('00000000-0000-4000-e000-000000000008','collective','physical','[SINTÉTICO] Ficha Oculta Preventivamente','pt','XX','xx-vila-brisa',
   'https://oculta.exemplo.invalid', '{}','sufficient_evidence','active','not_requested','activity_checked',
   current_date - 5, current_date - 5, 'fonte institucional (fictícia)', false, null, true),
  ('00000000-0000-4000-e000-000000000009','collective','physical','[SINTÉTICO] Rascunho da Conta B','pt','XX','xx-vila-aurora',
   'https://rascunho-b.exemplo.invalid', '{}','triage','unconfirmed','not_requested','found',
   null, null, null, false, '00000000-0000-4000-a000-00000000000b', true),
  ('00000000-0000-4000-e000-000000000010','collective','physical','[SINTÉTICO] Rascunho da Conta A','pt','XX','xx-vila-aurora',
   null, '{}','triage','unconfirmed','not_requested','found',
   null, null, null, false, '00000000-0000-4000-a000-00000000000a', true),
  ('00000000-0000-4000-e000-000000000011','cooperative','physical','[SINTÉTICO] Cooperativa Coral','pt','XY','xy-vila-coral',
   'https://coral.exemplo.invalid', '{}','sufficient_evidence','active','not_requested','activity_checked',
   current_date - 12, current_date - 12, 'fonte institucional (fictícia)', false, null, true),
  ('00000000-0000-4000-e000-000000000012','person','nonspatial','[SINTÉTICO] Pessoa Sem Adesão','pt','XX',null,
   null, '{}','triage','unconfirmed','not_requested','found',
   null, null, null, false, null, true);

-- manutenção dos estados para rascunhos
update app.entities set publication_state = 'draft' where id in ('00000000-0000-4000-e000-000000000009','00000000-0000-4000-e000-000000000010','00000000-0000-4000-e000-000000000012');

insert into app.entity_texts(entity_id, field, lang, body, state) values
  ('00000000-0000-4000-e000-000000000001','description','pt','Centro social fictício com biblioteca, cozinha solidária e assembleias abertas.','original'),
  ('00000000-0000-4000-e000-000000000001','description','en','Fictional social centre with a library, solidarity kitchen and open assemblies.','human_reviewed'),
  ('00000000-0000-4000-e000-000000000002','description','pt','Biblioteca comunitária fictícia que divide o espaço com o centro social.','original'),
  ('00000000-0000-4000-e000-000000000002','description','en','Fictional community library sharing the social centre space.','machine_unreviewed'),
  ('00000000-0000-4000-e000-000000000003','description','pt','Cooperativa de trabalho fictícia de reparo e reúso.','original'),
  ('00000000-0000-4000-e000-000000000009','description','pt','Rascunho privado da conta B — não deve vazar.','original');

insert into app.entity_categories(entity_id, category_id, is_primary) values
  ('00000000-0000-4000-e000-000000000001','autonomous_spaces', true),
  ('00000000-0000-4000-e000-000000000001','books_libraries', false),
  ('00000000-0000-4000-e000-000000000001','food_solidarity', false),
  ('00000000-0000-4000-e000-000000000002','books_libraries', true),
  ('00000000-0000-4000-e000-000000000003','worker_coops', true),
  ('00000000-0000-4000-e000-000000000003','repair_reuse', false),
  ('00000000-0000-4000-e000-000000000004','mutual_aid', true),
  ('00000000-0000-4000-e000-000000000005','digital_commons', true),
  ('00000000-0000-4000-e000-000000000006','ecology_land', true),
  ('00000000-0000-4000-e000-000000000007','housing_communities', true),
  ('00000000-0000-4000-e000-000000000008','mutual_aid', true),
  ('00000000-0000-4000-e000-000000000011','worker_coops', true);

insert into app.entity_practices(entity_id, practice_id, evidence_state) values
  ('00000000-0000-4000-e000-000000000001','assembly_decisions','evidenced'),
  ('00000000-0000-4000-e000-000000000001','shared_meals','declared'),
  ('00000000-0000-4000-e000-000000000002','free_lending','evidenced'),
  ('00000000-0000-4000-e000-000000000003','open_repair','evidenced');

insert into app.entity_places(entity_id, place_id, role) values
  ('00000000-0000-4000-e000-000000000001','00000000-0000-4000-c000-000000000001','venue'),
  ('00000000-0000-4000-e000-000000000002','00000000-0000-4000-c000-000000000001','shared'),
  ('00000000-0000-4000-e000-000000000003','00000000-0000-4000-c000-000000000002','venue'),
  ('00000000-0000-4000-e000-000000000006','00000000-0000-4000-c000-000000000003','activity_point'),
  ('00000000-0000-4000-e000-000000000007','00000000-0000-4000-c000-000000000004','venue'),
  ('00000000-0000-4000-e000-000000000008','00000000-0000-4000-c000-000000000006','venue'),
  ('00000000-0000-4000-e000-000000000011','00000000-0000-4000-c000-000000000005','venue');

insert into app.entity_relationships(from_entity, to_entity, kind, public_authorised) values
  ('00000000-0000-4000-e000-000000000001','00000000-0000-4000-e000-000000000004','part_of', true),
  ('00000000-0000-4000-e000-000000000003','00000000-0000-4000-e000-000000000004','part_of', false);  -- vínculo RESTRITO

insert into app.entity_managers(entity_id, account_id, status, verified_by, verified_at) values
  ('00000000-0000-4000-e000-000000000001','00000000-0000-4000-a000-0000000000f1','active','00000000-0000-4000-a000-0000000000c1', now()),
  ('00000000-0000-4000-e000-000000000009','00000000-0000-4000-a000-00000000000b','active','00000000-0000-4000-a000-0000000000c1', now()),
  ('00000000-0000-4000-e000-000000000010','00000000-0000-4000-a000-00000000000a','pending_verification', null, null);

insert into app.entity_aliases(old_id, entity_id) values
  ('00000000-0000-4000-e000-000000000099','00000000-0000-4000-e000-000000000001');

insert into app.entity_versions(id, entity_id, version_no, base_version_no, author_id, payload) values
  ('00000000-0000-4000-f000-00000000000b','00000000-0000-4000-e000-000000000009',1,0,'00000000-0000-4000-a000-00000000000b',
   '{"name":"[SINTÉTICO] Rascunho da Conta B","contact_url":"https://rascunho-b.exemplo.invalid"}'),
  ('00000000-0000-4000-f000-00000000000a','00000000-0000-4000-e000-000000000010',1,0,'00000000-0000-4000-a000-00000000000a',
   '{"name":"[SINTÉTICO] Rascunho da Conta A"}');

-- Proveniência, evidências e revisões para as fichas publicáveis
insert into app.source_records(source_id, external_id, url, accessed_at, licence, payload, entity_id, public_ref_safe)
select '00000000-0000-4000-b000-000000000001', 'ext-' || right(e.id::text, 3),
       'https://diretorio.exemplo.invalid/item/' || right(e.id::text, 3), current_date - 20,
       'CC-BY-4.0 (fictícia)', jsonb_build_object('name', e.original_name), e.id, e.kind <> 'community'
  from app.entities e where e.id in ('00000000-0000-4000-e000-000000000001','00000000-0000-4000-e000-000000000002',
    '00000000-0000-4000-e000-000000000003','00000000-0000-4000-e000-000000000004','00000000-0000-4000-e000-000000000005',
    '00000000-0000-4000-e000-000000000006','00000000-0000-4000-e000-000000000007','00000000-0000-4000-e000-000000000008',
    '00000000-0000-4000-e000-000000000011');

insert into app.field_provenance(entity_id, field_name, origin, source_record_id, licence, participant_managed)
select sr.entity_id, 'name', 'source', sr.id, sr.licence, false from app.source_records sr;

insert into app.evidence(entity_id, kind, level, url, observed_at, note, created_by)
select id, 'primary_page_read', 'E2', 'https://diretorio.exemplo.invalid/item/' || right(id::text, 3), current_date - 10,
       'Página própria fictícia consultada',
       case when country_code = 'XY' then '00000000-0000-4000-a000-0000000000c2'::uuid else '00000000-0000-4000-a000-0000000000c1'::uuid end
  from app.entities where research_state = 'sufficient_evidence';

insert into app.reviews(entity_id, reviewer_id, kind, decision, rationale)
select id, case when country_code = 'XY' then '00000000-0000-4000-a000-0000000000c2'::uuid else '00000000-0000-4000-a000-0000000000c1'::uuid end,
       'activity', 'approve', 'Atividade conferida em fonte própria fictícia.'
  from app.entities where research_state = 'sufficient_evidence';

-- ---------- Ofertas e necessidades ----------
insert into app.offers_needs(entity_id, kind, title, valid_from, valid_until, visibility, publication_state) values
  ('00000000-0000-4000-e000-000000000001','offer','[SINTÉTICO] Empréstimo de ferramentas', current_date, current_date + 30, 'public','published'),
  ('00000000-0000-4000-e000-000000000001','need','[SINTÉTICO] Necessidade vencida', current_date - 60, current_date - 1, 'public','published'),
  ('00000000-0000-4000-e000-000000000001','offer','[SINTÉTICO] Oferta restrita', current_date, current_date + 30, 'restricted','published');

-- ---------- Autorizações e identidade política (somente autodeclarada) ----------
-- Gestão de E1 declara identidade institucional, com autorização específica.
insert into app.consent_records(id, account_id, purpose, decision, text_version, entity_id) values
  ('00000000-0000-4000-d000-000000000001','00000000-0000-4000-a000-0000000000f1','political_identity_public','granted','pi-2026-11','00000000-0000-4000-e000-000000000001'),
  ('00000000-0000-4000-d000-000000000002','00000000-0000-4000-a000-0000000000f1','institutional_export','granted','exp-2026-11','00000000-0000-4000-e000-000000000001'),
  -- Pessoa pública: apresentação + cidade + identidade
  ('00000000-0000-4000-d000-000000000011','00000000-0000-4000-a000-000000000011','public_presentation','granted','pp-2026-11', null),
  ('00000000-0000-4000-d000-000000000012','00000000-0000-4000-a000-000000000011','location_city_region','granted','loc-2026-11', null),
  ('00000000-0000-4000-d000-000000000013','00000000-0000-4000-a000-000000000011','political_identity_public','granted','pi-2026-11', null),
  -- Pessoa reservada: recusou apresentação pública
  ('00000000-0000-4000-d000-000000000021','00000000-0000-4000-a000-000000000012','public_presentation','denied','pp-2026-11', null);

insert into app.profiles(account_id, public_id, pseudonym, bio, area_id, precision, is_synthetic) values
  ('00000000-0000-4000-a000-000000000011','00000000-0000-4000-9000-000000000011','[SINTÉTICO] Pseudônimo Público','Perfil fictício.','xx-vila-aurora','city', true),
  ('00000000-0000-4000-a000-000000000012','00000000-0000-4000-9000-000000000012','[SINTÉTICO] Pseudônimo Reservado','Perfil fictício reservado.','xx-vila-brisa','city', true);

insert into app.political_identity_declarations(consent_id, entity_id, profile_account_id, labels) values
  ('00000000-0000-4000-d000-000000000001','00000000-0000-4000-e000-000000000001', null, array['[SINTÉTICO] autogestão']),
  ('00000000-0000-4000-d000-000000000013', null, '00000000-0000-4000-a000-000000000011', array['[SINTÉTICO] ecossocialismo']);

insert into app.translation_tasks(entity_id, profile_account_id, field_name, target_lang) values
  ('00000000-0000-4000-e000-000000000001', null, 'political_identity', 'en'),
  (null, '00000000-0000-4000-a000-000000000011', 'political_identity', 'en'),
  ('00000000-0000-4000-e000-000000000001', null, 'description', 'es');

-- ---------- Relatos e reivindicações ----------
insert into app.reports(kind, entity_id, body, reporter_account, reporter_contact, priority) values
  ('exposure','00000000-0000-4000-e000-000000000007','[SINTÉTICO] Relato de exposição de local sensível.', null, 'contato-reservado@exemplo.invalid', 1),
  ('correction','00000000-0000-4000-e000-000000000003','[SINTÉTICO] Correção de horário enviada pela conta B.', '00000000-0000-4000-a000-00000000000b', null, 3);

insert into app.claims(entity_id, claimant_id, statement) values
  ('00000000-0000-4000-e000-000000000003','00000000-0000-4000-a000-00000000000a','[SINTÉTICO] Represento esta cooperativa fictícia.');

-- ---------- Publicação (pelas regras de publicação; sem atalho) ----------
select app._publish_entity(id) from app.entities
 where research_state = 'sufficient_evidence' order by id;

-- E8: oculta preventivamente após publicação
update app.entities set publication_state = 'hidden' where id = '00000000-0000-4000-e000-000000000008';
select app._project_entity('00000000-0000-4000-e000-000000000008');

select app._project_profile(account_id) from app.profiles;

commit;
