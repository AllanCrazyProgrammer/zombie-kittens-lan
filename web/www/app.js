/* Interfaz del juego: pantallas, red (anfitrión / invitado), animaciones y sonido. */
(function () {
  'use strict';
  const K = window.ZKCards, C = K.C;
  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const store = {
    get(k, d) { try { const v = localStorage.getItem('zk_' + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem('zk_' + k, JSON.stringify(v)); } catch (e) { /* sin almacenamiento */ } },
  };
  const Native = window.Android || null;

  const S = {
    screen: 'home', name: store.get('name', ''), avatar: store.get('avatar', Math.floor(Math.random() * 8)),
    token: store.get('token', null), sound: store.get('sound', true),
    mode: null, you: null, isHost: false, lobby: null, view: null, viewAt: 0,
    sel: [], seq: 0, log: [], modal: null, ins: [0, 0], giveSel: null, fresh: true,
    info: { ip: '', port: 8765, local: true, native: !!Native, static: !!window.ZK_STATIC }, found: [], conn: 'off', joinHost: '',
    isSolo: false, solo: Object.assign({ n: 2, level: 'normal', deck: 'official' }, store.get('solo', {})),
  };
  const LEVELS = { easy: ['😺', 'Fácil', 'Juega casi al azar. Ideal para aprender.'], normal: ['😼', 'Normal', 'Esquiva cuando el riesgo sube y usa sus cartas con cabeza.'], hard: ['😈', 'Difícil', 'Recuerda el mazo, te roba los Zombis y te deja el explosivo arriba.'], mix: ['🎲', 'Mixta', 'Cada rival con una dificultad distinta.'] };
  if (!S.token) { S.token = Math.random().toString(36).slice(2) + Date.now().toString(36); store.set('token', S.token); }

  /* ================= sonido ================= */
  let ac = null;
  function tone(f, d, type, vol, slide, delay) {
    if (!S.sound) return;
    try {
      ac = ac || new (window.AudioContext || window.webkitAudioContext)();
      if (ac.state === 'suspended') ac.resume();
      const t = ac.currentTime + (delay || 0), o = ac.createOscillator(), g = ac.createGain();
      o.type = type || 'sine'; o.frequency.setValueAtTime(f, t);
      if (slide) o.frequency.exponentialRampToValueAtTime(slide, t + d);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol || 0.15, t + 0.012); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
      o.connect(g); g.connect(ac.destination); o.start(t); o.stop(t + d + 0.02);
    } catch (e) { /* sin audio */ }
  }
  const SFX = {
    card: () => tone(520, 0.08, 'triangle', 0.12, 780),
    draw: () => tone(300, 0.1, 'triangle', 0.1, 420),
    turn: () => { tone(660, 0.12, 'sine', 0.16); tone(880, 0.18, 'sine', 0.16, null, 0.12); },
    nope: () => { tone(220, 0.16, 'square', 0.12, 150); tone(150, 0.2, 'square', 0.12, 100, 0.14); },
    boom: () => { tone(900, 0.5, 'sawtooth', 0.1, 1800); },
    die: () => { tone(160, 0.7, 'sawtooth', 0.22, 30); tone(90, 0.8, 'square', 0.18, 25, 0.05); },
    zombie: () => { tone(196, 0.2, 'sawtooth', 0.12, 262); tone(262, 0.2, 'sawtooth', 0.12, 330, 0.18); tone(330, 0.3, 'sawtooth', 0.12, 392, 0.36); },
    win: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.22, 'triangle', 0.16, null, i * 0.14)),
    lose: () => [392, 330, 262, 196].forEach((f, i) => tone(f, 0.26, 'triangle', 0.14, null, i * 0.16)),
    shuffle: () => [0, 1, 2, 3, 4].forEach((i) => tone(400 + Math.random() * 500, 0.05, 'triangle', 0.08, null, i * 0.05)),
    attack: () => { tone(700, 0.1, 'sawtooth', 0.12, 200); tone(700, 0.1, 'sawtooth', 0.12, 200, 0.12); },
    tap: () => tone(700, 0.04, 'sine', 0.06),
  };
  const buzz = (ms) => { try { if (Native && Native.vibrate) Native.vibrate(ms); else if (navigator.vibrate) navigator.vibrate(ms); } catch (e) { /* no vibra */ } };

  /* ================= avisos y efectos ================= */
  function toast(text, cls) {
    const el = document.createElement('div');
    el.className = 'toast ' + (cls || '');
    el.textContent = text;
    $('#toasts').appendChild(el);
    setTimeout(() => el.classList.add('out'), 2600);
    setTimeout(() => el.remove(), 3100);
    while ($('#toasts').children.length > 3) $('#toasts').firstChild.remove();
  }
  function bigfx(text, cls) {
    const el = document.createElement('div');
    el.className = 'bigfx ' + (cls || '');
    el.innerHTML = '<span>' + esc(text) + '</span>';
    $('#fx').appendChild(el);
    setTimeout(() => el.remove(), 1700);
  }
  function shake() { document.body.classList.add('shake'); setTimeout(() => document.body.classList.remove('shake'), 600); }

  /* ================= red ================= */
  let room = null, relay = null, ws = null, wsUrl = null, retryT = null, pingT = null, lastMsg = 0, pingAt = 0, left = true;

  function send(m) {
    if (S.mode === 'host') { if (room) room.onMsg('local', m); }
    else if (ws && ws.readyState === 1) ws.send(JSON.stringify(m));
  }
  const act = (a) => send({ t: 'act', a });
  const hello = () => send({ t: 'hello', token: S.token, name: S.name || 'Gatito', avatar: S.avatar });

  function leave() {
    left = true;
    clearTimeout(retryT); clearInterval(pingT);
    if (room) room.stopTimers();
    room = null;
    try { if (relay) { relay.onclose = null; relay.close(); } } catch (e) { /* ya cerrado */ }
    try { if (ws) { ws.onclose = null; ws.close(); } } catch (e) { /* ya cerrado */ }
    relay = ws = null;
    if (Native) { try { Native.stopAdvertise(); Native.stopDiscover(); } catch (e) { /* sin puente */ } }
    Object.assign(S, { mode: null, you: null, isHost: false, lobby: null, view: null, sel: [], seq: 0, log: [], modal: null, conn: 'off', fresh: true, isSolo: false });
  }

  function startHost(bots, solo) {
    leave(); left = false;
    S.mode = 'host'; S.conn = 'on'; S.isSolo = !!solo;
    room = new window.ZKRoom.Room({
      send: (cid, m) => {
        if (cid === 'local') { const copy = JSON.parse(JSON.stringify(m)); Promise.resolve().then(() => onMsg(copy)); }
        else if (relay && relay.readyState === 1) relay.send(JSON.stringify({ to: cid, data: m }));
      },
    });
    hello();
    if (solo) {
      // Un jugador: todo corre en este dispositivo, sin red
      const mix = ['easy', 'normal', 'hard', 'normal'];
      for (let i = 0; i < solo.n; i++) send({ t: 'addBot', level: solo.level === 'mix' ? mix[i % 4] : solo.level });
      send({ t: 'settings', deckMode: solo.deck });
      send({ t: 'start' });
      return;
    }
    for (let i = 0; i < (bots || 0); i++) send({ t: 'addBot' });
    connectRelay();
    if (Native) { try { Native.advertise(S.name || 'Gatito'); } catch (e) { /* sin puente */ } }
    clearInterval(pingT);
    pingT = setInterval(() => { if (relay && relay.readyState === 1) relay.send('{"t":"ping"}'); }, 4000);
  }
  function connectRelay() {
    if (left || S.mode !== 'host') return;
    try { relay = new WebSocket('ws://' + location.host + '/ws?role=host'); } catch (e) { return; }
    const r = relay, myRoom = room;
    r.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (!room || room !== myRoom) return;
      if (m.ev === 'msg') room.onMsg(m.from, m.data);
      else if (m.ev === 'close') room.onClose(m.from);
    };
    r.onclose = () => { if (!left && S.mode === 'host' && relay === r) retryT = setTimeout(connectRelay, 1200); };
  }

  function join(hostport) {
    leave(); left = false;
    S.mode = 'guest'; S.conn = 'connecting'; S.joinHost = hostport;
    wsUrl = 'ws://' + hostport + '/ws';
    S.screen = 'connecting';
    connectWs();
    clearInterval(pingT);
    pingT = setInterval(() => {
      if (!ws) return;
      if (ws.readyState !== 1) return;
      // Solo se da por muerta la conexión si un ping ENVIADO hace rato sigue sin respuesta
      if (pingAt && lastMsg < pingAt && Date.now() - pingAt > 9000) { pingAt = 0; return ws.close(); }
      if (!pingAt || lastMsg >= pingAt) pingAt = Date.now();
      ws.send('{"t":"ping"}');
    }, 4000);
    render();
  }
  function connectWs() {
    if (left || S.mode !== 'guest') return;
    let w;
    try { w = new WebSocket(wsUrl); } catch (e) { toast('Dirección inválida', 'bad'); leave(); S.screen = 'join'; return render(); }
    ws = w;
    w.onopen = () => { lastMsg = Date.now(); pingAt = 0; S.conn = 'on'; hello(); render(); };
    w.onmessage = (ev) => { lastMsg = Date.now(); let m; try { m = JSON.parse(ev.data); } catch (e) { return; } onMsg(m); };
    w.onclose = () => {
      if (left || ws !== w) return;
      S.conn = 'connecting'; render();
      retryT = setTimeout(connectWs, 1500);
    };
  }

  function onMsg(m) {
    switch (m.t) {
      case 'pong': return;
      case 'nohost':
        if (S.screen === 'connecting') { /* el anfitrión aún no crea la sala: seguimos intentando */ }
        return;
      case 'welcome': S.you = m.you; S.isHost = m.host; return;
      case 'lobby':
        S.lobby = m; S.view = null; S.sel = []; S.seq = 0; S.log = []; S.fresh = false;
        if (S.isSolo) return;
        if (S.modal && !S.modal.keep) S.modal = null;
        S.screen = 'lobby';
        return render();
      case 'state': {
        const first = !S.view;
        if (first) { S.sel = []; if (!S.fresh) { S.seq = 0; S.log = []; } }
        S.view = m.view; S.viewAt = performance.now(); S.screen = 'game';
        processEvents(m.view, first && S.fresh);
        S.fresh = false;
        const ids = m.view.hand.map((c) => c.id);
        S.sel = S.sel.filter((id) => ids.indexOf(id) >= 0);
        if (S.giveSel && ids.indexOf(S.giveSel) < 0) S.giveSel = null;
        if (S.modal && (S.modal.type === 'target' || S.modal.type === 'named') && !S.sel.length) S.modal = null;
        return render();
      }
      case 'err': toast(m.msg, 'bad'); return;
      case 'kicked': case 'full': {
        const msg = m.msg || 'El anfitrión te sacó de la sala.';
        leave(); S.screen = 'home'; render(); toast(msg, 'bad'); return;
      }
    }
  }

  function processEvents(v, silent) {
    for (const e of v.events) {
      if (e.seq <= S.seq) continue;
      S.seq = e.seq;
      if (e.text) S.log.push({ text: e.text, priv: !!e.to });
      if (silent) continue;
      const mine = e.player === S.you;
      switch (e.type) {
        case 'start': SFX.shuffle(); break;
        case 'play': SFX.card(); break;
        case 'draw': SFX.draw(); break;
        case 'turn': if (mine && !v.over) { SFX.turn(); buzz(60); toast('¡Tu turno!', 'good'); } break;
        case 'nope': SFX.nope(); bigfx(e.yup ? '¡SIP!' : '¡NOP!', e.yup ? 'green' : 'red'); break;
        case 'attack': SFX.attack(); if (e.target === S.you) { bigfx('¡TE ATACAN! ×' + e.n, 'red'); buzz(200); } break;
        case 'boom': SFX.boom(); bigfx('💣', 'bomb'); break;
        case 'died': SFX.die(); shake(); buzz(400); bigfx(mine ? '¡EXPLOTASTE!' : '¡BOOM!', 'red'); break;
        case 'zombie': SFX.zombie(); bigfx('🧟 ¡ZOMBI!', 'green'); break;
        case 'revived': if (e.target === S.you) { bigfx('¡REVIVISTE!', 'green'); buzz(200); } break;
        case 'shuffle': SFX.shuffle(); break;
        case 'future': S.modal = { type: 'future', cards: e.cards }; break;
        case 'clair': S.modal = { type: 'clair', positions: e.positions, len: e.len }; break;
        case 'got': case 'lost': toast(e.text, e.type === 'lost' ? 'bad' : 'good'); break;
        case 'steal': if (e.target === S.you && e.card) toast(e.text, 'bad'); break;
        case 'over': if (e.winner === S.you) SFX.win(); else SFX.lose(); break;
      }
    }
    if (S.log.length > 120) S.log.splice(0, S.log.length - 120);
  }

  /* ================= helpers de vista ================= */
  const P = (id) => S.view.players.find((p) => p.id === id);
  const pname = (id) => { const p = P(id); return p ? (id === S.you ? 'Tú' : esc(p.name)) : '?'; };
  const remain = (o) => Math.max(0, o.remain - (performance.now() - S.viewAt));
  const timerBar = (o, cls) => {
    const r = remain(o), from = o.total ? Math.min(1, r / o.total) : 1;
    return `<div class="timer ${cls || ''}"><i style="--from:${from.toFixed(3)};animation-duration:${Math.round(r)}ms"></i></div>`;
  };
  const lvlOf = (id) => { const p = S.lobby && S.lobby.players.find((x) => x.id === id); return p ? p.level : null; };
  const sortHand = (h) => h.slice().sort((a, b) => K.ORDER.indexOf(a.type) - K.ORDER.indexOf(b.type) || (a.id < b.id ? -1 : 1));
  const btn = (label, a, cls, extra) => `<button class="btn ${cls || ''}" data-act="${a}" ${extra || ''}>${label}</button>`;

  function comboState() {
    const v = S.view, sel = S.sel.map((id) => v.hand.find((c) => c.id === id)).filter(Boolean);
    if (sel.length < 2) return null;
    if (sel.length > 3) return { err: 'Máximo 3 cartas por jugada.' };
    const real = sel.filter((c) => c.type !== 'clone');
    if (!real.length) return { err: 'El Clon necesita acompañar a otra carta.' };
    if (real.some((c) => c.type !== real[0].type)) return { err: 'Para un combo, las cartas deben ser iguales.' };
    const me = P(S.you);
    if (v.cur !== S.you || !me.alive) return { err: 'Los combos solo se juegan en tu turno.' };
    if (v.prompt || v.stack.length) return { err: 'Espera a que termine la jugada en curso.' };
    if (!v.players.some((p) => p.id !== S.you && p.alive && p.count)) return { err: 'Nadie tiene cartas para robar.' };
    return { n: sel.length, of: real[0].type };
  }

  /* ================= pantallas ================= */
  const screens = {};

  function profileHTML() {
    return `<div class="profile">
      <button class="avatar big" data-act="avatar" aria-label="Cambiar gato">${K.avatar(S.avatar)}<i>↻</i></button>
      <label><span>Tu nombre</span><input id="name" maxlength="14" placeholder="Gatito" value="${esc(S.name)}" autocomplete="off"></label></div>`;
  }
  screens.home = () => {
    const host = S.info.local;
    return `<div class="screen home"><div class="home-art">${K.logo()}<p class="tag">Explota. Revive. Vuelve a explotar.</p></div>
      ${profileHTML()}
      <div class="menu">
        ${S.info.static ? btn('🤖 Jugar contra la IA', 'solo', 'primary xl') : ''}
        ${!S.info.static && host ? btn('🏠 Crear partida', 'create', 'primary') : ''}
        ${S.info.static ? '' : host ? btn('📡 Unirse a una partida', 'goJoin', 'green') : btn('📡 Unirse a esta partida', 'joinHere', 'primary')}
        ${S.info.static ? '' : btn('🤖 Un jugador contra la IA', 'solo')}
        <div class="row">${btn('📖 Cómo jugar', 'rules')}${btn('🃏 Cartas', 'cards')}</div>
      </div>
      <p class="fine">Juego hecho por fans para uso personal. Zombie Kittens es una marca de Exploding Kittens, Inc. · Arte original</p></div>`;
  };
  screens.solo = () => {
    const o = S.solo, deckInfo = o.deck === 'full' ? 'Todas las cartas (57) + explosivos.' : o.n === 1 ? 'Oficial para 2: las 24 cartas con huella 🐾 y 1 explosivo.' : o.n === 2 ? 'Oficial para 3: las 33 cartas sin huella y 2 explosivos.' : 'Oficial: todas las cartas y ' + o.n + ' explosivos.';
    return `<div class="screen pad"><header class="bar"><button class="ic" data-act="home">‹</button><h2>Un jugador</h2></header>
      ${profileHTML()}
      <h3>Rivales controlados por la IA</h3>
      <div class="seg">${[1, 2, 3, 4].map((k) => `<button class="${o.n === k ? 'on' : ''}" data-act="soloN" data-n="${k}"><b>${k}</b><span>${k === 1 ? 'rival' : 'rivales'}</span></button>`).join('')}</div>
      <h3>Dificultad</h3>
      <div class="levels">${Object.keys(LEVELS).map((k) => `<button class="${o.level === k ? 'on' : ''}" data-act="soloLevel" data-l="${k}"><i>${LEVELS[k][0]}</i><div><b>${LEVELS[k][1]}</b><span>${LEVELS[k][2]}</span></div></button>`).join('')}</div>
      <div class="row">${btn(o.deck === 'full' ? '🃏 Mazo: completo' : '🃏 Mazo: oficial', 'soloDeck')}</div>
      <p class="dim small">${deckInfo}</p>
      <div class="grow"></div>
      ${btn('¡Jugar!', 'soloStart', 'primary xl')}</div>`;
  };
  screens.connecting = () => `<div class="screen center"><div class="spinner"></div><h2>Conectando…</h2><p class="dim">${esc(S.joinHost)}</p>
    <p class="dim">Asegúrate de estar en la misma red Wi-Fi que el anfitrión y de que ya creó la partida.</p>${btn('Cancelar', 'home')}</div>`;
  screens.join = () => {
    const pre = S.info.ip ? S.info.ip.split('.').slice(0, 3).join('.') + '.' : '';
    return `<div class="screen pad"><header class="bar"><button class="ic" data-act="home">‹</button><h2>Unirse a una partida</h2></header>
      ${Native ? `<h3>Partidas en tu red</h3><div class="found">${S.found.length ? S.found.map((f, i) => `<button class="found-item" data-act="joinFound" data-i="${i}"><b>🐾 Sala de ${esc(f.name)}</b><span>${esc(f.host)}:${f.port}</span></button>`).join('') : '<div class="searching"><div class="spinner sm"></div> Buscando partidas en la red Wi-Fi…</div>'}</div>` : ''}
      <h3>Conectar por dirección</h3>
      <p class="dim">Escribe la dirección que aparece en la pantalla del anfitrión.</p>
      <div class="iprow"><input id="ip" inputmode="decimal" placeholder="192.168.1.20" value="${esc(S.manualIp != null ? S.manualIp : pre)}" autocomplete="off">${btn('Conectar', 'joinIp', 'primary')}</div>
      <div class="tips"><b>¿No aparece la partida?</b><ul><li>Todos deben estar en la <b>misma red Wi-Fi</b> (o conectados a la zona Wi-Fi de un teléfono).</li><li>El anfitrión debe tocar <b>Crear partida</b> primero.</li><li>Algunas redes públicas bloquean la conexión entre dispositivos: usen la zona Wi-Fi de un teléfono.</li></ul></div></div>`;
  };

  screens.lobby = () => {
    const L = S.lobby, n = L.players.length, url = S.info.ip ? 'http://' + S.info.ip + ':' + S.info.port : '';
    const deckInfo = L.settings.deckMode === 'full' ? 'Se usan las 57 cartas + explosivos.' :
      n <= 2 ? '2 jugadores: solo las 24 cartas con huella 🐾 + 1 explosivo.' : n === 3 ? '3 jugadores: las 33 cartas sin huella + 2 explosivos.' : n + ' jugadores: todas las cartas + ' + (n - 1) + ' explosivos.';
    const hostP = L.players.find((p) => p.host);
    return `<div class="screen pad lobby"><header class="bar"><button class="ic" data-act="leave">‹</button><h2>Sala de ${esc(hostP ? hostP.name : '')}</h2><span class="pill">${n}/5</span></header>
      ${S.isHost ? `<div class="panel connect">${url ? `<img class="qr" src="/qr?t=${encodeURIComponent(url)}" alt="QR"><div><b>¿Cómo se unen?</b><p>📱 Con la app: <b>Unirse a una partida</b> (misma Wi-Fi).</p><p>🌐 Sin app (iPhone, etc.): escanea el QR o abre</p><code>${esc(url)}</code></div>` : '<div><b>Sin red local</b><p>Conéctate a una red Wi-Fi o activa la zona Wi-Fi de tu teléfono para que otros se unan. Mientras tanto puedes jugar contra bots.</p></div>'}</div>` : ''}
      <div class="players">${L.players.map((p) => `<div class="prow"><span class="avatar">${K.avatar(p.avatar)}</span><b>${esc(p.name)}</b>${p.host ? '<span class="pill gold">Anfitrión</span>' : ''}${p.bot ? (S.isHost ? `<button class="pill lvl" data-act="botLevel" data-id="${p.id}">${LEVELS[p.level][0]} ${LEVELS[p.level][1]} ▾</button>` : `<span class="pill">${LEVELS[p.level][0]} ${LEVELS[p.level][1]}</span>`) : ''}${p.id === S.you ? '<span class="pill green">Tú</span>' : ''}${S.isHost && !p.host ? `<button class="ic sm" data-act="kick" data-id="${p.id}">✕</button>` : ''}</div>`).join('')}
        ${Array.from({ length: 5 - n }, () => '<div class="prow empty"><span class="avatar ghost"></span><i>Esperando jugador…</i></div>').join('')}</div>
      ${S.isHost ? `<div class="row">${btn('🤖 Añadir bot', 'addBot', '', n >= 5 ? 'disabled' : '')}${btn(L.settings.deckMode === 'full' ? '🃏 Mazo: completo' : '🃏 Mazo: oficial', 'deckMode')}</div>` : ''}
      <p class="dim small">${deckInfo}</p>
      <div class="row">${btn('📖 Reglas', 'rules')}${btn('🃏 Cartas', 'cards')}</div>
      <div class="grow"></div>
      ${S.isHost ? btn(n < 2 ? 'Faltan jugadores' : '¡Empezar partida!', 'start', 'primary xl', n < 2 ? 'disabled' : '') : '<div class="waiting"><div class="spinner sm"></div> Esperando a que el anfitrión empiece…</div>'}</div>`;
  };

  function stageHTML(v) {
    const me = P(S.you), t = v.stack[v.stack.length - 1], pr = v.prompt;
    if (v.win && t) {
      const c = t.eff === 'combo2' || t.eff === 'combo3' ? C[t.of] : C[t.eff];
      let what;
      if (t.eff === 'combo2') what = `pareja de <b>${c.name}</b> → roba a ${pname(t.target)}`;
      else if (t.eff === 'combo3') what = `trío de <b>${c.name}</b> → pide <b>${C[t.named].name}</b> a ${pname(t.target)}`;
      else what = `<b>${c.icon} ${c.name}</b>` + (t.target ? ' → ' + pname(t.target) : '');
      const st = t.nopes ? (t.nopes % 2 ? `<span class="tagx red">ANULADA por ${pname(t.last)}</span>` : `<span class="tagx green">¡VUELVE A VALER!</span>`) : '';
      const can = v.win.canNope && !v.win.passed;
      return `<div class="stage window" data-k="w${t.id}-${t.nopes}"><div class="st-txt">${pname(t.by)} juega ${what} ${st}</div>${timerBar(v.win)}
        ${can ? `<div class="row">${btn('🚫 ¡NOP!', 'nope', 'danger')}${btn('Dejar pasar', 'pass')}</div>` : `<div class="dim small">${v.win.total > 2000 ? 'Alguien podría decir Nop…' : ''}</div>`}</div>`;
    }
    if (pr) {
      let txt = '';
      if (pr.type === 'explode') txt = `💣 <b>${pname(pr.player)}</b> ${pr.mine ? 'sacaste' : 'sacó'} un Gatito Explosivo…`;
      else if (pr.type === 'zombie') {
        const cl = v.hand.find((c) => c.type === 'clairvoyance' && v.playable[c.id]);
        txt = `🧟 <b>${pname(pr.player)}</b> ${pr.mine ? 'escondes' : 'esconde'} ${pr.eks > 1 ? 'los Gatitos Explosivos' : 'el Gatito Explosivo'} en el mazo…` +
          (pr.watching ? '<br><span class="tagx green">👁️ Estás mirando</span>' : cl ? `<div class="row">${btn('👁️ Jugar Clarividencia', 'playOne', 'primary', `data-id="${cl.id}"`)}</div>` : '');
      } else if (pr.type === 'give') {
        const who = pr.waiting.map(pname).join(', ');
        txt = (pr.reason === 'favor' ? '🙏 Favor' : pr.reason === 'feed' ? '🍖 Alimenta a los Muertos' : '⚰️ Ladrón de Tumbas') + `: esperando carta de <b>${who}</b>…`;
      } else if (pr.type === 'dig') txt = `⛏️ <b>${pname(pr.player)}</b> ${pr.mine ? 'cavas' : 'cava'} más hondo…`;
      return `<div class="stage"><div class="st-txt">${txt}</div>${timerBar(pr, 'thin')}</div>`;
    }
    const last = S.log[S.log.length - 1];
    const myTurn = v.cur === S.you && me.alive;
    return `<div class="stage quiet"><div class="st-txt">${myTurn ? '<b>Juega cartas si quieres… y luego roba para terminar tu turno.</b>' : last ? esc(last.text) : ''}</div></div>`;
  }

  function selInfoHTML(v) {
    if (!S.sel.length) return '';
    const cards = S.sel.map((id) => v.hand.find((c) => c.id === id)).filter(Boolean);
    if (!cards.length) return '';
    let title, desc, action = '';
    if (cards.length === 1) {
      const c = C[cards[0].type], can = v.playable[cards[0].id];
      title = c.icon + ' ' + c.name; desc = c.short;
      if (can) action = btn('Jugar', 'play', 'primary');
      else {
        const me = P(S.you);
        const why = c.cat ? 'Selecciona otra igual para jugar una pareja.' : cards[0].type === 'zombie' ? 'Se usa sola cuando sacas un Gatito Explosivo.' :
          cards[0].type === 'nope' ? 'Úsala cuando alguien juegue una carta.' : cards[0].type === 'clairvoyance' ? 'Úsala cuando otro juegue un Gatito Zombi.' :
          !me.alive ? 'Estás muerto: solo Nop y cartas ⚡.' : v.cur !== S.you ? 'Espera tu turno.' : (cards[0].type === 'attack_dead' || cards[0].type === 'grave_robber' || cards[0].type === 'feed_dead') && !v.deadN ? 'Necesita que haya jugadores muertos.' : 'No se puede jugar ahora.';
        action = `<span class="why">${why}</span>`;
      }
    } else {
      const cs = comboState();
      title = cards.map((c) => C[c.type].icon).join(' ') + ' ' + (cards.length === 2 ? 'Pareja' : cards.length === 3 ? 'Trío' : 'Selección');
      if (cs && !cs.err) { desc = cs.n === 2 ? 'Roba una carta AL AZAR a un jugador vivo.' : 'Nombra la carta que quieres: si la tiene, te la da.'; action = btn(cs.n === 2 ? 'Jugar pareja' : 'Jugar trío', 'play', 'primary'); }
      else { desc = cs ? cs.err : ''; action = ''; }
    }
    return `<div class="selinfo" data-k="s${S.sel.join('-')}"><div class="si-txt"><b>${title}</b><span>${desc}</span></div><div class="si-act">${action}<button class="ic sm" data-act="zoomSel">ℹ️</button><button class="ic sm" data-act="clearSel">✕</button></div></div>`;
  }

  screens.game = () => {
    const v = S.view, me = P(S.you), n = v.players.length, myIdx = v.players.findIndex((p) => p.id === S.you);
    const opps = []; for (let k = 1; k < n; k++) opps.push(v.players[(myIdx + k) % n]);
    const myTurn = v.cur === S.you && me.alive, idle = !v.prompt && !v.stack.length && !v.over;
    const eks = v.players.filter((p) => p.alive).length - 1, risk = v.draw ? Math.round(100 * eks / v.draw) : 0;
    const hand = sortHand(v.hand);
    const W = Math.min(window.innerWidth, 560), cw = window.innerHeight >= 780 ? 116 : 104;
    const step = hand.length > 1 ? Math.min(cw + 6, Math.max(56, (W - 24 - cw) / (hand.length - 1))) : cw;
    const cnt = {}; for (const c of hand) cnt[c.type] = (cnt[c.type] || 0) + 1;
    const comboOk = myTurn && idle && v.players.some((p) => p.id !== S.you && p.alive && p.count);
    const can = (c) => v.playable[c.id] || (comboOk && (cnt[c.type] >= 2 || (cnt.clone && hand.length > 1)));
    const cur = P(v.cur);
    return `<div class="game ${myTurn ? 'myturn' : ''} ${me.alive ? '' : 'dead'}">
      <header class="topbar"><button class="ic" data-act="menu">☰</button>
        <div class="turn ${myTurn ? 'me' : ''}">${myTurn ? 'TU TURNO' : 'Turno de ' + esc(cur.name)}${v.turnsLeft > 1 ? ` <em>×${v.turnsLeft}</em>` : ''}</div>
        <button class="ic" data-act="log">📜</button></header>
      ${S.conn !== 'on' ? '<div class="reconn">Reconectando con el anfitrión…</div>' : ''}
      <div class="opps n${opps.length}">${opps.map((p) => `<div class="opp ${p.id === v.cur ? 'cur' : ''} ${p.alive ? '' : 'dead'} ${p.connected || p.bot ? '' : 'off'}">
        <span class="avatar">${K.avatar(p.avatar, !p.alive)}</span>
        <b>${p.bot && lvlOf(p.id) ? LEVELS[lvlOf(p.id)][0] + ' ' : ''}${esc(p.name)}</b>
        <span class="cnt">${p.alive ? '' : '💀 '}🂠 ${p.count}</span>${p.id === v.cur && v.turnsLeft > 1 ? `<em class="tl">×${v.turnsLeft}</em>` : ''}${!p.connected && !p.bot ? '<em class="offb">sin conexión</em>' : ''}</div>`).join('')}</div>
      <div class="table">
        <button class="pile draw ${myTurn && idle ? 'hot' : ''}" data-act="draw"><div class="stackb">${K.backHTML('b3')}${K.backHTML('b2')}${K.backHTML('b1')}</div><span class="badge">${v.draw}</span><label>${myTurn && idle ? 'TOCA PARA ROBAR' : 'Mazo'}</label></button>
        <div class="pile discard" data-act="zoomDiscard">${v.discard.length ? v.discard.slice(-3).map((d, i, a) => K.cardHTML(d.type, { cls: 'mini d' + (a.length - 1 - i), attr: `data-k="d${d.id}"` })).join('') : '<div class="slot">Descarte</div>'}<label>Descarte</label></div>
      </div>
      <div class="risk" title="Explosivos en el mazo">💣 ${eks} en ${v.draw} cartas · <b>${risk}%</b></div>
      ${stageHTML(v)}
      <div class="grow"></div>
      <div class="mebar"><span class="avatar">${K.avatar(me.avatar, !me.alive)}</span><div class="me-txt"><b>${esc(me.name)}</b><span>${me.alive ? (myTurn ? 'Te toca' + (v.turnsLeft > 1 ? ` · ${v.turnsLeft} turnos` : '') : 'Vivo') : '💀 Muerto — aún puedes jugar Nop y cartas ⚡'}</span></div>
        ${myTurn && idle ? btn('Robar carta', 'draw', 'primary') : ''}</div>
      ${selInfoHTML(v)}
      <div class="hand" style="--step:${step.toFixed(1)}px">${hand.map((c) => K.cardHTML(c.type, { cls: 'h' + (S.sel.indexOf(c.id) >= 0 ? ' sel' : '') + (can(c) ? ' can' : ''), attr: `data-act="sel" data-id="${c.id}"`, paw: c.paw })).join('') || '<div class="nohand">Sin cartas en la mano</div>'}</div>
    </div>`;
  };

  /* ================= modales ================= */
  function sheet(title, body, o) {
    o = o || {};
    return `<div class="overlay ${o.cls || ''}" data-k="m${esc(title)}" ${o.close === false ? '' : 'data-act="closeModal"'}><div class="sheet ${o.sheetCls || ''}" data-stop="1">
      ${title ? `<header><h3>${title}</h3>${o.close === false ? '' : '<button class="ic sm" data-act="closeModal">✕</button>'}</header>` : ''}<div class="sheet-body">${body}</div></div></div>`;
  }
  const insLabel = (pos, max) => pos <= 0 ? 'Arriba del todo: será la PRÓXIMA carta' : pos >= max ? 'Hasta el fondo del mazo' : `Debajo de ${pos} carta${pos > 1 ? 's' : ''} (posición ${pos + 1} de ${max + 1})`;

  function promptModal(v) {
    const pr = v.prompt;
    if (!pr || !pr.mine || v.over) return '';
    if (pr.type === 'explode') {
      const z = v.hand.find((c) => c.type === 'zombie'), cl = v.hand.find((c) => c.type === 'clone' && v.playable[c.id]);
      return `<div class="overlay boom" data-k="boom"><div class="boombox"><h1>¡GATITO EXPLOSIVO!</h1>${K.cardHTML('exploding', { cls: 'xl' })}${timerBar(pr)}
        ${z ? btn('🧟 Jugar Gatito Zombi', 'playOne', 'green xl', `data-id="${z.id}"`) : ''}
        ${cl ? btn('👯 Jugar Clon (copia al Zombi)', 'playOne', 'green', `data-id="${cl.id}"`) : ''}
        ${btn('💀 Morir (conservas tus cartas)', 'die', 'ghost')}
        <p class="dim small">Si mueres, otro jugador puede revivirte con su Gatito Zombi.</p></div></div>`;
    }
    if (pr.type === 'zombie') {
      if (pr.needRevive && !pr.revived) {
        return sheet('🧟 ¿A quién revives?', `<p>Debes traer de vuelta a un jugador muerto. Elige con cuidado: ¡solo ganará si te sobrevive!</p>
          <div class="plist">${v.players.filter((p) => !p.alive).map((p) => `<button class="pbtn" data-act="revive" data-id="${p.id}"><span class="avatar">${K.avatar(p.avatar, true)}</span><b>${esc(p.name)}</b><span>${p.count} cartas</span></button>`).join('')}</div>${timerBar(pr, 'thin')}`, { close: false });
      }
      if (pr.waiting) return sheet('Escondiendo…', '<div class="center"><div class="spinner"></div><p>Colocando los explosivos en el mazo…</p></div>', { close: false });
      let body = `<p>Coloca ${pr.eks > 1 ? 'cada explosivo' : 'el explosivo'} en secreto donde quieras. Nadie verá dónde (salvo con Clarividencia).</p>`;
      for (let i = 0; i < pr.eks; i++) {
        const max = v.draw + i; if (S.ins[i] > max) S.ins[i] = max;
        body += `<div class="ins"><b>💣 Explosivo ${pr.eks > 1 ? i + 1 : ''} ${pr.eks > 1 && i === 1 ? '(el del jugador revivido)' : ''}</b>
          <div class="ins-row"><span>Arriba</span><input type="range" min="0" max="${max}" value="${S.ins[i]}" data-ins="${i}"><span>Fondo</span></div>
          <div class="ins-lbl" id="insl${i}">${insLabel(S.ins[i], max)}</div>
          <div class="row tight">${btn('Arriba', 'insSet', 'sm', `data-i="${i}" data-v="0"`)}${btn('2ª', 'insSet', 'sm', `data-i="${i}" data-v="1"`)}${btn('Al azar', 'insSet', 'sm', `data-i="${i}" data-v="r"`)}${btn('Fondo', 'insSet', 'sm', `data-i="${i}" data-v="${max}"`)}</div></div>`;
      }
      return sheet('🧟 Esconde el Gatito Explosivo', body + timerBar(pr, 'thin') + btn('Confirmar', 'insert', 'primary xl'), { close: false });
    }
    if (pr.type === 'give') {
      const title = pr.reason === 'favor' ? `🙏 ${pname(pr.to)} te pide un Favor` : pr.reason === 'feed' ? `🍖 Alimenta a ${pname(pr.to)}` : '⚰️ Ladrón de Tumbas';
      const txt = pr.reason === 'rob' ? 'Elige 1 carta de tu mano: se barajará dentro del mazo.' : 'Elige 1 carta de tu mano para dársela.';
      return sheet(title, `<p>${txt}</p><div class="grid">${sortHand(v.hand).map((c) => K.cardHTML(c.type, { cls: 'g' + (S.giveSel === c.id ? ' sel' : ''), attr: `data-act="giveSel" data-id="${c.id}"` })).join('')}</div>${timerBar(pr, 'thin')}
        ${btn('Dar esta carta', 'give', 'primary xl', S.giveSel ? '' : 'disabled')}`, { close: false });
    }
    if (pr.type === 'dig') {
      return sheet('⛏️ Cava Más Hondo', `<p>Esta es la carta de arriba. ¿Te la quedas? Si no, DEBES robar la siguiente sea cual sea.</p><div class="center">${K.cardHTML(pr.card, { cls: 'xl' })}</div>${timerBar(pr, 'thin')}
        <div class="row">${btn('Me la quedo', 'digKeep', 'primary')}${btn('Robar la siguiente', 'digNext', 'danger')}</div>`, { close: false });
    }
    return '';
  }

  const RULES = `
    <h4>🎯 Objetivo</h4><p>En el mazo hay <b>Gatitos Explosivos</b>. Por turnos se roban cartas hasta que alguien saca uno y explota. Gana <b>el último jugador con vida</b>. Pero aquí la muerte no es el final: ¡puedes volver como zombi!</p>
    <h4>🧰 Preparación (automática)</h4><ul><li><b>2 jugadores:</b> solo las 24 cartas con huella 🐾.</li><li><b>3 jugadores:</b> solo las 33 cartas sin huella.</li><li><b>4 o 5 jugadores:</b> todas las cartas.</li><li>Cada jugador recibe <b>1 Gatito Zombi + 7 cartas</b> (8 en total). Los Zombis que sobren se barajan en el mazo.</li><li>Se mezclan en el mazo tantos Gatitos Explosivos como <b>jugadores menos uno</b>.</li></ul>
    <h4>🔁 Tu turno</h4><ol><li><b>Juega</b> todas las cartas que quieras (o ninguna). Toca una carta para seleccionarla y luego <b>Jugar</b>.</li><li><b>Roba</b> una carta del mazo para terminar tu turno… y reza para que no sea un Gatito Explosivo.</li></ol><p>El turno pasa al siguiente jugador vivo. No hay límite de cartas en la mano.</p>
    <h4>💥 Explotar y morir</h4><p>Si sacas un Gatito Explosivo y no juegas un Gatito Zombi (puedes tenerlo y decidir no usarlo), quedas <b>Muerto</b>. El explosivo se queda frente a ti y <b>conservas tu mano</b>. Puedes morir todas las veces que haga falta.</p>
    <h4>💀 Estar muerto</h4><ul><li>No juegas turnos ni robas.</li><li>Sí puedes jugar <b>Nop</b> y las cartas con <b>⚡ (YA)</b> en cualquier momento: Barajar, Alimenta a los Muertos y Clarividencia.</li><li>Nadie puede robarte cartas ni pedirte Favor (solo las cartas que lo dicen expresamente te afectan).</li></ul>
    <h4>🧟 Gatito Zombi y revivir</h4><p>Al sacar un explosivo puedes jugar tu Gatito Zombi en lugar de morir. Si hay muertos, <b>debes revivir a uno</b>. Después escondes en secreto tu explosivo (y el del jugador revivido) en cualquier lugar del mazo, cada uno donde quieras. El revivido vuelve a jugar con la mano que tenía.</p>
    <h4>🚫 Nop</h4><p>Cuando alguien juega una carta se abre una breve ventana: cualquiera (vivo o muerto) puede decir <b>¡NOP!</b> para anularla. Otro Nop anula al Nop anterior. Lo único que no se puede anular es un Gatito Explosivo o un Gatito Zombi.</p>
    <h4>✨ Combos especiales</h4><ul><li><b>Dos iguales:</b> juega 2 cartas con el mismo título (no solo gatos) para robar una carta <b>al azar</b> a un jugador vivo.</li><li><b>Tres iguales:</b> igual, pero <b>nombras la carta</b> que quieres; si la tiene, te la da.</li><li>El <b>Clon</b> puede completar cualquier pareja o trío.</li></ul><p>En un combo se ignora el texto de las cartas.</p>
    <h4>👥 Partidas de 2 jugadores</h4><p>Hay un solo explosivo, así que el primero que muera pierde: el Gatito Zombi funciona como tu única vida extra. Guarda tus Saltar y Ataque para cuando el mazo esté casi vacío, y usa Ver el Futuro o Cava Más Hondo para saber dónde está el explosivo. Cuando escondas el explosivo, ponerlo arriba obliga a tu rival a enfrentarlo de inmediato.</p>
    <h4>👨‍👩‍👧‍👦 Partidas de 3 a 5 jugadores</h4><p>Aquí entra el caos zombi: al revivir a alguien, <b>dos</b> explosivos vuelven al mazo. El <b>Ataque de los Muertos</b> se vuelve brutal con varios muertos (3 turnos por cada uno) y los muertos pueden seguir influyendo con Nop, Barajar y Alimenta a los Muertos.</p>
    <h4>💡 Consejos</h4><ul><li>Al inicio el riesgo es bajo: guarda tus cartas.</li><li>Fíjate en el indicador 💣: muestra la probabilidad de explotar al robar.</li><li>Consigue todos los Gatitos Zombi que puedas (¡con un trío puedes pedirlo por nombre!).</li></ul>
    <h4>📡 Jugar en red local</h4><ul><li>Un jugador toca <b>Crear partida</b>: su teléfono es el anfitrión.</li><li>Los demás, en la misma Wi-Fi, tocan <b>Unirse a una partida</b>. También pueden entrar sin instalar nada escaneando el QR desde el navegador (sirve para iPhone).</li><li>Sin Wi-Fi: el anfitrión activa su <b>zona Wi-Fi</b> y los demás se conectan a ella. No se necesita internet.</li><li>Si alguien pierde la conexión, puede volver a entrar y recupera su mano.</li></ul>`;

  function cardsGuide() {
    return K.ORDER.map((t) => `<div class="guide">${K.cardHTML(t, { cls: 'gd' })}<div><b>${C[t].icon} ${C[t].name}</b><i>${C[t].kind} · ${K.COUNTS[t]} cartas</i><p>${C[t].long}</p></div></div>`).join('') +
      '<p class="dim small">🐾 = copias con huella (las que se usan con 2 jugadores) + copias sin huella (las de 3 jugadores). Con 4-5 jugadores se usan todas.</p>';
  }

  function modalHTML() {
    const v = S.view, m = S.modal;
    let out = '';
    if (S.screen === 'game' && v) {
      out += promptModal(v);
      if (v.over) {
        const w = P(v.over.winner), iWon = v.over.winner === S.you;
        out += `<div class="overlay over ${iWon ? 'won' : ''}" data-k="over"><div class="overbox">${iWon ? '<div class="confetti">' + Array.from({ length: 24 }, (_, i) => `<i style="--x:${(i * 37) % 100}%;--d:${(i % 7) * 0.25}s;--c:${['#b6f23a', '#ffe14a', '#ff7fb0', '#49e0e6'][i % 4]}"></i>`).join('') + '</div>' : ''}
          <span class="avatar huge">${K.avatar(w ? w.avatar : 0)}</span><h1>${iWon ? '¡GANASTE!' : 'Ganó ' + esc(w ? w.name : '')}</h1><p>${iWon ? 'Eres el último gatito con vida. 🏆' : 'Fue el último gatito con vida.'}</p>
          ${S.isSolo ? btn('Jugar otra vez', 'again', 'primary xl') + btn('Cambiar rivales o dificultad', 'solo') : S.isHost ? btn('Volver a la sala (revancha)', 'toLobby', 'primary xl') : '<p class="dim">Esperando a que el anfitrión abra la sala…</p>'}${btn('Salir', 'leave', 'ghost')}</div></div>`;
      }
    }
    if (!m) return out;
    if (m.type === 'target') {
      const list = v.players.filter((p) => m.kind === 'dead' ? !p.alive : (p.alive && p.id !== S.you && p.count > 0));
      out += sheet(m.kind === 'dead' ? '¿A qué muerto alimentas?' : '¿Contra quién?', `<div class="plist">${list.map((p) => `<button class="pbtn" data-act="pickTarget" data-id="${p.id}"><span class="avatar">${K.avatar(p.avatar, !p.alive)}</span><b>${p.id === S.you ? 'Yo mismo' : esc(p.name)}</b><span>${p.count} cartas</span></button>`).join('')}</div>`);
    } else if (m.type === 'named') {
      out += sheet('¿Qué carta quieres?', `<p>Si ${pname(m.target)} la tiene, te la da.</p><div class="named">${K.ORDER.filter((t) => t !== 'exploding').map((t) => `<button data-act="pickNamed" data-t="${t}" style="--cc:${C[t].color}"><span>${C[t].icon}</span>${C[t].name}</button>`).join('')}</div>`);
    } else if (m.type === 'future') {
      out += sheet('🔮 El futuro (solo tú lo ves)', `<div class="future">${m.cards.map((t, i) => `<div><em>${i === 0 ? 'PRÓXIMA' : (i + 1) + 'ª'}</em>${K.cardHTML(t, { cls: 'f' })}</div>`).join('')}</div><p class="dim small">Las cartas siguen en el mismo orden en el mazo.</p>${btn('Entendido', 'closeModal', 'primary')}`);
    } else if (m.type === 'clair') {
      out += sheet('👁️ Clarividencia', `<p>Viste dónde quedaron los explosivos (mazo de ${m.len} cartas):</p><ul class="clair">${m.positions.map((p, i) => `<li>💣 Explosivo ${m.positions.length > 1 ? i + 1 : ''}: <b>${p === 0 ? 'arriba del todo' : 'debajo de ' + p + ' carta' + (p > 1 ? 's' : '')}</b>${m.positions.length > 1 && i === 0 ? ' <i>(antes de colocar el segundo)</i>' : ''}</li>`).join('')}</ul>${btn('Entendido', 'closeModal', 'primary')}`);
    } else if (m.type === 'menu') {
      out += sheet('Menú', `<div class="menu">${btn('📖 Cómo jugar', 'rules')}${btn('🃏 Guía de cartas', 'cards')}${btn(S.sound ? '🔊 Sonido: sí' : '🔇 Sonido: no', 'sound')}${btn('🚪 Salir de la partida', 'leaveAsk', 'danger')}</div>`);
    } else if (m.type === 'confirmLeave') {
      out += sheet('¿Salir de la partida?', `<p>${S.isSolo ? 'Se perderá la partida en curso.' : S.isHost ? 'Eres el anfitrión: si sales, la partida termina para todos.' : 'Podrás volver a entrar mientras la partida siga.'}</p><div class="row">${btn('Seguir jugando', 'closeModal')}${btn('Salir', 'leave', 'danger')}</div>`);
    } else if (m.type === 'log') {
      out += sheet('📜 Historial', `<div class="log">${S.log.slice().reverse().map((l) => `<p class="${l.priv ? 'priv' : ''}">${esc(l.text)}</p>`).join('') || '<p class="dim">Aún no pasa nada.</p>'}</div>`);
    } else if (m.type === 'rules') {
      out += sheet('📖 Cómo jugar', `<div class="rules">${RULES}</div>`, { sheetCls: 'tall' });
    } else if (m.type === 'cards') {
      out += sheet('🃏 Guía de cartas', cardsGuide(), { sheetCls: 'tall' });
    } else if (m.type === 'zoom') {
      const c = C[m.card];
      out += sheet('', `<div class="center">${K.cardHTML(m.card, { cls: 'xl' })}</div><h3>${c.icon} ${c.name}</h3><i class="dim">${c.kind}</i><p>${c.long}</p>`, { cls: 'zoom' });
    }
    return out;
  }

  let rendering = false;
  function render() {
    if (rendering) return;
    rendering = true;
    const app = $('#app');
    const hand = app.querySelector('.hand'), sl = hand ? hand.scrollLeft : 0;
    const sb = app.querySelector('.sheet-body'), st = sb ? sb.scrollTop : 0, sheetKey = S.modal ? S.modal.type : (S.view && S.view.prompt ? 'p' + S.view.prompt.type : '');
    const focusId = document.activeElement && document.activeElement.id;
    app.innerHTML = (screens[S.screen] || screens.home)() + modalHTML();
    const h2 = app.querySelector('.hand'); if (h2) h2.scrollLeft = sl;
    const sb2 = app.querySelector('.sheet-body'); if (sb2 && render.lastKey === sheetKey) sb2.scrollTop = st;
    render.lastKey = sheetKey;
    const keys = {};
    app.querySelectorAll('[data-k]').forEach((el) => { keys[el.dataset.k] = 1; if (render.keys && render.keys[el.dataset.k]) el.classList.add('na'); });
    render.keys = keys;
    if (focusId) { const f = document.getElementById(focusId); if (f) { f.focus(); try { f.setSelectionRange(f.value.length, f.value.length); } catch (e) { /* no aplica */ } } }
    rendering = false;
  }

  /* ================= acciones ================= */
  function playSelected(target, named) {
    const v = S.view;
    if (!S.sel.length) return;
    if (S.sel.length === 1) {
      const need = v.playable[S.sel[0]];
      if (!need) return;
      if ((need === 'dead' || need === 'living') && !target) { S.modal = { type: 'target', kind: need }; return render(); }
    } else {
      const cs = comboState();
      if (!cs || cs.err) return;
      if (!target) { S.modal = { type: 'target', kind: 'living' }; return render(); }
      if (cs.n === 3 && !named) { S.modal = { type: 'named', target }; return render(); }
    }
    act({ a: 'play', cards: S.sel.slice(), target: target || undefined, named: named || undefined });
    S.sel = []; S.modal = null;
    render();
  }

  const A = {
    home() { leave(); S.screen = 'home'; },
    avatar() { S.avatar = (S.avatar + 1) % 8; store.set('avatar', S.avatar); },
    create() { saveName(); startHost(0); },
    solo() { saveName(); leave(); S.screen = 'solo'; },
    soloN(d) { S.solo.n = Number(d.n); store.set('solo', S.solo); },
    soloLevel(d) { S.solo.level = d.l; store.set('solo', S.solo); },
    soloDeck() { S.solo.deck = S.solo.deck === 'full' ? 'official' : 'full'; store.set('solo', S.solo); },
    soloStart() { saveName(); startHost(0, S.solo); return false; },
    again() { S.view = null; send({ t: 'toLobby' }); send({ t: 'start' }); return false; },
    botLevel(d) { send({ t: 'botLevel', id: d.id }); },
    goJoin() { saveName(); S.screen = 'join'; S.found = []; if (Native) { try { Native.discover(); } catch (e) { /* sin puente */ } } },
    joinHere() { saveName(); join(location.host); },
    joinIp() {
      const el = $('#ip'); let v = (el ? el.value : '').trim().replace(/^https?:\/\//, '').replace(/\/.*$/, '');
      if (!/^[\w.\-]+(:\d+)?$/.test(v) || v.endsWith('.')) return toast('Escribe la dirección completa, por ejemplo 192.168.1.20', 'bad');
      if (v.indexOf(':') < 0) v += ':8765';
      join(v);
    },
    joinFound(d) { const f = S.found[Number(d.i)]; if (f) join(f.host + ':' + f.port); },
    leave() { leave(); S.screen = 'home'; },
    leaveAsk() { S.modal = { type: 'confirmLeave' }; },
    addBot() { send({ t: 'addBot' }); },
    kick(d) { send({ t: 'kick', id: d.id }); },
    deckMode() { send({ t: 'settings', deckMode: S.lobby.settings.deckMode === 'full' ? 'official' : 'full' }); },
    start() { send({ t: 'start' }); },
    toLobby() { send({ t: 'toLobby' }); },
    rules() { S.modal = { type: 'rules', keep: true }; },
    cards() { S.modal = { type: 'cards', keep: true }; },
    menu() { S.modal = { type: 'menu' }; },
    log() { S.modal = { type: 'log' }; },
    sound() { S.sound = !S.sound; store.set('sound', S.sound); },
    closeModal() { S.modal = null; },
    sel(d) {
      const i = S.sel.indexOf(d.id);
      if (i >= 0) S.sel.splice(i, 1);
      else {
        const v = S.view, c = v.hand.find((x) => x.id === d.id), first = v.hand.find((x) => x.id === S.sel[0]);
        if (first && c && (c.type === first.type || c.type === 'clone' || first.type === 'clone') && S.sel.length < 3) S.sel.push(d.id);
        else S.sel = [d.id];
      }
      SFX.tap();
    },
    clearSel() { S.sel = []; },
    zoomSel() { const c = S.view.hand.find((x) => x.id === S.sel[0]); if (c) S.modal = { type: 'zoom', card: c.type }; },
    zoomDiscard() { const d = S.view.discard[S.view.discard.length - 1]; if (d) S.modal = { type: 'zoom', card: d.type }; },
    play() { playSelected(); return false; },
    playOne(d) { act({ a: 'play', cards: [d.id] }); S.sel = []; },
    pickTarget(d) {
      const m = S.modal; S.modal = null;
      playSelected(d.id); return false;
    },
    pickNamed(d) { const t = S.modal.target; S.modal = null; playSelected(t, d.t); return false; },
    draw() { const v = S.view; if (v.cur === S.you && !v.prompt && !v.stack.length) { S.sel = []; act({ a: 'draw' }); } },
    nope() { const c = S.view.hand.find((x) => x.type === 'nope'); if (c) act({ a: 'play', cards: [c.id] }); },
    pass() { act({ a: 'pass' }); },
    die() { act({ a: 'die' }); },
    revive(d) { act({ a: 'revive', target: d.id }); },
    insSet(d) { const i = Number(d.i), max = S.view.draw + i; S.ins[i] = d.v === 'r' ? Math.floor(Math.random() * (max + 1)) : Math.min(max, Number(d.v)); },
    insert() { const n = S.view.prompt.eks; act({ a: 'insert', positions: S.ins.slice(0, n).map((x, i) => Math.min(x, S.view.draw + i)) }); S.ins = [0, 0]; },
    giveSel(d) { S.giveSel = d.id; },
    give() { if (S.giveSel) { act({ a: 'give', card: S.giveSel }); S.giveSel = null; } },
    digKeep() { act({ a: 'dig', keep: true }); },
    digNext() { act({ a: 'dig', keep: false }); },
  };
  function saveName() {
    const el = $('#name');
    if (el) S.name = el.value.trim().slice(0, 14);
    if (!S.name) S.name = 'Gatito' + Math.floor(Math.random() * 90 + 10);
    store.set('name', S.name);
  }

  document.addEventListener('click', (ev) => {
    let el = ev.target;
    while (el && el !== document.body) {
      if (el.dataset && el.dataset.act) break;
      if (el.dataset && el.dataset.stop) return;
      el = el.parentNode;
    }
    if (!el || !el.dataset || !el.dataset.act || el.disabled) return;
    const fn = A[el.dataset.act];
    if (!fn) return;
    if (el.classList.contains('btn')) SFX.tap();
    if (fn(el.dataset) !== false) render();
  });
  document.addEventListener('input', (ev) => {
    const el = ev.target;
    if (el.id === 'name') { S.name = el.value; store.set('name', S.name.trim()); }
    else if (el.id === 'ip') S.manualIp = el.value;
    else if (el.dataset && el.dataset.ins != null) {
      const i = Number(el.dataset.ins); S.ins[i] = Number(el.value);
      const l = document.getElementById('insl' + i); if (l) l.textContent = insLabel(S.ins[i], Number(el.max));
    }
  });
  window.addEventListener('resize', () => { if (S.screen === 'game') render(); });

  /* ----- puente con la app Android ----- */
  window.ZKNative = {
    found(list) { S.found = Array.isArray(list) ? list.filter((f) => !(f.host === S.info.ip && S.mode === 'host')) : []; if (S.screen === 'join') render(); },
    back() {
      if (S.modal) { S.modal = null; render(); return true; }
      if (S.screen === 'game') { S.modal = { type: 'confirmLeave' }; render(); return true; }
      if (S.screen === 'solo') { S.screen = 'home'; render(); return true; }
      if (S.screen === 'lobby' || S.screen === 'join' || S.screen === 'connecting') { if (S.screen === 'lobby' && S.isHost && S.lobby.players.length > 1) { S.modal = { type: 'confirmLeave' }; render(); return true; } leave(); S.screen = 'home'; render(); return true; }
      return false;
    },
  };

  /* ----- arranque ----- */
  // Sin servidor de juego (archivo suelto o hosting estático): solo se ofrece el modo de un jugador
  if (!S.info.static) fetch('/info').then((r) => r.json()).then((i) => { Object.assign(S.info, i); render(); }).catch(() => { S.info.static = true; render(); });
  setInterval(() => { if (S.screen === 'lobby' && S.isHost && !S.info.static) fetch('/info').then((r) => r.json()).then((i) => { if (i.ip !== S.info.ip) { Object.assign(S.info, i); render(); } }).catch(() => {}); }, 5000);
  render();
  window.ZKDebug = { S, send, act, get room() { return room; } };
})();
