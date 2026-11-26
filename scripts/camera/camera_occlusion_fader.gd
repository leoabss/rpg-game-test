class_name CameraOcclusionFader
extends Node
## Desvanece lo que se interpone entre la cámara y el jugador (casas, árboles).
## Va como hijo de OctopathCamera y usa su `target`.
##
## Cada frame lanza rayos desde la cámara a varios puntos del jugador (cabeza,
## pecho, pies y costados) contra `collision_mask`. Lo que golpean se desvanece
## suavemente; al dejar de tapar, vuelve.
##
## Qué se puede golpear:
##  - Cualquier cuerpo de la capa `world` (paredes, troncos...).
##  - Volúmenes "proxy" en la capa `camera_occluder` (4): StaticBody3D hijo del
##    prop, en el grupo `camera_occluder_proxy`, que cubre lo que la colisión no
##    cubre (techos, copas de árboles). No chocan con el jugador.
##  Se ignora lo que esté en el grupo `no_camera_fade`.
##
## Cómo se desvanece cada malla del prop:
##  - Material con la instance uniform `occlusion_fade` (prop_hd2d.gdshader):
##    dither opaco, conserva la sombra.
##  - Cualquier otro material: GeometryInstance3D.transparency (alpha).

## Capas que pueden tapar: 1 (world) + 4 (camera_occluder).
@export_flags_3d_physics var collision_mask: int = 1 | 8
## Cuánto se desvanece (0..1). En el shader se escala por `occlusion_max`.
@export_range(0.0, 1.0, 0.01) var fade_amount: float = 1.0
## Transparencia máxima para materiales sin dither (fallback).
@export_range(0.0, 1.0, 0.01) var fallback_transparency: float = 0.6
## Unidades de fade por segundo (4 = ~0.25 s).
@export var fade_speed: float = 4.0
## Puntos del jugador a los que se lanzan rayos (relativos a sus pies).
@export var probe_heights: PackedFloat32Array = PackedFloat32Array([0.25, 0.9, 1.6])
## Desplazamiento lateral (eje X de la cámara) de los rayos extra a media altura.
@export var probe_side_offset: float = 0.45
## Máximo de objetos atravesados por rayo.
@export var max_hits_per_ray: int = 4

var _faded: Dictionary = {}       # GeometryInstance3D -> fade actual
var _meshes_by_root: Dictionary = {}  # instance_id del root -> Array[GeometryInstance3D]
var _uses_dither: Dictionary = {}  # GeometryInstance3D -> bool


func _physics_process(delta: float) -> void:
	var cam := get_parent() as Camera3D
	var target: Node3D = cam.get("target") if cam else null
	if cam == null or target == null or not target.is_inside_tree():
		return

	var hit := _find_occluding_meshes(cam, target)
	for m in hit:
		if not _faded.has(m):
			_faded[m] = 0.0
	# Sin tipar la variable: un objeto liberado (roto, recogido...) fallaría al
	# asignarse a un GeometryInstance3D antes de poder comprobarlo.
	for m in _faded.keys():
		if not is_instance_valid(m):
			_faded.erase(m)
			_uses_dither.erase(m)
			continue
		var goal := fade_amount if hit.has(m) else 0.0
		var v := move_toward(float(_faded[m]), goal, fade_speed * delta)
		_apply(m, v)
		if v == 0.0 and goal == 0.0:
			_faded.erase(m)
		else:
			_faded[m] = v


func _find_occluding_meshes(cam: Camera3D, target: Node3D) -> Dictionary:
	var result := {}
	var space := cam.get_world_3d().direct_space_state
	var from := cam.global_position
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	var side := cam.global_basis.x * probe_side_offset
	var points: Array[Vector3] = []
	for h in probe_heights:
		points.append(target.global_position + Vector3.UP * h)
	var mid := target.global_position + Vector3.UP * 0.9
	points.append(mid + side)
	points.append(mid - side)

	for to in points:
		var excl := exclude.duplicate()
		for i in max_hits_per_ray:
			var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, excl)
			q.collide_with_areas = false
			var r := space.intersect_ray(q)
			if r.is_empty():
				break
			excl.append(r["rid"])
			var col := r["collider"] as Node
			if col == null or col.is_in_group(&"no_camera_fade"):
				continue
			var root := col.get_parent() if col.is_in_group(&"camera_occluder_proxy") else col
			for m in _meshes_of(root):
				result[m] = true
	return result


func _meshes_of(root: Node) -> Array:
	var id := root.get_instance_id()
	if not _meshes_by_root.has(id):
		_meshes_by_root[id] = root.find_children("*", "GeometryInstance3D", true, false)
		if not root.tree_exiting.is_connected(_forget_root):
			root.tree_exiting.connect(_forget_root.bind(id))
	return (_meshes_by_root[id] as Array).filter(func(m): return is_instance_valid(m))


func _forget_root(id: int) -> void:
	_meshes_by_root.erase(id)


func _apply(m: GeometryInstance3D, v: float) -> void:
	if not _uses_dither.has(m):
		var mat := m.material_override as ShaderMaterial
		# El uniform puede venir de un include (hd2d_prop_common.gdshaderinc).
		_uses_dither[m] = mat != null and mat.shader != null and (
				mat.shader.code.contains("instance uniform float occlusion_fade")
				or mat.shader.code.contains("hd2d_prop_common.gdshaderinc"))
	if _uses_dither[m]:
		m.set_instance_shader_parameter(&"occlusion_fade", v)
	else:
		m.transparency = v * fallback_transparency
