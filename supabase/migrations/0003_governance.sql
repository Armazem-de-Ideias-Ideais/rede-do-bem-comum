-- 0003 UP — proveniência, evidências, versões/revisões, reivindicações, autorizações,
-- ofertas/necessidades, relatos, auditoria, tombstones e filas auxiliares (todas privadas)

create type app.evidence_kind as enum ('primary_page_read','primary_page_indexed','directory_reference',
  'self_submitted','unverified_lead','representative_confirmation');
create type app.version_status as enum ('draft','submitted','approved','rejected','changes_requested','superseded','conflict');
create type app.review_decision as enum ('approve','reject','request_changes');
create type app.review_kind as enum ('source','activity','representation','publication');
create type app.consent_purpose as enum ('account_management','public_presentation','political_identity_public',
  'location_city_region','connection_requests','newsletter','institutional_export');
create type app.consent_decision as enum ('granted','denied');
create type app.report_kind as enum ('correction','exposure','abuse','withdrawal_request','other');

-- ---------- Fontes e registros de origem ----------
create table app.sources (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  base_url       text not null check (base_url ~ '^https://'),
  domain         text not null,
  licence        text,
  terms_url      text,
  adapter_allowed boolean not null default false,  -- lista de fontes autorizadas
  notes          text,
  created_at     timestamptz not null default now()
);

create table app.source_records (
  id           uuid primary key default gen_random_uuid(),
  source_id    uuid not null references app.sources(id),
  external_id  text not null,
  url          text not null check (url ~ '^https?://'),
  accessed_at  date not null,
  licence      text,
  payload      jsonb not null default '{}'::jsonb,  -- valores por campo, tal como lidos (dado não confiável)
  entity_id    uuid references app.entities(id) on delete set null,
  status       text not null default 'draft_created' check (status in ('draft_created','matched_suggestion','rejected')),
  public_ref_safe boolean not null default false, -- só publica a URL de origem quando segura
  imported_at  timestamptz not null default now(),
  unique (source_id, external_id)
);

-- Proveniência e licença POR CAMPO.
create table app.field_provenance (
  id               uuid primary key default gen_random_uuid(),
  entity_id        uuid not null references app.entities(id) on delete cascade,
  field_name       text not null,
  origin           text not null check (origin in ('participant','source','editorial')),
  source_record_id uuid references app.source_records(id) on delete set null,
  licence          text,
  participant_managed boolean not null default false, -- precedência sobre fontes externas
  recorded_at      timestamptz not null default now()
);
create index on app.field_provenance (entity_id, field_name);

create table app.evidence (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references app.entities(id) on delete cascade,
  kind        app.evidence_kind not null,
  level       text not null check (level in ('E0','E1','E2','E3')),
  url         text check (url ~ '^https?://'),
  observed_at date not null,
  note        text check (char_length(note) <= 2000),
  created_by  uuid references app.accounts(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index on app.evidence (entity_id);

-- ---------- Versões e revisões ----------
create table app.entity_versions (
  id              uuid primary key default gen_random_uuid(),
  entity_id       uuid not null references app.entities(id) on delete cascade,
  version_no      integer not null,
  base_version_no integer not null,      -- versão publicada/aplicada sobre a qual a proposta foi feita
  author_id       uuid references app.accounts(id) on delete set null,
  payload         jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  status          app.version_status not null default 'draft',
  row_version     integer not null default 1,
  payload_hash    text,
  submitted_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (entity_id, version_no)
);
create index on app.entity_versions (author_id);
create index on app.entity_versions (status) where status = 'submitted';

-- Versão submetida fica CONGELADA.
create function app.trg_version_frozen() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status <> 'draft' and new.payload is distinct from old.payload then
    raise exception 'versão % está congelada (status %)', old.id, old.status using errcode = 'P0001';
  end if;
  if new.entity_id is distinct from old.entity_id or new.author_id is distinct from old.author_id
     or new.version_no is distinct from old.version_no then
    raise exception 'campos de identidade da versão são imutáveis' using errcode = 'P0001';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger version_frozen before update on app.entity_versions
  for each row execute function app.trg_version_frozen();

create table app.reviews (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references app.entities(id) on delete cascade,
  version_id  uuid references app.entity_versions(id) on delete set null,
  reviewer_id uuid references app.accounts(id) on delete set null,
  kind        app.review_kind not null,
  decision    app.review_decision not null,
  rationale   text not null check (char_length(rationale) between 10 and 4000),
  created_at  timestamptz not null default now()
);
create index on app.reviews (entity_id);

-- ---------- Reivindicação de ficha ----------
create table app.claims (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references app.entities(id) on delete cascade,
  claimant_id uuid not null references app.accounts(id) on delete cascade,
  statement   text not null check (char_length(statement) between 10 and 4000),
  status      text not null default 'pending' check (status in ('pending','approved','rejected','withdrawn')),
  decided_by  uuid references app.accounts(id),
  decided_at  timestamptz,
  rationale   text,
  created_at  timestamptz not null default now()
);
create unique index claims_one_pending on app.claims (entity_id, claimant_id) where status = 'pending';

-- ---------- Autorizações (consentimentos) ----------
-- decision NÃO tem default: não existe consentimento pré-selecionado.
create table app.consent_records (
  id           uuid primary key default gen_random_uuid(),
  account_id   uuid not null references app.accounts(id) on delete cascade,
  purpose      app.consent_purpose not null,
  decision     app.consent_decision not null,
  text_version text not null check (text_version ~ '^[a-z0-9._-]{1,40}$'),
  entity_id    uuid references app.entities(id) on delete cascade,
  scope        jsonb not null default '{}'::jsonb,
  decided_at   timestamptz not null default now(),
  withdrawn_at timestamptz,
  check (withdrawn_at is null or decision = 'granted')
);
create index on app.consent_records (account_id, purpose);

create table app.political_identity_declarations (
  id                 uuid primary key default gen_random_uuid(),
  consent_id         uuid not null references app.consent_records(id) on delete cascade,
  entity_id          uuid references app.entities(id) on delete cascade,
  profile_account_id uuid references app.profiles(account_id) on delete cascade,
  labels             text[] not null check (cardinality(labels) between 1 and 5),
  status             text not null default 'active' check (status in ('active','withdrawn')),
  created_at         timestamptz not null default now(),
  check ((entity_id is null) <> (profile_account_id is null))
);

-- ---------- Ofertas e necessidades ----------
create table app.offers_needs (
  id                uuid primary key default gen_random_uuid(),
  entity_id         uuid not null references app.entities(id) on delete cascade,
  kind              text not null check (kind in ('offer','need')),
  title             text not null check (char_length(title) between 3 and 140),
  description       text check (char_length(description) <= 2000),
  valid_from        date not null default current_date,
  valid_until       date not null,
  visibility        text not null default 'restricted' check (visibility in ('public','restricted')),
  publication_state app.publication_state not null default 'draft',
  created_by        uuid references app.accounts(id) on delete set null,
  created_at        timestamptz not null default now(),
  check (valid_until >= valid_from and valid_until <= valid_from + 366)
);

-- ---------- Relatos (correção, exposição, retirada) ----------
create table app.reports (
  id               uuid primary key default gen_random_uuid(),
  kind             app.report_kind not null,
  entity_id        uuid references app.entities(id) on delete set null,
  body             text not null check (char_length(body) between 5 and 5000),
  reporter_account uuid references app.accounts(id) on delete set null,
  reporter_contact text check (char_length(reporter_contact) <= 200),
  priority         smallint not null default 3 check (priority between 1 and 3),
  status           text not null default 'open' check (status in ('open','triaged','actioned','closed')),
  handled_by       uuid references app.accounts(id),
  handled_at       timestamptz,
  referral_note    text,
  created_at       timestamptz not null default now()
);
create index on app.reports (status, priority);

-- ---------- Auditoria (sem conteúdo desnecessário) ----------
create table app.audit_log (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  actor        uuid,
  action       text not null,
  target_table text not null,
  target_id    text,
  details      jsonb not null default '{}'::jsonb
);

-- ---------- Tombstones de supressão (somente hashes) ----------
create table app.suppression_tombstones (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid,              -- sem FK: sobrevive à exclusão da entidade
  key_type    text not null check (key_type in ('entity_id','source_external','domain','name_country')),
  key_hash    text not null,
  reason_code text not null check (reason_code ~ '^[a-z_]{3,40}$'),
  created_by  uuid,
  created_at  timestamptz not null default now(),
  unique (key_type, key_hash)
);

-- ---------- Filas auxiliares ----------
create table app.rate_limits (
  key          text not null,
  bucket_start timestamptz not null,
  hits         integer not null default 0,
  primary key (key, bucket_start)
);

create table app.cache_invalidation_outbox (
  id           bigint generated always as identity primary key,
  entity_id    uuid,
  place_ids    uuid[] not null default '{}',
  reason       text not null,
  created_at   timestamptz not null default now(),
  processed_at timestamptz
);

create table app.translation_tasks (
  id                 uuid primary key default gen_random_uuid(),
  entity_id          uuid references app.entities(id) on delete cascade,
  profile_account_id uuid references app.profiles(account_id) on delete cascade,
  field_name         text not null,
  target_lang        text not null,
  status             text not null default 'queued' check (status in ('queued','done','cancelled')),
  created_at         timestamptz not null default now()
);
