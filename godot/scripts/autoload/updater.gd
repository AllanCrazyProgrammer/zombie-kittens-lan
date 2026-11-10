extends Node
## Busca versiones nuevas en GitHub Releases al abrir la app (una vez por arranque).
## Si hay una más nueva que la instalada, el menú muestra un aviso con un botón para descargarla.

signal changed

const API := "https://api.github.com/repos/AllanCrazyProgrammer/zombie-kittens-lan/releases/latest"

## idle | checking | latest | available | error
var state := "idle"
var latest := {}          # {version, url, page, notes}
var _http: HTTPRequest
## Solo para pruebas: se hace pasar por otra versión instalada (argumento --fake-version)
var _fake_version := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--fake-version")
	if i >= 0 and i + 1 < args.size():
		_fake_version = args[i + 1]
	if args.has("--no-update-check"):
		return
	check()


func installed_version() -> String:
	return _fake_version if _fake_version != "" else str(ProjectSettings.get_setting("application/config/version"))


func check() -> void:
	if state == "checking":
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 10.0
		add_child(_http)
		_http.request_completed.connect(_on_done)
	state = "checking"
	changed.emit()
	var err := _http.request(API, ["Accept: application/vnd.github+json", "User-Agent: ZombieKittens"])
	if err != OK:
		state = "error"
		changed.emit()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		state = "error"
		changed.emit()
		return
	var rel: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (rel is Dictionary):
		state = "error"
		changed.emit()
		return
	var url := ""
	for a: Dictionary in rel.get("assets", []):
		if str(a.get("name", "")).to_lower().ends_with(".apk"):
			url = a.get("browser_download_url", "")
			break
	latest = {"version": clean(str(rel.get("tag_name", ""))), "url": url, "page": rel.get("html_url", ""), "notes": rel.get("body", "")}
	state = "available" if is_newer(latest.version, installed_version()) else "latest"
	changed.emit()


## Abre la descarga del APK (o la página de la versión) en el navegador del teléfono.
func open_download() -> void:
	var target: String = latest.get("url", "")
	if target == "":
		target = latest.get("page", "")
	if target != "":
		OS.shell_open(target)


static func clean(v: String) -> String:
	var s := v.strip_edges().trim_prefix("v").trim_prefix("V")
	var out := ""
	for ch in s:
		if ch == "." or ch.is_valid_int():
			out += ch
		else:
			break
	return out if out != "" else "0"


## true si `remote` es estrictamente mayor que `local` (1.10.0 > 1.9.3; 2.0 == 2.0.0).
static func is_newer(remote: String, local: String) -> bool:
	var a := clean(remote).split(".")
	var b := clean(local).split(".")
	for i in maxi(a.size(), b.size()):
		var x := int(a[i]) if i < a.size() else 0
		var y := int(b[i]) if i < b.size() else 0
		if x != y:
			return x > y
	return false
