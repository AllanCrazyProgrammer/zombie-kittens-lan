"""Genera los modelos 3D del juego (godot/assets/models/*.glb) de forma reproducible.
Uso:  /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_models.py
"""
import math
import os
import bpy
import bmesh

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "models")
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, rough=0.6, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)
    print("OK", name)


def rounded_rect(w, h, r, seg=6):
    """Contorno (antihorario) de un rectángulo con esquinas redondeadas, centrado en el origen."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def build_card():
    """Carta 5:7 con tres materiales: frente (UV completa), dorso (UV espejada) y canto."""
    reset()
    W, H, R, T = 0.63, 0.882, 0.06, 0.006
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    outline = rounded_rect(W, H, R)
    top = [bm.verts.new((x, y, T / 2)) for x, y in outline]
    bot = [bm.verts.new((x, y, -T / 2)) for x, y in outline]
    f = bm.faces.new(top); f.material_index = 0
    for l in f.loops:
        l[uv].uv = (l.vert.co.x / W + 0.5, l.vert.co.y / H + 0.5)
    b = bm.faces.new(list(reversed(bot))); b.material_index = 1
    for l in b.loops:
        l[uv].uv = (0.5 - l.vert.co.x / W, l.vert.co.y / H + 0.5)
    n = len(outline)
    for i in range(n):
        s = bm.faces.new((top[i], bot[i], bot[(i + 1) % n], top[(i + 1) % n])); s.material_index = 2
        for l in s.loops:
            l[uv].uv = (0.5, 0.5)
    bm.normal_update()
    me = bpy.data.meshes.new("Card")
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("Card", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material("CardFront", (1, 1, 1), 0.45))
    me.materials.append(material("CardBack", (0.2, 0.1, 0.45), 0.45))
    me.materials.append(material("CardEdge", (0.97, 0.95, 0.88), 0.7))
    export("card")


def build_table():
    """Mesa redonda: tapete de fieltro con borde de madera y una base."""
    reset()
    felt = material("Felt", (0.10, 0.05, 0.24), 0.95)
    wood = material("Wood", (0.16, 0.09, 0.05), 0.5)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=2.2, depth=0.12, location=(0, 0, -0.06))
    top = bpy.context.object; top.name = "TableTop"; top.data.materials.append(felt)
    bpy.ops.object.shade_auto_smooth()
    bpy.ops.mesh.primitive_torus_add(major_segments=96, minor_segments=20, major_radius=2.2, minor_radius=0.13, location=(0, 0, -0.03))
    rim = bpy.context.object; rim.name = "TableRim"; rim.data.materials.append(wood)
    bpy.ops.object.shade_smooth()
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=0.9, radius2=0.45, depth=1.6, location=(0, 0, -0.92))
    base = bpy.context.object; base.name = "TableBase"; base.data.materials.append(wood)
    bpy.ops.object.shade_auto_smooth()
    export("table")


def build_tombstone():
    """Lápida con cruz grabada, para decorar la mesa."""
    reset()
    stone = material("Stone", (0.42, 0.40, 0.55), 0.9)
    dark = material("StoneDark", (0.2, 0.18, 0.3), 0.9)
    W, H, D, seg = 0.5, 0.75, 0.14, 16
    pts = [(-W / 2, 0), (W / 2, 0)]
    for i in range(seg + 1):
        a = math.pi * i / seg
        pts.append((W / 2 * math.cos(a), H - W / 2 + W / 2 * math.sin(a)))
    bm = bmesh.new()
    front = [bm.verts.new((x, -D / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, D / 2, z)) for x, z in pts]
    bm.faces.new(front); bm.faces.new(list(reversed(back)))
    n = len(pts)
    for i in range(n):
        bm.faces.new((front[i], front[(i + 1) % n], back[(i + 1) % n], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Tombstone"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("Tombstone", me); bpy.context.scene.collection.objects.link(ob)
    me.materials.append(stone)
    bev = ob.modifiers.new("Bevel", "BEVEL"); bev.width = 0.02; bev.segments = 3
    for loc, scale in (((0, -D / 2 - 0.005, 0.47), (0.035, 0.012, 0.15)), ((0, -D / 2 - 0.005, 0.52), (0.1, 0.012, 0.035))):
        bpy.ops.mesh.primitive_cube_add(location=loc, scale=scale)
        bpy.context.object.data.materials.append(dark)
    export("tombstone")


def cone_between(bm, p0, p1, r0, r1, seg=7):
    """Tronco de cono entre dos puntos (para ramas)."""
    from mathutils import Vector
    axis = (p1 - p0).normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(ref).normalized(); v = axis.cross(u)
    a = [bm.verts.new(p0 + (u * math.cos(2 * math.pi * i / seg) + v * math.sin(2 * math.pi * i / seg)) * r0) for i in range(seg)]
    b = [bm.verts.new(p1 + (u * math.cos(2 * math.pi * i / seg) + v * math.sin(2 * math.pi * i / seg)) * r1) for i in range(seg)]
    for i in range(seg):
        bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    bm.faces.new(list(reversed(b)))


def build_tree():
    """Árbol seco y retorcido para el fondo del cementerio."""
    import random
    from mathutils import Vector, Matrix
    reset()
    rnd = random.Random(7)
    bm = bmesh.new()

    def branch(p, d, length, radius, depth):
        end = p + d * length
        cone_between(bm, p, end, radius, radius * 0.62)
        if depth == 0:
            return
        for _ in range(2 if depth < 3 else 3):
            perp = d.cross(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))).normalized()
            nd = (Matrix.Rotation(math.radians(rnd.uniform(24, 52)), 3, perp) @ d).normalized()
            nd.z = abs(nd.z) * 0.8 + 0.15
            branch(end, nd.normalized(), length * rnd.uniform(0.6, 0.78), radius * 0.62, depth - 1)

    branch(Vector((0, 0, 0)), Vector((0.08, 0.0, 1)).normalized(), 1.5, 0.22, 4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Tree"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("Tree", me); bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material("Bark", (0.05, 0.035, 0.06), 0.95))
    for p in me.polygons:
        p.use_smooth = True
    export("tree")


def build_lantern():
    """Farol de mesa: base y tapa de metal, vidrio que emite luz."""
    reset()
    metal = material("LanternMetal", (0.07, 0.06, 0.09), 0.35, 0.9)
    glass = material("LanternGlass", (1.0, 0.72, 0.3), 0.2)
    b = glass.node_tree.nodes.get("Principled BSDF")
    b.inputs["Emission Color"].default_value = (1.0, 0.62, 0.22, 1.0)
    b.inputs["Emission Strength"].default_value = 4.0
    def add(op, mat, **kw):
        op(**kw); o = bpy.context.object; o.data.materials.append(mat); bpy.ops.object.shade_auto_smooth(); return o
    add(bpy.ops.mesh.primitive_cylinder_add, metal, vertices=24, radius=0.1, depth=0.035, location=(0, 0, 0.0175))
    add(bpy.ops.mesh.primitive_cylinder_add, glass, vertices=24, radius=0.07, depth=0.17, location=(0, 0, 0.12))
    add(bpy.ops.mesh.primitive_cone_add, metal, vertices=24, radius1=0.105, radius2=0.03, depth=0.07, location=(0, 0, 0.24))
    add(bpy.ops.mesh.primitive_torus_add, metal, major_segments=24, minor_segments=8, major_radius=0.04, minor_radius=0.008, location=(0, 0, 0.3), rotation=(math.pi / 2, 0, 0))
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        add(bpy.ops.mesh.primitive_cylinder_add, metal, vertices=8, radius=0.007, depth=0.18, location=(0.078 * math.cos(a), 0.078 * math.sin(a), 0.12))
    export("lantern")


def build_fence():
    """Tramo de reja de hierro con puntas."""
    reset()
    iron = material("Iron", (0.03, 0.03, 0.05), 0.5, 0.8)
    n, width, h = 9, 2.4, 1.3
    for i in range(n):
        x = -width / 2 + width * i / (n - 1)
        tall = h + (0.18 if i % 2 == 0 else 0.0)
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.022, depth=tall, location=(x, 0, tall / 2))
        bpy.context.object.data.materials.append(iron)
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.05, radius2=0.0, depth=0.16, location=(x, 0, tall + 0.08))
        bpy.context.object.data.materials.append(iron)
    for z in (0.28, h - 0.12):
        bpy.ops.mesh.primitive_cube_add(location=(0, 0, z), scale=(width / 2, 0.018, 0.022))
        bpy.context.object.data.materials.append(iron)
    export("fence")


build_card()
build_table()
build_tombstone()
build_tree()
build_lantern()
build_fence()
