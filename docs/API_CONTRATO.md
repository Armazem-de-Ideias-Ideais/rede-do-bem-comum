# Rede do Bem Comum: contrato da API (Fase 1, Marco C)

Versão 1.2 · 21/11/2026 · fonte da verdade para o front (`web/`) e para o backend (`supabase/`).
Regra de evolução: depois de publicado, este contrato **só cresce** (novos campos, funções ou valores). Toda mudança vai para o registro no fim do arquivo. (Exceção declarada na 1.2: o valor de `hidden` em `request_takedown`, ver o registro; o contrato ainda não tinha sido publicado.)

## 1. Como conectar

```js
import { createClient } from '@supabase/supabase-js'   // v2, por CDN ou vendorizado
const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  db:   { schema: 'api' },                 // ÚNICO schema exposto
  auth: { flowType: 'pkce', persistSession: true, detectSessionInUrl: true }
})
```

- Só o schema `api` é exposto pelo PostgREST. `app` e `pub` não existem para o front.
- Visitante = papel `anon` (chave anon). Conta logada = papel `authenticated` (JWT do link mágico).
- Leitura de view: `sb.from('<view>').select('<colunas>')`. Chamada de função: `sb.rpc('<função>', { p_...: ... })`. Os nomes dos parâmetros são exatamente os listados aqui (prefixo `p_`).
- Login: `sb.auth.signInWithOtp({ email, options: { emailRedirectTo: SITE_URL + '/' } })`. Com PKCE, o link volta com `?code=` e o hash da rota (`#i-...`, `#convite-...`) **não é preservado de forma confiável**: guarde a intenção pendente (ficha a reivindicar, token de convite) em `sessionStorage` antes de enviar o link e retome após o login. O link precisa ser aberto no mesmo navegador.
- O front nunca recebe e-mail de terceiros, coordenada exata, notas de pesquisa, lote, exposição ou auditoria. Nenhuma view ou função pública devolve esses campos.

### 1.1 Erros

`supabase-js` devolve `{ data, error }`. Use `error.code` (SQLSTATE) para decidir a mensagem; `error.message` vem em PT e serve só para log.

| `error.code` | Significado | Mensagem sugerida na interface |
|---|---|---|
| `28000` | Precisa estar logado | "Entre com seu e-mail para continuar." |
| `42501` | Sem permissão ou conflito de interesse | "Você não pode fazer isso com esta conta." |
| `P0002` | Não encontrado **ou** sem acesso (resposta idêntica, de propósito) | "Não encontramos este item." |
| `22023` | Dado inválido (tamanho, formato, valor fora da lista) | Mostrar ao lado do campo |
| `54000` | Limite de envios excedido | "Muitos envios. Tente de novo mais tarde." |
| `P0001` | Estado não permite a ação (já decidido, expirado, bloqueado) | Texto específico da tela |
| `40001` | Conflito de edição (versão mudou) | "A ficha mudou. Recarregue." |
| `PGRST*` | Erro do PostgREST (parâmetro com nome errado, função inexistente) | Erro de programação |

### 1.2 Paginação

- **Limite do servidor:** o Supabase devolve no máximo **1.000 linhas** por requisição (padrão "Max rows"). A lista completa (~1.700 fichas) exige 2 páginas.
- **Views:** paginação por chave (keyset) na coluna única indicada em cada view. Exemplo para `entity_list`:
  `sb.from('entity_list').select(cols).order('slug').gt('slug', ultimoSlug).limit(1000)`. Primeira página sem `.gt`. Pare quando vier menos que o limite. `.range(a, b)` também funciona, mas keyset é estável durante retiradas.
- **Funções que devolvem lista:** `p_limit` (com teto indicado) e cursor `p_after` (último id da página anterior) ou `p_offset` (painel do moderador).

### 1.3 Identificadores, slugs e rotas

| Item | Formato | Observação |
|---|---|---|
| `id` de ficha | UUID | Opaco. Fichas importadas têm UUID estável (derivado do código de pesquisa no servidor), que não muda em recargas. |
| `slug` | `^[a-z0-9]+(-[a-z0-9]+)*$`, até 80 caracteres | Nome sem acentos; colisão recebe `-<país>` e depois `-2`, `-3`. Nomes sem letras latinas viram `<país>-<8 hex>`. |
| Rota da ficha | `/#i-<slug>` | Slug antigo continua resolvendo: `entity_page` devolve `canonical_slug` e o front troca a URL com `history.replaceState`. |
| Convite | `/#convite-<token>` | `token` = 64 caracteres hex, uso único, expira (padrão 30 dias). |
| Código publicado (reivindicação b) | `rbc-` + 10 caracteres `[a-z2-9]` | Válido por 14 dias. |
| Código por e-mail (reivindicação a) | 6 dígitos | Válido por 30 minutos, 5 tentativas. |
| Família | id de `api.categories` (ex.: `agroecology`) | 24 famílias. |
| País | ISO 3166-1 alfa-2 (`BR`) ou `null` (rede global) | Nome do país no front via `Intl.DisplayNames`. |

## 2. Leitura pública (anon e authenticated)

Todas as superfícies públicas leem a mesma projeção publicada. Ficha retirada, oculta preventivamente ou não publicada **não aparece em nenhuma** delas (lista, mapa, busca, contadores, irmãs, ofertas, exportação, sitemap), nem por slug antigo.

### 2.1 `entity_list` (view) — lista, mapa e busca local

Uma linha por ficha institucional publicada. Chave de paginação: `slug`.

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `slug` | text | único |
| `name` | text | nome original |
| `alt_names` | text[] | outros nomes conhecidos (pode ser `{}`) |
| `kind` | text | `collective, cooperative, network, movement, organization, community, bookshop, publisher, school, library, archive, resource` |
| `presence_type` | text | `physical, territorial, hybrid, online, nonspatial` |
| `counter_class` | text | `initiative, territorial_group, network, online_resource` |
| `families` | text[] | ids de família, a primária primeiro |
| `primary_family` | text | |
| `country_code` | text | `null` = global/sem país |
| `city` | text | nome da cidade como informado; `null` se desconhecida ou se a iniciativa optou por não mostrar |
| `area_id` | text | id da cidade (`<pais>-<cidade>`), use para agrupar no mapa |
| `lon`, `lat` | numeric | **centro da cidade** (4 casas), nunca a sede. `null` = sem ponto no mapa |
| `location_precision` | text | `city` ou `none` |
| `world_region` | text | `Europa`, `América Latina e Caribe`, `América do Norte`, `Ásia`, `África`, `Oceania`, `Global / sem país` |
| `activity_badge` | text | `active_recent` → "ativa em 2026"; `source_checked` → "fonte consultada em nov/2026"; `to_confirm` → "atividade a confirmar" |
| `activity_month` | date | primeiro dia do mês da última atividade vista, ou `null` |
| `verification_label` | text | `found, source_checked, activity_checked, holder_confirmed, network_member` |
| `summary_pt` | text | resumo original (≤ 200 caracteres na carga inicial) |
| `summary_en` | text | tradução ou `null` |
| `summary_en_state` | text | `machine_unreviewed` ("tradução automática, sem revisão"), `human_reviewed`, `original` ou `null` |
| `website_url` | text | site próprio (http ou https) ou `null` |
| `is_managed` | boolean | ficha gerida pela própria iniciativa (não revela quem) |
| `has_offers` | boolean | tem oferta ou necessidade vigente |
| `search_text` | text | nome + outros nomes + cidade, minúsculo e **sem acentos**, para busca local |
| `published_at` | timestamptz | |

Filtros úteis (PostgREST): `.contains('families', ['agroecology'])`, `.eq('country_code','BR')`, `.in('presence_type',[...])`, `.eq('activity_badge','active_recent')`, `.ilike('search_text', '%' + semAcentos(q) + '%')`. Para não baixar tudo, selecione só as colunas usadas.

### 2.2 `entity_page(p_slug text default null, p_id uuid default null)` → jsonb | null

Ficha completa. Passe **um** dos dois. Devolve `null` se não existir ou não estiver publicada (o front mostra "ficha indisponível ou retirada").

```jsonc
{
  "id": "uuid", "slug": "christiania", "canonical_slug": "christiania",   // se diferente do pedido → redirecionar
  "name": "...", "alt_names": [], "kind": "community", "presence_type": "physical", "counter_class": "initiative",
  "families": [{"id": "housing_communities", "is_primary": true}, {"id": "autonomous_spaces", "is_primary": false}],
  "country_code": "DK", "city": "Copenhague", "area_id": "dk-copenhague", "lon": 12.566, "lat": 55.676,
  "location_precision": "city", "world_region": "Europa", "network_of": null,
  "activity_badge": "active_recent", "activity_month": "2026-11-01", "source_accessed_at": "2026-11-01",
  "verification_label": "activity_checked", "website_url": "https://...", "public_contact_url": null,
  "summary": { "pt": {"body": "...", "state": "original"}, "en": {"body": "...", "state": "machine_unreviewed"} | null },
  "sources": [{"name": "Pesquisa Rede do Bem Comum", "url": "https://...", "accessed_at": "2026-11-01", "licence": null}],
  "attribution": null | "Contém dados da Karte von Morgen / OpenFairDB, disponíveis sob ODbL",
  "offers_needs": [{"id": "uuid", "kind": "offer", "topic": "tools", "title": "...", "description": "...", "valid_until": "2027-01-31"}],
  "is_managed": false, "published_at": "..."
}
```

`attribution` não nulo é **obrigatório** na ficha (frase da Karte von Morgen). `api.entity_detail(p_id uuid)` (Marco B) continua disponível, mas o front deve usar `entity_page`.

### 2.3 `sister_initiatives(p_entity uuid, p_limit integer default 6)` → tabela

Iniciativas-irmãs, em dois grupos, cada um com até `p_limit` linhas (teto 12):

| Coluna | Tipo | Notas |
|---|---|---|
| `relation` | text | `same_family_other_country` (compartilha ≥ 1 família, outro país) ou `complementary_same_city` (mesma cidade, nenhuma família em comum) |
| `entity_id`, `slug`, `name` | | |
| `country_code`, `city` | | |
| `families` | text[] | |
| `shared_families` | text[] | vazio no grupo complementar |
| `activity_badge` | text | |

Ordem: mais famílias em comum primeiro; depois "ativa em 2026"; depois ordem pseudoaleatória estável por ficha (variedade sem mudar a cada recarga). Ficha sem cidade não tem grupo complementar.

### 2.4 Outras views

| View | Colunas | Chave de paginação |
|---|---|---|
| `categories` | `id, label_pt, label_en, subcategories_pt` | `id` (24 linhas) |
| `public_stats` | `entities_total, countries, cities, physical_places, initiatives, territorial_groups, networks, online_resources, offers_active, needs_active` (1 linha) | — |
| `public_counters` | (Marco B) `physical_places, initiatives, territorial_groups, networks, online_resources, public_profiles, includes_synthetic_data` | — |
| `country_counts` | `country_code, entities` | `country_code` |
| `offers_needs_feed` | `id, entity_id, entity_slug, entity_name, country_code, city, kind, topic, title, description, valid_until, published_at` — só vigentes | `id` |
| `attribution_sources` | `source_name, licence, attribution, entities` | `source_name` |
| `entities`, `entity_texts`, `entity_categories`, `places`, `entity_places`, `entity_sources`, `offers_needs`, `sitemap`, `areas` | (Marco B, mantidas) | `id` |

**Contadores distintos** (`public_stats`): disjuntos por construção e **nunca somados** na interface.
- `physical_places`: locais físicos distintos (um local com N iniciativas conta 1 vez; redes, grupos territoriais, recursos online e áreas não entram).
- `initiatives`, `territorial_groups`, `networks`, `online_resources`: fichas por classe (cada ficha em exatamente uma classe).
- `entities_total`: total de fichas publicadas; `countries` e `cities`: valores distintos com ≥ 1 ficha.
- `offers_active` / `needs_active`: itens vigentes (validade ≥ hoje).

Funções de leitura do Marco B continuam: `search_entities(p_query, p_limit, p_after)`, `autocomplete(p_prefix, p_limit)`, `places_in_bbox(...)`, `category_facets(p_country)`, `entity_detail(p_id)`.

## 3. Ações sem login (anon e authenticated)

Todas têm antispam: limite por **hash do IP** (sal diário no servidor, IP nunca gravado em claro) e, se logado, também por conta. Todas aceitam `p_hp` (honeypot): o front envia o valor de um campo invisível; **se vier preenchido, a função responde como sucesso e não grava nada**.

### 3.1 `request_takedown` — "Retirar do mapa"

`request_takedown(p_entity uuid, p_reason text, p_relation text, p_contact text default null, p_locale text default 'pt', p_hp text default null, p_email text default null)` → `{ "request_id": uuid, "hidden": false, "needs_confirmation": boolean, "queued": boolean }`

A retirada continua **sem login**, mas **o pedido nunca oculta a ficha**. Ela só sai do ar depois que quem pediu confirma por um link enviado ao e-mail (§3.1.1). Sem e-mail, o pedido vai para a fila da moderação (resposta em até 72 h) e a ficha fica no ar.

- `p_reason`: 10–2000 caracteres. `p_relation`: `representative | member | mentioned | other`. `p_contact`: opcional (≤ 200), privado, só o moderador vê. `p_email`: opcional, formato simples, até 200 caracteres (inválido → `22023`); vazio ou só espaços vale como ausente.
- **Com e-mail válido:** o servidor cria um token aleatório de 32 bytes (guarda só o sha256), com validade de 24 h e uso único, e enfileira o e-mail `takedown_confirm` (no idioma `p_locale`). Resposta: `{ request_id, hidden: false, needs_confirmation: true, queued: false }`. O front diz: "Enviamos um link para o seu e-mail. A ficha continua no ar até você confirmar."
- **Sem e-mail:** o pedido entra na fila. Resposta: `{ request_id, hidden: false, needs_confirmation: false, queued: true }`. O front diz: "Pedido na fila da moderação. A ficha continua no ar; a resposta vem em até 72 horas."
- **Limite de e-mails de confirmação:** 3 por e-mail por 24 h e um teto global por 24 h (`takedown_confirm_emails_per_day`, padrão 40, para preservar a cota gratuita da Resend, que também serve ao link de login). Acima do limite, o pedido é registrado na fila **sem e-mail** e a resposta é `queued: true`.
- **A resposta não revela se a ficha existe ou está publicada:** ficha inexistente, já oculta ou publicada recebem o mesmo formato (para ficha inexistente ou fora do ar não se envia e-mail nem se cria token).
- O e-mail fica só em `app.takedown_requests` (tabela privada, sem acesso de `anon`/`authenticated`) e em `email_hash` (hash com sal, na mesma tabela) para limites e filtros; `email_domain_matches` registra se o domínio do e-mail coincide com o do site da ficha (orienta a moderação; não muda o fluxo). Pedido não confirmado em 24 h expira e o e-mail em claro é apagado (`purge_expired`).
- Limites por IP: 5 por hora e 20 por dia; 20 por dia por conta. Estourou → `54000` (o front mostra a tela "Limite de pedidos atingido").
- Moderação: um e-mail por ocultação confirmada e por pedido sem e-mail (`takedown_request`), com teto de 20 por 24 h; acima disso o painel mostra tudo e o alerta de contenção (§3.1.1) cobre o aviso.
- Depois, o moderador **confirma** (retirada definitiva com tombstone, que impede reimportação) ou **restaura** com justificativa (§6).

#### 3.1.1 `confirm_takedown` — link do e-mail

`confirm_takedown(p_token text)` → `{ "hidden": boolean, "queued": boolean }` (anon e authenticated)

- O front abre a rota `#confirmar-retirada-<token>` (PT) ou `#confirm-withdrawal-<token>` (EN), que chama esta função. O token tem 64 caracteres hexadecimais; o link do e-mail usa `${SITE_URL}/#confirmar-retirada-<token>` (idioma pt/es) ou `${SITE_URL}/#confirm-withdrawal-<token>` (en).
- Token inexistente, já usado, vencido ou malformado → **o mesmo erro genérico** `P0002` ("link inválido ou vencido"). O front mostra "Link inválido ou vencido" sem dizer o motivo.
- Marca o token como usado e então oculta a ficha (`hidden: true`, `queued: false`; some de lista, mapa, busca, contadores e exportação) **se o disjuntor permitir**: no máximo 3 ocultações por e-mail (hash) em 24 h (`takedown_autohide_per_email_day`), `takedown_autohide_per_hour` (padrão 15) e `takedown_autohide_per_day` (padrão 50) no total.
- Acima do disjuntor: a ficha continua no ar, o pedido fica na fila com `contained = true` e a resposta é `{ hidden: false, queued: true }`. A moderação recebe **um único alerta** (`takedown_containment`) por janela de 24 h, não um por pedido. Também vai para a fila (`queued: true`) o pedido cuja ficha já não está no ar.
- Limite por IP: 30 por hora e 100 por dia (`54000`).

### 3.2 `report` — "Corrigir" e denúncias

`report(p_kind text, p_entity uuid, p_body text, p_contact text default null, p_hp text default null)` → uuid

- `p_kind`: `correction | exposure | abuse | other`. `exposure` e `abuse` têm prioridade. `p_body`: 5–5000.
- Não oculta a ficha (para ocultar, use `request_takedown`). Limite: 10 por hora por IP/conta.
- `submit_report` (Marco B) continua existindo, mas use `report`.

### 3.3 `suggest_initiative` — "Indicar uma iniciativa"

`suggest_initiative(p_name text, p_website text, p_country text, p_city text, p_families text[], p_description text, p_why text default null, p_contact text default null, p_locale text default 'pt', p_hp text default null)` → uuid

- Entra na fila editorial; **nunca publica direto**. `p_name` 2–180; `p_website` http(s) ou `null`; `p_country` ISO-2 ou `null`; `p_families` ⊂ `categories.id` (0–5); `p_description` 10–2000.
- Não envie dados de pessoas. Limite: 5 por hora, 20 por dia por IP/conta.

### 3.4 `send_contact_message` — formulário de contato

`send_contact_message(p_name text, p_email text, p_subject text, p_body text, p_locale text default 'pt', p_hp text default null)` → uuid

- `p_email` obrigatório e válido (para resposta); fica privado. `p_subject` 3–150; `p_body` 10–5000.
- Gravado no banco; o servidor envia notificação ao moderador (endereço nunca exposto). Limite: 3 por hora, 10 por dia por IP.

### 3.5 Convite (pré-visualização e recusa)

- `invite_preview(p_token text)` → jsonb com a ficha **proposta** (não publicada): `{ name, alt_names, kind, presence_type, families, country_code, city, summary_pt, website_url, source_url, expires_at }`. Token inválido, usado, revogado ou expirado → erro `P0002` (mesma mensagem para todos).
- `invite_decline(p_token text, p_reason text default null)` → void. A iniciativa recusa: nada é publicado, e um tombstone impede futura importação ou publicação. O token deixa de valer.

## 4. Conta (authenticated)

A conta é criada pelo link mágico e é **privada**: não cria perfil nem ficha pública.

- `my_account()` → jsonb:
  ```jsonc
  { "locale": "pt",
    "roles": ["moderator"],                       // vazio para contas comuns
    "managed": [{"entity_id": "...", "slug": "...", "name": "...", "accepts_connections": true}],
    "claims":  [{"id": "...", "entity_id": "...", "slug": "...", "name": "...", "method": "domain_email",
                 "status": "awaiting_code", "code_expires_at": "...", "published_code": null, "created_at": "..."}],
    "connections": {"incoming_pending": 1, "outgoing_pending": 0} }
  ```
- `set_locale(p_locale text)` → void (`pt` | `en`). O idioma define os e-mails enviados à conta.

## 5. Ações de conta

### 5.1 Reivindicação ("É sua? Reivindique") — três caminhos

`claim_start(p_entity uuid, p_method text, p_statement text, p_email text default null)` → jsonb
`{ "claim_id": uuid, "method": text, "status": text, "published_code": text|null, "code_expires_at": timestamptz|null }`

| `p_method` | Como verifica | `status` após `claim_start` | Próximo passo |
|---|---|---|---|
| `domain_email` (a) | `p_email` precisa ter o **mesmo domínio do site próprio** da ficha (ou subdomínio dele). Domínios de plataformas compartilhadas (gmail.com, wordpress.com, instagram.com etc.) não valem. Se `p_email` for o próprio e-mail da conta logada, a posse já foi provada pelo link mágico e a reivindicação é aprovada na hora. | `approved` ou `awaiting_code` | Código de 6 dígitos enviado a `p_email` → `claim_verify_code` |
| `published_code` (b) | O sistema gera `published_code`; a iniciativa publica o código no site ou numa rede social oficial e informa a URL. | `awaiting_evidence` | `claim_submit_evidence(p_claim, p_url)` → `pending`; o moderador confere e decide |
| `manual` (c) | `p_statement` explica o vínculo; o moderador decide. | `pending` | Aguardar decisão (e-mail) |

- `p_statement`: 10–2000. Só fichas publicadas. Uma reivindicação aberta por conta e ficha. Limite: 5 por dia por conta. A resposta nunca revela se a ficha já tem gestores.
- `domain_email` com domínio que não confere → erro `22023` ("o e-mail precisa ser do domínio do site da iniciativa"); ficha sem site próprio → `22023` (use b ou c).
- `claim_verify_code(p_claim uuid, p_code text)` → `{ "status": "approved" | "awaiting_code" | "failed", "attempts_left": int }`. 5 tentativas; código expirado → `P0001`.
- `claim_resend_code(p_claim uuid)` → `{ "code_expires_at": ... }` (máximo 3 por dia).
- `claim_submit_evidence(p_claim uuid, p_url text)` → `{ "status": "pending" }`. URL https.
- `claim_cancel(p_claim uuid)` → void.
- Estados: `awaiting_code`, `awaiting_evidence`, `pending`, `approved`, `rejected`, `withdrawn`, `failed`.
- **Aprovada:** a conta vira gestora ativa da ficha, a ficha passa a "gerida pela iniciativa" (`is_managed`, selo `holder_confirmed`), pedidos de conexão guardados são entregues, e a conta recebe e-mail.

### 5.2 Gestão da ficha

- `manager_update(p_entity uuid, p_payload jsonb)` → `{ "applied": ["descriptions", ...], "pending_version_id": uuid|null }`
  - Aplicados na hora (campos não sensíveis): `descriptions` (`{"pt": "...", "en": "..."}`; o idioma original fica `original`, os outros `human_reviewed`), `website_url`, `contact_url` (https), `access_conditions` (objeto), `categories` + `primary_category`.
  - Vão para revisão (campos sensíveis): `name`, `country_code`, `area_id`. Viram uma proposta congelada; a ficha pública não muda até a aprovação.
  - Qualquer outra chave → `22023`. Só gestor ativo (`P0002` para os demais).
- `set_accepts_connections(p_entity uuid, p_accept boolean)` → void.
- `withdraw_entity(p_entity uuid, p_reason_code text)` (Marco B) → o gestor retira a própria ficha (tombstone; `p_reason_code` `^[a-z_]{3,40}$`, ex.: `holder_request`).

### 5.3 Conectar (pedido mediado)

- `connect_request(p_from_entity uuid, p_to_entity uuid, p_message text, p_contact text)` → uuid
  - A conta precisa gerir `p_from_entity` (gestora ativa). As duas fichas publicadas e diferentes. `p_message` 10–1000; `p_contact` 5–300 (como a pedida pode responder: e-mail, telefone, site), **privado até o aceite**.
  - Se a pedida tem gestor: ele recebe e-mail. Se não tem: o pedido fica guardado (validade 180 dias) e é entregue quando alguém reivindicar a ficha.
  - Um pedido pendente por par de fichas. Limite: 10 por dia por conta.
  - Se a pedida desativou pedidos, a resposta é a mesma, mas o pedido nunca é entregue.
- `connect_respond(p_request uuid, p_accept boolean, p_contact text default null)` → void. Só gestor ativo da ficha pedida. Aceitar exige `p_contact` (5–300). O solicitante recebe e-mail.
- `connect_cancel(p_request uuid)` → void (solicitante, enquanto pendente).
- `my_connections()` → tabela: `request_id, direction ('in'|'out'), status ('pending'|'accepted'|'declined'|'cancelled'|'expired'), my_entity_id, my_entity_slug, my_entity_name, other_entity_id, other_entity_slug, other_entity_name, message, my_contact, other_contact, created_at, decided_at`.
  - **`other_contact` é `null` enquanto `status <> 'accepted'`.** Nenhuma outra superfície revela contatos.

### 5.4 Ofertas e necessidades

- `offer_need_upsert(p_id uuid, p_entity uuid, p_kind text, p_topic text, p_title text, p_description text, p_valid_until date)` → uuid. Para criar, `p_id = null`.
  - Só gestor ativo de ficha publicada (ficha reivindicada). `p_kind`: `offer | need`. `p_topic`: `tools | space | volunteering | knowledge | materials | other`. `p_title` 3–140; `p_description` ≤ 2000.
  - `p_valid_until`: de hoje até hoje + 365 dias (sugira 90). **Expira sozinho**: no dia seguinte a `valid_until`, some de `entity_page`, `offers_needs_feed`, `public_stats` e `has_offers`, sem tarefa agendada.
  - Máximo 20 itens vigentes por ficha.
- `offer_need_remove(p_id uuid)` → void.
- `my_offers_needs()` → tabela `id, entity_id, entity_slug, kind, topic, title, description, valid_until, expired`.

### 5.5 Aceitar convite (iniciativas de exposição alta)

`invite_accept(p_token text, p_consent_text_version text, p_location text default 'city', p_summary_pt text default null)` → `{ "entity_id": uuid, "slug": text }`

- Exige login. `p_consent_text_version`: versão do texto de autorização que a pessoa leu (`^[a-z0-9._-]{1,40}$`, ex.: `convite-2026-11`). `p_location`: `city` (aparece no centro da cidade) ou `none` (sem cidade e sem ponto no mapa). `p_summary_pt` opcional (10–200) substitui o resumo proposto.
- Na mesma transação: valida e **consome** o token (uso único), registra a autorização, publica a ficha, torna a conta gestora ativa (`holder_confirmed`) e avisa o moderador.
- Token inválido, usado, revogado ou expirado → `P0002`.

## 6. Painel editorial (moderador)

Exige papel `moderator` (concedido no banco; ver `README_DEPLOY.md`). Para os demais, toda função `mod_*` responde `P0002`.

- `mod_queue_counts()` → `{ takedowns, claims, reports, suggestions, contact, edits, invites_pending }` (itens abertos).
- `mod_list(p_queue text, p_status text default null, p_limit integer default 50, p_offset integer default 0)` → jsonb (array). `p_queue`: `takedowns | claims | reports | suggestions | contact | edits | invite_candidates | invitations`. Sem `p_status`, devolve os abertos. Teto 200.
- `mod_restore_auto_hidden(p_since timestamptz, p_until timestamptz, p_ip_hash text default null, p_email_hash text default null, p_rationale text default null)` → integer (**desfazer em lote**). Restaura todas as fichas ocultadas automaticamente na janela (`hidden_at` entre `p_since` e `p_until`, inclusive) e, se informados, só as do `ip_hash` e/ou `email_hash` dados, que ainda estejam ocultas de forma reversível (não arquivadas nem com tombstone) e com pedido `open`. Marca esses pedidos como `restored`, grava uma linha de auditoria por ficha (`entity.restored_batch`) e uma do lote (`takedown.batch_restored`) e devolve quantas fichas foram restauradas. `p_rationale` com 10+ caracteres (`22023` se faltar); janela inválida → `22023`.
- `mod_takedown_overview(p_hours integer default 48)` → jsonb para o painel: `{ window_hours, breaker { hidden_last_hour, limit_per_hour, hidden_last_24h, limit_per_day, limit_per_email_day, tripped, contained_last_24h, last_containment_alert_at, confirm_emails_last_24h, confirm_emails_limit_per_day }, by_ip [ { ip_hash, requests, hidden, contained, awaiting, first_at, last_at } ], by_email [ { email_hash, email_domain, requests, hidden, contained, awaiting, domain_matches, first_at, last_at } ] }`. Nenhum e-mail em claro: só o domínio e o hash (use os hashes como filtro do lote). Teto de 50 linhas por grupo; `p_hours` de 1 a 720.
- `mod_decide_takedown(p_request uuid, p_decision text, p_rationale text)` → void. `confirm`: retirada definitiva com tombstone (bloqueia reimportação). `restore`: republica e exige `p_rationale` ≥ 10. `reject_keep_hidden`: encerra o pedido e mantém oculta.
- `mod_decide_claim(p_claim uuid, p_approve boolean, p_rationale text)` → void (≥ 10 caracteres). Serve para (b) e (c).
- `triage_report(p_report uuid, p_status text, p_note text)` (Marco B): `triaged | actioned | closed`.
- `mod_decide_suggestion(p_id uuid, p_status text, p_note text)` → void: `accepted | rejected | duplicate`.
- `mod_mark_contact(p_id uuid, p_status text)` → void: `read | answered | spam`.
- `review_version(p_version uuid, p_decision text, p_kind text, p_rationale text)` (Marco B): aprova edição sensível (exige também papel `curator`).
- `hide_entity(p_entity, p_reason_code)` e `withdraw_entity(p_entity, p_reason_code)` (Marco B).
- Convites: `mod_create_invite(p_candidate uuid, p_days integer default 30)` → `{ invitation_id, token, expires_at, path: "/#convite-<token>" }`. **O token só aparece nesta resposta** (o banco guarda só o hash); o moderador envia o link pelo canal público da iniciativa. Criar novo convite revoga o anterior pendente. `mod_revoke_invite(p_invitation uuid)` → void.

Toda decisão grava auditoria (`app.audit_log`, privada).

Campos devolvidos por `mod_list` (cada item é um objeto):

| Fila | Campos |
|---|---|
| `takedowns` | `id, entity_id, entity_name, entity_slug, entity_state, reason, relation, contact, locale, auto_hidden, contained, status, created_at, decided_at, rationale, email, email_domain, email_domain_matches, email_hash, ip_hash, confirmed_at, hidden_at` (status: `awaiting_confirmation, open, confirmed, restored, closed_kept_hidden, expired`; sem `p_status`, só `open`; `awaiting_confirmation` não entra na fila nem no contador) |
| `claims` | `id, entity_id, entity_name, entity_slug, website_url, method, status, claim_statement, verify_domain, published_code, evidence_url, claimant_email, created_at, decided_at, rationale` (sem `p_status`: `pending` + `awaiting_evidence`) |
| `reports` | `id, kind, entity_id, entity_name, entity_slug, body, reporter_contact, priority, status, created_at, referral_note` |
| `suggestions` | `id, name, website, country_code, city, families, description, why, contact, locale, status, note, created_at` |
| `contact` | `id, sender_name, sender_email, subject, body, locale, status, created_at` |
| `edits` | `version_id, entity_id, entity_name, entity_slug, proposal, base_version_no, current_version_no, status, submitted_at` |
| `invite_candidates` | `id, research_id, name, kind, country_code, city, website_url, source_url, summary_pt, status, entity_id, last_invitation {id, status, expires_at}` |
| `invitations` | `id, candidate_id, name, status, expires_at, used_at, created_at` |

## 7. Fluxo dos 173 de exposição alta (convite e consentimento)

1. Os 173 ficam **só** em `app.invite_candidates` (privada; RLS sem leitura para anon/authenticated; carga apenas com `build_seed.py --private-invites`, em arquivo separado que não vai ao repositório). Nenhuma view, função pública, contador, busca ou exportação lê essa tabela.
2. O moderador lista (`mod_list('invite_candidates')`) e gera um convite (`mod_create_invite`) → token de uso único com validade.
3. A iniciativa abre `/#convite-<token>`, vê a prévia (`invite_preview`) e escolhe: aceitar (login + `invite_accept`) ou recusar (`invite_decline`).
4. Aceite → ficha publicada já gerida pela iniciativa. Recusa → tombstone; nunca entra.
5. Sem resposta até a validade → o token deixa de valer; o candidato continua privado.

## 8. E-mails (servidor)

O front **não envia e-mail** e nunca vê o endereço do moderador. Funções do banco gravam um evento em `app.notification_outbox`; um webhook do banco chama a Edge Function `notify`, que envia via Resend.

| Evento | Destino | Gatilho |
|---|---|---|
| `connect_received` | gestores da ficha pedida | `connect_request` (ou aprovação de reivindicação com pedidos guardados) |
| `connect_accepted` | conta solicitante | `connect_respond` com aceite |
| `claim_code` | `p_email` informado em (a) | `claim_start`, `claim_resend_code` |
| `claim_pending` | moderador | (b) com evidência, (c) |
| `claim_approved` / `claim_rejected` | conta reivindicante | decisão ou verificação |
| `takedown_confirm` | `p_email` do pedido (idioma do pedido: pt, en ou es) | `request_takedown` com e-mail válido dentro dos limites; o token vai por `notification_secrets` (apagado quando o envio conclui) e nunca é registrado em log |
| `takedown_request` | moderador | `confirm_takedown` que ocultou a ficha, ou `request_takedown` sem e-mail (ou acima do limite de e-mails); teto de 20 por 24 h |
| `takedown_containment` | moderador | primeiro pedido barrado pelo disjuntor em cada janela de 24 h (um único alerta) |
| `contact_message` | moderador (responder para o remetente) | `send_contact_message` |
| `invite_accepted` | moderador | `invite_accept` |

## 9. Funções exclusivas do servidor (service_role)

Não use no front. A Edge Function chama: `notification_pending(p_limit)`, `notification_claim(p_id)` e `notification_done(p_id, p_ok, p_error)`.

## 10. Registro de mudanças

- 1.0 (21/11/2026): versão inicial.
- 1.1 (21/11/2026, só acréscimos, implementado e testado): campos de cada fila de `mod_list` (§6); `my_account().managed[]` ganha `publication_state`; regra de slug tenta antes um dos outros nomes (`alt_names`) com letras latinas, e só depois `<país>-<8 hex>`; `invite_preview` e `invite_decline` têm limite por IP (30/h); `purge_expired()` disponível para `service_role`.
- 1.2 (21/11/2026, retirada com proteção contra abuso, migração `0012`): `request_takedown` ganha `p_email` e **nunca oculta** (a resposta passa a `{ request_id, hidden: false, needs_confirmation, queued }`; `hidden` agora é sempre `false`: é a única mudança de significado, aprovada pelo gestor antes da publicação); novas `confirm_takedown(p_token)` (anon/authenticated), `mod_restore_auto_hidden(...)` e `mod_takedown_overview(p_hours)` (moderador); `mod_list('takedowns')` ganha `contained, email, email_domain, email_domain_matches, email_hash, ip_hash, confirmed_at, hidden_at` e os estados `awaiting_confirmation` e `expired`; e-mails `takedown_confirm` e `takedown_containment`; configurações `takedown_autohide_per_hour` (15), `takedown_autohide_per_day` (50), `takedown_autohide_per_email_day` (3), `takedown_confirm_per_email_day` (3), `takedown_confirm_emails_per_day` (40), `takedown_mod_emails_per_day` (20); `purge_expired()` também expira pedidos não confirmados e apaga o e-mail em claro (`takedowns_expired`). Rota do front: `#confirmar-retirada-<token>` / `#confirm-withdrawal-<token>`.
