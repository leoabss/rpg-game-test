@tool
class_name OctopathCamera
extends Camera3D
## Cámara estilo HD-2D: perspectiva, FOV bajo, inclinación baja (pitch) mirando
## al objetivo desde "atrás" (+Z), seguimiento suavizado y profundidad de campo
## calculada relativa a la distancia al objetivo (efecto miniatura / tilt-shift).
##
## Es @tool: al cambiar cualquier valor en el Inspector la cámara se recoloca y
## el DOF se recalcula en el editor, así se ve el encuadre sin darle a Play.

@export var target: Node3D:
	set(value):
		target = value
		_refresh()

@export_group("Encuadre")
## Inclinación hacia abajo en grados. Más bajo = más "de lado", se ve menos
## suelo y las verticales se inclinan menos (Octopath ≈ 15-20°).
@export_range(5.0, 85.0, 0.5) var pitch_degrees: float = 18.0:
	set(value):
		pitch_degrees = value
		_refresh()
## Distancia de la cámara al punto de enfoque.
@export_range(2.0, 60.0, 0.1) var distance: float = 14.0:
	set(value):
		distance = value
		_refresh()
## Desplazamiento del punto de enfoque respecto al target (p.ej. altura del pecho).
@export var focus_offset: Vector3 = Vector3(0.0, 1.2, 0.0):
	set(value):
		focus_offset = value
		_refresh()
@export_range(5.0, 90.0, 0.5) var field_of_view: float = 28.0:
	set(value):
		field_of_view = value
		_refresh()

@export_group("Seguimiento")
## Mayor = sigue más rápido. 0 = sin suavizado.
@export var follow_smoothing: float = 6.0

@export_group("Profundidad de campo")
@export var dof_enabled: bool = true:
	set(value):
		dof_enabled = value
		_refresh()
## Lo que esté más lejos que (distance + far_margin) empieza a desenfocarse.
@export_range(0.0, 50.0, 0.1) var dof_far_margin: float = 5.0:
	set(value):
		dof_far_margin = value
		_refresh()
@export_range(0.1, 50.0, 0.1) var dof_far_transition: float = 14.0:
	set(value):
		dof_far_transition = value
		_refresh()
## Lo que esté más cerca que (distance - near_margin) empieza a desenfocarse.
@export_range(0.0, 50.0, 0.1) var dof_near_margin: float = 2.5:
	set(value):
		dof_near_margin = value
		_refresh()
@export_range(0.1, 50.0, 0.1) var dof_near_transition: float = 3.0:
	set(value):
		dof_near_transition = value
		_refresh()
## Intensidad del desenfoque (cerca y lejos).
@export_range(0.0, 1.0, 0.01) var dof_blur_amount: float = 0.1:
	set(value):
		dof_blur_amount = value
		_refresh()

var _focus_point: Vector3
var _shake_strength: float = 0.0
var _shake_start_usec: int = 0
var _shake_duration_usec: int = 0


## Sacudida leve (la llama GameFeel). Usa h_offset/v_offset, así no interfiere
## con el seguimiento, y tiempo real para seguir durante el hitstop.
func shake(strength: float, duration: float) -> void:
	if strength < _current_shake_strength():
		return
	_shake_strength = strength
	_shake_start_usec = Time.get_ticks_usec()
	_shake_duration_usec = int(duration * 1_000_000.0)


func _current_shake_strength() -> float:
	if _shake_duration_usec <= 0:
		return 0.0
	var t := float(Time.get_ticks_usec() - _shake_start_usec) / _shake_duration_usec
	return 0.0 if t >= 1.0 else _shake_strength * (1.0 - t) * (1.0 - t)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var s := _current_shake_strength()
	h_offset = randf_range(-s, s)
	v_offset = randf_range(-s, s) * 0.7


func _ready() -> void:
	_refresh()
	if target:
		_focus_point = target.global_position + focus_offset
		global_position = _desired_position()


func _physics_process(delta: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var goal := target.global_position + focus_offset
	if Engine.is_editor_hint() or follow_smoothing <= 0.0:
		_focus_point = goal
	else:
		# Suavizado exponencial independiente del framerate.
		_focus_point = _focus_point.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
	global_position = _desired_position()


func _desired_position() -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	var back := Vector3(0.0, sin(pitch), cos(pitch))
	return _focus_point + back * distance


## Reaplica encuadre y DOF. Se llama sola al cambiar cualquier export.
func _refresh() -> void:
	if not is_node_ready():
		return
	fov = field_of_view
	rotation = Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0)
	if target and target.is_inside_tree():
		_focus_point = target.global_position + focus_offset
		global_position = _desired_position()
	apply_dof()


## Aplica los parámetros de DOF al CameraAttributesPractical de la cámara.
func apply_dof() -> void:
	var attrs := attributes as CameraAttributesPractical
	if attrs == null:
		attrs = CameraAttributesPractical.new()
		attributes = attrs
	attrs.dof_blur_far_enabled = dof_enabled
	attrs.dof_blur_far_distance = distance + dof_far_margin
	attrs.dof_blur_far_transition = dof_far_transition
	attrs.dof_blur_near_enabled = dof_enabled
	attrs.dof_blur_near_distance = maxf(distance - dof_near_margin, 0.1)
	attrs.dof_blur_near_transition = dof_near_transition
	attrs.dof_blur_amount = dof_blur_amount
