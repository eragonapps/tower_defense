"""Rendert die Lager-Varianten aus den exportierten .glb – Zustand per Argument: hold | open"""
import bpy, math, os, random, sys
from mathutils import Vector
import dwarf_towers as dt
from berserker_concepts import SceneBuilder, environment

OUT = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["hold"]
state = args[0]
order = args[1].split(",") if len(args) > 1 else ["lvl1", "lvl2", "lvl3", "ironwall", "bloodrage"]
shot = args[2] if len(args) > 2 else "lineup"
SP = 4.6

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rng = random.Random(3)
b = SceneBuilder(rng, True)
environment(b, rng)
hold = state == "hold"
for i, v in enumerate(order):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f"berserker_camp_{v}.glb"))
    new = set(bpy.data.objects) - before
    root = [o for o in new if o.parent is None][0]
    root.location.x = (i - (len(order) - 1) / 2) * SP
    def node(n):
        return [o for o in new if o.name.split(".")[0] == n][0]
    def hide(o, h):
        for x in [o] + list(o.children_recursive):
            x.hide_render = h
    hide(node("Squad_Fight"), not hold)
    hide(node("Squad_Idle"), hold)
    hide(node("RageAura"), not hold)
    try:
        hide(node("HornBlast"), not hold)
    except IndexError:
        pass
    if not hold:
        bar = node("Barricade")
        bar.rotation_mode = "XYZ"; bar.rotation_euler = (0, 0, math.radians(-90))
    # Gegner
    if hold:
        for k in range(4):
            row = k // 2
            y = -0.55 + (k % 2) * 1.1 + rng.uniform(-0.1, 0.1) + (0.3 if row else 0)
            if abs(y) > 1.0:
                y = math.copysign(0.95, y)
            b.goblin(f"Gob_{i}_{k}", (root.location.x + 1.1 + row * 0.55, y, 0), math.radians(-90) + rng.uniform(-0.3, 0.3), rng)
    else:
        for k in range(3):
            b.goblin(f"Gob_{i}_{k}", (root.location.x + 1.6 - k * 1.3 + rng.uniform(-0.2, 0.2), rng.uniform(-0.7, 0.7), 0),
                     math.radians(-90), rng)

w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.01, 0.012, 0.02, 1)
def light(kind, loc, e, col, rot=(0, 0, 0), size=1):
    ld = bpy.data.lights.new(f"{kind}{loc}", kind); ld.energy = e; ld.color = col
    if kind == "AREA": ld.size = size
    if kind == "POINT": ld.shadow_soft_size = 0.2
    o = bpy.data.objects.new(ld.name, ld); o.location = loc; o.rotation_euler = rot
    sc.collection.objects.link(o)
light("SUN", (0, 0, 10), 2.4, (0.55, 0.65, 0.95), rot=(math.radians(48), 0, math.radians(-40)))
light("AREA", (0, 8, 6), 1500, (0.45, 0.55, 0.9), rot=(math.radians(-50), 0, math.radians(180)), size=16)
for i in range(len(order)):
    x = (i - (len(order) - 1) / 2) * SP
    light("POINT", (x - 0.3, 2.3, 1.1), 35, (1.0, 0.5, 0.2))
    light("POINT", (x + 0.8, -0.8, 1.4), 18 if hold else 6, (1.0, 0.35, 0.2))

cd = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
if shot == "lineup":
    cd.lens = 26
    cam.location = (0, -13.0, 10.5)
    tgt = Vector((0, 1.1, 0.0))
    sc.render.resolution_x, sc.render.resolution_y = 2400, 1000
else:
    cd.lens = 30
    cx = 0.0
    cam.location = (cx + 1.3, -5.4, 5.4)
    tgt = Vector((cx + 0.3, 0.7, 0.3))
    sc.render.resolution_x, sc.render.resolution_y = 1300, 900
cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 48; sc.cycles.use_denoising = True
sc.view_settings.view_transform = "AgX"; sc.view_settings.look = "AgX - Medium High Contrast"
sc.view_settings.exposure = 1.3
sc.render.filepath = os.path.join(OUT, f"preview_camp_{shot}_{state}.png")
bpy.ops.render.render(write_still=True)
print("RENDERED", sc.render.filepath)
