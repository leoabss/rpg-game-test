extends Node
## Autoload "GameFeel": sensación de golpe centralizada.
##  - hitstop(): congela el juego unos ms (Engine.time_scale = 0, se restaura con
##    un timer que ignora la escala de tiempo).
##  - shake(): sacudida de la cámara actual (si tiene método `shake`).
##  - sfx(): sonidos placeholder generados por código (sin archivos). Para usar
##    sonidos reales, poner un AudioStream en `sounds[nombre]` (o reemplazar
##    `_make_sounds()`); los nombres usados son: hit, break, bush, coin, heart, swing.

@export var hitstop_seconds: float = 0.07
@export var shake_strength: float = 0.06
@export var shake_duration: float = 0.18
@export var sfx_volume_db: float = -10.0
## Silenciar sonidos (p.ej. en tests).
@export var mute: bool = false

var sounds: Dictionary = {}

var _hitstop_token: int = 0
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_sounds()
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = sfx_volume_db
		add_child(p)
		_players.append(p)


## Todo junto, para cuando un ataque acierta.
func impact() -> void:
	hitstop(hitstop_seconds)
	shake(shake_strength, shake_duration)
	sfx(&"hit")


func hitstop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	# Cada hitstop invalida al anterior (token); solo el último restaura la
	# escala. No comparar con el reloj del sistema: el timer cuenta tiempo de
	# frames, que puede no coincidir con el reloj, y el juego quedaría congelado.
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.0
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0


func is_in_hitstop() -> bool:
	return Engine.time_scale == 0.0


func shake(strength: float, duration: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method(&"shake"):
		cam.shake(strength, duration)


func sfx(sound_name: StringName, pitch_variation: float = 0.08) -> void:
	if mute or not sounds.has(sound_name):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = sounds[sound_name]
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


# --- Sonidos placeholder ------------------------------------------------------

const RATE := 22050


func _make_sounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# Golpe seco: ruido corto + tono grave.
	sounds[&"hit"] = _wav(0.09, func(t: float, _i: int) -> float:
		var env := exp(-t * 45.0)
		return (rng.randf_range(-1, 1) * 0.6 + sin(TAU * 110.0 * t) * 0.8) * env)
	# Rotura (vasija/caja): ruido más largo con chasquidos.
	sounds[&"break"] = _wav(0.32, func(t: float, _i: int) -> float:
		var env := exp(-t * 10.0)
		var crack := 1.0 if fmod(t, 0.045) < 0.006 else 0.35
		return rng.randf_range(-1, 1) * env * crack)
	# Arbusto: ruido suave y agudo (hojas).
	var last := [0.0]
	sounds[&"bush"] = _wav(0.22, func(t: float, _i: int) -> float:
		var n := rng.randf_range(-1, 1)
		var hp: float = n - last[0]  # filtro paso alto simple
		last[0] = n
		return hp * 0.5 * exp(-t * 12.0) * (0.6 + 0.4 * sin(TAU * 23.0 * t)))
	# Moneda: dos notas.
	sounds[&"coin"] = _wav(0.16, func(t: float, _i: int) -> float:
		var f := 988.0 if t < 0.06 else 1319.0
		return signf(sin(TAU * f * t)) * 0.35 * exp(-t * 14.0))
	# Corazón: barrido ascendente.
	sounds[&"heart"] = _wav(0.22, func(t: float, _i: int) -> float:
		var f := lerpf(523.0, 1046.0, t / 0.22)
		return sin(TAU * f * t) * 0.6 * exp(-t * 8.0))
	# Golpe al aire.
	sounds[&"swing"] = _wav(0.12, func(t: float, _i: int) -> float:
		return rng.randf_range(-1, 1) * 0.18 * sin(PI * t / 0.12))


func _wav(seconds: float, gen: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(float(gen.call(float(i) / RATE, i)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
