class_name HitInfo
extends RefCounted
## Datos de un golpe: lo crea el Hitbox al impactar y lo recibe el Hurtbox.

## Puntos de daño.
var damage: int = 1
## Dirección del golpe en el mundo (plano XZ, normalizada).
var direction: Vector3 = Vector3.ZERO
## Distancia de retroceso sugerida para el que recibe (m).
var knockback: float = 0.3
## Identificador del ataque: un Hurtbox ignora el mismo id dos veces
## (evita golpes dobles si el hitbox sigue activo varios frames).
var attack_id: int = 0
## Nodo que atacó (p.ej. el Player).
var source: Node = null


static func create(p_damage: int, p_direction: Vector3, p_knockback: float, p_attack_id: int, p_source: Node) -> HitInfo:
	var info := HitInfo.new()
	info.damage = p_damage
	info.direction = p_direction
	info.knockback = p_knockback
	info.attack_id = p_attack_id
	info.source = p_source
	return info
