@tool
class_name ModelProp
extends StaticBody3D
## Prop basado en un modelo importado (.glb): aplica `material` como override a
## todas las mallas del modelo. Así el material (prop_hd2d / foliage_hd2d, con
## brillo/saturación/roughness) vive en la escena del prop y se ajusta desde el
## Inspector, sin tocar el .glb (que se regenera con tools/optimize_model.py).

@export var material: Material:
	set(value):
		material = value
		_apply()

## Parámetros `instance uniform` por instancia (p.ej. {"hue_shift": 0.02} en
## árboles). Se aplican a todas las mallas del prop; no duplican el material.
@export var instance_params: Dictionary = {}:
	set(value):
		instance_params = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		for key in instance_params:
			mesh.set_instance_shader_parameter(StringName(key), instance_params[key])
