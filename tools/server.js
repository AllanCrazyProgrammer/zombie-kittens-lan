/* Servidor de escritorio (opcional): hace lo mismo que el servidor integrado en la app Android.
 * Sirve el juego y retransmite mensajes entre el anfitrión (pestaña en localhost) y los invitados de la red.
 * Uso: npm run dev  → abre http://localhost:8765 en esta computadora para crear la partida. */
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { WebSocketServer } = require('ws');
const QRCode = require('qrcode');

const PORT = Number(process.env.PORT || 8765);
const ROOT = path.join(__dirname, '..', 'web', 'www');
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png', '.json': 'application/json' };

function lanIps() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) for (const i of list || []) if (i.family === 'IPv4' && !i.internal) out.push(i.address);
  return out;
}
const isLoopback = (a) => a === '127.0.0.1' || a === '::1' || a === '::ffff:127.0.0.1';

const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/info') {
    const ips = lanIps();
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    return res.end(JSON.stringify({ ip: ips[0] || '', ips, port: PORT, local: isLoopback(req.socket.remoteAddress), native: false }));
  }
  if (u.pathname === '/qr') {
    const svg = await QRCode.toString(u.searchParams.get('t') || '', { type: 'svg', margin: 1 });
    res.writeHead(200, { 'Content-Type': 'image/svg+xml' });
    return res.end(svg);
  }
  if (u.pathname === '/solo') {   // vista previa de la versión web de un solo archivo
    return fs.readFile(path.join(__dirname, '..', 'dist', 'zombie-kittens-web.html'), (err, data) => { res.writeHead(err ? 404 : 200, { 'Content-Type': MIME['.html'] }); res.end(err ? 'Ejecuta: npm run build:web' : data); });
  }
  let file = path.normalize(path.join(ROOT, u.pathname === '/' ? 'index.html' : u.pathname));
  if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('No encontrado'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
});

const wss = new WebSocketServer({ server, path: '/ws' });
let host = null, n = 0;
const clients = new Map();
const send = (ws, o) => { try { if (ws && ws.readyState === 1) ws.send(JSON.stringify(o)); } catch (e) { /* socket cerrado */ } };

wss.on('connection', (ws, req) => {
  const u = new URL(req.url, 'http://x');
  if (u.searchParams.get('role') === 'host') {
    if (!isLoopback(req.socket.remoteAddress)) return ws.close();
    if (host) host.close();
    for (const c of clients.values()) c.close();
    clients.clear();
    host = ws;
    ws.on('message', (raw) => {
      let m; try { m = JSON.parse(raw); } catch (e) { return; }
      if (m.t === 'ping') return send(ws, { t: 'pong' });
      send(clients.get(m.to), m.data);
    });
    ws.on('close', () => { if (host === ws) { host = null; for (const c of clients.values()) c.close(); clients.clear(); } });
    return;
  }
  if (!host) { send(ws, { t: 'nohost' }); return ws.close(); }
  const cid = 'c' + (++n);
  clients.set(cid, ws);
  send(host, { ev: 'open', from: cid });
  ws.on('message', (raw) => {
    let m; try { m = JSON.parse(raw); } catch (e) { return; }
    if (m.t === 'ping') return send(ws, { t: 'pong' });
    send(host, { ev: 'msg', from: cid, data: m });
  });
  ws.on('close', () => { if (clients.get(cid) === ws) { clients.delete(cid); send(host, { ev: 'close', from: cid }); } });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Zombie Kittens LAN listo.');
  console.log('  Anfitrión (esta computadora): http://localhost:' + PORT);
  for (const ip of lanIps()) console.log('  Invitados en la misma red:    http://' + ip + ':' + PORT);
});
