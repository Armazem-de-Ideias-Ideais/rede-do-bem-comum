# Rede do Bem Comum: notas do front-end (Fase 1)

21/11/2026. Site estático em `web/`, feito em JavaScript puro, sem etapa obrigatória de build e pronto para o Cloudflare Pages. **Nada foi publicado e nenhum recurso em nuvem foi criado.**

## Como gerar, servir e testar

- **Dados e textos.** Rode `python3 scripts/build_public_json.py` a partir de `rbc-app/`. O script gera:
  - `web/data/public.json`, com **1.546 fichas** (1.717 menos as 171 marcadas "segurar" na triagem);
  - `web/js/texts.js`, com os 6 textos de `docs/textos/` convertidos de Markdown para HTML, em PT e EN, mantendo as marcações de MINUTA.
- **Servidor local.** `node tests_web/serve.js 8765` serve `web/` com os cabeçalhos de `web/_headers`, a mesma CSP de produção.
- **Testes.** `node tests_web/run_tests.js` leva cerca de 4 minutos e grava `tests_web/results.json` e as capturas em `shots/`. A conferência das chaves de tradução também roda sozinha: `node tests_web/check_i18n.js`.
- **Modo de operação.** Fica em `web/config.js`:
  - `MODE: 'static'` é o padrão atual;
  - `MODE: 'supabase'` exige `SUPABASE_URL` e `SUPABASE_ANON_KEY`. Sem eles, o site continua em static;
  - `SITE_URL` vazio usa a origem atual. O domínio não está fixado no código.

## Arquitetura

- **Arquivos.** Reaproveitei do Marco A a identidade (`css/app.css`), os ícones, os assets e o MapLibre CSP vendorizado. Os acréscimos ficam em `css/site.css`. Os scripts, em ordem de carga, são `core`, `i18n`, `texts`, `icons`, `data`, `data-supabase`, `ui`, `map`, `view-*` e `app`.
- **Camada de dados.** Os dois adaptadores têm a mesma interface: `init`, `listInitiatives`, `sources`, `getPage?`, `siblings?`, `call`, `signIn`, `signOut`, `offersFeed` e `caps {auth, write}`.
  - **`static`** lê `data/public.json`. As iniciativas-irmãs são calculadas no cliente com a mesma regra de `api.sister_initiatives`: famílias em comum em outro país; complementares na mesma cidade sem família em comum.
  - **`supabase`** usa `vendor/supabase.js` (supabase-js 2.119.2, vendorizado e carregado só neste modo). Usa o schema `api` e PKCE, conforme o `API_CONTRATO.md` v1.0. Pagina `entity_list` por chave (`slug`), lê a ficha por `entity_page` (com redirecionamento por `canonical_slug`), as irmãs por `sister_initiatives` e as fontes por `attribution_sources`. Todas as ações são chamadas `rpc` com os parâmetros `p_*` do contrato. Os erros são traduzidos pelo `error.code` (§1.1).
  - **Lista branca no cliente.** Qualquer campo fora dos 22 campos públicos, mais `is_managed`, `has_offers` e `area_id` da API, é descartado na hora de indexar.
- **Busca e filtros no cliente.** Valem nos dois modos: busca sem acento e filtros por família, presença, país e selo. As contagens por faceta aplicam os outros filtros. A paginação é em janela, com 18 fichas por página.
- **Rotas.** Usam hash ASCII, com nomes próprios em cada língua. A ficha é `#i-<slug>` nas duas. As demais:
  - `#explorar`, `#participar`, `#sobre`, `#privacidade`, `#termos`, `#atribuicao`, `#carta-de-convivencia`, `#por-que-estou-aqui`, `#contato`, `#indicar`;
  - `#retirar[-slug]`, `#corrigir[-slug]`, `#reivindicar[-slug]`, `#conectar-slug`, `#editar-slug`;
  - `#entrar`, `#meu-espaco`, `#ofertas-e-necessidades[-slug]`, `#painel-editorial` e `#convite-<token>`.

  A troca de idioma preserva a tela, a ficha, a busca, os filtros e o modo.
- **Mapa.** Mostra um ponto por cidade (centro da cidade), com agrupamento e marcadores que são botões de 44 px. A legenda e uma faixa acima do mapa dizem "posição = centro da cidade". São 640 cidades, e 354 fichas não têm ponto no mapa. O MapLibre e o `world.geojson` (1,7 MB) só são baixados no modo mapa; a lista funciona sem eles.

## Telas

- **Públicas.**
  - **Início:** propósito, busca, contadores reais (fichas, países, cidades, ativas e por tipo), famílias e convite.
  - **Explorar:** lista e mapa.
  - **Ficha:** traz
    - o selo "ativa em 2026", "fonte consultada em nov/2026" ou "atividade a confirmar";
    - os resumos PT e EN, com o rótulo "tradução automática, sem revisão" e a ordem conforme o idioma da interface;
    - a fonte, a frase da Karte von Morgen quando há, e um link para Atribuição;
    - as iniciativas-irmãs e as ofertas e necessidades;
    - os botões "É sua? Reivindique", "Corrigir" e "Retirar do mapa", repetidos como atalhos no topo no celular.
  - **Páginas de texto:** a Atribuição traz a tabela de fontes gerada dos dados (415 fontes). Também há Participar e uma página de "não encontrada".
- **Com conta (modo supabase).**
  - **Entrar:** link mágico, com a intenção guardada em `sessionStorage` para retomar depois do `?code=`.
  - **Meu espaço:** fichas geridas, opção de aceitar conexões, reivindicações, conexões (aceitar com contato, recusar, cancelar), idioma dos e-mails e sair.
  - **Reivindicação nos três caminhos:**
    - (a) e-mail do domínio, com código de 6 dígitos e reenvio;
    - (b) código publicado mais URL de evidência;
    - (c) manual.
  - **Editar:** campos diretos e campos em revisão (nome e país), mais a retirada pela própria gestora.
  - **Conectar** e **Ofertas e necessidades** (mural público mais publicação e remoção).
  - **Painel editorial:** 8 filas de `mod_list` com decisões auditáveis. O link de convite aparece uma única vez.
- **Sem login (modo supabase).** Contato, Retirar do mapa, Corrigir (correção, exposição, abuso) e Indicar. Todas têm honeypot (`p_hp`) e tempo mínimo de 3 s. A retirada oculta a ficha na hora também no navegador de quem pediu.
- **Convite** (`#convite-<token>`): prévia, aceite com login e consentimento `convite-2026-11`, e recusa.
- **Modo static.** Todas essas telas mostram "em breve — enquanto isso, use o formulário de contato", sem formulário e sem simular gravação. No próprio Contato, o texto diz que o formulário ainda não está ativo.

## Resultados dos testes (Playwright + Chrome, servidor local com CSP)

**51 de 51 verificações aprovadas.**

- **Auditoria do `public.json`:**
  - cada registro tem exatamente os 22 campos públicos;
  - 0 campos proibidos;
  - 0 dos 173 ids privados, nem como campo nem em busca textual;
  - 0 registros "segurar";
  - coordenadas só com precisão `city`;
  - a frase da Karte von Morgen é literal;
  - os slugs são únicos;
  - 0 endereços de e-mail em `web/` (vendor incluído).
- **Varredura:** 104 telas (25 rotas mais o mapa, em PT e EN, a 360 e 1280 px) com:
  - 0 casos de rolagem horizontal;
  - 1 `h1` por tela;
  - `lang` correto e landmarks presentes;
  - nenhum resquício de "demonstração";
  - nenhuma tela com conta mostrando formulário no modo static.
- **Dados na interface:** os contadores batem com o JSON. Conferi família, família + país, família + país + selo, e presença. "sao paulo" e "São Paulo" dão o mesmo resultado (18). A paginação funciona e a lista não baixa o MapLibre.
- **Fichas:** 5 fichas reais (ativa, fonte consultada, Karte von Morgen, sem cidade e São Paulo), conferidas em PT a 1280 e em EN a 360. Os 9 critérios passam em todas.
- **Teclado:** 15 jornadas aprovadas, com foco visível: pular para o conteúdo, buscar, abrir ficha, filtro com foco preservado, troca de idioma em Explorar e na ficha, menu com Esc, marcador do mapa e "em breve".
- **Modo supabase com a API simulada por interceptação (6 verificações):**
  - paginação 1000 + 546;
  - `entity_page` e `sister_initiatives`;
  - `request_takedown` sem login, com o uuid certo; a ficha some da lista e a rota antiga diz "indisponível ou retirada";
  - honeypot enviado ao servidor;
  - reivindicação sem sessão pede o link mágico.
- **Console, CSP e rede:** 0 erros de console, 0 violações de CSP, 0 POST no modo static. Houve 4 avisos "GL Driver Message" do SwiftShader, contados à parte.
- **Capturas** (em `shots/`): `inicio_pt_1280`, `explorar_mapa_pt_1280`, `explore_list_en_360`, `ficha_kvm_pt_1280`, `profile_en_360` e `reivindicar_login_supabase_simulado`.
- **Ressalva:** o Google Fonts está bloqueado no ambiente de teste. Nos testes, ele foi atendido por interceptação com os TTF Noto do kit, nas mesmas origens.

## Decisões e pontos para validar

1. **O modo static não serve para o lançamento público.** Sem backend não há canal de retirada nem de contato, e a promessa de "retirada fácil" não se cumpre. Use-o só como prévia. O lançamento deve ser em `supabase`.
2. **`approved` não foi usado como filtro.** Em `publicavel_v1.json`, 1.490 dos 1.717 registros têm `approved=false`. Segui a decisão de 21/11 ("os 1.717 vão ao ar, menos os segurar") e apenas não exportei o campo. **Confirmar com o Rafael.**
3. **Slugs.** O build espelha `app._unique_slug` (migração 0008): nome sem acento, até 60 caracteres, colisão com `-<país>` e depois `-2`. Os registros são processados em ordem de id. Os links `#i-<slug>` coincidem entre os modos se a carga do servidor seguir a mesma ordem e não incluir os "segurar" em `app.entities`. Há 1 nome sem letras latinas (`jp-…`), que no servidor recebe hex do UUID; esse caso se resolve por `canonical_slug`. Sugestão: o `build_seed.py` importar o `slug` de `public.json`.
4. **`data/public.json` no modo supabase.** Ele não é atualizado com as retiradas. No modo supabase, não publique esse arquivo, ou gere a exportação a partir de `pub`. O app não cai para a base estática se a API falhar: mostra erro com "Tentar de novo", para não exibir fichas já retiradas.
5. **Licença.** A nota da Karte von Morgen dos dados ("… (ODbL)") foi trocada pela frase obrigatória literal: "Contém dados da Karte von Morgen / OpenFairDB, disponíveis sob ODbL". Em EN, aparece também uma glosa em inglês.
6. **Contadores.** Mostro total, países, cidades, ativas e contagem por `kind`, calculados da lista nos dois modos. Não somei as classes de `public_stats`, que poderiam ser usadas no modo supabase se a equipe preferir a separação do Plano §7.
7. **Painel editorial.** Os itens de `mod_list` aparecem de forma genérica (chave: valor), inclusive `claimant_email` (e-mail de quem reivindica), visível só para o papel moderador. As decisões seguem as assinaturas de `0011_marco_c_api.sql`. Edições sensíveis usam `review_version(..., p_kind='publication')`, que exige também o papel `curator`.
8. **Link mágico.** Com PKCE, o link precisa ser aberto no mesmo navegador; a tela avisa. `emailRedirectTo` é `SITE_URL/`.
9. **CSP** (`_headers`): `connect-src` libera `*.supabase.co`. Ajuste se o projeto usar domínio próprio.
10. **Publicação.** Este arquivo (`NOTAS_FRONT.md`) fica em `web/` por pedido, mas é nota interna. Tire-o do pacote enviado ao Pages.

## Limites em aberto

- **Acessibilidade.** **Não declaro conformidade WCAG.** Não houve teste com leitor de tela nem auditoria de contraste com ferramenta.
- **Adaptador supabase.** Foi validado só contra a API simulada. Falta rodar contra o banco real (local ou de homologação).
- **Peso.** `public.json` tem 1,3 MB sem compressão, e o Pages comprime. O pacote inteiro tem 5,4 MB, mas o mapa só é carregado sob demanda.
- **Mapa.** Os grupos podem se sobrepor em zoom mundial, e o botão de créditos do MapLibre tem cerca de 24 px (herdado do Marco A).
