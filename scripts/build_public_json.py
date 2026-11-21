#!/usr/bin/env python3
"""Gera web/data/public.json (base pública) e web/js/texts.js (textos institucionais).

Entradas (rbc-app/data):
  publicavel_v1.json      registros aprovados para publicação (1.717)
  traducoes_en.json       {id: resumo_en}  (opcional; id ausente => summary_en = null)
  triagem_resultado.json  decisões da triagem de aderência; "segurar" fica FORA

Saídas:
  web/data/public.json    somente campos públicos (lista branca abaixo)
  web/js/texts.js         textos de docs/textos/*.md convertidos para HTML (PT e EN)

O campo interno "approved" NÃO é filtro de publicação (decisão de 21/11: os 1.717 vão ao ar,
menos os "segurar" da triagem); ele apenas não é exportado.

Regras de privacidade:
  - lista BRANCA de campos; nada de research_notes, lot, exposure, audit, approved, evidence, network_of;
  - nenhum id da lista privada de exposição alta (verificado aqui e de novo nos testes);
  - coordenadas só de centro de cidade, e só quando location_precision == "city".
"""
import json, os, re, sys, unicodedata
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'data')
WEB = os.path.join(ROOT, 'web')
TEXTOS = os.path.join(ROOT, 'docs', 'textos')

PUBLIC_FIELDS = ['id', 'slug', 'name', 'aliases', 'kind', 'presence', 'country', 'city', 'region', 'categories',
                 'summary_pt', 'summary_en', 'summary_en_status', 'own_url', 'source_url', 'source_name',
                 'activity_badge', 'last_activity', 'city_lat', 'city_lng', 'location_precision', 'licence_note']
FORBIDDEN = {'research_notes', 'lot', 'exposure', 'audit', 'approved', 'evidence', 'network_of'}


def load(name, default=None):
    p = os.path.join(DATA, name)
    if not os.path.exists(p):
        if default is not None:
            print('aviso: %s ausente' % name, file=sys.stderr)
            return default
        sys.exit('arquivo obrigatório ausente: ' + p)
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def norm(s):
    """Espelha pub.norm (lower + unaccent)."""
    return unicodedata.normalize('NFKD', s or '').encode('ascii', 'ignore').decode('ascii').lower()


def slugify(s):
    """Espelha app.slugify: btrim(left(btrim(regexp_replace(norm(p), '[^a-z0-9]+', '-', 'g'), '-'), 60), '-')."""
    return re.sub(r'[^a-z0-9]+', '-', norm(s)).strip('-')[:60].strip('-')


def unique_slug(name, aliases, country, rid, taken):
    """Espelha app._unique_slug (supabase/migrations/0008): colisão -> -<país>; depois -2, -3...
    Processado em ordem de id, como a carga do servidor. Sem letras latinas -> <país>-<8 hex>
    (aqui o hex vem do md5 do código; no servidor, do UUID — caso raro, o servidor redireciona por canonical_slug)."""
    import hashlib
    cc = (country or '').strip().lower() or None
    base = slugify(name)
    if len(base) < 3:
        base = next((slugify(a) for a in (aliases or []) if len(slugify(a)) >= 3), None)
    if not base:
        return (cc or 'xx') + '-' + hashlib.md5(rid.encode()).hexdigest()[:8]
    cand = base
    if cand in taken and cc:
        cand = base + '-' + cc
    n = 2
    while cand in taken:
        cand = base + ('-' + cc if cc else '') + '-' + str(n); n += 1
    return cand


KVM_PHRASE = 'Contém dados da Karte von Morgen / OpenFairDB, disponíveis sob ODbL'


def licence(note):
    """A frase da Karte von Morgen é obrigatória e literal (ARQUITETURA_LANCAMENTO.md)."""
    if not note:
        return None
    return KVM_PHRASE if 'karte von morgen' in note.lower() else note


def domain(url):
    m = re.match(r'^[a-z]+://([^/?#:]+)', url or '', re.I)
    if not m:
        return None
    d = m.group(1).lower()
    return d[4:] if d.startswith('www.') else d


def build_public():
    recs = load('publicavel_v1.json')
    tr = load('traducoes_en.json', default={})
    if isinstance(tr, list):
        tr = {x['id']: x.get('summary_en') or x.get('en') for x in tr}
    triage = load('triagem_resultado.json', default=[])
    hold = {x['id'] for x in triage if x.get('decisao') == 'segurar'}
    private = load('convite_alta_exposicao_PRIVADO.json', default=[])
    private_ids = {x['id'] for x in private}

    out, seen_slugs, skipped = [], set(), {'segurar': 0, 'privado': 0}
    for r in sorted(recs, key=lambda x: x['id']):
        if r['id'] in private_ids:
            skipped['privado'] += 1; continue
        if r['id'] in hold:
            skipped['segurar'] += 1; continue
        slug = unique_slug(r['name'], r.get('aliases'), r.get('country'), r['id'], seen_slugs)
        assert re.match(r'^[a-z0-9]+(-[a-z0-9]+)*$', slug) and len(slug) <= 80 and slug not in seen_slugs, slug
        seen_slugs.add(slug)
        city_ok = r.get('location_precision') == 'city' and r.get('city_lat') is not None and r.get('city_lng') is not None
        en = tr.get(r['id']) if isinstance(tr, dict) else None
        rec = {
            'id': r['id'], 'slug': slug, 'name': r['name'], 'aliases': r.get('aliases') or [],
            'kind': r['kind'], 'presence': r['presence'], 'country': r.get('country'), 'city': r.get('city'),
            'region': r.get('region'), 'categories': r.get('categories') or [],
            'summary_pt': r.get('summary_pt'), 'summary_en': en or None,
            'summary_en_status': 'machine' if en else None,
            'own_url': r.get('own_url'), 'source_url': r.get('source_url'), 'source_name': domain(r.get('source_url')),
            'activity_badge': r.get('activity_badge'), 'last_activity': r.get('last_activity'),
            'city_lat': round(r['city_lat'], 3) if city_ok else None,
            'city_lng': round(r['city_lng'], 3) if city_ok else None,
            'location_precision': 'city' if city_ok else 'none',
            'licence_note': licence(r.get('licence_note')),
        }
        assert list(rec.keys()) == PUBLIC_FIELDS
        out.append(rec)

    out.sort(key=lambda x: x['id'])
    leak = [x['id'] for x in out if x['id'] in private_ids]
    assert not leak, leak
    for x in out:
        assert not (FORBIDDEN & set(x.keys()))
    doc = {
        'meta': {
            'generated': date.today().isoformat(), 'count': len(out), 'licence': 'ODbL-1.0',
            'licence_url': 'https://opendatacommons.org/licenses/odbl/1-0/',
            'attribution': 'Rede do Bem Comum', 'source_checked_month': '2026-11',
            'fields': PUBLIC_FIELDS,
        },
        'initiatives': out,
    }
    os.makedirs(os.path.join(WEB, 'data'), exist_ok=True)
    with open(os.path.join(WEB, 'data', 'public.json'), 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, separators=(',', ':'))
    print('public.json: %d registros (fora: %s); com resumo EN: %d' % (len(out), skipped, sum(1 for x in out if x['summary_en'])))


# ---------- textos institucionais ----------
TEXT_FILES = {  # arquivo -> id de rota
    'sobre.md': 'about', 'privacidade.md': 'privacy', 'termos.md': 'terms', 'atribuicao.md': 'attribution',
    'carta_de_convivencia.md': 'charter', 'por_que_estou_aqui.md': 'why',
}


def md_to_html(md):
    import markdown
    for fn, rid in TEXT_FILES.items():
        md = md.replace('](' + fn, '](route:' + rid)
    md = re.sub(r'<!-- FONTES_AUTO_INICIO -->.*?<!-- FONTES_AUTO_FIM -->', '\n<div data-sources-auto></div>\n', md, flags=re.S)
    html = markdown.markdown(md, extensions=['extra', 'sane_lists'])
    html = re.sub(r'<!--.*?-->', '', html, flags=re.S)
    # links externos abrem com rel seguro; links internos route:x viram data-route (resolvidos no cliente)
    html = re.sub(r'href="route:([a-z]+)"', r'href="#" data-route="\1"', html)
    html = re.sub(r'<a href="(https?://[^"]+)"', r'<a href="\1" rel="noopener noreferrer"', html)
    return html


def split_lang(md):
    """Arquivos têm: título bilíngue, preâmbulo opcional (MINUTA), '# Português' ... '---' ... '# English' ..."""
    head, _, rest = md.partition('# Português')
    pt, _, en = rest.partition('# English')
    pt = re.sub(r'\n-{3,}\s*$', '', pt.strip()).strip()
    en = en.strip()
    title_line = head.strip().splitlines()[0].lstrip('# ').strip()
    t_pt, _, t_en = title_line.partition(' / ')
    pre = '\n'.join(head.strip().splitlines()[1:]).strip()
    pre = re.sub(r'\n?-{3,}\s*$', '', pre).strip()
    d_pt = d_en = ''
    if pre:
        body = pre.lstrip('> ').strip()
        if ' / **' in body:
            a, b = body.split(' / **', 1)
            d_pt, d_en = a.strip(), '**' + b.strip()
        else:
            d_pt = d_en = body
    return {'pt': {'title': t_pt.strip(), 'draft': d_pt, 'body': pt}, 'en': {'title': (t_en or t_pt).strip(), 'draft': d_en, 'body': en}}


def build_texts():
    out = {}
    for fn, rid in TEXT_FILES.items():
        with open(os.path.join(TEXTOS, fn), encoding='utf-8') as f:
            parts = split_lang(f.read())
        out[rid] = {}
        for L in ('pt', 'en'):
            p = parts[L]
            out[rid][L] = {'title': p['title'], 'draft': md_to_html(p['draft']) if p['draft'] else '', 'html': md_to_html(p['body'])}
    js = '/* GERADO por scripts/build_public_json.py a partir de docs/textos/*.md — não editar à mão. */\nwindow.RBC_TEXTS = ' + json.dumps(out, ensure_ascii=False) + ';\n'
    if re.search(r'[\w.+-]+@[\w-]+\.[\w.]+', js):
        sys.exit('ERRO: endereço de e-mail encontrado nos textos; remova antes de publicar.')
    with open(os.path.join(WEB, 'js', 'texts.js'), 'w', encoding='utf-8') as f:
        f.write(js)
    print('texts.js: %d textos (%d bytes)' % (len(out), len(js)))


if __name__ == '__main__':
    build_public()
    build_texts()
