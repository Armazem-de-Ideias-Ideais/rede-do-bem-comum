// Google Fonts está bloqueado no sandbox de teste: a requisição é atendida por interceptação
// com os TTF Noto do kit de identidade, mantendo as mesmas origens (fonts.googleapis.com / fonts.gstatic.com).
const fs = require('fs'), path = require('path');
const F = path.join(__dirname, 'fonts');
const faces = [['Noto Sans', 400, 'NotoSans-Regular.ttf'], ['Noto Sans', 600, 'NotoSans-Bold.ttf'], ['Noto Sans', 700, 'NotoSans-Bold.ttf'], ['Noto Serif', 400, 'NotoSerif-Regular.ttf'], ['Noto Serif', 600, 'NotoSerif-Bold.ttf'], ['Noto Serif', 700, 'NotoSerif-Bold.ttf']];
const css = faces.map(f => `@font-face{font-family:'${f[0]}';font-style:normal;font-weight:${f[1]};font-display:swap;src:url(https://fonts.gstatic.com/s/test/${f[2]}) format('truetype');}`).join('\n') +
  faces.map(f => `@font-face{font-family:'${f[0]}';font-style:italic;font-weight:${f[1]};font-display:swap;src:url(https://fonts.gstatic.com/s/test/${f[2]}) format('truetype');}`).join('\n');
module.exports = async function routeFonts(ctx) {
  await ctx.route('https://fonts.googleapis.com/**', r => r.fulfill({ status: 200, contentType: 'text/css', headers: { 'access-control-allow-origin': '*' }, body: css }));
  await ctx.route('https://fonts.gstatic.com/**', r => { const f = path.basename(new URL(r.request().url()).pathname); const p = path.join(F, f); if (fs.existsSync(p)) r.fulfill({ status: 200, contentType: 'font/ttf', headers: { 'access-control-allow-origin': '*' }, body: fs.readFileSync(p) }); else r.abort(); });
};
