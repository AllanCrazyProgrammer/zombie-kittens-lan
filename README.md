# Zombie Kittens LAN

Versión digital hecha por fans (uso personal) del juego de cartas **Zombie Kittens**, para jugar
de 2 a 5 personas en la misma red Wi-Fi, cada quien en su teléfono. Arte original dibujado por código.

## Descargar

La forma más fácil: descarga el APK de la última versión en
[Releases](https://github.com/AllanCrazyProgrammer/zombie-kittens-lan/releases/latest) e instálalo en tu Android
(tendrás que permitir "instalar apps de origen desconocido").

- **Zombie Kittens 2.x / 3.x** (Godot, mesa 3D): la versión actual. Desde la 3.0 incluye el modo **Plus**.
- **Zombie Kittens LAN 1.x** (web/Android original): sigue disponible en la release v1.1.0.

## Instalar la versión original (1.x) en Android

1. Copia `ZombieKittensLAN.apk` al teléfono (o `adb install -r ZombieKittensLAN.apk` con el cable USB).
2. Ábrelo y permite "instalar apps de origen desconocido" si lo pide.

## Jugar

- **Anfitrión:** toca *Crear partida*. Su teléfono corre la partida.
- **Con la app:** los demás tocan *Unirse a una partida*; la sala aparece sola si están en la misma Wi-Fi
  (o escriben la dirección que muestra el anfitrión).
- **Sin app (iPhone u otro):** escanean el QR de la sala o abren `http://IP-del-anfitrión:8765` en el navegador.
- **Sin Wi-Fi:** el anfitrión activa su zona Wi-Fi y los demás se conectan a ella. No hace falta internet.
- *Practicar contra bots* funciona sin red.

## Versión web de un jugador

`zombie-kittens-web.html` es el juego completo en un solo archivo: ábrelo con doble clic en cualquier
navegador (o súbelo a un hosting estático). Juegas tú contra 1 a 4 rivales de IA en dificultad
Fácil, Normal, Difícil o Mixta. Se regenera con `npm run build:web`. El mismo modo está en la app
Android (*Un jugador contra la IA*), y en las salas en red el anfitrión puede tocar la dificultad de cada bot.

## Versión Godot (mesa 3D)

La carpeta `godot/` es la versión 2.x / 3.x del juego, reescrita en Godot 4 con mesa 3D. Es la versión actual y está completa: un jugador contra la IA, red local con búsqueda automática de salas y reconexión, tutorial guiado, pantalla de reglas, guía de cartas, ajustes de sonido y calidad gráfica. Aún no hay versión para iPhone ni exportación web.

- Modelos 3D: `Blender --background --python tools/blender/build_models.py`
- Sonidos y música (síntesis): `python3 tools/audio/gen_audio.py`
- Avatares de los jugadores: `Blender --background --python tools/blender/render_card_art.py -- --avatars`
- Ilustraciones 3D de las cartas: `Blender --background --python tools/blender/render_card_art.py` (opcional: `-- zombie nope` para solo algunas)
- Ícono de la app: `node tools/godot/build-icon.js`
- Caras de las cartas (ilustración + marco): `node tools/godot/build-card-textures.js`
- Exportar APK: `godot --headless --path godot --export-debug Android ../dist/ZombieKittensGodot.apk`
- Partida de demostración (la IA juega por ti) con capturas: `godot --path godot -- --auto 2 normal --slow --shots carpeta 3 --quit-after 120`
- Prueba de red con dos copias en la misma máquina: `godot --path godot -- --nettest host 2 --token A` y `godot --path godot -- --nettest discover --token B` (añade `--drop 5` para probar la reconexión)
- Prueba de toques (menú, elegir carta, jugar, robar, salir): `godot --path godot -- --uitest carpeta`
- Pruebas de reglas e IA: `godot --headless --path godot -s tests/run_tests.gd` (las partidas de referencia se regeneran con `node tools/godot/gen-traces.js`)
- Prueba de toques del modo Plus: `godot --path godot -- --uitest-plus carpeta` (por partes: `--uitest-plus-part N`)
- Medir el equilibrio del pack: `godot --headless --path godot -s tests/run_tests.gd -- --balance` (opciones `--variants=`, `--players=`, `--games=`)
- Partida de demostración en modo Plus: añadir `--plus` a `--auto` en el comando de demostración.
- Generar solo sonidos nuevos: `python3 tools/audio/gen_audio.py new` (o nombres concretos)

Si el juego no abre ventana en macOS (fallo de Metal), añade `--rendering-driver vulkan --rendering-method mobile` antes de `--`.

## Zombie Kittens Plus

**Qué es:** en la pantalla de inicio hay un selector **CLÁSICO / PLUS**. **Clásico** es el juego de siempre, sin cambios y compatible en red con la versión 2.x. **Plus** añade todo lo nuevo. En red, una sala Plus solo admite teléfonos actualizados. Quien se une adopta el modo de la sala.

**Qué trae Plus:**

- **Pack «La Cripta»** (opcional): 9 cartas nuevas: Ataque Dirigido, Marcha Atrás, Robar del Fondo, Ojo de Cuervo, Apocalipsis Zombi, Alterar el Futuro, Entierro, Trueque de Almas y Espanto (solo para muertos). Con el pack, cada jugador empieza con 8 cartas.
- **Gatito Putrefacto** (regla opcional, 3+ jugadores): sustituye a un explosivo. La primera vez no mata y se devuelve boca arriba a la vista de todos. La segunda mata, sin que valga el Zombi.
- **Reglas opcionales:** tiempo por turno (30 o 60 s), mano corta, muerte súbita con 2 vivos y «Nop sin pistas».
- **Mesa:** elegir objetivo tocando al rival, recordatorio de lo que sabes del mazo, ver el descarte, trío con imágenes, mazo visual para esconder cartas, medidor de riesgo, carta jugada en escena, lápidas de los muertos y efectos por carta.
- **Social:** reacciones rápidas, marcador de victorias de la sala, resumen al final de la partida e historial con iconos.
- **IA:** los bots juegan las cartas nuevas y tienen personalidad (agresivo, prudente, vengativo).
- **Sonido:** efectos nuevos y música que se intensifica con el riesgo.

Documentación del diseño: `docs/ESPECIFICACION-MEJORAS.md` (qué y por qué), `docs/CONTRATO-PLUS.md` (reglas técnicas exactas) y `docs/PLAN-TAREAS.md` (plan de trabajo).

## Estructura

| Carpeta | Qué hay |
| --- | --- |
| `web/www/engine.js` | Reglas del juego (autoritativas, corren en el teléfono anfitrión) |
| `web/www/room.js` | Sala, reconexión, temporizadores y bots |
| `web/www/cards.js` | Textos de las cartas y arte SVG |
| `web/www/app.js`, `style.css` | Interfaz, menús, reglas, sonido |
| `android/` | App Android: WebView + servidor HTTP/WebSocket local + búsqueda de partidas (NSD) |
| `tools/server.js` | Servidor equivalente para computadora (`npm run dev`) |
| `test/engine.test.js` | Pruebas de reglas + 6000 partidas simuladas (`npm test`) |
| `godot/scripts/rules/zk_game.gd` | Reglas del juego en Godot (clásico y Plus) |
| `godot/scripts/ai/zk_bots.gd` | IA de los bots |
| `godot/scripts/plus/` | Pantalla de partida y componentes del modo Plus |
| `godot/scripts/table/game_screen.gd` | Pantalla de partida del modo clásico |
| `godot/tests/run_tests.gd` | Pruebas de reglas, IA, red y equilibrio (`godot --headless --path godot -s tests/run_tests.gd`) |

## Compilar

```bash
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug
```

Zombie Kittens y Exploding Kittens son marcas de Exploding Kittens, Inc. Este proyecto no está afiliado ni es para distribución.
