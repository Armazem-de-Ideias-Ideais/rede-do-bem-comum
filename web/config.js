/* Configuração pública do site (sem segredos: a chave anon do Supabase é pública por natureza).
   MODE: "static" lê data/public.json (somente leitura; contas e formulários aparecem como "em breve").
         "supabase" usa a API (docs/API_CONTRATO.md); exige SUPABASE_URL e SUPABASE_ANON_KEY — sem eles, o site fica em "static".
   SITE_URL: endereço público (ex.: https://bemcomum.coolmeia.org). Vazio = origem atual. Nunca fixe o domínio no código. */
window.RBC_CONFIG = {
  MODE: 'static',
  SUPABASE_URL: '',
  SUPABASE_ANON_KEY: '',
  SITE_URL: ''
};
