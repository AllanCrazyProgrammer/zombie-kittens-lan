/* Genera las texturas de las cartas para Godot (godot/assets/cards/*.png) a partir del arte vectorial
 * del juego web, rasterizándolas con Chrome sin ventana. Uso: node tools/godot/build-card-textures.js */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..', '..');
const WWW = path.join(ROOT, 'web', 'www');
const OUT = path.join(ROOT, 'godot', 'assets', 'cards');
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const W = 750, H = 1050;
const K = require(path.join(WWW, 'cards.js')).ZKCards;

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'zk-cards-'));
const page = (body) => `<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="file://${WWW}/style.css">
<style>html,body{margin:0;background:transparent!important;overflow:hidden}
.card{--w:${W}px;border-radius:0!important;box-shadow:none!important;border-width:.16em!important}
.card.back svg{width:${W}px;height:${H}px}
.c-txt{font-size:.66em!important;line-height:1.18!important;height:6.3em!important;padding:.5em .7em!important}</style>${body}`;

function shot(name, body) {
  const html = path.join(tmp, name + '.html'), png = path.join(OUT, name + '.png');
  fs.writeFileSync(html, page(body));
  execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000',
    `--window-size=${W},${H}`, '--virtual-time-budget=3000', `--screenshot=${png}`, 'file://' + html], { stdio: 'ignore' });
  return png;
}
fs.mkdirSync(OUT, { recursive: true });
// Cara nueva: ilustración 3D (Blender) a sangre + banda de título + panel de texto.
const ART = path.join(ROOT, 'godot', 'assets', 'art');
const font = (f) => fs.readFileSync(path.join(WWW, 'fonts', f)).toString('base64');
const FACE_CSS = `@font-face{font-family:Bangers;src:url(data:font/woff2;base64,${font('bangers.woff2')})}
@font-face{font-family:Nunito;src:url(data:font/woff2;base64,${font('nunito.woff2')});font-weight:200 1000}
html,body{margin:0;background:#150a22;overflow:hidden}
.face{position:relative;width:${W}px;height:${H}px;box-sizing:border-box;border:14px solid #150a22;background-size:cover;background-position:center;overflow:hidden;font-family:Nunito,sans-serif}
.shade{position:absolute;inset:0;background:linear-gradient(#0008 0%,#0000 22%,#0000 55%,#000a 100%)}
.line{position:absolute;inset:10px;border:5px solid var(--cc);border-radius:22px;opacity:.9;box-shadow:0 0 0 2px #150a22 inset,0 0 0 2px #150a22}
.title{position:absolute;left:30px;right:30px;top:30px;min-height:112px;display:flex;align-items:center;gap:16px;padding:8px 24px;box-sizing:border-box;background:linear-gradient(var(--cc),color-mix(in srgb,var(--cc) 72%,#000));border:6px solid #150a22;border-radius:22px;box-shadow:0 8px 0 #0007;transform:rotate(-1.2deg)}
.title .ico{font-size:66px;line-height:1;filter:drop-shadow(0 3px 0 #0006)}
.title .name{font-family:Bangers,Impact,sans-serif;color:#fff;letter-spacing:.04em;line-height:.92;text-shadow:0 5px 0 #0008,0 0 12px #0006}
.now{position:absolute;right:38px;top:166px;background:#ffd23a;color:#2a1c00;font-family:Bangers,Impact,sans-serif;font-size:44px;letter-spacing:.04em;padding:2px 22px;border:5px solid #150a22;border-radius:16px;transform:rotate(7deg);box-shadow:0 6px 0 #0007}
.panel{position:absolute;left:30px;right:30px;bottom:30px;min-height:236px;box-sizing:border-box;padding:40px 30px 24px;background:#fbf5e6f2;border:6px solid #150a22;border-radius:26px;box-shadow:0 -6px 30px #0006;color:#1c1326;font-weight:800;font-size:38px;line-height:1.2;display:flex;align-items:center}
.kind{position:absolute;left:24px;top:-28px;background:var(--cc);color:#fff;font-family:Bangers,Impact,sans-serif;font-size:32px;letter-spacing:.06em;padding:3px 20px;border:5px solid #150a22;border-radius:14px;text-shadow:0 2px 0 #0006}`;
function facePage(t) {
  const c = K.C[t], len = c.name.length, size = len > 17 ? 58 : len > 12 ? 70 : 84;
  return `<!doctype html><meta charset="utf-8"><style>${FACE_CSS}</style>
  <div class="face" style="--cc:${c.color};background-image:url('file://${path.join(ART, t + '.png')}')"><div class="shade"></div><div class="line"></div>
  <div class="title"><span class="ico">${c.icon}</span><span class="name" style="font-size:${size}px">${c.name}</span></div>
  ${c.now ? '<div class="now">⚡ YA</div>' : ''}
  <div class="panel"><span class="kind">${c.kind}</span><span>${c.short}</span></div></div>`;
}
for (const t of K.ORDER) {
  if (!fs.existsSync(path.join(ART, t + '.png'))) { shot(t, K.cardHTML(t)); continue; }   // sin ilustración 3D: cara vectorial antigua
  const html = path.join(tmp, t + '.html'), png = path.join(OUT, t + '.png');
  fs.writeFileSync(html, facePage(t));
  execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files', `--window-size=${W},${H}`, '--virtual-time-budget=3000', `--screenshot=${png}`, 'file://' + html], { stdio: 'ignore' });
}
shot('back', K.backHTML());
// Emblema bordado en el centro del tapete
{
  const html = path.join(tmp, 'emblem.html'), png = path.join(ROOT, 'godot', 'assets', 'textures', 'emblem.png');
  fs.mkdirSync(path.dirname(png), { recursive: true });
  const ring = Array.from({ length: 36 }, (_, i) => `<circle cx="${(512 + 438 * Math.cos(i * Math.PI / 18)).toFixed(1)}" cy="${(512 + 438 * Math.sin(i * Math.PI / 18)).toFixed(1)}" r="7"/>`).join('');
  fs.writeFileSync(html, `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent;overflow:hidden}
  @font-face{font-family:Bangers;src:url(data:font/woff2;base64,${fs.readFileSync(path.join(WWW, 'fonts', 'bangers.woff2')).toString('base64')})}</style>
  <svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg" fill="#c8ff5a">
  <circle cx="512" cy="512" r="470" fill="none" stroke="#c8ff5a" stroke-width="10"/><circle cx="512" cy="512" r="404" fill="none" stroke="#c8ff5a" stroke-width="4"/>${ring}
  <g transform="translate(512 500) scale(5.2)"><ellipse cx="0" cy="10" rx="17" ry="14"/><ellipse cx="-19" cy="-9" rx="6.5" ry="9" transform="rotate(-22 -19 -9)"/><ellipse cx="-7" cy="-19" rx="6.5" ry="9.5" transform="rotate(-6 -7 -19)"/><ellipse cx="7" cy="-19" rx="6.5" ry="9.5" transform="rotate(6 7 -19)"/><ellipse cx="19" cy="-9" rx="6.5" ry="9" transform="rotate(22 19 -9)"/></g>
  <defs><path id="arc" d="M 172 512 A 340 340 0 0 0 852 512"/></defs>
  <text font-family="Bangers" font-size="92" letter-spacing="10" text-anchor="middle"><textPath href="#arc" startOffset="50%">ZOMBIE KITTENS</textPath></text></svg>`);
  execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000', '--window-size=1024,1024', '--virtual-time-budget=3000', `--screenshot=${png}`, 'file://' + html], { stdio: 'ignore' });
}
// Datos de cartas para Godot (nombres y textos), una sola fuente de verdad con el juego web
const data = {};
for (const t of K.ORDER) data[t] = { name: K.C[t].name, kind: K.C[t].kind, short: K.C[t].short, long: K.C[t].long, color: K.C[t].color, now: !!K.C[t].now, cat: !!K.C[t].cat };
fs.writeFileSync(path.join(ROOT, 'godot', 'data', 'cards.json'), JSON.stringify(data, null, 2));
fs.rmSync(tmp, { recursive: true, force: true });
console.log(K.ORDER.length + 1, 'texturas en', path.relative(ROOT, OUT));
