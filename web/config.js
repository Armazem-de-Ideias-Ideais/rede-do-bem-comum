/* Configuração pública do site (sem segredos: a chave anon do Supabase é pública por natureza).
   MODE: "static" lê data/public.json (somente leitura; contas e formulários aparecem como "em breve").
         "supabase" usa a API (docs/API_CONTRATO.md); exige SUPABASE_URL e SUPABASE_ANON_KEY — sem eles, o site fica em "static".
   SITE_URL: endereço público (ex.: https://bemcomum.coolmeia.org). Vazio = origem atual. Nunca fixe o domínio no código. */
window.RBC_CONFIG = {
  MODE: 'supabase',
  SUPABASE_URL: 'https://wjrvygacpdrnqstsqjmv.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndqcnZ5Z2FjcGRybnFzdHNxam12Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUyOTkwMjUsImV4cCI6MjExMDg3NTAyNX0.7DyLqUDSROxLfgLe1p78_RrgkU9JUpO9-VjNBJD5tms',
  SITE_URL: 'https://bemcomum.coolmeia.org'
};
