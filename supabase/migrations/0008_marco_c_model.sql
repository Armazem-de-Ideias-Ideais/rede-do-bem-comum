-- 0008 UP — Marco C: modelo de dados do lançamento público
-- Slugs, campos públicos novos da ficha, retirada preventiva, conexões, contato, indicações,
-- convites (privados) e fila de notificações. Tudo em app (privado) ou pub (projeção).
-- Nenhuma coluna interna da pesquisa (research_notes, lot, exposure, audit) existe no banco.

-- ---------- Configuração ----------
insert into app.settings(key, value) values
  ('ip_salt', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')),  -- sal do hash de IP (rotação diária na função)
  ('takedown_autohide_per_hour', '30')                                                 -- disjuntor da retirada preventiva automática
on conflict (key) do nothing;

-- Domínios de plataformas compartilhadas: um e-mail nesses domínios NÃO prova posse do site.
create table app.shared_domains (domain text primary key check (domain ~ '^[a-z0-9.-]+$'));
insert into app.shared_domains(domain) values
  ('gmail.com'),('googlemail.com'),('google.com'),('sites.google.com'),('outlook.com'),('hotmail.com'),('live.com'),
  ('yahoo.com'),('yahoo.com.br'),('icloud.com'),('me.com'),('aol.com'),('gmx.de'),('gmx.net'),('web.de'),('mail.ru'),
  ('yandex.ru'),('proton.me'),('protonmail.com'),('riseup.net'),('autistici.org'),('disroot.org'),('posteo.de'),
  ('tutanota.com'),('uol.com.br'),('bol.com.br'),('terra.com.br'),('ig.com.br'),('orange.fr'),('free.fr'),('laposte.net'),
  ('libero.it'),('qq.com'),('163.com'),('naver.com'),
  ('facebook.com'),('fb.com'),('instagram.com'),('twitter.com'),('x.com'),('t.me'),('telegram.org'),('youtube.com'),
  ('tiktok.com'),('linkedin.com'),('mastodon.social'),('linktr.ee'),('wordpress.com'),('blogspot.com'),('blogger.com'),
  ('wixsite.com'),('wix.com'),('weebly.com'),('squarespace.com'),('jimdo.com'),('jimdofree.com'),('github.io'),
  ('github.com'),('gitlab.io'),('gitlab.com'),('notion.site'),('medium.com'),('substack.com'),('tumblr.com'),
  ('noblogs.org'),('canalblog.com'),('over-blog.com'),('webnode.com'),('webnode.page'),('carrd.co'),('bandcamp.com'),
  ('meetup.com'),('kartevonmorgen.org'),('openstreetmap.org'),('wikipedia.org'),('google.org');

-- ---------- Entidades: campos públicos novos ----------
alter table app.entities
  add column slug           text,
  add column research_id    text,                       -- código interno da pesquisa (nunca projetado)
  add column website_url    text check (website_url ~ '^https?://[^\s<>"]+$' and char_length(website_url) <= 500),
  add column city           text check (char_length(city) <= 120),
  add column world_region   text check (char_length(world_region) <= 60),
  add column activity_badge text not null default 'to_confirm'
             check (activity_badge in ('active_recent','source_checked','to_confirm')),
  add column network_of     text check (char_length(network_of) <= 200),
  add column alt_names      text[] not null default '{}' check (cardinality(alt_names) <= 10),
  add column attribution    text check (char_length(attribution) <= 300),
  add column accepts_connections boolean not null default true,
  add constraint entities_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 80);
create unique index entities_slug_uniq on app.entities (slug);
create unique index entities_research_id_uniq on app.entities (research_id);

-- Slugs antigos (renomeação): continuam resolvendo para a ficha atual.
create table app.entity_slug_history (
  slug       text primary key check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  entity_id  uuid not null references app.entities(id) on delete cascade,
  created_at timestamptz not null default now()
);

create function app.slugify(p text) returns text
language sql immutable parallel safe strict set search_path = '' as $$
  select btrim(left(btrim(regexp_replace(pub.norm(p), '[^a-z0-9]+', '-', 'g'), '-'), 60), '-')
$$;

create function app._slug_taken(p_slug text, p_id uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from app.entities where slug = p_slug and id <> p_id)
      or exists (select 1 from app.entity_slug_history where slug = p_slug and entity_id <> p_id)
$$;

-- Regra: nome sem acentos; colisão → -<país>; depois -2, -3...; sem letras latinas → outro nome ou <país>-<8 hex>.
create function app._unique_slug(p_name text, p_country text, p_id uuid, p_alt text[] default '{}') returns text
language plpgsql stable set search_path = '' as $$
declare v_base text; v_cand text; v_n integer := 2; a text; v_cc text := lower(nullif(btrim(coalesce(p_country, '')), ''));
begin
  v_base := app.slugify(p_name);
  if v_base is null or char_length(v_base) < 3 then
    v_base := null;
    foreach a in array coalesce(p_alt, '{}') loop
      if char_length(coalesce(app.slugify(a), '')) >= 3 then v_base := app.slugify(a); exit; end if;
    end loop;
  end if;
  if v_base is null then
    return coalesce(v_cc, 'xx') || '-' || left(replace(p_id::text, '-', ''), 8);
  end if;
  v_cand := v_base;
  if app._slug_taken(v_cand, p_id) and v_cc is not null then v_cand := v_base || '-' || v_cc; end if;
  while app._slug_taken(v_cand, p_id) loop
    v_cand := v_base || coalesce('-' || v_cc, '') || '-' || v_n;
    v_n := v_n + 1;
  end loop;
  return v_cand;
end $$;

create function app.trg_entity_slug() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.slug is null then new.slug := app._unique_slug(new.original_name, new.country_code, new.id, new.alt_names); end if;
  elsif new.original_name is distinct from old.original_name and new.slug is not distinct from old.slug
        and old.slug is not null then
    -- renomeação aprovada: novo slug, o antigo vira redirecionamento
    insert into app.entity_slug_history(slug, entity_id) values (old.slug, old.id) on conflict (slug) do nothing;
    new.slug := app._unique_slug(new.original_name, new.country_code, new.id, new.alt_names);
  end if;
  return new;
end $$;
create trigger entity_slug before insert or update of original_name on app.entities
  for each row execute function app.trg_entity_slug();

-- Preenche slugs de entidades já existentes (ex.: seed sintético anterior a esta migração).
update app.entities set slug = app._unique_slug(original_name, country_code, id, alt_names) where slug is null;

-- ---------- Projeção pública: colunas novas ----------
alter table pub.entities
  add column slug               text,
  add column website_url        text,
  add column city               text,
  add column world_region       text,
  add column activity_badge     text,
  add column network_of         text,
  add column alt_names          text[] not null default '{}',
  add column attribution        text,
  add column is_managed         boolean not null default false,
  add column location_precision text not null default 'none',
  add column lon                numeric,
  add column lat                numeric,
  add column search_text        text not null default '';
create unique index pub_entities_slug on pub.entities (slug);
create index pub_entities_area on pub.entities (area_id);

create table pub.slug_redirects (
  slug      text primary key,
  entity_id uuid not null
);
create index on pub.slug_redirects (entity_id);

-- ---------- Ofertas e necessidades: tema ----------
alter table app.offers_needs
  add column topic text not null default 'other'
             check (topic in ('tools','space','volunteering','knowledge','materials','other')),
  add column updated_at timestamptz not null default now();
alter table pub.offers_needs
  add column topic        text not null default 'other',
  add column published_at timestamptz not null default now();

-- ---------- Reivindicação: três caminhos ----------
alter table app.claims drop constraint claims_status_check;
alter table app.claims add constraint claims_status_check
  check (status in ('pending','approved','rejected','withdrawn','awaiting_code','awaiting_evidence','failed'));
alter table app.claims
  add column method          text not null default 'manual' check (method in ('domain_email','published_code','manual')),
  add column verify_domain   text,
  add column verify_email    text check (char_length(verify_email) <= 254),   -- apagado ao concluir
  add column code_hash       text,
  add column code_expires_at timestamptz,
  add column code_attempts   integer not null default 0,
  add column published_code  text,
  add column evidence_url    text check (evidence_url ~ '^https://[^\s<>"]+$' and char_length(evidence_url) <= 500),
  add column verified_at     timestamptz;
create unique index claims_one_open on app.claims (entity_id, claimant_id)
  where status in ('awaiting_code','awaiting_evidence','pending');
-- defesa em profundidade: o hash do código nunca é legível pela conta
revoke select on app.claims from authenticated;
grant select (id, entity_id, claimant_id, statement, status, decided_by, decided_at, rationale, created_at,
              method, verify_domain, code_expires_at, published_code, evidence_url, verified_at)
  on app.claims to authenticated;

-- ---------- Retirada preventiva ----------
create table app.takedown_requests (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid references app.entities(id) on delete set null,
  reason      text not null check (char_length(reason) between 10 and 2000),
  relation    text not null check (relation in ('representative','member','mentioned','other')),
  contact     text check (char_length(contact) <= 200),
  locale      text not null default 'pt' check (locale in ('pt','en','es')),
  account_id  uuid references app.accounts(id) on delete set null,
  ip_hash     text,
  auto_hidden boolean not null default false,
  status      text not null default 'open' check (status in ('open','confirmed','restored','closed_kept_hidden')),
  decided_by  uuid references app.accounts(id) on delete set null,
  decided_at  timestamptz,
  rationale   text check (char_length(rationale) <= 2000),
  created_at  timestamptz not null default now()
);
create index on app.takedown_requests (status, created_at);
create index on app.takedown_requests (entity_id);

-- ---------- Conectar (pedido mediado) ----------
create table app.connect_requests (
  id           uuid primary key default gen_random_uuid(),
  from_entity  uuid not null references app.entities(id) on delete cascade,
  to_entity    uuid not null references app.entities(id) on delete cascade,
  from_account uuid references app.accounts(id) on delete set null,
  message      text not null check (char_length(message) between 10 and 1000),
  from_contact text not null check (char_length(from_contact) between 5 and 300),
  to_contact   text check (char_length(to_contact) between 5 and 300),
  status       text not null default 'pending'
               check (status in ('pending','accepted','declined','cancelled','expired','blocked')),
  delivered_at timestamptz,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '180 days',
  decided_at   timestamptz,
  decided_by   uuid references app.accounts(id) on delete set null,
  check (from_entity <> to_entity)
);
create unique index connect_one_open on app.connect_requests (from_entity, to_entity) where status in ('pending','blocked');
create index on app.connect_requests (to_entity, status);

-- ---------- Formulário de contato ----------
create table app.contact_messages (
  id           uuid primary key default gen_random_uuid(),
  sender_name  text not null check (char_length(sender_name) between 2 and 120),
  sender_email text not null check (char_length(sender_email) <= 254 and sender_email ~* '^[^@\s<>"]+@[^@\s<>"]+\.[a-z]{2,}$'),
  subject      text not null check (char_length(subject) between 3 and 150),
  body         text not null check (char_length(body) between 10 and 5000),
  locale       text not null default 'pt' check (locale in ('pt','en','es')),
  account_id   uuid references app.accounts(id) on delete set null,
  ip_hash      text,
  status       text not null default 'new' check (status in ('new','read','answered','spam')),
  handled_by   uuid references app.accounts(id) on delete set null,
  handled_at   timestamptz,
  created_at   timestamptz not null default now()
);
create index on app.contact_messages (status, created_at);

-- ---------- Indicar uma iniciativa (fila editorial) ----------
create table app.suggestions (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 2 and 180),
  website      text check (website ~ '^https?://[^\s<>"]+$' and char_length(website) <= 500),
  country_code char(2) check (country_code ~ '^[A-Z]{2}$'),
  city         text check (char_length(city) <= 120),
  families     text[] not null default '{}' check (cardinality(families) <= 5),
  description  text not null check (char_length(description) between 10 and 2000),
  why          text check (char_length(why) <= 2000),
  contact      text check (char_length(contact) <= 200),
  locale       text not null default 'pt' check (locale in ('pt','en','es')),
  account_id   uuid references app.accounts(id) on delete set null,
  ip_hash      text,
  status       text not null default 'new' check (status in ('new','accepted','rejected','duplicate')),
  note         text check (char_length(note) <= 2000),
  handled_by   uuid references app.accounts(id) on delete set null,
  handled_at   timestamptz,
  created_at   timestamptz not null default now()
);
create index on app.suggestions (status, created_at);

-- ---------- Convites para fichas de exposição alta (PRIVADO) ----------
-- Os candidatos nunca são lidos por views, funções públicas, contadores, busca ou exportação.
create table app.invite_candidates (
  id          uuid primary key,
  research_id text not null unique,
  data        jsonb not null check (jsonb_typeof(data) = 'object'),
  status      text not null default 'pending' check (status in ('pending','invited','accepted','declined','withdrawn')),
  entity_id   uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table app.invitations (
  id           uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references app.invite_candidates(id) on delete cascade,
  token_hash   text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),   -- token só existe em claro na resposta ao moderador
  status       text not null default 'pending' check (status in ('pending','accepted','declined','revoked','expired')),
  expires_at   timestamptz not null,
  used_at      timestamptz,
  used_by      uuid references app.accounts(id) on delete set null,
  created_by   uuid references app.accounts(id) on delete set null,
  created_at   timestamptz not null default now()
);
create unique index invitations_one_pending on app.invitations (candidate_id) where status = 'pending';

-- ---------- Fila de notificações por e-mail (consumida pela Edge Function) ----------
create table app.notification_outbox (
  id                bigint generated always as identity primary key,
  kind              text not null check (kind in ('connect_received','connect_accepted','claim_code','claim_pending',
                      'claim_approved','claim_rejected','takedown_request','contact_message','invite_accepted')),
  recipient_account uuid references app.accounts(id) on delete cascade,
  to_moderator      boolean not null default false,
  ref_id            uuid,
  entity_id         uuid,
  locale            text not null default 'pt' check (locale in ('pt','en','es')),
  created_at        timestamptz not null default now(),
  claimed_at        timestamptz,
  sent_at           timestamptz,
  attempts          integer not null default 0,
  last_error        text check (char_length(last_error) <= 500)
);
create index notification_outbox_pending on app.notification_outbox (id) where sent_at is null;

-- Dados de vida curta (código e endereço da reivindicação por e-mail). Apagados ao enviar.
-- Tabela separada para que o webhook (que recebe a linha do outbox) não os transporte.
create table app.notification_secrets (
  outbox_id  bigint primary key references app.notification_outbox(id) on delete cascade,
  data       jsonb not null,
  created_at timestamptz not null default now()
);

-- ---------- RLS e privilégios das tabelas novas ----------
-- Sem GRANT para anon/authenticated: acesso só por funções DEFINER verificadas (e service_role).
do $$
declare t text;
begin
  foreach t in array array['shared_domains','entity_slug_history','takedown_requests','connect_requests',
    'contact_messages','suggestions','invite_candidates','invitations','notification_outbox','notification_secrets'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant select, insert, update, delete on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

alter table pub.slug_redirects enable row level security;
grant select on pub.slug_redirects to anon, authenticated;
grant select, insert, update, delete on pub.slug_redirects to service_role;
create policy public_read on pub.slug_redirects for select to anon, authenticated using (true);

revoke all on function app.slugify(text), app._slug_taken(text, uuid), app._unique_slug(text, text, uuid, text[]),
  app.trg_entity_slug() from public;
-- o trigger de slug roda com o papel de quem insere (funções owner ou service_role)
grant execute on function app.slugify(text), app._slug_taken(text, uuid), app._unique_slug(text, text, uuid, text[])
  to service_role;
