/* Pruebas del motor: reglas concretas + miles de partidas simuladas con bots (reloj virtual). */
const assert = require('assert');
const E = require('../web/www/engine.js');
const { Room } = require('../web/www/room.js');

function rng(seed) { let s = seed >>> 0; return () => { s = (s + 0x6D2B79F5) | 0; let t = Math.imul(s ^ (s >>> 15), 1 | s); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const mk = (n, seed, mode) => new E.Game({ players: Array.from({ length: n }, (_, i) => ({ id: 'p' + i, name: 'J' + i })), rnd: rng(seed || 1), deckMode: mode, now: 0 });
const card = (g, p, type) => { const c = { id: 'x' + (++g.pid) + type, type, paw: false }; g.P(p).hand.push(c); return c.id; };
const count = (g) => g.draw.length + g.discard.length + g.players.reduce((a, p) => a + p.hand.length + (p.ek ? 1 : 0), 0) + (g.prompt && g.prompt.card ? 1 : 0) + (g.prompt && g.prompt.eks ? g.prompt.eks.length : 0) + (g.prompt && g.prompt.pool ? g.prompt.pool.length : 0);
let n = 0; const ok = (name) => { n++; console.log('  ✓ ' + name); };

// --- Preparación oficial ---
for (const [pl, deck, total] of [[2, 9, 25], [3, 11, 35], [4, 28, 60], [5, 21, 61]]) {
  const g = mk(pl, 7);
  assert.strictEqual(g.draw.length, deck, pl + ' jugadores: mazo');
  assert.strictEqual(count(g), total);
  assert.strictEqual(g.draw.filter((c) => c.type === 'exploding').length, pl - 1);
  for (const p of g.players) { assert.strictEqual(p.hand.length, 8); assert.strictEqual(p.hand.filter((c) => c.type === 'zombie').length >= 1, true); }
}
assert.ok(mk(2, 3).players.every((p) => p.hand.every((c) => c.paw)), '2 jugadores: solo cartas con huella');
assert.ok(mk(3, 3).players.every((p) => p.hand.every((c) => !c.paw)), '3 jugadores: solo cartas sin huella');
ok('preparación para 2, 3, 4 y 5 jugadores');

// --- Ataques apilados (ejemplo del reglamento) ---
{
  const g = mk(4, 2); g.cfg.FAST_MS = 0; g.cfg.NOPE_MS = 0;
  for (const p of g.players) p.hand = [];
  const order = (k) => g.players[(g.cur + k) % 4].id;
  const a = order(0), b = order(1), c = order(2), d = order(3);
  const play = (p, type, extra) => { assert.strictEqual(g.act(p, Object.assign({ a: 'play', cards: [card(g, p, type)] }, extra), 0), null); g.tick(1); };
  play(a, 'attack'); assert.strictEqual(g.curP().id, b); assert.strictEqual(g.turnsLeft, 2);
  play(b, 'attack'); assert.strictEqual(g.curP().id, c); assert.strictEqual(g.turnsLeft, 4);
  play(c, 'skip'); assert.strictEqual(g.turnsLeft, 3); assert.strictEqual(g.curP().id, c);
  play(c, 'super_skip'); assert.strictEqual(g.curP().id, d); assert.strictEqual(g.turnsLeft, 1);
  ok('Ataque se apila (2 → 4), Saltar quita 1 turno, Súper Salto los quita todos');
}
{
  const g = mk(4, 5); g.cfg.FAST_MS = 0;
  for (const p of g.players) p.hand = [];
  const a = g.curP().id, b = g.players[(g.cur + 1) % 4].id, c = g.players[(g.cur + 2) % 4].id;
  g.act(a, { a: 'play', cards: [card(g, a, 'attack')] }, 0); g.tick(1);
  g.draw.push({ id: 'safe', type: 'cat_a' });
  g.act(b, { a: 'draw' }, 2); assert.strictEqual(g.turnsLeft, 1);
  g.act(b, { a: 'play', cards: [card(g, b, 'attack')] }, 3); g.tick(4);
  assert.strictEqual(g.curP().id, c); assert.strictEqual(g.turnsLeft, 3);
  ok('víctima completa 1 turno y luego ataca: el siguiente juega 3');
}

// --- Nop / Yup ---
{
  const g = mk(3, 4);
  for (const p of g.players) p.hand = [];
  const a = g.curP().id, b = g.players[(g.cur + 1) % 3].id;
  const n1 = card(g, b, 'nope'), n2 = card(g, a, 'nope');
  g.act(a, { a: 'play', cards: [card(g, a, 'skip')] }, 0);
  assert.ok(g.act(a, { a: 'play', cards: [n2] }, 1), 'no puedes anular tu propia jugada');
  assert.strictEqual(g.act(b, { a: 'play', cards: [n1] }, 1), null);
  assert.strictEqual(g.act(a, { a: 'play', cards: [n2] }, 2), null);
  g.tick(999999);
  assert.strictEqual(g.curP().id, b, 'Nop + Nop = la jugada vale');
  ok('Nop anula y un segundo Nop (Yup) la restaura');
}

// --- Explotar, Gatito Zombi, revivir, Clarividencia ---
{
  const g = mk(3, 9); g.cfg.FAST_MS = 0;
  for (const p of g.players) p.hand = [];
  const a = g.curP().id, b = g.players[(g.cur + 1) % 3].id, c = g.players[(g.cur + 2) % 3].id;
  const ek = () => ({ id: 'ek' + (++g.pid), type: 'exploding' });
  g.draw.push(ek());
  g.act(a, { a: 'draw' }, 0);
  assert.strictEqual(g.P(a).alive, false); assert.strictEqual(g.curP().id, b);
  assert.ok(g.act(b, { a: 'play', cards: [card(g, b, 'favor')], target: a }, 1), 'no se puede pedir Favor a un muerto');
  const z = card(g, b, 'zombie'), cl = card(g, c, 'clairvoyance');
  g.draw.push(ek());
  g.act(b, { a: 'draw' }, 2);
  assert.strictEqual(g.prompt.type, 'explode');
  assert.strictEqual(g.act(b, { a: 'play', cards: [z] }, 3), null);
  assert.strictEqual(g.P(a).alive, true, 'el único muerto revive automáticamente');
  assert.strictEqual(g.prompt.eks.length, 2);
  assert.strictEqual(g.act(c, { a: 'play', cards: [cl] }, 4), null);
  const len = g.draw.length;
  assert.strictEqual(g.act(b, { a: 'insert', positions: [0, 3] }, 5), null);
  assert.ok(g.prompt, 'espera a Clarividencia');
  g.tick(999999);
  assert.strictEqual(g.prompt, null); assert.strictEqual(g.draw.length, len + 2);
  assert.ok(g.events.some((e) => e.type === 'clair' && e.to === c));
  assert.strictEqual(g.curP().id, c);
  ok('morir, Gatito Zombi revive y reinserta 2 explosivos, Clarividencia los ve');
}

// --- Vista: no filtra información secreta ---
{
  const g = mk(4, 11);
  const v = g.view('p0', 0);
  assert.strictEqual(JSON.stringify(v).includes('"hand":[{'), true);
  assert.strictEqual(v.players.every((p) => p.hand === undefined), true);
  ok('la vista solo incluye tu propia mano');
}

// --- Simulación masiva con bots ---
function simulate(players, seed, mode, levels) {
  const rnd = rng(seed);
  let now = 0, tid = 0; const timers = new Map();
  const room = new Room({
    send() {}, now: () => now, rnd,
    setTimeout: (f, ms) => { timers.set(++tid, { at: now + ms, f }); return tid; },
    clearTimeout: (t) => timers.delete(t),
  });
  room.settings.deckMode = mode;
  for (let i = 0; i < players; i++) room.players.push({ id: 'b' + i, name: 'B' + i, avatar: 0, bot: true, level: levels ? levels[i % levels.length] : 'normal', cid: null, host: false });
  room.start();
  const g = room.game, total = count(g);
  let steps = 0;
  while (!g.over) {
    assert.ok(timers.size > 0, 'partida atascada (seed ' + seed + ')');
    assert.ok(++steps < 20000, 'partida interminable (seed ' + seed + ')');
    let best = null;
    for (const [id, t] of timers) if (!best || t.at < best.t.at) best = { id, t };
    timers.delete(best.id); now = Math.max(now, best.t.at); best.t.f();
    assert.strictEqual(count(g), total, 'se perdieron o duplicaron cartas (seed ' + seed + ')');
    if (!g.over) {
      const eks = g.draw.filter((c) => c.type === 'exploding').length + (g.prompt && g.prompt.card && g.prompt.card.type === 'exploding' ? 1 : 0) + (g.prompt && g.prompt.eks ? g.prompt.eks.length : 0);
      assert.strictEqual(eks, g.living().length - 1, 'explosivos en juego != vivos - 1 (seed ' + seed + ')');
      assert.ok(g.draw.length > 0 || g.prompt, 'mazo vacío');
      assert.ok(g.curP().alive || g.prompt, 'turno de un muerto');
    }
  }
  assert.strictEqual(g.living().length, 1);
  simulate.winner = g.over.winner;
  return steps;
}
let games = 0, steps = 0;
for (let seed = 1; seed <= 1500; seed++) for (const pl of [2, 3, 4, 5]) { steps += simulate(pl, seed * 31 + pl, seed % 5 === 0 ? 'full' : 'official'); games++; }
ok(games + ' partidas completas simuladas con bots (' + steps + ' pasos) sin atascos ni cartas perdidas');
// --- Dificultades: todas terminan sus partidas y la IA difícil gana más ---
for (const lv of ['easy', 'hard']) { let k = 0; for (let seed = 1; seed <= 400; seed++) for (const pl of [2, 3, 4, 5]) { simulate(pl, seed * 17 + pl, 'official', [lv]); k++; } ok(k + ' partidas con IA ' + lv); }
const duel = (a, b, N) => { let w = 0; for (let i = 0; i < N; i++) { simulate(2, 9000 + i, 'official', i % 2 ? [a, b] : [b, a]); if (simulate.winner === (i % 2 ? 'b0' : 'b1')) w++; } return Math.round(100 * w / N); };
const hn = duel('hard', 'normal', 1000), ne = duel('normal', 'easy', 1000), he = duel('hard', 'easy', 1000);
console.log('    difícil vs normal: ' + hn + '%   normal vs fácil: ' + ne + '%   difícil vs fácil: ' + he + '%');
assert.ok(hn > 52 && ne > 52 && he > 60, 'las dificultades no están ordenadas');
ok('la IA difícil vence a la normal, y la normal a la fácil');
console.log('\n' + n + ' grupos de pruebas OK');
