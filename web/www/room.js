/* Sala de juego: vive en el dispositivo anfitrión. Maneja el lobby, reconexiones, bots y temporizadores. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./engine.js'));
  else root.ZKRoom = factory(root.ZKEngine);
})(typeof self !== 'undefined' ? self : this, function (E) {
  'use strict';

  const BOT_NAMES = ['Bigotes', 'Garritas', 'Pelusa', 'Don Miau', 'Ronroneo', 'Michi'];
  const VALUE = { zombie: 10, nope: 7, attack: 6, attack_dead: 6, super_skip: 6, skip: 5, see_future: 4, shuffle: 4, dig_deeper: 4, clone: 4, favor: 3, clairvoyance: 2, feed_dead: 2, grave_robber: 2 };
  const val = (t) => VALUE[t] || 1;
  const LEVELS = ['easy', 'normal', 'hard'];
  // profundidad final (desde arriba) de cada explosivo tras insertarlos uno tras otro
  const depths = (pos) => { const at = {}; if (pos.length > 1) { at[pos[0] + (pos[1] <= pos[0] ? 1 : 0)] = 'exploding'; at[pos[1]] = 'exploding'; } else at[pos[0]] = 'exploding'; return at; };

  class Room {
    /* io: { send(cid, msg), now(), setTimeout, clearTimeout, rnd } */
    constructor(io) {
      this.io = Object.assign({ now: () => Date.now(), setTimeout: (f, ms) => setTimeout(f, ms), clearTimeout: (t) => clearTimeout(t), rnd: Math.random }, io);
      this.players = [];          // {id, token, name, avatar, bot, cid, host}
      this.settings = { deckMode: 'official' };
      this.game = null;
      this.timer = null; this.botTimers = {}; this.mem = {}; this.botSeq = 0; this.pendingIns = {};
      this.nextId = 1;
    }

    /* ----- conexiones ----- */
    onClose(cid) {
      const p = this.players.find((x) => x.cid === cid);
      if (!p) return;
      p.cid = null;
      if (this.game) { this.game.setConnected(p.id, false, this.io.now()); this.sync(); }
      else { if (!p.host) this.players.splice(this.players.indexOf(p), 1); this.sendLobby(); }
    }
    onMsg(cid, m) {
      if (!m || typeof m !== 'object') return;
      let p = this.players.find((x) => x.cid === cid);
      if (m.t === 'hello') return this.hello(cid, m);
      if (!p) return;
      const host = p.host;
      switch (m.t) {
        case 'set':
          if (this.game) return;
          if (typeof m.name === 'string') p.name = this.cleanName(m.name, p);
          if (Number.isInteger(m.avatar)) p.avatar = m.avatar % 8;
          return this.sendLobby();
        case 'addBot': {
          if (!host || this.game || this.players.length >= 5) return;
          const used = this.players.map((x) => x.name);
          const name = BOT_NAMES.find((n) => used.indexOf(n) < 0) || 'Bot';
          this.players.push({ id: 'p' + this.nextId++, token: null, name, avatar: Math.floor(this.io.rnd() * 8), bot: true, level: LEVELS.indexOf(m.level) >= 0 ? m.level : 'normal', cid: null, host: false });
          return this.sendLobby();
        }
        case 'botLevel': {
          if (!host || this.game) return;
          const b = this.players.find((x) => x.id === m.id && x.bot);
          if (!b) return;
          b.level = LEVELS.indexOf(m.level) >= 0 ? m.level : LEVELS[(LEVELS.indexOf(b.level || 'normal') + 1) % 3];
          return this.sendLobby();
        }
        case 'kick': {
          if (!host || this.game) return;
          const k = this.players.find((x) => x.id === m.id);
          if (!k || k.host) return;
          this.players.splice(this.players.indexOf(k), 1);
          if (k.cid) this.io.send(k.cid, { t: 'kicked' });
          return this.sendLobby();
        }
        case 'settings':
          if (!host || this.game) return;
          if (m.deckMode === 'official' || m.deckMode === 'full') this.settings.deckMode = m.deckMode;
          return this.sendLobby();
        case 'start':
          if (!host || this.game) return;
          if (this.players.length < 2) return this.io.send(cid, { t: 'err', msg: 'Se necesitan al menos 2 jugadores.' });
          return this.start();
        case 'toLobby':
          if (!host) return;
          this.stopTimers(); this.game = null;
          this.players = this.players.filter((x) => x.bot || x.cid);
          return this.sendLobby();
        case 'act': {
          if (!this.game) return;
          const err = this.game.act(p.id, m.a, this.io.now());
          if (err) this.io.send(cid, { t: 'err', msg: err });
          return this.sync();
        }
      }
    }
    cleanName(s, self) {
      let n = String(s).replace(/[<>&"']/g, '').trim().slice(0, 14) || 'Gatito';
      let base = n, k = 2;
      while (this.players.some((x) => x !== self && x.name === n)) n = base.slice(0, 12) + ' ' + k++;
      return n;
    }
    hello(cid, m) {
      let p = m.token && this.players.find((x) => x.token === m.token);
      if (p) {
        if (p.cid && p.cid !== cid) this.io.send(p.cid, { t: 'kicked', msg: 'Te conectaste desde otro lugar.' });
        p.cid = cid;
      } else {
        if (this.game) return this.io.send(cid, { t: 'full', msg: 'La partida ya empezó. Espera a la siguiente.' });
        if (this.players.length >= 5) return this.io.send(cid, { t: 'full', msg: 'La sala está llena (máximo 5 jugadores).' });
        p = { id: 'p' + this.nextId++, token: String(m.token || ''), name: '', avatar: Number.isInteger(m.avatar) ? m.avatar % 8 : 0, bot: false, cid, host: cid === 'local' };
        p.name = this.cleanName(m.name || 'Gatito', p);
        this.players.push(p);
      }
      this.io.send(cid, { t: 'welcome', you: p.id, host: p.host });
      if (this.game) { this.game.setConnected(p.id, true, this.io.now()); this.sync(); }
      else this.sendLobby();
    }

    /* ----- lobby / partida ----- */
    lobbyMsg() {
      return {
        t: 'lobby', settings: this.settings,
        players: this.players.map((p) => ({ id: p.id, name: p.name, avatar: p.avatar, bot: p.bot, host: p.host, level: p.bot ? (p.level || 'normal') : null })),
      };
    }
    sendLobby() { const m = this.lobbyMsg(); for (const p of this.players) if (p.cid) this.io.send(p.cid, m); }
    start() {
      const now = this.io.now();
      this.mem = {}; this.pendingIns = {}; this.botSeq = 0;
      this.game = new E.Game({ players: this.players, deckMode: this.settings.deckMode, rnd: this.io.rnd, now });
      for (const p of this.players) if (!p.bot && !p.cid) this.game.setConnected(p.id, false, now);
      this.sync();
    }
    stopTimers() {
      if (this.timer) this.io.clearTimeout(this.timer);
      this.timer = null;
      for (const k of Object.keys(this.botTimers)) this.io.clearTimeout(this.botTimers[k]);
      this.botTimers = {};
    }
    sync() {
      const g = this.game;
      if (!g) return;
      const now = this.io.now();
      g.tick(now);
      this.learn();
      for (const p of this.players) if (p.cid) this.io.send(p.cid, { t: 'state', view: g.view(p.id, now) });
      if (this.timer) { this.io.clearTimeout(this.timer); this.timer = null; }
      if (g.over) { this.stopTimers(); return; }
      const d = g.nextDeadline();
      if (d != null) this.timer = this.io.setTimeout(() => { this.timer = null; this.sync(); }, Math.max(20, d - now + 15));
      for (const p of this.players) {
        if (!p.bot || this.botTimers[p.id]) continue;
        if (!this.botDecide(p)) continue;
        this.botTimers[p.id] = this.io.setTimeout(() => {
          delete this.botTimers[p.id];
          if (!this.game || this.game.over) return;
          const a = this.botDecide(p);
          if (a) {
            const err = this.game.act(p.id, a, this.io.now());
            if (a.a === 'insert' && !err) this.pendingIns[p.id] = a.positions;
          }
          this.sync();
        }, 700 + Math.floor(this.io.rnd() * 900));
      }
    }

    /* ----- bots: juegan solo con su mano y lo que han visto ----- */
    learn() {
      const g = this.game;
      const lvl = (id) => { const p = this.players.find((x) => x.id === id); return p && p.bot ? (p.level || 'normal') : null; };
      for (const e of g.events) {
        if (e.seq <= this.botSeq) continue;
        if (e.type === 'future' && e.to && lvl(e.to) && lvl(e.to) !== 'easy') this.mem[e.to] = { at: { 0: e.cards[0], 1: e.cards[1], 2: e.cards[2] }, len: e.len, shuf: e.shuf };
        else if (e.type === 'clair' && e.to && lvl(e.to) === 'hard') this.mem[e.to] = { at: depths(e.positions), len: e.len, shuf: e.shuf };
        else if (e.type === 'inserted') {
          const pos = this.pendingIns[e.player];
          delete this.pendingIns[e.player];
          if (pos && lvl(e.player) === 'hard') this.mem[e.player] = { at: depths(pos), len: e.len, shuf: e.shuf };
        }
      }
      this.botSeq = g.seq;
    }
    /* Lo que el bot SABE de la carta a cierta profundidad del mazo (0 = la próxima), o null */
    known(id, depth) {
      const m = this.mem[id], g = this.game;
      if (!m || m.shuf !== g.shuf) return null;
      const d = m.len - g.draw.length + (depth || 0);
      return d >= 0 && m.at[d] ? m.at[d] : null;
    }
    knownEksBelow(id) {
      const m = this.mem[id], g = this.game;
      if (!m || m.shuf !== g.shuf) return 0;
      const off = m.len - g.draw.length;
      return Object.keys(m.at).filter((d) => Number(d) > off && m.at[d] === 'exploding').length;
    }

    /* FÁCIL: juega casi al azar.  NORMAL: reacciona al riesgo.  DIFÍCIL: recuerda el mazo, ataca y roba Zombis. */
    botDecide(b) {
      const g = this.game, rnd = this.io.rnd;
      if (!g || g.over) return null;
      const me = g.P(b.id), pr = g.prompt;
      if (!me) return null;
      const L = b.level || 'normal', easy = L === 'easy', hard = L === 'hard';
      const pick = (a) => a[Math.floor(rnd() * a.length)];
      const has = (t) => me.hand.find((c) => c.type === t);
      const play = (c, extra) => Object.assign({ a: 'play', cards: [c.id] }, extra || {});
      if (pr) {
        if (pr.type === 'explode' && pr.player === me.id) {
          const z = has('zombie') || has('clone');
          return z ? play(z) : { a: 'die' };
        }
        if (pr.type === 'zombie' && pr.player === me.id && !pr.pendingPos) {
          if (pr.needRevive && !pr.revived) {
            const dead = g.dead();
            return { a: 'revive', target: (hard ? dead.slice().sort((x, y) => x.hand.length - y.hand.length)[0] : pick(dead)).id };
          }
          const len = g.draw.length;
          let positions;
          if (easy) positions = pr.eks.map((_, i) => Math.floor(rnd() * (len + i + 1)));
          else if (hard) {
            // Si el siguiente en robar es un rival, el explosivo va arriba; si vuelvo a robar yo, al fondo.
            const selfNext = g.turnsLeft > 1;
            positions = pr.eks.map((_, i) => selfNext ? len + i : (i === 0 ? 0 : Math.min(len + i, 1 + Math.floor(rnd() * 3))));
          } else positions = pr.eks.map((_, i) => Math.floor(rnd() * Math.min(5, len + i + 1)));
          return { a: 'insert', positions };
        }
        if (pr.type === 'give' && pr.waiting[me.id]) {
          const c = easy ? pick(me.hand) : me.hand.slice().sort((x, y) => val(x.type) - val(y.type))[0];
          return { a: 'give', card: c.id };
        }
        if (pr.type === 'dig' && pr.player === me.id) return { a: 'dig', keep: pr.card.type !== 'exploding' || (easy && rnd() < 0.5) };
        if (pr.type !== 'zombie') return null;
        if (hard && pr.player !== me.id && !g.stack.length) {
          const cv = has('clairvoyance');
          if (cv && !g.plan(me.id, [cv.id]).err) return play(cv);
        }
      }
      const s = g.top();
      if (s) {
        const nope = has('nope');
        if (!nope || s.last === me.id || s.passed[me.id]) return null;
        const live = s.nopes % 2 === 0;
        const nextId = g.players[g.nextLivingIdx(g.cur)].id;
        const hurts = s.by !== me.id && ((s.target === me.id && (s.eff === 'favor' || s.eff === 'combo2' || s.eff === 'combo3')) ||
          ((s.eff === 'attack' || s.eff === 'attack_dead') && nextId === me.id));
        const want = (live && hurts) || (!live && s.by === me.id);
        return want && rnd() < (easy ? 0.15 : hard ? 0.95 : 0.75) ? play(nope) : { a: 'pass' };
      }
      if (pr || g.curP().id !== me.id || !me.alive) return null;

      const others = g.players.filter((o) => o.id !== me.id && o.alive && o.hand.length);
      const deadN = g.dead().length;

      if (easy) {
        if (rnd() < 0.15) {
          const opts = me.hand.filter((c) => ['attack', 'skip', 'super_skip', 'see_future', 'shuffle', 'dig_deeper', 'favor', 'attack_dead', 'grave_robber'].indexOf(c.type) >= 0 && !g.plan(me.id, [c.id]).err);
          if (opts.length) { const c = pick(opts); return play(c, c.type === 'favor' ? { target: pick(others).id } : null); }
        }
        return { a: 'draw' };
      }

      const top = this.known(me.id, 0);
      const eksIn = g.living().length - 1;
      let danger;
      if (top) danger = top === 'exploding' ? 1 : 0;
      else { const k = hard ? this.knownEksBelow(me.id) : 0; danger = Math.max(0, eksIn - k) / Math.max(1, g.draw.length - k); }

      if (!hard) {
        if (!top && danger > 0.18 && has('see_future')) return play(has('see_future'));
        if (danger > (has('zombie') ? 0.5 : 0.28)) {
          if (g.turnsLeft > 1 && has('super_skip')) return play(has('super_skip'));
          if (has('attack')) return play(has('attack'));
          if (has('attack_dead') && deadN) return play(has('attack_dead'));
          if (has('skip')) return play(has('skip'));
          if (has('super_skip')) return play(has('super_skip'));
          if (has('shuffle') && top) return play(has('shuffle'));
          if (has('dig_deeper') && g.draw.length > 1 && top) return play(has('dig_deeper'));
        }
        if (others.length && rnd() < 0.3) {
          const byType = {};
          for (const c of me.hand) if (c.type !== 'zombie' && c.type !== 'nope' && c.type !== 'clone') (byType[c.type] = byType[c.type] || []).push(c);
          const pair = Object.values(byType).filter((a) => a.length >= 2).sort((x, y) => val(x[0].type) - val(y[0].type))[0];
          if (pair && val(pair[0].type) <= 4) return { a: 'play', cards: [pair[0].id, pair[1].id], target: pick(others).id };
          if (has('favor')) return play(has('favor'), { target: pick(others).id });
        }
        if (deadN && has('grave_robber') && danger > 0.3 && rnd() < 0.5) return play(has('grave_robber'));
        return { a: 'draw' };
      }

      /* ----- DIFÍCIL ----- */
      const zs = me.hand.filter((c) => c.type === 'zombie').length;
      const richest = others.slice().sort((x, y) => y.hand.length - x.hand.length)[0];
      // 1) Fortalecerse: conseguir Gatitos Zombi y cartas ajenas mientras el riesgo es bajo
      if (richest) {
        const byType = {};
        for (const c of me.hand) if (c.type !== 'zombie' && c.type !== 'nope' && c.type !== 'clone') (byType[c.type] = byType[c.type] || []).push(c);
        const groups = Object.values(byType).filter((a) => val(a[0].type) <= 3).sort((x, y) => y.length - x.length || val(x[0].type) - val(y[0].type));
        const grp = groups[0];
        if (grp && grp.length >= 3 && zs < 2) return { a: 'play', cards: grp.slice(0, 3).map((c) => c.id), target: richest.id, named: 'zombie' };
        if (grp && grp.length >= 2) return { a: 'play', cards: grp.slice(0, 2).map((c) => c.id), target: richest.id };
        if (has('favor')) return play(has('favor'), { target: richest.id });
      }
      // 2) Informarse antes de arriesgar
      if (!top && danger >= 0.14 && has('see_future')) return play(has('see_future'));
      // 3) Esquivar: con Zombi en mano tolera más riesgo
      const thr = zs ? 0.34 : 0.2;
      if (danger >= thr) {
        if (g.turnsLeft > 1 && has('super_skip')) return play(has('super_skip'));
        if (has('attack')) return play(has('attack'));
        if (has('attack_dead') && deadN) return play(has('attack_dead'));
        if (has('skip')) return play(has('skip'));
        if (has('super_skip')) return play(has('super_skip'));
        if (has('dig_deeper') && g.draw.length > 1 && this.known(me.id, 1) !== 'exploding') return play(has('dig_deeper'));
        if (top === 'exploding' && has('shuffle')) return play(has('shuffle'));
        if (deadN && has('grave_robber') && g.dead().some((o) => o.hand.length)) return play(has('grave_robber'));
      }
      return { a: 'draw' };
    }
  }

  return { Room };
});
