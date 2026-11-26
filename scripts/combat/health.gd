class_name Health
extends Node
## Vida de cualquier objeto/personaje golpeable. Se usa junto a un Hurtbox.

signal damaged(amount: int, info: HitInfo)
signal died(info: HitInfo)
signal revived

@export var max_hp: int = 1
## Recibe golpes (emite `damaged`) pero nunca pierde vida ni muere
## (muñeco de entrenamiento).
@export var immortal: bool = false

var hp: int


func _ready() -> void:
	hp = max_hp


func is_alive() -> bool:
	return hp > 0


func apply_damage(info: HitInfo) -> void:
	if not is_alive():
		return
	if not immortal:
		hp = maxi(hp - info.damage, 0)
	damaged.emit(info.damage, info)
	if hp == 0:
		died.emit(info)


func revive() -> void:
	hp = max_hp
	revived.emit()
