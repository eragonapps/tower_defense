"""Vorschau der Gegner: Zustands-Übersicht (sheet) und Größen-Lineup (lineup)."""
import bpy, math, os, sys
from mathutils import Vector
import dwarf_enemies as de

OUT = de.OUT
mode = os.environ.get("MODE", "sheet")


def setup_world(sc, strength=1.0):
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.035, 0.05, 1)
    def light(kind, loc, e, col, rot=(0, 0, 0), size=1):
        ld = bpy.data.lights.new(f"{kind}{loc}", kind); ld.energy = e * strength; ld.color = col
        if kind == "AREA": ld.size = size
        o = bpy.data.objects.new(ld.name, ld); o.location = loc; o.rotation_euler = rot
        sc.collection.objects.link(o)
    light("SUN", (0, 0, 10), 3.0, (0.75, 0.8, 1.0), rot=(math.radians(40), 0, math.radians(-35)))
    light("SUN", (0, 0, 10), 1.2, (0.5, 0.6, 1.0), rot=(math.radians(-60), 0, math.radians(160)))
    sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "AgX"; sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = 0.9


def mesh_bbox():
    lo, hi = Vector((9, 9, 9)), Vector((-9, -9, -9))
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name != "Ground":
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    return lo, hi


def set_state(rig, state):
    for o in rig.J.values():
        ad = o.animation_data
        if ad:
            for tr in ad.nla_tracks:
                tr.mute = tr.name != state


if mode == "sheet":
    states = [("Walk", 5), ("Hit", 3), ("Held", 5), ("Death", 25)]
    os.makedirs("/tmp/enemy_tiles", exist_ok=True)
    only = os.environ.get("ONLY", "").split(",") if os.environ.get("ONLY") else list(de.ENEMIES)
    for name in only:
        b, rig = de.build(name)
        sc = bpy.context.scene
        setup_world(sc)
        bpy.ops.mesh.primitive_plane_add(size=20)
        g = bpy.context.active_object; g.name = "Ground"
        gm = bpy.data.materials.new("G"); gm.use_nodes = True
        gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.045, 0.045, 1)
        g.data.materials.append(gm)
        lo, hi = mesh_bbox()
        size = max(hi - lo)
        center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (hi.z) * 0.45))
        cd = bpy.data.cameras.new("C"); cd.lens = 50
        cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
        d = Vector((0.85, -1.0, 0.6)).normalized()
        cam.location = center + d * (size * 2.3 + 0.4)
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.resolution_x = sc.render.resolution_y = 360
        sc.cycles.samples = 16
        for st, f in states:
            set_state(rig, st)
            sc.frame_set(f)
            sc.render.filepath = f"/tmp/enemy_tiles/{name}_{st}.png"
            bpy.ops.render.render(write_still=True)
        if name == "goblin_shaman":
            set_state(rig, "Cast"); sc.frame_set(15)
            sc.render.filepath = f"/tmp/enemy_tiles/{name}_Cast.png"
            bpy.ops.render.render(write_still=True)
        print("TILES", name)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    setup_world(sc)
    order = ["rat_swarm", "kobold_sapper", "goblin", "goblin_shaman", "draugr", "shadow_spider", "stone_golem",
             "cave_troll", "fallen_king", "deep_worm"]
    widths = {"rat_swarm": 0.8, "kobold_sapper": 0.6, "goblin": 0.6, "goblin_shaman": 0.7, "draugr": 0.7,
              "shadow_spider": 1.3, "stone_golem": 1.2, "cave_troll": 1.2, "fallen_king": 1.2, "deep_worm": 1.4}
    x = 0
    for n in order:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f"enemy_{n}.glb"))
        new = set(bpy.data.objects) - before
        root = [o for o in new if o.parent is None][0]
        x += widths[n] / 2
        root.location.x = x
        if n == "deep_worm":
            root.rotation_euler = (0, 0, math.radians(-70))
        x += widths[n] / 2 + 0.25
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "dwarf_miner.glb"))
    mroot = [o for o in set(bpy.data.objects) - before if o.parent is None][0]
    mroot.location = (-0.6, 0, 0)
    sc.frame_set(1)
    bpy.ops.mesh.primitive_plane_add(size=40)
    g = bpy.context.active_object; g.name = "Ground"
    gm = bpy.data.materials.new("G"); gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.045, 0.045, 1)
    g.data.materials.append(gm)
    mid = x / 2 - 0.3
    cd = bpy.data.cameras.new("C"); cd.lens = 35
    cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (mid + 0.3, -13.5, 4.2)
    cam.rotation_euler = (Vector((mid, 0, 0.55)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = 2400, 800
    sc.cycles.samples = 48
    sc.render.filepath = os.path.join(OUT, "preview_enemies_lineup.png")
    bpy.ops.render.render(write_still=True)
    print("LINEUP DONE")
