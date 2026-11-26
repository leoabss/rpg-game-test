extends SceneTree
# Test de combate con input simulado: 4 objetos x 8 direcciones, alcance,
# un golpe por ataque, reaparición del arbusto y recogida de botín.
# Correr: Godot_console --headless --path . -s res://tests/test_combat.gd
# Debe terminar con "RESULTADO: OK (0 fallos)".

const DIRS := {
	"right": ["move_right"], "down_right": ["move_right", "move_down"], "down": ["move_down"],
	"down_left": ["move_left", "move_down"], "left": ["move_left"], "up_left": ["move_left", "move_up"],
	"up": ["move_up"], "up_right": ["move_right", "move_up"],
}
const TYPES := {
	"arbusto": "res://scenes/props/arbusto.tscn",
	"muneco": "res://scenes/props/muneco_entrenamiento.tscn",
	"vasija": "res://scenes/props/vasija.tscn",
	"caja": "res://scenes/props/caja.tscn",
}
const START := Vector3(0, 0, -12)

var scene: Node
var p
var saw_hitstop := false
var failures := 0
var stats


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		if Engine.time_scale == 0.0:
			saw_hitstop = true


func face(dir_name: String) -> void:
	p.global_position = START
	p.velocity = Vector3.ZERO
	for a in DIRS[dir_name]: Input.action_press(a)
	await frames(2)
	for a in DIRS[dir_name]: Input.action_release(a)
	await frames(12)


func do_attack() -> void:
	Input.action_press("attack")
	var w := 0
	while not p.is_attacking and w < 6:
		await frames(1)
		w += 1
	Input.action_release("attack")
	var t := 0
	while p.is_attacking and t < 120:
		await frames(1)
		t += 1
	await frames(10)  # cooldown


func spawn(type: String, dist: float, behind := false) :
	var obj = load(TYPES[type]).instantiate()
	obj.drop_chance = 0.0
	scene.add_child(obj)
	var d: Vector3 = p.facing_3d * (-1.0 if behind else 1.0)
	obj.global_position = Vector3(p.global_position.x, 0, p.global_position.z) + d * dist
	return obj


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("   FALLO: ", msg)


func _run() -> void:
	scene = load("res://scenes/levels/pueblo_test.tscn").instantiate()
	root.add_child(scene)
	root.get_node("GameFeel").mute = true
	stats = root.get_node("PlayerStats")
	p = scene.get_node("Player")
	await frames(5)
	print("hitbox: reach=%.2f radius=%.2f height=%.2f (alcance total %.2f m)" % [p.attack_reach, p.attack_radius, p.attack_height, p.attack_reach + p.attack_radius])

	# 1) 4 tipos x 8 direcciones
	for type in TYPES:
		var row := []
		for dir_name in DIRS:
			await face(dir_name)
			var obj = spawn(type, 0.95)
			await frames(3)
			saw_hitstop = false
			await do_attack()
			var hits1 = obj.hit_count
			var ok = hits1 == 1 and saw_hitstop
			match type:
				"arbusto":
					ok = ok and not obj.health.is_alive() and not obj.visual.visible
				"muneco":
					ok = ok and obj.health.is_alive()
				"vasija", "caja":
					ok = ok and obj.health.is_alive()
					await do_attack()
					ok = ok and obj.hit_count == 2 and not obj.health.is_alive() and not obj.visual.visible
			check(ok, "%s %s: hits=%d vivo=%s hitstop=%s anim=%s" % [type, dir_name, obj.hit_count, obj.health.is_alive(), saw_hitstop, p.sprite.animation])
			row.append("%s:%s" % [dir_name, "OK" if ok else "X"])
			obj.queue_free()
			await frames(2)
		print("%-7s %s" % [type, "  ".join(row)])

	# 2) Alcance: fuera de alcance y por detrás no golpean
	for dir_name in ["right", "down", "up_left"]:
		await face(dir_name)
		var far = spawn("muneco", 1.75)
		var back = spawn("muneco", 0.95, true)
		await frames(3)
		await do_attack()
		check(far.hit_count == 0, "%s: golpeó fuera de alcance (1.75 m)" % dir_name)
		check(back.hit_count == 0, "%s: golpeó por detrás" % dir_name)
		print("alcance %-8s lejos(1.75 m)=%d  detras=%d  (esperado 0 y 0)" % [dir_name, far.hit_count, back.hit_count])
		far.queue_free(); back.queue_free()
		await frames(2)

	# 3) Muñeco: varios ataques seguidos = un golpe por ataque, número flotante
	await face("right")
	var dummy = spawn("muneco", 0.95)
	await frames(3)
	for i in 4:
		await do_attack()
	var labels := scene.find_children("*", "Label3D", true, false).size()
	check(dummy.hit_count == 4, "muñeco: 4 ataques -> %d golpes" % dummy.hit_count)
	print("muneco: 4 ataques -> %d golpes, contador='%s', vivo=%s" % [dummy.hit_count, dummy._counter_label.text, dummy.health.is_alive()])
	dummy.queue_free()

	# 4) Arbusto reaparece
	await face("left")
	var bush = spawn("arbusto", 0.95)
	bush.respawn_time = 0.5
	await frames(3)
	await do_attack()
	var dead = not bush.health.is_alive()
	p.global_position = START + Vector3(0, 0, 4)  # alejarse para que pueda reaparecer
	await frames(60)
	check(dead and bush.health.is_alive() and bush.visual.visible, "arbusto no reapareció")
	print("arbusto: roto=%s, reaparecido=%s" % [dead, bush.health.is_alive() and bush.visual.visible])
	bush.queue_free()

	# 5) Vasija suelta objeto y el héroe lo recoge
	for kind_idx in [0, 1]:
		await face("down")
		var pot = spawn("vasija", 0.95)
		pot.drop_chance = 1.0
		pot.drop_weights = PackedFloat32Array([1.0, 0.0]) if kind_idx == 0 else PackedFloat32Array([0.0, 1.0])
		await frames(3)
		stats.hearts = 2
		var coins0: int = stats.coins
		await do_attack()
		await do_attack()
		await frames(40)
		var pickups := scene.find_children("*", "Area3D", true, false).filter(func(a): return a.has_method("pop_from"))
		check(pickups.size() == 1, "vasija: no soltó objeto")
		if pickups.size() == 1:
			p.global_position = (pickups[0] as Node3D).global_position
			await frames(20)
		if kind_idx == 0:
			check(stats.coins == coins0 + 1, "moneda no sumó")
			print("vasija -> moneda: monedas %d -> %d" % [coins0, stats.coins])
		else:
			check(stats.hearts == 3, "corazón no curó")
			print("vasija -> corazón: corazones 2 -> %d" % stats.hearts)
		pot.queue_free()
		await frames(2)

	print("RESULTADO: %s (%d fallos)" % ["OK" if failures == 0 else "FALLOS", failures])
	quit()
