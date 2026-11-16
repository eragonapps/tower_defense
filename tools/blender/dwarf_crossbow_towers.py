"""
Zwergen-Armbrustturm – nutzt den Basis-Builder aus dwarf_towers.py

  crossbow_tower_lvl1.glb, _lvl2, _lvl3
  crossbow_tower_rapid.glb     Spezialisierung „Schnellfeuer“ (Doppel-Repetierarmbrust)
  crossbow_tower_sniper.glb    Spezialisierung „Scharfschütze“ (schwere Armbrust mit Zielfernrohr)
  projectile_bolt.glb          Bolzen Stufe 1–3
  projectile_bolt_rapid.glb    leichter Bolzen (Schnellfeuer)
  projectile_bolt_sniper.glb   schwerer Runenbolzen (Scharfschütze)

Nodes für Godot (wie beim Kanonenturm):
  Turret   -> um Y drehen zum Zielen
  Barrel   -> um X kippen (Elevation) / Rückstoß
  Muzzle   -> Spawnpunkt des Bolzens
  Muzzle_Upper / Muzzle_Lower -> nur „rapid“: abwechselnd feuern
  Bolt*    -> eingelegter Bolzen; beim Schuss ausblenden, nach Nachladen einblenden
Schussrichtung -Z (Godot forward), Ursprung = Mitte Boden. Bolzen-Projektile fliegen -Z.
"""
import bpy, math, os, random
from mathutils import Vector, Quaternion
import dwarf_towers as dt

OUT = os.path.dirname(os.path.abspath(__file__))
OCT = dt.OCT

XB_BASE = dict(
    name_prefix="CrossbowTower", turret="crossbow", turret_r=0.6,
    rune_color="#3dff86", rune_strength=6.0, banner_color="#15301f",
    furnace=False, chimneys=0, bow_scale=1.3, stock_len=1.0, limb_mat="iron",
    limb_runes=True, mantlet=True, slits=True, scope=False, twin=False, elev=6,
)
XB_VARIANTS = {
    "lvl1": dict(rows=3, r_bot=0.96, r_top=0.84, plinth_r=1.2, bands=("low",), rune_angles=(-1,),
                 rune_strength=3.5, banner=False, merlon_cap=None, corbels=False, turret_r=0.5,
                 bow_scale=1.0, limb_mat="wood", limb_runes=False, mantlet=False),
    "lvl2": dict(rows=4, r_bot=1.02, r_top=0.87, plinth_r=1.28, rune_angles=(-1, 5),
                 rune_strength=4.5, turret_r=0.56, bow_scale=1.15, limb_runes=False, mantlet=False),
    "lvl3": dict(),
    "rapid": dict(twin=True, bow_scale=0.95, rune_color="#a8ff3d", rune_strength=7.0, elev=4),
    "sniper": dict(rows=6, r_bot=1.04, r_top=0.84, plinth_r=1.32, bow_scale=1.45, stock_len=1.3,
                   scope=True, rune_color="#3dffc0", rune_strength=7.0, elev=3, mantlet=False),
}


class XBBuilder(dt.Builder):
    def __init__(self, cfg, rng):
        super().__init__(cfg, rng)
        self.M["wood"] = dt.mat("Wood_Dark", "#4a3324", rough=0.85)
        self.M["wood_light"] = dt.mat("Wood", "#6b4a32", rough=0.8)
        self.M["string"] = dt.mat("Bowstring", "#1d1b18", rough=0.9)
        self.M["feather"] = dt.mat("Fletching", "#5a1414", rough=0.9)
        self.M["lens"] = dt.mat("Scope_Lens", "#2a6650", emit=cfg["rune_color"], strength=5.0)
        self.M["slit"] = dt.mat("Arrow_Slit", "#060606", rough=1.0)

    def stick(self, p0, p1, w, h, material, parent, name):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        o = self.box((w, h, d.length), (p0 + p1) / 2, material=material, parent=parent, name=name)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
        return o

    # ---------------------------------------------------------------- Turm
    def build(self, variant):
        root = super().build(variant)
        c = self.cfg
        if c["slits"]:   # Schießscharten auf den freien Seiten (Banner vorne, Runensteine diagonal)
            Z0, ROW_H = 0.34, 0.38
            H = c["rows"] * ROW_H
            for k, a in enumerate((0, math.pi / 2, math.pi)):
                t = 0.62
                R = c["r_bot"] + (c["r_top"] - c["r_bot"]) * t + 0.035
                z = Z0 + H * t
                self.box((0.05, 0.07, 0.42), (math.cos(a) * R, math.sin(a) * R, z), (0, 0, a),
                         material="slit", parent=root, name=f"ArrowSlit_{k}")
                self.box((0.05, 0.22, 0.05), (math.cos(a) * R, math.sin(a) * R, z), (0, 0, a),
                         material="slit", parent=root, name=f"ArrowSlitCross_{k}")
                self.box((0.06, 0.2, 0.52), (math.cos(a) * (R - 0.012), math.sin(a) * (R - 0.012), z),
                         (0, 0, a), material="iron", parent=root, name=f"ArrowSlitFrame_{k}")
        return root

    # ---------------------------------------------------------------- Armbrust
    def bow(self, B, x, s, tag, bolt_name):
        c = self.cfg
        L = c["stock_len"]
        lm = c["limb_mat"]
        sl = 1.0 * s * L
        # Schaft + Schiene
        self.box((0.11 * s, sl, 0.11 * s), (x, 0.42 * s - sl / 2, 0), material="wood", parent=B,
                 name=f"Stock{tag}", bevel=0.012)
        self.box((0.05 * s, sl * 0.9, 0.025 * s), (x, 0.42 * s - sl / 2, 0.066 * s), material="iron",
                 parent=B, name=f"Rail{tag}")
        front = 0.42 * s - sl
        # Bügelblock
        self.box((0.2 * s, 0.13 * s, 0.15 * s), (x, front + 0.07 * s, 0), material="iron", parent=B,
                 name=f"ProdMount{tag}", bevel=0.015)
        # Wurfarme (nach hinten geschwungen)
        theta = math.radians(22)
        tips = []
        for side in (-1, 1):
            n = "L" if side < 0 else "R"
            start = Vector((x + side * 0.09 * s, front + 0.07 * s, 0))
            dirv = Vector((side * math.cos(theta), math.sin(theta), 0))
            ln = 0.6 * s
            tip = start + dirv * ln
            tips.append(tip)
            self.stick(start, tip, 0.075 * s, 0.06 * s, lm, B, f"Limb{tag}_{n}")
            self.stick(start + dirv * ln * 0.55, tip + dirv * 0.02 * s, 0.09 * s, 0.075 * s, "bronze", B,
                       f"LimbCap{tag}_{n}")
            if c["limb_runes"]:
                off = Vector((0, -0.035 * s, 0))
                self.stick(start + dirv * 0.12 * s + off, start + dirv * 0.48 * s + off, 0.018 * s,
                           0.012 * s, "rune", B, f"LimbRune{tag}_{n}")
        # Sehne (gespannt zur Nuss)
        nut = Vector((x, front + 0.48 * s, 0.07 * s))
        for i, tip in enumerate(tips):
            self.stick(tip, nut, 0.014 * s, 0.014 * s, "string", B, f"String{tag}_{i}")
        self.box((0.09 * s, 0.06 * s, 0.05 * s), tuple(nut), material="bronze", parent=B, name=f"Nut{tag}")
        # Eingelegter Bolzen
        Bo = self.empty(bolt_name, (x, 0, 0.09 * s), parent=B)
        b_back, b_front = nut.y - 0.02 * s, front - 0.12 * s
        self.stick((0, b_back, 0), (0, b_front, 0), 0.026 * s, 0.026 * s, "wood_light", Bo, f"BoltShaft{tag}")
        self.cyl(0.04 * s, 0.11 * s, (0, b_front - 0.05 * s, 0), verts=4, r2=0.0, rot=dt.ROT_Y,
                 material="iron", parent=Bo, name=f"BoltHead{tag}")
        for k in range(2):
            self.box((0.005 if k else 0.07 * s, 0.1 * s, 0.07 * s if k else 0.005),
                     (0, b_back + 0.03 * s, 0), material="feather", parent=Bo, name=f"BoltFletch{tag}_{k}")
        # Spannwinde hinten
        wy = 0.42 * s + 0.02 * s
        self.cyl(0.065 * s, 0.26 * s, (x, wy, -0.01 * s), verts=8, rot=(0, math.radians(90), 0),
                 material="iron", parent=B, name=f"Winch{tag}")
        for side in (-1, 1):
            hx = x + side * 0.15 * s
            self.box((0.03 * s, 0.03 * s, 0.16 * s), (hx, wy, -0.06 * s), material="bronze", parent=B,
                     name=f"Crank{tag}_{side}")
            self.cyl(0.022 * s, 0.09 * s, (hx + side * 0.04 * s, wy, -0.14 * s), verts=6,
                     rot=(0, math.radians(90), 0), material="wood", parent=B, name=f"CrankGrip{tag}_{side}")
        return Vector((x, b_front - 0.12 * s, 0.09 * s))

    def t_crossbow(self):
        c, T = self.cfg, self.turret
        self.turret_mount()
        s = c["bow_scale"]
        LIFT = 0.32   # Armbrust über die Zinnen heben
        top = 0.28 + LIFT + 0.05
        self.cyl(0.17, top - 0.28, (0, 0, 0.28 + (top - 0.28) / 2), rot=(0, 0, OCT), material="iron",
                 parent=T, name="Pedestal", bevel=0.02)
        self.cyl(0.24, 0.06, (0, 0, top), rot=(0, 0, OCT), material="bronze", parent=T,
                 name="Pedestal_Cap", bevel=0.01)
        if c["twin"]:
            # Doppelarmbrust übereinander (Repetier-Mechanik)
            self.cheeks(0.3, size=(0.1, 0.4, 0.5), z=0.5 + LIFT)
            B = self.barrel_node((0, 0.05, 0.56 + LIFT))
            self.cyl(0.05, 0.7, (0, 0, 0), rot=(0, math.radians(90), 0), material="iron", parent=B,
                     name="Trunnion")
            pts = []
            for n, z in (("Lower", -0.02), ("Upper", 0.2)):
                E = self.empty(f"Bow_{n}", (0, 0, z), parent=B)
                p = self.bow(E, 0.0, s, f"_{n}", f"Bolt_{n}")
                self.empty(f"Muzzle_{n}", tuple(p), parent=E)
                pts.append(p + Vector((0, 0, z)))
            self.empty("Muzzle", tuple((pts[0] + pts[1]) / 2), parent=B)
            # Magazin oben
            self.box((0.1, 0.36, 0.24), (0, -0.08, 0.42), material="wood", parent=B, name="Magazine",
                     bevel=0.01)
            self.box((0.12, 0.38, 0.03), (0, -0.08, 0.55), material="iron", parent=B, name="MagazineCap")
            for k in range(3):
                self.box((0.022, 0.022, 0.02), ((k - 1) * 0.026, -0.27, 0.48), material="feather",
                         parent=B, name=f"MagazineBolt_{k}")
            self.box((0.025, 0.36, 0.015), (0, -0.08, 0.36), material="rune", parent=B, name="MagazineRune")
            # Zahnrad-Spannmechanik seitlich
            for side in (-1, 1):
                gx = side * 0.13
                self.cyl(0.13, 0.05, (gx, 0.22, 0.1), verts=12, rot=(0, math.radians(90), 0),
                         material="bronze", parent=B, name=f"Gear_{side}", bevel=0.01)
                for i in range(10):
                    a = i * 2 * math.pi / 10
                    self.box((0.045, 0.045, 0.045), (gx, 0.22 + math.cos(a) * 0.14, 0.1 + math.sin(a) * 0.14),
                             (a, 0, 0), material="iron", parent=B, name=f"GearTooth_{side}_{i}")
        else:
            B = self.barrel_node((0, 0.05, 0.42 + 0.12 * s + LIFT))
            self.cheeks(0.12 + 0.08 * s, size=(0.08, 0.5 * s, 0.24 + 0.24 * s), z=0.3 + 0.12 * s + LIFT)
            self.cyl(0.045, 0.32 + 0.16 * s, (0, 0, 0), rot=(0, math.radians(90), 0), material="iron",
                     parent=B, name="Trunnion")
            p = self.bow(B, 0.0, s, "", "Bolt")
            self.empty("Muzzle", tuple(p), parent=B)
            if c["scope"]:
                L = 0.62
                y0 = -0.05
                self.cyl(0.05, L, (0, y0, 0.24), verts=8, rot=dt.ROT_Y, material="bronze", parent=B,
                         name="Scope", bevel=0.005)
                for k, yy in enumerate((y0 - L / 2, y0 + L / 2)):
                    self.cyl(0.068, 0.08, (0, yy, 0.24), verts=8, rot=dt.ROT_Y, material="bronze",
                             parent=B, name=f"ScopeBell_{k}")
                    self.cyl(0.052, 0.012, (0, yy + (-0.042 if k == 0 else 0.042), 0.24), verts=8,
                             rot=dt.ROT_Y, material="lens", parent=B, name=f"ScopeLens_{k}")
                for k, yy in enumerate((y0 - 0.15, y0 + 0.15)):
                    self.box((0.035, 0.04, 0.14), (0, yy, 0.16), material="iron", parent=B,
                             name=f"ScopeMount_{k}")
                # Stütze/Zweibein vorne
                for side in (-1, 1):
                    self.stick((side * 0.04, -0.75, -0.06), (side * 0.2, -0.75, -0.42), 0.035, 0.035,
                               "iron", B, f"Bipod_{side}")
        if c["mantlet"]:
            for side in (-1, 1):
                a = side * 0.35
                self.box((0.42, 0.06, 0.34), (side * 0.28, -0.5, 0.27), (0.15, 0, a), material="wood",
                         parent=T, name=f"Mantlet_{side}", bevel=0.01)
                self.box((0.46, 0.07, 0.04), (side * 0.28, -0.5, 0.42), (0.15, 0, a), material="iron",
                         parent=T, name=f"MantletRim_{side}")
                self.box((0.04, 0.075, 0.02), (side * 0.28, -0.505, 0.29), (0.15, 0, a), material="rune",
                         parent=T, name=f"MantletRune_{side}")


def build_variant(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cfg = dict(dt.BASE, **XB_BASE)
    cfg.update(XB_VARIANTS[variant])
    b = XBBuilder(cfg, random.Random(23))
    b.build(variant)
    path = os.path.join(OUT, f"crossbow_tower_{variant}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("EXPORTED", variant)


def build_bolts():
    specs = {
        "bolt": dict(s=1.0, head="iron", glow=False, rune="#3dff86"),
        "bolt_rapid": dict(s=0.8, head="iron", glow=True, rune="#a8ff3d"),
        "bolt_sniper": dict(s=1.35, head="bronze", glow=True, rune="#3dffc0"),
    }
    for name, sp in specs.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        cfg = dict(dt.BASE, **dict(XB_BASE, rune_color=sp["rune"]))
        b = XBBuilder(cfg, random.Random(1))
        s = sp["s"]
        R = b.empty(name.title().replace("_", ""), (0, 0, 0))
        b.stick((0, 0.3 * s, 0), (0, -0.25 * s, 0), 0.03 * s, 0.03 * s, "wood_light", R, "Shaft")
        b.cyl(0.05 * s, 0.14 * s, (0, -0.32 * s, 0), verts=4, r2=0.0, rot=dt.ROT_Y, material=sp["head"],
              parent=R, name="Head")
        b.cyl(0.03 * s, 0.04 * s, (0, -0.25 * s, 0), verts=6, rot=dt.ROT_Y, material="iron", parent=R,
              name="Ferrule")
        for k in range(3):
            a = k * 2 * math.pi / 3
            b.box((0.005, 0.13 * s, 0.06 * s), (math.cos(a) * 0.03 * s, 0.22 * s, math.sin(a) * 0.03 * s),
                  (0, -a + math.pi / 2, 0), material="feather", parent=R, name=f"Fletch_{k}")
        if sp["glow"]:
            if name == "bolt_sniper":
                for k in range(2):
                    b.stick((0, -0.2 * s, 0.017 * s if k else -0.017 * s), (0, 0.05 * s, 0.017 * s if k else -0.017 * s),
                            0.008 * s, 0.006 * s, "rune", R, f"RuneLine_{k}")
                b.cyl(0.02 * s, 0.1 * s, (0, -0.3 * s, 0), verts=4, r2=0.0, rot=dt.ROT_Y, material="rune",
                      parent=R, name="HeadGlow")
            else:
                T = b.empty("Tracer", (0, 0.3 * s, 0), parent=R)
                b.cyl(0.02 * s, 0.25 * s, (0, 0.125 * s, 0), verts=6, r2=0.0, rot=(-math.radians(90), 0, 0),
                      material="rune", parent=T, name="Tracer_Trail")
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"projectile_{name}.glb"),
                                  export_format="GLB", export_apply=True, export_yup=True)
        print("EXPORTED", name)


if __name__ == "__main__":
    for v in XB_VARIANTS:
        build_variant(v)
    build_bolts()
