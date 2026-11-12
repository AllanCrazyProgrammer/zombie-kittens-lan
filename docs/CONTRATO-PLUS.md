# Contrato técnico — Zombie Kittens Plus (T01)

Decisiones cerradas que todas las tareas deben seguir. Si una tarea necesita algo que aquí no está,
se detiene y lo pregunta al orquestador; no lo inventa.

## 1. Dos modos en la misma app

| | Clásico | Plus |
| --- | --- | --- |
| Qué es | El juego 2.2.0 tal como está hoy | Todo lo nuevo de `ESPECIFICACION-MEJORAS.md` |
| Reglas | 19 cartas, sin opciones nuevas | Cartas de «La Cripta» y reglas opcionales |
| Pantalla de partida | `GameScreen` actual, **congelada** | `PlusGameScreen` |
| IA | Comportamiento actual | Heurísticas nuevas |
| Red | Compatible con clientes 2.x | Exige `proto >= 3` |

**Regla de oro (P-0): con `plus = false` el juego se comporta exactamente igual que hoy** — mismas
reglas, misma pantalla, mismos mensajes de red, mismas decisiones de la IA.

### 1.1 Archivos congelados

No se modifican (salvo corrección pedida expresamente por el usuario):

- `godot/scripts/table/game_screen.gd`
- `web/www/*`, excepto añadir entradas de datos de cartas nuevas en `cards.js` (lo usa el generador de texturas)
- `godot/tests/traces.json`

### 1.2 Archivos compartidos: solo cambios aditivos

`zk_game.gd`, `zk_bots.gd`, `room_host.gd`, `client_session.gd`, `game_session.gd`, `local_match.gd`,
`net.gd`, `main.gd`, `menu_screen.gd`, `info_screen.gd`, `card_db.gd`, `card_3d.gd`, `vfx.gd`,
`table_world.gd`, `sfx.gd`, `ui_kit.gd`.

En ellos todo lo nuevo va detrás de `plus` o en funciones/parámetros nuevos con valor por defecto que
conserva el comportamiento actual. Prohibido cambiar la firma o el resultado de una función existente
cuando `plus = false`.

### 1.3 Código nuevo

- `godot/scripts/plus/` — todo el código exclusivo de Plus. La pantalla empieza como copia de
  `game_screen.gd` con `class_name PlusGameScreen` y a partir de ahí evoluciona por separado.
- `godot/data/cards.json` — las cartas nuevas llevan `"pack": "crypt"`. Las 19 actuales no llevan `pack`.
- `CardDB.types()` sigue devolviendo **solo** las cartas sin `pack` (la pantalla clásica la usa para
  el trío y la guía). Nuevo: `CardDB.types_for(packs: Array)` devuelve base + las de esos packs.

### 1.4 Cómo se elige el modo

- Pantalla de inicio: selector de dos posiciones **CLÁSICO / PLUS** encima de los botones. Se guarda en
  `user://settings.cfg`, sección `game`, clave `plus` (por defecto `false`). En Plus el título muestra
  «Zombie Kittens Plus» y los botones del menú no cambian de sitio.
- Un jugador: `opts.plus` viaja de `MenuScreen` → `main.gd` → `LocalMatch.start`.
- Sala: el modo se fija al **crear** la sala con el modo que tenga el anfitrión (`settings.plus`), y no
  cambia después. Quien se une adopta el modo de la sala, sea cual sea su selector.
- `GameSession.is_plus() -> bool` (por defecto `false`): `LocalMatch` devuelve `opts.plus`;
  `ClientSession` devuelve `lobby.settings.plus`.
- `main.gd._open_game()` crea `PlusGameScreen` si `_session.is_plus()`, si no `GameScreen`.
  Ambas exponen las mismas señales (`exit_requested`, `rematch_requested`, `lobby_requested`) y
  métodos que usa `main.gd` (`setup`, `notice`, `debug_*`, `coach`).
- Las opciones exclusivas de Plus (pack, reglas) solo se muestran en el menú cuando el modo es Plus.

## 2. Motor (`ZKGame`)

### 2.1 Opciones

```gdscript
ZKGame.new({
    players, deck_mode, rng|rnd, cfg, now,      # como hoy
    plus = false,                                # nuevo
    packs = [],                                  # ["crypt"]; se ignora si plus = false
    rules = {},                                  # ver 2.7; se ignora si plus = false
    names = {},                                  # {tipo: nombre} de las cartas de packs (el motor no lee CardDB)
})
```

Con `plus = false` no se lee ninguna variable nueva en ninguna rama que consuma azar o cambie estado.

### 2.2 Estado nuevo

| Variable | Tipo | Inicial | Significado |
| --- | --- | --- | --- |
| `plus` | bool | false | Modo |
| `packs` | Array | [] | Packs activos |
| `dir` | int | 1 | Sentido de juego (+1 / −1) |
| `tops` | int | 0 | Cartas retiradas de **arriba** del mazo desde el último cambio de `shuf` |
| `deck_types` | Array[String] | — | Tipos presentes en esta partida (se calcula en `_setup`, sin `exploding`) |

- `next_living_idx(from)` avanza con `dir`. Con `dir = 1` es idéntico al actual.
- `tops` se incrementa en cada `draw.pop_back()` y vuelve a 0 cada vez que `shuf` aumenta. Se mantiene
  siempre (no afecta a nada en clásico).
- `DECK_CRYPT` con el mismo formato que `DECK`. En `_setup`, si `plus` y `"crypt"` en `packs`, sus
  filas se procesan **después** de las de `DECK` y antes del primer barajado. Tabla de copias: §3.1 de
  la especificación.

### 2.3 Objetivos (`need`)

| `need` | Jugadores válidos |
| --- | --- |
| `living` (existe) | vivo, no yo, con cartas |
| `dead` (existe) | muerto |
| `living_any` | vivo, no yo |
| `any_hand` | no yo, con cartas (vivo o muerto) |
| `dead_hand` | muerto, con cartas |

### 2.4 Cartas (todas pasan por `stack` y admiten Nop)

| Carta | `plan` exige | `_apply` |
| --- | --- | --- |
| `targeted_attack` | mi turno, vivo; `need: living_any` | Si no soy el jugador en turno al resolverse: nada. `n = (turns_left si attacked, si no 0) + 2`. Si el objetivo ya no vive: el siguiente vivo desde su asiento según `dir`. `cur = objetivo; turns_left = n; attacked = true; idle_since = now`. Emite `turn` y `attack {player, target, n}` |
| `reverse` | mi turno, vivo | Si soy el jugador en turno: `dir = -dir`; emite `reverse {dir}`; `_end_turn` |
| `draw_bottom` | mi turno, vivo | Si soy el jugador en turno: `c = draw.pop_front(); mut += 1` (no toca `tops`); emite `draw {player, bottom: true}`; `_receive(p, c)` |
| `crow_eye` | mi turno, vivo; `need: any_hand` | Evento privado `peek {target, cards: [tipos]}` a quien juega; evento `info` público «X mira la mano de Y» |
| `apocalypse` | mi turno, vivo | Saca todos los `exploding` de `draw`; `shuffle_arr(resto)`; `shuffle_arr(explosivos)`; los añade al final (arriba). `mut += 1; shuf += 1; tops = 0`. Emite `apocalypse {n}`. Si soy el jugador en turno: `_advance(1, false)` |
| `alter_future` | mi turno, vivo | Abre decisión `alter` (2.5) |
| `bury` | mi turno, vivo | `card = draw.pop_back(); mut += 1; tops += 1`; abre decisión `bury` (2.5) |
| `soul_swap` | mi turno, vivo; `need: dead_hand` | Si el objetivo sigue muerto y con cartas: intercambia los arrays `hand`. Emite `swap {player, target}` y `got` privado a cada uno con el número de cartas |
| `haunt` | **estar muerto**; sin decisión ni pila pendientes salvo las reglas de las cartas ⚡; `need: living` | Si el objetivo sigue vivo y con cartas: carta al azar (`rnd`) de su mano → `discard` con `by = objetivo`. Emite `haunt {player, target, card}` |

- `haunt` se añade a `NOW` solo en Plus. Un vivo que la juegue (o la clone) recibe
  «Solo los muertos pueden espantar».
- Clon: resuelve `eff` como hoy; después se aplican las condiciones de la carta copiada.
- Trío: en Plus `named` se valida contra `deck_types`.

### 2.5 Decisiones nuevas

```gdscript
# Alterar el Futuro. cards: hasta 3 cartas de arriba, la primera es la próxima. Siguen en el mazo.
prompt = {type: "alter", player, cards: [Card], start, deadline}
act(id, {a: "reorder", order: [int]})   # permutación de índices de `cards`; order[0] será la próxima
# → reescribe esas posiciones; mut += 1; shuf += 1; tops = 0;
#   evento privado `future` con el orden nuevo; prompt = null; _settle. NO termina el turno.
# Plazo vencido: order = identidad.

# Entierro. La carta ya salió del mazo.
prompt = {type: "bury", player, card: Card, start, deadline}
act(id, {a: "bury", pos: int})          # 0 = arriba … draw.size() = fondo
# → draw.insert(draw.size() - pos, card); mut += 1; shuf += 1; tops = 0;
#   evento privado `buried {pos, len}`; evento público info; prompt = null; _end_turn; _settle.
# Plazo vencido: pos al azar con `rnd`.
```

Ambas usan `_dl([player], now)` y deben estar cubiertas en `view`, `_auto_prompt`, `signature` y
`set_connected`. En `view`, `cards` / `card` solo se incluyen (como tipos) si `mine`.

### 2.6 Vista y eventos

Con `plus = false`, `view()` devuelve exactamente las mismas claves y valores que hoy. Con `plus = true` añade:

| Clave | Valor |
| --- | --- |
| `plus` | `true` |
| `packs` | packs activos |
| `dir` | sentido |
| `deckTypes` | tipos de esta partida |
| `tops`, `shuf` | contadores para la vigencia de lo que el jugador sabe del mazo |
| `discard` | últimas 20 entradas en lugar de 5 |
| `rules` | reglas activas |

Eventos: en Plus, `future`, `clair` e `inserted` añaden `tops`. Eventos nuevos: `reverse`, `peek`
(privado), `apocalypse`, `swap`, `haunt`, `buried` (privado). `draw` puede llevar `bottom: true`.
`signature()` añade `dir` solo en Plus.

### 2.7 Reglas opcionales (fase 5)

`rules = {turn_ms: 0, nope_fixed: false, hand: 7, sudden_death: false}`. Se traducen a `cfg` en
`_init` solo si `plus`. Detalle en §4 de la especificación.

### 2.8 Gatito Putrefacto (`rotten`) — T60

**Activación.** Regla `rules.rotten` (bool, por defecto `false`). Solo tiene efecto con `plus`, el pack
`crypt` activo y 3 o más jugadores; en cualquier otro caso se ignora. Al repartir, uno de los `n − 1`
explosivos se sustituye por una carta de tipo `rotten`. `deck_types` no lo incluye (como `exploding`).

**Estado.** `Card.up: bool` (por defecto `false`). Solo el Putrefacto llega a tener `up = true`.

**Al recibirlo** (`_receive`, se comprueba antes que `exploding`; vale para cualquier forma de robar:
robo normal, Robar del Fondo, Cava Más Hondo):

| Estado | Efecto |
| --- | --- |
| Boca abajo (`up = false`) | No muere. Evento público `rot_found {player}`. Se abre la decisión `rot` |
| Boca arriba (`up = true`) | Muere al instante: no se abre `explode`, no valen Zombi ni Clon. Evento `boom {player, rotten: true}` y `_die`. La carta queda como su `ek` |

**Decisión `rot`.** `prompt = {type: "rot", player, card, start, deadline}`; acción
`{a: "rot", pos: int}` con la convención de `bury` (0 = arriba). Efecto: `card.up = true`; se inserta;
`mut += 1; shuf += 1; tops = 0`; evento público `rot_placed {player, depth, len}` (la posición es
pública); `_end_turn`. Plazo vencido: posición al azar. Cubierta en `view`, `_auto_prompt`,
`signature`, `set_connected`.

**Vista.** `rotDepth`: número de cartas por encima del Putrefacto si está en el mazo boca arriba; `-1`
en cualquier otro caso (boca abajo, en una decisión, frente a un muerto). Solo en Plus.

**Interacciones**

| Con | Regla |
| --- | --- |
| Barajar, Ladrón de Tumbas | Cambia de posición como cualquier carta; si está boca arriba sigue boca arriba y `rotDepth` refleja la nueva posición |
| Apocalipsis Zombi | Boca abajo: sube arriba junto con los explosivos. Boca arriba: se queda en el resto barajado, visible. El evento cuenta en `n` solo lo que subió |
| Ver / Alterar el Futuro | Aparece como `rotten` en la lista (tipo visible para quien mira, esté como esté). Alterar puede moverlo; conserva `up` |
| Cava Más Hondo | Si la primera carta es el Putrefacto: «me la quedo» aplica la tabla de arriba; «robar la siguiente» lo devuelve arriba sin cambiar `up` y roba la siguiente |
| Entierro | Lo entierra tal cual, sin voltearlo y sin efecto (igual que un explosivo). Boca arriba su posición sigue siendo pública |
| Robar del Fondo | Aplica la tabla de arriba |
| Clon, Gatito Zombi | No intervienen: boca abajo no hay muerte que evitar; boca arriba no se permite jugar nada |
| Revivir | El `ek` del revivido vuelve al mazo como hoy (lo esconde quien revive, en secreto) y se pone `up = false` |
| Trío | No se puede nombrar |
| Muerte súbita | Nunca se retira (cuenta como explosivo) |
| Fin de partida y riesgo | Cuenta como un explosivo más: sigue habiendo `vivos − 1` cartas de peligro en juego |

**IA.** `rotDepth` es información pública. Con `rotDepth = 0` robar es muerte segura: todos los
niveles salvo fácil usan cualquier salida disponible (saltar, atacar, Robar del Fondo, Barajar,
Entierro, Alterar el Futuro) antes de robar. Con `rotDepth > 0` se trata como un explosivo de posición
conocida. Al colocarlo: fácil al azar; normal y difícil arriba si el siguiente en robar es un rival, al
fondo si vuelve a robar el propio bot.

## 3. IA (`ZKBots`)

`ZKBots.new(game, levels, rnd, plus := false)`. Toda heurística nueva (cartas de packs e IA-02) va
dentro de `if plus`. En Plus la memoria del mazo usa `tops` en lugar de `len − draw.size()`.

## 4. Red

- `Net.PROTO = 3`.
- `hello` añade `proto`. Sala Plus: si falta o es menor que 3 → `{t: "full", msg: "Esta sala es de
  Zombie Kittens Plus. Actualiza el juego para entrar."}`. Sala clásica: no se comprueba (los clientes
  2.x siguen entrando).
- Baliza: añade `plus` y `proto`. La lista de salas muestra una etiqueta «PLUS» o «CLÁSICO».
- `lobby.settings`: `{deck_mode, plus, packs, rules}`. En sala clásica `packs = []` y `rules = {}`
  y el anfitrión rechaza cambiarlos.
- Las acciones nuevas viajan por `act`. `emote` y `scores` (fase 5) solo existen en salas Plus.

## 5. Pruebas obligatorias

- Trazas actuales sin regenerar (clásico idéntico al motor JS).
- **Guardia del clásico:** una prueba que compare, para varias semillas, las claves de `view()` y la
  secuencia de eventos de una partida `plus = false` contra una grabación hecha **antes** de tocar el
  motor (se graba en T05).
- Todo lo de §9 de la especificación se ejecuta con `plus = true`.
- Prueba de toques: `--uitest` sigue cubriendo la pantalla clásica; `--uitest-plus` cubre la de Plus.
