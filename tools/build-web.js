/* Genera dist/zombie-kittens-web.html: el juego completo de un jugador en UN solo archivo,
 * que se abre con doble clic o se sube a cualquier hosting estático. Uso: npm run build:web */
const fs = require('fs');
const path = require('path');
const W = path.join(__dirname, '..', 'web', 'www');
const read = (f) => fs.readFileSync(path.join(W, f), 'utf8');
const b64 = (f) => fs.readFileSync(path.join(W, f)).toString('base64');
const safe = (js) => js.replace(/<\/script/gi, '<\\/script');

let css = read('style.css').replace(/url\(fonts\/([\w.-]+)\)/g, (_, f) => `url(data:font/woff2;base64,${b64('fonts/' + f)})`);
let html = read('index.html')
  .replace('<link rel="stylesheet" href="style.css">', () => `<style>${css}</style>`)
  .replace(/<script src="([\w.]+)"><\/script>/g, (_, f) => `<script>${safe(read(f))}</script>`)
  .replace('<div id="app">', () => '<script>window.ZK_STATIC = true;</script>\n<div id="app">');
const out = path.join(__dirname, '..', 'dist');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'zombie-kittens-web.html'), html);
console.log('dist/zombie-kittens-web.html  ' + Math.round(html.length / 1024) + ' KB');
