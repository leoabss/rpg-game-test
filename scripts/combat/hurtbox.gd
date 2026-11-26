class_name Hurtbox
extends Area3D
## Zona que puede recibir golpes. Detección Area-Area con el Hitbox del atacante
## (Jolt no detecta StaticBody3D desde un Area3D, pero Area-Area sí).
##
## Uso: agregar como hijo un Hurtbox (con su CollisionShape3D) y un Health a
## cualquier objeto. Capa: `hurtbox` (5). `monitorable` debe estar activo.

signal hit_received(info: HitInfo)

## Health a la que se aplica el daño. Si está vacío, busca un hijo "Health" del padre.
@export var health: Health
## Si es false, ignora golpes (p.ej. mientras el objeto está destruido).
@export var active: bool = true

var _last_attack_id: int = -1


func _ready() -> void:
	if health == null and get_parent():
		health = get_parent().get_node_or_null(^"Health") as Health


## Devuelve true si el golpe se aplicó. Un mismo attack_id solo impacta una vez.
func receive_hit(info: HitInfo) -> bool:
	if not active or (health and not health.is_alive()):
		return false
	if info.attack_id == _last_attack_id:
		return false
	_last_attack_id = info.attack_id
	if health:
		health.apply_damage(info)
	hit_received.emit(info)
	return true
