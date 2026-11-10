extends Node
## Sonido del juego: efectos y música (generados por síntesis en tools/audio/gen_audio.py).
## Uso: Sfx.play("card")

const NAMES := ["tap", "card", "draw", "shuffle", "turn", "nope", "yup", "fuse", "explosion", "zombie", "attack", "alarm", "steal", "revive", "win", "lose"]
const SETTINGS := "user://settings.cfg"

var sfx_on := true
var music_on := true
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		sfx_on = cfg.get_value("audio", "sfx", true)
		music_on = cfg.get_value("audio", "music", true)
	for n: String in NAMES:
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
	_music.volume_db = -15.0
	add_child(_music)
	if music_on:
		_music.play()


func play(sound: String, volume_db: float = 0.0, pitch_var: float = 0.05) -> void:
	if not sfx_on or not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func set_sfx(on: bool) -> void:
	sfx_on = on
	_save()


func set_music(on: bool) -> void:
	music_on = on
	if on and not _music.playing:
		_music.play()
	elif not on:
		_music.stop()
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "sfx", sfx_on)
	cfg.set_value("audio", "music", music_on)
	cfg.save(SETTINGS)
