extends CanvasLayer
## HUD mínimo: corazones y monedas del héroe (lee el autoload PlayerStats).

const HEART_FULL := Color(0.95, 0.2, 0.25)
const HEART_EMPTY := Color(0.25, 0.12, 0.14)

@onready var hearts_box: HBoxContainer = %Hearts
@onready var coins_label: Label = %Coins


func _ready() -> void:
	PlayerStats.hearts_changed.connect(_on_hearts_changed)
	PlayerStats.coins_changed.connect(_on_coins_changed)
	_on_hearts_changed(PlayerStats.hearts, PlayerStats.max_hearts)
	_on_coins_changed(PlayerStats.coins)


func _on_hearts_changed(hearts: int, max_hearts: int) -> void:
	for c in hearts_box.get_children():
		c.queue_free()
	for i in max_hearts:
		var h := Label.new()
		h.text = "♥"
		h.add_theme_font_size_override(&"font_size", 34)
		h.add_theme_constant_override(&"outline_size", 8)
		h.add_theme_color_override(&"font_outline_color", Color(0.1, 0.05, 0.05))
		h.add_theme_color_override(&"font_color", HEART_FULL if i < hearts else HEART_EMPTY)
		hearts_box.add_child(h)


func _on_coins_changed(coins: int) -> void:
	coins_label.text = "%d" % coins
	var t := coins_label.create_tween()
	coins_label.pivot_offset = coins_label.size / 2.0
	t.tween_property(coins_label, "scale", Vector2.ONE * 1.3, 0.06)
	t.tween_property(coins_label, "scale", Vector2.ONE, 0.12)
