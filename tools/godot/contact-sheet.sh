#!/bin/sh
# Hoja de contacto con todas las cartas, para revisarlas de un vistazo. Uso: tools/godot/contact-sheet.sh salida.png [carpeta]
OUT="$1"; DIR="${2:-godot/assets/cards}"; ABS="$(cd "$DIR" && pwd)"
H="$(mktemp -d)/sheet.html"
{ echo '<body style="margin:0;background:#222;display:flex;flex-wrap:wrap;gap:6px;padding:6px;width:1588px">'
  for f in "$ABS"/*.png; do echo "<img src=\"file://$f\" style=\"width:220px\">"; done; echo '</body>'; } > "$H"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=1588,960 --screenshot="$OUT" "file://$H" >/dev/null 2>&1
