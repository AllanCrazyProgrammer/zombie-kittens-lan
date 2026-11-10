class_name InfoScreen
extends CanvasLayer
## Pantalla de consulta a pantalla completa: "Cómo jugar" (reglas) o la guía de cartas.
## Se abre encima del menú o de la partida y se cierra sola.

const RULES := [
	["Objetivo", "En el mazo hay Gatitos Explosivos. Por turnos se roban cartas hasta que alguien saca uno y explota. Gana el último jugador con vida. Pero aquí la muerte no es el final: ¡puedes volver como zombi!"],
	["Preparación (automática)", "• 2 jugadores: solo las 24 cartas con huella.\n• 3 jugadores: solo las 33 cartas sin huella.\n• 4 o 5 jugadores: todas las cartas.\n• Cada jugador recibe 1 Gatito Zombi + 7 cartas (8 en total). Los Zombis que sobren se barajan en el mazo.\n• En el mazo se mezclan tantos Gatitos Explosivos como jugadores menos uno."],
	["Tu turno", "1. Juega todas las cartas que quieras (o ninguna). Toca una carta para levantarla y luego JUGAR.\n2. Roba una carta del mazo para terminar tu turno… y reza para que no sea un Gatito Explosivo.\n\nEl turno pasa al siguiente jugador vivo. No hay límite de cartas en la mano."],
	["Explotar y morir", "Si sacas un Gatito Explosivo y no juegas un Gatito Zombi (puedes tenerlo y decidir no usarlo), quedas Muerto. Conservas tu mano. Puedes morir todas las veces que haga falta."],
	["Estar muerto", "• No juegas turnos ni robas.\n• Sí puedes jugar Nop y las cartas con ⚡ en cualquier momento: Barajar, Alimenta a los Muertos y Clarividencia.\n• Nadie puede robarte cartas ni pedirte Favor."],
	["Gatito Zombi y revivir", "Al sacar un explosivo puedes jugar tu Gatito Zombi en lugar de morir. Si hay muertos, debes revivir a uno. Después escondes en secreto tu explosivo (y el del jugador revivido) en cualquier lugar del mazo, cada uno donde quieras. El revivido vuelve a jugar con la mano que tenía."],
	["Nop", "Cuando alguien juega una carta se abre una breve ventana: cualquiera (vivo o muerto) puede decir ¡NOP! para anularla. Otro Nop anula al Nop anterior. Lo único que no se puede anular es un Gatito Explosivo o un Gatito Zombi."],
	["Combos especiales", "• Dos iguales: juega 2 cartas con el mismo título (no solo gatos) para robar una carta al azar a un jugador vivo.\n• Tres iguales: igual, pero nombras la carta que quieres; si la tiene, te la da.\n• El Clon puede completar cualquier pareja o trío.\n\nEn un combo se ignora el texto de las cartas."],
	["Partidas de 2 jugadores", "Hay un solo explosivo, así que el primero que muera pierde: el Gatito Zombi funciona como tu única vida extra. Guarda tus Saltar y Ataque para cuando el mazo esté casi vacío, y usa Ver el Futuro o Cava Más Hondo para saber dónde está el explosivo. Al esconderlo, ponerlo arriba obliga a tu rival a enfrentarlo de inmediato."],
	["Partidas de 3 a 5 jugadores", "Aquí entra el caos zombi: al revivir a alguien, dos explosivos vuelven al mazo. El Ataque de los Muertos se vuelve brutal con varios muertos (3 turnos por cada uno) y los muertos siguen influyendo con Nop, Barajar y Alimenta a los Muertos."],
	["Consejos", "• Al inicio el riesgo es bajo: guarda tus cartas.\n• Fíjate en el indicador de riesgo: es la probabilidad de explotar al robar.\n• Consigue todos los Gatitos Zombi que puedas (¡con un trío puedes pedirlo por nombre!)."],
	["Jugar en red local", "• Un jugador toca Crear sala: su teléfono es el anfitrión.\n• Los demás, en la misma Wi-Fi, tocan Unirse a una sala. Si la sala no aparece, escriben la dirección que ve el anfitrión.\n• Sin Wi-Fi: el anfitrión activa su zona Wi-Fi y los demás se conectan a ella. No se necesita internet.\n• Todos necesitan tener el juego instalado.\n• Si alguien pierde la conexión, el juego reintenta solo y recupera su mano.\n• El anfitrión debe dejar el juego abierto durante la partida."],
]


static func open(parent: Node, kind: String) -> InfoScreen:
	var s := InfoScreen.new()
	s.set_meta("kind", kind)
	parent.add_child(s)
	return s


func _ready() -> void:
	layer = 8
	var kind: String = get_meta("kind", "rules")
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.035, 0.16, 0.985)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var col := UIKit.vbox(16)
	margin.add_child(col)
	var head := UIKit.hbox(16)
	col.add_child(head)
	var title := UIKit.label("Cómo jugar" if kind == "rules" else "Guía de cartas", 68, UIKit.C.toxic, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UIKit.button("Cerrar", "primary", 40)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(queue_free)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := UIKit.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	if kind == "rules":
		_fill_rules(body)
	else:
		_fill_cards(body)


func _fill_rules(body: VBoxContainer) -> void:
	for sec: Array in RULES:
		var panel := UIKit.panel(Color(0.11, 0.06, 0.24), UIKit.C.line, Vector2(26, 20))
		var v := UIKit.vbox(8)
		panel.add_child(v)
		v.add_child(UIKit.label(sec[0], 46, UIKit.C.gold, true, true))
		v.add_child(UIKit.label(sec[1], 32, UIKit.C.ink, false, true))
		body.add_child(panel)


func _fill_cards(body: VBoxContainer) -> void:
	var counts := {"exploding": "4 cartas"}
	for row: Array in ZKGame.DECK:
		counts[row[0]] = "%d con huella + %d sin huella" % [row[1], row[2]]
	for t: String in CardDB.types():
		var d: Dictionary = CardDB.defs[t]
		var panel := UIKit.panel(Color(0.11, 0.06, 0.24), UIKit.C.line, Vector2(18, 18))
		var h := UIKit.hbox(20)
		panel.add_child(h)
		var pic := UIKit.card_image(t, 360)
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(pic)
		var v := UIKit.vbox(6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UIKit.label(d.name, 44, UIKit.C.ink, true, true))
		v.add_child(UIKit.label("%s · %s" % [d.kind, counts.get(t, "")], 26, UIKit.C.toxic, false, true))
		v.add_child(UIKit.label(d.long, 29, UIKit.C.ink, false, true))
		body.add_child(panel)
	var foot := UIKit.label("Con huella: las cartas que se usan con 2 jugadores. Sin huella: las de 3 jugadores. Con 4 o 5 se usan todas.", 26, UIKit.C.dim, false, true)
	body.add_child(foot)
