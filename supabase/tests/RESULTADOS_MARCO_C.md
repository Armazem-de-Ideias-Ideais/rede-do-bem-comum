# Resultados dos testes — Marco C (API e integridade de publicação)

Execução real em **21/11/2026**, Postgres local (cluster 16/main), sem nuvem. Comando:
`su postgres -c "bash supabase/tests/run_all.sh"`. Saídas brutas em `tests/output/` (`ciclo.log`, `b_rodada*.tap`, `c_detalhado.tap`).

## Ambiente

| Componente | Versão | Observação |
|---|---|---|
| PostgreSQL | 16.15 (Ubuntu 24.04) | Supabase usa 15/17; o código só usa recursos do 15+ |
| PostGIS / unaccent / pg_trgm | 3.4.2 / 1.1 / 1.6 | schema `extensions`, como no Supabase |
| pgTAP / pg_prove | 1.3.2 / 3.36 | |
| Shim Supabase | `tests/local_shim.sql` | papéis `anon`/`authenticated`/`service_role`, `auth.users`, `auth.uid()` |
| Dados | seed **real** gerado por `seed/build_seed.py` a partir de `data/publicavel_v1.json` + traduções + triagem; convites carregados **com** `--private-invites` | o arquivo privado gerado é apagado logo após a carga |

O papel e o JWT são simulados como o PostgREST faz (`set_config('role')` + `request.jwt.claims`); o IP do cliente, pelo cabeçalho `request.headers` (`cf-connecting-ip`).

## Resumo

| Etapa | Resultado |
|---|---|
| B1 — migrações 0001–0011 + seed sintético + suíte do Marco B | **187/187** PASS |
| B2 — DOWN do Marco C (0011→0008), resíduos do C e suíte do Marco B | resíduos **0**; **187/187** PASS |
| B3 — UP do Marco C sobre dados já existentes (preenche slugs) e suíte do Marco B | 0 entidades sem slug; **187/187** PASS |
| B4 — DOWN completo (0011→0001) | schemas `app/pub/api` removidos; 0 trigger em `auth.users` |
| C1 — seed público real | 1.717 de entrada → **1.544 `inserted`** (171 "segurar"; 2 com indício de encerramento); carga em ~4 s |
| C1 — seed privado (flag) | **173 `inserted`** em `app.invite_candidates` |
| C2 — recarga do seed público (idempotência) | **1.544 `updated`**, 0 `inserted` |
| C3 — suíte do Marco C (7 arquivos) | **244/244** PASS |

Contadores após a carga (`api.public_stats`): 1.544 fichas · 88 países · 652 cidades · 966 locais físicos · 1.054 iniciativas · 174 grupos territoriais · 290 redes · 26 recursos online.

## Suíte do Marco C

| Arquivo | Asserções | O que prova |
|---|---|---|
| `10_privacy_surface.sql` | 30 | **anon não lê nada privado**: nenhum privilégio de anon em `app` (inclui tabelas novas); RLS em 100% de `app`; nenhuma coluna interna/privada (`research_id`, `lot`, `exposure`, `audit`, `research_notes`, e-mails, contatos, hashes) em `api`/`pub`; os campos internos nem existem no banco; nenhuma DEFINER em `api`; nada executável por PUBLIC; anon executa só as 7 funções públicas previstas; fila de e-mail só para `service_role`; conta comum não lê candidatos, mensagens, hash de código nem o painel |
| `11_takedown_tombstone.sql` | 47 | **retirada preventiva some de todas as superfícies na mesma transação** (lista/mapa, slug, id, detalhe, view `entities`, busca, autocomplete, locais, mapa por área, irmãs, feed de ofertas, sitemap, 4 contadores); honeypot; validação; IP só como hash; moderador notificado; outbox de cache; **seed não republica ficha oculta**; limite 5/h por IP; disjuntor; restaurar exige justificativa; confirmação gera tombstones só com hashes; **reimportação bloqueada** por id, nome+país e domínio do site; registro sem relação entra normalmente |
| `12_connect.sql` | 31 | **conta A não lê contato de B (nem B o de A) antes do aceite**; só gestor ativo pede; um pendente por par; terceiro não vê nada; após aceite os dois lados veem; e-mails de recebido/aceito; pedido para ficha sem gestor fica guardado e é entregue na reivindicação; ficha que recusa pedidos responde igual e não recebe |
| `13_invites_high_exposure.sql` | 36 | **nenhum dos 173 aparece em view pública mesmo carregados com a flag** (por id, nome, busca por cada nome, slug, sitemap, contadores, locais, textos, exportação); seed público recusa candidato; **convite só funciona uma vez** (aceite e prévia falham depois), **expira**, é revogado por novo convite; token só como hash e fora da auditoria; aceite exige login e versão do texto, publica já gerida; recusa gera tombstone e bloqueia recarga |
| `14_offers_counters.sql` | 30 | **ofertas expiradas não aparecem** (feed, view do Marco B, ficha, `has_offers`, contador) sem tarefa agendada; renovação e remoção; validações; **contadores contam local uma vez** (local compartilhado por duas iniciativas = 1 local; mapa mostra 1 ponto com 2 fichas); classes disjuntas; redes/territórios/online sem local físico |
| `15_claims.sql` | 33 | reivindicação pelos **três caminhos**: (a) e-mail no domínio do site (plataformas compartilhadas e domínio diferente recusados; código de 6 dígitos em tabela de segredos; hash ilegível; tentativas; falha após 5 erros; aprovação imediata quando o e-mail da conta é do domínio), (b) código publicado + URL conferida pelo moderador, (c) manual com justificativa; quem reivindica não decide |
| `16_notify_forms_edits.sql` | 37 | formulário de contato (validação, honeypot, 3/h por IP, e-mail privado); fila de e-mail: só `service_role`, contexto sem o e-mail do moderador, reserva idempotente; indicação vai para a fila e não publica; relato; edição do gestor: resumo/site na hora, nome em revisão; **slug antigo redireciona** após renomeação; irmãs (outro país + família comum; complementares sem família comum; ordem estável); correção de `publication_blockers` |

## Desempenho (ordem de grandeza, dentro do Postgres, papel anon, 1.544 fichas)

| Consulta | Mediana | p95 |
|---|---|---|
| `entity_list` (todas as colunas) | 22,5 ms | 27,5 ms |
| `entity_list` (colunas do mapa) | 9,5 ms | 13,4 ms |
| `entity_page` | 0,5 ms | 0,8 ms |
| `sister_initiatives` | 8,5 ms | 9,4 ms |
| `public_stats` | 1,9 ms | 2,1 ms |
| `search_entities` | 0,8 ms | 3,8 ms |

## Correção encontrada no Marco B

`app.publication_blockers` (0006) falhava com "malformed array literal" sempre que havia **algum** bloqueio (`b := b || 'nome'`), em vez de devolver a lista; `publish_entity` de rascunho incompleto dava erro errado. A suíte do Marco B não exercitava esse caminho. Corrigido em `0009` (só `::text`); o DOWN restaura a versão original. Coberto em `16_…`.

## Não executado ou não testável nesta etapa

- **Supabase real, PostgREST e HTTP:** não houve projeto em nuvem (por restrição). Faltam: JWT verdadeiro, chave anon, cabeçalhos e erros do PostgREST, `Accept-Profile`, limite de 1.000 linhas.
- **Cabeçalho de IP:** o antispam assume `cf-connecting-ip`/`x-real-ip`/`x-forwarded-for` em `request.headers`. Confirmar em staging (README_DEPLOY §10.3). Sem o cabeçalho, os limites caem num balde comum (vira disjuntor global).
- **Edge Function `notify`:** verificada com `tsc --strict` e teste de fumaça dos modelos (escape de HTML, 9 tipos, PT/EN); **não** foi executada no runtime Deno nem contra a Resend; o webhook e o `pg_cron` não foram exercitados.
- **Auth (link mágico, PKCE, SMTP):** só configuração documentada.
- **Concorrência real** (duas sessões disputando o mesmo convite ou pedido): há `FOR UPDATE`, mas sem teste de corrida.
- **Verificação automática do código publicado (b):** por decisão de segurança (SSRF), quem confere a URL é o moderador.
