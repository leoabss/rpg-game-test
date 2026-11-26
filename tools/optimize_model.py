"""Optimiza un modelo 3D (p.ej. generado con TRELLIS) para usarlo en Godot.

Uso (Blender en background):
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b --factory-startup \
      --python tools/optimize_model.py -- <entrada.glb> <salida.glb> [opciones]

Opciones:
  --max-faces N     Decimate (Collapse, conserva UVs) si supera N caras. Default 20000.
  --max-tex N       Reduce texturas mayores a NxN. Default 2048.
  --scale S         Escala uniforme a aplicar.
  --height H        Alternativa a --scale: altura final en metros.
  --front DIR       Hacia dónde mira el frente (puerta) del modelo ORIGINAL, en ejes
                    de Godot: +X, -X, +Z, -Z. Se rota para que quede mirando +Z
                    (hacia la cámara), la convención del proyecto. Default +Z.
  --keep-metallic   No forzar metallic=0 (TRELLIS exporta metallic=1 -> se ve negro).
  --fix-light-spots Rellena manchas pequeñas gris claro/blancas de la textura (artefactos
                    de horneado de TRELLIS, p.ej. dentro de ruedas) con el color de
                    alrededor. Solo manchas de menos de --spot-max-area px, así que
                    superficies claras grandes (paredes encaladas) no se tocan. Opt-in.
  --spot-max-area N Área máxima (px) de una mancha a rellenar. Default 600.

Qué hace:
  1. Importa, une las mallas, aplica transformaciones.
  2. Rota el frente a +Z (Godot), aplica escala, pone el pivote en el centro de la base.
  3. Decimate si hace falta; reduce texturas grandes.
  4. Exporta <salida>.glb SIN texturas embebidas + <salida>_albedo.png aparte, y un
     .png.import con mipmaps + compresión VRAM (los defaults del proyecto son para
     pixel art y harían que el modelo titile a distancia).
  5. Escribe <salida>.report.json con caras, tamaño y una caja de colisión sugerida
     (huella de las paredes: bbox de los vértices en el 40% inferior de la altura).
"""
import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Matrix, Vector

FRONT_TO_ROT_Z = {  # rotación (grados, eje Z de Blender) para llevar el frente a Godot +Z (= Blender -Y)
    "+Z": 0.0, "+X": -90.0, "-X": 90.0, "-Z": 180.0,
}

TEXTURE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
mipmaps/generate=true
detect_3d/compress_to=0
"""


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) < 2:
        raise SystemExit(__doc__)
    opts = {"in": argv[0], "out": argv[1], "max_faces": 20000, "max_tex": 2048,
            "scale": None, "height": None, "front": "+Z", "keep_metallic": False,
            "fix_spots": False, "spot_max_area": 600}
    i = 2
    while i < len(argv):
        a = argv[i]
        if a in ("--keep-metallic", "--fix-light-spots"):
            opts["keep_metallic" if a == "--keep-metallic" else "fix_spots"] = True
            i += 1
            continue
        val = argv[i + 1]
        if a == "--spot-max-area":
            opts["spot_max_area"] = int(val)
            i += 2
            continue
        if a == "--max-faces": opts["max_faces"] = int(val)
        elif a == "--max-tex": opts["max_tex"] = int(val)
        elif a == "--scale": opts["scale"] = float(val)
        elif a == "--height": opts["height"] = float(val)
        elif a == "--front": opts["front"] = val.upper()
        else: raise SystemExit(f"Opción desconocida: {a}")
        i += 2
    if opts["front"] not in FRONT_TO_ROT_Z:
        raise SystemExit(f"--front debe ser uno de {list(FRONT_TO_ROT_Z)}")
    return opts


def fix_light_spots(img, max_area, min_value=150 / 255, max_sat=45 / 255):
    """Rellena manchas pequeñas claras y poco saturadas con el color vecino.
    Devuelve (manchas rellenadas, píxeles rellenados)."""
    import numpy as np
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = px[..., :3]
    lo = rgb.min(axis=2)
    cand = (lo > min_value) & ((rgb.max(axis=2) - lo) < max_sat)

    # Componentes conexas (4 vecinos); solo se rellenan las pequeñas.
    mask = np.zeros_like(cand)
    seen = np.zeros_like(cand)
    spots = 0
    for y0, x0 in zip(*np.nonzero(cand)):
        if seen[y0, x0]:
            continue
        stack, comp = [(y0, x0)], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            comp.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(comp) <= max_area:
            spots += 1
            ys, xs = zip(*comp)
            mask[list(ys), list(xs)] = True
    # Crecer la máscara 2 px: el borde antialiasado de la mancha queda fuera del
    # umbral pero sigue siendo claro, y si no se incluye deja un halo.
    for _ in range(2):
        g = np.pad(mask, 1)
        mask = mask | g[:-2, 1:-1] | g[2:, 1:-1] | g[1:-1, :-2] | g[1:-1, 2:]
    filled = int(mask.sum())

    # Relleno por dilatación: cada pasada copia el promedio de los vecinos conocidos.
    for _ in range(256):
        if not mask.any():
            break
        known = np.pad(~mask, 1)
        col = np.pad(rgb, ((1, 1), (1, 1), (0, 0)))
        acc = np.zeros_like(rgb)
        cnt = np.zeros((h, w), dtype=np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                k = known[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
                acc += col[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] * k[..., None]
                cnt += k
        fill = mask & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        mask &= ~fill
    px[..., :3] = rgb
    img.pixels[:] = px.ravel()
    return spots, filled


def world_bbox(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def to_godot(v):
    """Vector de Blender (Z arriba) a ejes de Godot (Y arriba): (x, z, -y)."""
    return [round(v.x, 3), round(v.z, 3), round(-v.y, 3)]


def main():
    o = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(o["in"]))

    meshes = [ob for ob in bpy.context.scene.objects if ob.type == "MESH"]
    if not meshes:
        raise SystemExit("El archivo no tiene mallas")
    faces_in = sum(len(m.data.polygons) for m in meshes)

    # Unir mallas y hornear transformaciones (quita el empty "world" de glTF).
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    mw = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = mw
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for ob in list(bpy.context.scene.objects):
        if ob != obj:
            bpy.data.objects.remove(ob, do_unlink=True)

    # Rotar frente -> +Z de Godot y escalar.
    rot = Matrix.Rotation(math.radians(FRONT_TO_ROT_Z[o["front"]]), 4, "Z")
    obj.data.transform(rot)
    mn, mx = world_bbox(obj)
    scale = o["scale"] or (o["height"] / (mx.z - mn.z) if o["height"] else 1.0)
    obj.data.transform(Matrix.Scale(scale, 4))
    # Pivote: centro de la base.
    mn, mx = world_bbox(obj)
    obj.data.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))

    # Decimate.
    faces_before = len(obj.data.polygons)
    if faces_before > o["max_faces"]:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = o["max_faces"] / faces_before * 0.98
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    faces_out = len(obj.data.polygons)

    # Materiales y texturas.
    base = os.path.splitext(o["out"])[0]
    tex_path = None
    tex_info = []
    for mat in obj.data.materials:
        if not mat or not mat.node_tree:
            continue
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf and not o["keep_metallic"]:
            bsdf.inputs["Metallic"].default_value = 0.0
            for link in list(bsdf.inputs["Metallic"].links):
                mat.node_tree.links.remove(link)
        if bsdf and bsdf.inputs["Base Color"].is_linked:
            node = bsdf.inputs["Base Color"].links[0].from_node
            if node.type == "TEX_IMAGE" and node.image and tex_path is None:
                img = node.image
                w0, h0 = img.size
                if max(w0, h0) > o["max_tex"]:
                    k = o["max_tex"] / max(w0, h0)
                    img.scale(int(w0 * k), int(h0 * k))
                tex_path = base + "_albedo.png"
                img.filepath_raw = os.path.abspath(tex_path)
                img.file_format = "PNG"
                if img.packed_file:
                    img.unpack(method="REMOVE")  # pasa a usar filepath_raw
                    img.filepath_raw = os.path.abspath(tex_path)
                info = {"original": [w0, h0], "final": list(img.size)}
                if o["fix_spots"]:
                    spots, filled = fix_light_spots(img, o["spot_max_area"])
                    info["light_spots_fixed"] = {"spots": spots, "pixels": filled}
                img.save()
                tex_info.append(info)

    # Exportar GLB sin imágenes (la textura va aparte con su propio import).
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.abspath(o["out"]), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_image_format="NONE",
        export_materials="EXPORT", export_normals=True, export_texcoords=True,
    )
    if tex_path:
        with open(tex_path + ".import", "w", encoding="utf-8", newline="\n") as f:
            f.write(TEXTURE_IMPORT)

    # Reporte + colisión sugerida (huella de paredes).
    mn, mx = world_bbox(obj)
    h = mx.z - mn.z
    low = [obj.matrix_world @ v.co for v in obj.data.vertices if v.co.z < mn.z + 0.4 * h]
    cmn = Vector((min(p.x for p in low), min(p.y for p in low), 0))
    cmx = Vector((max(p.x for p in low), max(p.y for p in low), 0))
    report = {
        "source": o["in"], "output": o["out"], "texture": tex_path,
        "faces_in": faces_in, "faces_out": faces_out, "scale": round(scale, 4),
        "front_was": o["front"],
        "size_godot_m": [round(mx.x - mn.x, 3), round(h, 3), round(mx.y - mn.y, 3)],
        "size_godot_m_note": "[ancho X, alto Y, profundidad Z]",
        "walls_footprint_godot": {
            "center": to_godot((cmn + cmx) / 2), "size_xz": [round(cmx.x - cmn.x, 3), round(cmx.y - cmn.y, 3)],
        },
        "textures": tex_info,
    }
    with open(base + ".report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print("REPORT", json.dumps(report))


main()
