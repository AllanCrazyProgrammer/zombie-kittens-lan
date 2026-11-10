/* Definición de cartas (textos en español) y arte vectorial ORIGINAL dibujado por código. */
(function (root) {
  'use strict';

  /* ---------- gato base reutilizable ---------- */
  function eye(x, style, c) {
    switch (style) {
      case 'none': return '';
      case 'x': return `<path d="M${x - 5} -7 l10 10 M${x + 5} -7 l-10 10" stroke="#111" stroke-width="3" stroke-linecap="round"/>`;
      case 'closed': return `<path d="M${x - 6} -2 q6 6 12 0" stroke="#111" stroke-width="2.6" fill="none" stroke-linecap="round"/>`;
      case 'wide': return `<circle cx="${x}" cy="-2" r="8.5" fill="#fff"/><circle cx="${x}" cy="-2" r="2.6" fill="#111"/>`;
      case 'big': return `<circle cx="${x}" cy="-2" r="8.5" fill="#111"/><circle cx="${x - 2.5}" cy="-5" r="3.2" fill="#fff"/><circle cx="${x + 3}" cy="1" r="1.6" fill="#fff"/>`;
      case 'glow': return `<circle cx="${x}" cy="-2" r="6.5" fill="${c}"/><circle cx="${x}" cy="-2" r="10" fill="${c}" opacity=".25"/>`;
      case 'angry': return `<ellipse cx="${x}" cy="-1" rx="7" ry="6.5" fill="${c}"/><ellipse cx="${x}" cy="-1" rx="1.8" ry="5.5" fill="#111"/><path d="M${x - 9 * Math.sign(x)} -11 L${x + 8 * Math.sign(x)} -5" stroke="#111" stroke-width="3.4" stroke-linecap="round"/>`;
      default: return `<ellipse cx="${x}" cy="-2" rx="7" ry="7.5" fill="${c}"/><ellipse cx="${x}" cy="-2" rx="2" ry="6" fill="#111"/><circle cx="${x - 2.5}" cy="-5" r="1.4" fill="#fff" opacity=".8"/>`;
    }
  }
  function cat(o) {
    o = Object.assign({ x: 60, y: 52, s: 1, rot: 0, fur: '#2b2342', ear: '#ff86b3', eye: '#ffe14a', eyes: 'slit', eyeL: null, eyeR: null, mouth: 'smile', body: true, tail: true, nose: '#ff86b3', line: '#111', under: '', extra: '' }, o);
    let g = `<g transform="translate(${o.x} ${o.y}) rotate(${o.rot}) scale(${o.s})">` + o.under;
    if (o.tail && o.body) g += `<path d="M17 38 q30 -2 20 -30" stroke="${o.fur}" stroke-width="7" fill="none" stroke-linecap="round"/>`;
    if (o.body) g += `<path d="M-21 46 q-5 -36 21 -36 q26 0 21 36 z" fill="${o.fur}"/><ellipse cx="-10" cy="45" rx="7" ry="4" fill="${o.fur}" stroke="${o.line}" stroke-opacity=".25"/><ellipse cx="10" cy="45" rx="7" ry="4" fill="${o.fur}" stroke="${o.line}" stroke-opacity=".25"/>`;
    g += `<path d="M-25 -12 l1 -26 l20 13 z M25 -12 l-1 -26 l-20 13 z" fill="${o.fur}"/>`;
    g += `<path d="M-20.5 -18 l1 -13 l10 7 z M20.5 -18 l-1 -13 l-10 7 z" fill="${o.ear}"/>`;
    g += `<ellipse cx="0" cy="0" rx="28" ry="22.5" fill="${o.fur}"/>`;
    g += eye(-11, o.eyeL || o.eyes, o.eye) + eye(11, o.eyeR || o.eyes, o.eye);
    g += `<path d="M-3 7 h6 l-3 3.6 z" fill="${o.nose}"/>`;
    const m = { stroke: o.line, 'stroke-width': 2, fill: 'none', 'stroke-linecap': 'round' };
    const st = `stroke="${m.stroke}" stroke-width="2" fill="none" stroke-linecap="round"`;
    if (o.mouth === 'smile') g += `<path d="M0 10.6 q-4 5 -9 1.5 M0 10.6 q4 5 9 1.5" ${st}/>`;
    else if (o.mouth === 'fangs') g += `<path d="M0 10.6 q-4 5 -9 1.5 M0 10.6 q4 5 9 1.5" ${st}/><path d="M-6 13 l1.6 6 l1.8 -5 z M6 13 l-1.6 6 l-1.8 -5 z" fill="#fff"/>`;
    else if (o.mouth === 'open') g += `<ellipse cx="0" cy="15" rx="6" ry="5" fill="#5a1030"/><path d="M-4 12 l1.5 4 l1.5 -4 z M4 12 l-1.5 4 l-1.5 -4 z" fill="#fff"/>`;
    else if (o.mouth === 'flat') g += `<path d="M-6 13 h12" ${st}/>`;
    else if (o.mouth === 'sad') g += `<path d="M-7 15 q7 -6 14 0" ${st}/>`;
    g += `<path d="M-17 6 h-13 M-17 9 l-12 4 M17 6 h13 M17 9 l12 4" stroke="${o.line}" stroke-opacity=".45" stroke-width="1.2" stroke-linecap="round"/>`;
    return g + o.extra + '</g>';
  }
  const Z = { fur: '#86c440', ear: '#5a8f25', nose: '#3f6b17', eye: '#fff36b' };   // gato zombi
  const stitch = `<path d="M-8 -17 l12 5 M-5 -19 l-2 5 M0 -17 l-2 5 M4 -15 l-2 5" stroke="#2f4f12" stroke-width="1.6" stroke-linecap="round"/>`;
  const tomb = (x, y, s, c) => `<g transform="translate(${x} ${y}) scale(${s || 1})"><path d="M-11 20 v-22 a11 11 0 0 1 22 0 v22 z" fill="${c || '#6f6a8f'}"/><path d="M-11 20 v-22 a11 11 0 0 1 6 -9.5 v31.5 z" fill="#000" opacity=".15"/><path d="M0 -6 v12 M-4 -2 h8" stroke="#3b3658" stroke-width="2.4" stroke-linecap="round"/></g>`;
  const moon = (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff6c9"/><circle cx="${x - r * 0.3}" cy="${y - r * 0.2}" r="${r * 0.18}" fill="#e9dc9f"/><circle cx="${x + r * 0.3}" cy="${y + r * 0.35}" r="${r * 0.12}" fill="#e9dc9f"/>`;
  const ground = (y, c) => `<path d="M0 ${y} q30 -7 60 -2 t60 -1 v${100 - y + 4} h-120 z" fill="${c}"/>`;
  const stars = (c) => `<g fill="${c || '#fff'}" opacity=".8"><circle cx="12" cy="12" r="1.2"/><circle cx="34" cy="22" r=".9"/><circle cx="100" cy="30" r="1.1"/><circle cx="76" cy="10" r=".8"/><circle cx="52" cy="8" r="1"/><circle cx="110" cy="12" r=".8"/></g>`;
  const mini = (x, y, r, c, inner) => `<g transform="translate(${x} ${y}) rotate(${r})"><rect x="-9" y="-13" width="18" height="26" rx="3" fill="${c}" stroke="#111" stroke-width="1.5"/>${inner || ''}</g>`;
  const bomb = (x, y, s) => `<g transform="translate(${x} ${y}) scale(${s})"><circle r="11" fill="#17131f"/><circle cx="-4" cy="-4" r="3" fill="#fff" opacity=".25"/><rect x="-3" y="-15" width="6" height="5" rx="1" fill="#4a4458"/><path d="M0 -15 q2 -8 9 -8" stroke="#c9a36b" stroke-width="2" fill="none"/><path d="M9 -29 l2 4 l4 -1 l-2.500 3.500 l3 3 l-4.500 0 l-1.500 4 l-1.800 -4 l-4.200 .5 l3 -3.200 l-2.500 -3.600 l4.200 1.200 z" fill="#ffd23a" stroke="#ff7a1a" stroke-width="1"/></g>`;
  const burst = (cx, cy, r1, r2, n, c) => { let d = ''; for (let i = 0; i < n * 2; i++) { const a = Math.PI * i / n, r = i % 2 ? r2 : r1; d += (i ? 'L' : 'M') + (cx + Math.cos(a) * r).toFixed(1) + ' ' + (cy + Math.sin(a) * r).toFixed(1); } return `<path d="${d}z" fill="${c}"/>`; };
  const bg = (id, a, b) => `<defs><linearGradient id="g${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs><rect width="120" height="100" fill="url(#g${id})"/>`;

  /* ---------- una escena por carta ---------- */
  const ART = {
    exploding: () => bg('ex', '#ff5a1f', '#a3141f') + burst(60, 50, 58, 30, 12, '#ffb52e') + burst(60, 50, 40, 22, 10, '#ffe66b') +
      cat({ y: 46, fur: '#17131f', ear: '#ff5a7a', eyes: 'wide', mouth: 'open', under: burst(0, 0, 35, 25, 16, '#17131f'), tail: false }) + bomb(88, 78, 1.05),
    zombie: () => bg('zo', '#2a1a55', '#4b2a7a') + stars() + moon(96, 20, 12) + tomb(24, 56, 1.25) + ground(74, '#2c4a1e') +
      `<ellipse cx="62" cy="78" rx="30" ry="7" fill="#1c3312"/>` +
      `<g transform="translate(98 66) rotate(12)"><rect x="-6" y="-14" width="12" height="30" rx="6" fill="${Z.fur}"/><circle cy="-17" r="8.500" fill="${Z.fur}"/><circle cx="-6" cy="-26" r="3.600" fill="${Z.fur}"/><circle cx="0" cy="-28.500" r="3.600" fill="${Z.fur}"/><circle cx="6" cy="-26" r="3.600" fill="${Z.fur}"/><ellipse cy="-16" rx="4.500" ry="3.600" fill="#3f6b17"/></g>` +
      cat(Object.assign({ x: 60, y: 54, body: false, eyeL: 'x', eyeR: 'slit', mouth: 'fangs', extra: stitch }, Z)) +
      `<path d="M28 80 q32 -12 66 0 v24 h-66 z" fill="#2c4a1e"/><path d="M36 78 l4 -6 l5 6 M70 77 l4 -7 l5 7" fill="#3c6428"/>`,
    attack: () => bg('at', '#ff9a2e', '#d6362b') + burst(60, 50, 70, 48, 9, 'rgba(255,255,255,.12)') +
      cat({ y: 50, fur: '#2b2342', eyes: 'angry', eye: '#ffe14a', mouth: 'fangs' }) +
      `<g stroke="#fff" stroke-width="5" stroke-linecap="round" fill="none"><path d="M70 14 q22 26 14 70"/><path d="M84 10 q22 26 14 70"/><path d="M98 8 q20 24 13 62"/></g><g stroke="#ffe14a" stroke-width="1.6" fill="none" opacity=".9"><path d="M72 16 q20 26 13 66"/><path d="M86 12 q20 26 13 66"/></g>`,
    attack_dead: () => bg('ad', '#23401c', '#0f2212') + moon(60, 30, 20) + ground(70, '#0b160c') +
      [[14, 70, .55], [38, 66, .7], [84, 66, .7], [106, 70, .55]].map(([x, y, s]) => cat({ x, y, s, fur: '#0b160c', ear: '#0b160c', nose: '#0b160c', line: '#0b160c', eyes: 'glow', eye: '#b6ff3a', mouth: 'none', tail: false })).join('') +
      cat(Object.assign({ x: 60, y: 60, s: .95, eyeL: 'slit', eyeR: 'x', mouth: 'fangs', extra: stitch + `<rect x="-33" y="6" width="9" height="26" rx="4.500" fill="${Z.fur}" transform="rotate(-28 -28 20)"/><rect x="24" y="6" width="9" height="26" rx="4.500" fill="${Z.fur}" transform="rotate(28 28 20)"/>` }, Z)),
    nope: () => bg('no', '#ff5468', '#9c1235') +
      cat({ x: 46, y: 54, fur: '#f1e6d2', ear: '#ff9fbf', eyes: 'closed', mouth: 'flat', line: '#3a2a2a' }) +
      `<g transform="translate(88 44)"><rect x="-3" y="18" width="6" height="34" fill="#e8e0d0"/><path d="M-10 -24 h20 l14 14 v20 l-14 14 h-20 l-14 -14 v-20 z" fill="#e11d2e" stroke="#fff" stroke-width="3.500"/><text y="6.500" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="19" fill="#fff">NOP</text></g>`,
    skip: () => bg('sk', '#39b8ff', '#2a4fd6') + `<circle cx="100" cy="18" r="9" fill="#fff" opacity=".35"/>` + ground(80, '#1b2e7a') + tomb(60, 66, 1.1, '#8b93c9') +
      `<path d="M10 70 q50 -78 100 -6" stroke="#fff" stroke-width="2.500" stroke-dasharray="3 6" fill="none" opacity=".8" stroke-linecap="round"/>` +
      cat({ x: 78, y: 26, s: .72, rot: 28, fur: '#ffb13d', ear: '#ff6f91', eyes: 'closed', line: '#5a2a00' }),
    super_skip: () => bg('ss', '#7b3cff', '#28106e') + stars('#ffe66b') + ground(84, '#170a45') + tomb(22, 76, .7, '#8b76d6') + tomb(56, 78, .8, '#8b76d6') + tomb(92, 76, .7, '#8b76d6') +
      `<g stroke="#ffe66b" stroke-width="2.500" stroke-linecap="round" opacity=".9"><path d="M6 30 h22 M2 42 h18 M10 54 h14"/></g>` +
      cat({ x: 70, y: 36, s: .8, rot: 62, fur: '#ffb13d', ear: '#ff6f91', eyes: 'angry', eye: '#fff', line: '#5a2a00', tail: false, under: `<path d="M-14 6 q-34 30 -8 62 q10 -14 22 -8 q8 -14 22 -8 q2 -34 -22 -46 z" fill="#e11d2e"/>` }),
    see_future: () => bg('sf', '#b34cff', '#3c1273') + stars('#ffd6ff') +
      `<path d="M34 92 q26 -16 52 0 z" fill="#ffc93a"/><rect x="40" y="82" width="40" height="7" rx="3" fill="#e0a21c"/>` +
      `<circle cx="60" cy="50" r="34" fill="#8ff2ff" opacity=".28"/><circle cx="60" cy="50" r="30" fill="#c9f8ff" opacity=".5" stroke="#e9fdff" stroke-width="2"/>` +
      mini(44, 54, -16, '#ffe14a') + mini(76, 54, 16, '#7ee06a') + mini(60, 50, 0, '#fff', `<text y="6" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="17" fill="#3c1273">?</text>`) +
      `<path d="M40 34 q6 -10 16 -12" stroke="#fff" stroke-width="3" fill="none" stroke-linecap="round" opacity=".9"/>` +
      `<path d="M14 80 q-2 -18 10 -22 q10 -2 12 8 z M106 80 q2 -18 -10 -22 q-10 -2 -12 8 z" fill="#2b2342"/>`,
    shuffle: () => bg('sh', '#22d3b4', '#0c6b7a') +
      mini(40, 52, -24, '#ffe14a') + mini(60, 46, 0, '#ff7fb0') + mini(80, 52, 24, '#fff') +
      `<g fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"><path d="M22 30 q38 -30 76 0"/><path d="M98 76 q-38 30 -76 0"/></g><path d="M100 18 l1 16 l-15 -6 z M20 88 l-1 -16 l15 6 z" fill="#fff"/>` +
      cat({ x: 60, y: 50, s: .36, body: false, fur: '#2b2342' }),
    feed_dead: () => bg('fd', '#c9d64a', '#5d7a1c') +
      cat(Object.assign({ x: 50, y: 50, eyeL: 'wide', eyeR: 'x', mouth: 'open', extra: stitch }, Z)) +
      `<g transform="translate(94 52) rotate(14)"><rect x="-2" y="0" width="4" height="40" rx="2" fill="#e8e8f0"/><path d="M-7 -18 v14 q0 6 7 6 q7 0 7 -6 v-14 M0 -18 v16" stroke="#e8e8f0" stroke-width="3" fill="none" stroke-linecap="round"/><g transform="translate(0 -26)"><path d="M-12 0 q0 -10 12 -10 q12 0 12 10 q0 8 -12 8 q-12 0 -12 -8 z" fill="#ff9fc0"/><path d="M-6 -4 q3 4 0 8 M0 -9 v16 M6 -4 q-3 4 0 8" stroke="#d8588a" stroke-width="1.800" fill="none" stroke-linecap="round"/></g></g>`,
    clone: () => bg('cl', '#5fe0ff', '#1d6fb8') +
      `<path d="M60 6 v88" stroke="#fff" stroke-width="2" stroke-dasharray="4 5" opacity=".8"/>` +
      cat({ x: 32, y: 52, s: .8, fur: '#ff8a3d', ear: '#ffd0a8', line: '#5a2a00' }) +
      `<g opacity=".78">` + cat({ x: 88, y: 52, s: .8, fur: '#39e6c9', ear: '#bafff2', eye: '#fff', line: '#0c4d57', nose: '#0c6b7a' }) + `</g>` +
      `<g fill="#fff" opacity=".9"><circle cx="60" cy="22" r="3"/><circle cx="60" cy="50" r="3"/><circle cx="60" cy="78" r="3"/></g>`,
    grave_robber: () => bg('gr', '#3a3a6e', '#17152e') + stars() + ground(76, '#2e2a1e') +
      `<path d="M62 78 h44 l-5 20 h-34 z" fill="#0d0b14"/>` + tomb(100, 58, 1.1) +
      `<g transform="translate(84 60) rotate(24)"><rect x="-2" y="-28" width="4" height="40" fill="#b9854a"/><path d="M-8 12 h16 v10 q-8 10 -16 0 z" fill="#cfd4e6"/></g>` +
      cat({ x: 38, y: 50, fur: '#2b2342', eyes: 'slit', eye: '#fff', extra: `<path d="M-28 -8 h56 v9 q-14 6 -28 0 q-14 6 -28 0 z" fill="#0d0b14" opacity=".92"/>` + eye(-11, 'slit', '#ffe14a') + eye(11, 'slit', '#ffe14a') + `<g transform="translate(22 34)"><path d="M-10 12 q-4 -22 10 -22 q14 0 10 22 z" fill="#d9b36b"/><path d="M-4 -9 h8" stroke="#8a6a2e" stroke-width="3" stroke-linecap="round"/><text y="8" text-anchor="middle" font-size="11" font-family="Bangers,Impact,sans-serif" fill="#8a6a2e">$</text></g>` }),
    favor: () => bg('fa', '#ff9fd0', '#e0457e') + burst(60, 52, 74, 52, 10, 'rgba(255,255,255,.14)') +
      cat({ y: 52, fur: '#fff5e6', ear: '#ff9fbf', eyes: 'big', mouth: 'sad', line: '#5a3a3a' }) +
      `<path d="M94 20 c-5 -8 -16 -2 -10 7 l10 10 l10 -10 c6 -9 -5 -15 -10 -7 z" fill="#fff"/><path d="M22 30 c-3 -5 -10 -1 -6 4.500 l6 6 l6 -6 c4 -5.500 -3 -9.500 -6 -4.500 z" fill="#fff" opacity=".8"/>`,
    dig_deeper: () => bg('dd', '#ffcf6b', '#e0862e') + `<rect y="46" width="120" height="54" fill="#6b4226"/><path d="M0 46 q30 -6 60 0 t60 0 v6 h-120 z" fill="#58a83a"/>` +
      `<g fill="#4f2f1a"><circle cx="16" cy="66" r="3"/><circle cx="100" cy="84" r="4"/><circle cx="30" cy="90" r="2.500"/></g>` +
      mini(52, 66, -8, '#fff', `<text y="6" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="16" fill="#6b4226">1</text>`) + mini(74, 82, 10, '#ffe14a', `<text y="6" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="16" fill="#6b4226">2</text>`) +
      `<g transform="translate(96 30) rotate(28)"><rect x="-2.500" y="-30" width="5" height="44" rx="2" fill="#b9854a"/><rect x="-8" y="-34" width="16" height="6" rx="3" fill="#8a5a2a"/><path d="M-10 14 h20 v12 q-10 12 -20 0 z" fill="#dfe4f2" stroke="#8b93a8" stroke-width="1.500"/></g>` +
      cat({ x: 26, y: 30, s: .55, body: false, fur: '#2b2342' }),
    clairvoyance: () => bg('cv', '#2747c9', '#0b1247') + stars('#9fe8ff') +
      `<g stroke="#9fe8ff" stroke-width="2" opacity=".55" stroke-linecap="round"><path d="M60 8 v-6 M92 18 l5 -5 M28 18 l-5 -5 M106 44 h8 M6 44 h8"/></g>` +
      `<path d="M10 46 q50 -46 100 0 q-50 46 -100 0 z" fill="#f4fbff" stroke="#9fe8ff" stroke-width="2.500"/><circle cx="60" cy="46" r="21" fill="#49e0e6"/><circle cx="60" cy="46" r="21" fill="none" stroke="#1a8fa8" stroke-width="2"/><ellipse cx="60" cy="46" rx="6.500" ry="19" fill="#0b1247"/><circle cx="52" cy="37" r="4" fill="#fff" opacity=".85"/>` +
      bomb(60, 88, .62) + `<path d="M44 70 l16 8 l16 -8" stroke="#9fe8ff" stroke-width="2" fill="none" stroke-dasharray="2 4" stroke-linecap="round"/>`,
    cat_a: () => bg('ca', '#ffe7a3', '#e0a84a') + `<path d="M0 78 l30 -40 l22 28 l14 -18 l54 60 v-8 h-120 z" fill="#c98a2e" opacity=".5"/>` +
      cat({ y: 52, fur: '#efe6cf', ear: '#d9c9a3', eyeL: 'slit', eyeR: 'slit', eye: '#7ee06a', nose: '#b89f6e', line: '#6b5a36', mouth: 'flat',
        extra: `<g stroke="#b8a878" stroke-width="1.600" fill="none"><path d="M-27 -8 q27 -8 54 2 M-28 2 q10 3 14 -4 M10 -14 q8 8 18 6 M-26 12 q26 9 52 0 M-18 22 q18 6 36 0 M-21 30 q20 8 42 2 M-20 40 q20 6 40 0"/></g><path d="M22 14 q14 6 10 22" stroke="#efe6cf" stroke-width="4" fill="none" stroke-linecap="round"/>` }),
    cat_b: () => bg('cb', '#8a1f4f', '#2a0a2e') + moon(92, 20, 13) +
      `<g fill="#17131f"><path d="M14 22 q6 -8 12 0 q4 -4 8 0 q-6 2 -8 8 q-2 -5 -6 -3 q-3 -4 -6 -5 z"/><path d="M34 40 q4 -5 8 0 q3 -3 6 0 q-4 1 -6 6 q-1 -4 -4 -2 q-2 -3 -4 -4 z"/></g>` +
      cat({ y: 52, fur: '#2b2342', ear: '#e11d2e', eye: '#ff4d5e', mouth: 'fangs', under: `<path d="M-38 48 q-6 -44 12 -52 l26 14 l26 -14 q18 8 12 52 z" fill="#17131f"/><path d="M-30 46 q-4 -34 8 -42 l22 12 l22 -12 q12 8 8 42 z" fill="#c2182b"/><path d="M-26 -2 l-8 -18 l20 8 z M26 -2 l8 -18 l-20 8 z" fill="#17131f"/>` }),
    cat_c: () => bg('cc', '#6b7cff', '#2a2a7a') + stars() +
      `<g transform="translate(60 50)"><ellipse cx="0" cy="44" rx="24" ry="4" fill="#000" opacity=".25"/><path d="M-22 -20 l0 -18 l14 9 z M22 -20 l0 -18 l-14 9 z" fill="#f4f7ff"/><path d="M-27 34 v-36 a27 26 0 0 1 54 0 v36 q-4.500 -8 -9 0 q-4.500 8 -9 0 q-4.500 -8 -9 0 q-4.500 8 -9 0 q-4.500 -8 -9 0 q-4.500 8 -9 0 z" fill="#f4f7ff"/><path d="M-27 34 v-36 a27 26 0 0 1 8 -18 v50 q-4 -4 -8 4 z" fill="#c9d2ff" opacity=".7"/><ellipse cx="-10" cy="-4" rx="5.500" ry="7.500" fill="#1b1b4a"/><ellipse cx="10" cy="-4" rx="5.500" ry="7.500" fill="#1b1b4a"/><path d="M-3 7 h6 l-3 3.600 z" fill="#ff86b3"/><ellipse cx="0" cy="16" rx="4" ry="5" fill="#1b1b4a"/><ellipse cx="-19" cy="6" rx="4" ry="2.500" fill="#ff9fbf" opacity=".6"/><ellipse cx="19" cy="6" rx="4" ry="2.500" fill="#ff9fbf" opacity=".6"/></g>` +
      `<text x="96" y="30" font-family="Bangers,Impact,sans-serif" font-size="13" fill="#fff" opacity=".85" transform="rotate(12 96 30)">miau~</text>`,
    cat_d: () => bg('cd', '#3b3b4f', '#111118') + `<circle cx="60" cy="50" r="40" fill="#7ee06a" opacity=".12"/>` +
      cat({ y: 50, fur: '#f1efe6', ear: '#17131f', nose: '#17131f', line: '#17131f', eyes: 'none', mouth: 'none',
        extra: `<ellipse cx="-11" cy="-2" rx="7.500" ry="8.500" fill="#17131f"/><ellipse cx="11" cy="-2" rx="7.500" ry="8.500" fill="#17131f"/><circle cx="-11" cy="-1" r="2.400" fill="#7ee06a"/><circle cx="11" cy="-1" r="2.400" fill="#7ee06a"/><path d="M-9 14 h18 M-6 11 v6 M-2 11 v6 M2 11 v6 M6 11 v6" stroke="#17131f" stroke-width="1.600" stroke-linecap="round"/><g stroke="#17131f" stroke-width="2.400" stroke-linecap="round" fill="none"><path d="M0 24 v20 M-12 28 q12 5 24 0 M-13 34 q13 5 26 0 M-12 40 q12 5 24 0"/></g>` }),
    back: () => `<defs><linearGradient id="gbk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3a1f7a"/><stop offset="1" stop-color="#1b0f3d"/></linearGradient><pattern id="pbk" width="16" height="16" patternUnits="userSpaceOnUse" patternTransform="rotate(30)"><circle cx="8" cy="8" r="1.600" fill="#9be22d" opacity=".22"/></pattern></defs><rect width="100" height="140" rx="10" fill="url(#gbk)"/><rect width="100" height="140" rx="10" fill="url(#pbk)"/><rect x="6" y="6" width="88" height="128" rx="7" fill="none" stroke="#9be22d" stroke-width="2" opacity=".7"/>` +
      `<g transform="translate(50 72)" fill="#9be22d"><ellipse cx="0" cy="10" rx="17" ry="14"/><ellipse cx="-19" cy="-9" rx="6.500" ry="9" transform="rotate(-22 -19 -9)"/><ellipse cx="-7" cy="-19" rx="6.500" ry="9.500" transform="rotate(-6 -7 -19)"/><ellipse cx="7" cy="-19" rx="6.500" ry="9.500" transform="rotate(6 7 -19)"/><ellipse cx="19" cy="-9" rx="6.500" ry="9" transform="rotate(22 19 -9)"/></g><path d="M42 80 l5 5 M47 80 l-5 5 M53 80 l5 5 M58 80 l-5 5" stroke="#1b0f3d" stroke-width="2.200" stroke-linecap="round"/>`,
  };

  /* ---------- textos ---------- */
  const C = {
    exploding: { name: 'Gatito Explosivo', icon: '💣', color: '#e2331f', kind: 'Peligro', short: 'Si lo sacas, ¡explotas! A menos que juegues un Gatito Zombi.',
      long: 'Debes mostrarla de inmediato. Si no puedes (o no quieres) jugar un Gatito Zombi, quedas MUERTO: el explosivo se queda frente a ti y conservas el resto de tu mano. Hay un explosivo menos que jugadores.' },
    zombie: { name: 'Gatito Zombi', icon: '🧟', color: '#5fa329', kind: 'Salvación', short: 'En vez de explotar, esconde el Gatito Explosivo en el mazo… y revive a un jugador muerto.',
      long: 'La carta más poderosa. Si sacas un Gatito Explosivo puedes (no es obligatorio) jugarla en lugar de morir. Si hay jugadores muertos DEBES elegir a uno para revivirlo. Luego colocas en secreto tu explosivo (y el del jugador revivido, cada uno donde quieras) dentro del mazo. Tu turno termina. Nadie puede anularla con Nop.' },
    attack: { name: 'Ataque (2x)', icon: '⚔️', color: '#e2571f', kind: 'Acción', short: 'Termina tu turno sin robar. El siguiente jugador juega 2 turnos seguidos.',
      long: 'Termina tu turno sin robar y obliga al siguiente jugador a jugar 2 turnos seguidos. Los ataques se apilan: si la víctima juega otro Ataque, sus turnos pendientes pasan al siguiente jugador MÁS 2 turnos extra (2 → 4 → 6…).' },
    attack_dead: { name: 'Ataque de los Muertos', icon: '☠️', color: '#2f6b2a', kind: 'Acción', short: 'Termina tu turno sin robar. El siguiente juega 3 turnos por cada jugador muerto.',
      long: 'Termina tu turno sin robar. El siguiente jugador debe jugar 3 turnos por cada jugador Muerto. No puedes jugarla si no hay muertos. Se apila con otros ataques igual que Ataque (2x).' },
    nope: { name: 'Nop', icon: '🚫', color: '#d61f45', kind: 'En cualquier momento', now: true, short: 'Anula cualquier acción, excepto un Gatito Explosivo o un Gatito Zombi.',
      long: 'Juégala en cualquier momento antes de que una acción comience, aunque no sea tu turno: la carta anulada se pierde. Puedes jugar un Nop sobre otro Nop para cancelarlo (¡un "Sip"!). También anula combos especiales. Los jugadores muertos también pueden jugarla.' },
    skip: { name: 'Saltar', icon: '⏭️', color: '#2a7fe0', kind: 'Acción', short: 'Termina tu turno inmediatamente sin robar carta.',
      long: 'Termina tu turno sin robar. Si te atacaron, solo cancela 1 de tus turnos pendientes: con 2 turnos necesitas 2 cartas de Saltar.' },
    super_skip: { name: 'Súper Salto', icon: '⏩', color: '#6a35e0', kind: 'Acción', short: 'Termina tu turno sin robar. Si debías jugar varios turnos, termínalos TODOS.',
      long: 'Termina tu turno sin robar carta. Si debías jugar varios turnos (porque te atacaron), los termina todos de una vez.' },
    see_future: { name: 'Ver el Futuro (3x)', icon: '🔮', color: '#9a3ce0', kind: 'Acción', short: 'Mira en secreto las 3 cartas de arriba del mazo.',
      long: 'Mira en privado las 3 cartas superiores del mazo y déjalas en el mismo orden. No se las muestres a nadie.' },
    shuffle: { name: 'Barajar', icon: '🔀', color: '#12a892', kind: 'En cualquier momento', now: true, short: 'Baraja el mazo. Puedes jugarla aunque no sea tu turno.',
      long: 'Baraja el mazo. Tiene el símbolo ⚡: puedes jugarla en cualquier momento antes de que una acción comience, aunque no sea tu turno. Los jugadores muertos también pueden jugarla. Ideal justo después de que alguien use Ver el Futuro.' },
    feed_dead: { name: 'Alimenta a los Muertos', icon: '🍖', color: '#8a9a1f', kind: 'En cualquier momento', now: true, short: 'Elige a un muerto: cada jugador vivo (menos tú) le da 1 carta.',
      long: 'Elige a un jugador Muerto. Todos los jugadores Vivos (excepto tú) deben elegir 1 carta de su mano y dársela. Tiene ⚡: puede jugarse en cualquier momento, y los muertos también pueden jugarla… ¡incluso sobre sí mismos!' },
    clone: { name: 'Clon', icon: '👯', color: '#1f8fd6', kind: 'Acción', short: 'Se convierte en la carta que está debajo en el descarte.',
      long: 'Al jugarla copia la carta que queda debajo de ella en la pila de descarte y adopta sus reglas. No puede ir sobre otro Clon, ni jugarse fuera de tu turno o estando muerto. Si sacas un explosivo y la carta superior del descarte es un Gatito Zombi, ¡el Clon te salva! También completa parejas y tríos con cualquier carta.' },
    grave_robber: { name: 'Ladrón de Tumbas', icon: '⚰️', color: '#4a4a8a', kind: 'Acción', short: 'Cada muerto con cartas elige 1 de su mano y la baraja en el mazo.',
      long: 'Todos los jugadores Muertos con cartas deben elegir 1 carta de su mano para barajarla dentro del mazo. No puedes jugarla si no hay muertos. Muy útil al final: más cartas en el mazo = menos probabilidad de explotar.' },
    favor: { name: 'Favor', icon: '🙏', color: '#e0457e', kind: 'Acción', short: 'Obliga a otro jugador vivo a darte 1 carta de su mano. Él elige cuál.',
      long: 'Obliga a cualquier otro jugador a darte 1 carta de su mano; ese jugador elige cuál. No puedes jugarla contra un jugador Muerto.' },
    dig_deeper: { name: 'Cava Más Hondo', icon: '⛏️', color: '#d68a1f', kind: 'Acción', short: 'Roba la carta de arriba y mírala. Si no la quieres, DEBES robar la siguiente.',
      long: 'Roba la carta superior, mírala y decide si te la quedas. Si te la quedas, va a tu mano y tu turno termina. Si no, DEBES robar la siguiente carta sea cual sea, y la que rechazaste vuelve arriba del mazo. Si solo queda 1 carta en el mazo, no tiene efecto.' },
    clairvoyance: { name: 'Clarividencia', icon: '👁️', color: '#2747c9', kind: 'En cualquier momento', now: true, short: 'Cuando otro jugador use un Gatito Zombi, mira dónde esconde los explosivos.',
      long: 'Juégala cuando otro jugador haya jugado un Gatito Zombi: verás en qué posición del mazo coloca el/los Gatito(s) Explosivo(s). Tiene ⚡: puedes jugarla aunque no sea tu turno, incluso estando muerto.' },
    cat_a: { name: 'Gato Momia', icon: '🤕', color: '#b8892e', kind: 'Carta de gato', cat: true },
    cat_b: { name: 'Vampigato', icon: '🧛', color: '#8a1f4f', kind: 'Carta de gato', cat: true },
    cat_c: { name: 'Fantasmiau', icon: '👻', color: '#5463e0', kind: 'Carta de gato', cat: true },
    cat_d: { name: 'Esquelegato', icon: '💀', color: '#4a4a5e', kind: 'Carta de gato', cat: true },
  };
  for (const k of Object.keys(C)) if (C[k].cat) {
    C[k].short = 'No hace nada sola. Juega 2 iguales para robar una carta al azar a otro jugador.';
    C[k].long = 'Las cartas de gato no tienen poder por sí solas. Si juntas 2 iguales puedes jugarlas como pareja para robar una carta al azar de cualquier jugador Vivo. Con 3 iguales, nombras la carta que quieres.';
  }
  const ORDER = ['zombie', 'nope', 'attack', 'attack_dead', 'skip', 'super_skip', 'see_future', 'dig_deeper', 'shuffle', 'favor', 'clone', 'clairvoyance', 'feed_dead', 'grave_robber', 'cat_a', 'cat_b', 'cat_c', 'cat_d', 'exploding'];
  const COUNTS = { exploding: '4', zombie: '2🐾 + 3', attack: '2🐾 + 0', attack_dead: '0🐾 + 3', nope: '2🐾 + 3', skip: '1🐾 + 2', super_skip: '1🐾 + 1', see_future: '2🐾 + 2', shuffle: '1🐾 + 1', feed_dead: '0🐾 + 2', clone: '1🐾 + 2', grave_robber: '0🐾 + 1', favor: '1🐾 + 2', dig_deeper: '2🐾 + 2', clairvoyance: '1🐾 + 1', cat_a: '2🐾 + 2', cat_b: '2🐾 + 2', cat_c: '2🐾 + 2', cat_d: '2🐾 + 2' };

  const artSvg = (type) => `<svg viewBox="0 0 120 100" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg">${ART[type]()}</svg>`;
  const artCache = {};
  function cardHTML(type, o) {
    o = o || {};
    const c = C[type];
    if (!artCache[type]) artCache[type] = artSvg(type);
    return `<div class="card ${o.cls || ''}" style="--cc:${c.color}" ${o.attr || ''}>
      <div class="c-top"><span class="c-ico">${c.icon}</span><span class="c-name">${c.name}</span></div>
      <div class="c-art">${artCache[type]}${c.now ? '<span class="c-now">⚡ YA</span>' : ''}</div>
      <div class="c-txt">${c.short}</div>${o.paw ? '<span class="c-paw">🐾</span>' : ''}</div>`;
  }
  const backHTML = (cls) => `<div class="card back ${cls || ''}"><svg viewBox="0 0 100 140" preserveAspectRatio="none">${ART.back()}</svg></div>`;

  const FURS = [['#2b2342', '#ff86b3', '#ffe14a'], ['#ff8a3d', '#ffd0a8', '#fff'], ['#f1e6d2', '#ff9fbf', '#49c2e6'], ['#86c440', '#5a8f25', '#fff36b'], ['#8d8fa8', '#ffd0e0', '#ffe14a'], ['#b06a3a', '#ffc9a0', '#9be22d'], ['#ff7fb0', '#fff', '#fff'], ['#49b8e0', '#d6f6ff', '#ffe14a']];
  const BGS = ['#6a35e0', '#1f8fd6', '#e0457e', '#3d2a6e', '#12a892', '#e2571f', '#4a4a8a', '#d6a01f'];
  function avatar(i, dead) {
    const f = FURS[(i || 0) % 8];
    return `<svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="32" fill="${dead ? '#3a3a44' : BGS[(i || 0) % 8]}"/>` +
      cat({ x: 32, y: 38, s: .92, body: false, fur: dead ? '#8b8b96' : f[0], ear: dead ? '#666' : f[1], eye: f[2], eyes: dead ? 'x' : 'slit', mouth: dead ? 'flat' : 'smile' }) + '</svg>';
  }
  function logo() {
    return `<svg viewBox="0 0 320 240" class="logo" xmlns="http://www.w3.org/2000/svg">${moon(160, 78, 62)}
      <g opacity=".9">${tomb(52, 150, 1.5, '#5a4a9a')}${tomb(270, 152, 1.4, '#5a4a9a')}</g>
      <g transform="translate(232 138) rotate(10)"><rect x="-9" y="-20" width="18" height="46" rx="9" fill="${Z.fur}"/><circle cy="-25" r="13" fill="${Z.fur}"/><circle cx="-9" cy="-39" r="5.500" fill="${Z.fur}"/><circle cx="0" cy="-43" r="5.500" fill="${Z.fur}"/><circle cx="9" cy="-39" r="5.500" fill="${Z.fur}"/><ellipse cy="-24" rx="7" ry="5.500" fill="#3f6b17"/></g>
      ${cat(Object.assign({ x: 160, y: 118, s: 1.9, body: false, eyeL: 'x', eyeR: 'slit', mouth: 'fangs', extra: stitch }, Z))}
      <ellipse cx="160" cy="196" rx="158" ry="40" fill="#1b3312"/>
      <g font-family="Bangers,Impact,sans-serif" text-anchor="middle"><text x="160" y="218" font-size="58" textLength="292" lengthAdjust="spacingAndGlyphs" fill="#0d0820" stroke="#0d0820" stroke-width="10" stroke-linejoin="round">ZOMBIE KITTENS</text><text x="160" y="218" font-size="58" textLength="292" lengthAdjust="spacingAndGlyphs" fill="#b6f23a">ZOMBIE KITTENS</text></g></svg>`;
  }

  root.ZKCards = { C, ORDER, COUNTS, cardHTML, backHTML, avatar, logo, artSvg };
})(typeof self !== 'undefined' ? self : this);
