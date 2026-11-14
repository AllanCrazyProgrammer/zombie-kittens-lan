extends Node
## Sonido del juego: efectos y música (generados por síntesis en tools/audio/gen_audio.py).
## Uso: Sfx.play("card")

const NAMES := ["tap", "card", "draw", "shuffle", "turn", "nope", "yup", "fuse", "explosion", "zombie", "attack", "alarm", "steal", "revive", "win", "lose"]
## Efectos del modo PLUS (La Cripta y extras). Se cargan igual que los anteriores: Sfx.play("crow").
const NAMES_PLUS := ["targeted", "reverse", "bottom", "crow", "apocalypse", "alter", "bury", "swap", "haunt", "rotten",
		"emote", "tick", "tomb", "aim", "sudden"]
## Música por capas (misma composición, tempo y duración que music.wav): base, percusión, tensión.
const LAYER_FILES := ["music_base", "music_drums", "music_tension"]
const MUSIC_DB := -15.0
const SETTINGS := "user://settings.cfg"

var sfx_on := true
var music_on := true
var sfx_volume := 1.0    ## 0-1; 1.0 = volumen de siempre
var music_volume := 1.0  ## 0-1; 1.0 = volumen de siempre
var layers_on := false   ## true: suena la música por capas (lo activa la pantalla Plus)
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _lp: AudioStreamPlayer          # reproductor de las 3 capas (AudioStreamSynchronized), se crea al primer uso
var _sync: AudioStreamSynchronized
var _xf := 0.0                      # reparto entre music.wav (0) y las capas (1) durante el fundido
var _xf_tween: Tween
var _drums := 0.0
var _tension := 0.0
var _layer_tweens := [null, null]


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		sfx_on = cfg.get_value("audio", "sfx", true)
		music_on = cfg.get_value("audio", "music", true)
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", 1.0)), 0.0, 1.0)
	for n: String in NAMES:
		_streams[n] = load("res://assets/audio/%s.wav" % n)
	for n: String in NAMES_PLUS:
		_streams[n] = load("res://assets/audio/%s.wav" % n)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	var track: AudioStreamWAV = load("res://assets/audio/music.wav")
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	track.loop_begin = 0
	track.loop_end = int(track.get_length() * track.mix_rate)
	_music.stream = track
	_music.volume_db = MUSIC_DB + _vol_db(music_volume)
	add_child(_music)
	if music_on:
		_music.play()


func play(sound: String, volume_db: float = 0.0, pitch_var: float = 0.05) -> void:
	if not sfx_on or not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db + _vol_db(sfx_volume)
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func set_sfx(on: bool) -> void:
	sfx_on = on
	_save()


func set_music(on: bool) -> void:
	music_on = on
	var cur := _active_player()
	if on and not cur.playing:
		cur.play()
	elif not on:
		_music.stop()
		if _lp != null:
			_lp.stop()
	_save()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_save()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_music_volume()
	_save()


## Música por capas (opcional, para la pantalla Plus). Al activarla se pasa de music.wav a las tres capas
## sincronizadas con un fundido corto, conservando la posición; al desactivarla se vuelve a music.wav.
func set_layers(enabled: bool) -> void:
	if enabled == layers_on:
		return
	if enabled and not _ensure_layers():
		return
	layers_on = enabled
	if enabled:
		_apply_layer_levels(false)
	if not music_on:
		_xf = 1.0 if enabled else 0.0   # sin música: solo se anota el estado; sonará al activar la música
		_apply_music_volume()
		return
	var src: AudioStreamPlayer = _music if enabled else _lp
	var dst: AudioStreamPlayer = _lp if enabled else _music
	var pos := src.get_playback_position() if src.playing else 0.0
	if not dst.playing:
		dst.play(pos)
	_fade_xf(1.0 if enabled else 0.0, 0.5)


## Mezcla de capas (0-1 cada una) con fundido de ~1 s. Se recuerda aunque las capas no estén activas todavía.
func set_intensity(drums: float, tension: float) -> void:
	_drums = clampf(drums, 0.0, 1.0)
	_tension = clampf(tension, 0.0, 1.0)
	if layers_on:
		_apply_layer_levels(true)


func _vol_db(v: float) -> float:
	return 0.0 if v >= 1.0 else (-80.0 if v <= 0.0001 else linear_to_db(v))


func _active_player() -> AudioStreamPlayer:
	return _lp if (layers_on and _lp != null) else _music


func _apply_music_volume() -> void:
	var base := MUSIC_DB + _vol_db(music_volume)
	_music.volume_db = base + _vol_db(1.0 - _xf)
	if _lp != null:
		_lp.volume_db = base + _vol_db(_xf)


func _set_xf(v: float) -> void:
	_xf = v
	_apply_music_volume()


func _fade_xf(target: float, secs: float) -> void:
	if _xf_tween != null and _xf_tween.is_valid():
		_xf_tween.kill()
	_xf_tween = create_tween()
	_xf_tween.tween_method(_set_xf, _xf, target, secs)
	_xf_tween.tween_callback(_xf_done)


func _xf_done() -> void:
	# al terminar el fundido se para el reproductor que ya no se oye
	if layers_on:
		_music.stop()
	elif _lp != null:
		_lp.stop()


func _ensure_layers() -> bool:
	if _lp != null:
		return true
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = LAYER_FILES.size()
	for i in LAYER_FILES.size():
		var track := load("res://assets/audio/%s.wav" % LAYER_FILES[i]) as AudioStreamWAV
		if track == null:
			push_warning("Sfx: falta la capa de música %s" % LAYER_FILES[i])
			return false
		track.loop_mode = AudioStreamWAV.LOOP_FORWARD
		track.loop_begin = 0
		track.loop_end = int(track.get_length() * track.mix_rate)
		sync.set_sync_stream(i, track)
	_sync = sync
	_lp = AudioStreamPlayer.new()
	_lp.stream = _sync
	add_child(_lp)
	_apply_music_volume()
	return true


## La base siempre suena; percusión y tensión según set_intensity. smooth = fundido de 1 s.
func _apply_layer_levels(smooth: bool) -> void:
	if _sync == null:
		return
	_sync.set_sync_stream_volume(0, 0.0)
	var targets := [_drums, _tension]
	for k in 2:
		var idx := k + 1
		var tw: Tween = _layer_tweens[k]
		if tw != null and tw.is_valid():
			tw.kill()
		if smooth:
			var from_v := db_to_linear(_sync.get_sync_stream_volume(idx))
			var t := create_tween()
			t.tween_method(_set_layer.bind(idx), from_v, targets[k], 1.0)
			_layer_tweens[k] = t
		else:
			_set_layer(targets[k], idx)


func _set_layer(v: float, idx: int) -> void:
	_sync.set_sync_stream_volume(idx, -80.0 if v <= 0.001 else linear_to_db(v))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "sfx", sfx_on)
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.save(SETTINGS)
