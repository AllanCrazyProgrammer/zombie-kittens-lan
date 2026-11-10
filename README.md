# Zombie Kittens LAN

Versión digital hecha por fans (uso personal) del juego de cartas **Zombie Kittens**, para jugar
de 2 a 5 personas en la misma red Wi-Fi, cada quien en su teléfono. Arte original dibujado por código.

## Instalar en Android

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
