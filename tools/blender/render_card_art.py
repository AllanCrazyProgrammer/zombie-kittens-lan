"""Ilustraciones 3D de las cartas, renderizadas con Cycles (godot/assets/art/<carta>.png, 750x1050).
Cada carta es una pequeña escena con gatos de estilo "juguete de vinilo" construidos por código.

Uso:  Blender --background --python tools/blender/render_card_art.py -- [carta ...] [--samples N]
"""
import math
import os
import sys
import random
import bpy
from mathutils import Vector

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "godot", "assets", "art")
FONT = os.path.join(ROOT, "godot", "assets", "fonts", "Bangers-Regular.ttf")
os.makedirs(OUT, exist_ok=True)
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SAMPLES = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 96
ONLY = [a for a in argv if not a.startswith("--") and not a.isdigit()]


def hexc(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(ch * 2 for ch in h)
    return tuple(pow(int(h[i:i + 2], 16) / 255.0, 2.2) for i in (0, 2, 4))


# ---------------------------------------------------------------- primitivas
def mat(color, rough=0.5, metal=0.0, emit=0.0, emit_color=None, trans=0.0, coat=0.0):
    m = bpy.data.materials.new("m")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    c = hexc(color) if isinstance(color, str) else color
    b.inputs["Base Color"].default_value = (*c, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        e = hexc(emit_color) if isinstance(emit_color, str) else (emit_color or c)
        b.inputs["Emission Color"].default_value = (*e, 1)
        b.inputs["Emission Strength"].default_value = emit
    if trans:
        b.inputs["Transmission Weight"].default_value = trans
        b.inputs["IOR"].default_value = 1.45
    if coat:
        b.inputs["Coat Weight"].default_value = coat
    return m


def _fin(ob, m, parent):
    if m:
        ob.data.materials.append(m)
    if hasattr(ob.data, "polygons"):
        for p in ob.data.polygons:
            p.use_smooth = True
    if parent:
        ob.parent = parent
    return ob


def sphere(loc, scale, m, parent=None, rot=(0, 0, 0)):
    s = (scale, scale, scale) if isinstance(scale, (int, float)) else scale
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1, location=loc, scale=s, rotation=rot)
    return _fin(bpy.context.object, m, parent)


def cone(loc, r1, r2, depth, m, parent=None, rot=(0, 0, 0), verts=32, direction=None):
    if direction is not None:
        rot = Vector(direction).to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    ob = _fin(bpy.context.object, m, parent)
    if verts <= 8:
        for p in ob.data.polygons:
            p.use_smooth = False
    return ob


def box(loc, scale, m, parent=None, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc, scale=scale, rotation=rot)
    ob = _fin(bpy.context.object, m, parent)
    for p in ob.data.polygons:
        p.use_smooth = False
    if bevel:
        b = ob.modifiers.new("b", "BEVEL"); b.width = bevel; b.segments = 3
    return ob


def tube(points, r, m, parent=None):
    """Tubo redondeado que pasa por los puntos dados (colas, brazos, sonrisas, mechas...)."""
    cu = bpy.data.curves.new("t", "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    cu.bevel_depth = r
    cu.bevel_resolution = 6
    cu.use_fill_caps = True
    ob = bpy.data.objects.new("t", cu)
    bpy.context.scene.collection.objects.link(ob)
    if m:
        cu.materials.append(m)
    if parent:
        ob.parent = parent
    return ob


def text(body, loc, size, m, rot=(math.pi / 2, 0, 0), extrude=0.02, parent=None):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    ob = bpy.context.object
    ob.data.body = body
    ob.data.size = size
    ob.data.extrude = extrude
    ob.data.align_x = "CENTER"
    ob.data.align_y = "CENTER"
    try:
        ob.data.font = bpy.data.fonts.load(FONT)
    except Exception:
        pass
    ob.data.materials.append(m)
    if parent:
        ob.parent = parent
    return ob


def empty(loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0):
    e = bpy.data.objects.new("e", None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    e.rotation_euler = rot
    e.scale = (scale, scale, scale)
    return e


# ---------------------------------------------------------------- el gato
BLACK = "#0c0a12"


def cat(loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0, fur="#2b2342", belly=None, ear="#ff86b3", eye="#ffe14a",
        eyes="normal", eye_l=None, eye_r=None, mouth="smile", arm_l=None, arm_r=None, tail=True, body=True,
        glow_eyes=1.5, whiskers="#ffffff", fur_rough=0.55, fur_mat=None):
    """Gato sentado mirando hacia -Y. arm_l/arm_r: posición local de la mano (si se quiere el brazo levantado)."""
    root = empty()
    F = fur_mat or mat(fur, fur_rough, coat=0.25)
    Bm = mat(belly, 0.6) if belly else F
    P = mat(ear, 0.5)
    K = mat(BLACK, 0.25)
    Wm = mat("#ffffff", 0.3)
    if body:
        sphere((0, 0.02, 0.33), (0.31, 0.27, 0.35), F, root)
        sphere((0, -0.1, 0.3), (0.2, 0.19, 0.25), Bm, root)
        for sx in (-1, 1):
            sphere((0.13 * sx, -0.25, 0.06), (0.085, 0.11, 0.065), F, root)          # patas delanteras
            sphere((0.25 * sx, -0.08, 0.06), (0.1, 0.14, 0.07), F, root)             # patas traseras
        if tail:
            tube([(0.2, 0.2, 0.12), (0.42, 0.3, 0.2), (0.52, 0.28, 0.5), (0.44, 0.24, 0.72)], 0.05, F, root)
    # cabeza
    sphere((0, -0.02, 0.82), (0.37, 0.31, 0.3), F, root)
    for sx in (-1, 1):
        cone((0.215 * sx, 0.0, 1.08), 0.165, 0.0, 0.34, F, root, rot=(0, math.radians(17) * sx, 0))
        cone((0.21 * sx, -0.05, 1.06), 0.1, 0.0, 0.22, P, root, rot=(math.radians(10), math.radians(17) * sx, 0))
        sphere((0.06 * sx, -0.3, 0.725), (0.07, 0.05, 0.055), Bm, root)              # hocico
        if whiskers:
            Wk = mat(whiskers, 0.4)
            for dz in (-0.02, 0.02):
                tube([(0.15 * sx, -0.3, 0.73 + dz), (0.4 * sx, -0.27, 0.73 + dz * 3.5)], 0.0035, Wk, root)
    sphere((0, -0.335, 0.765), (0.03, 0.02, 0.022), P, root)                          # nariz

    def eye_at(sx, style):
        x, y, z = 0.145 * sx, -0.275, 0.86
        if style == "x":
            for a in (-1, 1):
                tube([(x - 0.06, y - 0.03, z - 0.06 * a), (x + 0.06, y - 0.03, z + 0.06 * a)], 0.016, K, root)
        elif style == "closed":
            tube([(x - 0.065, y - 0.025, z + 0.01), (x, y - 0.045, z - 0.03), (x + 0.065, y - 0.025, z + 0.01)], 0.013, K, root)
        elif style == "happy":
            tube([(x - 0.065, y - 0.025, z - 0.02), (x, y - 0.045, z + 0.03), (x + 0.065, y - 0.025, z - 0.02)], 0.013, K, root)
        elif style == "wide":
            sphere((x, y, z), (0.095, 0.05, 0.1), Wm, root)
            sphere((x, y - 0.045, z), (0.025, 0.012, 0.025), K, root)
        elif style == "big":
            sphere((x, y, z - 0.01), (0.1, 0.05, 0.105), K, root)
            sphere((x - 0.03, y - 0.047, z + 0.035), 0.028, mat("#ffffff", 0.2, emit=2), root)
            sphere((x + 0.035, y - 0.047, z - 0.035), 0.014, mat("#ffffff", 0.2, emit=2), root)
        elif style == "socket":
            sphere((x, y + 0.01, z), (0.09, 0.05, 0.1), K, root)
            sphere((x, y - 0.035, z), 0.028, mat(eye, 0.3, emit=6), root)
        else:
            E = mat(eye, 0.2, emit=glow_eyes, coat=1.0)
            sphere((x, y, z), (0.085, 0.045, 0.095), E, root)
            if style != "glow":
                sphere((x, y - 0.04, z), (0.022, 0.012, 0.075), K, root)
                sphere((x - 0.028, y - 0.045, z + 0.04), 0.016, mat("#ffffff", 0.2, emit=3), root)
            if style == "angry":
                tube([(x - 0.11 * sx, y - 0.05, z + 0.135), (x + 0.1 * sx, y - 0.06, z + 0.06)], 0.022, K, root)
    eye_at(-1, eye_l or eyes)
    eye_at(1, eye_r or eyes)

    if mouth in ("smile", "fangs"):
        for sx in (-1, 1):
            tube([(0, -0.335, 0.735), (0.045 * sx, -0.34, 0.7), (0.1 * sx, -0.31, 0.725)], 0.008, K, root)
        if mouth == "fangs":
            for sx in (-1, 1):
                cone((0.05 * sx, -0.335, 0.68), 0.016, 0.0, 0.055, Wm, root, rot=(math.pi, 0, 0))
    elif mouth == "open":
        sphere((0, -0.31, 0.69), (0.07, 0.04, 0.06), mat("#5a1030", 0.4), root)
        for sx in (-1, 1):
            cone((0.035 * sx, -0.34, 0.715), 0.013, 0.0, 0.045, Wm, root, rot=(math.pi, 0, 0))
    elif mouth == "flat":
        tube([(-0.06, -0.335, 0.705), (0.06, -0.335, 0.705)], 0.008, K, root)
    elif mouth == "sad":
        tube([(-0.065, -0.325, 0.69), (0, -0.34, 0.715), (0.065, -0.325, 0.69)], 0.008, K, root)

    for sx, hand in ((-1, arm_l), (1, arm_r)):
        if hand:
            sh = Vector((0.24 * sx, -0.08, 0.5))
            h = Vector(hand)
            mid = (sh + h) / 2 + Vector((0.05 * sx, -0.03, -0.02))
            tube([sh, mid, h], 0.062, F, root)
            sphere(h, (0.09, 0.085, 0.09), F, root)
            sphere(h + Vector((0, -0.07, 0)), (0.045, 0.02, 0.04), P, root)
    root.location = loc
    root.rotation_euler = rot
    root.scale = (scale, scale, scale)
    return root


ZOMBIE = dict(fur="#7fc23a", belly="#a4dc5a", ear="#4f8a1e", eye="#fff36b", eye_l="x", mouth="fangs")


def stitches(root, m=None):
    m = m or mat("#22400c", 0.6)
    tube([(-0.12, -0.3, 1.0), (0.04, -0.31, 0.97)], 0.008, m, root)
    for i in range(3):
        x = -0.09 + i * 0.05
        tube([(x, -0.31, 1.02 - i * 0.012), (x - 0.01, -0.31, 0.96 - i * 0.012)], 0.007, m, root)


def tombstone(loc, scale=1.0, rot_z=0.0, color="#77709a"):
    r = empty()
    S = mat(color, 0.9)
    box((0, 0, 0.3), (0.22, 0.07, 0.3), S, r)
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.22, depth=0.14, location=(0, 0, 0.6), rotation=(math.pi / 2, 0, 0))
    o = _fin(bpy.context.object, S, r)
    bpy.ops.object.shade_auto_smooth()
    D = mat("#3b3658", 0.9)
    box((0, -0.075, 0.5), (0.025, 0.01, 0.12), D, r)
    box((0, -0.075, 0.55), (0.08, 0.01, 0.025), D, r)
    r.location = loc
    r.rotation_euler = (0, 0, rot_z)
    r.scale = (scale,) * 3
    return r


def bomb(loc, scale=1.0):
    r = empty()
    sphere((0, 0, 0.3), 0.3, mat("#15131c", 0.18, coat=1.0), r)
    cone((0, 0, 0.62), 0.07, 0.07, 0.08, mat("#4a4458", 0.4, 0.8), r)
    tube([(0, 0, 0.64), (0.05, 0, 0.76), (0.16, -0.02, 0.8), (0.22, -0.03, 0.9)], 0.014, mat("#c9a36b", 0.8), r)
    sphere((0.23, -0.03, 0.93), 0.06, mat("#ffd23a", 0.3, emit=40, emit_color="#ffb020"), r)
    for i in range(7):
        a = i * 0.9
        sphere((0.23 + 0.13 * math.cos(a), -0.03, 0.93 + 0.13 * math.sin(a)), 0.014, mat("#fff", 0.3, emit=30, emit_color="#ffd060"), r)
    r.location = loc
    r.scale = (scale,) * 3
    return r


def mini_card(loc, rot, color, scale=1.0, emit=0.0):
    return box(loc, (0.09 * scale, 0.004, 0.126 * scale), mat(color, 0.35, emit=emit), rot=rot, bevel=0.003)


def moon(loc=(1.5, 6, 2.35), r=0.55):
    sphere(loc, r, mat("#fff6c9", 0.5, emit=6, emit_color="#fff1b8"))


def stars(n=40, seed=3, color="#ffffff"):
    rnd = random.Random(seed)
    m = mat(color, 0.5, emit=25)
    for _ in range(n):
        sphere((rnd.uniform(-5, 5), 7, rnd.uniform(1.3, 3.4)), rnd.uniform(0.008, 0.02), m)


# ---------------------------------------------------------------- escena base
def stage(sky_top, sky_bottom, ground, key="#fff2dc", rim="#b6f23a", fill="#8fa0ff", hills=None, key_power=300, rim_power=420, bare=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception as e:
        print("GPU no disponible:", e)
    sc.render.resolution_x, sc.render.resolution_y = 750, 1050
    sc.render.film_transparent = False
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Punchy"
        sc.view_settings.exposure = 0.9
    except Exception:
        sc.view_settings.view_transform = "Standard"
    # cielo: degradado vertical en pantalla
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    nt = w.node_tree; nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB"); bg = nt.nodes.new("ShaderNodeBackground"); out = nt.nodes.new("ShaderNodeOutputWorld")
    ramp.color_ramp.elements[0].position = 0.25; ramp.color_ramp.elements[0].color = (*hexc(sky_bottom), 1)
    ramp.color_ramp.elements[1].position = 1.0; ramp.color_ramp.elements[1].color = (*hexc(sky_top), 1)
    nt.links.new(tc.outputs["Window"], sep.inputs[0]); nt.links.new(sep.outputs["Y"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bg.inputs[0]); nt.links.new(bg.outputs[0], out.inputs[0])
    bg.inputs[1].default_value = 1.0
    # suelo y colinas que tapan el horizonte
    if not bare:
        bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
        bpy.context.object.data.materials.append(mat(ground, 0.9))
        H = mat(hills or ground, 0.95)
        sphere((-3.2, 7.5, -0.6), (4.5, 3, 2.0), H); sphere((3.6, 9, -0.8), (5.5, 3, 2.4), H); sphere((0, 12, -1.0), (9, 3, 2.6), H)
    # luces
    def area(loc, power, color, size, target=(0, 0, 0.6)):
        l = bpy.data.lights.new("l", "AREA"); l.energy = power; l.color = hexc(color); l.size = size
        o = bpy.data.objects.new("l", l); sc.collection.objects.link(o); o.location = loc
        o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    area((-2.4, -3.2, 3.6), key_power, key, 2.5)
    area((2.8, -2.6, 1.4), key_power * 0.25, fill, 3.0)
    area((1.2, 2.8, 2.6), rim_power, rim, 1.6)
    area((-1.8, 2.4, 1.8), rim_power * 0.5, rim, 1.6)
    # cámara
    cd = bpy.data.cameras.new("c"); cd.lens = 35; cd.sensor_fit = "VERTICAL"; cd.sensor_height = 36
    cd.dof.use_dof = True; cd.dof.focus_distance = 3.5; cd.dof.aperture_fstop = 4.0
    co = bpy.data.objects.new("c", cd); sc.collection.objects.link(co)
    # Cámara baja y casi horizontal: el personaje queda entre el título (arriba) y el panel de texto (abajo),
    # con una franja de cielo visible sobre el horizonte.
    co.location = (0, -3.5, 0.96)
    co.rotation_euler = (Vector((0, 0, 0.55)) - Vector(co.location)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co


def render(name):
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("ARTE", name)


# ---------------------------------------------------------------- las 19 cartas
def s_zombie():
    stage("#1b0f45", "#5a2f9a", "#243d18", rim="#b6f23a", hills="#162a10")
    moon(); stars(30)
    tombstone((-0.75, 0.9, 0), 1.5, 0.25)
    c = cat(loc=(0, 0.1, -0.2), arm_r=(0.52, -0.12, 1.2), tail=False, **ZOMBIE)
    stitches(c)
    D = mat("#3b2a18", 0.95)
    sphere((0, -0.15, -0.05), (0.75, 0.5, 0.2), D)
    for i, (x, y, s) in enumerate([(-0.5, -0.5, 0.1), (0.45, -0.55, 0.08), (0.7, -0.2, 0.12), (-0.75, -0.15, 0.09), (0.1, -0.62, 0.07)]):
        sphere((x, y, 0.04), s, D)


def s_exploding():
    stage("#ff9a1f", "#d6281f", "#7a1408", key="#fff0c0", rim="#ffd23a", fill="#ff6a3a", hills="#9a1c10", rim_power=660)
    c = cat(loc=(-0.28, 0.05, 0), fur="#17131f", ear="#ff5a7a", eyes="wide", mouth="open", whiskers=None, fur_rough=0.4)
    F = mat("#17131f", 0.4)
    rnd = random.Random(5)
    for i in range(16):
        a = math.radians(-30 + i * 16)
        d = Vector((math.cos(a), rnd.uniform(-0.2, 0.2), math.sin(a)))
        cone(Vector((0, 0, 0.84)) + d * 0.33, 0.07, 0.0, 0.22, F, c, direction=d)
    bomb((0.5, -0.25, 0), 1.0)
    S = mat("#ffd23a", 0.3, emit=30, emit_color="#ffb020")
    for i in range(26):
        sphere((rnd.uniform(-1.3, 1.3), rnd.uniform(-0.5, 1.5), rnd.uniform(0.2, 1.9)), rnd.uniform(0.012, 0.035), S)


def s_attack():
    stage("#ff8a2e", "#c82a22", "#5a1210", key="#fff0d8", rim="#ffd23a", hills="#7a1810")
    c = cat(loc=(-0.2, 0, 0), rot=(0, 0, math.radians(-14)), fur="#2b2342", eyes="angry", mouth="fangs", arm_r=(0.5, -0.3, 1.05))
    W = mat("#ffffff", 0.3)
    for i in range(3):
        cone((0.44 + i * 0.055, -0.36, 1.15), 0.016, 0.0, 0.09, W, c)
    G = mat("#fff6c0", 0.3, emit=22, emit_color="#ffe27a")
    for i in range(3):
        x = 0.42 + i * 0.2
        tube([(x, -0.75, 1.45), (x + 0.22, -0.8, 1.0), (x + 0.14, -0.75, 0.45), (x - 0.02, -0.7, 0.2)], 0.022, G)


def s_attack_dead():
    stage("#12301a", "#2f6b2a", "#0e1f10", rim="#b6f23a", fill="#4a8a4a", hills="#0a160b", key_power=228)
    moon((0, 6, 2.45), 0.9)
    for x, y, s, tone in ((-0.85, 0.9, 0.78, "#4f8f2a"), (0.85, 0.9, 0.78, "#4f8f2a"), (-1.5, 1.8, 0.62, "#35701c"), (1.5, 1.8, 0.62, "#35701c")):
        z = dict(ZOMBIE); z["fur"] = tone; z["belly"] = None
        cat(loc=(x, y, 0), scale=s, arm_l=(-0.2, -0.5, 0.72), arm_r=(0.2, -0.5, 0.72), eye_l="x" if x < 0 else "normal", eye_r="normal" if x < 0 else "x", **{k: v for k, v in z.items() if k not in ("eye_l",)})
    c = cat(loc=(0, -0.05, 0), arm_l=(-0.24, -0.55, 0.78), arm_r=(0.24, -0.55, 0.78), **ZOMBIE)
    stitches(c)


def s_nope():
    stage("#ff5a6e", "#9c1235", "#5a0c22", rim="#ffd0d8", hills="#7a1030")
    cat(loc=(-0.3, 0, 0), fur="#f1e6d2", belly="#ffffff", ear="#ff9fbf", eyes="closed", mouth="flat", whiskers="#5a4a4a", arm_r=(0.5, -0.28, 0.6), tail=False)
    r = empty((0.24, -0.33, 0))
    box((0, 0, 0.42), (0.022, 0.022, 0.42), mat("#e8e0d0", 0.5), r)
    for radius, depth, y, m in ((0.4, 0.05, 0.0, mat("#ffffff", 0.4)), (0.35, 0.06, -0.006, mat("#d4101f", 0.35, coat=0.6))):
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=depth, location=(0, y, 1.08), rotation=(math.pi / 2, math.radians(22.5), 0))
        o = _fin(bpy.context.object, m, r)
        for p in o.data.polygons:
            p.use_smooth = False
    text("NOP", (-0.01, -0.05, 1.07), 0.34, mat("#ffffff", 0.4, emit=1.0), parent=r, extrude=0.012)
    r.location = (0.52, -0.3, 0)


def s_skip():
    stage("#2a6fe0", "#7fd0ff", "#1f6b3a", key="#ffffff", rim="#fff6c0", fill="#bfe6ff", hills="#2f8a4a", key_power=372)
    tombstone((0.05, 0.1, 0), 1.25, -0.1, "#9aa2c9")
    cat(loc=(0.15, 0, 0.95), rot=(math.radians(-12), math.radians(28), 0), scale=0.82, fur="#ff9a2e", belly="#ffd9a0", ear="#ff6f91", eyes="happy",
        arm_l=(-0.45, -0.25, 0.75), arm_r=(0.48, -0.25, 0.8))
    Wd = mat("#ffffff", 0.4, emit=3)
    for i in range(9):
        t = i / 8
        sphere((-1.25 + t * 1.0, 0.0, 0.25 + math.sin(t * math.pi * 0.6) * 1.0), 0.028 + 0.012 * t, Wd)
    for x, y, z, s in ((-1.2, 5, 2.1, 0.5), (1.4, 6, 2.5, 0.7), (0.3, 7, 1.9, 0.45)):
        C = mat("#ffffff", 0.9, emit=0.4)
        sphere((x, y, z), (s, 0.3, s * 0.45), C); sphere((x + s * 0.6, y, z - 0.05), (s * 0.7, 0.3, s * 0.36), C)


def s_super_skip():
    stage("#1a0b55", "#6a35e0", "#1c1048", rim="#ffe66b", fill="#b08aff", hills="#150a3a")
    stars(60, 9, "#ffe66b")
    for x, s in ((-0.85, 0.75), (-0.05, 0.9), (0.8, 0.75)):
        tombstone((x, 0.5, 0), s, 0.1 * x, "#8b76d6")
    c = cat(loc=(-0.05, -0.1, 1.25), rot=(math.radians(-8), math.radians(72), math.radians(8)), scale=0.8, fur="#ff9a2e", belly="#ffd9a0", ear="#ff6f91",
            eyes="angry", eye="#ffffff", arm_l=(-0.2, -0.1, 1.35), arm_r=(0.2, -0.1, 1.35), tail=False)
    R = mat("#e11d2e", 0.5)
    cone((0, 0.2, 0.25), 0.5, 0.12, 0.75, R, c, rot=(math.radians(-22), 0, 0), verts=24).scale = (1, 0.18, 1)
    G = mat("#ffe66b", 0.4, emit=14)
    for i, z in enumerate((1.05, 1.3, 1.55)):
        tube([(-1.5, 0.2, z), (-0.85 - i % 2 * 0.2, 0.2, z)], 0.014, G)


def s_see_future():
    stage("#2a0c5a", "#b34cff", "#2a1050", rim="#ff9fff", fill="#9fd8ff", hills="#1c0a3a")
    stars(40, 4, "#ffd6ff")
    cat(loc=(0, 0.7, 0.42), scale=1.15, fur="#3a2a6a", eyes="glow", eye="#8ff2ff", glow_eyes=9, mouth="smile", arm_l=(-0.5, -0.6, 0.25), arm_r=(0.5, -0.6, 0.25), tail=False)
    G = mat("#e0a21c", 0.25, 1.0)
    cone((0, -0.1, 0.09), 0.34, 0.2, 0.18, G)
    sphere((0, -0.1, 0.58), 0.42, mat("#dff8ff", 0.02, trans=1.0))
    mini_card((-0.17, -0.1, 0.62), (0, 0, math.radians(18)), "#ffe14a", 1.25, 2.5)
    mini_card((0.17, -0.1, 0.62), (0, 0, math.radians(-18)), "#7ee06a", 1.25, 2.5)
    mini_card((0, -0.16, 0.65), (0, 0, 0), "#ffffff", 1.35, 2.5)
    text("?", (0, -0.18, 0.64), 0.2, mat("#3c1273", 0.4))


def s_shuffle():
    stage("#0c5a6a", "#22d3b4", "#0c4a50", rim="#c8fff0", hills="#0a3a40")
    cat(loc=(0, 0.2, 0), fur="#2b2342", eyes="happy", arm_l=(-0.5, -0.2, 0.95), arm_r=(0.5, -0.2, 0.95))
    cols = ["#ffe14a", "#ff7fb0", "#ffffff", "#7ee06a", "#ff9a2e", "#8ff2ff", "#b08aff"]
    for i in range(7):
        a = math.radians(160 - i * 23.5)
        mini_card((math.cos(a) * 0.95, -0.25, 1.05 + math.sin(a) * 0.62), (math.radians(8), a - math.pi / 2, 0), cols[i], 1.5)
    Wd = mat("#ffffff", 0.3, emit=8)
    


def s_feed_dead():
    stage("#5d7a1c", "#c9d64a", "#3a4a12", rim="#f0ff9a", hills="#4a601a")
    c = cat(loc=(-0.25, 0, 0), eye_r="wide", arm_r=(0.42, -0.3, 0.62), **dict(ZOMBIE, mouth="open"))
    stitches(c)
    r = empty((0.5, -0.36, 0))
    M = mat("#dfe4f2", 0.2, 1.0)
    tube([(0, 0, 0.35), (0, 0, 1.0)], 0.02, M, r)
    for dx in (-0.07, 0, 0.07):
        tube([(dx, 0, 1.0), (dx, 0, 1.22)], 0.013, M, r)
    tube([(-0.07, 0, 1.0), (0.07, 0, 1.0)], 0.014, M, r)
    B = mat("#ff9fc0", 0.35, coat=0.6)
    rnd = random.Random(2)
    for i in range(22):
        a, b = rnd.uniform(0, 6.28), rnd.uniform(-0.6, 1.2)
        sphere((0.17 * math.cos(a) * math.cos(b) * 1.15, 0.13 * math.sin(a) * math.cos(b), 1.36 + 0.13 * math.sin(b)), 0.07, B, r)


def s_clone():
    stage("#1d6fb8", "#5fe0ff", "#1a4a80", rim="#ffffff", hills="#16407a")
    cat(loc=(-0.48, 0, 0), scale=0.9, fur="#ff8a3d", belly="#ffd0a8", ear="#ffb0c8", eyes="normal")
    holo = mat("#39e6c9", 0.15, emit=1.6, emit_color="#39e6c9", trans=0.7)
    cat(loc=(0.48, 0, 0), scale=0.9, eye="#ffffff", eyes="normal", fur_mat=holo, ear="#bafff2", whiskers="#bafff2", glow_eyes=6)
    Wd = mat("#ffffff", 0.3, emit=12)
    for i in range(9):
        sphere((0, -0.2, 0.12 + i * 0.16), 0.022, Wd)


def s_grave_robber():
    stage("#12142e", "#3a3a7a", "#2e2a1e", key="#ffe6c0", rim="#9fb2ff", fill="#6a70c0", hills="#1a1a30", key_power=228)
    moon((-1.6, 6, 2.4), 0.55); stars(30, 8)
    tombstone((0.72, 0.75, 0), 1.35, -0.2)
    box((0.7, -0.1, 0.005), (0.42, 0.3, 0.006), mat("#050408", 1.0))
    D = mat("#3b2a18", 0.95)
    sphere((1.25, -0.2, 0.0), (0.3, 0.3, 0.2), D)
    c = cat(loc=(-0.35, 0, 0), fur="#1c1826", eyes="normal", eye="#ffffff", arm_l=(-0.5, -0.25, 0.6))
    box((0, -0.3, 0.86), (0.36, 0.03, 0.06), mat("#050408", 0.6), c)
    for sx in (-1, 1):
        sphere((0.145 * sx, -0.305, 0.86), (0.06, 0.03, 0.05), mat("#ffe14a", 0.2, emit=3), c)
        sphere((0.145 * sx, -0.335, 0.86), (0.016, 0.01, 0.045), mat(BLACK, 0.3), c)
    S = mat("#d9b36b", 0.85)
    sphere((-0.92, -0.3, 0.3), (0.3, 0.27, 0.32), S)
    cone((-0.92, -0.3, 0.68), 0.1, 0.16, 0.16, S)
    text("$", (-0.92, -0.58, 0.3), 0.3, mat("#8a6a2e", 0.6))
    tube([(0.3, -0.45, 0.02), (0.55, -0.35, 0.95)], 0.022, mat("#b9854a", 0.6))
    box((0.6, -0.33, 1.08), (0.11, 0.012, 0.14), mat("#cfd4e6", 0.25, 1.0), rot=(0, math.radians(-14), 0), bevel=0.01)


def s_favor():
    stage("#e0457e", "#ffb8dc", "#b03068", key="#fff6f0", rim="#ffffff", fill="#ffd0e8", hills="#c83a74", key_power=360)
    cat(loc=(0, 0, 0), fur="#fff5e6", belly="#ffffff", ear="#ff9fbf", eyes="big", mouth="sad", whiskers="#b89a9a", arm_l=(-0.2, -0.42, 0.5), arm_r=(0.2, -0.42, 0.5))
    R = mat("#ff2a55", 0.25, coat=1.0)
    for sx in (-1, 1):
        sphere((0.085 * sx, -0.5, 0.56), 0.11, R)
    cone((0, -0.5, 0.42), 0.165, 0.0, 0.26, R, rot=(math.pi, 0, 0)).scale = (1, 0.62, 1)
    H = mat("#ffffff", 0.3, emit=2.5)
    rnd = random.Random(4)
    for _ in range(9):
        x, z, s = rnd.uniform(-1.3, 1.3), rnd.uniform(1.25, 1.95), rnd.uniform(0.04, 0.09)
        y = rnd.uniform(0.5, 2)
        for sx in (-1, 1):
            sphere((x + s * 0.75 * sx, y, z), s, H)
        cone((x, y, z - s * 1.2), s * 1.5, 0.0, s * 2.2, H, rot=(math.pi, 0, 0)).scale = (1, 0.6, 1)


def s_dig_deeper():
    stage("#ffb84a", "#ffe9a8", "#6b4226", key="#fff6e0", rim="#ffe9a8", hills="#58a83a", key_power=372)
    D = mat("#4f2f1a", 0.95)
    box((0.3, -0.35, 0.004), (0.5, 0.36, 0.006), mat("#140c06", 1.0))
    sphere((-0.75, -0.3, 0.0), (0.42, 0.36, 0.3), D); sphere((-0.5, -0.55, 0.0), (0.2, 0.2, 0.14), D)
    mini_card((0.2, -0.4, 0.1), (math.radians(60), 0, math.radians(-12)), "#ffffff", 1.7)
    mini_card((0.45, -0.3, 0.07), (math.radians(68), 0, math.radians(14)), "#ffe14a", 1.7)
    text("1", (0.2, -0.47, 0.13), 0.16, mat("#6b4226", 0.5), rot=(math.radians(60), 0, math.radians(-12)), extrude=0.004)
    cat(loc=(-0.15, 0.45, 0), fur="#2b2342", eyes="normal", arm_l=(-0.35, -0.35, 0.72), arm_r=(0.3, -0.38, 0.6))
    tube([(-0.6, 0.05, 1.3), (0.35, -0.15, 0.35)], 0.024, mat("#b9854a", 0.6))
    box((0.47, -0.18, 0.2), (0.13, 0.012, 0.16), mat("#dfe4f2", 0.2, 1.0), rot=(0, math.radians(-42), 0), bevel=0.012)


def s_clairvoyance():
    stage("#07103a", "#2747c9", "#0b1247", rim="#49e0e6", fill="#7a8aff", hills="#081040", key_power=228)
    stars(50, 6, "#9fe8ff")
    cat(loc=(0, 0.3, 0), scale=0.9, fur="#1c2260", eyes="glow", eye="#49e0e6", glow_eyes=10, arm_l=(-0.5, -0.25, 0.85), arm_r=(0.5, -0.25, 0.85))
    r = empty((0, -0.15, 1.36), scale=0.8)
    sphere((0, 0, 0), (0.46, 0.2, 0.3), mat("#f4fbff", 0.25, coat=1.0), r)
    sphere((0, -0.14, 0), (0.24, 0.1, 0.24), mat("#49e0e6", 0.2, emit=3, coat=1.0), r)
    sphere((0, -0.22, 0), (0.07, 0.03, 0.2), mat(BLACK, 0.2), r)
    G = mat("#9fe8ff", 0.3, emit=12)
    for i in range(9):
        a = math.radians(20 + i * 17.5)
        d = Vector((math.cos(a), 0, math.sin(a)))
        tube([Vector((0, 0, 1.36)) + d * 0.5 + Vector((0, -0.1, 0)), Vector((0, 0, 1.36)) + d * 0.66 + Vector((0, -0.1, 0))], 0.012, G)
    bomb((0.0, -0.75, 0), 0.5)


def s_cat_a():
    stage("#ffb84a", "#ffe7a3", "#d9a84a", key="#fff6e0", rim="#fff0c0", hills="#c98a2e", key_power=360)
    cone((-1.9, 6, 1.6), 3.2, 0.0, 3.6, mat("#c98a2e", 0.9), verts=4, rot=(0, 0, math.radians(45)))
    cone((2.4, 8, 1.2), 2.6, 0.0, 2.8, mat("#b87a26", 0.9), verts=4, rot=(0, 0, math.radians(45)))
    c = cat(loc=(0, 0, 0), fur="#efe6cf", ear="#d9c9a3", eye="#7ee06a", eyes="normal", mouth="flat", whiskers=None, glow_eyes=3, arm_r=(0.5, -0.2, 0.72))
    Bn = mat("#fbf6e6", 0.8)
    rnd = random.Random(1)
    def band(z, rx, ry, tilt, y=0.0, rr=0.022):
        bpy.ops.mesh.primitive_torus_add(major_segments=48, minor_segments=8, major_radius=1, minor_radius=rr / max(rx, ry), location=(0, y, z), rotation=(math.radians(tilt), math.radians(rnd.uniform(-6, 6)), 0))
        o = _fin(bpy.context.object, Bn, c); o.scale = (rx, ry, max(rx, ry))
    for i, z in enumerate((0.12, 0.2, 0.28, 0.36, 0.44, 0.52)):
        w = 0.33 * math.sqrt(max(0.05, 1 - ((z - 0.33) / 0.36) ** 2))
        band(z, w, w * 0.88, rnd.uniform(-8, 8), 0.02)
    for z, tilt in ((0.7, 10), (0.76, -6), (0.95, 8), (1.0, -10), (0.9, 30)):
        w = 0.385 * math.sqrt(max(0.05, 1 - ((z - 0.82) / 0.31) ** 2))
        band(z, w, w * 0.85, tilt, -0.02)
    tube([(0.5, -0.2, 0.72), (0.62, -0.22, 0.5), (0.58, -0.2, 0.3)], 0.02, Bn, c)


def s_cat_b():
    stage("#1a0618", "#8a1f4f", "#2a0a2e", key="#ffe0e0", rim="#ff4d6e", fill="#a070ff", hills="#1a0620", key_power=252)
    moon((1.5, 6, 2.4), 0.65)
    c = cat(loc=(0, 0.05, 0), fur="#241c36", ear="#e11d2e", eye="#ff3048", eyes="normal", mouth="fangs", glow_eyes=5)
    K = mat("#0e0a14", 0.5); R = mat("#c2182b", 0.45)
    cone((0, 0.2, 0.36), 0.62, 0.3, 0.74, K, c).scale = (1, 0.5, 1)
    cone((0, 0.16, 0.37), 0.57, 0.27, 0.7, R, c).scale = (1, 0.42, 1)
    for sx in (-1, 1):
        cone((0.27 * sx, 0.05, 0.72), 0.14, 0.0, 0.36, K, c, rot=(math.radians(-10), math.radians(-28) * sx, 0), verts=3)
    Bt = mat("#0a0810", 0.6)
    for x, z, s in ((-1.15, 1.85, 1.0), (-0.6, 2.05, 0.7), (1.05, 1.7, 0.8)):
        sphere((x, 1.5, z), 0.06 * s, Bt)
        for sx in (-1, 1):
            cone((x + 0.12 * s * sx, 1.5, z + 0.02), 0.09 * s, 0.0, 0.2 * s, Bt, rot=(0, math.radians(90) * sx, 0), verts=3).scale = (1, 0.2, 1)


def s_cat_c():
    stage("#1c1c6a", "#6b7cff", "#22226a", key="#e8f0ff", rim="#c8d4ff", fill="#9fb0ff", hills="#1a1a5a", key_power=252)
    stars(40, 2)
    r = empty((0, 0, 0.42))
    G = mat("#f4f7ff", 0.5, emit=0.55, emit_color="#c8d4ff")
    sphere((0, 0, 0.62), (0.44, 0.38, 0.44), G, r)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.44, depth=0.6, location=(0, 0, 0.32))
    o = _fin(bpy.context.object, G, r); o.scale = (1, 0.864, 1)
    for i in range(10):
        a = i * math.tau / 10
        sphere((0.37 * math.cos(a), 0.32 * math.sin(a), 0.03), (0.125, 0.11, 0.12), G, r)
    for sx in (-1, 1):
        cone((0.24 * sx, 0, 1.05), 0.14, 0.0, 0.28, G, r, rot=(0, math.radians(20) * sx, 0))
        sphere((0.15 * sx, -0.345, 0.66), (0.075, 0.04, 0.105), mat("#1b1b4a", 0.3), r)
        sphere((0.27 * sx, -0.3, 0.5), (0.06, 0.03, 0.035), mat("#ff9fbf", 0.5, emit=0.5), r)
    sphere((0, -0.375, 0.56), (0.03, 0.02, 0.022), mat("#ff86b3", 0.5), r)
    sphere((0, -0.36, 0.44), (0.055, 0.03, 0.07), mat("#1b1b4a", 0.3), r)
    r.rotation_euler = (0, math.radians(-7), 0)
    sphere((0, 0, 0.02), (0.5, 0.4, 0.02), mat("#0a0a30", 1.0))
    tombstone((-1.0, 1.1, 0), 1.1, 0.3, "#5a62b0"); tombstone((1.05, 1.4, 0), 0.95, -0.25, "#5a62b0")


def s_cat_d():
    stage("#0c0c12", "#2a3a2a", "#101014", key="#f0fff0", rim="#7ee06a", fill="#4a6a5a", hills="#0a0a0e", key_power=252, rim_power=600)
    c = cat(loc=(0, 0, 0), fur="#f1efe6", ear="#17131f", eyes="socket", eye="#7ee06a", mouth=None, whiskers=None, fur_rough=0.4)
    K = mat("#14121a", 0.5)
    tube([(-0.1, -0.33, 0.7), (0.1, -0.33, 0.7)], 0.008, K, c)
    for i in range(5):
        x = -0.08 + i * 0.04
        tube([(x, -0.335, 0.725), (x, -0.335, 0.675)], 0.006, K, c)
    tube([(0, -0.3, 0.52), (0, -0.33, 0.2)], 0.018, K, c)
    for z, w in ((0.5, 0.15), (0.42, 0.19), (0.34, 0.2), (0.26, 0.18)):
        tube([(-w, -0.2, z + 0.03), (0, -0.335 + (0.36 - z) * 0.05, z), (w, -0.2, z + 0.03)], 0.016, K, c)
    G = mat("#7ee06a", 0.4, emit=10)
    rnd = random.Random(12)
    for _ in range(14):
        sphere((rnd.uniform(-1.3, 1.3), rnd.uniform(0.3, 2), rnd.uniform(0.2, 2.2)), rnd.uniform(0.012, 0.03), G)
    tombstone((-1.0, 1.0, 0), 1.15, 0.3, "#3a3a4a"); tombstone((1.05, 1.3, 0), 1.0, -0.25, "#3a3a4a")


# ---------------------------------------------------------------- 10 cartas del pack "crypt"
def arrow(points, color="#ffe14a", r=0.035, emit=6.0, head=0.13):
    """Flecha brillante: tubo por los puntos + punta cónica en el último tramo."""
    m = mat(color, 0.3, emit=emit)
    tube(points, r, m)
    d = (Vector(points[-1]) - Vector(points[-2])).normalized()
    cone(Vector(points[-1]) + d * head * 0.5, head * 0.8, 0.0, head * 1.6, m, direction=d)


def arc_pts(cx, cz, rad, a0, a1, y=-0.2, n=7):
    return [(cx + rad * math.cos(math.radians(a0 + (a1 - a0) * i / (n - 1))), y,
             cz + rad * math.sin(math.radians(a0 + (a1 - a0) * i / (n - 1)))) for i in range(n)]


def ghost_mat():
    return mat("#bfeaff", 0.15, emit=1.4, emit_color="#8fd8ff", trans=0.7)


def sparkles(n, seed, color, area=(-1.3, 1.3, 0.2, 2.0), y=(0.3, 1.5), size=(0.012, 0.03), emit=10):
    rnd = random.Random(seed)
    G = mat(color, 0.4, emit=emit)
    for _ in range(n):
        sphere((rnd.uniform(area[0], area[1]), rnd.uniform(*y), rnd.uniform(area[2], area[3])), rnd.uniform(*size), G)


def s_targeted_attack():
    stage("#ff7a2e", "#b8200f", "#4a0e0a", key="#fff0d8", rim="#ffd23a", hills="#6a1410", rim_power=520)
    cat(loc=(-0.62, -0.05, 0), rot=(0, 0, math.radians(-12)), fur="#2b2342", eyes="angry", mouth="fangs", arm_r=(0.5, -0.4, 0.95))
    r = empty((0.62, 0.35, 0), scale=1.0)
    tube([(0, 0.0, 0.0), (0, 0.0, 0.62)], 0.03, mat("#b9854a", 0.6), r)
    box((0, 0.0, 0.02), (0.3, 0.12, 0.02), mat("#b9854a", 0.6), r)
    for rad, c, y in ((0.52, "#ffffff", 0.0), (0.44, "#e11d2e", -0.012), (0.34, "#ffffff", -0.024), (0.24, "#e11d2e", -0.036), (0.12, "#ffffff", -0.048)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=rad, depth=0.03, location=(0, y, 1.05), rotation=(math.pi / 2, 0, 0))
        _fin(bpy.context.object, mat(c, 0.4, emit=0.3), r)
    sphere((0, -0.06, 1.05), 0.05, mat("#e11d2e", 0.3, emit=3), r)
    # dardo clavado en el centro
    G = mat("#fff6c0", 0.3, emit=14, emit_color="#ffe27a")
    tube([(0, -0.06, 1.05), (-0.45, -0.7, 1.28)], 0.02, mat("#e8e0d0", 0.4), r)
    for sx in (-1, 1):
        sphere((-0.42 + 0.0 * sx, -0.66, 1.3 + 0.07 * sx), (0.09, 0.02, 0.05), mat("#ffd23a", 0.4), r)
    arrow([(0.0, -0.5, 1.5), (0.3, -0.5, 1.68), (0.62, -0.5, 1.6), (0.72, -0.5, 1.5)], "#ffe27a", 0.03, 12, 0.1)
    sparkles(14, 3, "#ffd23a")


def s_reverse():
    stage("#0e7c8a", "#3de0d0", "#0d5058", key="#f2fffb", rim="#c8fff0", hills="#0a4048", rim_power=480)
    cat(loc=(-0.7, 0.1, 0), rot=(0, 0, math.radians(55)), scale=0.85, fur="#ff9a2e", belly="#ffd9a0", ear="#ff6f91", eyes="happy", arm_l=(-0.4, -0.3, 0.55), arm_r=(0.4, -0.3, 0.7))
    cat(loc=(0.7, 0.1, 0), rot=(0, 0, math.radians(-55)), scale=0.85, fur="#2b2342", eyes="normal", mouth="fangs", arm_l=(-0.4, -0.3, 0.7), arm_r=(0.4, -0.3, 0.55))
    # flechas de sentido contrario bajo cada gato y circular grande arriba
    arrow([(-1.2, -0.5, 0.12), (-0.5, -0.55, 0.14), (0.1, -0.55, 0.14)], "#ffe14a", 0.045, 8, 0.18)
    arrow([(0.95, -0.5, 0.42), (0.5, -0.55, 0.44), (-0.1, -0.55, 0.44)], "#ff7fb0", 0.045, 8, 0.18)
    arrow(arc_pts(0, 1.4, 0.42, 20, 200, -0.3), "#ffffff", 0.05, 10, 0.18)
    arrow(arc_pts(0, 1.4, 0.42, 200, 380, -0.3), "#ffe14a", 0.05, 10, 0.18)
    sparkles(16, 11, "#c8fff0")


def s_draw_bottom():
    stage("#3a2410", "#9a6a30", "#2a1a0c", key="#ffe9c8", rim="#ffc070", fill="#c08a50", hills="#20120a", key_power=260)
    moon((-1.4, 6, 2.35), 0.5)
    r = empty((0.35, 0.05, 0))
    # mazo vertical: tapa arriba, laterales de cartas
    for i in range(18):
        z = 0.62 + i * 0.045
        box((0, 0, z), (0.34, 0.24, 0.018), mat("#6a3a9a" if i % 2 else "#fbf5e6", 0.5), r, bevel=0.004)
    box((0, 0, 0.58), (0.34, 0.24, 0.02), mat("#3a1a5a", 0.5), r, bevel=0.004)
    # mesa sostiene el mazo
    box((0, 0, 0.28), (0.4, 0.3, 0.28), mat("#4a2f1a", 0.8), r, bevel=0.02)
    # carta del fondo asomando por delante
    box((0, -0.3, 0.42), (0.3, 0.012, 0.19), mat("#ffe14a", 0.35, emit=1.5), r, rot=(math.radians(-14), 0, 0), bevel=0.004)
    text("?", (0.0, -0.325, 0.42), 0.22, mat("#6b3a10", 0.5), parent=r, rot=(math.radians(76), 0, 0), extrude=0.004)
    arrow([(0.35, -0.7, 1.05), (0.35, -0.7, 0.62)], "#ffe14a", 0.04, 10, 0.16)
    c = cat(loc=(-0.75, 0.05, 0), rot=(0, 0, math.radians(15)), fur="#2b2342", eyes="normal", arm_r=(0.45, -0.3, 0.45))


def s_crow_eye():
    stage("#0c0e26", "#3a4388", "#1c1a2a", key="#e8eeff", rim="#9fb2ff", fill="#6a70c0", hills="#101226", key_power=240)
    moon((-1.5, 6, 2.5), 0.6); stars(30, 21)
    tombstone((0.0, 0.6, 0), 1.5, 0.0, "#6a6a8a")
    r = empty((0.0, 0.55, 1.0), scale=1.3)
    Bk = mat("#17131f", 0.25, coat=0.6)
    sphere((0, 0, 0.0), (0.34, 0.3, 0.4), Bk, r)
    sphere((0, -0.12, 0.45), (0.25, 0.23, 0.24), Bk, r)
    cone((0, -0.5, 0.38), 0.1, 0.0, 0.5, mat("#ff9a2e", 0.35, coat=0.6), r, direction=(0, -1, -0.55))
    cone((0, -0.42, 0.4), 0.09, 0.0, 0.4, mat("#d97a1a", 0.35, coat=0.6), r, direction=(0, -1, -0.25))
    for sx in (-1, 1):
        tube([(0.12 * sx, 0, -0.38), (0.12 * sx, -0.05, -0.62)], 0.03, mat("#ff9a2e", 0.5), r)
    for sx in (-1, 1):
        sphere((0.145 * sx, -0.3, 0.52), (0.075, 0.04, 0.085), mat("#ffe14a", 0.2, emit=4), r)
        sphere((0.145 * sx, -0.335, 0.52), (0.028, 0.015, 0.05), mat(BLACK, 0.2), r)
        sphere((0.33 * sx, 0.1, 0.0), (0.08, 0.2, 0.36), Bk, r, rot=(0, math.radians(8) * sx, 0))
    cone((0, 0.2, -0.45), 0.14, 0.0, 0.5, Bk, r, rot=(math.radians(-160), 0, 0), verts=8)
    # abanico de cartas que el cuervo mira
    cols = ["#ffe14a", "#7ee06a", "#ff7fb0", "#8ff2ff", "#ffffff"]
    for i in range(5):
        a = math.radians(-34 + i * 17)
        mini_card((0.0 + math.sin(a) * 0.42, -0.25, 0.4 + math.cos(a) * 0.1), (math.radians(-12), 0, -a), cols[i], 2.0, 1.2)
    sparkles(12, 7, "#9fb2ff", emit=12)


def s_apocalypse():
    stage("#2a0610", "#e0401a", "#240808", key="#ffd8b0", rim="#ff9a2e", fill="#ff6a3a", hills="#160406", key_power=260, rim_power=700)
    # cometa
    M = mat("#ffb020", 0.3, emit=28, emit_color="#ff7a10")
    sphere((0.8, 0.9, 1.75), 0.3, M)
    sphere((0.8, 0.86, 1.75), 0.2, mat("#fff0a0", 0.3, emit=40, emit_color="#fff0a0"))
    for i in range(7):
        t = i / 6
        sphere((0.8 + 0.7 * t, 0.95, 1.75 + 0.35 * t), 0.26 * (1 - 0.6 * t), mat("#ff6a1a", 0.4, emit=10 * (1 - t) + 2, emit_color="#ff5a10"))
    sparkles(30, 5, "#ffb020", area=(-1.4, 1.4, 0.3, 2.4), y=(0.2, 1.6), size=(0.012, 0.03), emit=25)
    c = cat(loc=(-0.45, -0.05, 0), rot=(math.radians(-6), 0, math.radians(-8)), arm_l=(-0.4, -0.45, 1.0), arm_r=(0.4, -0.45, 1.0), tail=False, **dict(ZOMBIE, eye_l="wide", eye_r="wide", mouth="open"))
    stitches(c)
    for x, s in ((0.3, 0.6), (0.82, 0.5)):
        bomb((x, -0.1 + s * -0.1, 0), s)


def s_alter_future():
    stage("#220a52", "#a24ae0", "#2a1060", rim="#ff9fff", fill="#9fd8ff", hills="#1a0838", rim_power=520)
    stars(45, 14, "#ffd6ff")
    cat(loc=(0, 0.95, 0), scale=0.85, fur="#3a2a6a", eyes="glow", eye="#8ff2ff", glow_eyes=9, mouth="smile", arm_l=(-0.5, -0.5, 0.95), arm_r=(0.5, -0.5, 0.95), tail=False)
    for x, z, col, n, ang in ((-0.6, 1.42, "#ffe14a", "1", 10), (0.0, 1.5, "#ffffff", "2", 0), (0.6, 1.42, "#7ee06a", "3", -10)):
        mini_card((x, -0.2, z), (0, 0, math.radians(ang)), col, 1.7, 2.0)
        text(n, (x, -0.225, z), 0.2, mat("#3c1273", 0.4), rot=(math.pi / 2, 0, math.radians(ang)), extrude=0.004)
    arrow(arc_pts(-0.3, 1.12, 0.26, 160, 20, -0.4, 6), "#8ff2ff", 0.03, 10, 0.1)
    arrow(list(reversed(arc_pts(0.3, 1.1, 0.26, 200, 340, -0.4, 6))), "#ff9fff", 0.03, 10, 0.1)
    sparkles(18, 2, "#ffd6ff", area=(-1.3, 1.3, 0.4, 2.3), y=(0.2, 1.2))


def s_bury():
    stage("#3a2616", "#c08a52", "#4a2f1a", key="#ffe9c8", rim="#ffc070", fill="#c08a50", hills="#2e1c10", key_power=300)
    D = mat("#5a3a20", 0.95)
    sphere((0.25, -0.2, 0.0), (0.85, 0.5, 0.32), D)
    sphere((-0.3, -0.35, 0.0), (0.3, 0.25, 0.14), D); sphere((0.95, -0.42, 0.0), (0.25, 0.22, 0.13), D)
    box((0.25, -0.45, 0.31), (0.12, 0.012, 0.17), mat("#ffe14a", 0.35, emit=1.0), rot=(math.radians(-8), 0, math.radians(10)), bevel=0.004)
    text("?", (0.25, -0.465, 0.32), 0.18, mat("#6b3a10", 0.5), rot=(math.radians(82), 0, math.radians(10)), extrude=0.004)
    # pala clavada en el montón
    tube([(0.82, -0.25, 1.35), (0.62, -0.3, 0.45)], 0.026, mat("#b9854a", 0.6))
    box((0.58, -0.32, 0.3), (0.13, 0.012, 0.17), mat("#cfd4e6", 0.25, 1.0), rot=(math.radians(8), math.radians(-10), math.radians(-14)), bevel=0.012)
    box((0.84, -0.25, 1.38), (0.07, 0.02, 0.03), mat("#b9854a", 0.6))
    cat(loc=(-0.85, 0.1, 0), rot=(0, 0, math.radians(14)), fur="#2b2342", eyes="closed", mouth="smile", arm_r=(0.45, -0.4, 0.4))
    tombstone((1.2, 1.2, 0), 1.2, -0.3, "#6a5a7a")
    sparkles(10, 6, "#ffc070", area=(-1, 1.2, 0.1, 0.9), y=(-0.5, 0.2), size=(0.01, 0.025), emit=3)


def s_soul_swap():
    stage("#0a4a54", "#38c8b8", "#0c3a42", key="#f0fffb", rim="#c8fff0", fill="#8ff2ff", hills="#08323a", rim_power=500)
    stars(25, 17, "#c8fff0")
    cat(loc=(-0.62, 0.05, 0), rot=(0, 0, math.radians(18)), scale=0.95, fur="#ff9a2e", belly="#ffd9a0", ear="#ff6f91", eyes="big", mouth="smile", arm_r=(0.4, -0.4, 0.8))
    cat(loc=(0.62, 0.05, 0.12), rot=(0, 0, math.radians(-18)), scale=0.95, eye="#ffffff", eyes="normal", fur_mat=ghost_mat(), ear="#bafff2", whiskers="#bafff2", glow_eyes=6, arm_l=(-0.4, -0.4, 0.8), tail=False)
    arrow(arc_pts(0, 1.0, 0.45, 160, 20, -0.5, 7), "#ffe14a", 0.04, 10, 0.14)
    arrow(arc_pts(0, 0.9, 0.45, 200, 340, -0.5, 7), "#ff7fb0", 0.04, 10, 0.14)
    for i in range(2):
        mini_card((-0.62 + 1.24 * (i % 2), -0.3, 1.4 + 0.1 * (i % 2)), (0, 0, math.radians(14 * (1 - 2 * (i % 2)))), ["#ffe14a", "#7ee06a"][i % 2], 1.5, 1.5)
    sparkles(14, 8, "#c8fff0")


def s_haunt():
    stage("#14123a", "#4a54b0", "#1c1c46", key="#dfe6ff", rim="#9fb2ff", fill="#7a8ad8", hills="#0e0e2c", key_power=230, rim_power=520)
    moon((1.3, 6, 2.5), 0.65); stars(25, 19)
    G = ghost_mat()
    c = cat(loc=(0.15, 0.7, 0.1), scale=1.2, eye="#ffffff", eyes="normal", mouth="open", fur_mat=G, ear="#d8e4ff", whiskers="#d8e4ff", glow_eyes=8, arm_l=(-0.55, -0.4, 1.0), arm_r=(0.55, -0.4, 1.0), tail=False)
    # cola de fantasma ondulada
    cat(loc=(-0.65, -0.35, 0), rot=(0, 0, math.radians(10)), scale=0.75, fur="#ff9a2e", belly="#ffd9a0", ear="#ff6f91", eyes="wide", mouth="open", arm_l=(-0.35, -0.3, 0.85), arm_r=(0.35, -0.3, 0.85))
    for x, z, a, col in ((0.95, 1.25, 25, "#ffe14a"), (1.0, 0.7, 50, "#7ee06a")):
        mini_card((x, -0.35, z), (math.radians(10), 0, math.radians(a)), col, 1.4, 1.5)
    sparkles(18, 9, "#c8d4ff")


def s_rotten():
    stage("#1c2a08", "#7fa81a", "#1c2a0c", key="#f2ffd0", rim="#c8ff5a", fill="#8ab040", hills="#142008", key_power=240, rim_power=620)
    rotten = dict(fur="#6f8f1a", belly="#a8b83a", ear="#8a4a2a", eye="#e8ff6b", eye_l="x", mouth="open", whiskers=None, fur_rough=0.7)
    c = cat(loc=(-0.3, 0.05, 0), rot=(0, 0, math.radians(-6)), **rotten)
    Sp = mat("#4a6012", 0.8)
    rnd = random.Random(7)
    for i in range(14):
        a = math.radians(-20 + i * 15)
        d = Vector((math.cos(a), rnd.uniform(-0.2, 0.2), math.sin(a)))
        cone(Vector((0, 0, 0.84)) + d * 0.33, 0.07, 0.0, 0.2, Sp, c, direction=d)
    stitches(c, mat("#1a2606", 0.6))
    # bomba podrida
    r = empty((0.62, -0.3, 0), scale=1.0)
    sphere((0, 0, 0.3), 0.3, mat("#5a7a10", 0.6, coat=0.4), r)
    sphere((0.1, -0.2, 0.42), (0.1, 0.06, 0.08), mat("#2a3a08", 0.9), r)
    cone((0, 0, 0.62), 0.07, 0.07, 0.08, mat("#4a4458", 0.4, 0.8), r)
    tube([(0, 0, 0.64), (0.05, 0, 0.74), (0.12, -0.02, 0.72), (0.14, -0.03, 0.64)], 0.014, mat("#8a7a4a", 0.8), r)
    sphere((0.14, -0.03, 0.6), 0.04, mat("#c8ff5a", 0.3, emit=20, emit_color="#a0ff30"), r)
    tube([(-0.2, -0.22, 0.45), (-0.22, -0.26, 0.2), (-0.2, -0.28, 0.02)], 0.03, mat("#8aff2a", 0.2, emit=2), r)
    B = mat("#b6ff3a", 0.15, emit=3, trans=0.5)
    for i in range(14):
        sphere((rnd.uniform(-1.3, 1.3), rnd.uniform(-0.3, 1.2), rnd.uniform(0.2, 2.0)), rnd.uniform(0.02, 0.07), B)
    sphere((-1.0, -0.2, 1.5), 0.03, mat("#0a0a0a", 0.4)); sphere((0.9, 0.2, 1.8), 0.03, mat("#0a0a0a", 0.4))



SCENES = {
    "zombie": s_zombie, "exploding": s_exploding, "attack": s_attack, "attack_dead": s_attack_dead, "nope": s_nope,
    "skip": s_skip, "super_skip": s_super_skip, "see_future": s_see_future, "shuffle": s_shuffle, "feed_dead": s_feed_dead,
    "clone": s_clone, "grave_robber": s_grave_robber, "favor": s_favor, "dig_deeper": s_dig_deeper,
    "clairvoyance": s_clairvoyance, "cat_a": s_cat_a, "cat_b": s_cat_b, "cat_c": s_cat_c, "cat_d": s_cat_d,
    "targeted_attack": s_targeted_attack, "reverse": s_reverse, "draw_bottom": s_draw_bottom, "crow_eye": s_crow_eye,
    "apocalypse": s_apocalypse, "alter_future": s_alter_future, "bury": s_bury, "soul_swap": s_soul_swap,
    "haunt": s_haunt, "rotten": s_rotten,
}
# Avatares de los jugadores: busto de gato sobre fondo transparente (godot/assets/avatars/cat_N.png)
AVATARS = [
    dict(fur="#3a2a6a", ear="#ff86b3", eye="#ffe14a"),
    dict(fur="#ff8a3d", belly="#ffd0a8", ear="#ffb0c8", eye="#7ee06a"),
    dict(fur="#f1e6d2", belly="#ffffff", ear="#ff9fbf", eye="#49c2e6", whiskers="#8a7a7a"),
    dict(fur="#8d8fa8", belly="#c8cade", ear="#ffd0e0", eye="#ffe14a"),
    dict(fur="#2a2230", ear="#e11d2e", eye="#ff4d5e", mouth="fangs"),
    dict(fur="#b06a3a", belly="#e0a878", ear="#ffc9a0", eye="#9be22d"),
]


def render_avatars():
    out = os.path.join(ROOT, "godot", "assets", "avatars")
    os.makedirs(out, exist_ok=True)
    for i, look in enumerate(AVATARS):
        stage("#000000", "#000000", "#000000", rim="#b6f23a", key_power=120, rim_power=160, bare=True)
        sc = bpy.context.scene
        sc.render.film_transparent = True
        sc.render.resolution_x = sc.render.resolution_y = 512
        sc.camera.data.lens = 60
        sc.camera.data.dof.use_dof = False
        sc.camera.location = (0, -2.9, 0.86)
        sc.camera.rotation_euler = (Vector((0, 0, 0.74)) - Vector(sc.camera.location)).to_track_quat("-Z", "Y").to_euler()
        cat(tail=False, **look)
        sc.render.filepath = os.path.join(out, "cat_%d.png" % i)
        bpy.ops.render.render(write_still=True)
        print("AVATAR", i)


if "--avatars" in argv:
    render_avatars()
    sys.exit(0)

for name, fn in SCENES.items():
    if ONLY and name not in ONLY:
        continue
    try:
        fn()
        render(name)
    except Exception:
        import traceback
        print("FALLO", name)
        traceback.print_exc()
