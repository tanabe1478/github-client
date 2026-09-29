// Renders Claude Design artboards (.dc.html) to PNG, one per board at its
// canvas size and 2x scale, for the README images in docs/images/design.
//
// Usage:
//   node scripts/design/render-design.cjs <project-dir> <output-dir>
//
// <project-dir> holds the canvas's project/ files (canvas.json and every
// *.dc.html) plus the Design type's artifact-type/dc-runtime.js copied in as
// support.js, which each artboard loads. Needs the playwright package and
// its Chromium (npm install playwright; npx playwright install chromium).
const { chromium } = require('playwright');
const http = require('http'); const fs = require('fs'); const path = require('path');
const dir = process.argv[2]; const out = process.argv[3];
const canvas = JSON.parse(fs.readFileSync(path.join(dir, 'canvas.json'), 'utf8'));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const file = path.join(dir, decodeURIComponent(req.url.split('?')[0]));
  if (!file.startsWith(dir) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(file).replace('.dc', '')] || 'text/html' });
  fs.createReadStream(file).pipe(res);
}).listen(0, async () => {
  const port = server.address().port;
  const browser = await chromium.launch();
  fs.mkdirSync(out, { recursive: true });
  for (const name of canvas.order) {
    const board = canvas.boards[name];
    const page = await browser.newPage({ viewport: { width: board.w, height: board.h }, deviceScaleFactor: 2 });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(`http://127.0.0.1:${port}/${name}`);
    await page.waitForTimeout(1500);
    const file = path.join(out, name.replace('.dc.html', '.png'));
    await page.screenshot({ path: file, clip: { x: 0, y: 0, width: board.w, height: board.h } });
    console.log(name, errors.length ? 'errors: ' + errors.join('; ') : 'ok');
    await page.close();
  }
  await browser.close(); server.close();
});
