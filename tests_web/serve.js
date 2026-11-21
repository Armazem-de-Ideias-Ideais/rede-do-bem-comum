// Servidor HTTP local para os testes: serve web/ e aplica os cabeçalhos de web/_headers (CSP igual à produção).
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', 'web');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.geojson': 'application/geo+json', '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.txt': 'text/plain; charset=utf-8' };
function headers() {
  const h = {}; let on = false;
  for (const line of fs.readFileSync(path.join(ROOT, '_headers'), 'utf8').split('\n')) {
    if (/^\/\*\s*$/.test(line)) { on = true; continue; }
    if (/^\S/.test(line)) { on = false; continue; }
    const m = on && line.match(/^\s+([A-Za-z-]+):\s*(.+)$/); if (m) h[m[1].toLowerCase()] = m[2].trim();
  }
  return h;
}
module.exports = function start(port) {
  const H = headers();
  return new Promise(res => {
    const srv = http.createServer((req, rsp) => {
      let p = decodeURIComponent(new URL(req.url, 'http://x').pathname); if (p.endsWith('/')) p += 'index.html';
      const f = path.join(ROOT, p);
      if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { rsp.writeHead(404, H); rsp.end('404'); return; }
      rsp.writeHead(200, Object.assign({ 'content-type': TYPES[path.extname(f)] || 'application/octet-stream' }, H));
      fs.createReadStream(f).pipe(rsp);
    }).listen(port || 0, '127.0.0.1', () => res(srv));
  });
};
if (require.main === module) module.exports(+process.argv[2] || 8765).then(s => console.log('http://127.0.0.1:' + s.address().port));
