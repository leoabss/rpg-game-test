# RPG HD-2D (Godot 4.7.2 · GDScript)

RPG 2.5D con estética HD-2D (sprites pixel art billboard en mundo 3D, bloom, DOF tilt-shift, niebla volumétrica). Renderer **Forward+** (obligatorio: la niebla volumétrica y SSAO no existen en Mobile/Compatibility).

## Cómo correr

Godot: `C:\Users\daniel\Downloads\GODOT\Godot_v4.7.2-stable_win64.exe` (usar `_console.exe` para ver logs en terminal).
Blender: `C:\Program Files\Blender Foundation\Blender 5.3\blender.exe` (usar en background: `-b --factory-startup --python <script> -- <args>`).

```bash
# Abrir el editor
"/c/Users/daniel/Downloads/GODOT/Godot_v4.7.2-stable_win64.exe" -e --path .

# Jugar la escena principal (pueblo_test)
"/c/Users/daniel/Downloads/GODOT/Godot_v4.7.2-stable_win64.exe" --path .

# Verificación headless (importa recursos y corre ~120 frames; revisar SCRIPT ERROR / ERROR en la salida)
"/c/Users/daniel/Downloads/GODOT/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import
"/c/Users/daniel/Downloads/GODOT/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --quit-after 120
```

Siempre correr la verificación headless después de cambiar scripts o escenas.

## Estructura

```
project.godot            Config, Input Map, capas de física, calidad de sombras
scenes/
  levels/                Niveles jugables (pueblo_test.tscn = escena principal)
  player/                player.tscn (CharacterBody3D)
  camera/                octopath_camera.tscn (Camera3D + CameraAttributesPractical)
  props/                 Props reutilizables: casa_comun, casa_carreta, arbol_otono (modelos 3D) + placeholders (casa, árbol, farol; ya no usados en pueblo_test salvo el farol)
  ui/                    Overlays (vignette.tscn)
scripts/                 GDScript, espejando la estructura de scenes/ (player/, camera/, ...)
shaders/                 .gdshader (vignette, prop_hd2d, foliage_hd2d) + includes/hd2d_prop_common.gdshaderinc
resources/               Recursos compartidos (.tres): hd2d_environment.tres, hero_frames.tres (generado)
tools/                   Scripts de línea de comandos (build_sprite_frames.gd, optimize_model.py para Blender)
assets/sprites/<pj>/     Exports de PixelLab tal cual (metadata.json + PNGs) + sprite_import.json
assets/models/<grupo>/   Modelos optimizados (.glb + _albedo.png + .report.json), generados por optimize_model.py
assets/models/_source/   Originales (TRELLIS, etc.) tal cual; tiene .gdignore (Godot no los importa)
assets/textures/         Texturas de terreno/props
```

## Convenciones

- Archivos y carpetas en `snake_case`; nodos en `PascalCase`; `class_name` en PascalCase para scripts reutilizables.
- Identificadores de código en inglés, comentarios y docs en español.
- GDScript tipado estático (`var x: float`, `:=`), `@export` + `@export_group` para todo lo ajustable.
- Escala del mundo: **1 unidad = 1 metro**. Personaje ≈ 1.6 m.
- Movimiento en el plano XZ: input "arriba" = −Z (alejándose de la cámara), "abajo" = +Z.
- Las props van como escenas propias en `scenes/props/` e instanciadas en los niveles.
- Capas de física: 1 `world`, 2 `player`, 3 `enemies`, 4 `camera_occluder` (solo para los rayos del fader de cámara; nada choca con ella). El hitbox de ataque del jugador detecta la capa 3 y llama `take_hit(direction)` en los cuerpos que lo implementen.
- Física 3D = **Jolt** (default en Godot 4.6+): las `Area3D` **no detectan `StaticBody3D`** por defecto. Enemigos/objetos golpeables deben ser `CharacterBody3D`/`RigidBody3D`/`AnimatableBody3D`.

## Input Map

| Acción | Teclas |
|---|---|
| `move_left/right/up/down` | WASD y flechas |
| `run` | Shift |
| `attack` | J y Espacio |

## Player (`scripts/player/player.gd`)

- Velocidad `walk_speed`/`run_speed`, `acceleration`/`deceleration` exportados.
- `facing` (Vector2, espacio input) y `facing_3d` (Vector3) guardan la última dirección mirada; `get_facing_name()` devuelve una de 8: `right, down_right, down, down_left, left, up_left, up, up_right`.
- `get_anim_state()` → `idle | walk | run | attack`.
- `attack()`: bloquea movimiento y giro, reproduce `attack_<dir>` una vez y vuelve a idle/walk al terminar (`animation_finished`). El golpe (`take_hit` a lo que esté en `AttackHitbox`) se aplica al llegar al frame de impacto **de esa dirección** (`hit_frames.attack.<dir>` del SpriteFrames; PixelLab no sincroniza el golpe entre direcciones). Sin animación de ataque usa `fallback_attack_duration`/`fallback_attack_hit_time`.
- **Sprites**: nodo `Sprite` (AnimatedSprite3D) con billboard Y, filtro nearest, alpha cut Discard (proyecta sombra), `shaded`. `setup_sprite()` lee la metadata del SpriteFrames: `pixel_size = character_height / body_height_px` (héroe 1.65 m; puertas 1.7 m) y `offset.y = foot_offset_px` (pies en el origen = suelo). Sin SpriteFrames se muestra la cápsula placeholder.
- **Fallback de animaciones** (`_resolve_animation`, cacheado): misma dirección → vecinas de más cercana a más lejana (en diagonales primero la horizontal: `down_right → right → down`) → espejo `left↔right` con `flip_h` → estados alternativos (`run → walk → idle`, `attack → idle`, `idle →` frame 0 de walk en pausa). Funciona con 4 u 8 direcciones y con estados incompletos; al agregar animaciones no hay que tocar código.
- Velocidad de animación: FPS por estado en el SpriteFrames + multiplicadores `idle/walk/run_anim_speed`. Si `run` cae a `walk`, se acelera ×(run_speed/walk_speed).

## Pipeline de sprites (PixelLab → SpriteFrames)

1. Exportar el personaje de PixelLab y descomprimirlo tal cual en `assets/sprites/<pj>/` (con `metadata.json`).
2. Importar y generar:
   ```bash
   "/c/Users/daniel/Downloads/GODOT/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import
   "/c/Users/daniel/Downloads/GODOT/Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s res://tools/build_sprite_frames.gd -- res://assets/sprites/hero res://resources/hero_frames.tres
   ```
3. Volver a correrlo cada vez que se regenere o agregue una animación. No editar `hero_frames.tres` a mano (se sobreescribe).

- Lee `states[].frames.rotations` (1 frame por dirección, prioridad baja) y `states[].frames.animations` (`{nombre: {direccion: [pngs]}}`). Sin metadata escanea `<anim>/<direccion>/*.png` y `<estado>/rotations/<direccion>.png`.
- Nombres de PixelLab → estado por palabra clave: idle/breath/stand → `idle`, walk → `walk`, run/sprint → `run`, attack/slash/swing/strike/punch/kick → `attack`. Direcciones `south/north-east/...` → `down/up_right/...`.
- `sprite_import.json` (opcional, en la carpeta del export): `aliases` (nombre exacto → estado; el héroe usa `"Cross_Punch": "attack"`), `fps`, `loop`, `hit_frame`.
- `hit_frame`: `"auto"` (default para attack) detecta por dirección el frame donde la silueta llega más lejos hacia donde mira; para `up`/`down` (golpe hacia/desde cámara, no medible en 2D) usa el promedio de las demás. Se puede forzar: `{"attack": 3}` o `{"attack": {"default": "auto", "up_left": 3}}`.
- **Lienzos mixtos**: PixelLab exporta algunos clips en otro tamaño (las `south` del héroe vienen en 68×68, el resto 48×48) y con los pies a distinta altura. El builder alinea cada clip por su línea de pies en un lienzo común con `AtlasTexture.margin` (héroe: 68×70, pies en fila 58).
- Guarda metadata en el SpriteFrames: `hit_frames` (`{estado: {dir: frame}}`), `foot_offset_px`, `body_height_px` (de la pose idle), `frame_height_px` (calculados con el bounding box opaco de los PNG).
- Import de PNG: `[importer_defaults]` en `project.godot` fuerza lossless, sin mipmaps y **`detect_3d` desactivado** (si no, Godot recomprime a VRAM S3TC + mipmaps al ver la textura en 3D y el pixel art se ensucia). El builder avisa si algún `.import` no cumple. El filtro nearest lo pone el nodo.

## Pipeline de modelos 3D (TRELLIS → Godot)

1. Guardar el original en `assets/models/_source/<grupo>/<nombre>.glb`.
2. Optimizar con Blender:
   ```bash
   "/c/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b --factory-startup --python tools/optimize_model.py -- assets/models/_source/pueblo/casa_comun.glb assets/models/pueblo/casa_comun.glb --front +X --scale 12.3
   ```
   - Une mallas, rota el frente a **+Z** (`--front` = hacia dónde mira la puerta en el original, en ejes de Godot), escala (`--scale` o `--height`), pivote en el centro de la base, Decimate Collapse si pasa de `--max-faces` (20000), reduce texturas > `--max-tex` (2048), fuerza **metallic=0** (TRELLIS exporta metallic=1 → se ve casi negro).
   - `--fix-light-spots` (opt-in): rellena manchas pequeñas gris claro/blancas de la textura (artefactos de horneado de TRELLIS, p.ej. el "fondo" visto entre los rayos de una rueda) con el color vecino. Solo manchas < `--spot-max-area` px (600), así que paredes claras grandes no se tocan. Lo reduce pero no siempre lo elimina: si el entorno de la mancha también es claro, queda un tono apagado.
   - `--pivot trunk`: centra el pivote en el pie del tronco (vértices del 3% inferior) en vez del centro de la caja; para árboles con tronco inclinado.
   - Árbol otoño: `--height 6 --max-faces 6500 --pivot trunk --fix-light-spots` → 32.5k → 6.4k caras, 6.1 m, copa desde ~2.6 m.
   - Exporta el `.glb` **sin textura** + `<nombre>_albedo.png` aparte con un `.png.import` propio (VRAM + mipmaps: los `[importer_defaults]` del proyecto son para pixel art y harían titilar el modelo) + `<nombre>.report.json` (caras, tamaño, huella de paredes para la colisión).
   - Escala: medir la puerta en un render del original y apuntar a **puerta ≈ 1.8 m** (héroe 1.65 m). Casa común: ×12.3 → 10.5 × 7.0 × 12.2 m (`--front +X`). Casa carreta: ×7.9 → 7.9 × 7.3 × 4.7 m (`--front +Z --fix-light-spots`; la puerta está en una plataforma a ~1 m con escalones, ruedas en el suelo).
3. Escena en `scenes/props/<nombre>.tscn`: raíz `StaticBody3D` con `scripts/props/model_prop.gd` (`ModelProp`, `@tool`: aplica `material` como override a todas las mallas, e `instance_params` (Dictionary) como `instance uniform` por instancia), instancia del `.glb`, y colisión con cajas simples (paredes, sin aleros).
4. Material: `ShaderMaterial` con `shaders/prop_hd2d.gdshader` → `brightness`, `saturation`, `contrast`, `tint`, `roughness`, `specular` (ajustes en espacio perceptual). Casa común y casa carreta (mismos valores para que combinen): 1.12 / 1.2 / 1.06 / tinte (1, 0.96, 0.9) / 0.9 / 0.25. Más de ~1.25 de brillo con 1.3 de saturación quema los techos.
   - Vegetación: `shaders/foliage_hd2d.gdshader` (mismo ajuste de color y dither por el include común) + viento solo en la copa (vertex shader: `canopy_start/full`, `wind_strength` 0.03, `wind_speed`, `wind_direction` en ejes del MUNDO, `leaf_flutter`; fase distinta por árbol; también mueve la sombra) + tono por árbol con `instance_params`: `hue_variation` (-1 más rojo … +1 más naranja; **acerca** el tono a `hue_red`/`hue_orange` por el camino más corto, no lo rota: rotar volvía violetas los rosados) y `canopy_saturation`.
   - Colisión de árboles: solo un cilindro delgado en el tronco (el héroe pasa bajo la copa) + `CameraOccluder` cilíndrico en la copa.
6. **Varios árboles**: rotación Y aleatoria, escala 0.8–1.2 y `hue_variation`/`canopy_saturation` distintos por instancia, escritos en el `.tscn` (deterministas, editables). Rendimiento medido con 10 árboles (RTX 3060 Ti, 1600×900, vsync off): +0.4–0.5 ms/frame (254 → 231 FPS); cada árbol se dibuja también en las pasadas de sombra (4 cascadas del sol + omnis de faroles), por eso suben draw calls/triángulos más que las caras del modelo. No hace falta MultiMesh hasta decenas de árboles (y se perdería fader/colisión por árbol).
5. **Proxy de oclusión**: agregar un hijo `CameraOccluder` (StaticBody3D, grupo `camera_occluder_proxy`, `collision_layer = 8`, `collision_mask = 0`) con una caja que cubra todo el volumen visible (techo incluido). Sin él, solo la colisión de paredes dispara el desvanecido y un techo alto puede tapar al héroe sin detectarse.

## Desvanecido de oclusión (cámara)

- `OctopathCamera/OcclusionFader` (`scripts/camera/camera_occlusion_fader.gd`): cada frame lanza rayos cámara → jugador (pies, pecho, cabeza y costados) contra capas 1 + 4. Lo que golpea se desvanece (`fade_speed`, ~0.25 s) y vuelve al dejar de tapar. Un `CameraOccluder` desvanece a su padre (el prop entero). Grupo `no_camera_fade` para excluir algo.
- Materiales con `instance uniform float occlusion_fade` (`prop_hd2d`, `foliage_hd2d`; el fader también detecta el include `hd2d_prop_common.gdshaderinc`): **dither** opaco (patrón Bayer 4×4, `occlusion_max` = 0.75), sin problemas de orden y **la sombra se mantiene** (no descarta en `IN_SHADOW_PASS`). Por instancia: no duplica materiales.
- Otros materiales (placeholders): fallback `GeometryInstance3D.transparency` (`fallback_transparency`).

## Look HD-2D — dónde ajustar

- **`resources/hd2d_environment.tres`**: tonemap Filmic, glow/bloom, SSAO, niebla volumétrica, saturación/contraste, cielo y luz ambiente.
- **Cámara** (`octopath_camera.gd`, `@tool`, exports en el nodo `OctopathCamera`): `pitch_degrees` (18), `distance` (14), `field_of_view` (28), `focus_offset`, `follow_smoothing`, y DOF relativo a la distancia (`dof_far_margin`, `dof_near_margin`, transiciones, `dof_blur_amount`). Los cambios se ven en vivo en el editor; el DOF del sub-recurso de la escena se sobreescribe desde el script.
  - Cámara baja = personajes vistos casi de lado → generar sprites en PixelLab con vista "side" / "low top-down".
- **Iluminación** (nodo `Lighting` del nivel, `scripts/levels/hd2d_lighting.gd`, `@tool`): color/intensidad del sol, `sun_elevation_degrees` (bajo = sombras largas), `sun_azimuth_degrees`, `shadow_softness`, `ambient_color` (azulado = sombras frías), `ambient_energy`, niebla. Es la fuente de verdad: sobreescribe el `Sun` y el Environment compartido. **No poner transforms escritas a mano en luces**: si la base no es exactamente ortonormal, Godot ve "escala" y muestra ⚠ en el nodo.
- **Faroles**: `scenes/props/lamp_placeholder.tscn` + `scripts/props/street_lamp.gd` (exports por instancia: color, energía, alcance, halo en niebla). La luz cuelga de un brazo, separada del poste: si una OmniLight queda justo encima de un poste con sombras, el poste tapa un cono hacia abajo y aparece un círculo oscuro en el suelo.
- **Viñeta**: `scenes/ui/vignette.tscn` → parámetros del shader (`intensity`, `radius`, `softness`, `vignette_color`).
- Calidad de sombras en `project.godot` (`[rendering]`).
