/* Graba partidas completas del motor original (JavaScript) para verificar el port a Godot.
 * Cada paso guarda la acción (o el avance del reloj) y una huella del estado resultante.
 * Uso: node tools/godot/gen-traces.js [partidas]   →  godot/tests/traces.json
 *      node tools/godot/gen-traces.js --dump <partida> <paso>   (muestra el estado completo, para depurar) */
const fs = require('fs');
const path = require('path');
const E = require('../../web/www/engine.js');
const { Room } = require('../../web/www/room.js');

function rng(seed) { let s = seed >>> 0; return () => { s = (s + 0x6D2B79F5) | 0; let t = Math.imul(s ^ (s >>> 15), 1 | s); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function fnv(str) { let h = 2166136261; for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; } return h >>> 0; }

function digest(g) {
  const ids = (a) => a.map((c) => c.id).join(',');
  let s = 'D:' + ids(g.draw) + '|X:' + g.discard.map((d) => d.card.id + '/' + d.by).join(',') +
    '|H:' + g.players.map((p) => p.id + '=' + ids(p.hand) + '/' + (p.alive ? 1 : 0) + '/' + (p.ek ? p.ek.id : '-') + '/' + (p.connected ? 1 : 0)).join(';') +
    '|C:' + g.cur + '/' + g.turnsLeft + '/' + (g.attacked ? 1 : 0) +
    '|S:' + g.stack.map((x) => [x.eff, x.by, x.nopes, x.last, x.target || '-', x.named || '-', x.deadline, Object.keys(x.passed).join('+')].join('/')).join(';') + '|P:';
  const pr = g.prompt;
  if (pr) {
    s += pr.type + '/' + pr.deadline;
    if (pr.player) s += '/pl=' + pr.player;
    if (pr.card) s += '/c=' + pr.card.id;
    if (pr.eks) s += '/e=' + ids(pr.eks) + '/r=' + (pr.revived || '-') + '/pp=' + (pr.pendingPos ? pr.pendingPos.join('+') : '-') + '/w=' + pr.watchers.join('+') + '/m=' + pr.minUntil;
    if (pr.waiting) s += '/wt=' + Object.keys(pr.waiting).join('+') + '/to=' + (pr.to || '-') + '/rs=' + pr.reason + '/pool=' + ids(pr.pool);
  }
  const last = g.events[g.events.length - 1];
  s += '|O:' + (g.over ? (g.over.winner || '-') : '') + '|E:' + g.seq + '/' + (last ? last.type : '') + '|M:' + g.mut + '/' + g.shuf + '/' + g.idleSince;
  return s;
}

function record(index, dumpStep) {
  const seed = 1000 + index * 7919, n = 2 + (index % 4), mode = index % 5 === 4 ? 'full' : 'official';
  const levels = ['easy', 'normal', 'hard'];
  const botRnd = rng(seed ^ 0x5bd1e995);
  let now = 0, tid = 0;
  const timers = new Map();
  const room = new Room({ send() {}, now: () => now, rnd: botRnd, setTimeout: (f, ms) => { timers.set(++tid, { at: now + ms, f }); return tid; }, clearTimeout: (t) => timers.delete(t) });
  // Algunos jugadores "ausentes" (humanos sin conexión): el motor juega por ellos y así se cubren los automatismos
  const gone = [];
  for (let i = 0; i < n; i++) {
    const absent = index % 3 === 0 && i === (index >> 2) % n;
    if (absent) gone.push(i);
    room.players.push({ id: 'b' + i, name: 'B' + i, avatar: 0, bot: !absent, level: levels[(index + i) % 3], cid: null, host: false });
  }
  const g = room.game = new E.Game({ players: room.players, deckMode: mode, rnd: rng(seed), now });
  for (const i of gone) g.setConnected('b' + i, false, now);
  g.tick(now);
  const steps = [];
  const out = { seed, n, mode, gone, init: fnv(digest(g)), steps };
  let depth = 0;
  const act0 = g.act.bind(g), tick0 = g.tick.bind(g);
  const push = (row) => { if (dumpStep === steps.length) console.log(digest(g)); steps.push(row); };
  g.act = (pid, a, t) => { depth++; const err = act0(pid, a, t); depth--; if (!depth) push([0, t, Number(pid.slice(1)), a, err ? 1 : 0, fnv(digest(g))]); return err; };
  g.tick = (t) => { depth++; tick0(t); depth--; if (!depth) push([1, t, 0, null, 0, fnv(digest(g))]); };
  room.sync();
  let guard = 0;
  while (!g.over) {
    if (!timers.size || ++guard > 20000) throw new Error('partida atascada ' + index);
    let best = null;
    for (const [id, t] of timers) if (!best || t.at < best.t.at) best = { id, t };
    timers.delete(best.id); now = Math.max(now, best.t.at); best.t.f();
  }
  out.winner = g.over.winner;
  return out;
}

const args = process.argv.slice(2);
if (args[0] === '--dump') { record(Number(args[1]), Number(args[2])); process.exit(0); }
const N = Number(args[0] || 120);
const r = rng(12345), rngSample = Array.from({ length: 8 }, () => r());
const games = Array.from({ length: N }, (_, i) => record(i));
const file = path.join(__dirname, '..', '..', 'godot', 'tests', 'traces.json');
fs.writeFileSync(file, JSON.stringify({ rng: rngSample, fnv: fnv('D:c1,c2|X:'), games }));
const steps = games.reduce((a, g) => a + g.steps.length, 0);
console.log(N + ' partidas, ' + steps + ' pasos, ' + Math.round(fs.statSync(file).size / 1024) + ' KB');
