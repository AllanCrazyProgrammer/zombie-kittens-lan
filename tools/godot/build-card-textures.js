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
// Datos de cartas para Godot (nombres y textos), una sola fuente de verdad con el juego web
const data = {};
for (const t of K.ORDER) data[t] = { name: K.C[t].name, kind: K.C[t].kind, short: K.C[t].short, long: K.C[t].long, color: K.C[t].color, now: !!K.C[t].now, cat: !!K.C[t].cat };
fs.writeFileSync(path.join(ROOT, 'godot', 'data', 'cards.json'), JSON.stringify(data, null, 2));
fs.rmSync(tmp, { recursive: true, force: true });
console.log(K.ORDER.length + 1, 'texturas en', path.relative(ROOT, OUT));
