# Zombie Kittens — Especificación de mejoras (v3.0)

Alcance: versión Godot (`godot/`, hoy 2.2.0). La versión web 1.x (`web/www/`) queda congelada como
referencia de reglas. Este documento define **qué** construir y **cómo encaja** en el código actual;
cada punto tiene criterios de aceptación para poder implementarlo y probarlo por separado.

Índice
1. Diagnóstico del juego actual
2. Principios y restricciones técnicas
3. Expansión «La Cripta»: 9 cartas nuevas + 1 peligro nuevo
4. Modos y opciones de sala
5. Mejoras de interacción (UX)
6. Mejoras visuales y de sonido
7. IA
8. Red y protocolo
9. Pruebas
10. Plan por fases
11. Anexo: lista de archivos a tocar al añadir una carta

---

## 1. Diagnóstico del juego actual

### 1.1 Qué hay

| Área | Estado | Dónde |
| --- | --- | --- |
| Reglas | 19 tipos de carta, Nop con pila, combos de 2/3, muertos que siguen jugando ⚡, revivir | `scripts/rules/zk_game.gd` |
| IA | 3 niveles; el difícil recuerda el mazo | `scripts/ai/zk_bots.gd` |
| Red | Sala LAN con anfitrión autoritativo, búsqueda automática, reconexión por ficha | `scripts/net/`, `scripts/autoload/net.gd` |
| Mesa | 3D, mano en abanico, arrastre al centro, carta en grande, historial, tutorial | `scripts/table/game_screen.gd` (1 725 líneas) |
| Efectos | Explosión, onda, zombi, cortes de ataque, confeti, cámara lenta, vibración | `scripts/vfx/vfx.gd`, `game_screen.gd` |
| Sonido | 16 efectos + 1 pista de música en bucle | `scripts/autoload/sfx.gd` |

### 1.2 Puntos fuertes (no tocar)

- Motor separado de la escena (`act` / `tick` / `view`), verificado paso a paso contra el motor JS con
  `tests/traces.json`. Es la base que permite añadir cartas con seguridad.
- La pantalla no contiene reglas: solo lee `view()` y envía acciones.
- La mecánica propia del juego (los muertos conservan la mano y siguen influyendo) funciona y es lo que
  lo distingue; las cartas nuevas deben apoyarse en ella.

### 1.3 Carencias detectadas

**Juego**
- D-01 · Casi todas las cartas actúan sobre el mazo o el turno. Solo Favor y los combos afectan a un
  rival concreto, así que hay poca interacción directa y pocas decisiones de «a quién».
- D-02 · Un jugador muerto solo tiene 4 cartas útiles (Nop, Barajar, Alimenta, Clarividencia). En
  partidas de 4–5 puede pasar minutos mirando.
- D-03 · El orden de turnos es fijo: no hay forma de alterar quién juega después salvo matar.
- D-04 · No hay opciones de partida más allá de «mazo oficial / completo».

**Interacción**
- D-05 · Elegir objetivo es una lista de botones en una ventana (`_build_modal`, tipo `target`), no se
  toca al rival sobre la mesa.
- D-06 · «Ver el Futuro» se muestra una vez y se pierde: no hay recordatorio, aunque el evento ya trae
  `mut`/`shuf`/`len` para saber si sigue vigente.
- D-07 · No se puede consultar el descarte (la vista solo envía las últimas 5 y la mesa dibuja 3). El
  Clon depende de la carta de arriba y el panel de selección no dice **qué** va a copiar.
- D-08 · El trío ofrece los 18 tipos como botones de texto, incluidos tipos que no existen en el mazo
  de esa partida (p. ej. Ataque de los Muertos en una partida oficial de 2).
- D-09 · Esconder el explosivo se hace con un deslizador numérico; es correcto pero poco legible.
- D-10 · Un humano conectado que no juega bloquea la mesa: solo hay plazo para jugadores
  desconectados (`GONE_MS`) y para decisiones (`PROMPT_MS`), no para el turno.
- D-11 · No hay comunicación entre jugadores (reacciones), ni marcador entre partidas de una sala, ni
  resumen al terminar.
- D-12 · Con 5 jugadores las fichas de rivales pierden el avatar (`if n <= 4`).

**Visual**
- D-13 · Un rival muerto solo se oscurece e inclina; su explosivo no se ve «frente a él» como dicen las
  reglas, y revivir no tiene transición propia del asiento.
- D-14 · El riesgo es una línea de texto gris; es el dato más importante de la partida.
- D-15 · La carta jugada va directa al descarte: no hay un momento en que la mesa vea qué se jugó y
  contra quién, y la ventana de Nop no tiene presencia en la mesa 3D.
- D-16 · La música no reacciona a la tensión.

**Técnico**
- D-17 · La duración de la ventana de Nop delata información: dura 6,5 s si alguien puede responder y
  0,9 s si nadie tiene Nop (`_open_window`). Un jugador atento deduce quién no tiene Nop.
- D-18 · No hay comprobación de versión entre anfitrión y cliente (`hello` no la envía). Con cartas
  nuevas, un cliente viejo recibiría tipos que no conoce.
- D-19 · `_update_hud` destruye y recrea todas las fichas, botones y ventanas en cada cambio de estado
  y en cada selección.
- D-20 · Por verificar: una `GameScreen` nueva empieza con `_seq = 0` y reproduce hasta 80 eventos
  guardados (sonidos, avisos, ventana de «futuro»). Afecta a quien reabre la app y vuelve con su ficha.
- D-21 · El README dice que la versión Godot «contiene solo la base»; está desactualizado.

---

## 2. Principios y restricciones técnicas

- R-1 · **El juego base no cambia.** Con la expansión apagada, `ZKGame` debe producir exactamente los
  mismos estados y consumir los mismos números aleatorios que hoy. `_test_traces` debe seguir pasando
  sin regenerar `traces.json`.
- R-2 · Todo lo nuevo se activa por opciones de partida (`opts.packs`, `opts.rules`), elegidas por el
  anfitrión en la sala y enviadas a todos en `lobby.settings`.
- R-3 · La expansión vive solo en Godot. `web/www/engine.js` no se modifica.
- R-4 · La interfaz sigue sin reglas: cualquier dato que necesite se añade a `view()`.
- R-5 · Información oculta: todo evento con datos privados lleva `to`; `view()` nunca incluye cartas
  ajenas salvo las marcadas como reveladas.
- R-6 · Todo debe ser jugable por los bots y terminar: cada decisión nueva tiene plazo y acción
  automática en `_auto_prompt`.
- R-7 · Rendimiento: objetivo 60 fps en calidad media en un Android de gama media; los efectos nuevos
  respetan `apply_quality`.

---

## 3. Expansión «La Cripta»

Se activa con `packs: ["crypt"]`. Las cartas se añaden con el mismo formato que `DECK`
(`[tipo, copias con huella, copias sin huella]`), así que el reparto por número de jugadores sale solo:
2 jugadores usan «con huella», 3 usan «sin huella», 4–5 usan ambas.

### 3.1 Resumen

| # | id | Nombre | Tipo | Huella / sin | 2 j | 3 j | 4–5 j | Coste |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `targeted_attack` | Ataque Dirigido | Acción | 0 / 1 | 0 | 1 | 1 | Bajo |
| 2 | `reverse` | Marcha Atrás | Acción | 0 / 1 | 0 | 1 | 1 | Bajo |
| 3 | `draw_bottom` | Robar del Fondo | Acción | 0 / 1 | 0 | 1 | 1 | Bajo |
| 4 | `crow_eye` | Ojo de Cuervo | Acción | 1 / 1 | 1 | 1 | 2 | Bajo |
| 5 | `apocalypse` | Apocalipsis Zombi | Acción | 0 / 1 | 0 | 1 | 1 | Bajo |
| 6 | `alter_future` | Alterar el Futuro (3x) | Acción | 1 / 1 | 1 | 1 | 2 | Medio |
| 7 | `bury` | Entierro | Acción | 0 / 1 | 0 | 1 | 1 | Medio |
| 8 | `soul_swap` | Trueque de Almas | Acción | 0 / 1 | 0 | 1 | 1 | Medio |
| 9 | `haunt` | Espanto | ⚡ solo muerto | 0 / 1 | 0 | 1 | 1 | Medio |
| 10 | `rotten` | Gatito Putrefacto | Peligro | — | 0 | 1 | 1 | Alto |

Cartas añadidas: +2 (2 j), +9 (3 j), +11 (4–5 j). Con 2 jugadores solo existen Ojo de Cuervo y Alterar el Futuro. El Putrefacto **sustituye** a un explosivo, no se suma.

Reglas comunes a todas, salvo que se indique lo contrario:
- Se pueden anular con Nop (pasan por `stack` como cualquier acción).
- El Clon puede copiarlas si la carta copiada sería jugable por ese jugador en ese momento.
- En pareja o trío se ignora su texto (regla actual de combos).

### 3.2 Ficha de cada carta

#### 1. Ataque Dirigido — `targeted_attack`
- **Texto corto:** «Termina tu turno sin robar. Elige quién juega 2 turnos seguidos.»
- **Efecto:** igual que Ataque (2x), pero el turno salta al jugador vivo elegido. Después de él, el
  orden continúa desde su asiento. Se apila como un ataque: `n = (turns_left si attacked) + 2`.
- **Motor:** `plan` devuelve `need: "living"` (cualquier vivo menos uno mismo, tenga o no cartas).
  `_apply`: `cur = índice del objetivo; turns_left = n; attacked = true`; emite `turn` y `attack`.
- **Casos límite:** si el objetivo murió antes de resolverse, pasa al siguiente vivo en el sentido de
  juego. No existe en partidas de 2 (sería un Ataque normal).
- **IA:** normal lo usa como Ataque contra un rival al azar; difícil elige al rival con más cartas o,
  si conoce que la carta de arriba es explosiva, al que no tiene Zombi conocido.
- **Aceptación:** tras resolverse, `view.cur` es el objetivo y `turnsLeft` es 2 (o pendientes + 2).

#### 2. Marcha Atrás — `reverse`
- **Texto corto:** «Invierte el sentido de juego y termina tu turno sin robar.»
- **Efecto:** cambia el sentido y termina **un** turno (como Saltar: si te atacaron, solo quita uno).
- **Motor:** nueva variable `dir` (+1 / −1) usada en `next_living_idx`. Se añade a `signature()` y a
  `view()` como `dir`. Con `dir = +1` el comportamiento es idéntico al actual (R-1).
- **Casos límite:** con 2 jugadores vivos equivale a Saltar. No existe en el mazo de 2.
- **Interfaz:** flecha de sentido en el tapete (ver V-06) y popup «¡MARCHA ATRÁS!».
- **Aceptación:** con 4 jugadores A→B→C→D, si B la juega, el siguiente turno es de A.

#### 3. Robar del Fondo — `draw_bottom`
- **Texto corto:** «Termina tu turno robando la carta de ABAJO del mazo.»
- **Efecto:** sustituye al robo normal de ese turno. Si es un explosivo, explota igual.
- **Motor:** `_apply` hace `draw.pop_front()` y llama a `_receive`. Emite `draw` con `bottom: true`.
- **Memoria del mazo:** hoy los bots y la interfaz calculan la profundidad con `len − draw.size()`,
  que supone que solo se quitan cartas de arriba. Se añade un contador `tops` (cartas retiradas de
  arriba desde el último barajado); el robo del fondo no lo incrementa. `future`, `clair` e
  `inserted` incluyen `tops` y la memoria usa `tops` en vez de `len`.
- **IA:** se juega cuando se sabe que la carta de arriba es explosiva, o con riesgo alto y sin
  Saltar/Ataque. El difícil no la usa si él mismo escondió un explosivo al fondo.
- **Aceptación:** el mazo pierde su primera carta (índice 0) y el recordatorio de futuro sigue vigente.

#### 4. Ojo de Cuervo — `crow_eye`
- **Texto corto:** «Mira en secreto la mano completa de otro jugador.»
- **Efecto:** el jugador ve todas las cartas del objetivo (vivo o muerto). El objetivo se entera de
  que lo miraron, no de qué se hizo con ello.
- **Motor:** `need: "any_hand"` (cualquier otro jugador con cartas). Evento privado
  `peek {to, target, cards: [tipos]}` y evento público con texto «X mira la mano de Y».
- **Interfaz:** ventana tipo «futuro» con las cartas del rival en miniatura; queda en el historial
  como entrada privada (verde).
- **Sinergia:** prepara un trío (nombrar una carta que sabes que tiene) o un Trueque de Almas.
- **IA:** el difícil guarda lo visto y lo usa para nombrar en tríos; normal no la prioriza.

#### 5. Apocalipsis Zombi — `apocalypse`
- **Texto corto:** «Baraja el mazo y pon TODOS los explosivos arriba. Tu turno termina sin robar.»
- **Efecto:** se sacan los explosivos (y el Putrefacto si está boca abajo), se baraja el resto y los
  explosivos se colocan arriba en orden aleatorio. Termina **todos** los turnos del jugador.
- **Motor:** `shuffle_draw()` + recolocación; `shuf += 1`; `_advance(1, false)`. Evento
  `apocalypse {n}` con texto «Los N explosivos están arriba del mazo».
- **Equilibrio:** una sola copia y solo con 3+ jugadores. Es información pública: todos saben que los
  próximos N robos explotan, lo que dispara una ronda de Saltar/Ataque/Barajar/Nop.
- **IA:** el difícil la juega si el siguiente jugador no es él y tiene al menos un Zombi o un Saltar
  de reserva; nunca si le quedan turnos pendientes que no pueda saltar.
- **Aceptación:** tras resolverse, las N primeras cartas (`draw[-1]`…`draw[-N]`) son explosivos.

#### 6. Alterar el Futuro (3x) — `alter_future`
- **Texto corto:** «Mira en secreto las 3 cartas de arriba y reordénalas como quieras.»
- **Motor:** nueva decisión `prompt = {type: "alter", player, cards: [Card], deadline}`; las cartas no
  salen del mazo. Acción `{"a": "reorder", "order": [2, 0, 1]}` (permutación de índices; se valida
  tamaño y que no haya repetidos). Al confirmar: `mut += 1`, `shuf += 1` para invalidar la memoria de
  los demás, y evento privado `future` al jugador con el orden nuevo.
- **Plazo:** `PROMPT_MS`; al vencer se deja el orden original.
- **Vista:** `prompt.cards` solo se envía si `mine`.
- **Interfaz:** tres cartas grandes que se arrastran para reordenar, con etiquetas PRÓXIMA / SEGUNDA /
  TERCERA fijas debajo; botón CONFIRMAR.
- **IA:** coloca el explosivo en la posición que le tocará al siguiente rival (teniendo en cuenta
  `turns_left`), o lo más abajo posible si va a seguir robando.

#### 7. Entierro — `bury`
- **Texto corto:** «Roba la carta de arriba, mírala y entiérrala en secreto donde quieras. Tu turno termina.»
- **Efecto:** la carta nunca entra en la mano. Si es un explosivo **no explota**: se entierra igual.
- **Motor:** `prompt = {type: "bury", player, card, deadline}`; acción `{"a": "bury", "pos": n}` con
  la misma convención de posiciones que `insert` (0 = arriba). `mut += 1`, `shuf += 1`, `_end_turn`.
  Evento público sin posición; el jugador recuerda la posición (memoria como `inserted`).
- **Plazo:** al vencer, posición al azar.
- **Interfaz:** reutiliza la ventana de esconder el explosivo (ver UX-06), mostrando la carta robada.
- **Equilibrio:** es un Saltar con información, más fuerte que Ver el Futuro si arriba hay un
  explosivo. Por eso solo 1–2 copias.

#### 8. Trueque de Almas — `soul_swap`
- **Texto corto:** «Intercambia tu mano completa con la de un jugador muerto.»
- **Efecto:** las dos manos cambian de dueño enteras. Requiere un muerto con al menos 1 carta.
- **Motor:** `need: "dead_hand"`. `_apply` intercambia los arrays `hand`. Evento público `swap`
  y eventos privados `got` resumidos («Recibiste 6 cartas») a ambos.
- **Casos límite:** si el muerto fue revivido antes de resolverse, no tiene efecto. Se puede anular.
- **Intención de diseño:** da valor a las manos de los muertos y crea una razón para **no** revivir a
  alguien (o para revivirlo antes de que le quiten la mano).
- **IA:** el difícil la juega si el muerto tiene más cartas que él y él no tiene Zombi.

#### 9. Espanto — `haunt`
- **Texto corto:** «Solo si estás MUERTO: elige a un vivo. Descarta una carta al azar de su mano.»
- **Efecto:** carta ⚡ que solo puede jugar un muerto. La carta descartada va boca arriba al descarte
  (todos la ven).
- **Motor:** se añade a `NOW`; `plan` exige `not p.alive` y `need: "living"` con cartas. `_apply`
  mueve una carta al azar del objetivo a `discard` con `by` = objetivo. Evento `haunt {player, target, card}`.
- **Clon:** un vivo no puede clonar un Espanto (error: «Solo los muertos pueden espantar»).
- **Interacción con el Clon ajeno:** la carta descartada pasa a ser la de arriba del descarte, así que
  el siguiente Clon la copia. Es intencional.
- **IA:** un bot muerto la juega contra el jugador vivo con más cartas en cuanto la mesa está libre.
- **Aceptación:** un jugador vivo ve el Espanto como no jugable con el motivo correcto.

#### 10. Gatito Putrefacto — `rotten` (peligro nuevo, fase aparte)
- **Texto corto:** «Boca abajo: no pasa nada, devuélvelo boca ARRIBA donde quieras. Boca arriba: mueres. Ni el Zombi te salva.»
- **Preparación:** con 3+ jugadores sustituye a uno de los explosivos.
- **Primera vez (boca abajo):** quien lo roba no muere; lo coloca en la posición que quiera, boca
  arriba. Su turno termina. Desde entonces **todos** ven a cuántas cartas está.
- **Segunda vez (boca arriba):** quien lo roba muere sin poder jugar Zombi ni Clon. El Putrefacto se
  queda frente a él como su explosivo. Si lo reviven, vuelve al mazo boca abajo (lo esconde quien revive).
- **Motor:** `Card` gana `up: bool`. `view()` añade `rotDepth` (cartas por encima, o −1 si está boca
  abajo o fuera del mazo). Barajar cambia su posición pero sigue visible. `_receive` trata `rotten`
  antes que `exploding`. Decisión nueva `prompt.type = "rot"` (reutiliza la interfaz de esconder).
- **Interfaz:** una carta con borde verde enfermizo asomando del lado del mazo a la altura que
  corresponde, y un contador «☣ en 4» junto al número del mazo.
- **IA:** el riesgo se calcula con certeza para esa carta; todos los niveles salvo fácil la evitan
  cuando `rotDepth` es 0.
- **Por qué va aparte:** toca reparto, robo, muerte, revivir, vista e interfaz del mazo. Debe entrar
  después de que las 9 cartas anteriores estén probadas.

### 3.3 Cambios generales del motor

| Cambio | Detalle |
| --- | --- |
| Opciones | `ZKGame.new({..., packs: [], rules: {}})`. Sin `packs`, `_setup` no toca nada nuevo |
| Mazo | `DECK_CRYPT` con el formato de `DECK`; se añade a `cards` **antes** del barajado del reparto solo si el pack está activo |
| Nombres | `NAMES` se completa desde `CardDB` en vez de duplicarse; el motor recibe los nombres en `opts` para seguir sin depender de nodos |
| `plan` | Nuevos `need`: `any_hand`, `dead_hand`. `living` admite la variante «sin exigir cartas» |
| Acciones | `reorder`, `bury`, `rot` en `act` |
| Decisiones | `alter`, `bury`, `rot` en `view`, `_auto_prompt`, `signature`, `set_connected` |
| Eventos | `peek`, `swap`, `haunt`, `apocalypse`, `reverse`; `draw.bottom` |
| Vista | `dir`, `packs`, `deckTypes` (tipos presentes en esta partida), `rotDepth`, `tops` |
| Trío | `named` se valida contra `deckTypes`, no contra todos los nombres |

### 3.4 Equilibrio

Añadir cartas seguras baja el riesgo por robo y alarga la partida. Objetivos medidos con simulaciones
de bots (500 partidas por configuración, ver §9):

- Duración media en turnos: no más de +20 % respecto al juego base con el mismo número de jugadores.
- Ningún asiento gana más de 5 puntos porcentuales por encima del reparto uniforme.
- Difícil contra fácil mantiene al menos la ventaja que tiene hoy.
- Resultado medido: reducir la mano inicial ALARGA la partida (hay menos cartas de reserva), así que no
  sirve como palanca. El ajuste aplicado es mano inicial 8 con el pack activo (si no hay `rules.hand`
  explícito) y una sola copia de Ataque Dirigido, Marcha Atrás, Robar del Fondo, Entierro y Espanto.
  Duración frente al clásico: aproximadamente 0–3 % con 2 jugadores, +7–12 % con 4, +13–16 % con 5 y
  +29–36 % con 3; este último NO cumple el objetivo de +20 % y queda como pendiente conocido.

---

## 4. Modos y opciones de sala

Opciones del anfitrión en la sala (y en «Un jugador»), enviadas en `lobby.settings.rules`:

| id | Opción | Valores | Por defecto | Efecto |
| --- | --- | --- | --- | --- |
| M-01 | `packs` | `[]`, `["crypt"]` | `[]` | Activa la expansión |
| M-02 | `turn_ms` | 0, 30 000, 60 000 | 0 | Tiempo por turno para humanos conectados; al vencer se roba automáticamente (resuelve D-10) |
| M-03 | `nope_fixed` | sí / no | no | Ventana de Nop de duración constante (3,5 s) haya o no Nop en la mesa (resuelve D-17) |
| M-04 | `hand` | 5, 7 | 7 | Mano inicial; 5 = «partida rápida» |
| M-05 | `sudden_death` | sí / no | no | Cuando quedan 2 vivos, cada vuelta completa se retira la carta del fondo del mazo si no es explosivo |

M-02 y M-03 cambian tiempos, no reglas; aun así se implementan como `cfg` para que con los valores por
defecto se cumpla R-1.

Marcador de sala (M-06): `RoomHost` cuenta victorias por jugador mientras la sala exista y las envía
en `lobby`. Se muestran en la sala y en la ventana de fin de partida.

---

## 5. Mejoras de interacción (UX)

Cada punto: problema → comportamiento → aceptación.

### UX-01 · Elegir objetivo tocando la mesa
- **Problema:** D-05.
- **Comportamiento:** al necesitar objetivo, la mesa entra en «modo puntería»: los asientos válidos se
  iluminan con un aro pulsante, los no válidos se atenúan, el panel inferior dice «Toca a un rival» y
  muestra CANCELAR. Tocar un avatar o su ficha superior confirma. Mientras se lleva una carta
  arrastrada, soltarla sobre un rival válido la juega contra él directamente.
- **Técnico:** cada asiento recibe un `Area3D`; las fichas superiores pasan a ser botones. La ventana
  de lista se conserva como alternativa de accesibilidad (ajuste «Elegir objetivo en lista»).
- **Aceptación:** Favor contra un rival se completa en 2 toques (carta → rival) o en 1 arrastre.

### UX-02 · Recordatorio del futuro
- **Problema:** D-06.
- **Comportamiento:** tras Ver/Alterar el Futuro, Clarividencia, Entierro o esconder un explosivo
  propio, aparece junto al mazo una tira de hasta 3 miniaturas con lo que el jugador sabe de las
  próximas cartas. Se actualiza al robarse cartas (se desplaza) y desaparece cuando el mazo se baraja
  o cambia de forma que invalida el dato (`shuf` distinto). Tocarla la muestra en grande.
- **Técnico:** la interfaz guarda `{at, tops, shuf}` igual que `ZKBots._mem` y lo compara con la vista.
- **Aceptación:** veo el futuro, cierro la ventana, un rival roba: la tira muestra las 2 cartas
  restantes. Alguien baraja: la tira desaparece.

### UX-03 · Ver el descarte y qué copia el Clon
- **Problema:** D-07.
- **Comportamiento:** tocar la pila de descarte abre una lista con las cartas jugadas, la más reciente
  arriba, con quién la jugó. Al seleccionar un Clon, el panel dice «Copiará: Saltar» (o por qué no
  puede copiar la carta de arriba).
- **Técnico:** `view.discard` pasa de 5 a las últimas 20 entradas. El descarte es información pública.
- **Aceptación:** con un Ataque arriba del descarte, el panel del Clon muestra «Copiará: Ataque (2x)».

### UX-04 · Trío: elegir carta con imágenes
- **Problema:** D-08.
- **Comportamiento:** cuadrícula de miniaturas de carta (3 columnas, desplazable) solo con los tipos
  de `view.deckTypes`. Si el jugador usó Ojo de Cuervo sobre ese rival, las cartas vistas aparecen
  primero bajo «Sabes que tiene».
- **Aceptación:** en una partida oficial de 2 jugadores no se ofrece Ataque de los Muertos.

### UX-05 · Ventana de Nop más clara
- **Comportamiento:** mientras hay una jugada en la pila, la carta jugada se queda flotando sobre el
  centro de la mesa (ver V-02) con un anillo de tiempo alrededor. El botón ¡NOP! muestra cuántos Nop
  tiene el jugador («¡NOP! ×2»). Si el jugador no tiene Nop, no ve botones.
  Nuevo ajuste local «Dejar pasar automáticamente cuando la jugada no me afecta» (desactivado por
  defecto): envía `pass` si la jugada no lo tiene como objetivo ni es un ataque hacia él.
- **Aceptación:** con el ajuste activo, un Barajar ajeno no pide respuesta.

### UX-06 · Esconder el explosivo con un mazo visual
- **Problema:** D-09.
- **Comportamiento:** en lugar del deslizador, un mazo dibujado de perfil con un hueco que se arrastra
  arriba y abajo; el texto actual («Debajo de 3 cartas…») se conserva. Los atajos Arriba / Segunda /
  Al azar / Fondo se mantienen. Si hay recordatorio del futuro, las cartas conocidas se marcan en el
  perfil. Se reutiliza para Entierro y Putrefacto.
- **Aceptación:** se puede colocar en cualquier posición de un mazo de 40 cartas con precisión de 1.

### UX-07 · Tiempo de turno visible
- **Depende de:** M-02.
- **Comportamiento:** con `turn_ms` activo, el panel de turno muestra una barra; a los 10 s finales
  parpadea en rojo, suena `alarm` una vez y vibra. Para los rivales, la barra se ve en la ficha del
  jugador en turno.

### UX-08 · Reacciones rápidas
- **Problema:** D-11.
- **Comportamiento:** botón 😼 junto a HISTORIAL abre 6 reacciones (😹 🙀 😾 💀 🙏 👏). La reacción
  aparece como globo sobre el avatar del emisor durante 2 s para todos. Límite: 1 cada 3 s por
  jugador. Los muertos pueden usarlas. Ajuste para silenciarlas.
- **Técnico:** mensaje de sala `{t: "emote", e: n}` que `RoomHost` reenvía; no pasa por el motor ni
  por el historial. Los bots reaccionan a veces (al explotar un rival, al recibir un Nop).

### UX-09 · Resumen de fin de partida
- **Comportamiento:** la ventana final muestra, por jugador: posición, veces que explotó, veces
  revivido, Nops jugados, cartas robadas a otros. Debajo, el marcador de sala (M-06). Botones actuales.
- **Técnico:** contadores en la interfaz a partir de los eventos (no hace falta tocar el motor).

### UX-10 · Fichas de rivales
- **Problema:** D-12, D-19.
- **Comportamiento:** fichas persistentes que se actualizan en lugar de recrearse; con 5 jugadores se
  usa avatar pequeño en vez de quitarlo. La ficha muestra iconos de estado: ☠ muerto, ⚔×N turnos
  pendientes, 📶 sin conexión, y un destello cuando ese jugador es objetivo de la jugada en curso.
- **Aceptación:** seleccionar una carta no provoca la recreación de las fichas.

### UX-11 · Ordenar la mano
- **Comportamiento:** ajuste local con 2 opciones: «Por tipo» (actual) y «Por momento de uso»
  (Zombi y Nop a la izquierda, acciones, ⚡, gatos). Las cartas que forman pareja o trío llevan una
  marca pequeña en la esquina para verlos sin seleccionar.

### UX-12 · Historial con iconos
- **Comportamiento:** cada entrada lleva la miniatura de la carta implicada y el avatar de quien
  actuó. Filtro «Solo lo mío». Sin cambios en el motor.

### UX-13 · Accesibilidad y ajustes
- Tamaño de texto de la interfaz: normal / grande.
- Vibración: sí / no (hoy siempre activa).
- Reducir movimiento: sin sacudidas de cámara, sin cámara lenta, sin destellos a pantalla completa.
- Las cartas ⚡ y las jugables no dependen solo del color: llevan icono y borde distinto.

### UX-14 · Tutorial ampliado
- Consejos nuevos para: modo puntería, recordatorio del futuro, descarte, y uno por cada carta de la
  expansión la primera vez que llega a la mano (texto = `short` de la carta + cuándo conviene).
- Los consejos vistos se guardan en `user://settings.cfg` para no repetirse entre partidas.

### UX-15 · Corrección: eventos antiguos al abrir la pantalla
- **Problema:** D-20 (verificar primero con una prueba: reconectar con una app recién abierta).
- **Comportamiento:** al crear `GameScreen`, los eventos existentes se registran en el historial pero
  no disparan sonidos, popups ni ventanas; solo los posteriores a la primera vista.

---

## 6. Mejoras visuales y de sonido

### V-01 · Medidor de riesgo
Sustituye la línea de texto (D-14). Una mecha horizontal bajo las fichas: verde < 15 %, amarillo
15–30 %, naranja 30–50 %, rojo > 50 %, con chispa animada en el extremo y el porcentaje encima. Al
cruzar un umbral hacia arriba, pulso breve y sonido `fuse` suave. El texto «N explosivos en M cartas»
queda en pequeño debajo.

### V-02 · Carta jugada en escena
Toda carta jugada pasa 0,6 s (o lo que dure la ventana de Nop) flotando e inclinada hacia la cámara
sobre el centro de la mesa, a tamaño ×1,4, antes de caer al descarte. Si tiene objetivo, un haz de luz
del color de la carta va del jugador al objetivo. Si la anulan, la carta se rompe en dos mitades con un
sello «NOP» rojo; si un segundo Nop la restaura, se recompone con destello verde.

### V-03 · Asientos de los muertos
Al morir: el avatar se hunde y en su lugar sube una lápida (`tombstone.glb` ya existe) con su nombre;
su explosivo queda boca arriba delante. El avatar reaparece como fantasma translúcido flotando encima,
para recordar que sigue jugando ⚡. Al revivir: la lápida se parte, sale una mano verde y el avatar
vuelve con tinte verdoso durante el resto de la partida.

### V-04 · Efecto propio por carta
| Carta | Efecto |
| --- | --- |
| Ver / Alterar el Futuro | Las 3 cartas de arriba se levantan del mazo con brillo morado (solo quien juega ve las caras) |
| Barajar | Las cartas del mazo se abren en espiral y vuelven (sustituye al temblor actual) |
| Saltar / Súper Salto | El avatar del jugador da un salto; estela azul hacia el siguiente |
| Favor / pareja / trío | La carta robada viaja en arco con estela; al llegar a mi mano se voltea |
| Cava Más Hondo / Entierro | Montón de tierra y pala sobre el mazo |
| Alimenta a los Muertos | Las cartas vuelan en círculo hacia la lápida |
| Ladrón de Tumbas | Manos saliendo del suelo junto a cada lápida |
| Clon | La carta copia el aspecto de la carta de abajo con un efecto de escaneo |
| Ataque Dirigido | Los cortes actuales, orientados hacia el asiento del objetivo |
| Marcha Atrás | La flecha del tapete gira 180° |
| Ojo de Cuervo | Un cuervo cruza de un asiento al otro |
| Trueque de Almas | Dos remolinos de cartas se cruzan entre la lápida y el jugador |
| Espanto | El fantasma del muerto atraviesa al objetivo; una carta sale despedida al descarte |
| Apocalipsis Zombi | El cielo se pone rojo 2 s; los explosivos emergen del mazo y se apilan arriba |

Todos como funciones en `Vfx`, lanzados desde `_process_events`, con versión reducida en calidad baja.

### V-05 · Mazo vivo
El grosor del mazo refleja mejor las cartas reales (hoy se limita a 14 modelos: mantener el límite
pero escalar la altura). Con riesgo > 30 % el mazo emite humo leve; > 50 % tiembla cada pocos
segundos y la luz de la mesa vira a rojo.

### V-06 · Tapete con información
Flecha de sentido de juego alrededor del emblema (necesaria para Marcha Atrás; visible siempre que el
pack esté activo). Marcadores ⚔ frente al jugador atacado, uno por turno pendiente.

### V-07 · Cartas en mano
- Las jugables ahora mismo llevan un borde luminoso suave; las no jugables se oscurecen un 15 %.
- Al aparecer la ventana de Nop, los Nop de la mano se levantan solos.
- Robar: la carta vuela del mazo a la cámara, se voltea, se queda 0,4 s en grande y entra en la mano.
- Brillo tornasol (`FOIL`) también para Apocalipsis y Putrefacto.

### V-08 · Avatares con expresión
Los avatares 3D de la mesa reaccionan con poses sencillas (escala, giro, salto): susto al revelarse un
explosivo, celebración al sobrevivir, cabeceo al llegar su turno. Sin nuevos modelos.

### V-09 · Ambiente
Niebla baja animada en el cementerio, relámpago ocasional de fondo con riesgo alto, y variación de la
luna por partida. Opcional: 2 tapetes alternativos elegibles en ajustes.

### A-01 · Música por capas
La pista actual se separa en 3 capas generadas con `tools/audio/gen_audio.py` (base, percusión,
tensión). La capa de tensión entra con riesgo > 30 % y la percusión se acelera con > 50 % o durante
un ataque contra el jugador. Fundidos de 1 s.

### A-02 · Sonidos nuevos
Uno por carta nueva (9) más: reacción, tictac de últimos 10 s, lápida, cuervo. Volumen de música y de
efectos como deslizadores independientes en lugar de sí/no.

---

## 7. IA

- IA-01 · Usar las cartas nuevas según las heurísticas de §3.2 y añadirlas a `VALUE`
  (`apocalypse` 6, `targeted_attack` 6, `bury` 5, `alter_future` 5, `draw_bottom` 5, `soul_swap` 4,
  `reverse` 4, `crow_eye` 3, `haunt` 3).
- IA-02 · Carencias actuales a corregir de paso:
  - Ningún nivel juega Barajar para romper lo que un rival acaba de ver con Ver el Futuro.
  - Normal y difícil nunca juegan Alimenta a los Muertos; los bots muertos solo usan Nop y Clarividencia.
  - El Clon solo se usa para salvarse, nunca para copiar un Ataque o un Saltar.
  - Normal no hace tríos.
- IA-03 · Personalidad: cada bot recibe un rasgo fijo por nombre (agresivo, prudente, vengativo) que
  desplaza sus umbrales ±20 % y, en el vengativo, elige como objetivo a quien le robó o atacó último.
- IA-04 · Los bots usan reacciones (UX-08) con baja frecuencia.
- IA-05 · La IA sigue sin hacer trampa: solo usa su mano, los eventos públicos y los privados dirigidos a ella.

---

## 8. Red y protocolo

- N-01 · **Versión de protocolo.** `hello` incluye `proto: 3`. Si no coincide, `RoomHost` responde
  `{t: "full", msg: "Tu versión es distinta a la del anfitrión. Actualiza el juego."}`. La baliza de
  sala incluye `proto` y la lista de salas marca las incompatibles como no disponibles.
- N-02 · `lobby.settings` pasa a `{deck_mode, packs, rules}`; el mensaje `settings` del anfitrión
  acepta esos campos con validación de valores.
- N-03 · Mensajes nuevos: `emote` (cliente → anfitrión → todos) y `scores` dentro de `lobby`.
- N-04 · Las acciones nuevas (`reorder`, `bury`, `rot`) viajan por el `act` existente.
- N-05 · Tamaño de `state`: al ampliar `discard` a 20 entradas, comprobar que el mensaje sigue por
  debajo de 8 KB con 5 jugadores.

---

## 9. Pruebas

Todo en `godot/tests/run_tests.gd`, ejecutable sin ventana.

| Prueba | Qué comprueba |
| --- | --- |
| Trazas (existente) | Con `packs: []` todo sigue idéntico al motor JS. No se regenera `traces.json` |
| Unitarias por carta | Una función por carta nueva: caso normal, anulada con Nop, clonada, objetivo inválido, caso límite de su ficha |
| Conservación | En 2 000 partidas simuladas con el pack activo, el número total de cartas no cambia y ninguna está en dos sitios |
| Sin bloqueos | Ninguna partida supera 2 000 pasos; toda decisión nueva se resuelve sola al vencer su plazo |
| Información oculta | `view()` de un jugador nunca contiene cartas de `alter`/`bury` ajenos ni manos ajenas; `peek` solo llega a su destinatario |
| Equilibrio | Informe de duración media, victorias por asiento y por nivel, base contra expansión (§3.4) |
| Sentido de juego | Con `dir = −1`, ataques, saltos y muertes avanzan al jugador correcto |
| Protocolo | Un `hello` con `proto` distinto es rechazado |
| Toques (`--uitest`) | Nuevos pasos: elegir objetivo tocando un asiento, abrir descarte, reordenar en Alterar el Futuro |

---

## 10. Plan por fases

Cada fase se puede publicar sola.

| Fase | Contenido | Tamaño | Depende de |
| --- | --- | --- | --- |
| 1 · Interacción | UX-01, UX-02, UX-03, UX-04, UX-10, UX-15, V-01, N-01 | Medio | — |
| 2 · Cartas I | `packs` + `dir` + `tops`; cartas 1–5; V-06; IA-01 parcial; pruebas | Medio | Fase 1 (UX-01 para objetivos, N-01) |
| 3 · Cartas II | Cartas 6–9; UX-06; IA-01 completo; informe de equilibrio | Medio | Fase 2 |
| 4 · Mesa viva | V-02, V-03, V-04, V-05, V-07, V-08, A-01, A-02 | Grande | Fase 2 para los efectos de cartas nuevas |
| 5 · Social y modos | M-02 a M-06, UX-05, UX-07, UX-08, UX-09, IA-03, IA-04 | Medio | N-01 |
| 6 · Putrefacto | Carta 10 completa | Medio | Fase 3 |
| Continuo | UX-11 a UX-14, V-09, IA-02, README (D-21) | Pequeño | — |

Orden recomendado: 1 → 2 → 3 → 5 → 4 → 6. La fase 1 mejora el juego actual sin tocar reglas y deja
listas las piezas (puntería, versión de protocolo) que las cartas nuevas necesitan.

---

## 11. Anexo: archivos a tocar al añadir una carta

1. `godot/data/cards.json` — nombre, tipo, textos, color, `now`, `cat`, y campo nuevo `pack`.
2. `web/www/cards.js` — solo la entrada de datos e icono, porque `tools/godot/build-card-textures.js` la usa para generar la cara.
3. `tools/blender/render_card_art.py` — ilustración → `godot/assets/art/<id>.png`.
4. `node tools/godot/build-card-textures.js` → `godot/assets/cards/<id>.png`.
5. `godot/scripts/rules/zk_game.gd` — `DECK_CRYPT`, `plan`, `_apply`, y si tiene decisión: `act`, `view`, `_auto_prompt`, `signature`.
6. `godot/scripts/ai/zk_bots.gd` — `VALUE`, `decide`, y `learn` si genera conocimiento del mazo.
7. `godot/scripts/table/game_screen.gd` — `_process_events` (sonido y efecto), `_why_not`, ventana de decisión si aplica, `_record` si el evento no trae texto.
8. `godot/scripts/vfx/vfx.gd` y `tools/audio/gen_audio.py` + `Sfx.NAMES` — efecto y sonido.
9. `godot/scripts/ui/info_screen.gd` — la guía de cartas debe agrupar por pack.
10. `godot/tests/run_tests.gd` — prueba unitaria de la carta.
