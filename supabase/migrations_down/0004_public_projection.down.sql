-- 0004 DOWN
drop function if exists app._project_profile(uuid), app._project_entity(uuid), app._unproject_entity(uuid),
  app._refresh_place(uuid), app._public_point(app.places), app._is_suppressed(uuid);
drop table if exists pub.export_set, pub.entity_sources, pub.entity_aliases, pub.offers_needs, pub.profiles,
  pub.relationships, pub.entity_places, pub.places, pub.entity_practices, pub.entity_categories,
  pub.entity_texts, pub.entities cascade;
drop function if exists app.url_domain(text), app.key_hash(text), app.counter_class(app.entity_kind, app.presence_type), pub.norm(text);
