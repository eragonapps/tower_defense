"""
Zwergen-Kanonenturm – alle Ausbaustufen (Low-Poly, düsterer Zwergenstil)

Aufruf:  python3 dwarf_towers.py            -> exportiert alle Varianten als .glb
         (oder: blender -b -P dwarf_towers.py)

Varianten:
  cannon_tower_lvl1.glb        Stufe 1
  cannon_tower_lvl2.glb        Stufe 2
  cannon_tower_lvl3.glb        Stufe 3
  cannon_tower_rapid.glb       Spezialisierung „Schnellfeuer“ (Rotationskanone)
  cannon_tower_heavy.glb       Spezialisierung „Wucht“ (Mörser)

Nodes für Godot (in allen Varianten gleich):
  Turret  -> um Y drehen zum Zielen
  Barrel  -> um X kippen (Elevation), auch für Rückstoß-Animation
  Muzzle  -> Spawnpunkt Projektil / Mündungsfeuer
  Spin    -> nur „rapid“: um lokale Z-Achse drehen (Läufe rotieren)
Lauf zeigt nach -Z (Godot forward), Ursprung = Mitte Boden.
"""
import bpy, bmesh, math, random, os
from mathutils import Vector, Euler, Quaternion

OUT = os.path.dirname(os.path.abspath(__file__))
OCT = math.pi / 8
ROT_Y = (math.radians(90), 0, 0)   # Zylinder entlang Y legen

# ============================================================== Konfiguration
BASE = dict(
    rows=5, r_bot=1.08, r_top=0.9, plinth_r=1.35,
    bands=("low", "high"), rune_angles=(-1, 1, 3, 5),   # Vielfache von pi/4
    banner=True, merlon_cap="bronze", corbels=True, buttresses=False,
    rune_color="#ff6a12", rune_strength=6.0,
    turret="cannon", turret_r=0.62,
    barrel_r=0.22, barrel_len=1.0, hoops=3, horns=True, elev=8,
    furnace=True, chimneys=1,
)
VARIANTS = {
    "lvl1": dict(rows=3, r_bot=0.96, r_top=0.84, plinth_r=1.2, bands=("low",),
                 rune_angles=(-1,), rune_strength=3.0, banner=False, merlon_cap=None,
                 corbels=False, turret_r=0.5, barrel_r=0.17, barrel_len=0.7, hoops=1,
                 horns=False, furnace=False, chimneys=0),
    "lvl2": dict(rows=4, r_bot=1.02, r_top=0.87, plinth_r=1.28, rune_angles=(-1, 5),
                 rune_strength=4.5, turret_r=0.56, barrel_r=0.2, barrel_len=0.85, hoops=2,
                 horns=False, chimneys=0),
    "lvl3": dict(),
    "rapid": dict(turret="gatling", rune_color="#ffa424", rune_strength=7.0, elev=4,
                  chimneys=2),
    "heavy": dict(rows=5, r_bot=1.12, r_top=0.95, plinth_r=1.5, turret="mortar",
                  turret_r=0.78, buttresses=True, merlon_cap="spike",
                  rune_color="#ff3410", rune_strength=7.0, elev=35, chimneys=2),
}

# ============================================================== Helfer
def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)

def mat(name, color, metal=0.0, rough=0.8, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(color), 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(emit), 1)
        b.inputs["Emission Strength"].default_value = strength
    return m

def make_materials(cfg):
    return {
        "stone":     mat("Stone_Dark",   "#4a4744", rough=0.92),
        "stone_alt": mat("Stone_Darker", "#363433", rough=0.95),
        "stone_key": mat("Stone_Rune",   "#2a2928", rough=0.85),
        "iron":      mat("Iron_Black",   "#4a4d52", metal=0.9, rough=0.5),
        "bronze":    mat("Bronze_Aged",  "#8a5c2e", metal=1.0, rough=0.45),
        "rune":      mat("Rune_Glow",    cfg["rune_color"], emit=cfg["rune_color"],
                         strength=cfg["rune_strength"]),
        "ember":     mat("Forge_Ember",  "#ff4a0a", emit="#ff5a10", strength=10.0),
        "banner":    mat("Banner", cfg.get("banner_color", "#5a1414"), rough=0.9),
        "bore":      mat("Barrel_Bore",  "#120a06", emit="#ff4a0a", strength=1.5),
        "bore_dark": mat("Barrel_Bore_Dark", "#0a0909", rough=1.0),
    }

class Builder:
    def __init__(self, cfg, rng):
        self.cfg, self.rng = cfg, rng
        self.M = make_materials(cfg)

    # --- Grundformen; Koordinaten immer lokal zum Parent
    def _finish(self, o, material, parent, name, bevel=0.0):
        o.name = name
        o.data.materials.clear(); o.data.materials.append(self.M[material])
        if bevel > 0:
            md = o.modifiers.new("Bevel", "BEVEL")
            md.width, md.segments, md.limit_method = bevel, 1, "ANGLE"
        o.parent = parent
        o.matrix_parent_inverse.identity()
        for p in o.data.polygons:
            p.use_smooth = False
        return o

    def box(self, size, loc, rot=(0, 0, 0), material="stone", parent=None, name="Box", bevel=0.0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
        o = bpy.context.active_object
        o.scale = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        return self._finish(o, material, parent, name, bevel)

    def cyl(self, r, depth, loc, verts=8, rot=(0, 0, 0), r2=None, material="stone",
            parent=None, name="Cyl", bevel=0.0):
        if r2 is None:
            bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth,
                                                location=loc, rotation=rot)
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2,
                                            depth=depth, location=loc, rotation=rot)
        return self._finish(bpy.context.active_object, material, parent, name, bevel)

    def ico(self, r, loc, material, parent, name):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=loc)
        return self._finish(bpy.context.active_object, material, parent, name)

    def empty(self, name, loc, parent=None, rot=(0, 0, 0)):
        e = bpy.data.objects.new(name, None)
        e.location, e.rotation_euler = loc, rot
        e.empty_display_size = 0.3
        bpy.context.scene.collection.objects.link(e)
        e.parent = parent
        return e

    # --- Rune aus Leuchtstäben
    def rune(self, center, angle, scale, parent, tag):
        strokes = [(0.0, -0.22, 0.0, 0.2), (0.0, 0.02, -0.14, 0.18), (0.0, 0.02, 0.14, 0.18),
                   (-0.12, -0.22, 0.12, -0.22), (-0.07, -0.12, 0.07, -0.12)]
        out = Vector((math.cos(angle), math.sin(angle), 0))
        side = Vector((-math.sin(angle), math.cos(angle), 0))
        for k, (x0, z0, x1, z1) in enumerate(strokes):
            dx, dz = (x1 - x0) * scale, (z1 - z0) * scale
            L = math.hypot(dx, dz) + 0.035 * scale
            p = Vector(center) + side * ((x0 + x1) / 2 * scale) + Vector((0, 0, (z0 + z1) / 2 * scale))
            o = self.box((0.03, 0.035 * scale, L), p, material="rune", parent=parent,
                         name=f"Rune_{tag}_{k}")
            o.rotation_mode = "QUATERNION"
            o.rotation_quaternion = Quaternion(out, math.atan2(-dx, dz)) @ Euler((0, 0, angle)).to_quaternion()

    # ========================================================== Turm
    def build(self, variant):
        c, rng = self.cfg, self.rng
        root = self.empty(f"{c.get('name_prefix', 'CannonTower')}_{variant}", (0, 0, 0))
        self.root = root
        ROW_H, Z0 = 0.38, 0.34
        rows, rb, rt = c["rows"], c["r_bot"], c["r_top"]

        # Bodenplatte
        self.cyl(c["plinth_r"], 0.22, (0, 0, 0.11), rot=(0, 0, OCT), material="stone_alt",
                 parent=root, name="Plinth", bevel=0.05)
        self.cyl(c["plinth_r"] - 0.13, 0.12, (0, 0, 0.28), rot=(0, 0, OCT), material="stone",
                 parent=root, name="Plinth_Step", bevel=0.03)

        # Kern + Steinblöcke
        H = rows * ROW_H
        self.cyl(rb - 0.25, H, (0, 0, Z0 + H / 2), r2=rt - 0.25, rot=(0, 0, OCT),
                 material="stone_alt", parent=root, name="Core")
        for row in range(rows):
            t = row / max(rows - 1, 1)
            R = rb + (rt - rb) * t
            z = Z0 + row * ROW_H + ROW_H / 2
            w = 2 * R * math.sin(math.pi / 8) * 1.02
            for i in range(8):
                a = (i + 0.5 * (row % 2)) * math.pi / 4
                rr = R - 0.17 + rng.uniform(-0.015, 0.02)
                self.box((0.34, w * rng.uniform(0.93, 0.99), ROW_H * rng.uniform(0.9, 0.97)),
                         (math.cos(a) * rr, math.sin(a) * rr, z + rng.uniform(-0.01, 0.01)),
                         (rng.uniform(-0.02, 0.02), rng.uniform(-0.03, 0.03), a + rng.uniform(-0.025, 0.025)),
                         material=("frost_stone" if c.get("frost") and rng.random() < c["frost"]
                                   else "stone" if rng.random() > 0.3 else "stone_alt"),
                         parent=root, name=f"Block_{row}_{i}", bevel=0.035)

        # Strebepfeiler (Wucht)
        if c["buttresses"]:
            for k, a in enumerate((0, math.pi / 2, math.pi)):
                bh = H * 0.8
                r = rb + 0.1
                self.box((0.5, 0.34, bh), (math.cos(a) * r, math.sin(a) * r, Z0 + bh / 2 - 0.05),
                         (0, -0.2, a), material="stone", parent=root, name=f"Buttress_{k}", bevel=0.04)
                self.box((0.56, 0.4, 0.1), (math.cos(a) * (r + 0.12), math.sin(a) * (r + 0.12), Z0 + 0.4),
                         (0, -0.2, a), material="iron", parent=root, name=f"ButtressBand_{k}", bevel=0.01)
                self.cyl(0.2, 0.3, (math.cos(a) * (r - 0.18), math.sin(a) * (r - 0.18), Z0 + bh + 0.1),
                         verts=4, r2=0.0, rot=(0, 0, a + math.pi / 4), material="iron",
                         parent=root, name=f"ButtressSpike_{k}")

        # Runensteine
        zr = Z0 + H / 2
        Rm = rb + (rt - rb) * 0.5 + 0.05
        for k, ang in enumerate(c["rune_angles"]):
            a = ang * math.pi / 4
            self.box((0.12, 0.42, 0.78), (math.cos(a) * Rm, math.sin(a) * Rm, zr), (0, 0, a),
                     material="stone_key", parent=root, name=f"RuneStone_{k}", bevel=0.04)
            rr = Rm + 0.115
            self.rune((math.cos(a) * rr, math.sin(a) * rr, zr), a, 1.25, root, f"S{k}")

        # Eisenbänder
        def band(z, r, h, name):
            self.cyl(r, h, (0, 0, z), rot=(0, 0, OCT), material="iron", parent=root,
                     name=name, bevel=0.015)
            for i in range(8):
                a = i * math.pi / 4
                rr = r * math.cos(OCT) + 0.01
                self.ico(0.035, (math.cos(a) * rr, math.sin(a) * rr, z), "iron", root, f"{name}_Rivet{i}")
        if "low" in c["bands"]:
            band(Z0 + 0.06, rb + 0.03, 0.12, "Band_Low")
        if "high" in c["bands"]:
            band(Z0 + H - 0.05, rt + 0.04, 0.14, "Band_High")

        # Plattform, Kragsteine, Zinnen
        TOP = Z0 + H
        self.cyl(rt + 0.28, 0.18, (0, 0, TOP + 0.09), rot=(0, 0, OCT), material="stone_alt",
                 parent=root, name="Platform", bevel=0.04)
        if c["corbels"]:
            for i in range(8):
                a = i * math.pi / 4 + OCT
                self.box((0.22, 0.16, 0.16), (math.cos(a) * (rt + 0.1), math.sin(a) * (rt + 0.1), TOP - 0.06),
                         (0, 0.5, a), material="stone", parent=root, name=f"Corbel_{i}", bevel=0.03)
        mr = rt + 0.15
        for i in range(8):
            a = i * math.pi / 4
            high = i % 2 == 0
            h = (0.42 if high else 0.3) * (0.8 if variant == "lvl1" else 1.0)
            loc = (math.cos(a) * mr, math.sin(a) * mr, TOP + 0.18 + h / 2)
            self.box((0.2, 0.34, h), loc, (0, 0, a), material="stone", parent=root,
                     name=f"Merlon_{i}", bevel=0.035)
            if high and c["merlon_cap"] == "bronze":
                self.cyl(0.13, 0.1, (loc[0], loc[1], TOP + 0.18 + h + 0.05), verts=4, r2=0.0,
                         rot=(0, 0, a + math.pi / 4), material="bronze", parent=root, name=f"MerlonCap_{i}")
            elif high and c["merlon_cap"] == "ice":
                self.cyl(0.11, 0.38, (loc[0], loc[1], TOP + 0.18 + h + 0.17), verts=5, r2=0.0,
                         rot=(rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), a), material="ice",
                         parent=root, name=f"MerlonIce_{i}")
            elif high and c["merlon_cap"] == "spike":
                self.box((0.24, 0.38, 0.06), (loc[0], loc[1], TOP + 0.18 + h + 0.03), (0, 0, a),
                         material="iron", parent=root, name=f"MerlonPlate_{i}")
                self.cyl(0.08, 0.32, (loc[0], loc[1], TOP + 0.18 + h + 0.22), verts=4, r2=0.0,
                         rot=(0, 0, a + math.pi / 4), material="iron", parent=root, name=f"MerlonSpike_{i}")

        # Banner vorne
        if c["banner"]:
            bpy.ops.mesh.primitive_plane_add(size=1)
            ban = bpy.context.active_object
            bm = bmesh.new(); bm.from_mesh(ban.data)
            bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
            bm.to_mesh(ban.data); bm.free()
            blen = min(1.0, H - 0.5)
            ban.scale = (0.5, blen, 1.0); ban.rotation_euler = (math.radians(90), 0, 0)
            bpy.ops.object.transform_apply(location=False, scale=True, rotation=True)
            for v in ban.data.vertices:
                if v.co.z < -blen / 2 + 0.05 and abs(v.co.x) < 0.01:
                    v.co.z += 0.2 * blen
                v.co.y += math.sin(v.co.z * 5.0) * 0.025
            ban.location = (0, -(rt + 0.08), TOP - 0.12 - blen / 2)
            self._finish(ban, "banner", root, "Banner")
            self.box((0.62, 0.05, 0.05), (0, -(rt + 0.1), TOP - 0.1), material="iron",
                     parent=root, name="Banner_Rod")
            self.rune((0, -(rt + 0.12), TOP - 0.12 - blen * 0.45), -math.pi / 2, 0.75 * min(1, blen + 0.1),
                      root, "Banner")

        # Turret
        turret = self.empty(c.get("top_name", "Turret"), (0, 0, TOP + 0.18), parent=root)
        self.turret, self.TOP = turret, TOP
        getattr(self, "t_" + c["turret"])()
        self.furnace()
        return root

    def turret_mount(self):
        tr = self.cfg["turret_r"]
        self.cyl(tr, 0.1, (0, 0, 0.05), verts=16, material="bronze", parent=self.turret,
                 name="Turret_Ring", bevel=0.02)
        self.cyl(tr - 0.12, 0.18, (0, 0, 0.19), rot=(0, 0, OCT), material="iron",
                 parent=self.turret, name="Turret_Base", bevel=0.03)

    # ---------------------------------------------------------- Turret-Teile
    def cheeks(self, x, size=(0.1, 0.62, 0.42), z=0.45):
        for s in (-1, 1):
            n = "L" if s < 0 else "R"
            self.box(size, (s * x, -0.02, z), material="iron", parent=self.turret,
                     name=f"Cheek_{n}", bevel=0.03)
            self.box((0.04, size[1] * 0.8, 0.06), (s * (x + size[0] / 2 + 0.01), -0.02, z + size[2] * 0.35),
                     material="bronze", parent=self.turret, name=f"CheekTrim_{n}")

    def barrel_node(self, pivot):
        b = self.empty("Barrel", pivot, parent=self.turret, rot=(-math.radians(self.cfg["elev"]), 0, 0))
        return b

    def t_cannon(self):
        self.turret_mount()
        c = self.cfg
        br, L = c["barrel_r"], c["barrel_len"]
        x = br + 0.13
        self.cheeks(x, size=(0.1, 0.4 + L * 0.22, 0.3 + br * 0.6))
        B = self.barrel_node((0, 0.05, 0.3 + br))
        self.cyl(0.06, 2 * x + 0.1, (0, 0, 0), rot=(0, math.radians(90), 0), material="iron",
                 parent=B, name="Trunnion")
        self.cyl(br * 1.14, 0.42 * L, (0, 0.12, 0), verts=12, rot=ROT_Y, material="bronze",
                 parent=B, name="Breech", bevel=0.02)
        self.cyl(br, L, (0, -0.55 * L, 0), verts=12, rot=ROT_Y, r2=br * 0.78, material="bronze",
                 parent=B, name="Barrel_Tube", bevel=0.01)
        for k in range(c["hoops"]):
            y = -0.1 - k * (0.8 * L / max(c["hoops"], 1))
            self.cyl(br * 1.09 - k * 0.02, 0.07, (0, y, 0), verts=12, rot=ROT_Y, material="iron",
                     parent=B, name=f"Hoop_{k}")
        tip = -1.05 * L - 0.08
        self.cyl(br * 0.78, 0.2, (0, tip, 0), verts=12, rot=ROT_Y, r2=br * 1.1, material="bronze",
                 parent=B, name="Muzzle_Flare", bevel=0.01)
        self.cyl(br * 0.55, 0.05, (0, tip - 0.1, 0), verts=12, rot=ROT_Y, material="bore",
                 parent=B, name="Bore")
        if c["horns"]:
            for s in (-1, 1):
                self.cyl(0.07, 0.32, (s * 0.24, 0.28, 0.14), verts=6, r2=0.0,
                         rot=(math.radians(-60), s * math.radians(35), 0), material="bronze",
                         parent=B, name=f"Horn_{'L' if s < 0 else 'R'}")
        self.empty("Muzzle", (0, tip - 0.14, 0), parent=B)

    def t_gatling(self):
        self.turret_mount()
        self.cheeks(0.38, size=(0.1, 0.66, 0.46))
        B = self.barrel_node((0, 0.05, 0.55))
        self.cyl(0.06, 0.86, (0, 0, 0), rot=(0, math.radians(90), 0), material="iron",
                 parent=B, name="Trunnion")
        # Zahnrad-/Antriebsgehäuse
        self.cyl(0.27, 0.34, (0, 0.14, 0), verts=12, rot=ROT_Y, material="bronze",
                 parent=B, name="GearHousing", bevel=0.02)
        for i in range(14):
            a = i * 2 * math.pi / 14
            self.box((0.07, 0.12, 0.07), (math.cos(a) * 0.3, 0.06, math.sin(a) * 0.3), (0, a, 0),
                     material="iron", parent=B, name=f"GearTooth_{i}")
        self.cyl(0.12, 0.12, (0, 0.36, 0), verts=8, rot=ROT_Y, material="iron", parent=B, name="GearCap")
        # Rotierendes Laufbündel
        S = self.empty("Spin", (0, 0, 0), parent=B)
        for i in range(6):
            a = i * math.pi / 3
            x, z = math.cos(a) * 0.14, math.sin(a) * 0.14
            self.cyl(0.058, 1.08, (x, -0.58, z), verts=8, rot=ROT_Y, material="iron",
                     parent=S, name=f"SpinBarrel_{i}")
            self.cyl(0.035, 0.03, (x, -1.12, z), verts=8, rot=ROT_Y, material="bore",
                     parent=S, name=f"SpinBore_{i}")
        for k, y in enumerate((-0.12, -0.55, -1.0)):
            self.cyl(0.23 if k != 1 else 0.21, 0.06, (0, y, 0), verts=12, rot=ROT_Y,
                     material="bronze" if k == 2 else "iron", parent=S, name=f"Clamp_{k}", bevel=0.01)
        self.cyl(0.07, 1.0, (0, -0.55, 0), verts=8, rot=ROT_Y, material="bronze", parent=S, name="SpinAxle")
        self.empty("Muzzle", (0, -1.18, 0), parent=B)
        # Munitionstrommel seitlich
        T = self.turret
        self.cyl(0.25, 0.3, (-0.7, 0.12, 0.5), verts=12, rot=(0, math.radians(90), 0),
                 material="bronze", parent=T, name="AmmoDrum", bevel=0.02)
        for s in (-1, 1):
            self.cyl(0.27, 0.05, (-0.7 + s * 0.13, 0.12, 0.5), verts=12, rot=(0, math.radians(90), 0),
                     material="iron", parent=T, name=f"AmmoDrumRim_{s}")
        self.box((0.3, 0.14, 0.1), (-0.48, 0.05, 0.58), (0, -0.3, 0), material="iron",
                 parent=T, name="AmmoFeed")

    def t_mortar(self):
        self.turret_mount()
        self.cheeks(0.52, size=(0.16, 0.8, 0.62), z=0.5)
        B = self.barrel_node((0, 0.05, 0.66))
        self.cyl(0.1, 1.22, (0, 0, 0), rot=(0, math.radians(90), 0), material="iron",
                 parent=B, name="Trunnion")
        self.cyl(0.4, 0.46, (0, 0.12, 0), verts=12, rot=ROT_Y, material="iron",
                 parent=B, name="Breech", bevel=0.03)
        self.cyl(0.4, 0.24, (0, 0.46, 0), verts=12, rot=ROT_Y, r2=0.16, material="iron",
                 parent=B, name="Breech_Cap", bevel=0.02)
        self.cyl(0.37, 0.62, (0, -0.4, 0), verts=12, rot=ROT_Y, r2=0.43, material="bronze",
                 parent=B, name="Barrel_Tube", bevel=0.01)
        self.cyl(0.395, 0.07, (0, -0.28, 0), verts=12, rot=ROT_Y, material="rune",
                 parent=B, name="RuneBand")
        for k, y in enumerate((-0.12, -0.5)):
            self.cyl(0.41 + k * 0.03, 0.08, (0, y, 0), verts=12, rot=ROT_Y, material="iron",
                     parent=B, name=f"Hoop_{k}")
        self.cyl(0.49, 0.12, (0, -0.74, 0), verts=12, rot=ROT_Y, material="bronze",
                 parent=B, name="Muzzle_Lip", bevel=0.02)
        self.cyl(0.32, 0.05, (0, -0.79, 0), verts=12, rot=ROT_Y, material="bore_dark",
                 parent=B, name="Bore")
        # Hammer-Embleme seitlich am Verschluss
        for s in (-1, 1):
            n = "L" if s < 0 else "R"
            self.box((0.05, 0.1, 0.32), (s * 0.43, 0.12, 0.0), material="bronze", parent=B,
                     name=f"Hammer_Handle_{n}")
            self.box((0.06, 0.26, 0.12), (s * 0.44, 0.12, 0.16), material="bronze", parent=B,
                     name=f"Hammer_Head_{n}", bevel=0.01)
        self.empty("Muzzle", (0, -0.84, 0), parent=B)

    def furnace(self):
        c, T = self.cfg, self.turret
        if not c["furnace"]:
            return
        big = c["turret"] == "mortar"
        y = 0.62 if big else 0.48
        w, h = (0.6, 0.46) if big else (0.46, 0.36)
        self.box((w, 0.3, h), (0, y, 0.2 + h / 2 + 0.03), material="iron", parent=T,
                 name="Furnace", bevel=0.04)
        self.box((w * 0.65, 0.02, h * 0.45), (0, y + 0.155, 0.2 + h * 0.45), material="ember",
                 parent=T, name="Furnace_Grate")
        for k in range(3):
            self.box((0.035, 0.03, h * 0.5), ((k - 1) * w * 0.22, y + 0.165, 0.2 + h * 0.45),
                     material="iron", parent=T, name=f"Grate_Bar_{k}")
        for k in range(c["chimneys"]):
            x = 0.13 if c["chimneys"] == 1 else (-0.16 + 0.32 * k)
            ch = 0.4 + (0.1 if big else 0)
            self.cyl(0.07, ch, (x, y + 0.04, 0.2 + h + ch / 2), verts=6, material="iron",
                     parent=T, name=f"Chimney_{k}")
            self.cyl(0.1, 0.06, (x, y + 0.04, 0.2 + h + ch), verts=6, material="bronze",
                     parent=T, name=f"Chimney_Cap_{k}")


def build_variant(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cfg = dict(BASE, **VARIANTS[variant])
    b = Builder(cfg, random.Random(7))
    b.build(variant)
    path = os.path.join(OUT, f"cannon_tower_{variant}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh(); me.calc_loop_triangles()
            tris += len(me.loop_triangles); o.evaluated_get(dg).to_mesh_clear()
    print(f"EXPORTED {variant}: {path} ({tris} tris)")


if __name__ == "__main__":
    for v in VARIANTS:
        build_variant(v)
