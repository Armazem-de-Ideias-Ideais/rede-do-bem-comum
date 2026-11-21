# Resultados dos testes — migração 0012 (retirada com proteção contra abuso)

Execução real em **21/11/2026**, Postgres 16 local, sem rede e sem nuvem. Nada foi publicado nem implantado.

- Banco: `su postgres -c "bash supabase/tests/run_all.sh"` (saídas brutas em `supabase/tests/output/`: `ciclo.log`, `b_rodada*.tap`, `c_detalhado.tap`, `esquema_*.txt`).
- Front: `node tests_web/run_tests.js` (Playwright + Chrome do sistema; resultados em `tests_web/results.json`).

## Banco

| Etapa | Resultado |
|---|---|
| B1 — migrações 0001–0012 + seed sintético + suíte do Marco B | **187/187** |
| B2 — DOWN do Marco C (0012→0008), resíduos e suíte do Marco B | resíduos **0**; **187/187** |
| B3 — UP do Marco C (0008→0012) sobre dados existentes e suíte do Marco B | 0 entidades sem slug; **187/187** |
| B4 — DOWN completo (0012→0001) | nenhum schema restante; 0 trigger em `auth.users` |
| C1/C2 — seed real (1.544 públicas, 173 convites privados) e recarga idempotente | 1.544 `inserted`, depois 1.544 `updated` |
| C3 — suíte do Marco C (8 arquivos) | **384/384** (antes da 0012: 244) |
| D — 0012 UP + DOWN devolve o esquema do 0011 | **idêntico** (1.167 itens comparados: funções com definição e EXECUTE, colunas, restrições, índices, configurações e privilégios de tabela; o 0012 altera 59 linhas dessa fotografia) |

Por arquivo do Marco C: `10_privacy_surface` 30 · `11_takedown_tombstone` 52 (era 47) · `12_connect`, `13`, `14`, `15`, `16` sem mudança (167 no total) · `17_takedown_abuse` **135** (novo).

### O que o `17_takedown_abuse.sql` cobre

Pedido nunca oculta sem confirmação; confirmar oculta; token de uso único, vencido, malformado, inexistente e nulo com o mesmo erro genérico (`P0002`, "link inválido ou vencido"); só o sha256 do token no banco e o token em claro ausente de pedidos, tokens, fila e auditoria; segredo apagado depois do envio; 3 e-mails de confirmação por e-mail por dia (caixa alta e espaços não escapam); disjuntor por e-mail, por hora e por dia, com um único alerta `takedown_containment` por janela de 24 h; limite global de e-mails de confirmação vira fila; teto de 20 e-mails por dia à moderação; resposta idêntica para ficha inexistente, oculta ou publicada (e nenhum token gasto nesses casos); honeypot; `email_domain_matches` (verdadeiro, domínio compartilhado, ficha inexistente, nulo sem e-mail); lote por janela, por `ip_hash` e por `email_hash`, sem restaurar ficha arquivada pela moderação, com justificativa obrigatória, auditoria por ficha e por lote; visão agrupada sem e-mail em claro; `purge_expired` expira pedidos e apaga o e-mail; anon e conta comum sem acesso às funções de moderação nem a e-mail, token ou hash.

### Ajustes em testes existentes

- `10_privacy_surface`: `confirm_takedown` entra na lista de funções que `anon` executa; `takedown_tokens` e `email_hash`/`email_domain`/`email_domain_matches` entram nas verificações de privacidade.
- `11_takedown_tombstone`: o pedido agora passa por e-mail + confirmação antes de todas as asserções de "some de todas as superfícies" (as asserções originais de superfície, tombstone e reimportação foram mantidas); honeypot, e-mail inválido, "ficha continua no ar até confirmar", disjuntor via confirmação e W sem e-mail (fila) foram atualizados. Em vez de "E5 ocultada pelo 1º pedido", o total agora volta ao inicial (pedidos sem e-mail não ocultam).

## Front

`node tests_web/run_tests.js`: **62/62** verificações (antes: 51), 108 telas (antes 104: a rota de confirmação entrou na varredura PT/EN × 360/1280), 15 jornadas de teclado, 0 erros de console, 0 violações de CSP, 0 POST no modo static.

Novas verificações (API simulada por interceptação): campo e-mail com o texto exato da decisão e sem "na hora/imediat"; pedido com e-mail ("Enviamos um link para o seu e-mail") com `p_email` enviado; pedido sem e-mail (`p_email = null`, "Pedido na fila da moderação", 72 horas, ficha no ar); e-mail inválido barrado no formulário; limite `54000` com tela própria; ficha continua na lista depois dos três resultados; rota de confirmação com link válido ("Ficha retirada", ficha some da lista e da rota), na fila, desconhecido/vencido ("Link inválido ou vencido", atalho para novo pedido) e malformado (sem chamar o servidor); inglês (fila, link inválido, dica do formulário). Respostas 404/429 deliberadas do servidor simulado são contadas à parte (`mockHttpErrors`) e não como erro de console.

## Não testado aqui

- Edge Function `notify` rodando em Deno e o envio real pela Resend: não há Deno nem rede. Os modelos (`takedown_confirm` PT/EN/ES, `takedown_containment`, `takedown_request` revisado) foram executados em Node com remoção de tipos e conferidos à mão; o contrato banco → função (contexto de `notification_claim`) está coberto pelo pgTAP.
- Webhook do banco, `pg_cron` e o cabeçalho de IP real atrás do Cloudflare/Supabase (nos testes o IP é simulado por `request.headers`).
- PostgREST/supabase-js reais (o front foi testado contra interceptação) e Postgres 15/17 do Supabase (o teste foi no 16).
- Painel editorial: não há tela no front para `mod_restore_auto_hidden` e `mod_takedown_overview` (só as funções e o contrato).
