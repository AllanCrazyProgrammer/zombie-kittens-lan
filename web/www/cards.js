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
  const stars = (c) => `<g fill="${c || '#fff'}" opacity=".85"><circle cx="14" cy="14" r="2.6"/><circle cx="104" cy="26" r="2.4"/><circle cx="60" cy="10" r="2.2"/><circle cx="34" cy="86" r="2.2"/><circle cx="96" cy="84" r="2.4"/></g>`;
  const mini = (x, y, r, c, inner) => `<g transform="translate(${x} ${y}) rotate(${r})"><rect x="-9" y="-13" width="18" height="26" rx="3" fill="${c}" stroke="#111" stroke-width="1.5"/>${inner || ''}</g>`;
  const bomb = (x, y, s) => `<g transform="translate(${x} ${y}) scale(${s})"><circle r="11" fill="#17131f"/><circle cx="-4" cy="-4" r="3" fill="#fff" opacity=".25"/><rect x="-3" y="-15" width="6" height="5" rx="1" fill="#4a4458"/><path d="M0 -15 q2 -8 9 -8" stroke="#c9a36b" stroke-width="2" fill="none"/><path d="M9 -29 l2 4 l4 -1 l-2.500 3.500 l3 3 l-4.500 0 l-1.500 4 l-1.800 -4 l-4.200 .5 l3 -3.200 l-2.500 -3.600 l4.200 1.200 z" fill="#ffd23a" stroke="#ff7a1a" stroke-width="1"/></g>`;
  const burst = (cx, cy, r1, r2, n, c) => { let d = ''; for (let i = 0; i < n * 2; i++) { const a = Math.PI * i / n, r = i % 2 ? r2 : r1; d += (i ? 'L' : 'M') + (cx + Math.cos(a) * r).toFixed(1) + ' ' + (cy + Math.sin(a) * r).toFixed(1); } return `<path d="${d}z" fill="${c}"/>`; };
  const bg = (id, a, b) => `<defs><linearGradient id="g${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs><rect width="120" height="100" fill="url(#g${id})"/>`;

  /* ---------- fondos y focos nuevos: cada carta se lee por su silueta ---------- */
  /* halo: círculo claro detrás del sujeto para separarlo del fondo. */
  const halo = (cx, cy, r, c, op) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${c || '#fff'}" opacity="${op == null ? .22 : op}"/>`;
  /* rays: abanico de rayos desde el centro (sol naciente). */
  const rays = (cx, cy, r, n, c, op) => { let d = ''; for (let i = 0; i < n; i++) { const a0 = (i * 2 * Math.PI) / n, a1 = a0 + Math.PI / n * .55; d += `M${cx} ${cy} L${(cx + Math.cos(a0) * r).toFixed(1)} ${(cy + Math.sin(a0) * r).toFixed(1)} L${(cx + Math.cos(a1) * r).toFixed(1)} ${(cy + Math.sin(a1) * r).toFixed(1)} z`; } return `<path d="${d}" fill="${c || '#fff'}" opacity="${op == null ? .14 : op}"/>`; };
  /* dots: patrón de puntos grandes (legible a 104px, no estrellas de 1px). */
  const dots = (id, c, op) => `<defs><pattern id="pd${id}" width="20" height="20" patternUnits="userSpaceOnUse"><circle cx="5" cy="5" r="2.6" fill="${c || '#fff'}" opacity="${op == null ? .3 : op}"/><circle cx="15" cy="15" r="1.8" fill="${c || '#fff'}" opacity="${op == null ? .2 : op}"/></pattern></defs><rect width="120" height="100" fill="url(#pd${id})"/>`;
  /* stripes: patrón de rayas diagonales gruesas. */
  const stripes = (id, c, op) => `<defs><pattern id="ps${id}" width="18" height="18" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="18" height="7" fill="${c || '#fff'}" opacity="${op == null ? .13 : op}"/></pattern></defs><rect width="120" height="100" fill="url(#ps${id})"/>`;
  /* sparkles: destellos de 4 puntas, grandes (reemplazan a las estrellas diminutas). */
  const sparkles = (c) => `<g fill="${c || '#fff'}"><path d="M14 12 l2.5 6 6 2.5 -6 2.5 -2.5 6 -2.5 -6 -6 -2.5 6 -2.5 z"/><path d="M102 26 l2 5 5 2 -5 2 -2 5 -2 -5 -5 -2 5 -2 z"/><path d="M60 10 l1.8 4.4 4.4 1.8 -4.4 1.8 -1.8 4.4 -1.8 -4.4 -4.4 -1.8 4.4 -1.8 z"/></g>`;
  /* bigBomb: bomba gigante con mecha corta (la de bomb() se sale del cuadro al escalarla). */
  const bigBomb = (x, y, s) => `<g transform="translate(${x} ${y}) scale(${s || 1})"><circle r="15" fill="#17131f"/><circle cx="-5" cy="-5" r="4" fill="#fff" opacity=".25"/><rect x="-3" y="-20" width="7" height="6" rx="1.5" fill="#4a4458"/><path d="M0 -20 q3 -9 11 -9" stroke="#c9a36b" stroke-width="2.5" fill="none"/><path d="M11 -32 l2.5 5 5 -1 -3 4.5 3.5 3.5 -5.5 0 -2 5 -2 -5 -5 .5 3.5 -3.5 -3 -4.5 5 1.5 z" fill="#ffd23a" stroke="#ff7a1a" stroke-width="1.2"/></g>`;
  /* stopSign: octógono de STOP centrado en (cx, cy), radio 40*s. */
  const stopSign = (cx, cy, s) => { const r = 40 * (s || 1); const pts = []; for (let k = 0; k < 8; k++) { const a = (22.5 + 45 * k) * Math.PI / 180; pts.push((cx + Math.cos(a) * r).toFixed(1) + ',' + (cy + Math.sin(a) * r).toFixed(1)); } return `<polygon points="${pts.join(' ')}" fill="#e11d2e" stroke="#fff" stroke-width="4" stroke-linejoin="round"/>`; };
  /* bigEye: ojo gigante de ancho w y alto h, iris de radio iris. */
  const bigEye = (cx, cy, w, h, iris) => `<g><path d="M${cx - w / 2} ${cy} q${w / 2} ${-h} ${w} 0 q${-w / 2} ${h} ${-w} 0 z" fill="#f4fbff" stroke="#9fe8ff" stroke-width="3"/><circle cx="${cx}" cy="${cy}" r="${iris}" fill="#49e0e6"/><circle cx="${cx}" cy="${cy}" r="${(iris * .45).toFixed(1)}" fill="#0b1247"/><circle cx="${(cx - iris * .35).toFixed(1)}" cy="${(cy - iris * .35).toFixed(1)}" r="${(iris * .22).toFixed(1)}" fill="#fff"/></g>`;
  /* bigHeart: corazón grande centrado en (cx, cy), escala s. */
  const bigHeart = (cx, cy, s) => `<g transform="translate(${cx} ${cy}) scale(${s || 1})"><path d="M0 10 c-10 -14 -30 -4 -18 14 l18 18 18 -18 c12 -18 -8 -28 -18 -14 z" fill="#fff" stroke="#e0457e" stroke-width="3" stroke-linejoin="round"/></g>`;
  /* bigBone: muslo de carne gigante (hueso + carne), rotado rot grados. */
  const bigBone = (x, y, s, rot) => `<g transform="translate(${x} ${y}) rotate(${rot || 0}) scale(${s || 1})"><rect x="10" y="-5" width="30" height="10" rx="5" fill="#f4ead8"/><circle cx="42" cy="-7" r="7" fill="#f4ead8"/><circle cx="42" cy="7" r="7" fill="#f4ead8"/><ellipse cx="0" cy="0" rx="20" ry="17" fill="#e88a5a"/><ellipse cx="-4" cy="-3" rx="11" ry="8" fill="#f2a878"/></g>`;
  /* bigShovel: pala gigante, rotada rot grados. */
  const bigShovel = (x, y, s, rot) => `<g transform="translate(${x} ${y}) rotate(${rot || 0}) scale(${s || 1})"><rect x="-3.5" y="-36" width="7" height="46" rx="3.5" fill="#b9854a"/><rect x="-10" y="-42" width="20" height="9" rx="4.5" fill="#8a5a2a"/><path d="M-12 10 h24 v15 q-12 15 -24 0 z" fill="#dfe4f2" stroke="#8b93a8" stroke-width="2"/></g>`;
  /* fan: tres cartas grandes (34x48) abanicadas, centradas en (cx, cy). */
  const fan = (cx, cy, c1, c2, c3) => `<g><g transform="translate(${cx - 22} ${cy}) rotate(-26)"><rect x="-17" y="-24" width="34" height="48" rx="5" fill="${c1}" stroke="#111" stroke-width="2"/></g><g transform="translate(${cx + 22} ${cy}) rotate(26)"><rect x="-17" y="-24" width="34" height="48" rx="5" fill="${c3}" stroke="#111" stroke-width="2"/></g><g transform="translate(${cx} ${cy - 4})"><rect x="-17" y="-24" width="34" height="48" rx="5" fill="${c2}" stroke="#111" stroke-width="2"/></g></g>`;

  /* ---------- una escena por carta ----------
     Regla: un solo objeto protagonista grande (~50% del cuadro 120x100),
     con halo detrás, y el gato desplazado/rotado/escalado de forma distinta
     en cada carta. Sin detalles menores de 2px ni textos menores de 18px. */
  const ART = {
    exploding: () => bg('ex', '#ff5a1f', '#a3141f') + rays(60, 50, 70, 12, '#ffb52e', .2) + halo(54, 60, 42, '#ffe66b', .35) + burst(54, 60, 46, 30, 10, '#ffb52e') +
      bigBomb(54, 66, 1.9) + cat({ x: 98, y: 24, s: .45, rot: 20, fur: '#17131f', ear: '#ff5a7a', eyes: 'wide', mouth: 'open', body: false, tail: false }),
    zombie: () => bg('zo', '#2a1a55', '#4b2a7a') + dots('zo', '#b6f23a', .25) + moon(104, 18, 14) + halo(52, 56, 42, '#86c440', .28) +
      tomb(100, 62, 1.5) + ground(78, '#2c4a1e') +
      cat(Object.assign({ x: 50, y: 56, s: 1.25, body: true, eyeL: 'x', eyeR: 'slit', mouth: 'fangs', extra: stitch }, Z)) +
      `<g transform="translate(92 78) rotate(12)"><rect x="-6" y="-14" width="12" height="30" rx="6" fill="${Z.fur}"/><circle cy="-17" r="8.5" fill="${Z.fur}"/><circle cx="-6" cy="-26" r="3.6" fill="${Z.fur}"/><circle cx="0" cy="-28.5" r="3.6" fill="${Z.fur}"/><circle cx="6" cy="-26" r="3.6" fill="${Z.fur}"/><ellipse cy="-16" rx="4.5" ry="3.6" fill="#3f6b17"/></g>`,
    attack: () => bg('at', '#ff9a2e', '#d6362b') + stripes('at', '#fff', .14) + halo(74, 52, 40, '#ffe14a', .3) +
      `<g stroke="#fff" stroke-width="7" stroke-linecap="round" fill="none"><path d="M8 12 q26 30 16 76"/><path d="M26 8 q26 30 16 76"/><path d="M44 10 q24 28 15 70"/></g>` +
      cat({ x: 82, y: 54, s: 1.15, rot: -14, fur: '#2b2342', eyes: 'angry', eye: '#ffe14a', mouth: 'fangs' }),
    attack_dead: () => bg('ad', '#23401c', '#0f2212') + dots('ad', '#b6ff3a', .22) + halo(60, 54, 42, '#b6ff3a', .2) +
      cat({ x: 16, y: 62, s: .8, fur: '#0b160c', ear: '#0b160c', nose: '#0b160c', line: '#0b160c', eyes: 'glow', eye: '#b6ff3a', mouth: 'none', body: false, tail: false }) +
      cat({ x: 104, y: 62, s: .8, fur: '#0b160c', ear: '#0b160c', nose: '#0b160c', line: '#0b160c', eyes: 'glow', eye: '#b6ff3a', mouth: 'none', body: false, tail: false }) +
      cat(Object.assign({ x: 60, y: 58, s: 1.1, eyeL: 'slit', eyeR: 'x', mouth: 'fangs', extra: stitch + `<rect x="-33" y="6" width="9" height="26" rx="4.5" fill="${Z.fur}" transform="rotate(-28 -28 20)"/><rect x="24" y="6" width="9" height="26" rx="4.5" fill="${Z.fur}" transform="rotate(28 28 20)"/>` }, Z)),
    nope: () => bg('no', '#ff5468', '#9c1235') + rays(60, 50, 70, 10, '#fff', .16) + halo(60, 50, 44, '#fff', .18) +
      stopSign(60, 50, 1) + `<text x="60" y="60" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="26" fill="#fff">NOP</text>` +
      cat({ x: 18, y: 84, s: .5, rot: -14, fur: '#f1e6d2', ear: '#ff9fbf', eyes: 'closed', mouth: 'flat', line: '#3a2a2a', body: false, tail: false }),
    skip: () => bg('sk', '#39b8ff', '#2a4fd6') + stripes('sk', '#fff', .15) + halo(60, 48, 40, '#fff', .25) +
      `<path d="M10 80 q50 -80 96 -6" stroke="#fff" stroke-width="4" stroke-dasharray="6 8" fill="none" stroke-linecap="round"/><path d="M106 74 l-18 -4 l6 14 z" fill="#fff"/>` +
      cat({ x: 62, y: 52, s: 1.05, rot: 28, fur: '#ffb13d', ear: '#ff6f91', eyes: 'closed', line: '#5a2a00' }),
    super_skip: () => bg('ss', '#7b3cff', '#28106e') + rays(60, 50, 70, 10, '#ffe66b', .18) + halo(66, 50, 40, '#ffe66b', .22) +
      `<g stroke="#ffe66b" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" fill="none"><path d="M6 26 l16 12 -16 12"/><path d="M24 26 l16 12 -16 12"/><path d="M42 26 l16 12 -16 12"/></g>` +
      cat({ x: 78, y: 54, s: 1.05, rot: 40, fur: '#ffb13d', ear: '#ff6f91', eyes: 'angry', eye: '#fff', line: '#5a2a00', tail: false, under: `<path d="M-14 6 q-34 30 -8 62 q10 -14 22 -8 q8 -14 22 -8 q2 -34 -22 -46 z" fill="#e11d2e"/>` }),
    see_future: () => bg('sf', '#b34cff', '#3c1273') + dots('sf', '#ffd6ff', .25) + halo(60, 52, 42, '#8ff2ff', .3) +
      `<circle cx="60" cy="52" r="38" fill="#c9f8ff" opacity=".55" stroke="#e9fdff" stroke-width="3"/>` +
      mini(44, 56, -18, '#ffe14a') + mini(76, 56, 18, '#7ee06a') + mini(60, 54, 0, '#fff', `<text y="7" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="18" fill="#3c1273">?</text>`) +
      `<path d="M34 94 q26 -14 52 0 z" fill="#ffc93a"/><rect x="40" y="84" width="40" height="8" rx="4" fill="#e0a21c"/>` +
      cat({ x: 16, y: 82, s: .42, rot: -16, fur: '#2b2342', body: false, tail: false }) + cat({ x: 104, y: 82, s: .42, rot: 16, fur: '#2b2342', body: false, tail: false }),
    shuffle: () => bg('sh', '#22d3b4', '#0c6b7a') + stripes('sh', '#fff', .15) + halo(60, 50, 42, '#fff', .25) +
      fan(60, 52, '#ffe14a', '#ff7fb0', '#fff') +
      `<g fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round"><path d="M16 14 q44 -18 88 0"/><path d="M104 88 q-44 18 -88 0"/></g><path d="M106 8 l0 16 -14 -8 z M14 94 l0 -16 14 8 z" fill="#fff"/>`,
    feed_dead: () => bg('fd', '#c9d64a', '#5d7a1c') + dots('fd', '#fff', .22) + halo(44, 52, 38, '#86c440', .3) +
      cat(Object.assign({ x: 42, y: 54, s: 1.1, eyeL: 'wide', eyeR: 'x', mouth: 'open', extra: stitch }, Z)) +
      bigBone(84, 54, .85, -24),
    clone: () => bg('cl', '#5fe0ff', '#1d6fb8') + rays(60, 50, 70, 10, '#fff', .16) + halo(60, 50, 44, '#fff', .2) +
      `<path d="M60 4 v92" stroke="#fff" stroke-width="3" stroke-dasharray="8 8" opacity=".8"/><g fill="#fff"><circle cx="60" cy="18" r="4"/><circle cx="60" cy="50" r="4"/><circle cx="60" cy="82" r="4"/></g>` +
      cat({ x: 30, y: 54, s: .95, fur: '#ff8a3d', ear: '#ffd0a8', line: '#5a2a00' }) +
      `<g opacity=".85">` + cat({ x: 90, y: 54, s: .95, fur: '#39e6c9', ear: '#bafff2', eye: '#fff', line: '#0c4d57', nose: '#0c6b7a' }) + `</g>`,
    grave_robber: () => bg('gr', '#3a3a6e', '#17152e') + dots('gr', '#9fe8ff', .2) + halo(40, 52, 38, '#cfd4e6', .2) +
      ground(80, '#2e2a1e') +
      cat({ x: 40, y: 54, s: 1.1, fur: '#2b2342', eyes: 'slit', eye: '#fff', extra: `<path d="M-28 -8 h56 v9 q-14 6 -28 0 q-14 6 -28 0 z" fill="#0d0b14" opacity=".92"/>` + eye(-11, 'slit', '#ffe14a') + eye(11, 'slit', '#ffe14a') }) +
      bigShovel(100, 44, 1, 28),
    favor: () => bg('fa', '#ff9fd0', '#e0457e') + rays(60, 46, 70, 10, '#fff', .18) + halo(60, 46, 40, '#fff', .3) +
      bigHeart(64, 42, 1.15) +
      cat({ x: 20, y: 86, s: .55, rot: -12, fur: '#fff5e6', ear: '#ff9fbf', eyes: 'big', mouth: 'sad', line: '#5a3a3a', body: false, tail: false }),
    dig_deeper: () => bg('dd', '#ffcf6b', '#e0862e') + stripes('dd', '#6b4226', .16) + `<rect y="52" width="120" height="48" fill="#6b4226"/><path d="M0 52 q30 -6 60 0 t60 0 v6 h-120 z" fill="#58a83a"/>` +
      halo(52, 66, 34, '#ffe14a', .3) +
      `<g transform="translate(48 70) scale(1.5)">` + mini(0, 0, -10, '#fff', `<text y="7" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="18" fill="#6b4226">1</text>`) + `</g>` +
      `<g transform="translate(76 78) scale(1.5)">` + mini(0, 0, 10, '#ffe14a', `<text y="7" text-anchor="middle" font-family="Bangers,Impact,sans-serif" font-size="18" fill="#6b4226">2</text>`) + `</g>` +
      bigShovel(100, 44, 1, 28) +
      cat({ x: 22, y: 28, s: .55, rot: -18, fur: '#2b2342', body: false, tail: false }),
    clairvoyance: () => bg('cv', '#2747c9', '#0b1247') + dots('cv', '#9fe8ff', .25) + halo(60, 48, 42, '#49e0e6', .25) +
      bigEye(60, 46, 104, 52, 20) +
      `<path d="M40 68 l20 10 l20 -10" stroke="#9fe8ff" stroke-width="2.5" fill="none" stroke-dasharray="3 5" stroke-linecap="round"/>` + bomb(60, 88, .7),
    cat_a: () => bg('ca', '#ffe7a3', '#e0a84a') + stripes('ca', '#c98a2e', .2) + halo(60, 52, 42, '#fff', .3) +
      cat({ x: 60, y: 54, s: 1.25, fur: '#efe6cf', ear: '#d9c9a3', eyeL: 'slit', eyeR: 'slit', eye: '#7ee06a', nose: '#b89f6e', line: '#6b5a36', mouth: 'flat',
        extra: `<g stroke="#b8a878" stroke-width="5" fill="none" opacity=".9"><path d="M-28 -6 q28 -10 56 0 M-28 6 q28 8 56 0 M-28 18 q28 8 56 0 M-24 -16 q24 -6 48 0" stroke="#b8a878" stroke-width="5" fill="none" opacity=".9"/></g>` }),
    cat_b: () => bg('cb', '#8a1f4f', '#2a0a2e') + rays(60, 50, 70, 10, '#ff4d5e', .16) + halo(60, 52, 42, '#c2182b', .3) +
      `<path d="M10 16 q8 -10 16 0 q6 -6 12 0 q-4 4 -8 8 q-4 -6 -8 -4 q-6 -2 -12 -4 z" fill="#17131f"/>` +
      `<path d="M22 18 q38 -16 76 0 q10 40 -6 66 q-4 -26 -14 -34 q-6 18 -18 24 q-12 -6 -18 -24 q-10 8 -14 34 q-16 -26 -6 -66 z" fill="#c2182b"/>` +
      cat({ x: 60, y: 54, s: 1.15, fur: '#2b2342', ear: '#e11d2e', eye: '#ff4d5e', mouth: 'fangs' }),
    cat_c: () => bg('cc', '#6b7cff', '#2a2a7a') + dots('cc', '#fff', .22) + moon(100, 16, 14) + halo(60, 54, 42, '#fff', .28) +
      `<g transform="translate(60 54)"><ellipse cx="0" cy="42" rx="30" ry="5" fill="#000" opacity=".3"/><path d="M-34 36 v-38 a34 32 0 0 1 68 0 v36 q-5.5 -10 -11 0 q-5.5 10 -11 0 q-5.5 -10 -11 0 q-5.5 10 -11 0 q-5.5 -10 -11 0 q-5.5 -10 -12 0 z" fill="#f4f7ff"/><path d="M-34 36 v-38 a34 32 0 0 1 10 -22 v54 q-5 -5 -10 6 z" fill="#c9d2ff" opacity=".7"/><ellipse cx="-12" cy="-4" rx="7" ry="9" fill="#1b1b4a"/><ellipse cx="12" cy="-4" rx="7" ry="9" fill="#1b1b4a"/><circle cx="-14" cy="-6" r="2.5" fill="#fff"/><circle cx="10" cy="-6" r="2.5" fill="#fff"/><path d="M-4 8 h8 l-4 5 z" fill="#ff86b3"/><ellipse cx="0" cy="18" rx="5" ry="6" fill="#1b1b4a"/><ellipse cx="-23" cy="8" rx="5" ry="3" fill="#ff9fbf" opacity=".6"/><ellipse cx="23" cy="8" rx="5" ry="3" fill="#ff9fbf" opacity=".6"/></g>`,
    cat_d: () => bg('cd', '#3b3b4f', '#111118') + stripes('cd', '#7ee06a', .12) + halo(60, 52, 42, '#7ee06a', .22) +
      cat({ x: 60, y: 52, s: 1.25, fur: '#f1efe6', ear: '#17131f', nose: '#17131f', line: '#17131f', eyes: 'none', mouth: 'none',
        extra: `<ellipse cx="-11" cy="-2" rx="9" ry="10" fill="#17131f"/><ellipse cx="11" cy="-2" rx="9" ry="10" fill="#17131f"/><circle cx="-11" cy="-1" r="3.4" fill="#7ee06a"/><circle cx="11" cy="-1" r="3.4" fill="#7ee06a"/><path d="M-10 16 h20 M-7 13 v7 M-2 13 v7 M3 13 v7 M8 13 v7" stroke="#17131f" stroke-width="2.4" stroke-linecap="round"/><g stroke="#17131f" stroke-width="4" stroke-linecap="round" fill="none"><path d="M0 26 v22 M-14 30 q14 6 28 0 M-15 38 q15 6 30 0 M-14 46 q14 6 28 0"/></g>` }),
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
