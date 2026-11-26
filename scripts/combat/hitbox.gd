class_name Hitbox
extends Area3D
## Zona de golpe de un ataque. Se mantiene monitoreando Hurtboxes (capa 5) y el
## dueño llama `begin_attack()` al empezar el ataque y `strike()` en el frame
## del golpe: aplica el golpe a cada Hurtbox solapado, una sola vez por ataque.
## El tamaño se ajusta con `radius` (forma esférica del CollisionShape3D hijo).

signal hit_landed(targets: int)

static var _next_attack_id: int = 1

@export var damage: int = 1
@export var knockback: float = 0.3
## Radio de la esfera de golpe (m). Se aplica a la forma hija.
@export var radius: float = 0.45:
	set(value):
		radius = value
		_apply_radius()
## Llamar a GameFeel.impact() (hitstop, sacudida, sonido) al acertar.
@export var impact_feedback: bool = true

var attack_id: int = 0


func _ready() -> void:
	monitoring = true
	monitorable = false
	_apply_radius()


## Nuevo ataque: los Hurtbox vuelven a aceptar un golpe de este hitbox.
func begin_attack() -> int:
	attack_id = _next_attack_id
	_next_attack_id += 1
	return attack_id


## Aplica el golpe a todo lo que esté dentro ahora. Devuelve cuántos impactaron.
func strike(direction: Vector3, source: Node = null) -> int:
	var count := 0
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or (source and hurtbox.owner == source):
			continue
		var info := HitInfo.create(damage, direction, knockback, attack_id, source)
		if hurtbox.receive_hit(info):
			count += 1
	if count > 0:
		if impact_feedback:
			GameFeel.impact()
		hit_landed.emit(count)
	return count


func _apply_radius() -> void:
	if not is_node_ready():
		return
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs and cs.shape is SphereShape3D:
			(cs.shape as SphereShape3D).radius = radius
