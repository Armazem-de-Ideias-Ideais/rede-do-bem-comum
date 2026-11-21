-- 0001 DOWN (drop schema ... cascade também remove as entradas de pg_default_acl)
drop schema if exists api cascade;
drop schema if exists pub cascade;
drop schema if exists app cascade;
-- Em projeto Supabase, PostGIS/unaccent/pg_trgm podem ser usados por outros objetos:
-- remova as três linhas abaixo nesse caso.
drop extension if exists pg_trgm;
drop extension if exists unaccent;
drop extension if exists postgis;
