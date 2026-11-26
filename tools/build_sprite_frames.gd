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
##     { "aliases": {"Cross_Punch": "attack"}, "fps": {"walk": 10},
##       "loop": {"attack": false},
##       "hit_frame": {"attack": "auto"} }   # o un int, o {"default": "auto", "down": 4}
##
## Qué genera: animaciones "<estado>_<direccion>" (idle_down, walk_up_left...),
## con FPS/loop por estado, y metadatos que usa player.gd:
##   hit_frames ({estado: {direccion: frame}}), foot_offset_px,
##   body_height_px, frame_height_px.
## Clips con lienzos/pies distintos se alinean por la línea de pies en un
## lienzo común (AtlasTexture con margin).
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

	# Cargar texturas e imágenes y medir cada clip.
	# PixelLab puede exportar clips con lienzos distintos (p.ej. 48x48 y 68x68)
	# y con los pies a distinta altura. Se alinea cada clip por la línea de
	# pies (su bottom opaco más bajo) dentro de un lienzo común, rellenando
	# con AtlasTexture.margin, para que el personaje no salte al cambiar de clip.
	var data := {}  # data[state][dir] = {"tex": [], "img": [], "foot": int}
	var above := 0  # px del lienzo común por encima de los pies
	var below := 0  # px por debajo de los pies
	var canvas_w := 0
	for state in clips:
		data[state] = {}
		for dir in clips[state]:
			var entry := {"tex": [], "img": [], "foot": 0}
			for p in clips[state][dir]["frames"]:
				var tex := load(p) as Texture2D
				var img := Image.load_from_file(ProjectSettings.globalize_path(p))
				if tex == null or img == null:
					push_error("No se pudo cargar %s (¿corriste --import?)" % p)
					return 1
				_check_import(p)
				entry["tex"].append(tex)
				entry["img"].append(img)
				var used := img.get_used_rect()
				if used.size != Vector2i.ZERO:
					entry["foot"] = maxi(entry["foot"], used.end.y)
			for img: Image in entry["img"]:
				above = maxi(above, entry["foot"])
				below = maxi(below, img.get_height() - entry["foot"])
				canvas_w = maxi(canvas_w, img.get_width())
			data[state][dir] = entry
	var canvas_h := above + below

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var hit_frames := {}
	var fps_cfg: Dictionary = _config.get("fps", {})
	var loop_cfg: Dictionary = _config.get("loop", {})
	var body_h_idle := 0
	var body_h_all := 0
	var padded := 0

	for state in data:
		for dir in data[state]:
			var anim := StringName("%s_%s" % [state, dir])
			frames.add_animation(anim)
			frames.set_animation_speed(anim, float(fps_cfg.get(state, DEFAULT_FPS.get(state, 8.0))))
			frames.set_animation_loop(anim, bool(loop_cfg.get(state, DEFAULT_LOOP.get(state, true))))
			var entry: Dictionary = data[state][dir]
			var foot: int = entry["foot"]
			for i in entry["tex"].size():
				var tex: Texture2D = entry["tex"][i]
				var img: Image = entry["img"][i]
				var size := Vector2(img.get_width(), img.get_height())
				var pad := Vector2(floorf((canvas_w - size.x) / 2.0), above - foot)
				if pad != Vector2.ZERO or size != Vector2(canvas_w, canvas_h):
					var atlas := AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(Vector2.ZERO, size)
					atlas.margin = Rect2(pad, Vector2(canvas_w, canvas_h) - size)
					tex = atlas
					padded += 1
				frames.add_frame(anim, tex)
				var used := img.get_used_rect()
				if used.size != Vector2i.ZERO:
					var h := foot - used.position.y
					body_h_all = maxi(body_h_all, h)
					if state == "idle":
						body_h_idle = maxi(body_h_idle, h)
		if data[state].size() > 0 and _hit_cfg_for(state) != null:
			hit_frames[state] = _compute_hit_frames(state, data[state])

	frames.set_meta(&"hit_frames", hit_frames)
	frames.set_meta(&"frame_height_px", canvas_h)
	# Desplazamiento (px, hacia arriba) para que la línea de pies quede en el
	# origen del nodo con `centered = true`.
	frames.set_meta(&"foot_offset_px", above - canvas_h / 2.0)
	# Altura de referencia: la pose idle si existe (los ataques levantan brazos).
	frames.set_meta(&"body_height_px", body_h_idle if body_h_idle > 0 else body_h_all)

	var err := ResourceSaver.save(frames, out_path)
	if err != OK:
		push_error("Error guardando %s: %s" % [out_path, error_string(err)])
		return 1

	print("SpriteFrames guardado en ", out_path)
	for state in data:
		var dirs: Array = data[state].keys()
		var counts := dirs.map(func(d): return "%s(%d)" % [d, data[state][d]["tex"].size()])
		print("  %s: %s" % [state, ", ".join(counts)])
	print("  lienzo=%dx%d foot_offset_px=%s body_height_px=%d frames_rellenados=%d" % [
		canvas_w, canvas_h, frames.get_meta(&"foot_offset_px"), frames.get_meta(&"body_height_px"), padded])
	print("  hit_frames=%s" % [hit_frames])
	return 0


# --- Frame de impacto -------------------------------------------------------

## Config de hit_frame para un estado: int, "auto", {dir|"default": int|"auto"}
## o null si el estado no tiene golpe (solo "attack" lo tiene por defecto).
func _hit_cfg_for(state: String) -> Variant:
	var cfg: Dictionary = _config.get("hit_frame", {})
	if cfg.has(state):
		return cfg[state]
	return "auto" if state == "attack" else null


## Frame de impacto por dirección: {dir: frame}.
## "auto": el frame donde la silueta llega más lejos hacia donde mira el
## personaje (solo medible con componente horizontal). Para up/down (el golpe
## va hacia/desde la cámara) se usa el promedio de las demás direcciones.
func _compute_hit_frames(state: String, clips_by_dir: Dictionary) -> Dictionary:
	var cfg: Variant = _hit_cfg_for(state)
	var per_dir: Dictionary = cfg if cfg is Dictionary else {"default": cfg}
	var result := {}
	var auto_dirs: Array = []
	for dir in clips_by_dir:
		var c: Variant = per_dir.get(dir, per_dir.get("default", "auto"))
		var count: int = clips_by_dir[dir]["img"].size()
		if c is String and c == "auto":
			auto_dirs.append(dir)
		else:
			result[dir] = clampi(int(c), 0, count - 1)
	var measured: Array = []
	for dir in auto_dirs:
		var sx := 1 if String(dir).contains("right") else (-1 if String(dir).contains("left") else 0)
		if sx == 0:
			continue
		var best := 0
		var best_reach := -INF
		var imgs: Array = clips_by_dir[dir]["img"]
		for i in imgs.size():
			var img: Image = imgs[i]
			var used := img.get_used_rect()
			var cx := img.get_width() / 2.0
			var reach := (used.end.x - cx) if sx > 0 else (cx - used.position.x)
			if reach > best_reach:
				best_reach = reach
				best = i
		result[dir] = best
		measured.append(best)
	var fallback := -1
	if measured.size() > 0:
		fallback = roundi(measured.reduce(func(a, b): return a + b, 0) / float(measured.size()))
	for dir in auto_dirs:
		if not result.has(dir):
			var count: int = clips_by_dir[dir]["img"].size()
			result[dir] = clampi(fallback if fallback >= 0 else count / 2, 0, count - 1)
	return result


## Avisa si el PNG no está importado como pixel art (lossless, sin mipmaps).
func _check_import(png_path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(png_path + ".import") != OK:
		return
	if int(cfg.get_value("params", "compress/mode", 0)) != 0 or bool(cfg.get_value("params", "mipmaps/generate", false)):
		push_warning("%s no está importado como pixel art (compress/mode=0, mipmaps off). Revisa [importer_defaults] o el .import." % png_path)


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
