/* Ícono de la app (godot/assets/icon/icon.png, 512x512) a partir de la ilustración del Gatito Zombi.
 * Uso: node tools/godot/build-icon.js */
const fs = require('fs'), os = require('os'), path = require('path');
const { execFileSync } = require('child_process');
const ROOT = path.join(__dirname, '..', '..');
const ART = path.join(ROOT, 'godot', 'assets', 'art', 'zombie.png');
const OUT = path.join(ROOT, 'godot', 'assets', 'icon', 'icon.png');
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const html = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'zk-icon-')), 'icon.html');
// La ilustración mide 750x1050; el gato queda centrado cerca de (375, 450). Se recorta un cuadrado alrededor.
fs.writeFileSync(html, `<!doctype html><style>html,body{margin:0;background:#170c33;overflow:hidden}
.i{width:512px;height:512px;background:url('file://${ART}') no-repeat;background-size:${Math.round(750 * 512 / 470)}px auto;
background-position:${Math.round(-(375 - 235) * 512 / 470)}px ${Math.round(-(450 - 235) * 512 / 470)}px}</style><div class="i"></div>`);
execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files', '--window-size=512,512', `--screenshot=${OUT}`, 'file://' + html], { stdio: 'ignore' });
console.log('ícono en', path.relative(ROOT, OUT));
