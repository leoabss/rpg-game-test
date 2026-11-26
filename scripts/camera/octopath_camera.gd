class_name OctopathCamera
extends Camera3D
## Cámara estilo HD-2D: perspectiva, FOV bajo, inclinada (pitch) mirando al
## objetivo desde "atrás" (+Z), seguimiento suavizado y profundidad de campo
## calculada relativa a la distancia al objetivo (efecto miniatura / tilt-shift).

@export var target: Node3D

@export_group("Encuadre")
## Inclinación hacia abajo en grados (Octopath ~30°).
@export_range(5.0, 85.0, 0.5) var pitch_degrees: float = 30.0
## Distancia de la cámara al punto de enfoque.
@export var distance: float = 18.0
## Desplazamiento del punto de enfoque respecto al target (p.ej. altura del pecho).
@export var focus_offset: Vector3 = Vector3(0.0, 1.0, 0.0)
@export_range(5.0, 90.0, 0.5) var field_of_view: float = 30.0

@export_group("Seguimiento")
## Mayor = sigue más rápido. 0 = sin suavizado.
@export var follow_smoothing: float = 6.0

@export_group("Profundidad de campo")
@export var dof_enabled: bool = true
## Todo lo que esté más lejos que (distance + far_margin) empieza a desenfocarse.
@export var dof_far_margin: float = 5.0
@export var dof_far_transition: float = 12.0
## Todo lo que esté más cerca que (distance - near_margin) empieza a desenfocarse.
@export var dof_near_margin: float = 7.0
@export var dof_near_transition: float = 4.0
@export_range(0.0, 1.0, 0.01) var dof_blur_amount: float = 0.12

var _focus_point: Vector3


func _ready() -> void:
	fov = field_of_view
	rotation = Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0)
	apply_dof()
	if target:
		_focus_point = target.global_position + focus_offset
		global_position = _desired_position()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_position + focus_offset
	if follow_smoothing <= 0.0:
		_focus_point = goal
	else:
		# Suavizado exponencial independiente del framerate.
		_focus_point = _focus_point.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
	global_position = _desired_position()


func _desired_position() -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	var back := Vector3(0.0, sin(pitch), cos(pitch))
	return _focus_point + back * distance


## Aplica los parámetros de DOF al CameraAttributesPractical de la cámara.
## Llamar de nuevo si se cambian los valores en runtime.
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
