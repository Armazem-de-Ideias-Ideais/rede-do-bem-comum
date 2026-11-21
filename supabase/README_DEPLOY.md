# Rede do Bem Comum: passo a passo do deploy do backend (Supabase, plano gratuito)

Este guia cria o projeto Supabase, aplica as migrações, configura o login por link mágico com SMTP da Resend, carrega os dados, publica a Edge Function `notify` e liga o webhook. **Nenhum valor secreto aparece aqui.** Onde houver `<...>`, digite o valor no painel ou no terminal, nunca num arquivo do repositório.

Contrato da API para o front: `docs/API_CONTRATO.md`. Arquitetura: `docs/ARQUITETURA_LANCAMENTO.md`.

## 0. Antes de começar

| Item | Para quê | Custo |
|---|---|---|
| Conta Supabase | Banco, autenticação, Data API, Edge Function | Plano gratuito (US$ 0) |
| Conta Resend com domínio verificado | E-mails do login e das notificações | Gratuito: 3.000 e-mails/mês, 100/dia |
| `psql` (cliente PostgreSQL) | Aplicar migrações e carregar o seed | — |
| Python 3.9+ | Gerar o SQL do seed | — |
| Supabase CLI (opcional) | `db push`, `functions deploy`, `secrets set` | — |

Guarde todas as senhas e chaves num gerenciador de senhas. Nada de `.env` no git.

**Limites do plano gratuito que importam:** projeto pausa após 7 dias sem nenhuma requisição (o tráfego do site evita isso); 500 MB de banco; 500 mil invocações de Edge Function por mês. Upgrade para o Pro (US$ 25/mês) só com aprovação prévia.

## 1. Criar o projeto

1. Painel do Supabase → **New project**. Nome: `rede-do-bem-comum`. Região: a mais próxima do público principal (ex.: São Paulo, `sa-east-1`).
2. Gere a senha do banco no próprio formulário e guarde-a no gerenciador de senhas.
3. Anote o **Project ref** (aparece na URL do painel) e, em **Project Settings → API Keys**, a **chave anon/publishable** (vai para o front) e a **service role/secret** (só servidor; nunca no front nem no repositório).
4. **Connect** (botão no topo) → copie a *connection string* (modo "Session pooler" serve para o `psql`). Use-a numa variável só no terminal:
   ```bash
   read -rs DATABASE_URL   # cole a string e tecle Enter; não fica no histórico
   export DATABASE_URL
   ```

## 2. Expor somente o schema `api`

Painel → **Project Settings → Data API**:
- **Exposed schemas:** deixe **apenas `api`** (retire `public` e `graphql_public`).
- **Extra search path:** `extensions`.
- **Max rows:** `1000`.

Opcional e recomendado: **Database → Extensions** → desative `pg_graphql` se não for usar GraphQL.

## 3. Aplicar as migrações

As migrações estão em `supabase/migrations/` (0001–0007 do Marco B, 0008–0011 do Marco C), sempre nesta ordem. As reversões ficam em `supabase/migrations_down/` (não são aplicadas no deploy).

**Opção A — psql (recomendada):**
```bash
for f in $(ls supabase/migrations/*.sql | sort); do
  psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 -f "$f" || { echo "parou em $f"; break; }
done
```

**Opção B — Supabase CLI:** `supabase link --project-ref <PROJECT_REF>` e `supabase db push` (a pasta `migrations/` já está no formato do CLI; `migrations_down/` é ignorada).

**Opção C — SQL Editor do painel:** abra cada arquivo de `migrations/` em ordem, cole e rode. Não pule nenhum.

**Nunca** aplique `supabase/tests/local_shim.sql`, `supabase/tests/seed_synthetic.sql` nem `supabase/tests/helpers.sql` no projeto: são só para testes locais (o Supabase já tem `auth`, papéis e extensões).

Depois, marque o ambiente como produção (bloqueia dados sintéticos):
```sql
update app.settings set value = 'production' where key = 'environment';
```

## 4. Autenticação (link mágico) e SMTP da Resend

1. **Resend → Domains:** adicione o domínio de envio (ex.: um subdomínio de `coolmeia.org`) e crie no DNS os registros SPF e DKIM indicados (DMARC recomendado). Espere a verificação.
2. **Resend → API Keys:** crie duas chaves com permissão *Sending access*: uma para o SMTP do Supabase Auth e outra para a Edge Function (assim dá para revogar uma sem parar a outra).
3. **Supabase → Authentication → Emails → SMTP Settings:** ative *Custom SMTP*:
   - Host `smtp.resend.com`, porta `465`, usuário `resend`, senha = chave da Resend para SMTP;
   - Sender email: endereço do domínio verificado (ex.: `avisos@<seu-dominio>`); Sender name: `Rede do Bem Comum`.
4. **Authentication → Sign In / Providers → Email:** habilitado; *Confirm email* desligado (o link mágico já confirma). Sem senha no lançamento.
5. **Authentication → URL Configuration:**
   - **Site URL:** `https://bemcomum.coolmeia.org` (ou o domínio vigente; o código não fixa domínio).
   - **Redirect URLs:** `https://bemcomum.coolmeia.org/**`, `https://<projeto>.pages.dev/**` (prévias do Cloudflare Pages) e `http://localhost:8788/**` (desenvolvimento).
6. **Authentication → Emails → Templates → Magic Link:** texto bilíngue curto, por exemplo: assunto "Seu link de acesso · Your sign-in link"; corpo com `{{ .ConfirmationURL }}` e a frase "Se não foi você, ignore este e-mail / If this wasn't you, ignore this email."
7. **Authentication → Rate Limits:** ajuste "emails sent per hour" ao volume esperado (com SMTP próprio, o padrão é baixo; 30–60/h é razoável no lançamento, respeitando 100/dia da Resend gratuita).

O front deve usar `flowType: 'pkce'` (ver contrato §1).

## 5. Carregar os dados

1. Gere o SQL localmente, a partir da raiz do repositório de dados:
   ```bash
   python3 -I supabase/seed/build_seed.py \
     --dados data/publicavel_v1.json --traducoes data/traducoes_en.json \
     --triagem data/triagem_resultado.json --pendentes data/triagem_aderencia_246.json
   ```
   Saída em `supabase/seed/out/` (pasta ignorada pelo git) e um resumo em `resumo_seed.json`. Na versão de 21/11/2026: 1.717 de entrada → **1.544 publicáveis** (171 "segurar" na triagem; 2 com indício de encerramento).
2. Carregue:
   ```bash
   psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/seed/out/seed_publico.sql
   ```
   Resultado esperado: `inserted | 1544`. Pelo SQL Editor, use os arquivos `seed_publico_parte_NN.sql` em ordem (a parte 01 traz as famílias).
3. A carga é **idempotente**: rodar de novo devolve `updated` e nunca republica fichas retiradas, ocultas ou geridas pela própria iniciativa; registros com tombstone voltam `blocked_by_tombstone`.
4. **Convites de exposição alta (173):** só quando houver decisão de iniciar os convites. Gere com a flag explícita e carregue; depois apague o arquivo:
   ```bash
   python3 -I supabase/seed/build_seed.py ... --private-invites data/convite_alta_exposicao_PRIVADO.json
   psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/seed/out/PRIVADO_convites.sql
   rm supabase/seed/out/PRIVADO_convites.sql
   ```
   Esses registros vão só para `app.invite_candidates` (privada) e não aparecem em nenhuma superfície pública até o aceite do convite.

## 6. Papel do moderador

1. Abra o site, entre com o e-mail do moderador pelo link mágico (isso cria a conta).
2. No **SQL Editor** (digite o e-mail na hora; não salve a consulta com ele):
   ```sql
   insert into app.role_grants(account_id, role, granted_by)
   select u.id, r::app.staff_role, null
     from auth.users u, unnest(array['moderator','curator','admin']) r
    where u.email = '<E-MAIL-DA-CONTA-DO-MODERADOR>';
   insert into app.audit_log(actor, action, target_table, details)
   values (null, 'role.bootstrap', 'role_grants', '{"note":"moderador inicial"}');
   ```
   `curator` permite aprovar edições sensíveis; `admin` permite conceder papéis a outras contas pelo próprio sistema (`api.grant_role`), nunca a si mesmo.

## 7. Edge Function `notify`

1. Gere um segredo para o webhook (ex.: `openssl rand -hex 32`) e guarde-o no gerenciador.
2. Defina os segredos da função em **Edge Functions → Secrets** (painel) ou pelo CLI com um arquivo temporário fora do repositório, apagado em seguida:
   | Nome | Valor |
   |---|---|
   | `RESEND_API_KEY` | chave da Resend para a função |
   | `MODERATOR_EMAIL` | e-mail do moderador (só aqui) |
   | `SITE_URL` | `https://bemcomum.coolmeia.org` |
   | `FROM_EMAIL` | `Rede do Bem Comum <avisos@<seu-dominio>>` |
   | `NOTIFY_WEBHOOK_SECRET` | o segredo do passo 1 |

   `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` já existem automaticamente.
3. Publique: `supabase functions deploy notify --project-ref <PROJECT_REF>` (o `config.toml` já define `verify_jwt = false`; a função checa o segredo sozinha).

## 8. Webhook do banco → função

**Painel → Database → Webhooks → Create a new hook:**
- Nome `notify_outbox`; tabela **`app.notification_outbox`**; evento **Insert**.
- Tipo **Supabase Edge Functions** → função `notify`, método POST, timeout 5000 ms.
- HTTP headers: `Content-Type: application/json` e `x-webhook-secret: <NOTIFY_WEBHOOK_SECRET>`.

Se o painel não listar tabelas do schema `app`, crie pelo SQL Editor (o segredo fica no catálogo do banco, que é privado; troque-o se vazar):
```sql
create trigger notify_outbox_webhook after insert on app.notification_outbox
for each row execute function supabase_functions.http_request(
  'https://<PROJECT_REF>.supabase.co/functions/v1/notify', 'POST',
  '{"Content-Type":"application/json","x-webhook-secret":"<NOTIFY_WEBHOOK_SECRET>"}', '{}', '5000');
```

**Rede de segurança (recomendada):** com `pg_cron` e `pg_net` ativos (Database → Extensions), guarde o segredo no Vault e agende a drenagem e a limpeza:
```sql
select vault.create_secret('<NOTIFY_WEBHOOK_SECRET>', 'notify_webhook_secret');
select cron.schedule('rbc-notify-drain', '*/10 * * * *', $$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/notify',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'notify_webhook_secret')),
    body := '{"drain": true}'::jsonb) $$);
select cron.schedule('rbc-purge', '17 3 * * *', $$ select app.purge_expired() $$);
```
A função é idempotente: a mesma notificação nunca é enviada duas vezes (reserva no banco + `Idempotency-Key` na Resend).

## 9. Front

`web/config.js` recebe só `SUPABASE_URL` (`https://<PROJECT_REF>.supabase.co`) e a chave anon/publishable. Nenhuma outra chave vai para o navegador.

## 10. Verificação depois do deploy

Com a chave anon numa variável de terminal (`ANON`):
```bash
curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/entity_list?select=slug&limit=2" \
  -H "apikey: $ANON" -H "Accept-Profile: api"                       # 2 fichas
curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/public_stats" -H "apikey: $ANON" -H "Accept-Profile: api"
curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/invite_candidates" -H "apikey: $ANON" -H "Accept-Profile: app"
                                                                     # deve falhar: schema app não exposto
```
Depois:
1. Envie o formulário de contato pelo site → o moderador recebe o e-mail; em `app.notification_outbox` a linha fica com `sent_at`.
2. Faça um pedido de retirada de teste numa ficha, confira que ela some da lista, e **restaure** pelo painel com justificativa.
3. Confirme que o hash de IP está chegando (antispam): `select count(*), count(ip_hash) from app.takedown_requests;` (os dois números devem ser iguais). Se `ip_hash` vier nulo, o cabeçalho de IP não está chegando ao banco e os limites caem num balde comum.
4. Rode **Advisors → Security** no painel e confira que não há views *security definer* nem tabelas expostas sem RLS.

## 11. Reverter

Faça backup antes (Database → Backups, ou `pg_dump`). Para desfazer só o Marco C, aplique `migrations_down/0011…0008` em ordem decrescente; para tudo, `0011…0001`. Os arquivos `down` apagam dados das estruturas que removem. Após restaurar um backup, rode `select app.reapply_suppressions();` **antes** de reabrir o tráfego.

## 12. Checklist de segredos

- [ ] Nenhum e-mail pessoal, senha, chave ou token em arquivo versionado.
- [ ] `service_role`/secret key só na Edge Function (automática) e no gerenciador de senhas.
- [ ] `MODERATOR_EMAIL` só nos Secrets da função.
- [ ] `PRIVADO_convites.sql` apagado depois da carga; `data/convite_alta_exposicao_PRIVADO.json` fora do repositório público.
- [ ] Logs da função não registram endereços, códigos nem mensagens (já é o comportamento do código).
