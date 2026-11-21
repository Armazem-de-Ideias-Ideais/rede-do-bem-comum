# Rede do Bem Comum — arquitetura do lançamento público (Fase 1)

Decisões aprovadas por Rafael Reinehr em 21/11/2026. Este documento é o contrato comum de todos os agentes. Em caso de dúvida, vale o `Briefing_Fable_52.md` do kit e o `Privacidade_e_Publicacao_Requisitos.md`.

## Decisões
- **Publicação.** Cerca de 1.717 iniciativas de exposição baixa ou média vão ao ar com aviso público e retirada fácil. **Os 173 de exposição alta NÃO entram em nenhuma tabela pública**: ficam numa lista privada e só são publicados após aceite por convite.
  - Registros com indício de encerramento: fora.
  - Registros com nota "aderência a avaliar": passam por triagem antes (arquivo `data/triagem_aderencia_246.json`).
- **Licença dos dados:** ODbL 1.0 para a base pública.
  - Página de atribuição listando as fontes.
  - Frase obrigatória para registros da Karte von Morgen: "Contém dados da Karte von Morgen / OpenFairDB, disponíveis sob ODbL".
  - **Licença do código:** AGPL-3.0.
- **Responsáveis (controladores):** Rafael Reinehr, The Brains & Love Cooperation e Coolmeia — Ideias em Cooperação.
- **Moderação:** Rafael Reinehr. **O e-mail pessoal dele nunca aparece** em código cliente, repositório, página ou log. Fica só como segredo de servidor (variável `MODERATOR_EMAIL`).
  - Contato público: formulário no site, gravado no banco, com notificação por e-mail para o moderador feita no servidor.
- **Domínio:** `bemcomum.coolmeia.org`. Trocar depois é barato; o código não pode fixar o domínio (use variável `SITE_URL`).
- **Orçamento:** teto de US$ 40–50/mês, quanto menos melhor. Lançamento em **US$ 0**:
  - Cloudflare Pages: grátis;
  - Supabase: plano gratuito;
  - Resend: plano gratuito, 3.000 e-mails/mês;
  - Supabase Pro (US$ 25) só quando o tráfego exigir, com aprovação prévia.
- **Idiomas:** português e inglês no lançamento; espanhol na Fase 2.
  - Os resumos das fichas são originais em PT. A tradução EN é automática e marcada como tal ("tradução automática, sem revisão").

## Pilha
- **Front:** site estático em `web/`, JavaScript puro, sem framework e sem etapa obrigatória de build, como o protótipo do Marco A (`/home/claude/work/build/prototype/`).
  - Hospedagem em Cloudflare Pages.
  - Bibliotecas por CDN ou vendorizadas: MapLibre GL e `@supabase/supabase-js` v2.
  - `web/config.js` guarda só `SUPABASE_URL` e `SUPABASE_ANON_KEY`, ambos públicos por natureza.
- **Banco e autenticação:** Supabase (Postgres 15, PostGIS disponível), autenticação por **link mágico por e-mail**.
  - Base: migrações do Marco B em `/home/claude/work/build/db/migrations` (schemas `app` privado, `pub` projeção e `api` exposto; RLS; tombstones; consentimentos; versões).
  - O Marco C acrescenta o que falta (abaixo) em `supabase/migrations/`.
- **E-mails:** uma Supabase Edge Function (Deno) chamada por webhook do banco ou por RPC. Ela envia por Resend as notificações de:
  - pedido de conexão;
  - reivindicação;
  - formulário de contato e pedido de retirada (estes para o moderador).
  - Segredos `RESEND_API_KEY` e `MODERATOR_EMAIL` só na função.
- **Repositório:** GitHub, organização `Armazem-de-Ideias-Ideais`, repositório `rede-do-bem-comum` (a criar). Nenhum segredo no repositório.

## Funcionalidades da Fase 1
1. **Mapa e lista.** Agrupamento por cidade (posição = centro da cidade, dito na legenda), filtros por família, presença, país e selo de atividade, busca sem acentos. A lista funciona sem o mapa.
2. **Ficha pública** em `/#i-<slug>`, ou rota equivalente compatível com Pages. Contém:
   - nome, natureza, famílias, resumo PT e EN (com o estado da tradução), site próprio, fonte e atribuição;
   - selo de atividade: "ativa em 2026", "fonte consultada em nov/2026" ou "atividade a confirmar";
   - **iniciativas-irmãs**: mesmas famílias em outros países, mais complementares na mesma cidade;
   - ofertas e necessidades vigentes;
   - botões **"É sua? Reivindique"**, **"Corrigir"** e **"Retirar do mapa"**.
3. **Retirada.** Pedido sem login (com antispam) **oculta a ficha imediatamente, de forma preventiva**, em mapa, lista, busca, contadores e exportação. O pedido entra na fila do moderador, que confirma a retirada (vira tombstone contra reimportação) ou restaura com justificativa.
4. **Conta** por link mágico. A conta é privada; não cria perfil público.
5. **Reivindicação** de ficha. Verificação por um de três caminhos:
   - (a) e-mail no mesmo domínio do site próprio;
   - (b) código publicado no site ou na rede social da iniciativa;
   - (c) aprovação manual do moderador.

   Quem gere a ficha propõe edições; edição de campo sensível passa por revisão.
6. **Conectar.** Uma iniciativa gerida pede contato a outra. A pedida recebe e-mail (se tiver gestor) ou o pedido fica guardado até ela reivindicar a ficha. Os contatos só aparecem para os dois lados depois do aceite. Há limite de pedidos por dia.
7. **Ofertas e necessidades** entre iniciativas (ferramentas, espaço, voluntariado, saberes, materiais). Só iniciativas reivindicadas publicam; cada item tem validade e expira sozinho.
8. **Indicar uma iniciativa.** Formulário que entra na fila editorial, nunca publica direto.
9. **Painel editorial** (moderador): filas de retiradas, correções, reivindicações, indicações e denúncias, com decisão auditada.
10. **Sobre, Privacidade, Termos, Atribuição e Carta de convivência**, em PT e EN.

## Fase 2 (não implementar agora, mas não bloquear)
Círculos temáticos e regionais (Discourse com SSO), resumo mensal por e-mail, radar de financiamento, biblioteca de receitas, espanhol e salas Matrix E2EE.

## Dados
- `data/publicavel_v1.json`: 1.717 registros. Campos internos que NÃO vão a público: `research_notes`, `lot`, `exposure`, `audit`.
- `data/convite_alta_exposicao_PRIVADO.json`: 173 registros. **Nunca carregar em tabela pública, seed público, front ou repositório público.**
- Coordenadas públicas: só o centro da cidade (`city_lat`/`city_lng`) com `location_precision = 'city'`. Nada mais preciso existe na base.
