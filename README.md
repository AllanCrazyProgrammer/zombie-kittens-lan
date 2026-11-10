# Zombie Kittens LAN

Versión digital hecha por fans (uso personal) del juego de cartas **Zombie Kittens**, para jugar
de 2 a 5 personas en la misma red Wi-Fi, cada quien en su teléfono. Arte original dibujado por código.

## Descargar

La forma más fácil: descarga el APK de la última versión en
[Releases](https://github.com/AllanCrazyProgrammer/zombie-kittens-lan/releases/latest) e instálalo en tu Android
(tendrás que permitir "instalar apps de origen desconocido").

- **Zombie Kittens 2.x** (Godot, mesa 3D): la versión actual.
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

## Versión Godot (en desarrollo)

La carpeta `godot/` es la reescritura del juego en Godot 4 con mesa 3D. Hoy contiene solo la base:
escena de mesa con cartas de prueba, modelos hechos con Blender y exportación a Android.
Ya se puede jugar contra la IA y en red local: un teléfono crea la sala y los demás la encuentran solos en la misma Wi-Fi (o escriben su dirección). Hay reconexión, y el anfitrión puede añadir rivales de IA. Incluye tutorial guiado, pantalla de reglas, guía de cartas y ajustes de sonido y calidad gráfica. Falta la versión para iPhone y la exportación web.

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

## Compilar

```bash
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug
```

Zombie Kittens y Exploding Kittens son marcas de Exploding Kittens, Inc. Este proyecto no está afiliado ni es para distribución.
