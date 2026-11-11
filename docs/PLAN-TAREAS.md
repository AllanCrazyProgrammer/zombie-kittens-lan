# Plan de tareas — Zombie Kittens v3.0

Desglose de [ESPECIFICACION-MEJORAS.md](ESPECIFICACION-MEJORAS.md) en tareas ejecutables. Los códigos
entre paréntesis (UX-01, V-02, §3.2…) remiten a esa especificación, que contiene el comportamiento y
los criterios de aceptación completos; aquí solo se resume la comprobación de cada tarea.

## Modo «Zombie Kittens Plus»

Todo lo nuevo vive detrás de un modo elegible en el menú, **Zombie Kittens Plus**. El modo **Clásico**
es el juego 2.2.0 sin ningún cambio: mismas reglas, misma pantalla, misma IA y compatible en red con
clientes 2.x. El diseño está en [CONTRATO-PLUS.md](CONTRATO-PLUS.md) y manda sobre este plan:

- `game_screen.gd` queda congelado; Plus usa una copia propia en `godot/scripts/plus/`.
- T04 parte la pantalla **de Plus**, no la clásica. Todas las tareas de MESA trabajan sobre la de Plus.
- T05 (nueva, Sonnet): selector CLÁSICO / PLUS en el menú, `plus` de extremo a extremo, pantalla Plus
  como copia, y grabación de la «guardia del clásico». Va antes de T04.
- T03 (README) se mueve al cierre para describir ya los dos modos.
- Las mejoras de IA, las opciones de sala y las reacciones solo existen en Plus.

## Reglas de ejecución

- **Carriles por archivo.** Dos tareas que tocan el mismo archivo nunca corren a la vez.
  - MOTOR: `scripts/rules/`, `scripts/ai/`, `tests/run_tests.gd`
  - MESA: `scripts/table/`, `scripts/vfx/`
  - SALA: `scripts/net/`, `scripts/autoload/net.gd`, `scripts/ui/menu_screen.gd`
  - RECURSOS: `data/cards.json`, `web/www/cards.js`, `tools/`, `assets/`, `scripts/autoload/sfx.gd`, `scripts/ui/info_screen.gd`
- Cada carril trabaja en su propio worktree y rama; el orquestador integra en una rama por fase.
- **Puerta de calidad de toda tarea:** `godot --headless --path godot -s tests/run_tests.gd` termina en
  «TODO OK» y, si toca la mesa, `godot --path godot -- --uitest <carpeta>` pasa.
- **Escalado:** una tarea sube de modelo (Haiku → Sonnet → Fable) solo tras dos intentos fallidos en
  su puerta de calidad o si el orquestador rechaza el diff en revisión por un fallo de diseño.
- El orquestador (Fable) no escribe código de las tareas de Haiku/Sonnet: escribe el encargo, revisa el
  diff, ejecuta las puertas e integra.
- Al cerrar cada fase hay una parada para que el usuario la pruebe en el teléfono.

## Límites de verificación

- Disponibles: Godot 4.7.2, Node, Blender, Chrome. Se pueden ejecutar pruebas de reglas, de toques con
  capturas, de red con dos copias y exportar el APK.
- No disponible: `adb`. El rendimiento real (R-7) y el tacto en un teléfono solo los puede comprobar el usuario.
- La calidad del arte y de los efectos se revisa con capturas, pero el juicio final es del usuario.

## Tareas

Modelos: **H** = Haiku, **S** = Sonnet, **F** = Fable 5.2.

### Fase 0 · Preparación

| ID | Tarea | Carril | Depende | Modelo | Por qué ese modelo | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T00 | Línea base: ejecutar pruebas de reglas, de toques y de red; guardar resultados y capturas | — | — | H | Solo ejecutar comandos y anotar salidas | Informe con el resultado de las 3 pruebas |
| T01 | Contrato del motor: firmas exactas de `packs`, `rules`, `dir`, `tops`, `deckTypes`, `need` nuevos, decisiones `alter`/`bury`, eventos y campos de `view` (§3.3), y cómo se garantiza R-1 | MOTOR (doc) | — | F | Decisión de arquitectura con impacto en motor, IA, red e interfaz; un error aquí se paga en todas las fases | Documento corto que T20–T33 siguen sin tener que decidir nada |
| T02 | Reproducir D-20 (eventos viejos al reabrir la pantalla) con una prueba | MESA | T00 | S | Depuración acotada con hipótesis ya formulada | Prueba que falla si el fallo existe, o nota de que no existe |
| T03 | README al día (D-21) | — | — | H | Texto, sin razonamiento | README describe la versión Godot actual |
| T04 | Partir `game_screen.gd` (1 725 líneas) en entrada, HUD, ventanas y efectos, sin cambiar comportamiento | MESA | T00 | S | Refactor mecánico pero amplio; lo tocan ~25 tareas y partirlo reduce conflictos y el contexto que cada agente debe leer | Pruebas de toques idénticas a la línea base |

### Fase 1 · Interacción

| ID | Tarea | Carril | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T10 | Versión de protocolo en `hello` y en la baliza; salas incompatibles marcadas (N-01) | SALA | T00 | S | Cambio de red estándar con prueba | `hello` con `proto` distinto es rechazado |
| T11 | Fichas de rivales persistentes con iconos de estado y avatar con 5 jugadores (UX-10) | MESA | T04 | S | Refactor de interfaz moderado | Seleccionar carta no recrea las fichas |
| T12 | Modo puntería: tocar asiento o ficha, soltar carta sobre un rival (UX-01) | MESA | T11 | S | Entrada táctil 3D con varios estados; estándar pero delicado | Favor en 2 toques o 1 arrastre |
| T13 | Ver descarte y «Copiará: …» del Clon; `view.discard` a 20 (UX-03) | MESA + MOTOR (vista) | T04 | S | Funcionalidad estándar | Panel del Clon nombra la carta copiada |
| T14 | Recordatorio del futuro junto al mazo (UX-02) | MESA | T13 | S | Lógica de vigencia con `shuf`; estándar | Se desplaza al robar, desaparece al barajar |
| T15 | Trío con miniaturas y solo tipos del mazo; `view.deckTypes` (UX-04) | MESA + MOTOR (vista) | T13 | S | Funcionalidad estándar | Partida de 2 no ofrece cartas ausentes |
| T16 | Medidor de riesgo en forma de mecha (V-01) | MESA | T11 | S | Control nuevo con animación | 4 tramos de color y pulso al subir de tramo |
| T17 | Corregir D-20 si T02 lo confirmó (UX-15) | MESA | T02, T04 | S | Arreglo acotado | La prueba de T02 pasa |
| T18 | Pasos nuevos en la prueba de toques para T12–T15 | MESA | T12–T15 | S | Creación de pruebas | `--uitest` cubre puntería, descarte y trío |
| R1 | Revisión, integración y parada de fase | — | T10–T18 | F | Responsabilidad del orquestador | Todas las puertas en verde; APK de prueba |

### Fase 2 · Cartas I

| ID | Tarea | Carril | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T20 | Andamiaje del motor según T01: `packs`, `DECK_CRYPT`, `dir`, `tops`, `need` nuevos | MOTOR | T01, R1 | S | Con el contrato escrito es implementación guiada; las trazas detectan cualquier desvío de R-1. Sube a F si las trazas fallan dos veces | Trazas sin regenerar en «TODO OK» |
| T21 | Datos de las 10 cartas en `cards.json` y `cards.js`, campo `pack`; guía de cartas agrupada por pack | RECURSOS | T01 | H | Copiar textos de la especificación a un formato existente | 29 tipos cargan en `CardDB` |
| T22 | Ilustraciones de las 10 cartas con Blender y generación de caras | RECURSOS | T21 | S | Escribir escenas siguiendo el patrón de `render_card_art.py`; requiere criterio visual | 10 PNG coherentes con el estilo actual (revisión con capturas) |
| T23 | Cartas 1–5 en el motor con prueba unitaria por carta: Ataque Dirigido, Marcha Atrás, Robar del Fondo, Ojo de Cuervo, Apocalipsis | MOTOR | T20 | S | Cinco efectos bien especificados sobre mecanismos existentes | Criterio de aceptación de cada ficha (§3.2) |
| T24 | Memoria de los bots con `tops` e IA de las cartas 1–5; valores en `VALUE` | MOTOR | T23 | S | Heurísticas ya definidas en la especificación | Simulaciones sin bloqueos; difícil sigue ganando a fácil |
| T25 | Interfaz de las cartas 1–5: eventos, motivos de «no jugable», ventana de Ojo de Cuervo, flecha de sentido y marcas de ataque (V-06) | MESA | T23, T12 | S | Funcionalidad estándar | Cada carta jugable de principio a fin en una partida de demostración |
| T26 | Opción «La Cripta» en sala y en un jugador; `lobby.settings` ampliado (N-02) | SALA | T20, T10 | S | Estándar, con validación de red | El pack elegido llega a todos los clientes |
| T27 | Pruebas de conservación, sin bloqueos, información oculta y sentido de juego (§9) | MOTOR | T24 | S | Creación de pruebas | 2 000 partidas con el pack sin fallos |
| R2 | Revisión, integración y parada de fase | — | T20–T27 | F | Orquestador | Puertas en verde; APK de prueba |

### Fase 3 · Cartas II

| ID | Tarea | Carril | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T30 | Cartas 6–9 en el motor con sus decisiones y pruebas: Alterar el Futuro, Entierro, Trueque de Almas, Espanto | MOTOR | R2 | S | Decisiones nuevas ya definidas por T01 | Aceptación de cada ficha; plazos se resuelven solos |
| T31 | Mazo visual para esconder cartas, reutilizable (UX-06) | MESA | R2 | S | Control nuevo con arrastre | Precisión de 1 carta en un mazo de 40 |
| T32 | Interfaz de las cartas 6–9: reordenar arrastrando, enterrar, trueque, espanto | MESA | T30, T31 | S | Estándar | Cada carta jugable de principio a fin |
| T33 | IA de las cartas 6–9 y carencias actuales (IA-02) | MOTOR | T30 | S | Heurísticas definidas | Simulaciones sin bloqueos |
| T34 | Informe de equilibrio base contra expansión (§3.4) | MOTOR | T33 | S | Ampliar el simulador existente | Tabla de duración y victorias por asiento y nivel |
| T35 | Decidir ajustes de copias o mano inicial con el informe | — | T34 | F | Decisión de diseño con datos ambiguos; es corta | Ajuste aplicado o justificación de no ajustar |
| R3 | Revisión, integración y parada de fase | — | T30–T35 | F | Orquestador | Puertas en verde; APK de prueba |

### Fase 5 · Social y modos (va antes que la 4)

| ID | Tarea | Carril | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T50 | Reglas opcionales en el motor: tiempo de turno, Nop fijo, mano inicial, muerte súbita (M-02 a M-05) | MOTOR | R3 | S | Cambios de configuración con pruebas; con valores por defecto no altera nada | Trazas intactas; prueba por opción |
| T51 | Opciones en la sala y marcador de victorias (M-06) | SALA | T50, T26 | S | Estándar | Marcador persiste entre partidas de una sala |
| T52 | Barra de tiempo de turno y aviso final (UX-07) | MESA | T50 | H | Reutiliza `timer_bar` y un sonido existente; cambio pequeño y cerrado | Barra visible y alarma a los 10 s |
| T53 | Reacciones rápidas: mensaje `emote`, globo sobre el avatar, límite de frecuencia (UX-08) | SALA + MESA | T10 | S | Toca red e interfaz | Reacción visible en dos copias conectadas |
| T54 | Ventana de Nop: contador de Nop y paso automático opcional (UX-05); resumen de fin de partida (UX-09) | MESA | R3 | S | Estándar | Aceptación de UX-05 y UX-09 |
| T55 | Personalidad de los bots y reacciones (IA-03, IA-04) | MOTOR | T33, T53 | S | Heurísticas | Diferencia medible de comportamiento entre rasgos |
| R5 | Revisión, integración y parada de fase | — | T50–T55 | F | Orquestador | Puertas en verde; APK de prueba |

### Fase 4 · Mesa viva

| ID | Tarea | Carril | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T40 | Carta jugada en escena y rotura al anularla (V-02) | MESA | R5 | S | Animación ligada a la pila de jugadas | Captura de la carta flotando durante la ventana |
| T41 | Lápidas, explosivo a la vista y fantasmas; revivir (V-03) | MESA | T40 | S | Animación estándar con modelo existente | Captura de un asiento muerto y uno revivido |
| T42 | Un efecto por carta, 14 en total, con versión de calidad baja (V-04) | MESA (`vfx.gd`) | T41 | S | Volumen alto pero patrón repetido de `Vfx` | Cada evento dispara su efecto |
| T43 | Mazo vivo, cartas jugables resaltadas, robo con revelado, avatares con expresión (V-05, V-07, V-08) | MESA | T42 | S | Estándar | Capturas de cada estado |
| T44 | Música en 3 capas, 13 sonidos nuevos, volúmenes con deslizador (A-01, A-02) | RECURSOS | R5 | S | Síntesis con el generador existente | Capas entran según el riesgo |
| T45 | Registrar sonidos nuevos en `Sfx.NAMES` y conectarlos a los eventos | RECURSOS + MESA | T44, T42 | H | Lista de nombres y llamadas de una línea | Ningún evento nuevo queda sin sonido |
| T46 | Pasada de rendimiento con el registro de FPS existente en las 3 calidades | MESA | T43 | S | Medir y recortar; sube a F solo si aparece un cuello de botella difícil | FPS registrados; sin caídas nuevas respecto a T00 |
| R4 | Revisión, integración y parada de fase | — | T40–T46 | F | Orquestador | Puertas en verde; APK de prueba |

### Fase 6 · Gatito Putrefacto

| ID | Tarea | Carril | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T60 | Resolver las interacciones no definidas del Putrefacto con Barajar, Apocalipsis, Cava Más Hondo, Entierro, Robar del Fondo, Alterar el Futuro, Clon y revivir | MOTOR (doc) | R3 | F | Requisitos ambiguos y efecto sobre casi todo el motor | Tabla de interacciones sin huecos |
| T61 | Motor y pruebas del Putrefacto | MOTOR | T60 | S | Implementación guiada por T60 | Pruebas de cada fila de la tabla |
| T62 | Interfaz e IA del Putrefacto | MESA + MOTOR | T61, T31 | S | Estándar | Jugable de principio a fin |
| R6 | Revisión e integración | — | T61, T62 | F | Orquestador | Puertas en verde |

### Continuo (se intercalan cuando su carril está libre)

| ID | Tarea | Carril | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| T70 | Ordenar la mano y marca de pareja o trío (UX-11) | MESA | T04 | H | Una función de orden y un ajuste | Dos órdenes seleccionables |
| T71 | Historial con miniaturas y filtro (UX-12) | MESA | T04 | S | Estándar | Filtro «Solo lo mío» |
| T72 | Accesibilidad: tamaño de texto, vibración, reducir movimiento (UX-13) | MESA + ajustes | R4 | S | Toca todos los efectos | Con «reducir movimiento» no hay sacudidas ni destellos |
| T73 | Consejos nuevos del tutorial y guardado de los vistos (UX-14) | MESA | R3 | H | Textos y un diccionario guardado | Consejos no se repiten entre partidas |
| T74 | Ambiente: niebla, relámpagos, luna variable (V-09) | MESA (`table_world.gd`) | R4 | S | Estándar | Respeta los niveles de calidad |

### Cierre

| ID | Tarea | Depende | Modelo | Por qué | Comprobación |
| --- | --- | --- | --- | --- | --- |
| T90 | Subir versión a 3.0.0, exportar APK, ejecutar todas las pruebas | Todo | H | Comandos | APK generado y pruebas en verde |
| T91 | Verificación final contra la especificación, punto por punto | T90 | F | Juicio global sobre el conjunto | Lista de la especificación marcada como hecha, pendiente o descartada |

## Paralelismo

- Fase 0: T00, T01 y T03 a la vez; después T02 y T04.
- Fase 1: T10 (SALA) en paralelo con la cadena de MESA T11 → T12 → T13 → T14 → T15 → T16.
- Fase 2: T21 → T22 (RECURSOS) en paralelo con T20 → T23 → T24 → T27 (MOTOR); T25 (MESA) y T26 (SALA) arrancan al terminar T23 y T20.
- Fase 3: T30 → T33 → T34 (MOTOR) en paralelo con T31 (MESA).
- Fases 5 y 4: MOTOR, SALA, MESA y RECURSOS en paralelo según la columna «Depende».
- T60 (diseño) se puede adelantar en cuanto cierre la fase 3.

## Reparto por modelo

| Modelo | Tareas | Uso |
| --- | --- | --- |
| Haiku | 8 | Comandos, datos, textos y cambios de una pieza |
| Sonnet | 39 | Implementación, pruebas, refactor |
| Fable 5.2 | 10 | 3 de diseño (T01, T35, T60), 6 revisiones de fase y la verificación final |
