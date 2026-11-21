#!/usr/bin/env python3
"""Gera o SQL de carga da Rede do Bem Comum a partir dos dados de pesquisa.

Uso (da raiz do repositório):
    python3 -I supabase/seed/build_seed.py \
        --dados data/publicavel_v1.json \
        --traducoes data/traducoes_en.json \
        --triagem data/triagem_resultado.json \
        --pendentes data/triagem_aderencia_246.json

Saídas em supabase/seed/out/ (pasta ignorada pelo git):
    seed_publico.sql                 carga completa, uma transação
    seed_publico_parte_NN.sql        a mesma carga em partes (para o SQL Editor do Supabase)
    resumo_seed.json                 contagens e exclusões (sem dados internos)

Convites de exposição alta: SOMENTE com --private-invites <arquivo>, gera
    PRIVADO_convites.sql             carga na tabela privada app.invite_candidates (nunca pública)
Por padrão os 173 não são lidos nem carregados.

Regras:
- Campos internos da pesquisa (research_notes, lot, exposure, audit) nunca entram no SQL.
- Registros com decisão "segurar" na triagem não entram. Registros da lista de pendentes
  ("aderência a avaliar") só entram com decisão explícita "publicar".
- Registros com indício de encerramento nas notas de pesquisa não entram
  (desligue com --manter-indicio-encerramento).
- Registros com exposure diferente de low/medium nunca entram no seed público.
- Tradução EN ausente → resumo EN nulo.
- IDs estáveis: UUID v5 do código de pesquisa (recargas atualizam a mesma ficha).
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import sys
import unicodedata
import uuid

NAMESPACE = uuid.UUID("6f1d3c2a-8b4e-5d7f-9a0b-1c2d3e4f5a6b")  # fixo: não mude depois da primeira carga
KVM_PHRASE = "Contém dados da Karte von Morgen / OpenFairDB, disponíveis sob ODbL"
INTERNAL_FIELDS = {"research_notes", "lot", "exposure", "audit", "approved"}
CLOSURE_PATTERNS = [
    r"j[áa] encerrad", r"poss[íi]vel encerramento", r"encerrou (as )?atividades", r"\bextint[oa]s?\b",
    r"permanently closed", r"definitivamente fechad", r"deixou de funcionar",
]
URL_RE = re.compile(r'^https?://[^\s<>"]+$')
KINDS = {"collective", "network", "movement", "cooperative", "organization", "community", "bookshop",
         "publisher", "school", "library", "archive", "resource"}
PRESENCES = {"physical", "territorial", "online", "hybrid", "nonspatial"}
BADGES = {"active_recent", "source_checked", "to_confirm"}
EVIDENCE = {"primary_page_read", "primary_page_indexed", "directory_reference", "self_submitted",
            "unverified_lead", "representative_confirmation"}


def slugify(text: str) -> str:
    s = unicodedata.normalize("NFKD", text or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:60].strip("-")


def sql_str(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_json(obj) -> str:
    return sql_str(json.dumps(obj, ensure_ascii=False, separators=(",", ":"))) + "::jsonb"


def load_json(path, default=None):
    if not path:
        return default
    if not os.path.exists(path):
        print(f"aviso: {path} não encontrado; seguindo sem ele", file=sys.stderr)
        return default
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def to_record(r: dict, en: dict, collected_on: str) -> dict:
    """Converte um registro de pesquisa para a lista FECHADA de chaves aceita por app._validate_record."""
    rid = r["id"]
    if not re.match(r"^[A-Z0-9-]{3,40}$", rid):
        raise ValueError(f"código de pesquisa inválido: {rid!r}")
    if r["kind"] not in KINDS or r["presence"] not in PRESENCES:
        raise ValueError(f"{rid}: kind/presence inválido")
    country = r.get("country") or None
    city = (r.get("city") or "").strip() or None
    lat, lng = r.get("city_lat"), r.get("city_lng")
    precision = r.get("location_precision") or "none"
    area_id = None
    if precision == "city" and country and city and lat is not None and lng is not None:
        cslug = slugify(city) or uuid.uuid5(NAMESPACE, f"{country}|{city}").hex[:8]
        area_id = f"{country.lower()}-{cslug}"[:80].strip("-")
        if not re.match(r"^[a-z0-9-]{2,80}$", area_id):
            raise ValueError(f"{rid}: area_id inválido {area_id!r}")
    else:
        precision, lat, lng = "none", None, None
    lot = r.get("lot") or ""
    note = r.get("licence_note") or ""
    source_key = "kvm" if (lot == "IMPORT-KVM-ODbL" or "Karte von Morgen" in note) else "research"
    own = (r.get("own_url") or "").strip() or None
    if own and (not URL_RE.match(own) or len(own) > 500):
        own = None
    summary_en = en.get(rid)
    summary_en = summary_en.strip() if isinstance(summary_en, str) and summary_en.strip() else None
    rec = {
        "id": str(uuid.uuid5(NAMESPACE, rid)),
        "research_id": rid,
        "name": r["name"].strip(),
        "alt_names": [a.strip() for a in (r.get("aliases") or []) if a and a.strip()][:10],
        "kind": r["kind"],
        "presence": r["presence"],
        "country": country,
        "city": city,
        "region": r.get("region"),
        "categories": list(dict.fromkeys(r.get("categories") or [])),
        "summary_pt": (r.get("summary_pt") or "").strip() or None,
        "summary_en": summary_en[:4000] if summary_en else None,
        "own_url": own,
        "source_url": r["source_url"],
        "source_key": source_key,
        "evidence": r.get("evidence") if r.get("evidence") in EVIDENCE else "directory_reference",
        "last_activity": r.get("last_activity") if re.match(r"^\d{4}-\d{2}$", r.get("last_activity") or "") else None,
        "activity_badge": r.get("activity_badge") if r.get("activity_badge") in BADGES else "to_confirm",
        "network_of": (r.get("network_of") or "").strip() or None,
        "area_id": area_id,
        "city_lat": lat,
        "city_lng": lng,
        "location_precision": precision,
        "attribution": KVM_PHRASE if source_key == "kvm" else None,
        "collected_on": collected_on,
    }
    leaked = INTERNAL_FIELDS & set(rec)
    assert not leaked, f"campo interno no registro: {leaked}"
    return rec


def categories_sql(familias: list) -> str:
    rows = []
    for f in familias:
        subs = "array[" + ",".join(sql_str(s) for s in f.get("subs_pt", [])) + "]::text[]"
        rows.append(f"({sql_str(f['id'])}, {sql_str(f['pt'])}, {sql_str(f['en'])}, {subs})")
    return ("insert into pub.categories(id, label_pt, label_en, subcategories_pt) values\n  "
            + ",\n  ".join(rows)
            + "\non conflict (id) do update set label_pt = excluded.label_pt, label_en = excluded.label_en,"
              " subcategories_pt = excluded.subcategories_pt;\n")


def render(records: list, fn: str, header: str, familias: list | None, part: str = "") -> str:
    out = [f"-- {header}{part}",
           "-- Gerado por supabase/seed/build_seed.py. Não edite à mão. Rode como owner (postgres) ou service_role.",
           "begin;"]
    if familias is not None:
        out.append(categories_sql(familias))
    out.append("create temp table if not exists _rbc_seed(research_id text, result text);")
    for rec in records:
        out.append(f"insert into _rbc_seed values ({sql_str(rec['research_id'])}, app.{fn}({sql_json(rec)}));")
    out.append("commit;")
    out.append("select result, count(*) from _rbc_seed group by result order by result;")
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dados", required=True, help="publicavel_v1.json")
    ap.add_argument("--traducoes", help='traducoes_en.json no formato {"<id>": "<summary_en>"}')
    ap.add_argument("--triagem", help='triagem_resultado.json: [{"id":..., "decisao":"publicar"|"segurar"}]')
    ap.add_argument("--pendentes", help="lista de registros que exigem decisão de triagem (triagem_aderencia_246.json)")
    ap.add_argument("--familias", default=os.path.join(here, "familias.json"))
    ap.add_argument("--saida", default=os.path.join(here, "out"))
    ap.add_argument("--coleta", default="2026-11-20", help="data de consulta das fontes (AAAA-MM-DD)")
    ap.add_argument("--tamanho-parte", type=int, default=400)
    ap.add_argument("--manter-indicio-encerramento", action="store_true")
    ap.add_argument("--private-invites", metavar="ARQUIVO",
                    help="carga PRIVADA dos candidatos a convite (exposição alta). Só com esta flag.")
    a = ap.parse_args(argv)
    _dt.date.fromisoformat(a.coleta)

    dados = load_json(a.dados)
    en = load_json(a.traducoes, {}) or {}
    triagem = load_json(a.triagem, []) or []
    pend = load_json(a.pendentes, []) or []
    familias = load_json(a.familias)
    decisoes = {t["id"]: t.get("decisao") for t in triagem}
    pendentes = {p["id"] for p in pend}
    fam_ids = {f["id"] for f in familias}
    closure = re.compile("|".join(CLOSURE_PATTERNS), re.I)

    excl = {"triagem_segurar": [], "triagem_sem_decisao": [], "indicio_encerramento": [], "exposicao_alta": []}
    records = []
    for r in sorted(dados, key=lambda x: x["id"]):
        rid = r["id"]
        if r.get("exposure") not in ("low", "medium"):
            excl["exposicao_alta"].append(rid); continue
        if decisoes.get(rid) == "segurar":
            excl["triagem_segurar"].append(rid); continue
        if rid in pendentes and decisoes.get(rid) != "publicar":
            excl["triagem_sem_decisao"].append(rid); continue
        if not a.manter_indicio_encerramento and closure.search(r.get("research_notes") or ""):
            excl["indicio_encerramento"].append(rid); continue
        rec = to_record(r, en, a.coleta)
        unknown = set(rec["categories"]) - fam_ids
        if unknown:
            raise ValueError(f"{rid}: famílias desconhecidas {unknown}")
        records.append(rec)

    os.makedirs(a.saida, exist_ok=True)
    with open(os.path.join(a.saida, ".gitignore"), "w") as fh:
        fh.write("*\n")
    header = f"Rede do Bem Comum: seed público ({len(records)} registros)"
    with open(os.path.join(a.saida, "seed_publico.sql"), "w", encoding="utf-8") as fh:
        fh.write(render(records, "seed_load_record", header, familias))
    for old in os.listdir(a.saida):
        if old.startswith("seed_publico_parte_"):
            os.remove(os.path.join(a.saida, old))
    n = max(a.tamanho_parte, 1)
    parts = [records[i:i + n] for i in range(0, len(records), n)]
    for i, chunk in enumerate(parts, 1):
        with open(os.path.join(a.saida, f"seed_publico_parte_{i:02d}.sql"), "w", encoding="utf-8") as fh:
            fh.write(render(chunk, "seed_load_record", header, familias if i == 1 else None,
                            f" — parte {i}/{len(parts)}"))

    resumo = {
        "gerado_em": _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"),
        "entrada": len(dados), "publicaveis": len(records),
        "com_traducao_en": sum(1 for r in records if r["summary_en"]),
        "com_ponto_de_cidade": sum(1 for r in records if r["area_id"]),
        "fonte_kvm": sum(1 for r in records if r["source_key"] == "kvm"),
        "excluidos": {k: len(v) for k, v in excl.items()},
        "excluidos_ids": excl, "partes": len(parts), "convites_privados": None,
    }

    if a.private_invites:
        priv = load_json(a.private_invites)
        if priv is None:
            raise SystemExit("arquivo de convites não encontrado")
        pub_ids = {r["research_id"] for r in records}
        cand = []
        for r in sorted(priv, key=lambda x: x["id"]):
            if r["id"] in pub_ids:
                raise SystemExit(f"{r['id']} está nos dois arquivos; abortado")
            cand.append(to_record(r, en, a.coleta))
        with open(os.path.join(a.saida, "PRIVADO_convites.sql"), "w", encoding="utf-8") as fh:
            fh.write(render(cand, "seed_load_candidate",
                            f"PRIVADO: candidatos a convite ({len(cand)}). NUNCA versionar nem publicar", None))
        resumo["convites_privados"] = len(cand)

    with open(os.path.join(a.saida, "resumo_seed.json"), "w", encoding="utf-8") as fh:
        json.dump(resumo, fh, ensure_ascii=False, indent=1)
    # verificação final: nenhum campo interno no SQL gerado
    for fn in os.listdir(a.saida):
        if fn.endswith(".sql"):
            body = open(os.path.join(a.saida, fn), encoding="utf-8").read()
            for k in INTERNAL_FIELDS:
                assert f'"{k}"' not in body, f"{fn} contém o campo interno {k}"
    print(json.dumps({k: v for k, v in resumo.items() if k != "excluidos_ids"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
