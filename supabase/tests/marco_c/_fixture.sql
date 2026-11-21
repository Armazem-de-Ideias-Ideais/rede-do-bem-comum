-- Fixture dos testes do Marco C (somente local/CI). Roda como owner DEPOIS de:
-- shim → migrações 0001–0011 → seed público real (build_seed.py) → seed PRIVADO de convites (--private-invites) → helpers.
-- Contas fictícias (domínios .invalid / example.org); entidades escolhidas por consulta, não por código fixo.

insert into auth.users(id, email) values
  ('c0000000-0000-4000-a000-0000000000d1', 'moderacao@example.org'),
  ('c0000000-0000-4000-a000-00000000000a', 'conta-a@example.org'),
  ('c0000000-0000-4000-a000-00000000000b', 'conta-b@example.org'),
  ('c0000000-0000-4000-a000-00000000000c', 'conta-c@example.org'),
  ('c0000000-0000-4000-a000-00000000000e', 'conta-e@example.org'),
  ('c0000000-0000-4000-a000-00000000000f', 'conta-f@example.org');
insert into app.role_grants(account_id, role, granted_by) values
  ('c0000000-0000-4000-a000-0000000000d1', 'moderator', null),
  ('c0000000-0000-4000-a000-0000000000d1', 'curator', null);

create table tests.fx (key text primary key, id uuid, txt text);
grant select, insert on tests.fx to anon, authenticated, service_role;
create function tests.id(p_key text) returns uuid language sql stable as $$ select id from tests.fx where key = p_key $$;
create function tests.txt(p_key text) returns text language sql stable as $$ select txt from tests.fx where key = p_key $$;
-- simula o cabeçalho de IP que o PostgREST repassa (hash com sal diário no banco)
create function tests.ip(p_ip text) returns text language sql as
$$ select '# ip simulado: ' || p_ip || left(set_config('request.headers', jsonb_build_object('cf-connecting-ip', p_ip)::text, true), 0) $$;
grant execute on function tests.id(text), tests.txt(text), tests.ip(text) to anon, authenticated, service_role;

insert into tests.fx(key, id) values
  ('MOD', 'c0000000-0000-4000-a000-0000000000d1'), ('A', 'c0000000-0000-4000-a000-00000000000a'),
  ('B', 'c0000000-0000-4000-a000-00000000000b'), ('C', 'c0000000-0000-4000-a000-00000000000c'),
  ('E', 'c0000000-0000-4000-a000-00000000000e'), ('F', 'c0000000-0000-4000-a000-00000000000f');

-- Par na mesma cidade (cidade pequena), sem família em comum, ambas com local físico: X (retirada) e Y (irmã complementar)
insert into tests.fx(key, id, txt)
select k, id, null from (
  select e1.id as x, e2.id as y from pub.entities e1 join pub.entities e2 on e2.area_id = e1.area_id and e2.id <> e1.id
   where e1.counter_class = 'initiative' and e2.counter_class = 'initiative'
     and exists (select 1 from pub.entity_places ep where ep.entity_id = e1.id)
     and not exists (select 1 from pub.entity_categories c1 join pub.entity_categories c2 on c2.category_id = c1.category_id
                      where c1.entity_id = e1.id and c2.entity_id = e2.id)
     and (select count(*) from pub.entities e3 where e3.area_id = e1.area_id) <= 5
   order by e1.slug limit 1) p,
  lateral (values ('X', p.x), ('Y', p.y)) v(k, id);

-- W: iniciativa com site próprio de domínio não compartilhado (retirada confirmada + tombstone)
insert into tests.fx(key, id, txt)
select 'W', e.id, app.url_domain(e.website_url) from app.entities e
 where e.publication_state = 'published' and e.website_url is not null and not app._is_shared_domain(app.url_domain(e.website_url))
   and e.id not in (select id from tests.fx where id is not null) and e.country_code is not null
 order by e.research_id limit 1;

-- E1..E5: fichas publicadas distintas para Conectar e ofertas
insert into tests.fx(key, id)
select 'E' || row_number() over (order by e.research_id), e.id from app.entities e
 where e.publication_state = 'published' and e.id not in (select id from tests.fx where id is not null)
   and e.website_url is null
 order by e.research_id limit 5;

-- Reivindicação: DA (site com domínio próprio), DB, DC (quaisquer), DN (sem site)
insert into tests.fx(key, id, txt)
select 'DA', e.id, app.url_domain(e.website_url) from app.entities e
 where e.publication_state = 'published' and e.website_url is not null and not app._is_shared_domain(app.url_domain(e.website_url))
   and app.url_domain(e.website_url) ~ '^[a-z0-9.-]+$' and e.id not in (select id from tests.fx where id is not null)
 order by e.research_id desc limit 1;
insert into tests.fx(key, id)
select k, id from (select e.id, row_number() over (order by e.research_id desc) as n from app.entities e
  where e.publication_state = 'published' and e.website_url is null and e.id not in (select id from tests.fx where id is not null)
  order by e.research_id desc limit 3) s,
  lateral (values (case s.n when 1 then 'DB' when 2 then 'DC' else 'DN' end)) v(k);

-- Contadores: PA e PB, duas iniciativas com local físico em cidades diferentes
insert into tests.fx(key, id)
select k, id from (select e.id, row_number() over (order by e.slug) as n from pub.entities e
  where e.counter_class = 'initiative' and exists (select 1 from pub.entity_places ep where ep.entity_id = e.id)
    and e.id not in (select id from tests.fx where id is not null) and e.area_id is not null
  order by e.slug limit 2) s, lateral (values (case s.n when 1 then 'PA' else 'PB' end)) v(k);

-- Candidatos a convite (privados)
insert into tests.fx(key, id)
select 'K' || row_number() over (order by research_id), id from app.invite_candidates order by research_id limit 4;

do $$
begin
  if (select count(*) from tests.fx) <> 24 or exists (select 1 from tests.fx where id is null) then
    raise exception 'fixture incompleta: %', (select string_agg(key, ',') from tests.fx);
  end if;
end $$;
