class_name CloneHint
extends RefCounted
## Qué copiará un Clon jugado solo (UX-03). Refleja los errores de `ZKGame.plan()` para un Clon
## en el turno del jugador; no contiene reglas nuevas.


## Devuelve {ok: bool, text: String}: «Copiará: <carta>» o el motivo por el que no puede copiar.
static func describe(view: Dictionary) -> Dictionary:
	var disc: Array = view.discard
	if disc.is_empty():
		return {"ok": false, "text": "No copia nada: el descarte está vacío."}
	var type: String = disc[disc.size() - 1].type
	var nm := CardDB.display_name(type)
	if type == "clone":
		return {"ok": false, "text": "No puede copiar: arriba hay otro Clon."}
	if ZKGame.is_cat(type) or type == "exploding":
		return {"ok": false, "text": "No copia %s: sola no hace nada. Úsalo en pareja." % nm}
	if type == "zombie":
		return {"ok": false, "text": "No copia %s: solo se usa al sacar un explosivo." % nm}
	if type in ["attack_dead", "grave_robber", "feed_dead"] and int(view.deadN) == 0:
		return {"ok": false, "text": "No copia %s: no hay jugadores muertos." % nm}
	if type == "nope" and view.stack.is_empty():
		return {"ok": false, "text": "No copia %s: no hay jugada que anular." % nm}
	if type == "clairvoyance":
		return {"ok": false, "text": "No copia %s: solo cuando otro usa un Gatito Zombi." % nm}
	return {"ok": true, "text": "Copiará: " + nm}
