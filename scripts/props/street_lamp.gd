@tool
extends StaticBody3D
## Farol: expone color/intensidad/alcance de su luz para ajustarlos por instancia.

@export var light_color: Color = Color(1.0, 0.56, 0.22):
	set(value):
		light_color = value
		_apply()
@export_range(0.0, 16.0, 0.1) var light_energy: float = 4.0:
	set(value):
		light_energy = value
		_apply()
@export_range(0.5, 30.0, 0.1) var light_range: float = 8.0:
	set(value):
		light_range = value
		_apply()
## Cuánto ilumina la niebla volumétrica (halo alrededor del farol).
@export_range(0.0, 8.0, 0.1) var fog_glow: float = 2.0:
	set(value):
		fog_glow = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	var light := $Lantern/Light as OmniLight3D
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = light_range
	light.light_volumetric_fog_energy = fog_glow
