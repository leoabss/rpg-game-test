class_name HittableProp
extends StaticBody3D
## Objeto que reacciona a golpes (arbusto, muñeco, vasija, caja...). Requiere
## hijos `Health`, `Hurtbox` (con su forma) y `Visual` (Node3D con el aspecto:
## malla placeholder y/o un Sprite3D de PixelLab; todo lo de Visual parpadea,
## retrocede y se oculta al romperse). Opcional: `BreakParticles` (CPUParticles3D).
##
## Todo se configura con exports, así un objeto nuevo es solo una escena.

signal hit_count_changed(count: int)
signal broken
signal respawned

@export_group("Reacción al golpe")
## Parpadeo blanco al recibir un golpe.
@export var flash_on_hit: bool = true
@export var flash_time: float = 0.12
## Retroceso del Visual en la dirección del golpe (m) y su duración.
@export var knockback_distance: float = 0.15
@export var knockback_time: float = 0.22
## Inclinación (grados) del Visual al ser golpeado (muñeco: se sacude).
@export var tilt_degrees: float = 0.0
## Número de daño flotante.
@export var show_damage_numbers: bool = false
## Mostrar sobre el objeto la cuenta de golpes recibidos.
@export var show_hit_counter: bool = false
## Altura (m) a la que aparecen números/contador.
@export var label_height: float = 1.2
@export var hit_sound: StringName = &""

@export_group("Rotura")
## Sonido al romperse ("bush", "break"...).
@export var break_sound: StringName = &"break"
## Segundos hasta reaparecer tras romperse (0 = no reaparece).
@export var respawn_time: float = 0.0
## Probabilidad (0..1) de soltar un objeto al romperse.
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.0
## Objetos posibles y su peso relativo (mismo índice).
@export var drop_scenes: Array[PackedScene] = []
@export var drop_weights: PackedFloat32Array = PackedFloat32Array()

var hit_count: int = 0

@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var visual: Node3D = $Visual
@onready var particles: CPUParticles3D = get_node_or_null(^"BreakParticles")

var _flash_material: StandardMaterial3D
var _counter_label: Label3D
var _react_tween: Tween
var _visual_rest: Transform3D


func _ready() -> void:
	_visual_rest = visual.transform
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1, 1, 1, 0)
	if show_hit_counter:
		_counter_label = _make_label("Golpes: 0", 36, Color(1, 1, 1))
		add_child(_counter_label)
		_counter_label.position = Vector3(0, label_height + 0.35, 0)


func _on_damaged(amount: int, info: HitInfo) -> void:
	hit_count += 1
	hit_count_changed.emit(hit_count)
	if _counter_label:
		_counter_label.text = "Golpes: %d" % hit_count
	if hit_sound != &"":
		GameFeel.sfx(hit_sound)
	if show_damage_numbers:
		_spawn_damage_number(amount)
	if health.is_alive():
		_react(info)


func _react(info: HitInfo) -> void:
	if _react_tween:
		_react_tween.kill()
	visual.transform = _visual_rest
	_react_tween = create_tween()
	var dir := info.direction
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
		var push := _visual_rest.origin + dir * maxf(knockback_distance, info.knockback * 0.5)
		var tilt_axis := Vector3.UP.cross(dir).normalized()
		var tilted := _visual_rest.basis.rotated(tilt_axis, deg_to_rad(tilt_degrees)) if tilt_degrees != 0.0 else _visual_rest.basis
		_react_tween.set_parallel(true)
		_react_tween.tween_property(visual, "position", push, knockback_time * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_react_tween.tween_property(visual, "basis", tilted, knockback_time * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_react_tween.chain().tween_property(visual, "position", _visual_rest.origin, knockback_time * 0.75).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_react_tween.parallel().tween_property(visual, "basis", _visual_rest.basis, knockback_time * 0.75).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if flash_on_hit:
		_flash()


func _flash() -> void:
	for g: GeometryInstance3D in visual.find_children("*", "GeometryInstance3D", true, false):
		g.material_overlay = _flash_material
	_flash_material.albedo_color.a = 0.85
	var t := create_tween()
	t.tween_property(_flash_material, "albedo_color:a", 0.0, flash_time).set_delay(flash_time * 0.4)


func _on_died(_info: HitInfo) -> void:
	if _react_tween:
		_react_tween.kill()
	visual.transform = _visual_rest
	visual.visible = false
	hurtbox.set_deferred(&"monitorable", false)
	_set_collision(false)
	if particles:
		particles.restart()
		particles.emitting = true
	GameFeel.sfx(break_sound)
	_try_drop()
	broken.emit()
	if respawn_time > 0.0:
		_respawn_later()


func _respawn_later() -> void:
	await get_tree().create_timer(respawn_time, false).timeout
	# No reaparecer encima del jugador: reintentar en un rato.
	while _player_nearby(1.2):
		await get_tree().create_timer(1.0, false).timeout
	health.revive()
	hurtbox.set_deferred(&"monitorable", true)
	_set_collision(true)
	visual.visible = true
	visual.scale = Vector3.ONE * 0.2
	var t := create_tween()
	t.tween_property(visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	respawned.emit()


func _player_nearby(dist: float) -> bool:
	for p in get_tree().get_nodes_in_group(&"player"):
		if (p as Node3D).global_position.distance_to(global_position) < dist:
			return true
	return false


func _set_collision(enabled: bool) -> void:
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred(&"disabled", not enabled)


func _try_drop() -> void:
	if drop_scenes.is_empty() or randf() >= drop_chance:
		return
	var total := 0.0
	for i in drop_scenes.size():
		total += drop_weights[i] if i < drop_weights.size() else 1.0
	var r := randf() * total
	var chosen := drop_scenes[0]
	for i in drop_scenes.size():
		r -= drop_weights[i] if i < drop_weights.size() else 1.0
		if r <= 0.0:
			chosen = drop_scenes[i]
			break
	var item: Node3D = chosen.instantiate()
	get_parent().add_child(item)
	item.global_position = global_position
	if item.has_method(&"pop_from"):
		item.pop_from(global_position)


func _spawn_damage_number(amount: int) -> void:
	var l := _make_label(str(amount), 64, Color(1.0, 0.92, 0.55))
	get_parent().add_child(l)
	l.global_position = global_position + Vector3(randf_range(-0.2, 0.2), label_height, 0.0)
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y + 0.8, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.4)
	t.chain().tween_callback(l.queue_free)


func _make_label(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0.15, 0.08, 0.05)
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l
