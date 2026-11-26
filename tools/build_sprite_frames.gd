extends SceneTree
## Genera un SpriteFrames (.tres) a partir de un export de personaje de PixelLab.
##
## Uso (desde la raíz del proyecto, después de importar los PNG):
##   Godot_console.exe --headless --path . --import
##   Godot_console.exe --headless --path . -s res://tools/build_sprite_frames.gd -- <carpeta_export> <salida.tres>
## Ej:
##   ... -s res://tools/build_sprite_frames.gd -- res://assets/sprites/hero res://resources/hero_frames.tres
##
## Qué lee:
##   - metadata.json de PixelLab (export_version 3.x): `states[].frames.rotations`
##     ({direccion: png}, 1 frame) y `states[].frames.animations`
##     ({nombre: {direccion: [png, ...]}}). Rutas relativas a la carpeta del export.
##   - Sin metadata.json: escanea la carpeta buscando `<anim>/<direccion>/*.png`
##     (frames) y `<estado>/rotations/<direccion>.png` (1 frame).
##   - sprite_import.json opcional en la carpeta del export para personalizar:
##     { "aliases": {"walking-8-frames": "walk"}, "fps": {"walk": 10},
##       "hit_frame": {"attack": 3}, "loop": {"attack": false} }
##
## Qué genera: animaciones "<estado>_<direccion>" (idle_down, walk_up_left...),
## con FPS/loop por estado, y metadatos que usa player.gd:
##   hit_frames (Dictionary estado->frame del golpe), foot_offset_px,
##   body_height_px, frame_height_px.
## Las animaciones de "rotations" (estáticas) solo se usan si no hay una
## animación real para ese mismo estado y dirección.

const DIRECTIONS := {
	"south": "down", "south-east": "down_right", "east": "right", "north-east": "up_right",
	"north": "up", "north-west": "up_left", "west": "left", "south-west": "down_left",
	# Por si el export ya usa la convención del proyecto.
	"down": "down", "down_right": "down_right", "right": "right", "up_right": "up_right",
	"up": "up", "up_left": "up_left", "left": "left", "down_left": "down_left",
}

## Palabras clave -> estado del proyecto (se busca como subcadena, en orden).
const DEFAULT_ALIASES := [
	["idle", "idle"], ["breath", "idle"], ["stand", "idle"],
	["run", "run"], ["sprint", "run"],
	["walk", "walk"],
	["attack", "attack"], ["slash", "attack"], ["swing", "attack"],
	["strike", "attack"], ["punch", "attack"], ["kick", "attack"],
]

const DEFAULT_FPS := {"idle": 4.0, "walk": 8.0, "run": 12.0, "attack": 12.0}
const DEFAULT_LOOP := {"idle": true, "walk": true, "run": true, "attack": false}

var _src: String
var _config: Dictionary = {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_src = (args[0] if args.size() > 0 else "res://assets/sprites/hero").trim_suffix("/")
	var out: String = args[1] if args.size() > 1 else "res://resources/hero_frames.tres"
	var code := build(out)
	quit(code)


func build(out_path: String) -> int:
	if not DirAccess.dir_exists_absolute(_src):
		push_error("No existe la carpeta: %s" % _src)
		return 1
	_config = _read_json(_src + "/sprite_import.json")

	# clips[state][direction] = {"frames": [paths], "priority": int}
	var clips := {}
	var meta := _read_json(_src + "/metadata.json")
	if meta.has("states") or meta.has("frames"):
		_collect_from_metadata(meta, clips)
	else:
		print("Sin metadata.json válido: escaneando carpetas.")
		_collect_from_scan(_src, "", clips)

	if clips.is_empty():
		push_error("No se encontraron frames en %s" % _src)
		return 1

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var hit_frames := {}
	var fps_cfg: Dictionary = _config.get("fps", {})
	var loop_cfg: Dictionary = _config.get("loop", {})
	var hit_cfg: Dictionary = _config.get("hit_frame", {})
	var bottom_max := 0
	var top_min := 1 << 30
	var frame_h := 0

	for state in clips:
		for dir in clips[state]:
			var anim := StringName("%s_%s" % [state, dir])
			frames.add_animation(anim)
			frames.set_animation_speed(anim, float(fps_cfg.get(state, DEFAULT_FPS.get(state, 8.0))))
			frames.set_animation_loop(anim, bool(loop_cfg.get(state, DEFAULT_LOOP.get(state, true))))
			var paths: Array = clips[state][dir]["frames"]
			for p in paths:
				var tex := load(p) as Texture2D
				if tex == null:
					push_error("No se pudo cargar %s (¿corriste --import?)" % p)
					return 1
				frames.add_frame(anim, tex)
				var img := Image.load_from_file(ProjectSettings.globalize_path(p))
				if img:
					var used := img.get_used_rect()
					if used.size != Vector2i.ZERO:
						bottom_max = maxi(bottom_max, used.end.y)
						top_min = mini(top_min, used.position.y)
					frame_h = maxi(frame_h, img.get_height())
			if state == "attack" and not hit_frames.has(state):
				var count := paths.size()
				hit_frames[state] = clampi(int(hit_cfg.get(state, count / 2)), 0, count - 1)

	frames.set_meta(&"hit_frames", hit_frames)
	frames.set_meta(&"frame_height_px", frame_h)
	# Desplazamiento (px, hacia arriba) para que el borde inferior de los pies
	# quede en el origen del nodo con `centered = true`.
	frames.set_meta(&"foot_offset_px", bottom_max - frame_h / 2.0)
	frames.set_meta(&"body_height_px", bottom_max - top_min)

	var err := ResourceSaver.save(frames, out_path)
	if err != OK:
		push_error("Error guardando %s: %s" % [out_path, error_string(err)])
		return 1

	print("SpriteFrames guardado en ", out_path)
	for state in clips:
		var dirs: Array = clips[state].keys()
		var counts := dirs.map(func(d): return "%s(%d)" % [d, clips[state][d]["frames"].size()])
		print("  %s: %s" % [state, ", ".join(counts)])
	print("  foot_offset_px=%s body_height_px=%d frame_height_px=%d hit_frames=%s" % [
		frames.get_meta(&"foot_offset_px"), bottom_max - top_min, frame_h, hit_frames])
	return 0


# --- Fuentes ---------------------------------------------------------------

func _collect_from_metadata(meta: Dictionary, clips: Dictionary) -> void:
	var states: Array = meta.get("states", [meta])
	for st in states:
		var st_frames: Dictionary = st.get("frames", {})
		var st_name: String = st.get("folder", st.get("character", {}).get("name", "idle"))
		# Rotaciones: 1 frame por dirección, prioridad baja.
		var rot: Dictionary = st_frames.get("rotations", {})
		var rot_state := _map_state(st_name)
		for d in rot:
			_add_clip(clips, rot_state, d, [rot[d]], 0)
		# Animaciones reales: prioridad alta.
		var anims: Dictionary = st_frames.get("animations", {})
		for anim_name in anims:
			var state := _map_state(anim_name)
			var per_dir = anims[anim_name]
			if per_dir is Dictionary:
				for d in per_dir:
					var list = per_dir[d]
					_add_clip(clips, state, d, list if list is Array else [list], 1)


func _collect_from_scan(dir_path: String, parent_name: String, clips: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var here := dir_path.get_file()
	var pngs := Array(dir.get_files()).filter(func(f: String): return f.get_extension().to_lower() == "png")
	pngs.sort()
	if DIRECTIONS.has(here.to_lower()) and not pngs.is_empty():
		# <anim>/<direccion>/frame_000.png ...
		var paths := pngs.map(func(f): return dir_path + "/" + f)
		_add_clip(clips, _map_state(parent_name), here, paths, 1)
	else:
		# <estado>/rotations/<direccion>.png
		var owner_name := parent_name if here.to_lower() == "rotations" else here
		for f in pngs:
			var d: String = f.get_basename()
			if DIRECTIONS.has(d.to_lower()):
				_add_clip(clips, _map_state(owner_name), d, [dir_path + "/" + f], 0)
	for sub in dir.get_directories():
		_collect_from_scan(dir_path + "/" + sub, here, clips)


# --- Helpers ---------------------------------------------------------------

func _add_clip(clips: Dictionary, state: String, raw_dir: String, rel_paths: Array, priority: int) -> void:
	var dir: String = DIRECTIONS.get(raw_dir.to_lower(), "")
	if dir == "" or state == "":
		push_warning("Ignorado: estado '%s' dirección '%s'" % [state, raw_dir])
		return
	var paths := rel_paths.map(func(p: String): return p if p.begins_with("res://") else _src + "/" + p)
	if not clips.has(state):
		clips[state] = {}
	var existing: Dictionary = clips[state].get(dir, {})
	if existing.is_empty() or priority > int(existing["priority"]):
		clips[state][dir] = {"frames": paths, "priority": priority}


func _map_state(raw_name: String) -> String:
	var aliases: Dictionary = _config.get("aliases", {})
	if aliases.has(raw_name):
		return aliases[raw_name]
	var n := raw_name.to_lower()
	for pair in DEFAULT_ALIASES:
		if n.contains(pair[0]):
			return pair[1]
	return n.replace("-", "_").replace(" ", "_")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
