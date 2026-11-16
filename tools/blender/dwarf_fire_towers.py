"""
Zwergen-Feuerturm (Verbrennen) – nutzt den Basis-Builder aus dwarf_towers.py

  fire_tower_lvl1.glb, _lvl2, _lvl3
  fire_tower_rapid.glb       Spezialisierung „Schnellfeuer“ (Feuerlanze, Einzelziel)
  fire_tower_inferno.glb     Spezialisierung „Großbrand“ (Feuerkrone, Flächenbrand)
  fx_flame_stream.glb        Flammenstrahl (Länge 1.5, ab Düse nach -Z) – in Godot auf Reichweite skalieren
  fx_firebolt.glb            Feuergeschoss der Feuerlanze (fliegt -Z)
  fx_lava_pool.glb           brennender Boden für Großbrand (Radius 1)

Nodes für Godot:
  Turret       -> um Y drehen zum Zielen (Großbrand: optional langsam drehen)
  Barrel       -> um X kippen
  Muzzle       -> Düsenöffnung: Flammen-Partikel / Strahl / Geschoss hier ansetzen
  PilotFlame   -> Zündflamme an der Düse (flackern lassen: Skalierung animieren)
  Nozzle_0..3  -> nur Großbrand: vier Mäuler, zeigen schräg nach außen/unten
  LavaSurface  -> nur Großbrand: Lava im Tiegel (langsam auf/ab wippen)
  AoEOrigin    -> nur Großbrand: Mittelpunkt für den Flächenschaden (Bodenhöhe)
Ursprung = Mitte Boden.
"""
import bpy, bmesh, math, os, random
from mathutils import Vector
import dwarf_towers as dt

OUT = os.path.dirname(os.path.abspath(__file__))
OCT = dt.OCT
ROT_Y = dt.ROT_Y

FIRE_BASE = dict(
    name_prefix="FireTower", turret="flamer", turret_r=0.58,
    rune_color="#ff2e1f", rune_strength=6.5, banner_color="#24100c",
    furnace=False, chimneys=0, elev=4, frost=0.3,          # frost = Anteil angekohlter Blöcke
    tanks=2, nozzle_len=0.6, nozzle_r=0.11, teeth=True, bellows=True, gauge=True,
    cracks=10, drips=0, lance=False, crown=False,
)
FIRE_VARIANTS = {
    "lvl1": dict(rows=3, r_bot=0.96, r_top=0.84, plinth_r=1.2, bands=("low",), rune_angles=(-1,),
                 rune_strength=3.5, banner=False, merlon_cap=None, corbels=False, turret_r=0.5,
                 frost=0.15, tanks=1, nozzle_len=0.35, nozzle_r=0.09, teeth=False, bellows=False,
                 gauge=False, cracks=0),
    "lvl2": dict(rows=4, r_bot=1.02, r_top=0.87, plinth_r=1.28, rune_angles=(-1, 5), rune_strength=4.5,
                 turret_r=0.54, frost=0.22, tanks=1, nozzle_len=0.48, nozzle_r=0.1, teeth=True,
                 gauge=False, cracks=4),
    "lvl3": dict(),
    "rapid": dict(lance=True, rune_color="#ffc23a", rune_strength=7.0, tanks=0, bellows=False,
                  nozzle_len=1.0, nozzle_r=0.065, cracks=10),
    "inferno": dict(crown=True, turret_r=0.72, r_bot=1.1, r_top=0.93, plinth_r=1.45, rune_color="#ff1a10",
                    rune_strength=7.5, frost=0.45, cracks=18, drips=10, merlon_cap="spike", tanks=0,
                    bellows=False, gauge=False),
}


class FireBuilder(dt.Builder):
    def __init__(self, cfg, rng):
        super().__init__(cfg, rng)
        M = self.M
        M["frost_stone"] = dt.mat("Stone_Charred", "#262220", rough=0.95)   # angekohlt
        M["lava"] = dt.mat("Lava", "#ff8a1a", emit="#ff6a10", strength=9.0)
        M["lava_hot"] = dt.mat("Lava_Hot", "#ffd860", emit="#ffc040", strength=12.0)
        M["flame_red"] = dt.mat("Flame_Red", "#ff3a10", emit="#ff2a08", strength=8.0)
        M["crust"] = dt.mat("Lava_Crust", "#1a1210", rough=1.0)
        M["leather"] = dt.mat("Leather", "#3a1a12", rough=0.9)
        M["wood"] = dt.mat("Wood_Dark", "#4a3324", rough=0.85)
        M["smoke"] = dt.mat("Smoke", "#1c1a1a", rough=1.0)

    def stick(self, p0, p1, w, h, material, parent, name):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        o = self.box((w, h, d.length), (p0 + p1) / 2, material=material, parent=parent, name=name)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
        return o

    def cone_dir(self, base, direction, length, r, material, parent, name, verts=6, r2=0.0):
        d = Vector(direction).normalized()
        o = self.cyl(r, length, Vector(base) + d * length / 2, verts=verts, r2=r2, material=material,
                     parent=parent, name=name)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = d.to_track_quat("Z", "Y")
        return o

    # ---------------------------------------------------------------- Turm
    def build(self, variant):
        root = super().build(variant)
        c, rng = self.cfg, self.rng
        Z0, ROW_H = 0.34, 0.38
        H = c["rows"] * ROW_H
        free = [0.3, 0.9, 1.4, 1.75, 2.2, 2.6, 3.0, 3.4, 4.1, 4.5, 5.0, 5.5, 5.9]
        # Magmarisse: Zickzack-Linien auf der Mauer (Banner vorne und Runensteine diagonal aussparen)
        for k in range(c["cracks"]):
            a = free[k % len(free)] + rng.uniform(-0.12, 0.12)
            if abs(math.remainder(a + math.pi / 2, 2 * math.pi)) < 0.45:
                a += 0.6
            t = rng.uniform(0.1, 0.85)
            z = Z0 + H * t
            R = c["r_bot"] + (c["r_top"] - c["r_bot"]) * t + 0.012
            pts = []
            for j in range(4):
                aa = a + (j % 2) * rng.uniform(0.04, 0.09) * (1 if k % 2 else -1)
                zz = z + j * 0.075 * (1 if k % 2 else -1)
                pts.append(Vector((math.cos(aa) * R, math.sin(aa) * R, zz)))
            for j in range(3):
                self.stick(pts[j], pts[j + 1], 0.02, 0.022, "lava", root, f"MagmaCrack_{k}_{j}")
        # Lavaströme vom Tiegel herab (Großbrand)
        for k in range(c["drips"]):
            a = k * 2 * math.pi / c["drips"] + 0.25
            if abs(math.remainder(a + math.pi / 2, 2 * math.pi)) < 0.4:
                continue
            top = Z0 + H + 0.18
            ln = rng.uniform(0.5, 1.3)
            prev = None
            for j in range(4):
                t = 1 - (j / 3) * (ln / H)
                zz = Z0 + H * t - 0.06
                R = c["r_bot"] + (c["r_top"] - c["r_bot"]) * t + 0.025
                p = Vector((math.cos(a) * R, math.sin(a) * R, zz))
                if prev is not None:
                    self.stick(prev, p, 0.05 - j * 0.008, 0.035, "lava", root, f"LavaDrip_{k}_{j}")
                prev = p
            self.ico(0.035, tuple(prev - Vector((0, 0, 0.02))), "lava_hot", root, f"LavaDripEnd_{k}")
        return root

    # ---------------------------------------------------------------- Flammenwerfer
    def pilot(self, parent, y):
        P = self.empty("PilotFlame", (0, y, 0), parent=parent)
        P.scale = (1.7, 1.9, 1.7)
        self.cyl(0.05, 0.14, (0, -0.06, 0), verts=6, r2=0.0, rot=ROT_Y, material="lava_hot", parent=P,
                 name="Pilot_Core")
        for k in range(3):
            a = k * 2 * math.pi / 3
            self.cyl(0.03, 0.1, (math.cos(a) * 0.04, -0.03, math.sin(a) * 0.04), verts=5, r2=0.0, rot=ROT_Y,
                     material="flame_red", parent=P, name=f"Pilot_Tongue_{k}")
        return P

    def t_flamer(self):
        c, T = self.cfg, self.turret
        if c["crown"]:
            return self.t_crown()
        self.turret_mount()
        L, nr = c["nozzle_len"], c["nozzle_r"]
        self.cheeks(0.26, size=(0.08, 0.46, 0.4), z=0.42)
        B = self.barrel_node((0, 0.05, 0.52))
        self.cyl(0.05, 0.62, (0, 0, 0), rot=(0, math.radians(90), 0), material="iron", parent=B,
                 name="Trunnion")
        # Brennkammer
        self.cyl(0.17, 0.42, (0, 0.05, 0), verts=10, rot=ROT_Y, material="bronze", parent=B,
                 name="Chamber", bevel=0.015)
        for k, y in enumerate((-0.12, 0.22)):
            self.cyl(0.185, 0.05, (0, y, 0), verts=10, rot=ROT_Y, material="iron", parent=B,
                     name=f"ChamberHoop_{k}")
        self.box((0.04, 0.16, 0.012), (0, 0.05, 0.172), material="rune", parent=B, name="ChamberRune")
        # Düse
        y0 = -0.16
        self.cyl(nr * 1.3, L, (0, y0 - L / 2, 0), verts=8, rot=ROT_Y, r2=nr, material="iron", parent=B,
                 name="Nozzle", bevel=0.008)
        if c["lance"]:
            for k in range(6):
                y = y0 - 0.1 - k * (L - 0.2) / 5
                self.cyl(nr * 1.9, 0.025, (0, y, 0), verts=8, rot=ROT_Y, material="iron", parent=B,
                         name=f"CoolingFin_{k}")
            self.cyl(nr * 1.2, 0.05, (0, y0 - L * 0.5, 0), verts=8, rot=ROT_Y, material="rune", parent=B,
                     name="LanceRuneBand")
        tip = y0 - L
        self.cyl(nr, 0.14, (0, tip - 0.06, 0), verts=8, rot=ROT_Y, r2=nr * 1.7, material="bronze", parent=B,
                 name="Nozzle_Mouth", bevel=0.008)
        if c["teeth"]:
            for k in range(6):
                a = k * math.pi / 3 + math.pi / 6
                base = (math.cos(a) * nr * 1.55, tip - 0.11, math.sin(a) * nr * 1.55)
                self.cone_dir(base, (math.cos(a) * 0.5, -1, math.sin(a) * 0.5), 0.12, 0.03, "iron", B,
                              f"Tooth_{k}", verts=4)
        self.pilot(B, tip - 0.13)
        self.empty("Muzzle", (0, tip - 0.16, 0), parent=B)
        # Tanks / Drucktank
        if c["lance"]:
            sp = self.ico(0.27, (0, 0.5, 0.52), "bronze", T, "PressureTank")
            bpy.ops.object.select_all(action="DESELECT")
            self.cyl(0.285, 0.05, (0, 0.5, 0.52), verts=12, material="rune", parent=T, name="PressureTankRune")
            for k, x in enumerate((-0.2, 0.2)):
                self.cyl(0.05, 0.42, (x, 0.32, 0.45), verts=8, material="iron", parent=T, name=f"Piston_{k}")
                self.cyl(0.03, 0.2, (x, 0.32, 0.75), verts=6, material="bronze", parent=T, name=f"PistonRod_{k}")
            self.stick((0, 0.3, 0.55), (0, 0.22, 0.52), 0.06, 0.06, "iron", T, "TankPipe")
        xs = {0: [], 1: [-0.4], 2: [-0.4, 0.4]}[c["tanks"]]
        for k, x in enumerate(xs):
            r, h = 0.15, 0.5
            self.cyl(r, h, (x, 0.12, 0.2 + h / 2), verts=10, material="bronze", parent=T, name=f"Tank_{k}",
                     bevel=0.01)
            o = self.ico(r, (x, 0.12, 0.2 + h), "bronze", T, f"TankDome_{k}")
            o.scale = (1, 1, 0.5)
            for j, z in enumerate((0.26, 0.2 + h - 0.06)):
                self.cyl(r + 0.012, 0.04, (x, 0.12, z), verts=10, material="iron", parent=T,
                         name=f"TankBand_{k}_{j}")
            self.box((0.06, 0.02, 0.24), (x, 0.12 - r - 0.003, 0.2 + h / 2), material="lava", parent=T,
                     name=f"TankWindow_{k}")
            self.stick((x, 0.12, 0.2 + h + 0.05), (x * 0.4, 0.2, 0.6), 0.045, 0.045, "iron", T, f"TankPipe_{k}")
        if c["bellows"]:
            y = 0.5
            self.box((0.36, 0.05, 0.22), (0, y - 0.07, 0.44), (0.12, 0, 0), material="wood", parent=T,
                     name="Bellows_Plate_A")
            self.box((0.36, 0.05, 0.22), (0, y + 0.08, 0.44), (-0.12, 0, 0), material="wood", parent=T,
                     name="Bellows_Plate_B")
            self.box((0.3, 0.12, 0.19), (0, y, 0.44), material="leather", parent=T, name="Bellows_Leather")
            self.stick((0, y - 0.12, 0.44), (0, 0.3, 0.5), 0.04, 0.04, "iron", T, "Bellows_Pipe")
        if c["gauge"]:   # Manometer vorne am linken Tank
            self.cyl(0.07, 0.03, (-0.4, -0.05, 0.62), verts=10, rot=ROT_Y, material="bronze", parent=T,
                     name="Gauge")
            self.cyl(0.055, 0.005, (-0.4, -0.066, 0.62), verts=10, rot=ROT_Y, material="crust", parent=T,
                     name="Gauge_Face")
            self.box((0.01, 0.006, 0.05), (-0.39, -0.07, 0.635), (0, -0.6, 0), material="lava_hot", parent=T,
                     name="Gauge_Needle")

    # ---------------------------------------------------------------- Feuerkrone (Großbrand)
    def t_crown(self):
        c, T, rng = self.cfg, self.turret, self.rng
        self.turret_mount()
        self.empty("AoEOrigin", (0, 0, 0), parent=self.root)
        # Stützbeine
        for k in range(4):
            a = k * math.pi / 2
            self.stick((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.25), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.6),
                       0.08, 0.08, "iron", T, f"Leg_{k}")
        # Tiegel
        self.cyl(0.32, 0.5, (0, 0, 0.78), verts=12, r2=0.62, material="iron", parent=T, name="Crucible",
                 bevel=0.02)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.62, minor_radius=0.05, major_segments=24,
                                         minor_segments=4, location=(0, 0, 1.03))
        self._finish(bpy.context.active_object, "bronze", T, "Crucible_Rim")
        for k, z in enumerate((0.62, 0.86)):
            rr = 0.32 + (0.62 - 0.32) * (z - 0.53) / 0.5 + 0.012
            self.cyl(rr, 0.05, (0, 0, z), verts=12, material="bronze", parent=T, name=f"CrucibleBand_{k}")
        # Runen außen am Tiegel
        for k in range(4):
            a = k * math.pi / 2 - math.pi / 2
            rr = 0.52
            self.rune((math.cos(a) * rr, math.sin(a) * rr, 0.84), a, 0.42, T, f"Crucible{k}")
        # Lava
        LS = self.empty("LavaSurface", (0, 0, 0.97), parent=T)
        self.cyl(0.58, 0.04, (0, 0, 0), verts=16, material="lava", parent=LS, name="Lava")
        for k in range(7):
            a = rng.uniform(0, 2 * math.pi); rr = rng.uniform(0.1, 0.42)
            o = self.ico(rng.uniform(0.06, 0.12), (math.cos(a) * rr, math.sin(a) * rr, 0.02), "crust", LS,
                         f"Crust_{k}")
            o.scale = (1, 1, 0.3)
        for k in range(5):
            a = k * 2 * math.pi / 5 + 0.3; rr = rng.uniform(0.0, 0.35)
            self.cone_dir((math.cos(a) * rr, math.sin(a) * rr, 0.0), (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 1),
                          rng.uniform(0.25, 0.45), 0.09, "lava_hot" if k % 2 else "flame_red", LS, f"Flame_{k}")
        # vier Drachenmäuler
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            out = Vector((math.cos(a), math.sin(a), -0.55)).normalized()
            base = Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 0.95))
            self.cone_dir(base - out * 0.12, out, 0.38, 0.11, "bronze", T, f"Spout_{k}", verts=8, r2=0.075)
            mouth = base + out * 0.26
            self.cone_dir(mouth, out, 0.12, 0.075, "bronze", T, f"SpoutMouth_{k}", verts=8, r2=0.13)
            for j in range(4):
                b = j * math.pi / 2
                side = out.cross(Vector((0, 0, 1))).normalized()
                up = side.cross(out).normalized()
                off = (side * math.cos(b) + up * math.sin(b)) * 0.12
                self.cone_dir(mouth + out * 0.1 + off, out + off * 3, 0.1, 0.025, "iron", T, f"SpoutTooth_{k}_{j}",
                              verts=4)
            N = self.empty(f"Nozzle_{k}", tuple(mouth + out * 0.16), parent=T)
            N.rotation_mode = "QUATERNION"
            N.rotation_quaternion = (-out).to_track_quat("Y", "Z")   # Nozzle-lokal -Y = Ausstoß (-Z in Godot)
            self.cone_dir(mouth + out * 0.1, out, 0.2, 0.06, "lava_hot", T, f"SpoutPilot_{k}", verts=6)
            # Lava läuft über den Rand
            self.stick(base + Vector((0, 0, 0.08)), base + out * 0.05 + Vector((0, 0, -0.05)), 0.06, 0.03, "lava",
                       T, f"SpoutSpill_{k}")
        self.empty("Muzzle", (0, 0, 1.0), parent=T)


# ==================================================================== Export
def build_variant(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cfg = dict(dt.BASE, **FIRE_BASE)
    cfg.update(FIRE_VARIANTS[variant])
    b = FireBuilder(cfg, random.Random(31))
    b.build(variant)
    path = os.path.join(OUT, f"fire_tower_{variant}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("EXPORTED", variant)


def new_fx():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = FireBuilder(dict(dt.BASE, **FIRE_BASE), random.Random(9))
    # große Leuchtflächen: weniger Emission, damit die Farben nicht zu Weiß ausbrennen
    for key, st in (("lava", 1.6), ("lava_hot", 2.2), ("flame_red", 1.8)):
        b.M[key].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = st
    return b


def export_fx(name):
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{name}.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    print("EXPORTED", name)


def build_fx():
    # Flammenstrahl: Wolke aus Low-Poly-Puffs, heiß an der Düse, rot/rauchig am Ende
    b = new_fx(); rng = b.rng
    R = b.empty("FlameStream", (0, 0, 0))
    n = 26
    for i in range(n):
        t = i / (n - 1)
        y = -0.08 - t * 1.45
        spread = 0.04 + t * 0.32
        mat = "lava_hot" if t < 0.3 else "lava" if t < 0.62 else "flame_red" if t < 0.88 else "smoke"
        r = 0.06 + t * 0.16 * rng.uniform(0.8, 1.2)
        p = (rng.uniform(-spread, spread) * 0.7, y, rng.uniform(-spread, spread) * 0.7)
        o = b.ico(r, p, mat, R, f"Puff_{i}")
        o.scale = (1, 1.4, 1)
    export_fx("fx_flame_stream")

    # Feuergeschoss
    b = new_fx()
    R = b.empty("Firebolt", (0, 0, 0))
    o = b.ico(0.09, (0, 0, 0), "lava_hot", R, "Core"); o.scale = (1, 1.3, 1)
    for k in range(5):
        a = k * 2 * math.pi / 5
        off = (math.cos(a) * 0.05, 0.05, math.sin(a) * 0.05)
        b.cone_dir(off, (math.cos(a) * 0.25, 1, math.sin(a) * 0.25), 0.28 + (k % 2) * 0.1, 0.05,
                   "lava" if k % 2 else "flame_red", R, f"Tail_{k}", verts=5)
    b.cone_dir((0, 0.02, 0), (0, 1, 0), 0.45, 0.07, "lava", R, "Tail_Main", verts=6)
    export_fx("fx_firebolt")

    # Lavateppich
    b = new_fx(); rng = b.rng
    R = b.empty("LavaPool", (0, 0, 0))
    def blob(radius, z, mat, name, seg=20, jitter=0.12):
        bm = bmesh.new()
        verts = []
        for i in range(seg):
            a = i * 2 * math.pi / seg
            rr = radius * (1 + rng.uniform(-jitter, jitter))
            verts.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
        bm.faces.new(verts)
        me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
        o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
        return b._finish(o, mat, R, name)
    blob(1.0, 0.0, "crust", "Pool_Crust", seg=24, jitter=0.1)
    blob(0.78, 0.008, "lava", "Pool_Lava", seg=20, jitter=0.15)
    blob(0.32, 0.014, "lava_hot", "Pool_Hot", seg=12, jitter=0.25)
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi); rr = rng.uniform(0.2, 0.7)
        o = b.ico(rng.uniform(0.06, 0.13), (math.cos(a) * rr, math.sin(a) * rr, 0.01), "crust", R, f"CrustIsland_{k}")
        o.scale = (1, 1, 0.25)
    F = b.empty("Flames", (0, 0, 0), parent=R)
    for k in range(10):
        a = rng.uniform(0, 2 * math.pi); rr = rng.uniform(0.1, 0.8)
        b.cone_dir((math.cos(a) * rr, math.sin(a) * rr, 0), (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 1),
                   rng.uniform(0.18, 0.4), rng.uniform(0.05, 0.09), "lava_hot" if k % 3 == 0 else "lava" if k % 3 == 1
                   else "flame_red", F, f"FlameTongue_{k}", verts=5)
    export_fx("fx_lava_pool")


if __name__ == "__main__":
    for v in FIRE_VARIANTS:
        build_variant(v)
    build_fx()
