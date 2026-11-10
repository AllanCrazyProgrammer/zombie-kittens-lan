/* Motor de reglas de Zombie Kittens (autoritativo, corre en el dispositivo anfitrión).
 * Sin dependencias: funciona igual en el navegador/WebView y en Node (pruebas). */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.ZKEngine = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // [tipo, copias CON huella, copias SIN huella]  (reglamento oficial: 24 con, 33 sin, + 4 explosivos = 61)
  const DECK = [
    ['zombie', 2, 3], ['attack', 2, 0], ['attack_dead', 0, 3], ['nope', 2, 3],
    ['skip', 1, 2], ['super_skip', 1, 1], ['see_future', 2, 2], ['shuffle', 1, 1],
    ['feed_dead', 0, 2], ['clone', 1, 2], ['grave_robber', 0, 1], ['favor', 1, 2],
    ['dig_deeper', 2, 2], ['clairvoyance', 1, 1],
    ['cat_a', 2, 2], ['cat_b', 2, 2], ['cat_c', 2, 2], ['cat_d', 2, 2],
  ];
  const NAMES = {
    exploding: 'Gatito Explosivo', zombie: 'Gatito Zombi', attack: 'Ataque (2x)',
    attack_dead: 'Ataque de los Muertos', nope: 'Nop', skip: 'Saltar', super_skip: 'Súper Salto',
    see_future: 'Ver el Futuro (3x)', shuffle: 'Barajar', feed_dead: 'Alimenta a los Muertos',
    clone: 'Clon', grave_robber: 'Ladrón de Tumbas', favor: 'Favor', dig_deeper: 'Cava Más Hondo',
    clairvoyance: 'Clarividencia', cat_a: 'Gato Momia', cat_b: 'Vampigato', cat_c: 'Fantasmiau',
    cat_d: 'Esquelegato',
  };
  const NOW = { shuffle: 1, feed_dead: 1, clairvoyance: 1 };
  const CFG = { NOPE_MS: 6500, FAST_MS: 900, PROMPT_MS: 40000, GONE_MS: 6000, CLAIR_MS: 4000, HAND: 7 };
  const isCat = (t) => t.indexOf('cat_') === 0;

  function shuffleArr(a, rnd) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(rnd() * (i + 1));
      const t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  class Game {
    constructor(opts) {
      this.rnd = opts.rnd || Math.random;
      this.cfg = Object.assign({}, CFG, opts.cfg || {});
      this.players = opts.players.map((p) => ({
        id: p.id, name: p.name, avatar: p.avatar || 0, bot: !!p.bot,
        hand: [], alive: true, ek: null, connected: true,
      }));
      this.draw = []; this.discard = []; this.stack = [];
      this.prompt = null; this.over = null;
      this.events = []; this.seq = 0; this.pid = 0; this.mut = 0; this.shuf = 0;
      this.cur = 0; this.turnsLeft = 1; this.attacked = false; this.idleSince = opts.now || 0;
      this.setup(opts.deckMode || 'official');
    }

    setup(mode) {
      const n = this.players.length;
      let id = 0;
      const cards = [], zombies = [], eks = [];
      for (const [type, w, wo] of DECK) {
        const make = (k, paw) => { for (let i = 0; i < k; i++) (type === 'zombie' ? zombies : cards).push({ id: 'c' + (++id), type, paw }); };
        if (mode === 'full' || n >= 4) { make(w, true); make(wo, false); }
        else if (n === 2) make(w, true);
        else make(wo, false);
      }
      for (let i = 0; i < 4; i++) eks.push({ id: 'c' + (++id), type: 'exploding', paw: false });
      shuffleArr(zombies, this.rnd);
      for (const p of this.players) if (zombies.length) p.hand.push(zombies.pop());
      cards.push(...zombies);
      shuffleArr(cards, this.rnd);
      for (let k = 0; k < this.cfg.HAND; k++) for (const p of this.players) if (cards.length) p.hand.push(cards.pop());
      for (let i = 0; i < n - 1; i++) cards.push(eks.pop());
      this.draw = shuffleArr(cards, this.rnd);
      this.cur = Math.floor(this.rnd() * n);
      this.emit('start', { text: '¡Comienza la partida! Empieza ' + this.curP().name + '.' });
    }

    /* ---------- utilidades ---------- */
    P(id) { return this.players.find((p) => p.id === id); }
    curP() { return this.players[this.cur]; }
    living() { return this.players.filter((p) => p.alive); }
    dead() { return this.players.filter((p) => !p.alive); }
    top() { return this.stack[this.stack.length - 1]; }
    topDiscard() { return this.discard[this.discard.length - 1]; }
    idle() { return !this.prompt && !this.stack.length && !this.over; }
    emit(type, data, to) {
      const e = Object.assign({ seq: ++this.seq, type }, data || {});
      if (to) e.to = to;
      this.events.push(e);
      if (this.events.length > 80) this.events.splice(0, this.events.length - 80);
      return e;
    }
    shuffleDraw() { shuffleArr(this.draw, this.rnd); this.mut++; this.shuf++; }
    nextLivingIdx(from) {
      const n = this.players.length;
      for (let k = 1; k <= n; k++) { const i = (from + k) % n; if (this.players[i].alive) return i; }
      return from;
    }
    dl(ids, now, base) {
      const gone = ids.every((id) => { const p = this.P(id); return p && !p.bot && !p.connected; });
      return now + (gone ? this.cfg.GONE_MS : (base || this.cfg.PROMPT_MS));
    }

    /* ---------- validación de jugadas ---------- */
    plan(pid, ids, target, named) {
      if (this.over) return { err: 'La partida ya terminó.' };
      const p = this.P(pid);
      if (!p) return { err: 'Jugador desconocido.' };
      if (!ids || !ids.length || ids.length > 3) return { err: 'Selección inválida.' };
      const cards = [];
      for (const id of ids) {
        const c = p.hand.find((x) => x.id === id);
        if (!c || cards.indexOf(c) >= 0) return { err: 'No tienes esa carta.' };
        cards.push(c);
      }
      const isCur = this.curP().id === pid;
      const pr = this.prompt;
      const deadN = this.dead().length;

      if (cards.length === 1) {
        let eff = cards[0].type;
        if (eff === 'clone') {
          if (!p.alive || !isCur) return { err: 'El Clon solo se juega en tu turno y estando vivo.' };
          const td = this.topDiscard();
          if (!td) return { err: 'No hay ninguna carta debajo para clonar.' };
          if (td.card.type === 'clone') return { err: 'No puedes jugar un Clon sobre otro Clon.' };
          eff = td.card.type;
          if (isCat(eff) || eff === 'exploding') return { err: 'Clonar esa carta sola no hace nada. Úsalo en pareja con otra carta.' };
        }
        if (eff === 'zombie') {
          if (!(pr && pr.type === 'explode' && pr.player === pid)) return { err: 'El Gatito Zombi se juega cuando sacas un Gatito Explosivo (o en combos).' };
          return { kind: 'zombie', eff, cards };
        }
        if (isCat(eff)) return { err: 'Las cartas de gato se juegan en pareja o en trío.' };
        if (eff === 'nope') {
          const t = this.top();
          if (!t || (pr && pr.type !== 'zombie')) return { err: 'No hay ninguna jugada que anular ahora.' };
          if (t.last === pid) return { err: 'No puedes anular tu propia jugada.' };
          return { kind: 'nope', eff, cards };
        }
        if (eff === 'clairvoyance') {
          if (!(pr && pr.type === 'zombie' && pr.player !== pid)) return { err: 'Clarividencia se juega cuando OTRO jugador usa un Gatito Zombi.' };
          if (pr.watchers.indexOf(pid) >= 0 || this.stack.some((s) => s.eff === 'clairvoyance' && s.by === pid)) return { err: 'Ya estás mirando.' };
          return { kind: 'action', eff, cards };
        }
        if (pr) return { err: 'Espera a que termine la acción en curso.' };
        if (NOW[eff]) {
          if (eff === 'feed_dead') {
            if (!deadN) return { err: 'No hay jugadores muertos.' };
            if (!target) return { need: 'dead', eff, cards };
            const t = this.P(target);
            if (!t || t.alive) return { err: 'Elige a un jugador muerto.' };
          }
          return { kind: 'action', eff, cards, target: eff === 'feed_dead' ? target : null };
        }
        if (!isCur || !p.alive) return { err: 'Solo puedes jugar esa carta en tu turno.' };
        if (this.stack.length) return { err: 'Espera a que se resuelva la jugada anterior.' };
        if ((eff === 'attack_dead' || eff === 'grave_robber') && !deadN) return { err: 'No hay jugadores muertos: no puedes jugar esta carta.' };
        if (eff === 'favor') {
          if (!this.players.some((o) => o.id !== pid && o.alive && o.hand.length)) return { err: 'Nadie tiene cartas para darte.' };
          if (!target) return { need: 'living', eff, cards };
          const t = this.P(target);
          if (!t || !t.alive || t.id === pid || !t.hand.length) return { err: 'Elige a un jugador vivo con cartas.' };
          return { kind: 'action', eff, cards, target };
        }
        return { kind: 'action', eff, cards, target: null };
      }

      // Combos especiales: dos o tres iguales (el Clon copia a la carta que acompaña)
      const real = cards.filter((c) => c.type !== 'clone');
      if (!real.length) return { err: 'Un combo necesita al menos una carta que no sea Clon.' };
      if (real.some((c) => c.type !== real[0].type)) return { err: 'Las cartas del combo deben tener el mismo título.' };
      if (!isCur || !p.alive) return { err: 'Los combos solo se juegan en tu turno.' };
      if (pr) return { err: 'Espera a que termine la acción en curso.' };
      if (this.stack.length) return { err: 'Espera a que se resuelva la jugada anterior.' };
      if (!this.players.some((o) => o.id !== pid && o.alive && o.hand.length)) return { err: 'Ningún jugador vivo tiene cartas para robar.' };
      const eff = cards.length === 2 ? 'combo2' : 'combo3';
      if (!target) return { need: 'living', eff, cards, of: real[0].type };
      const t = this.P(target);
      if (!t || !t.alive || t.id === pid || !t.hand.length) return { err: 'Elige a un jugador vivo con cartas.' };
      if (eff === 'combo3') {
        if (!named) return { need: 'named', eff, cards, target, of: real[0].type };
        if (!NAMES[named] || named === 'exploding') return { err: 'Carta inválida.' };
      }
      return { kind: 'action', eff, cards, target, named: eff === 'combo3' ? named : null, of: real[0].type };
    }

    /* ---------- entrada de acciones ---------- */
    act(pid, a, now) {
      if (this.over) return 'La partida ya terminó.';
      const p = this.P(pid);
      if (!p || !a) return 'Acción inválida.';
      let err = null;
      switch (a.a) {
        case 'play': err = this.doPlay(p, a, now); break;
        case 'draw': err = this.doDraw(p, now); break;
        case 'pass': err = this.doPass(p, now); break;
        case 'die': err = this.doDie(p, now); break;
        case 'revive': err = this.doRevive(p, a.target, now); break;
        case 'insert': err = this.doInsert(p, a.positions, now); break;
        case 'give': err = this.doGive(p, a.card, now); break;
        case 'dig': err = this.doDig(p, !!a.keep, now); break;
        default: err = 'Acción desconocida.';
      }
      if (!err) this.idleSince = now;
      return err || null;
    }

    doPlay(p, a, now) {
      const pl = this.plan(p.id, a.cards, a.target, a.named);
      if (pl.err) return pl.err;
      if (pl.need) return 'Falta elegir un objetivo.';
      for (const c of pl.cards) {
        p.hand.splice(p.hand.indexOf(c), 1);
        this.discard.push({ card: c, by: p.id });
      }
      const cardName = pl.cards.length === 1 && pl.cards[0].type === 'clone' ? 'Clon (como ' + NAMES[pl.eff] + ')' : NAMES[pl.cards[0].type];
      if (pl.kind === 'zombie') {
        const pr = this.prompt;
        const deadP = this.dead();
        const clair = this.players.some((o) => o.id !== p.id && o.hand.some((c) => c.type === 'clairvoyance'));
        this.prompt = {
          type: 'zombie', player: p.id, eks: [pr.card], needRevive: deadP.length > 0, revived: null,
          watchers: [], pendingPos: null, minUntil: clair ? now + this.cfg.CLAIR_MS : now,
          start: now, deadline: this.dl([p.id], now, this.cfg.PROMPT_MS + 15000),
        };
        this.emit('zombie', { player: p.id, text: p.name + ' juega ' + cardName + ' y se salva de explotar.' });
        if (deadP.length === 1) this.doRevive(p, deadP[0].id, now);
        return null;
      }
      if (pl.kind === 'nope') {
        const t = this.top();
        t.nopes++; t.last = p.id;
        const yup = t.nopes % 2 === 0;
        this.emit('nope', { player: p.id, yup, text: p.name + (yup ? ' responde con otro Nop: ¡la jugada vuelve a valer!' : ' dice ¡NOP! a ' + this.P(t.by).name + '.') });
        this.openWindow(now);
        return null;
      }
      const s = {
        id: ++this.pid, eff: pl.eff, by: p.id, last: p.id, target: pl.target || null, named: pl.named || null,
        of: pl.of || null, n: pl.cards.length, nopes: 0, passed: {}, deadline: 0, total: 0,
      };
      let text;
      const tn = s.target ? this.P(s.target).name : '';
      if (s.eff === 'combo2') text = p.name + ' juega una pareja de ' + NAMES[s.of] + ' contra ' + tn + '.';
      else if (s.eff === 'combo3') text = p.name + ' juega un trío de ' + NAMES[s.of] + ' contra ' + tn + ' y pide: ' + NAMES[s.named] + '.';
      else if (s.eff === 'favor') text = p.name + ' pide un Favor a ' + tn + '.';
      else if (s.eff === 'feed_dead') text = p.name + ' juega Alimenta a los Muertos para ' + tn + '.';
      else text = p.name + ' juega ' + cardName + '.';
      this.emit('play', { player: p.id, eff: s.eff, text });
      this.stack.push(s);
      this.openWindow(now);
      return null;
    }

    eligible(s) {
      return this.players.filter((o) => o.id !== s.last && (o.bot || o.connected) && o.hand.some((c) => c.type === 'nope'));
    }
    openWindow(now) {
      const s = this.top();
      if (!s) return;
      s.passed = {};
      s.total = this.eligible(s).length ? this.cfg.NOPE_MS : this.cfg.FAST_MS;
      s.deadline = now + s.total;
    }
    doPass(p, now) {
      const s = this.top();
      if (!s || (this.prompt && this.prompt.type !== 'zombie')) return 'No hay nada que pasar.';
      s.passed[p.id] = 1;
      if (this.eligible(s).every((o) => s.passed[o.id])) this.resolveTop(now);
      return null;
    }
    resolveTop(now) {
      const s = this.stack.pop();
      if (!s) return;
      if (s.nopes % 2) this.emit('cancel', { eff: s.eff, text: 'La jugada de ' + this.P(s.by).name + ' fue anulada.' });
      else this.apply(s, now);
      this.settle(now);
    }
    settle(now) {
      if (this.over) return;
      if (this.prompt && this.prompt.type !== 'zombie') return;
      if (this.stack.length) this.openWindow(now);
    }

    /* ---------- efectos ---------- */
    apply(s, now) {
      const p = this.P(s.by);
      const isCur = this.curP().id === p.id;
      switch (s.eff) {
        case 'attack':
        case 'attack_dead': {
          if (!isCur) return;
          const add = s.eff === 'attack' ? 2 : 3 * this.dead().length;
          if (!add) { this.emit('info', { text: 'Ya no hay muertos: el Ataque de los Muertos no tiene efecto.' }); return; }
          const n = (this.attacked ? this.turnsLeft : 0) + add;
          this.advance(n, true, now);
          this.emit('attack', { player: p.id, target: this.curP().id, n, text: this.curP().name + ' debe jugar ' + n + ' turnos seguidos.' });
          return;
        }
        case 'skip': if (isCur) { this.emit('info', { text: p.name + ' termina su turno sin robar.' }); this.endTurn(now); } return;
        case 'super_skip': if (isCur) { this.emit('info', { text: p.name + ' termina TODOS sus turnos sin robar.' }); this.advance(1, false, now); } return;
        case 'see_future': {
          const cards = this.draw.slice(-3).reverse().map((c) => c.type);
          this.emit('future', { cards, mut: this.mut, len: this.draw.length, shuf: this.shuf }, p.id);
          return;
        }
        case 'shuffle': this.shuffleDraw(); this.emit('shuffle', { text: 'El mazo fue barajado.' }); return;
        case 'feed_dead': {
          const t = this.P(s.target);
          if (!t || t.alive) return;
          const givers = this.living().filter((o) => o.id !== p.id && o.hand.length);
          if (!givers.length) return;
          this.startGive('feed', t.id, givers, now);
          return;
        }
        case 'favor': {
          const t = this.P(s.target);
          if (!t || !t.alive || !t.hand.length) return;
          this.startGive('favor', p.id, [t], now);
          return;
        }
        case 'grave_robber': {
          const givers = this.dead().filter((o) => o.hand.length);
          if (!givers.length) { this.emit('info', { text: 'Los muertos no tienen cartas que robar.' }); return; }
          this.startGive('rob', null, givers, now);
          return;
        }
        case 'dig_deeper': {
          if (!isCur) return;
          if (this.draw.length <= 1) { this.emit('info', { text: 'Solo queda 1 carta en el mazo: Cava Más Hondo no tiene efecto.' }); return; }
          const card = this.draw.pop(); this.mut++;
          this.prompt = { type: 'dig', player: p.id, card, start: now, deadline: this.dl([p.id], now) };
          return;
        }
        case 'combo2': {
          const t = this.P(s.target);
          if (!t || !t.alive || !t.hand.length) return;
          const c = t.hand.splice(Math.floor(this.rnd() * t.hand.length), 1)[0];
          p.hand.push(c);
          this.emit('steal', { player: p.id, target: t.id, text: p.name + ' le roba una carta al azar a ' + t.name + '.' });
          this.emit('got', { card: c.type, text: 'Le robaste ' + NAMES[c.type] + ' a ' + t.name + '.' }, p.id);
          this.emit('lost', { card: c.type, text: p.name + ' te robó ' + NAMES[c.type] + '.' }, t.id);
          return;
        }
        case 'combo3': {
          const t = this.P(s.target);
          if (!t || !t.alive) return;
          const i = t.hand.findIndex((c) => c.type === s.named);
          if (i < 0) { this.emit('info', { text: t.name + ' no tiene ' + NAMES[s.named] + '. ' + p.name + ' no consigue nada.' }); return; }
          const c = t.hand.splice(i, 1)[0];
          p.hand.push(c);
          this.emit('steal', { player: p.id, target: t.id, card: c.type, text: p.name + ' le quita ' + NAMES[c.type] + ' a ' + t.name + '.' });
          return;
        }
        case 'clairvoyance': {
          const pr = this.prompt;
          if (pr && pr.type === 'zombie' && pr.watchers.indexOf(p.id) < 0) pr.watchers.push(p.id);
          return;
        }
      }
    }

    startGive(reason, to, givers, now) {
      const waiting = {};
      for (const g of givers) waiting[g.id] = 1;
      this.prompt = { type: 'give', reason, to, waiting, pool: [], start: now, deadline: this.dl(givers.map((g) => g.id), now) };
    }
    doGive(p, cardId, now) {
      const pr = this.prompt;
      if (!pr || pr.type !== 'give' || !pr.waiting[p.id]) return 'No tienes que dar ninguna carta.';
      const i = p.hand.findIndex((c) => c.id === cardId);
      if (i < 0) return 'No tienes esa carta.';
      const c = p.hand.splice(i, 1)[0];
      delete pr.waiting[p.id];
      if (pr.reason === 'rob') {
        pr.pool.push(c);
        this.emit('info', { text: p.name + ' entrega una carta al mazo.' });
      } else {
        const t = this.P(pr.to);
        t.hand.push(c);
        this.emit('gave', { player: p.id, target: t.id, text: p.name + ' le da una carta a ' + t.name + '.' });
        this.emit('got', { card: c.type, text: p.name + ' te dio ' + NAMES[c.type] + '.' }, t.id);
      }
      if (!Object.keys(pr.waiting).length) {
        this.prompt = null;
        if (pr.reason === 'rob') { this.draw.push(...pr.pool); this.shuffleDraw(); this.emit('shuffle', { text: 'Las cartas de los muertos se barajan en el mazo.' }); }
        this.settle(now);
      }
      return null;
    }

    /* ---------- robar / explotar / zombi ---------- */
    doDraw(p, now) {
      if (this.curP().id !== p.id || !p.alive) return 'No es tu turno.';
      if (!this.idle()) return 'Espera a que termine la acción en curso.';
      const c = this.draw.pop(); this.mut++;
      this.emit('draw', { player: p.id });
      this.receive(p, c, now);
      return null;
    }
    receive(p, c, now) {
      if (c.type === 'exploding') {
        const td = this.topDiscard();
        const canSave = p.hand.some((x) => x.type === 'zombie') ||
          (p.hand.some((x) => x.type === 'clone') && td && td.card.type === 'zombie');
        this.emit('boom', { player: p.id, text: '¡' + p.name + ' sacó un GATITO EXPLOSIVO!' });
        if (!canSave) { this.die(p, c, now); return; }
        this.prompt = { type: 'explode', player: p.id, card: c, start: now, deadline: this.dl([p.id], now, 25000) };
        return;
      }
      p.hand.push(c);
      this.emit('got', { card: c.type, drawn: true, text: 'Robaste: ' + NAMES[c.type] + '.' }, p.id);
      this.endTurn(now);
    }
    doDie(p, now) {
      const pr = this.prompt;
      if (!pr || pr.type !== 'explode' || pr.player !== p.id) return 'No puedes hacer eso ahora.';
      this.die(p, pr.card, now);
      return null;
    }
    die(p, card, now) {
      this.prompt = null;
      p.alive = false; p.ek = card;
      this.emit('died', { player: p.id, text: '💥 ' + p.name + ' explotó y está MUERTO (por ahora).' });
      const alive = this.living();
      if (alive.length <= 1) {
        this.over = { winner: alive[0] ? alive[0].id : null };
        this.stack = [];
        this.emit('over', { winner: this.over.winner, text: '🏆 ' + (alive[0] ? alive[0].name : 'Nadie') + ' es el último gatito con vida. ¡Gana la partida!' });
        return;
      }
      this.advance(1, false, now);
    }
    doRevive(p, target, now) {
      const pr = this.prompt;
      if (!pr || pr.type !== 'zombie' || pr.player !== p.id) return 'No puedes hacer eso ahora.';
      if (!pr.needRevive || pr.revived) return 'No hay nadie a quien revivir.';
      const t = this.P(target);
      if (!t || t.alive) return 'Elige a un jugador muerto.';
      t.alive = true; pr.eks.push(t.ek); t.ek = null; pr.revived = t.id;
      this.emit('revived', { player: p.id, target: t.id, text: '🧟 ' + p.name + ' revive a ' + t.name + '. ¡Vuelve al juego!' });
      return null;
    }
    doInsert(p, positions, now) {
      const pr = this.prompt;
      if (!pr || pr.type !== 'zombie' || pr.player !== p.id) return 'No puedes hacer eso ahora.';
      if (pr.needRevive && !pr.revived) return 'Primero elige a quién revivir.';
      if (!Array.isArray(positions) || positions.length !== pr.eks.length) return 'Posiciones inválidas.';
      for (let i = 0; i < positions.length; i++) {
        const v = positions[i];
        if (!Number.isInteger(v) || v < 0 || v > this.draw.length + i) return 'Posición fuera del mazo.';
      }
      pr.pendingPos = positions.slice();
      if (!this.stack.length && now >= pr.minUntil) this.finishInsert(now);
      return null;
    }
    finishInsert(now) {
      const pr = this.prompt;
      const p = this.P(pr.player);
      pr.pendingPos.forEach((pos, i) => {
        this.draw.splice(Math.max(0, this.draw.length - pos), 0, pr.eks[i]);
      });
      this.mut++; this.shuf++;
      for (const w of pr.watchers) {
        this.emit('clair', { positions: pr.pendingPos.slice(), len: this.draw.length, shuf: this.shuf, text: 'Clarividencia: viste dónde quedó cada Gatito Explosivo.' }, w);
      }
      this.prompt = null;
      this.emit('inserted', { player: p.id, n: pr.eks.length, len: this.draw.length, shuf: this.shuf, text: p.name + ' esconde ' + (pr.eks.length > 1 ? 'los ' + pr.eks.length + ' Gatitos Explosivos' : 'el Gatito Explosivo') + ' en el mazo.' });
      this.endTurn(now);
      this.settle(now);
    }
    doDig(p, keep, now) {
      const pr = this.prompt;
      if (!pr || pr.type !== 'dig' || pr.player !== p.id) return 'No puedes hacer eso ahora.';
      this.prompt = null;
      if (keep) {
        this.emit('info', { text: p.name + ' se queda con la primera carta.' });
        this.receive(p, pr.card, now);
      } else {
        const second = this.draw.pop();
        this.draw.push(pr.card); this.mut++; this.shuf++;
        this.emit('info', { text: p.name + ' no quiso la primera carta… y roba la siguiente.' });
        this.receive(p, second, now);
      }
      this.settle(now);
      return null;
    }

    endTurn(now) {
      this.turnsLeft--;
      if (this.turnsLeft <= 0) this.advance(1, false, now);
      else this.idleSince = now;
    }
    advance(n, attacked, now) {
      this.cur = this.nextLivingIdx(this.cur);
      this.turnsLeft = n; this.attacked = attacked; this.idleSince = now;
      this.emit('turn', { player: this.curP().id });
    }

    /* ---------- tiempo: plazos y acciones automáticas ---------- */
    setConnected(pid, on, now) {
      const p = this.P(pid);
      if (!p) return;
      p.connected = on;
      const pr = this.prompt;
      if (!on && pr) {
        const mine = pr.player === pid || (pr.waiting && pr.waiting[pid]);
        if (mine) pr.deadline = Math.min(pr.deadline, now + this.cfg.GONE_MS);
      }
      if (!on) this.idleSince = Math.max(this.idleSince, now);
    }
    nextDeadline() {
      if (this.over) return null;
      const pr = this.prompt;
      let d = Infinity;
      if (this.stack.length && (!pr || pr.type === 'zombie')) d = Math.min(d, this.top().deadline);
      if (pr) {
        d = Math.min(d, pr.deadline);
        if (pr.type === 'zombie' && pr.pendingPos) d = Math.min(d, pr.minUntil);
      }
      const c = this.curP();
      if (this.idle() && !c.bot && !c.connected) d = Math.min(d, this.idleSince + this.cfg.GONE_MS);
      return d === Infinity ? null : d;
    }
    tick(now) {
      for (let guard = 0; guard < 30 && !this.over; guard++) {
        const pr = this.prompt;
        if (pr && pr.type === 'zombie' && pr.pendingPos && !this.stack.length && now >= pr.minUntil) { this.finishInsert(now); continue; }
        if (this.stack.length && (!pr || pr.type === 'zombie') && now >= this.top().deadline) { this.resolveTop(now); continue; }
        if (pr && now >= pr.deadline) { this.autoPrompt(now); continue; }
        const c = this.curP();
        if (this.idle() && !c.bot && !c.connected && now >= this.idleSince + this.cfg.GONE_MS) { this.act(c.id, { a: 'draw' }, now); continue; }
        break;
      }
    }
    autoPrompt(now) {
      const pr = this.prompt;
      const pick = (arr) => arr[Math.floor(this.rnd() * arr.length)];
      if (pr.type === 'explode') {
        const p = this.P(pr.player);
        const z = p.hand.find((c) => c.type === 'zombie') || p.hand.find((c) => c.type === 'clone');
        if (!z || this.act(p.id, { a: 'play', cards: [z.id] }, now)) this.die(p, pr.card, now);
      } else if (pr.type === 'zombie') {
        const p = this.P(pr.player);
        if (pr.needRevive && !pr.revived) this.doRevive(p, pick(this.dead()).id, now);
        if (!pr.pendingPos) {
          const pos = pr.eks.map((_, i) => Math.floor(this.rnd() * (this.draw.length + i + 1)));
          this.doInsert(p, pos, now);
        }
        if (this.prompt === pr) { this.stack = []; pr.minUntil = now; this.finishInsert(now); }
      } else if (pr.type === 'give') {
        for (const id of Object.keys(pr.waiting)) { const p = this.P(id); this.doGive(p, pick(p.hand).id, now); }
      } else if (pr.type === 'dig') {
        this.doDig(this.P(pr.player), true, now);
      }
    }

    /* ---------- vista por jugador (oculta la información secreta) ---------- */
    view(pid, now) {
      const me = this.P(pid);
      const pr = this.prompt;
      const t = this.top();
      const v = {
        you: pid,
        players: this.players.map((p) => ({ id: p.id, name: p.name, avatar: p.avatar, bot: p.bot, alive: p.alive, connected: p.connected, count: p.hand.length })),
        hand: me ? me.hand.map((c) => ({ id: c.id, type: c.type, paw: c.paw })) : [],
        playable: {},
        draw: this.draw.length, discardN: this.discard.length,
        discard: this.discard.slice(-5).map((d) => ({ id: d.card.id, type: d.card.type, by: d.by })),
        cur: this.curP().id, turnsLeft: this.turnsLeft, attacked: this.attacked,
        deadN: this.dead().length,
        stack: this.stack.map((s) => ({ id: s.id, eff: s.eff, of: s.of, by: s.by, target: s.target, named: s.named, nopes: s.nopes, last: s.last })),
        win: null, prompt: null, over: this.over,
        events: this.events.filter((e) => !e.to || e.to === pid),
      };
      if (me) for (const c of me.hand) {
        const pl = this.plan(pid, [c.id]);
        if (!pl.err) v.playable[c.id] = pl.need || 1;
      }
      if (t && (!pr || pr.type === 'zombie')) {
        v.win = {
          remain: Math.max(0, t.deadline - now), total: t.total,
          canNope: !!me && t.last !== pid && me.hand.some((c) => c.type === 'nope'),
          passed: !!t.passed[pid],
        };
      }
      if (pr) {
        const o = { type: pr.type, remain: Math.max(0, pr.deadline - now), total: pr.deadline - pr.start };
        if (pr.type === 'explode') { o.player = pr.player; o.mine = pr.player === pid; }
        else if (pr.type === 'zombie') {
          o.player = pr.player; o.mine = pr.player === pid; o.needRevive = pr.needRevive; o.revived = pr.revived;
          o.eks = pr.eks.length; o.waiting = !!pr.pendingPos; o.watching = pr.watchers.indexOf(pid) >= 0;
        } else if (pr.type === 'give') {
          o.reason = pr.reason; o.to = pr.to; o.waiting = Object.keys(pr.waiting); o.mine = !!pr.waiting[pid];
        } else if (pr.type === 'dig') {
          o.player = pr.player; o.mine = pr.player === pid; o.card = o.mine ? pr.card.type : null;
        }
        v.prompt = o;
      }
      return v;
    }
  }

  return { Game, DECK, NAMES, NOW, isCat, shuffleArr };
});
