-- 0008 DOWN — remove o modelo do Marco C e devolve app/pub ao estado do Marco B
drop table if exists app.notification_secrets, app.notification_outbox, app.invitations, app.invite_candidates,
  app.suggestions, app.contact_messages, app.connect_requests, app.takedown_requests cascade;

-- reivindicações: estados novos voltam a 'withdrawn' antes de restaurar a regra antiga
drop index if exists app.claims_one_open;
update app.claims set status = 'withdrawn' where status in ('awaiting_code','awaiting_evidence','failed');
alter table app.claims drop column if exists method, drop column if exists verify_domain, drop column if exists verify_email,
  drop column if exists code_hash, drop column if exists code_expires_at, drop column if exists code_attempts,
  drop column if exists published_code, drop column if exists evidence_url, drop column if exists verified_at;
alter table app.claims drop constraint claims_status_check;
alter table app.claims add constraint claims_status_check check (status in ('pending','approved','rejected','withdrawn'));
revoke select on app.claims from authenticated;
grant select on app.claims to authenticated;

alter table pub.offers_needs drop column if exists topic, drop column if exists published_at;
alter table app.offers_needs drop column if exists topic, drop column if exists updated_at;

drop table if exists pub.slug_redirects cascade;
drop index if exists pub.pub_entities_slug;
drop index if exists pub.pub_entities_area;
alter table pub.entities drop column if exists slug, drop column if exists website_url, drop column if exists city,
  drop column if exists world_region, drop column if exists activity_badge, drop column if exists network_of,
  drop column if exists alt_names, drop column if exists attribution, drop column if exists is_managed,
  drop column if exists location_precision, drop column if exists lon, drop column if exists lat,
  drop column if exists search_text;

drop trigger if exists entity_slug on app.entities;
drop function if exists app.trg_entity_slug(), app._unique_slug(text, text, uuid, text[]), app._slug_taken(text, uuid),
  app.slugify(text);
drop table if exists app.entity_slug_history cascade;
drop index if exists app.entities_slug_uniq;
drop index if exists app.entities_research_id_uniq;
alter table app.entities drop constraint if exists entities_slug_format;
alter table app.entities drop column if exists slug, drop column if exists research_id, drop column if exists website_url,
  drop column if exists city, drop column if exists world_region, drop column if exists activity_badge,
  drop column if exists network_of, drop column if exists alt_names, drop column if exists attribution,
  drop column if exists accepts_connections;

drop table if exists app.shared_domains cascade;
delete from app.settings where key in ('ip_salt','takedown_autohide_per_hour');
