-- 0003 DOWN
drop table if exists app.translation_tasks, app.cache_invalidation_outbox, app.rate_limits,
  app.suppression_tombstones, app.audit_log, app.reports, app.offers_needs,
  app.political_identity_declarations, app.consent_records, app.claims, app.reviews,
  app.entity_versions, app.evidence, app.field_provenance, app.source_records, app.sources cascade;
drop function if exists app.trg_version_frozen();
drop type if exists app.report_kind, app.consent_decision, app.consent_purpose, app.review_kind,
  app.review_decision, app.version_status, app.evidence_kind;
