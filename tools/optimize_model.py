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
            "scale": None, "height": None, "front": "+Z", "keep_metallic": False}
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == "--keep-metallic":
            opts["keep_metallic"] = True
            i += 1
            continue
        val = argv[i + 1]
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
                img.save()
                tex_info.append({"original": [w0, h0], "final": list(img.size)})

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
