class_name Pickup
extends Area3D
## Objeto recogible (moneda, corazón). El héroe lo recoge al tocarlo.
## Visual en el hijo `Visual` (placeholder o Sprite3D de PixelLab).

enum Kind { COIN, HEART }

@export var kind: Kind = Kind.COIN
@export var amount: int = 1
## Segundos antes de poder recogerlo (deja ver la animación de salida).
@export var pickup_delay: float = 0.35
@export var spin_speed: float = 2.5
@export var bob_height: float = 0.08

var _ready_to_collect: bool = false
var _collected: bool = false
var _t: float = 0.0

@onready var visual: Node3D = $Visual


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	monitoring = true
	_t = randf() * TAU
	get_tree().create_timer(pickup_delay, false).timeout.connect(func(): _ready_to_collect = true)


## Sale despedido desde `from` y cae cerca (lo llama el objeto que lo suelta).
func pop_from(from: Vector3) -> void:
	var land := from + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(0.3, 0.8))
	global_position = from + Vector3(0, 0.6, 0)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "global_position:x", land.x, 0.4)
	t.tween_property(self, "global_position:z", land.z, 0.4)
	t.tween_property(self, "global_position:y", from.y + 1.3, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(self, "global_position:y", land.y, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	visual.rotation.y += spin_speed * delta
	if _collected:
		return  # la animación de recogida controla la altura
	visual.position.y = 0.35 + sin(_t * 3.0) * bob_height


func _physics_process(_delta: float) -> void:
	if not _ready_to_collect or _collected:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group(&"player"):
			collect()
			return


func collect() -> void:
	_collected = true
	match kind:
		Kind.COIN:
			PlayerStats.add_coins(amount)
			GameFeel.sfx(&"coin", 0.02)
		Kind.HEART:
			PlayerStats.heal(amount)
			GameFeel.sfx(&"heart", 0.02)
	var t := create_tween().set_parallel(true)
	t.tween_property(visual, "position:y", visual.position.y + 0.8, 0.25)
	t.tween_property(visual, "scale", Vector3.ONE * 0.1, 0.25)
	t.chain().tween_callback(queue_free)
