#!/usr/bin/env bash
# Ciclo completo de testes do banco (Marco B + Marco C), SOMENTE local/CI.
# Uso, como superusuário do Postgres local (ex.: su postgres -c "bash supabase/tests/run_all.sh"):
#   RBC_DATA_DIR=<pasta com publicavel_v1.json etc.>  (padrão: ../data a partir de supabase/)
# Bancos usados (apagados e recriados): RBC_TEST_DB_B (padrão rbc_test_b) e RBC_TEST_DB_C (padrão rbc_test_c).
# Não contém senhas. Não aponte as variáveis para bancos com dados reais de produção.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/tests"; OUT="$T/output"; SEED_OUT="$OUT/seed"
DATA="${RBC_DATA_DIR:-$ROOT/../data}"
DB_B="${RBC_TEST_DB_B:-rbc_test_b}"; DB_C="${RBC_TEST_DB_C:-rbc_test_c}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)
mkdir -p "$OUT" "$SEED_OUT"
LOG="$OUT/ciclo.log"; : > "$LOG"
say() { echo "### $*" | tee -a "$LOG"; }

ups()     { for f in $(ls "$ROOT"/migrations/*.sql | sort); do "${PSQL[@]}" -d "$1" -f "$f" || { echo "FALHA up $f"; return 1; }; done; }
ups_c()   { for f in $(ls "$ROOT"/migrations/00{08,09,10,11}_*.sql | sort); do "${PSQL[@]}" -d "$1" -f "$f" || { echo "FALHA up $f"; return 1; }; done; }
downs_c() { for f in $(ls "$ROOT"/migrations_down/00{08,09,10,11}_*.down.sql | sort -r); do "${PSQL[@]}" -d "$1" -f "$f" || { echo "FALHA down $f"; return 1; }; done; }
downs()   { for f in $(ls "$ROOT"/migrations_down/*.down.sql | sort -r); do "${PSQL[@]}" -d "$1" -f "$f" || { echo "FALHA down $f"; return 1; }; done; }
fresh()   { dropdb --if-exists "$1"; createdb "$1"; "${PSQL[@]}" -d "$1" -f "$T/local_shim.sql" >/dev/null 2>&1; "${PSQL[@]}" -d "$1" -c 'create extension if not exists pgtap'; }
suite_b() { (cd "$T/marco_b" && pg_prove -d "$1" 0*.sql 2>&1); }
residue_c() { psql -X -At -d "$1" -c "select 'resíduos do Marco C: ' ||
   ((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where (n.nspname, c.relname) in (('api','entity_list'),('app','takedown_requests'),('app','invite_candidates'),('app','notification_outbox'),('pub','slug_redirects')))
  + (select count(*) from information_schema.columns where table_schema in ('app','pub') and column_name in ('slug','website_url','activity_badge','topic','method'))
  + (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('app','api')
      and p.proname in ('request_takedown','claim_start','connect_request','invite_accept','entity_page','_upsert_record','slugify')))"; }

say "B1) $DB_B: shim + migrações 0001–0011 + seed sintético + testes do Marco B"
fresh "$DB_B" 2>&1 | tee -a "$LOG"
ups "$DB_B" 2>&1 | tee -a "$LOG"
"${PSQL[@]}" -d "$DB_B" -f "$T/seed_synthetic.sql" >/dev/null 2>>"$LOG"
"${PSQL[@]}" -d "$DB_B" -f "$T/helpers.sql" >/dev/null 2>>"$LOG"
suite_b "$DB_B" | tee "$OUT/b_rodada1_com_C.tap" | tail -3 | tee -a "$LOG"

say "B2) DOWN do Marco C (0011→0008) e testes do Marco B de novo"
downs_c "$DB_B" 2>&1 | tee -a "$LOG"
residue_c "$DB_B" 2>&1 | tee -a "$LOG"
suite_b "$DB_B" | tee "$OUT/b_rodada2_sem_C.tap" | tail -3 | tee -a "$LOG"

say "B3) UP do Marco C sobre dados existentes (preenche slugs) e testes do Marco B"
ups_c "$DB_B" 2>&1 | tee -a "$LOG"
psql -X -At -d "$DB_B" -c "select 'entidades sem slug: ' || count(*) from app.entities where slug is null" | tee -a "$LOG"
suite_b "$DB_B" | tee "$OUT/b_rodada3_com_C.tap" | tail -3 | tee -a "$LOG"

say "B4) DOWN completo (0011→0001) e verificação de resíduos"
"${PSQL[@]}" -d "$DB_B" -c 'drop schema tests cascade' 2>&1 | tee -a "$LOG"
downs "$DB_B" 2>&1 | tee -a "$LOG"
psql -X -At -d "$DB_B" -c "select 'schemas restantes: ' || coalesce(string_agg(nspname, ','), '(nenhum)') from pg_namespace where nspname in ('app','pub','api');
  select 'trigger em auth.users: ' || count(*) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;" 2>&1 | tee -a "$LOG"

say "C1) $DB_C: shim + migrações + seed REAL gerado por build_seed.py (público + convites privados com a flag)"
fresh "$DB_C" 2>&1 | tee -a "$LOG"
ups "$DB_C" 2>&1 | tee -a "$LOG"
python3 -I "$ROOT/seed/build_seed.py" --dados "$DATA/publicavel_v1.json" --traducoes "$DATA/traducoes_en.json" \
  --triagem "$DATA/triagem_resultado.json" --pendentes "$DATA/triagem_aderencia_246.json" \
  --saida "$SEED_OUT" --private-invites "$DATA/convite_alta_exposicao_PRIVADO.json" 2>&1 | tee -a "$LOG"
psql -X -v ON_ERROR_STOP=1 -d "$DB_C" -f "$SEED_OUT/seed_publico.sql" 2>&1 | grep -v '^\(BEGIN\|COMMIT\|INSERT\|CREATE\)' | tee -a "$LOG"
psql -X -v ON_ERROR_STOP=1 -d "$DB_C" -f "$SEED_OUT/PRIVADO_convites.sql" 2>&1 | grep -v '^\(BEGIN\|COMMIT\|INSERT\|CREATE\)' | tee -a "$LOG"
rm -f "$SEED_OUT/PRIVADO_convites.sql"   # o arquivo privado não fica no disco depois da carga de teste
say "C2) recarga do seed público (idempotência: espera 'updated', nenhum 'inserted')"
psql -X -v ON_ERROR_STOP=1 -d "$DB_C" -c 'drop table if exists _rbc_seed' -f "$SEED_OUT/seed_publico.sql" 2>&1 | grep -v '^\(BEGIN\|COMMIT\|INSERT\|CREATE\|DROP\)' | tee -a "$LOG"
psql -X -At -d "$DB_C" -c "select 'public_stats: ' || row_to_json(s)::text from api.public_stats s;
  select 'candidatos privados: ' || count(*) from app.invite_candidates;" | tee -a "$LOG"
"${PSQL[@]}" -d "$DB_C" -f "$T/helpers.sql" >/dev/null 2>>"$LOG"
"${PSQL[@]}" -d "$DB_C" -f "$T/marco_c/_fixture.sql" 2>&1 | tee -a "$LOG"
say "C3) testes do Marco C"
(cd "$T/marco_c" && pg_prove -v -d "$DB_C" 1*.sql 2>&1) > "$OUT/c_detalhado.tap"
grep -E '^(ok|not ok)|^Files=|^Result|^1[0-9]_|Failed|# +(got|expected|Looks)' "$OUT/c_detalhado.tap" | grep -v '^ok' | tee -a "$LOG"
grep -E '^Files=|^Result' "$OUT/c_detalhado.tap" | tee -a "$LOG"
say "fim"
