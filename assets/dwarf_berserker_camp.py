"""
Zwergenberserkerwall – Kriegshorn-Lager (hält Gegner auf dem Weg fest)

  berserker_camp_lvl1.glb, _lvl2, _lvl3
  berserker_camp_ironwall.glb   Spezialisierung „Eisenwall“ (länger festhalten)
  berserker_camp_bloodrage.glb  Spezialisierung „Blutrausch“ (Schaden an festgehaltenen Gegnern)

Aufbau / Ausrichtung:
  - Ursprung = Wegmitte an der Sperre. Der Weg läuft entlang X (Gegner kommen von +X),
    das Lager steht seitlich daneben (in Godot auf der -Z-Seite). PATH_W = Wegbreite.
  - Exportiert im Zustand „Festhalten“ mit beiden Trupps sichtbar – Zustände per Sichtbarkeit schalten:

Nodes für Godot:
  Barricade     -> Sturmpfahl-Sperre. rotation.y = 0: quer über dem Weg (Festhalten)
                   rotation.y = -90°: am Wegrand (offen). Pivot sitzt am Wegrand.
  Squad_Fight   -> Berserker vor der Sperre (nur beim Festhalten sichtbar)
  Squad_Idle    -> Berserker im Lager (nur wenn offen sichtbar)
  Berserker_N   -> einzelne Figuren (für Wippen/Schlag-Animation per Tween)
  RageAura      -> Wutring auf dem Weg (beim Festhalten sichtbar, pulsieren lassen)
  HornBlast     -> Leuchten am Kriegshorn (beim Auslösen kurz einblenden)
  HoldPoint     -> Position, an der Gegner stoppen (vor der Sperre)
"""
import bpy, math, os, random
from mathutils import Vector
import dwarf_towers as dt
from berserker_concepts import SceneBuilder

OUT = os.path.dirname(os.path.abspath(__file__))
PATH_W = 2.4

CAMP_BASE = dict(n_fight=3, pal_n=15, pal_r=1.05, pal_h=0.95, pal_iron=False, horn=2, braziers=1,
                 stakes=6, iron_bands=True, iron_tips=True, mantlets=False, double_log=False,
                 left="shield", banner_rune=True, trophies=False, totem=False, aura_strength=3.0,
                 rune_color="#ffc53a", paint_strength=5.0)
CAMP_VARIANTS = {
    "lvl1": dict(n_fight=1, pal_n=9, pal_r=0.8, pal_h=0.75, horn=0, braziers=0, stakes=4, iron_bands=False,
                 iron_tips=False, banner_rune=False, aura_strength=1.8),
    "lvl2": dict(n_fight=2, pal_n=12, pal_r=0.95, pal_h=0.85, horn=1, braziers=1, iron_tips=False,
                 aura_strength=2.4),
    "lvl3": dict(),
    "ironwall": dict(n_fight=3, pal_n=17, pal_r=1.15, pal_h=1.05, pal_iron=True, braziers=2, mantlets=True,
                     double_log=True, left="tower", rune_color="#ffe08a", aura_strength=3.0),
    "bloodrage": dict(n_fight=4, pal_n=15, pal_r=1.1, braziers=2, left="axe", trophies=True, totem=True,
                      rune_color="#ff8a3a", paint_strength=8.0, aura_strength=5.0),
}


class CampBuilder(SceneBuilder):
    def __init__(self, cfg, rng):
        super().__init__(rng, True)
        M = self.M
        M["rune"] = dt.mat("Rune_Glow", cfg["rune_color"], emit=cfg["rune_color"], strength=6.0)
        M["paint"].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = cfg["paint_strength"]
        M["aura"].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = cfg["aura_strength"]
        M["paint_idle"] = dt.mat("WarPaint_Idle", "#8a1c14", emit="#ff2010", strength=0.4)
        M["eyes_idle"] = dt.mat("Eyes_Idle", "#2a2420", rough=0.8)
        M["iron_plate"] = dt.mat("Iron_Plate", "#3c3f44", metal=0.6, rough=0.85)

    def calm(self, root):
        """Ruhe-Figuren: Bemalung gedimmt, Augen aus."""
        for o in root.children_recursive:
            if o.type == "MESH" and o.data.materials:
                n = o.data.materials[0].name
                if n.startswith("WarPaint"):
                    o.data.materials[0] = self.M["paint_idle"]
                elif n.startswith("RageEyes"):
                    o.data.materials[0] = self.M["eyes_idle"]

    def brazier(self, loc, name, parent):
        x, y, z = loc
        for k in range(3):
            a = k * 2 * math.pi / 3
            self.stick((x + math.cos(a) * 0.15, y + math.sin(a) * 0.15, 0), (x, y, z - 0.08), 0.03, 0.03, "iron",
                       parent, f"{name}_Leg{k}")
        self.cyl(0.13, 0.1, (x, y, z), verts=8, r2=0.17, material="iron", parent=parent, name=f"{name}_Bowl")
        for k in range(3):
            self.cone_dir((x + (k - 1) * 0.05, y, z + 0.04), (0, 0, 1), 0.2 - k * 0.03, 0.06, "ember", parent,
                          f"{name}_Fire{k}", verts=5)

    # ------------------------------------------------------------ Sperre
    def barricade(self, c, root):
        L = PATH_W + 0.2
        B = self.empty("Barricade", (0, PATH_W / 2 + 0.1, 0), parent=root)
        logs = [0.32] if not c["double_log"] else [0.22, 0.46]
        for k, z in enumerate(logs):
            self.stick((0, 0.05, z), (0, -L, z), 0.15, 0.15, "wood", B, f"Barricade_Log{k}")
        n = c["stakes"]
        for i in range(n):
            y = -L * (i + 0.5) / n
            for s in (-1, 1):
                d = Vector((s, 0, 0.9)).normalized()
                base = Vector((0, y, 0.34)) - d * 0.32
                self.cone_dir(base, d, 0.78, 0.05, "wood_light", B, f"Stake_{i}_{s}", verts=5)
                if c["iron_tips"]:
                    self.cone_dir(base + d * 0.66, d, 0.16, 0.035, "iron", B, f"StakeTip_{i}_{s}", verts=4)
                if c["trophies"] and i % 2 == 0 and s == 1:
                    tip = base + d * 0.78
                    h = self.ico(0.09, tuple(tip - d * 0.12), "iron", B, f"Trophy_{i}")
                    h.scale = (1, 1, 0.7)
                    self.cone_dir(tip - d * 0.12 + Vector((0, 0.07, 0.02)), (0, 1, 0.6), 0.12, 0.03, "bone", B,
                                  f"TrophyHorn_{i}", verts=4)
            if c["iron_bands"]:
                for z in logs:
                    self.box((0.17, 0.05, 0.17), (0, y, z), material="iron", parent=B, name=f"Band_{i}_{z}")
            if c["mantlets"] and i < n - 1:
                yy = -L * (i + 1) / n
                self.box((0.06, L / n * 0.8, 0.34), (0.16, yy, 0.42), rot=(0, -0.35, 0), material="iron_plate", parent=B,
                         name=f"Plate_{i}")
                self.box((0.02, 0.035, 0.16), (0.195, yy, 0.43), rot=(0, -0.35, 0), material="rune", parent=B,
                         name=f"PlateRune_{i}")
        # Böcke an den Enden
        for k, y in enumerate((-0.15, -L + 0.15)):
            for s in (-1, 1):
                self.stick((s * 0.2, y, 0), (0, y, logs[0] + 0.05), 0.06, 0.06, "wood", B, f"Trestle_{k}_{s}")
        return B

    # ------------------------------------------------------------ Lager
    def camp(self, c, root, variant):
        rng = self.rng
        cy = PATH_W / 2 + 0.2 + c["pal_r"]
        # Palisade
        n = c["pal_n"]
        for i in range(n):
            a = math.radians(-12 + i * 204 / (n - 1))
            x, y = math.cos(a) * c["pal_r"], cy + math.sin(a) * c["pal_r"]
            h = c["pal_h"] * rng.uniform(0.9, 1.1)
            self.cyl(0.075, h, (x, y, h / 2), verts=7, material="wood", parent=root, name=f"Palisade_{i}")
            self.cyl(0.075, 0.18, (x, y, h + 0.09), verts=7, r2=0.0, material="wood_light", parent=root,
                     name=f"PalisadeTip_{i}")
            if c["pal_iron"]:
                for z in (0.2, h - 0.15):
                    self.cyl(0.082, 0.05, (x, y, z), verts=7, material="iron", parent=root, name=f"PalisadeBand_{i}_{z}")
            if c["trophies"] and i % 4 == 1:
                hh = self.ico(0.09, (x, y, h + 0.08), "iron", root, f"PalisadeTrophy_{i}")
                hh.scale = (1, 1, 0.7)
        # Banner
        bh = 1.6 + 0.25 * (variant != "lvl1")
        self.stick((0, cy + 0.3, 0), (0, cy + 0.3, bh + 0.15), 0.07, 0.07, "wood", root, "BannerPole")
        self.stick((-0.28, cy + 0.3, bh + 0.05), (0.28, cy + 0.3, bh + 0.05), 0.04, 0.04, "wood", root, "BannerBar")
        self.box((0.52, 0.03, 0.8), (0, cy + 0.28, bh - 0.38), material="banner_r", parent=root, name="Banner")
        if c["banner_rune"]:
            self.rune((0, cy + 0.26, bh - 0.35), -math.pi / 2, 0.75, root, "Banner")
        # Kriegshorn
        if c["horn"]:
            sc = 0.75 if c["horn"] == 1 else 1.0
            hx, hy, hz = 0.55, cy + 0.05, 0.9 * sc
            H = self.empty("WarHorn", (hx, hy, hz), parent=root)
            for k in range(3):
                self.stick(((k - 1) * 0.25 * sc, 0, -hz), (0, 0, -0.05), 0.04, 0.04, "wood", H, f"HornStand{k}")
            pts = [Vector((0.25, 0, 0.05)), Vector((0.05, -0.05, 0)), Vector((-0.2, -0.15, 0.08)),
                   Vector((-0.35, -0.3, 0.3))]
            pts = [p * sc for p in pts]
            rads = [r * sc for r in (0.05, 0.08, 0.12, 0.17)]
            for k in range(3):
                d = pts[k + 1] - pts[k]
                self.cone_dir(pts[k], d, d.length + 0.03, rads[k], "bone", H, f"Horn_{k}", verts=8, r2=rads[k + 1])
            for k in range(2):
                o = self.ico(rads[k + 1] + 0.012, tuple(pts[k + 1]), "bronze", H, f"HornRing{k}")
                o.scale = (1, 1, 0.35)
            hb = self.empty("HornBlast", tuple(pts[3] + Vector((-0.05, -0.08, 0.06))), parent=H)
            self.ico(0.12 * sc, (0, 0, 0), "rune", hb, "HornBlast_Glow")
        # Feuerschalen
        spots = [(-0.6, cy - 0.15), (0.75, cy + 0.6)]
        for k in range(c["braziers"]):
            self.brazier((spots[k][0], spots[k][1], 0.55), f"Brazier{k}", root)
        # Totem (Blutrausch)
        if c["totem"]:
            tx, ty = -0.45, cy + 0.55
            self.cyl(0.1, 1.5, (tx, ty, 0.75), verts=6, material="wood", parent=root, name="Totem")
            for k, z in enumerate((0.55, 0.95, 1.35)):
                self.box((0.24, 0.24, 0.16), (tx, ty, z), rot=(0, 0, k * 0.4), material="wood_light", parent=root,
                         name=f"TotemBlock{k}")
                self.box((0.25, 0.02, 0.04), (tx, ty - 0.12, z + 0.02), rot=(0, 0, k * 0.4), material="paint",
                         parent=root, name=f"TotemPaint{k}")
            h = self.ico(0.16, (tx, ty, 1.58), "iron", root, "TotemHelm")
            h.scale = (1, 1, 0.75)
            for s in (-1, 1):
                self.cone_dir((tx + s * 0.13, ty, 1.6), (s, 0.1, 0.8), 0.28, 0.05, "bone", root, f"TotemHorn{s}", verts=5)
        return cy

    # ------------------------------------------------------------ Trupps
    def squads(self, c, root, cy):
        beards = ["beard_r", "beard_b", "beard_g", "beard_r"]
        F = self.empty("Squad_Fight", (0, 0, 0), parent=root)
        n = c["n_fight"]
        for i in range(n):
            y = -PATH_W / 2 + PATH_W * (i + 0.5) / n
            self.dwarf(f"Berserker_F{i}", (0.42 + self.rng.uniform(-0.03, 0.03), y, 0), math.radians(90), "fight",
                       beards[i], left=c["left"], parent=F)
        I = self.empty("Squad_Idle", (0, 0, 0), parent=root)
        spots = [(-0.35, cy + 0.15, -1.6), (0.25, cy + 0.55, 3.6), (0.4, cy - 0.45, -0.4), (-0.15, cy - 0.5, 0.3)]
        for i in range(n):
            x, y, yaw = spots[i]
            d = self.dwarf(f"Berserker_I{i}", (x, y, 0), yaw, "idle", beards[i], left=c["left"], parent=I)
        self.calm(I)
        # Wutaura + Haltepunkt
        a = self.ring((0.95, 0, 0.01), 1.0, "aura", "RageAura")
        a.parent = root
        a.scale = (0.85, PATH_W / 2 * 0.95, 0.3)
        self.empty("HoldPoint", (0.9, 0, 0), parent=root)


def build_variant(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    c = dict(CAMP_BASE, **CAMP_VARIANTS[variant])
    b = CampBuilder(c, random.Random(17))
    root = b.empty(f"BerserkerCamp_{variant}", (0, 0, 0))
    b.root = root
    b.barricade(c, root)
    cy = b.camp(c, root, variant)
    b.squads(c, root, cy)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"berserker_camp_{variant}.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    print("EXPORTED", variant)


if __name__ == "__main__":
    for v in CAMP_VARIANTS:
        build_variant(v)
