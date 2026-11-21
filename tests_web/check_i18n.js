// Confere se toda chave de interface usada no código existe em PT e EN (e se os dois dicionários têm as mesmas chaves).
global.window={RBC_CONFIG:{},location:{origin:'http://x',pathname:'/'}}; global.navigator={language:'pt'}; global.document={};
const vm=require('vm'),fs=require('fs'); process.chdir(process.argv[2] || require("path").resolve(__dirname, "..", "web", "js"));
['core.js','i18n.js'].forEach(f=>vm.runInThisContext(fs.readFileSync(f,'utf8')));
const RBC=window.RBC; const pt=RBC.I18N.pt, en=RBC.I18N.en;
const used=new Set();
for (const f of fs.readdirSync('.').filter(f=>f.endsWith('.js'))) { const s=fs.readFileSync(f,'utf8'); for (const m of s.matchAll(/\bt\('([a-z0-9_.]+)'[,)]/g)) used.add(m[1]); }
['withdraw','correct','suggest','claim','edit','connect','offers','login','invite','withdraw.lead','correct.lead','sort.relevance','nav.why','nav.terms','nav.login','nav.privacy','explore.mode_map_on','explore.mode_list_on','counts.total','counts.countries','counts.cities','counts.active','form.errsum.one','form.errsum.many'].forEach(k=>used.add(k));
const miss=[...used].filter(k=>!k.endsWith('.') && (pt[k]==null||en[k]==null));
const asym=Object.keys(pt).filter(k=>en[k]==null).concat(Object.keys(en).filter(k=>pt[k]==null));
console.log(JSON.stringify({used:used.size,missing:miss,asym,pt:Object.keys(pt).length,en:Object.keys(en).length}));
process.exit(miss.length||asym.length?1:0);
