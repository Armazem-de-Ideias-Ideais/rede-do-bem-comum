-- 0002 DOWN
drop trigger if exists on_auth_user_created_rbc on auth.users;
drop function if exists app.handle_new_user();
drop table if exists app.entity_aliases, app.entity_managers, app.entity_relationships,
  app.entity_places, app.places, app.entity_practices, app.entity_categories,
  app.entity_texts, app.entities, app.role_grants, app.profiles, app.accounts,
  pub.areas, pub.practices, pub.categories, app.settings cascade;
drop function if exists app.trg_person_place_guard(), app.trg_place_precision_guard(),
  app.trg_block_synthetic_in_production();
drop type if exists app.relationship_kind, app.staff_role, app.verification_label, app.text_state,
  app.place_kind, app.location_precision, app.publication_state, app.participation_state,
  app.activity_state, app.research_state, app.presence_type, app.entity_kind;
