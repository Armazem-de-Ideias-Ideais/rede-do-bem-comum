-- 0002 UP — tipos, referências públicas e núcleo privado
-- Decisão estrutural: conta ≠ perfil ≠ entidade ≠ local ≠ vínculo.

-- ---------- Tipos (schema app; não expostos) ----------
create type app.entity_kind as enum ('person','collective','network','movement','cooperative',
  'organization','community','bookshop','publisher','school','library','archive','resource');
create type app.presence_type as enum ('physical','territorial','online','hybrid','nonspatial');
-- Quatro eixos INDEPENDENTES (Plano §8)
create type app.research_state as enum ('discovered','triage','verifying','sufficient_evidence','discarded');
create type app.activity_state as enum ('unconfirmed','active','inactive','closed','historical','unknown');
create type app.participation_state as enum ('not_requested','invited','representative_confirmed','withdrawn');
create type app.publication_state as enum ('research_only','draft','in_review','published','hidden','archived');
create type app.location_precision as enum ('exact_public_venue','city','region','none');
create type app.place_kind as enum ('physical_venue','recurring_point','territorial_area');
create type app.text_state as enum ('original','machine_unreviewed','human_reviewed','needs_update');
create type app.verification_label as enum ('found','source_checked','activity_checked','holder_confirmed','network_member');
create type app.staff_role as enum ('curator','moderator','admin');
create type app.relationship_kind as enum ('part_of','shares_space','cooperates_with');

-- ---------- Configuração ----------
create table app.settings (
  key   text primary key,
  value text not null
);
insert into app.settings(key, value) values ('environment', 'development');

-- ---------- Referências públicas (não sensíveis) ----------
create table pub.categories (
  id       text primary key check (id ~ '^[a-z_]{3,40}$'),
  label_pt text not null,
  label_en text not null,
  subcategories_pt text[] not null default '{}'
);

create table pub.practices (
  id       text primary key check (id ~ '^[a-z_]{3,60}$'),
  label_pt text not null,
  label_en text not null
);

-- Áreas administrativas/gazetteer. label_point é o ponto PÚBLICO usado quando a
-- precisão escolhida é cidade/região: nunca derivado da coordenada exata do local.
create table pub.areas (
  id           text primary key check (id ~ '^[a-z0-9-]{2,80}$'),
  level        text not null check (level in ('country','region','city')),
  parent_id    text references pub.areas(id),
  country_code char(2) check (country_code ~ '^[A-Z]{2}$'),
  name         text not null,
  label_point  extensions.geometry(Point, 4326) not null,
  is_synthetic boolean not null default false
);

-- ---------- Contas (privadas) e perfis (públicos só por adesão) ----------
create table app.accounts (
  id         uuid primary key references auth.users(id) on delete cascade,
  locale     text not null default 'pt' check (locale in ('pt','en')),
  created_at timestamptz not null default now()
);

-- Perfil é OUTRA linha, com identificador público distinto do id da conta.
-- Não existe coluna de endereço: pessoas nunca informam endereço residencial.
create table app.profiles (
  account_id uuid primary key references app.accounts(id) on delete cascade,
  public_id  uuid not null unique default gen_random_uuid(),
  pseudonym  text check (char_length(pseudonym) between 2 and 80),
  bio        text check (char_length(bio) <= 1000),
  area_id    text references pub.areas(id),
  precision  app.location_precision not null default 'none'
             check (precision in ('city','region','none')),
  is_synthetic boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (precision = 'none' or area_id is not null)
);

-- Papéis internos: nunca autoatribuídos (CHECK) e só concedidos por função auditada.
create table app.role_grants (
  id             uuid primary key default gen_random_uuid(),
  account_id     uuid not null references app.accounts(id) on delete cascade,
  role           app.staff_role not null,
  scope_country  char(2) check (scope_country ~ '^[A-Z]{2}$'),
  scope_category text references pub.categories(id),
  granted_by     uuid references app.accounts(id),  -- null = bootstrap pelo operador (auditado)
  granted_at     timestamptz not null default now(),
  revoked_at     timestamptz,
  check (granted_by is distinct from account_id)
);
create index on app.role_grants (account_id) where revoked_at is null;

-- ---------- Entidades ----------
create table app.entities (
  id                  uuid primary key default gen_random_uuid(),
  kind                app.entity_kind not null,
  presence_type       app.presence_type not null,
  original_name       text not null check (char_length(original_name) between 2 and 180),
  original_lang       text not null default 'und' check (original_lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$|^und$'),
  country_code        char(2) check (country_code ~ '^[A-Z]{2}$'),
  area_id             text references pub.areas(id),
  public_contact_url  text check (public_contact_url ~ '^https://[^\s<>"]+$'),
  access_conditions   jsonb not null default '{}'::jsonb check (jsonb_typeof(access_conditions) = 'object'),
  research_state      app.research_state not null default 'discovered',
  activity_state      app.activity_state not null default 'unconfirmed',
  participation_state app.participation_state not null default 'not_requested',
  publication_state   app.publication_state not null default 'draft',
  verification_label  app.verification_label not null default 'found',
  last_activity_verified_at date,
  source_accessed_at  date,
  review_due_at       date,
  rights_basis        text,     -- decisão registrada sobre base de publicação/direitos
  export_permission   boolean not null default false,
  current_version_no  integer not null default 0,
  created_by          uuid references app.accounts(id) on delete set null,
  is_synthetic        boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (kind <> 'person' or export_permission = false)
);
create index on app.entities (publication_state);
create index on app.entities (country_code);

-- Textos por campo e idioma, com estado de tradução.
create table app.entity_texts (
  entity_id  uuid not null references app.entities(id) on delete cascade,
  field      text not null check (field in ('name','description','access_note')),
  lang       text not null check (lang ~ '^[a-z]{2,3}$'),
  body       text not null check (char_length(body) <= 4000),
  state      app.text_state not null,
  updated_at timestamptz not null default now(),
  primary key (entity_id, field, lang)
);

create table app.entity_categories (
  entity_id   uuid not null references app.entities(id) on delete cascade,
  category_id text not null references pub.categories(id),
  is_primary  boolean not null default false,
  basis       text not null default 'declared' check (basis in ('declared','evidenced','editorial')),
  primary key (entity_id, category_id)
);
create unique index entity_one_primary_category on app.entity_categories (entity_id) where is_primary;

create table app.entity_practices (
  entity_id      uuid not null references app.entities(id) on delete cascade,
  practice_id    text not null references pub.practices(id),
  evidence_state text not null default 'declared' check (evidence_state in ('declared','evidenced')),
  primary key (entity_id, practice_id)
);

-- ---------- Locais (N:N com entidades) ----------
create table app.places (
  id                uuid primary key default gen_random_uuid(),
  kind              app.place_kind not null default 'physical_venue',
  area_id           text references pub.areas(id),
  geom_exact        extensions.geometry(Point, 4326),   -- PRIVADO
  address_private   text check (char_length(address_private) <= 300), -- PRIVADO
  precision         app.location_precision not null default 'none',
  is_sensitive      boolean not null default false,
  activity_state    app.activity_state not null default 'unconfirmed',
  publication_state app.publication_state not null default 'draft',
  moved_to          uuid references app.places(id),
  is_synthetic      boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (precision <> 'exact_public_venue' or geom_exact is not null),
  check (not is_sensitive or precision in ('region','none')),
  check (precision not in ('city','region') or area_id is not null)
);
create index places_geom_exact_gix on app.places using gist (geom_exact);

create table app.entity_places (
  entity_id   uuid not null references app.entities(id) on delete cascade,
  place_id    uuid not null references app.places(id) on delete cascade,
  role        text not null default 'venue' check (role in ('venue','headquarters','activity_point','shared')),
  public_link boolean not null default true,
  primary key (entity_id, place_id)
);
create index on app.entity_places (place_id);

-- Relações entre entidades (nunca entre pessoas e grupos: isso é membership privada).
create table app.entity_relationships (
  id                uuid primary key default gen_random_uuid(),
  from_entity       uuid not null references app.entities(id) on delete cascade,
  to_entity         uuid not null references app.entities(id) on delete cascade,
  kind              app.relationship_kind not null,
  public_authorised boolean not null default false,
  created_at        timestamptz not null default now(),
  check (from_entity <> to_entity),
  unique (from_entity, to_entity, kind)
);

-- Gestores / memberships: SEMPRE privados.
create table app.entity_managers (
  entity_id   uuid not null references app.entities(id) on delete cascade,
  account_id  uuid not null references app.accounts(id) on delete cascade,
  scope       text not null default 'full' check (scope in ('full','edit_only')),
  status      text not null default 'pending_verification'
              check (status in ('pending_verification','active','revoked')),
  verified_by uuid references app.accounts(id),
  verified_at timestamptz,
  created_at  timestamptz not null default now(),
  primary key (entity_id, account_id)
);
create index on app.entity_managers (account_id) where status = 'active';

-- Aliases para preservar URLs antigas após fusão.
create table app.entity_aliases (
  old_id     uuid primary key,
  entity_id  uuid not null references app.entities(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- ---------- Integridade: pessoa nunca com localização exata ----------
create function app.trg_person_place_guard() returns trigger
language plpgsql set search_path = '' as $$
declare v_kind app.entity_kind; v_prec app.location_precision;
begin
  select kind into v_kind from app.entities where id = new.entity_id;
  select precision into v_prec from app.places where id = new.place_id;
  if v_kind = 'person' and v_prec = 'exact_public_venue' then
    raise exception 'entidade pessoal não pode ter localização exata' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger person_place_guard before insert or update on app.entity_places
  for each row execute function app.trg_person_place_guard();

create function app.trg_place_precision_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.precision = 'exact_public_venue' and exists (
      select 1 from app.entity_places ep join app.entities e on e.id = ep.entity_id
      where ep.place_id = new.id and e.kind = 'person') then
    raise exception 'local vinculado a pessoa não pode ter precisão exata' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger place_precision_guard before update of precision on app.places
  for each row execute function app.trg_place_precision_guard();

-- ---------- Guarda contra dados sintéticos em produção ----------
create function app.trg_block_synthetic_in_production() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.is_synthetic and coalesce((select value from app.settings where key = 'environment'), '') = 'production' then
    raise exception 'dados sintéticos são proibidos em produção' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger no_synthetic_in_prod before insert or update on app.entities
  for each row execute function app.trg_block_synthetic_in_production();
create trigger no_synthetic_in_prod before insert or update on app.places
  for each row execute function app.trg_block_synthetic_in_production();
create trigger no_synthetic_in_prod before insert or update on app.profiles
  for each row execute function app.trg_block_synthetic_in_production();

-- ---------- Conta criada a partir de auth.users ----------
create function app.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into app.accounts(id) values (new.id) on conflict do nothing;
  return new;
end $$;
revoke all on function app.handle_new_user() from public;
create trigger on_auth_user_created_rbc after insert on auth.users
  for each row execute function app.handle_new_user();
