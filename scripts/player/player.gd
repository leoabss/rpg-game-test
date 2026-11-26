class_name Player
extends CharacterBody3D
## Jugador: movimiento en 8 direcciones sobre el plano XZ, caminar/correr con
## aceleración suave y ataque básico en la última dirección mirada.
##
## Visual: por ahora una cápsula (Placeholder). El nodo Sprite (AnimatedSprite3D)
## ya está configurado (billboard Y, filtro nearest, alpha cut) y se activa solo
## cuando se le asigna un SpriteFrames. Las animaciones se buscan con el patrón
## "<estado>_<direccion>", p.ej. "walk_down_left", "idle_up", "attack_right".

signal attacked(direction: Vector3)

## Nombres de las 8 direcciones, en orden angular empezando por la derecha
## (en espacio de input, +Y = hacia la cámara = "down").
const DIRECTION_NAMES: Array[StringName] = [
	&"right", &"down_right", &"down", &"down_left",
	&"left", &"up_left", &"up", &"up_right",
]

@export_group("Movimiento")
@export var walk_speed: float = 3.5
@export var run_speed: float = 6.5
## Unidades/s² al acelerar hacia la velocidad objetivo.
@export var acceleration: float = 28.0
## Unidades/s² al frenar sin input.
@export var deceleration: float = 36.0

@export_group("Ataque")
@export var attack_cooldown: float = 0.35
## Distancia del hitbox respecto al centro del jugador.
@export var attack_reach: float = 0.9
@export var attack_active_time: float = 0.12

@export_group("Visual")
## Si es true y el Sprite tiene SpriteFrames, se oculta la cápsula placeholder.
@export var use_sprite_when_available: bool = true

## Última dirección mirada en espacio de input (2D, normalizada).
var facing: Vector2 = Vector2.DOWN
## Última dirección mirada en el mundo (3D, plano XZ, normalizada).
var facing_3d: Vector3 = Vector3.BACK
var is_running: bool = false
var is_attacking: bool = false

var _attack_cooldown_left: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var sprite: AnimatedSprite3D = $Sprite
@onready var placeholder: Node3D = $Placeholder
@onready var attack_hitbox: Area3D = $AttackHitbox
@onready var attack_flash: MeshInstance3D = $AttackHitbox/Flash


func _ready() -> void:
	var has_frames := sprite.sprite_frames != null
	sprite.visible = has_frames and use_sprite_when_available
	placeholder.visible = not sprite.visible
	attack_hitbox.monitoring = false
	attack_flash.visible = false
	_update_hitbox_position()


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)

	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	is_running = Input.is_action_pressed(&"run")

	if input_dir.length_squared() > 0.0001:
		facing = input_dir.normalized()
		facing_3d = Vector3(facing.x, 0.0, facing.y)
		_update_hitbox_position()

	# Velocidad horizontal con aceleración/desaceleración suave.
	var speed := run_speed if is_running else walk_speed
	var target := Vector2(input_dir.x, input_dir.y) * speed
	var current := Vector2(velocity.x, velocity.z)
	var rate := acceleration if input_dir != Vector2.ZERO else deceleration
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
	if _attack_cooldown_left > 0.0:
		return
	_attack_cooldown_left = attack_cooldown
	is_attacking = true
	attack_hitbox.monitoring = true
	attack_flash.visible = true
	attacked.emit(facing_3d)

	await get_tree().create_timer(attack_active_time, false, true).timeout
	for body in attack_hitbox.get_overlapping_bodies():
		if body != self and body.has_method(&"take_hit"):
			body.take_hit(facing_3d)
	attack_hitbox.monitoring = false
	attack_flash.visible = false
	is_attacking = false


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


func _update_hitbox_position() -> void:
	attack_hitbox.position = Vector3(0.0, 0.9, 0.0) + facing_3d * attack_reach


func _update_visuals() -> void:
	# La cápsula gira para mostrar hacia dónde mira (debug visual).
	placeholder.rotation.y = atan2(-facing_3d.x, -facing_3d.z)

	if not sprite.visible or sprite.sprite_frames == null:
		return
	var anim := StringName("%s_%s" % [get_anim_state(), get_facing_name()])
	if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)
