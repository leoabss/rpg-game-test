extends Node
## Autoload "PlayerStats": monedas y corazones del héroe (lo lee el HUD).

signal coins_changed(coins: int)
signal hearts_changed(hearts: int, max_hearts: int)

@export var max_hearts: int = 3

var coins: int = 0
var hearts: int = 3


func _ready() -> void:
	hearts = max_hearts


func add_coins(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins)


func heal(amount: int) -> void:
	hearts = mini(hearts + amount, max_hearts)
	hearts_changed.emit(hearts, max_hearts)


func take_damage(amount: int) -> void:
	hearts = maxi(hearts - amount, 0)
	hearts_changed.emit(hearts, max_hearts)


func reset() -> void:
	coins = 0
	hearts = max_hearts
	coins_changed.emit(coins)
	hearts_changed.emit(hearts, max_hearts)
