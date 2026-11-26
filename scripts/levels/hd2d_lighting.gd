@tool
class_name Hd2dLighting
extends Node
## Panel único para ajustar la iluminación HD-2D de un nivel desde el Inspector:
## sol (color, intensidad, ángulo, suavidad de sombra) y ambiente/niebla.
##
## Es @tool: los cambios se ven en vivo en el editor. Este nodo es la fuente de
## verdad para estos valores: los sobreescribe en el Sun y en el Environment al
## cargar. Ojo: el Environment es un recurso compartido
## (resources/hd2d_environment.tres), así que lo que cambies aquí afecta a todos
## los niveles que lo usen.
##
## Look Octopath: sol cálido y bajo (sombras largas) + ambiente azulado (las
## sombras quedan frías). Ese contraste cálido/frío es gran parte del estilo.

@export var sun: DirectionalLight3D:
	set(value):
		sun = value
		_apply()
@export var world_environment: WorldEnvironment:
	set(value):
		world_environment = value
		_apply()

@export_group("Sol")
@export var sun_color: Color = Color(1.0, 0.82, 0.6):
	set(value):
		sun_color = value
		_apply()
@export_range(0.0, 8.0, 0.05) var sun_energy: float = 2.2:
	set(value):
		sun_energy = value
		_apply()
## Altura del sol sobre el horizonte. Bajo = sombras largas.
@export_range(1.0, 89.0, 0.5) var sun_elevation_degrees: float = 28.0:
	set(value):
		sun_elevation_degrees = value
		_apply()
## Rumbo del sol alrededor del eje Y. -60° = sol desde la izquierda-frente:
## sombras largas hacia la derecha y fachadas (que miran a cámara) iluminadas.
## Valores < -90° ponen el sol a contraluz (sombras hacia cámara, más neblina).
@export_range(-180.0, 180.0, 0.5) var sun_azimuth_degrees: float = -60.0:
	set(value):
		sun_azimuth_degrees = value
		_apply()
## Tamaño aparente del sol: mayor = penumbra más suave (PCSS).
@export_range(0.0, 10.0, 0.1) var shadow_softness: float = 1.5:
	set(value):
		shadow_softness = value
		_apply()

@export_group("Ambiente")
## Color de la luz ambiental = color de las zonas en sombra.
@export var ambient_color: Color = Color(0.5, 0.62, 0.85):
	set(value):
		ambient_color = value
		_apply()
@export_range(0.0, 4.0, 0.01) var ambient_energy: float = 0.55:
	set(value):
		ambient_energy = value
		_apply()
@export_range(0.0, 0.1, 0.001) var fog_density: float = 0.005:
	set(value):
		fog_density = value
		_apply()
@export var fog_color: Color = Color(0.85, 0.85, 0.9):
	set(value):
		fog_color = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	if sun:
		sun.light_color = sun_color
		sun.light_energy = sun_energy
		sun.light_angular_distance = shadow_softness
		# rotation (no transform a mano) para que la base quede ortonormal.
		sun.rotation = Vector3(deg_to_rad(-sun_elevation_degrees), deg_to_rad(sun_azimuth_degrees), 0.0)
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = ambient_energy
		env.volumetric_fog_density = fog_density
		env.volumetric_fog_albedo = fog_color
