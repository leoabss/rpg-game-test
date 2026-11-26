class_name Player
extends CharacterBody3D
## Jugador: movimiento en 8 direcciones sobre el plano XZ, caminar/correr con
## aceleración suave y ataque en la última dirección mirada.
##
## Visual: AnimatedSprite3D (`Sprite`) con un SpriteFrames generado por
## tools/build_sprite_frames.gd. Las animaciones se llaman "<estado>_<direccion>"
## (idle_down, walk_up_left, attack_right...). Si falta alguna se usa la más
## cercana (ver `_resolve_animation`), así funciona con 4 u 8 direcciones y con
## estados incompletos. Sin SpriteFrames se muestra la cápsula placeholder.

signal attacked(direction: Vector3)

## Nombres de las 8 direcciones, en orden angular empezando por la derecha
## (en espacio de input, +Y = hacia la cámara = "down").
const DIRECTION_NAMES: Array[StringName] = [
	&"right", &"down_right", &"down", &"down_left",
	&"left", &"up_left", &"up", &"up_right",
]
## Estado -> estados alternativos si no existe su animación.
const STATE_FALLBACKS := {
	&"run": [&"walk", &"idle"],
	&"walk": [&"idle"],
	&"attack": [&"idle"],
	## Sin idle: se usa el primer frame de walk/run, en pausa.
	&"idle": [&"walk", &"run"],
}

@export_group("Movimiento")
@export var walk_speed: float = 3.5
@export var run_speed: float = 6.5
## Unidades/s² al acelerar hacia la velocidad objetivo.
@export var acceleration: float = 28.0
## Unidades/s² al frenar sin input.
@export var deceleration: float = 36.0
## Frenado durante el ataque (alto = se planta en el sitio).
@export var attack_deceleration: float = 60.0

@export_group("Ataque")
@export var attack_cooldown: float = 0.15
## Hitbox del ataque: esfera centrada a `attack_reach` m del centro del jugador
## (en la dirección mirada), a `attack_height` m del suelo, de radio
## `attack_radius`. Alcance total = reach + radius. Puño actual: el puño
## llega a 0.72-0.86 m (medido en los frames de impacto) -> 0.55 + 0.35 = 0.9 m.
## Para una espada: subir reach/radius (p.ej. 0.8 + 0.6).
@export var attack_reach: float = 0.55:
	set(value):
		attack_reach = value
		if is_node_ready():
			_update_hitbox_position()
@export var attack_radius: float = 0.35:
	set(value):
		attack_radius = value
		if is_node_ready():
			_update_hitbox_position()
@export var attack_height: float = 0.9:
	set(value):
		attack_height = value
		if is_node_ready():
			_update_hitbox_position()
@export var attack_damage: int = 1
@export var attack_knockback: float = 0.3
## Mostrar la esfera del hitbox un instante al golpear (debug).
@export var show_hit_flash: bool = false
## Solo si NO hay animación de ataque: duración total y momento del golpe.
@export var fallback_attack_duration: float = 0.35
@export var fallback_attack_hit_time: float = 0.12
## Cuánto se ve el destello del golpe (debug).
@export var hit_flash_time: float = 0.1

@export_group("Visual")
## Altura del personaje en metros (puertas = 1.7 m). Con un SpriteFrames que
## tenga metadata `body_height_px`, se calcula pixel_size a partir de esto.
@export var character_height: float = 1.65
## Velocidad de reproducción de idle/walk/run (multiplica los FPS del SpriteFrames).
@export var idle_anim_speed: float = 1.0
@export var walk_anim_speed: float = 1.0
@export var run_anim_speed: float = 1.0

## Última dirección mirada en espacio de input (2D, normalizada).
var facing: Vector2 = Vector2.DOWN
## Última dirección mirada en el mundo (3D, plano XZ, normalizada).
var facing_3d: Vector3 = Vector3.BACK
var is_running: bool = false
var is_attacking: bool = false

var _attack_cooldown_left: float = 0.0
var _attack_elapsed: float = 0.0
var _attack_uses_anim: bool = false
var _attack_hit_done: bool = false
var _hit_frame: int = 0
## Caché "<estado>_<dir>" -> [animación real, flip_h].
var _anim_cache: Dictionary = {}
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var sprite: AnimatedSprite3D = $Sprite
@onready var placeholder: Node3D = $Placeholder
@onready var attack_hitbox: Hitbox = $AttackHitbox
@onready var attack_flash: MeshInstance3D = $AttackHitbox/Flash


func _ready() -> void:
	attack_flash.visible = false
	sprite.animation_finished.connect(_on_sprite_animation_finished)
	setup_sprite()
	_update_hitbox_position()


## Configura el sprite según el SpriteFrames asignado: tamaño, pies en el
## suelo y visibilidad del placeholder. Llamar de nuevo si se cambia `sprite_frames`.
func setup_sprite() -> void:
	_anim_cache.clear()
	var frames := sprite.sprite_frames
	sprite.visible = frames != null
	placeholder.visible = frames == null
	if frames == null:
		return
	sprite.centered = true
	sprite.position = Vector3.ZERO
	if frames.has_meta(&"body_height_px") and int(frames.get_meta(&"body_height_px")) > 0:
		sprite.pixel_size = character_height / float(frames.get_meta(&"body_height_px"))
	# Pies en el origen del CharacterBody3D (= suelo).
	sprite.offset = Vector2(0.0, float(frames.get_meta(&"foot_offset_px", 0.0)))


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)

	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	is_running = Input.is_action_pressed(&"run")

	if is_attacking:
		_process_attack(delta)
		input_dir = Vector2.ZERO  # el ataque bloquea el movimiento y el giro
	elif input_dir.length_squared() > 0.0001:
		facing = input_dir.normalized()
		facing_3d = Vector3(facing.x, 0.0, facing.y)
		_update_hitbox_position()

	# Velocidad horizontal con aceleración/desaceleración suave.
	var speed := run_speed if is_running else walk_speed
	var target := input_dir * speed
	var current := Vector2(velocity.x, velocity.z)
	var rate := acceleration
	if is_attacking:
		rate = attack_deceleration
	elif input_dir == Vector2.ZERO:
		rate = deceleration
	current = current.move_toward(target, rate * delta)
	velocity.x = current.x
	velocity.z = current.y

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	if Input.is_action_just_pressed(&"attack"):
		attack()

	_update_visuals()


func attack() -> void:
	if is_attacking or _attack_cooldown_left > 0.0:
		return
	is_attacking = true
	_attack_elapsed = 0.0
	_attack_hit_done = false
	attack_hitbox.begin_attack()  # nuevo attack_id: cada objetivo recibe 1 golpe por ataque
	attack_hitbox.damage = attack_damage
	attack_hitbox.knockback = attack_knockback
	GameFeel.sfx(&"swing")
	attacked.emit(facing_3d)

	var resolved := _resolve_animation(&"attack", get_facing_name())
	_attack_uses_anim = resolved[0] != &"" and String(resolved[0]).begins_with("attack_")
	if _attack_uses_anim:
		_hit_frame = _get_hit_frame(resolved[0])
		sprite.flip_h = resolved[1]
		sprite.speed_scale = 1.0
		sprite.play(resolved[0])
		sprite.frame = 0


## Frame de impacto de una animación de ataque, según la metadata
## `hit_frames` del SpriteFrames: {"attack": {"<dir>": frame}} (por dirección,
## porque PixelLab no sincroniza el golpe entre direcciones) o {"attack": frame}.
## Se usa la dirección de la animación que realmente suena (tras el fallback).
func _get_hit_frame(anim: StringName) -> int:
	var count := sprite.sprite_frames.get_frame_count(anim)
	var cfg: Variant = (sprite.sprite_frames.get_meta(&"hit_frames", {}) as Dictionary).get("attack", count / 2)
	if cfg is Dictionary:
		cfg = cfg.get(String(anim).trim_prefix("attack_"), count / 2)
	return clampi(int(cfg), 0, count - 1)


func _process_attack(delta: float) -> void:
	_attack_elapsed += delta
	if _attack_uses_anim:
		# Golpe sincronizado con el frame de impacto de la animación.
		if not _attack_hit_done and sprite.frame >= _hit_frame:
			_do_hit()
		# El final lo marca `animation_finished`; red de seguridad por si acaso.
		if _attack_elapsed > 3.0:
			_end_attack()
	else:
		if not _attack_hit_done and _attack_elapsed >= fallback_attack_hit_time:
			_do_hit()
		if _attack_elapsed >= fallback_attack_duration:
			_end_attack()


func _do_hit() -> void:
	_attack_hit_done = true
	# Golpea a los Hurtbox solapados (Area-Area). Hitstop/sacudida/sonido los
	# dispara el Hitbox vía GameFeel si acierta.
	attack_hitbox.strike(facing_3d, self)
	if show_hit_flash:
		attack_flash.visible = true
		get_tree().create_timer(hit_flash_time, false, true).timeout.connect(
			func(): attack_flash.visible = false)


func _end_attack() -> void:
	if not is_attacking:
		return
	if not _attack_hit_done:
		_do_hit()
	is_attacking = false
	_attack_cooldown_left = attack_cooldown


func _on_sprite_animation_finished() -> void:
	if is_attacking and _attack_uses_anim:
		_end_attack()


## Devuelve el nombre de la dirección (de 8) más cercana a `facing`.
func get_facing_name() -> StringName:
	var index := wrapi(roundi(facing.angle() / (PI / 4.0)), 0, 8)
	return DIRECTION_NAMES[index]


## Estado de animación actual: "attack", "run", "walk" o "idle".
func get_anim_state() -> StringName:
	if is_attacking:
		return &"attack"
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.1:
		return &"idle"
	return &"run" if is_running else &"walk"


## Busca la animación a usar para (estado, dirección). Devuelve [nombre, flip_h];
## nombre vacío si no hay nada utilizable. Orden de búsqueda:
##   1. misma dirección; 2. direcciones vecinas de más cercana a más lejana
##   (en diagonales prefiere la horizontal: down_right -> right -> down);
##   3. espejo horizontal (left <-> right con flip_h);
##   4. lo mismo con los estados de STATE_FALLBACKS (run -> walk -> idle).
func _resolve_animation(state: StringName, dir: StringName) -> Array:
	var key := StringName("%s_%s" % [state, dir])
	if _anim_cache.has(key):
		return _anim_cache[key]
	var result: Array = [&"", false]
	var frames := sprite.sprite_frames
	if frames:
		var states: Array = [state]
		states.append_array(STATE_FALLBACKS.get(state, [&"idle"]))
		for s in states:
			result = _find_in_state(frames, s, dir)
			if result[0] != &"":
				break
	_anim_cache[key] = result
	return result


func _find_in_state(frames: SpriteFrames, state: StringName, dir: StringName) -> Array:
	var i := DIRECTION_NAMES.find(dir)
	# Offsets en pasos de 45°. En diagonales (índice impar) los vecinos ±1 son
	# cardinales; se prueba primero el horizontal (right/left = índice par 0 o 4).
	var order: Array[int] = [0]
	for step in range(1, 5):
		var a := wrapi(i + step, 0, 8)
		var b := wrapi(i - step, 0, 8)
		var a_horizontal := a == 0 or a == 4
		order.append_array([step, -step] if a_horizontal or not (b == 0 or b == 4) else [-step, step])
	for flip in [false, true]:
		for off in order:
			var d: StringName = DIRECTION_NAMES[wrapi(i + off, 0, 8)]
			if flip:
				d = _mirror(d)
			var anim := StringName("%s_%s" % [state, d])
			if frames.has_animation(anim):
				return [anim, flip]
	return [&"", false]


func _mirror(dir: StringName) -> StringName:
	var s := String(dir)
	if s.contains("left"):
		return StringName(s.replace("left", "right"))
	if s.contains("right"):
		return StringName(s.replace("right", "left"))
	return dir


func _update_hitbox_position() -> void:
	attack_hitbox.position = Vector3(0.0, attack_height, 0.0) + facing_3d * attack_reach
	attack_hitbox.radius = attack_radius
	# El destello de debug es una esfera de radio 0.45: escalarla al radio real.
	attack_flash.scale = Vector3.ONE * (attack_radius / 0.45)


func _update_visuals() -> void:
	placeholder.rotation.y = atan2(-facing_3d.x, -facing_3d.z)
	if not sprite.visible or (is_attacking and _attack_uses_anim):
		return  # durante el ataque la animación la controla attack()
	var state := get_anim_state()
	var resolved := _resolve_animation(state, get_facing_name())
	if resolved[0] == &"":
		return
	sprite.flip_h = resolved[1]
	match state:
		&"run":
			# Si "run" cae a "walk", se acelera para que se note la carrera.
			var boost := run_speed / walk_speed if String(resolved[0]).begins_with("walk_") else 1.0
			sprite.speed_scale = run_anim_speed * boost
		&"walk":
			sprite.speed_scale = walk_anim_speed
		_:
			sprite.speed_scale = idle_anim_speed
			if not String(resolved[0]).begins_with("idle_"):
				# Idle "prestado": pose fija en el primer frame.
				if sprite.animation != resolved[0] or sprite.is_playing():
					sprite.animation = resolved[0]
					sprite.frame = 0
					sprite.pause()
				return
	if sprite.animation != resolved[0] or not sprite.is_playing():
		sprite.play(resolved[0])
