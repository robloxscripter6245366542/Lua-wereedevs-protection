"""
Steal an Egg — procedural low-poly model generator for Blender (tested on 4.0).

Builds every egg and pet from Config.lua as a single textured mesh (palette-texture
technique: each colour is a cell in a small PNG), then exports .fbx + .glb for the
Roblox 3D Importer and renders a preview PNG of each.

Usage:
    blender -b -P make_models.py -- <out_dir> [--only NAME ...] [--no-render]
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "out")
ONLY = []
if "--only" in argv:
    ONLY = [a for a in argv[argv.index("--only") + 1:] if not a.startswith("--")]
RENDER = "--no-render" not in argv


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


BLACK = hexc("1a1a1f")
WHITE = hexc("ffffff")
PINK = hexc("ff8fb0")
GOLD = hexc("ffcc33")
ORANGE = hexc("ff9a2e")

# ---------------------------------------------------------------- scene helpers
PARTS = []


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PARTS.clear()
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def colour_mat(rgb):
    key = "C_%02x%02x%02x" % tuple(int(round(c * 255)) for c in rgb)
    m = bpy.data.materials.get(key)
    if not m:
        m = bpy.data.materials.new(key)
        m["rgb"] = list(rgb)
    return m


def part(kind, loc, scale=(1, 1, 1), rot=(0, 0, 0), color=WHITE, seg=14, smooth=True):
    loc = tuple(loc)
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(6, seg // 2), location=loc)
    elif kind == "ico":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=loc)
        smooth = False
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=max(4, seg // 2), radius1=1, radius2=0, depth=2, location=loc)
        smooth = False
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=max(6, seg // 2), radius=1, depth=2, location=loc)
    elif kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
        smooth = False
    else:
        raise ValueError(kind)
    o = bpy.context.active_object
    o.scale = scale
    o.rotation_euler = tuple(math.radians(r) for r in rot)
    o.data.materials.append(colour_mat(color))
    if smooth:
        bpy.ops.object.shade_smooth()
    PARTS.append(o)
    return o


def pair(kind, x, y, z, scale, rot=(0, 0, 0), color=WHITE, **kw):
    """Mirrored pair across X. rot Y/Z are mirrored."""
    out = []
    for s in (-1, 1):
        out.append(part(kind, (s * x, y, z), scale, (rot[0], rot[1] * s, rot[2] * s), color, **kw))
    return out


def eyes(hx, hy, hz, spread=0.32, size=0.15, color=BLACK, forward=0.72):
    for s in (-1, 1):
        part("sphere", (s * spread, hy + forward, hz + 0.12), (size * 0.85, size * 0.55, size * 1.15), color=color, seg=10)
        part("sphere", (s * spread + 0.04 * s, hy + forward + 0.07, hz + 0.2), (0.045, 0.03, 0.045), color=WHITE, seg=6)


def lighten(c, t):
    return tuple(a + (1 - a) * t for a in c)


def darken(c, t):
    return tuple(a * (1 - t) for a in c)


# ---------------------------------------------------------------- finishing / export
CELLS = 8  # 8x8 palette grid
CELL_PX = 8


def finish(name, folder):
    bpy.ops.object.select_all(action="DESELECT")
    for o in PARTS:
        o.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    mesh = obj.data
    mesh.name = name

    # Origin at bottom centre, sitting on the ground.
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    offset = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
    for v in mesh.vertices:
        v.co -= offset

    # Palette texture: one cell per colour, every face's UVs point at its colour cell.
    colours = [tuple(m["rgb"]) for m in mesh.materials]
    if len(colours) > CELLS * CELLS:
        raise RuntimeError(f"{name}: too many colours ({len(colours)})")
    size = CELLS * CELL_PX
    image = bpy.data.images.new(name + "_tex", size, size, alpha=False)
    pixels = [0.0] * (size * size * 4)
    for idx, rgb in enumerate(colours):
        cx, cy = idx % CELLS, idx // CELLS
        for py in range(cy * CELL_PX, (cy + 1) * CELL_PX):
            for px in range(cx * CELL_PX, (cx + 1) * CELL_PX):
                i = (py * size + px) * 4
                pixels[i:i + 4] = [rgb[0], rgb[1], rgb[2], 1.0]
    image.pixels = pixels
    tex_path = os.path.join(folder, name + "_tex.png")
    image.filepath_raw = tex_path
    image.file_format = "PNG"
    image.save()

    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        idx = poly.material_index
        u = ((idx % CELLS) + 0.5) / CELLS
        v = ((idx // CELLS) + 0.5) / CELLS
        for li in poly.loop_indices:
            uv.data[li].uv = (u, v)
        poly.material_index = 0

    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.55
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mesh.materials.clear()
    mesh.materials.append(mat)

    # Roblox limit is 20k tris per MeshPart; we stay far below.
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    assert tris < 20000, f"{name} has {tris} tris"

    base = os.path.join(folder, name)
    obj.select_set(True)
    bpy.ops.export_scene.fbx(filepath=base + ".fbx", use_selection=True, path_mode="COPY",
                             embed_textures=True, apply_unit_scale=True, axis_forward="-Z", axis_up="Y")
    bpy.ops.export_scene.gltf(filepath=base + ".glb", use_selection=True, export_format="GLB")
    if RENDER:
        render(obj, base + "_preview.png")
    return tris


def render(obj, path):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = scene.render.resolution_y = 320
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.75, 0.95, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    scene.world = world

    dims = obj.dimensions
    height = dims.z
    radius = max(dims.x, dims.y, dims.z)
    target = Vector((0, 0, height * 0.45))
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    direction = Vector((0.75, 1.0, 0.55)).normalized()  # front three-quarter view (models face +Y)
    cam.location = target + direction * radius * 2.6
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(140))
    scene.collection.objects.link(sun)

    bpy.ops.mesh.primitive_plane_add(size=radius * 12, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.6, 0.3, 1)
    ground.data.materials.append(gm)

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------- eggs
def egg_shape(color_fn, height=4.0, seg=20, extras=None):
    """Egg built from a UV sphere tapered at the top; faces coloured by color_fn(center, index)."""
    r = height / 2
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2 + 2, location=(0, 0, 0))
    o = bpy.context.active_object
    mesh = o.data
    for v in mesh.vertices:
        z = v.co.z  # -1..1
        taper = 1 - 0.22 * max(0.0, z) - 0.05 * max(0.0, -z)
        v.co.x *= 0.76 * r * taper
        v.co.y *= 0.76 * r * taper
        v.co.z = z * r + r
    cache = {}
    for i, poly in enumerate(mesh.polygons):
        rgb = color_fn(poly.center, i)
        if rgb not in cache:
            mesh.materials.append(colour_mat(rgb))
            cache[rgb] = len(mesh.materials) - 1
        poly.material_index = cache[rgb]
    bpy.ops.object.shade_smooth()
    PARTS.append(o)
    if extras:
        extras(r)
    return o


def surface_point(r, theta, h):
    """Point on the egg surface at angle theta and height fraction h (0 bottom .. 1 top)."""
    z = (h * 2 - 1)
    ring = math.sqrt(max(0.0, 1 - z * z)) * 0.76 * r * (1 - 0.22 * max(0.0, z) - 0.05 * max(0.0, -z))
    return Vector((math.cos(theta) * ring, math.sin(theta) * ring, z * r + r)), Vector((math.cos(theta), math.sin(theta), 0))


def speckle(base, spot, chance, seed):
    rng = random.Random(seed)

    def fn(c, i):
        return spot if rng.random() < chance else base
    return fn


def bands(colors):
    def fn(c, i):
        idx = min(len(colors) - 1, int(c.z / 4.0 * len(colors)))
        return colors[idx]
    return fn


def make_eggs(folder):
    eggs = {}

    def dirt():
        egg_shape(speckle(hexc("8a5a3b"), hexc("5c3a24"), 0.25, 1))
    eggs["Dirt"] = dirt

    def grass():
        def fn(c, i):
            return hexc("5cc24a") if c.z < 2.6 else hexc("8fe06a")

        def extras(r):
            rng = random.Random(2)
            for k in range(14):
                th = k / 14 * math.tau
                p, n = surface_point(r, th, 0.62)
                part("cone", p + n * 0.15, (0.12, 0.12, 0.45 + rng.random() * 0.3), (rng.uniform(-15, 15), rng.uniform(-15, 15), 0), hexc("3fa83a"))
        egg_shape(fn, extras=extras)
    eggs["Grass"] = grass

    def spotted():
        rng = random.Random(3)

        def fn(c, i):
            return hexc("8b5a2b") if rng.random() < 0.18 else hexc("f4ead2")
        egg_shape(fn)
    eggs["Spotted"] = spotted

    def ice():
        def fn(c, i):
            return hexc("bfe8ff") if c.z > 1.2 else hexc("8fd3ff")

        def extras(r):
            for k in range(7):
                th = k / 7 * math.tau
                p, n = surface_point(r, th, 0.15)
                part("cone", p + n * 0.3 + Vector((0, 0, 0.5)), (0.3, 0.3, 0.9),
                     (math.degrees(-n.y * 0.4), math.degrees(n.x * 0.4), 0), hexc("e6f7ff"))
        egg_shape(fn, extras=extras)
    eggs["Ice"] = ice

    def lava():
        def fn(c, i):
            crack = abs(math.sin(c.z * 3.1 + math.atan2(c.y, c.x) * 2)) < 0.22
            return hexc("ff7a1a") if crack else hexc("3a2622")
        egg_shape(fn, seg=24)
    eggs["Lava"] = lava

    def crystal():
        def extras(r):
            rng = random.Random(6)
            for k in range(9):
                th = rng.random() * math.tau
                h = rng.uniform(0.25, 0.85)
                p, n = surface_point(r, th, h)
                tilt = Vector((n.x, n.y, 0.6)).normalized()
                rot = tilt.to_track_quat("Z", "Y").to_euler()
                part("cone", p + tilt * 0.4, (0.25, 0.25, 0.7), tuple(math.degrees(a) for a in rot), hexc("e2b8ff"))
        egg_shape(lambda c, i: hexc("b06cff") if (i % 3) else hexc("9150e0"), extras=extras)
    eggs["Crystal"] = crystal

    def golden():
        def fn(c, i):
            if 1.7 < c.z < 2.2:
                return hexc("d94141")
            return GOLD if i % 2 else hexc("f0b820")

        def extras(r):
            for k in range(6):
                th = k / 6 * math.tau
                p, n = surface_point(r, th, 0.49)
                part("sphere", p + n * 0.08, (0.22, 0.22, 0.22), color=hexc("4fc3ff") if k % 2 else hexc("7dff8a"), seg=8)
        egg_shape(fn, extras=extras)
    eggs["Golden"] = golden

    def cosmic():
        rng = random.Random(8)

        def fn(c, i):
            roll = rng.random()
            if roll < 0.06:
                return WHITE
            return hexc("2b1f6e") if roll < 0.6 else hexc("3d2a90")

        def extras(r):
            for k in range(3):
                th = k / 3 * math.tau + 0.4
                p = Vector((math.cos(th) * r * 1.15, math.sin(th) * r * 1.15, r * (0.6 + k * 0.35)))
                part("ico", p, (0.25, 0.25, 0.25), color=hexc("ffe680"))
            part("cyl", (0, 0, r * 1.05), (r * 1.15, r * 1.15, 0.06), (12, 0, 0), hexc("9f8cff"), seg=32)
        egg_shape(fn, extras=extras)
    eggs["Cosmic"] = cosmic

    def rainbow():
        egg_shape(bands([hexc(h) for h in ("ff4d4d", "ff9a3d", "ffe14d", "5ce05c", "4db8ff", "8a5cff", "ff6ad5")]), seg=24)
    eggs["Rainbow"] = rainbow

    def void():
        def fn(c, i):
            crack = abs(math.sin(c.z * 4 + math.atan2(c.y, c.x) * 3)) < 0.12
            return hexc("b14dff") if crack else hexc("120b1c")

        def extras(r):
            # One big glowing eye staring out the front (+Y)
            p, n = surface_point(r, math.pi / 2, 0.55)
            part("sphere", p + n * 0.02, (0.75, 0.25, 0.55), color=hexc("f2e6ff"), seg=12)
            part("sphere", p + n * 0.2, (0.22, 0.12, 0.42), color=hexc("b14dff"), seg=10)
            for k in range(5):
                th = k / 5 * math.tau
                part("cone", (math.cos(th) * 0.45, math.sin(th) * 0.45, r * 2.05), (0.15, 0.15, 0.45),
                     (math.degrees(-math.sin(th) * 0.3), math.degrees(math.cos(th) * 0.3), 0), hexc("2a1840"))
        egg_shape(fn, seg=24, extras=extras)
    eggs["Void"] = void
    return eggs


# ---------------------------------------------------------------- pet archetypes (face +Y)
def quadruped(main, second, accent=GOLD, ears="cat", tail="thin", neck=0.0, horn=False, horns=False,
              wings=False, wing_color=None, mane=None, spots=None, legs=0.45, snout=True, flames=False,
              crystals=None, stars=False, spikes=None, eye=BLACK, body_scale=(1.0, 1.35, 0.95)):
    bz = 0.95 + legs
    part("sphere", (0, 0, bz), body_scale, color=main, seg=16)
    part("sphere", (0, 0.35, bz - 0.25), (body_scale[0] * 0.8, body_scale[1] * 0.75, body_scale[2] * 0.7), color=second, seg=12)
    hy, hz = 1.3 + neck * 0.35, bz + 0.85 + neck
    if neck > 0:
        mid = Vector((0, (1.0 + hy) / 2, (bz + 0.4 + hz) / 2))
        length = Vector((0, hy - 1.0, hz - bz - 0.4)).length
        part("cyl", mid, (0.32, 0.32, length / 2), (-math.degrees(math.atan2(hy - 1.0, hz - bz - 0.4)), 0, 0), main, seg=12)
    part("sphere", (0, hy, hz), (0.82, 0.78, 0.76), color=main, seg=16)
    eyes(0, hy, hz, color=eye)
    if snout:
        part("sphere", (0, hy + 0.62, hz - 0.22), (0.38, 0.3, 0.26), color=second, seg=10)
        part("sphere", (0, hy + 0.9, hz - 0.12), (0.1, 0.07, 0.08), color=BLACK, seg=8)
    # legs + paws
    for sx in (-1, 1):
        for sy in (-1, 1):
            part("cyl", (sx * 0.55, sy * 0.72, legs / 2 + 0.2), (0.24, 0.24, legs / 2 + 0.2), color=main, seg=10)
            part("sphere", (sx * 0.55, sy * 0.72 + 0.08, 0.16), (0.3, 0.34, 0.18), color=second, seg=10)
    # ears
    ez = hz + 0.62
    if ears == "cat":
        pair("cone", 0.42, hy - 0.05, ez, (0.24, 0.16, 0.32), (0, 18, 0), main)
        pair("cone", 0.42, hy + 0.02, ez - 0.04, (0.13, 0.08, 0.2), (0, 18, 0), PINK)
    elif ears == "pointy":
        pair("cone", 0.42, hy - 0.05, ez + 0.1, (0.3, 0.18, 0.45), (0, 20, 0), main)
        pair("cone", 0.42, hy + 0.03, ez + 0.05, (0.16, 0.08, 0.28), (0, 20, 0), second)
    elif ears == "long":
        pair("sphere", 0.28, hy - 0.1, ez + 0.6, (0.17, 0.1, 0.72), (0, 10, 0), main, seg=10)
        pair("sphere", 0.28, hy - 0.03, ez + 0.6, (0.09, 0.06, 0.55), (0, 10, 0), PINK, seg=8)
    elif ears == "round":
        pair("sphere", 0.55, hy - 0.1, ez - 0.05, (0.26, 0.1, 0.24), (0, 0, 0), second, seg=10)
    elif ears == "floppy":
        pair("sphere", 0.72, hy - 0.05, hz + 0.05, (0.15, 0.25, 0.48), (0, -20, 0), second, seg=10)
    # tail
    if tail == "thin":
        part("cyl", (0, -1.45, bz + 0.4), (0.1, 0.1, 0.55), (-45, 0, 0), main, seg=8)
    elif tail == "fluffy":
        part("sphere", (0, -1.5, bz + 0.45), (0.38, 0.75, 0.38), (-50, 0, 0), main, seg=12)
        part("sphere", (0, -2.0, bz + 0.95), (0.25, 0.3, 0.25), (-50, 0, 0), WHITE, seg=10)
    elif tail == "puff":
        part("sphere", (0, -1.35, bz + 0.15), (0.3, 0.3, 0.3), color=WHITE, seg=10)
    elif tail == "long":
        part("cone", (0, -1.95, bz - 0.1), (0.3, 0.3, 0.95), (-100, 0, 0), main)
    elif tail == "tuft":
        part("cyl", (0, -1.45, bz + 0.3), (0.08, 0.08, 0.5), (-40, 0, 0), main, seg=8)
        part("sphere", (0, -1.8, bz + 0.7), (0.2, 0.2, 0.25), color=second, seg=8)
    # extras
    if horn:
        part("cone", (0, hy + 0.3, hz + 0.95), (0.13, 0.13, 0.5), (20, 0, 0), accent)
    if horns:
        pair("cone", 0.35, hy - 0.3, hz + 0.75, (0.12, 0.12, 0.42), (-30, 15, 0), accent)
    if wings:
        wc = wing_color or lighten(main, 0.5)
        pair("sphere", 1.15, -0.1, bz + 0.75, (1.05, 0.55, 0.08), (0, -30, 0), wc, seg=12)
        pair("sphere", 1.6, -0.35, bz + 1.0, (0.6, 0.35, 0.07), (0, -35, 0), lighten(wc, 0.3), seg=10)
    if mane:
        cols = mane if isinstance(mane, list) else [mane]
        for k in range(11):
            a = k / 11 * math.tau
            part("sphere", (math.cos(a) * 0.75, hy - 0.2, hz + math.sin(a) * 0.72), (0.34, 0.3, 0.34),
                 color=cols[k % len(cols)], seg=10)
    if spots:
        rng = random.Random(len(str(main)))
        for _ in range(7):
            a = rng.uniform(0, math.tau)
            y = rng.uniform(-0.9, 0.9)
            p = Vector((math.cos(a) * body_scale[0] * 0.97, y, bz + math.sin(a) * body_scale[2] * 0.97))
            if p.z > bz - 0.4:
                part("sphere", p, (0.22, 0.22, 0.22), color=spots, seg=8)
    if flames:
        for k, y in enumerate((-0.6, 0.0, 0.6)):
            part("cone", (0, y, bz + body_scale[2] + 0.2), (0.25, 0.25, 0.45 + 0.1 * k), (0, 0, 0), ORANGE)
            part("cone", (0, y, bz + body_scale[2] + 0.1), (0.15, 0.15, 0.3), (0, 0, 0), GOLD)
    if crystals:
        for k, y in enumerate((-0.7, -0.1, 0.5)):
            part("cone", (0.15 * (-1) ** k, y, bz + body_scale[2] + 0.1), (0.22, 0.22, 0.5 + 0.12 * k), ((-1) ** k * 15, 0, 0), crystals)
    if spikes:
        for k in range(5):
            part("cone", (0, -1.0 + k * 0.45, bz + body_scale[2] - 0.05), (0.14, 0.2, 0.3), (0, 0, 0), spikes)
    if stars:
        for k in range(6):
            a = k / 6 * math.tau
            part("ico", (math.cos(a) * 1.5, math.sin(a) * 1.5, bz + 1.4 + 0.2 * math.sin(a * 3)), (0.14, 0.14, 0.14), color=hexc("fff08a"))


def worm(main, second):
    for k in range(5):
        a = k * 0.7
        part("sphere", (0, 1.2 - k * 0.6, 0.5 + 0.25 * math.sin(a)), (0.55 - k * 0.04,) * 3, color=main if k % 2 else second, seg=12)
    part("sphere", (0, 1.6, 1.15), (0.6, 0.6, 0.6), color=main, seg=14)
    eyes(0, 1.6, 1.25, spread=0.22, size=0.13, forward=0.5)
    part("sphere", (0, 2.15, 1.0), (0.18, 0.06, 0.08), color=PINK, seg=8)


def slime(main, second):
    part("sphere", (0, 0, 1.0), (1.4, 1.4, 1.0), color=main, seg=18)
    part("sphere", (0, 0, 1.75), (0.6, 0.6, 0.4), color=lighten(main, 0.35), seg=12)
    part("sphere", (0.55, 0.75, 1.65), (0.25, 0.15, 0.18), color=lighten(main, 0.7), seg=8)
    eyes(0, 0.55, 1.15, spread=0.42, size=0.2, forward=0.75)
    part("sphere", (0, 1.38, 0.85), (0.25, 0.05, 0.12), color=darken(main, 0.6), seg=8)


def mole(main, second):
    part("sphere", (0, 0, 1.0), (1.05, 1.3, 1.0), color=main, seg=16)
    part("sphere", (0, 1.15, 1.0), (0.42, 0.45, 0.35), color=PINK, seg=12)
    part("sphere", (0, 1.58, 1.05), (0.16, 0.08, 0.13), color=hexc("d04a7a"), seg=8)
    pair("sphere", 0.3, 0.95, 1.45, (0.08, 0.05, 0.08), color=BLACK, seg=6)
    for s in (-1, 1):
        part("sphere", (s * 0.85, 0.8, 0.45), (0.38, 0.32, 0.12), (0, 0, s * 20), PINK, seg=10)
        for c in (-1, 0, 1):
            part("cone", (s * 0.95 + c * 0.12 * s, 1.1, 0.42), (0.06, 0.06, 0.15), (-90, 0, 0), WHITE)
    part("cube", (0, 0.2, 2.08), (0.6, 0.6, 0.1), color=hexc("ffd23f"))  # hard hat
    part("sphere", (0, 0.15, 1.95), (0.7, 0.75, 0.35), color=hexc("ffd23f"), seg=12)


def bird(main, second, beak=ORANGE, wings=0.6, crest=None, tail_feathers=None, belly=WHITE, flames=False, scale_wings=1.0):
    part("sphere", (0, 0, 1.4), (0.95, 0.9, 1.25), color=main, seg=16)
    part("sphere", (0, 0.38, 1.25), (0.7, 0.6, 0.95), color=belly, seg=14)
    part("sphere", (0, 0.1, 2.75), (0.75, 0.72, 0.7), color=main, seg=14)
    eyes(0, 0.1, 2.75, spread=0.3, size=0.13, forward=0.65)
    part("cone", (0, 0.95, 2.6), (0.16, 0.16, 0.28), (-90, 0, 0), beak)
    pair("sphere", 0.45, 0.35, 0.12, (0.3, 0.42, 0.12), color=beak, seg=10)
    pair("sphere", 0.95, -0.05, 1.55, (0.22, 0.55 * scale_wings, wings * scale_wings), (10, -15, 0), second, seg=12)
    if scale_wings > 1.2:
        pair("sphere", 1.45, -0.35, 2.35, (1.15, 0.55, 0.09), (0, -28, 0), lighten(second, 0.25), seg=12)
        pair("sphere", 2.2, -0.5, 2.85, (0.6, 0.35, 0.07), (0, -35, 0), lighten(second, 0.5), seg=10)
    if crest:
        for k, c in enumerate(crest):
            part("cone", (0, -0.1 - 0.15 * k, 3.45 + 0.05 * k), (0.12, 0.12, 0.35), (-20 - 15 * k, 0, 0), c)
    if tail_feathers:
        for k, c in enumerate(tail_feathers):
            ang = (k - (len(tail_feathers) - 1) / 2) * 18
            part("sphere", (math.sin(math.radians(ang)) * 0.6, -1.3, 0.9), (0.18, 0.8, 0.12), (-30, 0, ang), c, seg=10)
    if flames:
        for k in range(3):
            part("cone", ((k - 1) * 0.3, -0.25, 3.55), (0.18, 0.18, 0.4), (-15, (k - 1) * 20, 0), ORANGE)


def biped(main, second, accent=GOLD, horns=False, crystals=None, fur=False, face=None, eye=BLACK):
    part("sphere", (0, 0, 1.9), (1.15, 0.95, 1.25), color=main, seg=16)
    part("sphere", (0, 0.4, 1.7), (0.8, 0.6, 0.85), color=second, seg=12)
    part("sphere", (0, 0.1, 3.4), (0.8, 0.75, 0.72), color=main, seg=14)
    part("sphere", (0, 0.55, 3.3), (0.55, 0.35, 0.45), color=face or second, seg=12)
    eyes(0, 0.1, 3.5, spread=0.28, size=0.13, forward=0.68, color=eye)
    pair("sphere", 1.25, 0.1, 2.0, (0.35, 0.35, 0.85), (0, -15, 0), main, seg=12)
    pair("sphere", 1.45, 0.25, 1.15, (0.32, 0.32, 0.3), color=second, seg=10)
    pair("cyl", 0.5, 0, 0.45, (0.38, 0.38, 0.45), color=main, seg=12)
    pair("sphere", 0.5, 0.15, 0.12, (0.42, 0.5, 0.18), color=second, seg=10)
    if horns:
        pair("cone", 0.55, 0.0, 4.05, (0.14, 0.14, 0.4), (0, 25, 0), accent)
    if fur:
        for k in range(8):
            a = k / 8 * math.tau
            part("cone", (math.cos(a) * 0.95, math.sin(a) * 0.8, 2.85), (0.2, 0.2, 0.3), (0, 180, 0), main)
    if crystals:
        for k, (x, z) in enumerate(((-0.6, 2.9), (0.5, 3.0), (0.0, 3.05), (-0.9, 2.3), (0.9, 2.4))):
            part("cone", (x, -0.4, z), (0.2, 0.2, 0.55), (-25, x * 25, 0), crystals)


def bat(main, second, accent):
    part("sphere", (0, 0, 2.2), (0.75, 0.7, 0.8), color=main, seg=14)
    part("sphere", (0, 0.1, 3.0), (0.6, 0.55, 0.55), color=main, seg=14)
    eyes(0, 0.1, 3.0, spread=0.22, size=0.12, forward=0.5, color=hexc("ff4dd2"))
    pair("cone", 0.35, 0.05, 3.6, (0.2, 0.12, 0.35), (0, 15, 0), main)
    for s in (-1, 1):
        part("sphere", (s * 1.3, -0.1, 2.5), (1.0, 0.1, 0.7), (0, s * -15, 0), second, seg=12)
        part("cone", (s * 2.0, -0.1, 2.0), (0.12, 0.12, 0.3), (0, 180, 0), second)
    for k in range(3):
        part("cone", ((k - 1) * 0.3, -0.5, 2.6 + 0.2 * (k == 1)), (0.15, 0.15, 0.4), (-30, (k - 1) * 20, 0), accent)
    pair("cyl", 0.25, 0, 1.2, (0.1, 0.1, 0.35), color=darken(main, 0.3), seg=6)
    pair("cone", 0.25, 0.1, 0.8, (0.12, 0.12, 0.12), (180, 0, 0), darken(main, 0.3))


def whale(main, second):
    part("sphere", (0, 0, 1.4), (1.4, 2.4, 1.3), color=main, seg=18)
    part("sphere", (0, 0.4, 0.95), (1.1, 1.8, 0.85), color=second, seg=14)
    eyes(0, 1.2, 1.35, spread=0.95, size=0.15, forward=0.7)
    part("sphere", (0, -2.5, 1.7), (0.3, 0.6, 0.3), (-30, 0, 0), main, seg=10)
    pair("sphere", 0.7, -3.0, 2.2, (0.75, 0.35, 0.08), (0, -15, -15), main, seg=12)
    pair("sphere", 1.4, 0.6, 0.9, (0.6, 0.3, 0.08), (0, 30, -20), second, seg=10)
    for k in range(7):
        a = k / 7 * math.tau
        part("ico", (math.cos(a) * 1.8, math.sin(a) * 2.6, 2.6 + 0.3 * math.sin(a * 2)), (0.16, 0.16, 0.16), color=hexc("fff08a"))
    part("cyl", (0, 0.4, 2.9), (0.08, 0.08, 0.3), color=hexc("aee9ff"), seg=6)
    part("sphere", (0, 0.4, 3.25), (0.35, 0.35, 0.15), color=hexc("aee9ff"), seg=10)


def serpent(main, second, accent):
    n = 9
    for k in range(n):
        t = k / (n - 1)
        x = math.sin(t * math.pi * 1.5) * 0.9
        y = -1.8 + t * 2.6
        z = 0.55 + t * t * 2.8
        r = 0.65 - t * 0.2
        part("sphere", (x, y, z), (r, r, r), color=main if k % 2 else second, seg=12)
    hx, hy, hz = math.sin(1.5 * math.pi) * 0.9, 0.95, 3.6
    part("sphere", (hx, hy, hz), (0.65, 0.85, 0.55), color=main, seg=14)
    eyes(hx, hy, hz, spread=0.3, size=0.14, forward=0.75, color=hexc("d68bff"))
    pair("cone", 0.35, hy - 0.4, hz + 0.6, (0.13, 0.13, 0.5), (-35, 15, 0), accent)
    for k in range(4):
        part("cone", (math.sin(k / 3 * math.pi * 1.5) * 0.9, -1.6 + k * 0.8, 1.1 + k * 0.6), (0.1, 0.15, 0.3), color=accent)


def egg_king():
    egg_shape(lambda c, i: hexc("fff1c9") if c.z < 3.2 else hexc("f7e3a8"), height=4.6)
    eyes(0, 1.05, 2.6, spread=0.45, size=0.2, forward=0.6)
    part("sphere", (0, 1.65, 2.05), (0.35, 0.05, 0.12), color=hexc("c94f4f"), seg=8)
    part("cyl", (0, 0, 4.5), (0.95, 0.95, 0.3), color=GOLD, seg=20)
    for k in range(6):
        a = k / 6 * math.tau
        part("cone", (math.cos(a) * 0.85, math.sin(a) * 0.85, 5.05), (0.2, 0.2, 0.35), color=GOLD)
        part("sphere", (math.cos(a) * 0.95, math.sin(a) * 0.95, 4.5), (0.12, 0.12, 0.12), color=hexc("e0344b") if k % 2 else hexc("3a9bff"), seg=6)
    part("sphere", (0, -0.6, 2.2), (1.8, 0.4, 2.0), (0, 0, 0), hexc("b01f3a"), seg=14)  # cape
    pair("sphere", 1.55, 0.3, 2.2, (0.22, 0.22, 0.6), (0, -40, 0), hexc("fff1c9"), seg=10)
    part("cyl", (1.95, 0.5, 2.5), (0.07, 0.07, 1.2), color=GOLD, seg=8)  # sceptre
    part("ico", (1.95, 0.5, 3.8), (0.25, 0.25, 0.25), color=hexc("b14dff"))


# ---------------------------------------------------------------- pet table (names match Config.lua)
R = hexc
PETS = {
    # Dirt Egg
    "Worm": lambda: worm(R("ff9db0"), R("f28aa0")),
    "Slime": lambda: slime(R("7be85c"), R("5cc24a")),
    "Mole": lambda: mole(R("6b4a3a"), R("8a5f4a")),
    # Grass Egg
    "Bunny": lambda: quadruped(R("f2f2f2"), R("ffe3ea"), ears="long", tail="puff", legs=0.3, snout=False),
    "Fox": lambda: quadruped(R("ff8a2e"), R("fff3e6"), ears="pointy", tail="fluffy"),
    "Cat": lambda: quadruped(R("ffb14d"), R("fff0d9"), ears="cat", tail="thin", spots=R("e08a2a")),
    # Spotted Egg
    "Cow": lambda: quadruped(R("ffffff"), R("ffc2d1"), ears="round", tail="tuft", horns=True, accent=R("f2e3c6"), spots=R("2a2a2a")),
    "Dalmatian": lambda: quadruped(R("ffffff"), R("f0f0f0"), ears="floppy", tail="thin", spots=R("1f1f1f")),
    "Giraffe": lambda: quadruped(R("ffcc4d"), R("fff0c2"), ears="round", tail="tuft", neck=1.6, legs=0.9, horns=True,
                                 accent=R("8b5a2b"), spots=R("b5651d")),
    # Ice Egg
    "Penguin": lambda: bird(R("2b3440"), R("2b3440"), belly=WHITE, wings=0.7),
    "Arctic Fox": lambda: quadruped(R("f4fbff"), R("dff2ff"), ears="pointy", tail="fluffy", eye=R("2a6fdb")),
    "Yeti": lambda: biped(R("eef6ff"), R("cfe8ff"), accent=R("9fd4ff"), horns=True, fur=True, face=R("8fb8d9")),
    # Lava Egg
    "Fire Lizard": lambda: quadruped(R("e8442a"), R("ffb03a"), ears=None, tail="long", legs=0.25, spikes=ORANGE,
                                     body_scale=(0.9, 1.5, 0.75)),
    "Hellhound": lambda: quadruped(R("3a1f1f"), R("5a2a2a"), ears="pointy", tail="long", flames=True, eye=R("ff3b1f")),
    "Dragon": lambda: quadruped(R("d93a2b"), R("ffcf6a"), ears=None, tail="long", horns=True, wings=True,
                                wing_color=R("ff7a5c"), spikes=GOLD, accent=R("f5e6c8")),
    # Crystal Egg
    "Crystal Bat": lambda: bat(R("6a3fb5"), R("a97bff"), R("e2b8ff")),
    "Gem Golem": lambda: biped(R("7d6aa6"), R("9e8cc7"), crystals=R("e2b8ff"), eye=R("7df9ff")),
    "Unicorn": lambda: quadruped(R("ffffff"), R("ffe6f5"), ears="cat", tail="fluffy", horn=True, mane=R("c9a6ff"), legs=0.6),
    # Golden Egg
    "Golden Lion": lambda: quadruped(R("ffc933"), R("fff0b3"), ears="round", tail="tuft", mane=R("d98a1f"), legs=0.55),
    "Pegasus": lambda: quadruped(R("fffdf5"), R("fff3c2"), ears="cat", tail="fluffy", wings=True, wing_color=R("fff6d1"),
                                 mane=GOLD, legs=0.65),
    "Phoenix": lambda: bird(R("ff5a1f"), R("ffb02e"), beak=GOLD, belly=R("ffd34d"), crest=[R("ffd34d"), ORANGE, R("ff3b1f")],
                            tail_feathers=[R("ff3b1f"), ORANGE, GOLD, ORANGE, R("ff3b1f")], flames=True, scale_wings=1.5),
    # Cosmic Egg
    "Star Whale": lambda: whale(R("3b3fa8"), R("8fa2ff")),
    "Nebula Cat": lambda: quadruped(R("3a2a8a"), R("b28cff"), ears="cat", tail="thin", stars=True, spots=R("ff7ae0"),
                                    eye=R("7df9ff")),
    "Galaxy Dragon": lambda: quadruped(R("241a5c"), R("7a5cff"), ears=None, tail="long", horns=True, wings=True,
                                       wing_color=R("8f6bff"), spikes=R("7df9ff"), stars=True, accent=R("fff08a"),
                                       eye=R("7df9ff")),
    # Rainbow Egg
    "Rainbow Unicorn": lambda: quadruped(R("ffffff"), R("ffe6f5"), ears="cat", tail="fluffy", horn=True, wings=True,
                                         wing_color=R("ffd1f0"), legs=0.6,
                                         mane=[R(h) for h in ("ff4d4d", "ff9a3d", "ffe14d", "5ce05c", "4db8ff", "8a5cff")]),
    "Prism Fox": lambda: quadruped(R("8fe9ff"), R("ffffff"), ears="pointy", tail="fluffy", crystals=R("ff8ae0"),
                                   eye=R("8a5cff")),
    "Rainbow Phoenix": lambda: bird(R("ff4dd2"), R("4db8ff"), beak=GOLD, belly=R("ffe14d"),
                                    crest=[R("ff4d4d"), R("ffe14d"), R("5ce05c")],
                                    tail_feathers=[R(h) for h in ("ff4d4d", "ff9a3d", "ffe14d", "5ce05c", "4db8ff", "8a5cff")],
                                    scale_wings=1.5),
    # Void Egg
    "Void Serpent": lambda: serpent(R("1c1030"), R("3a1f5c"), R("b14dff")),
    "The Egg King": egg_king,
}


def main():
    eggs_dir = os.path.join(OUT, "Eggs")
    pets_dir = os.path.join(OUT, "Pets")
    os.makedirs(eggs_dir, exist_ok=True)
    os.makedirs(pets_dir, exist_ok=True)
    report = []
    reset()
    for name, build in make_eggs(None).items():
        if ONLY and name not in ONLY:
            continue
        reset()
        build()
        report.append((name, "Egg", finish(name, eggs_dir)))
    for name, build in PETS.items():
        if ONLY and name not in ONLY:
            continue
        reset()
        build()
        report.append((name, "Pet", finish(name, pets_dir)))
    for name, kind, tris in report:
        print(f"[made] {kind:3} {name:16} {tris:6d} tris")


main()
