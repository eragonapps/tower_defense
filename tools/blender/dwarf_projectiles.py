"""
Projektile für die Zwergen-Kanonentürme (gleicher Stil, gleiche Materialien).

  projectile_cannonball.glb   Stufe 1–3  (in Godot pro Stufe skalieren: 0.8 / 0.9 / 1.0)
  projectile_rapid_slug.glb   Schnellfeuer – Bronzegeschoss mit Leuchtspur
  projectile_mortar_bomb.glb  Wucht – Runenbombe mit glimmender Lunte

Ursprung = Schwerpunkt, Flugrichtung = -Z (Godot forward).
Rapid-Slug: Node "Tracer" separat -> kann in Godot ausgeblendet/skaliert werden.
Mörserbombe: Node "Fuse_Ember" -> Ankerpunkt für Funken-Partikel.
"""
import bpy, math, os, random
import dwarf_towers as dt

OUT = os.path.dirname(os.path.abspath(__file__))
ROT_Y = dt.ROT_Y


def new_builder():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = dt.Builder(dict(dt.BASE), random.Random(1))
    b.M["tracer"] = dt.mat("Tracer_Glow", "#ffb030", emit="#ffa424", strength=12.0)
    b.M["rune_red"] = dt.mat("Rune_Glow_Red", "#ff3410", emit="#ff3410", strength=7.0)
    return b


def export(name):
    path = os.path.join(OUT, f"projectile_{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("EXPORTED", path)


def sphere(b, r, sub, material, parent, name, loc=(0, 0, 0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    return b._finish(bpy.context.active_object, material, parent, name)


def cannonball():
    b = new_builder()
    R = b.empty("Cannonball", (0, 0, 0))
    sphere(b, 0.11, 2, "iron", R, "Ball")
    b.cyl(0.113, 0.026, (0, 0, 0), verts=16, material="bronze", parent=R, name="Band_A")
    b.cyl(0.113, 0.026, (0, 0, 0), verts=16, rot=ROT_Y, material="bronze", parent=R, name="Band_B")
    export("cannonball")


def rapid_slug():
    b = new_builder()
    R = b.empty("RapidSlug", (0, 0, 0))
    b.cyl(0.032, 0.1, (0, 0.0, 0), verts=8, rot=ROT_Y, material="bronze", parent=R, name="Body")
    b.cyl(0.034, 0.02, (0, 0.035, 0), verts=8, rot=ROT_Y, material="iron", parent=R, name="Rim")
    # Spitze nach -Y (= Godot -Z)
    b.cyl(0.032, 0.06, (0, -0.08, 0), verts=8, rot=ROT_Y, r2=0.0,
          material="iron", parent=R, name="Tip")
    T = b.empty("Tracer", (0, 0.05, 0), parent=R)
    b.cyl(0.026, 0.22, (0, 0.11, 0), verts=8, rot=(-math.radians(90), 0, 0), r2=0.0, material="tracer",
          parent=T, name="Tracer_Trail")
    export("rapid_slug")


def mortar_bomb():
    b = new_builder()
    R = b.empty("MortarBomb", (0, 0, 0))
    r = 0.26
    sphere(b, r, 2, "iron", R, "Shell")
    # Glühender Runenring zwischen zwei Bronzebändern
    b.cyl(r + 0.004, 0.035, (0, 0, 0), verts=16, material="rune_red", parent=R, name="RuneRing")
    for s in (-1, 1):
        b.cyl(r - 0.008, 0.035, (0, 0, s * 0.045), verts=16, material="bronze", parent=R,
              name=f"Band_{s}")
    # Nieten auf den Bändern
    for i in range(10):
        a = i * 2 * math.pi / 10
        for s in (-1, 1):
            b.ico(0.016, (math.cos(a) * (r - 0.003), math.sin(a) * (r - 0.003), s * 0.045),
                  "iron", R, f"Rivet_{i}_{s}")
    # Kanten-Stacheln (Zwergen-Optik)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        b.cyl(0.035, 0.08, (math.cos(a) * (r + 0.02), math.sin(a) * (r + 0.02), 0), verts=4,
              r2=0.0, rot=(0, math.radians(90), a), material="iron", parent=R, name=f"Spike_{i}")
    # Zünderkappe + Lunte oben
    b.cyl(0.075, 0.06, (0, 0, r + 0.0), verts=8, material="bronze", parent=R, name="FuseCap",
          bevel=0.01)
    b.cyl(0.018, 0.1, (0.0, 0.0, r + 0.08), verts=6, rot=(0.35, 0, 0), material="iron",
          parent=R, name="Fuse")
    E = b.empty("Fuse_Ember", (0, -0.018, r + 0.135), parent=R)
    sphere(b, 0.026, 1, "ember", E, "Ember")
    export("mortar_bomb")


if __name__ == "__main__":
    cannonball()
    rapid_slug()
    mortar_bomb()
