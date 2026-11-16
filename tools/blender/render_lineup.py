"""Importiert die exportierten .glb (Gegenprobe des Exports) und rendert Vorschauen."""
import bpy, math, os, random, sys
from mathutils import Vector

OUT = os.path.dirname(os.path.abspath(__file__))
PREFIX = os.environ.get("PREFIX", "cannon_tower")
ORDER = os.environ.get("ORDER", "lvl1,lvl2,lvl3,rapid,heavy").split(",")
FRONT_COL = tuple(map(float, os.environ.get("FRONT_COL", "1.0,0.45,0.15").split(",")))
BACK_COL = tuple(map(float, os.environ.get("BACK_COL", "1.0,0.4,0.1").split(",")))
SPACING = 3.6

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
roots = {}
for i, v in enumerate(ORDER):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f"{PREFIX}_{v}.glb"))
    new = set(bpy.data.objects) - before
    root = [o for o in new if o.parent is None][0]
    root.location.x = (i - 2) * SPACING
    roots[v] = root

# Turrets leicht unterschiedlich ausrichten -> lebendiger
for v, ang in zip(ORDER, (-25, -15, -30, -20, -35)):
    ts = [o for o in roots[v].children_recursive if o.name.startswith("Turret")]
    if not ts:
        continue
    t = ts[0]
    t.rotation_mode = "XYZ"; t.rotation_euler = (0, 0, 0)
    t.rotation_quaternion = (1, 0, 0, 0)
    t.rotation_mode = "QUATERNION"
    import mathutils
    t.rotation_quaternion = mathutils.Euler((0, 0, math.radians(ang))).to_quaternion()

# Umgebung
world = bpy.data.worlds.new("W"); scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.008, 0.01, 0.016, 1)

gm = bpy.data.materials.new("Ground"); gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.012, 0.011, 0.012, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1
bpy.ops.mesh.primitive_plane_add(size=60)
bpy.context.active_object.data.materials.append(gm)
rng = random.Random(3)
rock = bpy.data.materials.new("Rock"); rock.use_nodes = True
rock.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.019, 0.018, 1)
for i in range(30):
    x = rng.uniform(-10, 10); y = rng.uniform(-3, 4)
    if min(abs(x - (k - 2) * SPACING) for k in range(5)) < 1.8 and abs(y) < 1.8:
        continue
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=rng.uniform(0.1, 0.3), location=(x, y, 0.05))
    o = bpy.context.active_object
    o.scale = (1, rng.uniform(0.7, 1.2), rng.uniform(0.5, 0.8))
    o.data.materials.append(rock)

def light(kind, loc, energy, color, size=0.3, rot=(0, 0, 0)):
    ld = bpy.data.lights.new(f"{kind}{loc}", kind)
    ld.energy, ld.color = energy, color
    if kind == "AREA": ld.size = size
    elif kind == "POINT": ld.shadow_soft_size = size
    o = bpy.data.objects.new(ld.name, ld); o.location, o.rotation_euler = loc, rot
    scene.collection.objects.link(o)

light("SUN", (0, 0, 10), 1.3, (0.55, 0.65, 0.95), rot=(math.radians(50), 0, math.radians(-30)))
light("AREA", (2, 8, 6), 1800, (0.45, 0.55, 0.9), size=14, rot=(math.radians(-60), 0, math.radians(180)))
for i in range(5):
    x = (i - 2) * SPACING
    light("POINT", (x - 0.4, -1.8, 1.4), 22, FRONT_COL)
    light("POINT", (x, 1.6, 3.4), 25, BACK_COL)

cam_d = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cam_d)
scene.collection.objects.link(cam); scene.camera = cam

scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"
scene.cycles.samples = 64; scene.cycles.use_denoising = True
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.8

def shot(name, loc, target, lens, res):
    cam_d.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = os.path.join(OUT, f"preview_{os.environ.get('TAG', '')}{name}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)

which = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["lineup", "specs"]
if "lineup" in which:
    shot("lineup", (0, -19.5, 7.8), (0, 0, 1.6), 36, (2048, 900))
if "specs" in which:
    shot("specs", (5.4 - 3.0, -8.6, 5.0), (5.4, 0, float(os.environ.get("SPEC_Z", "1.8"))), 40, (1600, 1000))
