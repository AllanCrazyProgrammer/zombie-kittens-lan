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
for (const t of K.ORDER) shot(t, K.cardHTML(t));
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
