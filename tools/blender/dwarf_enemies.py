"""
Gegner „Die Brut der Tiefe“ – düsteres Zwergen-Setting. Jede .glb enthält Animationen (AnimationPlayer):
  Walk  – Laufzyklus auf der Stelle (Schleife); Godot bewegt den Root entlang des Pfads
  Hit   – kurzes Zucken bei Treffer (einmalig)
  Death – Sterben, endet liegend (einmalig, danach queue_free / Ausblenden)
  Held  – Zerren gegen eine Sperre (Schleife, für die Berserkerwall)
  Cast  – nur Schamane: Heilzauber (HealRing auf dem Boden)

Blickrichtung -Z (Godot forward), Ursprung = Boden in der Mitte.
Gemeinsame Nodes: Body (ganzer Körper), HitPoint (Ziel für Projektile), HealthBarAnchor (über dem Kopf).
"""
import bpy, math, os, random, sys
from mathutils import Vector, Euler
import dwarf_towers as dt
from miner_concepts import MineBuilder

OUT = os.path.dirname(os.path.abspath(__file__))
R = math.radians
ROT_Y = dt.ROT_Y
TAU = 2 * math.pi


# ====================================================================== Builder
class EnemyBuilder(MineBuilder):
    def __init__(self, rng):
        super().__init__(rng)
        M = self.M
        def m(k, *a, **kw):
            M[k] = dt.mat(*a, **kw)
        m("rust", "Rust_Iron", "#6a4a34", metal=0.6, rough=0.75)
        m("undead", "Undead_Skin", "#7a8789", rough=0.8)
        m("ghost", "Undead_Glow", "#3aa8e0", emit="#3ab8ff", strength=3.5)
        m("corrupt", "Corrupt_Glow", "#5fbf2a", emit="#6aff2a", strength=2.6)
        m("troll", "Troll_Skin", "#56664f", rough=0.85)
        m("troll_dark", "Troll_Dark", "#3d4a39", rough=0.9)
        m("fur", "Rat_Fur", "#3b332e", rough=1.0)
        m("pink", "Rat_Skin", "#a8786e", rough=0.8)
        m("chitin", "Spider_Chitin", "#221d26", metal=0.2, rough=0.45)
        m("chitin_hi", "Spider_Mark", "#4a2c3e", rough=0.6)
        m("cape", "Royal_Cape", "#2b1d30", rough=0.95)
        m("gold_old", "Tarnished_Gold", "#9c7a32", metal=1.0, rough=0.5)
        m("beard_dead", "Beard_Dead", "#9aa4a6", rough=1.0)
        m("powder", "Powder_Blast", "#ffb040", emit="#ff8a20", strength=6.0)
        m("spark", "Fuse_Spark", "#ffd060", emit="#ffb030", strength=10.0)
        m("bone_w", "Bone_White", "#cfc6ae", rough=0.6)
        m("rope", "Rope", "#5c4a33", rough=1.0)
        m("worm_plate", "Worm_Plate", "#3e3a36", rough=0.8)
        m("worm_flesh", "Worm_Flesh", "#4b3a3a", rough=0.8)

    def eye(self, p, parent, name, mat, r=0.02):
        return self.ico(r, p, mat, parent, name)


def key(o, f, loc=None, rot=None, scale=None):
    if loc is not None:
        o.location = loc; o.keyframe_insert("location", frame=f)
    if rot is not None:
        o.rotation_euler = rot; o.keyframe_insert("rotation_euler", frame=f)
    if scale is not None:
        o.scale = (scale,) * 3 if isinstance(scale, (int, float)) else scale
        o.keyframe_insert("scale", frame=f)


class Rig:
    """Sammelt Gelenke + Grundpose; schreibt Zustände als NLA-Spuren."""
    def __init__(self):
        self.J = {}
        self.base = {}

    def add(self, name, obj):
        obj.rotation_mode = "XYZ"
        self.J[name] = obj
        return obj

    def snapshot(self):
        for n, o in self.J.items():
            self.base[n] = (tuple(o.location), tuple(o.rotation_euler), tuple(o.scale))

    def pose_base(self, f):
        for n, o in self.J.items():
            l, r, s = self.base[n]
            key(o, f, loc=l, rot=r, scale=s)

    def k(self, n, f, loc=None, rot=None, scale=None, dloc=None, drot=None):
        o = self.J[n]
        l0, r0, s0 = self.base[n]
        if dloc is not None:
            loc = tuple(a + b for a, b in zip(l0, dloc))
        if drot is not None:
            rot = tuple(a + b for a, b in zip(r0, drot))
        key(o, f, loc=loc, rot=rot, scale=scale)

    def push(self, state):
        for n, o in self.J.items():
            ad = o.animation_data
            if ad and ad.action:
                act = ad.action; act.name = f"{state}_{n}"
                tr = ad.nla_tracks.new(); tr.name = state
                tr.strips.new(state, 1, act)
                ad.action = None

    def restore(self):
        for n, o in self.J.items():
            o.location, o.rotation_euler, o.scale = self.base[n]


# ====================================================================== Zweibeiner
def biped_rig(b, name, hip_h, hip_w, sh_z, sh_w, neck_z, height):
    rig = Rig()
    root = b.empty(name, (0, 0, 0))
    Bd = rig.add("Body", b.empty("Body", (0, 0, 0), parent=root))
    for s, n in ((-1, "Leg_L"), (1, "Leg_R")):
        rig.add(n, b.empty(n, (s * hip_w, 0, hip_h), parent=Bd))
    H = rig.add("Hips", b.empty("Hips", (0, 0, hip_h), parent=Bd))
    rig.add("Head", b.empty("Head", (0, 0, neck_z), parent=H))
    for s, n in ((-1, "Shoulder_L"), (1, "Shoulder_R")):
        rig.add(n, b.empty(n, (s * sh_w, 0, sh_z), parent=H))
    b.empty("HitPoint", (0, 0, sh_z * 0.5), parent=H)
    b.empty("HealthBarAnchor", (0, 0, height + 0.18), parent=root)
    rig.root, rig.hip_h = root, hip_h
    return rig


def limb_leg(b, J, n, length, w, mat, foot_mat=None, foot=0.06):
    b.box((w, w * 1.15, length), (0, 0, -length / 2), material=mat, parent=J[n], name=f"{n}_Mesh")
    b.box((w * 1.1, w * 1.7, foot), (0, -w * 0.3, -length + foot / 2), material=foot_mat or mat, parent=J[n],
          name=f"{n}_Foot")


def limb_arm(b, J, n, hand, w, mat, fist_mat=None, fist=0.045):
    hand = Vector(hand)
    b.stick((0, 0, 0), hand, w, w, mat, J[n], f"{n}_Arm")
    b.ico(fist, tuple(hand), fist_mat or mat, J[n], f"{n}_Hand")
    return hand


def biped_anims(rig, p):
    """p: period, stride, arm, bob, lean, sway, extras(state, f_start, f_end)"""
    J = rig.J
    hip = rig.base["Hips"][0]
    extra = p.get("extras", lambda *a: None)
    lean = p["lean"]
    # Grundhaltung inkl. Vorbeugen
    def base(f):
        rig.pose_base(f)
        rig.k("Hips", f, drot=(lean, 0, 0))
        rig.k("Head", f, drot=(-lean * 0.6, 0, 0))

    # ---- Walk
    P = p["period"]
    base(1); base(P + 1)
    for i in range(9):
        f = 1 + round(i * P / 8)
        ph = TAU * i / 8
        s = math.sin(ph)
        rig.k("Leg_L", f, drot=(p["stride"] * s, 0, 0))
        rig.k("Leg_R", f, drot=(-p["stride"] * s, 0, 0))
        rig.k("Shoulder_L", f, drot=(-p["arm"] * s, 0, 0))
        rig.k("Shoulder_R", f, drot=(p["arm"] * s, 0, 0))
        rig.k("Hips", f, dloc=(0, 0, p["bob"] * math.cos(2 * ph)), drot=(lean, 0, p["sway"] * s))
    extra("Walk", 1, P + 1)
    rig.push("Walk")

    # ---- Hit
    base(1); base(9)
    rig.k("Hips", 3, drot=(lean - 0.4, 0, 0.1))
    rig.k("Head", 3, drot=(-0.35, 0, -0.15))
    rig.k("Shoulder_L", 3, drot=(0.5, -0.3, 0)); rig.k("Shoulder_R", 3, drot=(0.5, 0.3, 0))
    rig.k("Body", 3, dloc=(0, 0.04, 0))
    extra("Hit", 1, 9)
    rig.push("Hit")

    # ---- Death
    base(1); base(25)
    lay = p.get("lay", 0.12)
    rig.k("Hips", 5, drot=(lean - 0.35, 0, 0))
    rig.k("Body", 5, dloc=(0, 0.03, 0))
    for f, ang, z in ((13, -1.5, lay), (17, -1.38, lay + 0.04), (25, -1.52, lay)):
        rig.k("Body", f, loc=(0, 0.05, z), rot=(ang, 0, 0.15))
        rig.k("Hips", f, drot=(0, 0, 0))
        rig.k("Leg_L", f, drot=(-0.5, 0.2, 0)); rig.k("Leg_R", f, drot=(-0.3, -0.25, 0))
        rig.k("Shoulder_L", f, drot=(-0.4, -1.1, 0)); rig.k("Shoulder_R", f, drot=(-0.6, 1.2, 0))
        rig.k("Head", f, drot=(0.2, 0, 0.6))
    extra("Death", 1, 25)
    rig.push("Death")

    # ---- Held (gegen Sperre zerren)
    base(1); base(17)
    for i in range(9):
        f = 1 + 2 * i
        s = math.sin(TAU * i / 4)
        rig.k("Body", f, drot=(0.32, 0, 0.03 * (1 if i % 2 else -1)))
        rig.k("Leg_L", f, drot=(0.35 + 0.25 * s, 0, 0)); rig.k("Leg_R", f, drot=(0.35 - 0.25 * s, 0, 0))
        rig.k("Shoulder_L", f, drot=(-1.35 + 0.12 * s, 0.15, 0))
        rig.k("Shoulder_R", f, drot=(-1.35 - 0.12 * s, -0.15, 0))
        rig.k("Hips", f, drot=(lean * 0.5, 0, 0))
        rig.k("Head", f, drot=(-0.25, 0, 0.1 * s))
    extra("Held", 1, 17)
    rig.push("Held")

    if "cast" in p:
        base(1); base(25)
        for f in (5, 15):
            rig.k("Shoulder_R", f, drot=(-2.6, 0, 0.2))
            rig.k("Shoulder_L", f, drot=(-1.0, 0, -0.3))
            rig.k("Head", f, drot=(-0.3, 0, 0))
            rig.k("Hips", f, drot=(lean - 0.15, 0, 0))
        extra("Cast", 1, 25)
        rig.push("Cast")
    rig.restore()


# ====================================================================== Gegner
def goblin(b):
    rig = biped_rig(b, "Goblin", 0.2, 0.065, 0.24, 0.15, 0.27, 0.62)
    J = rig.J
    for n in ("Leg_L", "Leg_R"):
        limb_leg(b, J, n, 0.2, 0.06, "gob", "leather")
    H = J["Hips"]
    b.cyl(0.15, 0.27, (0, 0.02, 0.12), verts=7, r2=0.1, rot=(0.15, 0, 0), material="gob_cloth", parent=H, name="Torso")
    b.box((0.2, 0.03, 0.14), (0, -0.13, 0.02), material="leather", parent=H, name="Loincloth")
    K = J["Head"]
    b.ico(0.11, (0, -0.04, 0.07), "gob", K, "HeadMesh")
    b.cone_dir((0, -0.14, 0.06), (0, -1, -0.3), 0.08, 0.035, "gob", K, "Nose", verts=5)
    for s in (-1, 1):
        b.cone_dir((s * 0.09, -0.03, 0.09), (s, 0.35, 0.3), 0.17, 0.035, "gob", K, f"Ear{s}", verts=4)
        b.eye((s * 0.045, -0.135, 0.1), K, f"Eye{s}", "gob_eye", 0.018)
    for s in (-1, 1):
        b.cone_dir((s * 0.03, -0.13, 0.02), (0, 0, 1), 0.035, 0.012, "bone_w", K, f"Tooth{s}", verts=4)
    limb_arm(b, J, "Shoulder_L", (0.02, -0.04, -0.21), 0.05, "gob")
    hr = limb_arm(b, J, "Shoulder_R", (-0.02, -0.06, -0.2), 0.05, "gob")
    b.stick(hr + Vector((0, 0.03, -0.05)), hr + Vector((0, -0.07, 0.24)), 0.025, 0.025, "wood", J["Shoulder_R"], "PickHandle")
    b.cone_dir(hr + Vector((0, -0.07, 0.24)), (0, -1, -0.2), 0.12, 0.022, "rust", J["Shoulder_R"], "PickHead", verts=4)
    b.cone_dir(hr + Vector((0, -0.07, 0.24)), (0, 1, -0.3), 0.08, 0.022, "rust", J["Shoulder_R"], "PickBack", verts=4)
    rig.snapshot()
    biped_anims(rig, dict(period=16, stride=0.6, arm=0.6, bob=0.012, lean=0.28, sway=0.08, lay=0.1))
    return rig


def kobold(b):
    rig = biped_rig(b, "KoboldSapper", 0.17, 0.06, 0.2, 0.13, 0.23, 0.55)
    J = rig.J
    for n in ("Leg_L", "Leg_R"):
        limb_leg(b, J, n, 0.17, 0.055, "troll_dark", "leather")
    H = J["Hips"]
    b.cyl(0.13, 0.24, (0, 0, 0.1), verts=7, r2=0.1, material="leather", parent=H, name="Torso")
    b.cone_dir((0, 0.1, 0.02), (0, 1, -0.6), 0.25, 0.04, "troll_dark", H, "Tail", verts=4)
    K = J["Head"]
    b.cone_dir((0, 0.04, 0.06), (0, -1, 0.1), 0.2, 0.08, "troll_dark", K, "Snout", verts=6)
    for s in (-1, 1):
        b.cone_dir((s * 0.05, 0.04, 0.1), (s * 0.3, 0.8, 0.6), 0.12, 0.025, "bone_w", K, f"Horn{s}", verts=4)
        b.eye((s * 0.045, -0.04, 0.1), K, f"Eye{s}", "gob_eye", 0.016)
    b.box((0.16, 0.06, 0.04), (0, -0.02, 0.12), material="leather", parent=K, name="Goggles")
    limb_arm(b, J, "Shoulder_L", (0.02, -0.06, -0.17), 0.045, "troll_dark")
    hr = limb_arm(b, J, "Shoulder_R", (-0.02, -0.06, -0.17), 0.045, "troll_dark")
    b.box((0.03, 0.03, 0.12), tuple(hr + Vector((0, 0, 0.04))), material="wood", parent=J["Shoulder_R"], name="Torch")
    b.ico(0.03, tuple(hr + Vector((0, 0, 0.12))), "spark", J["Shoulder_R"], "TorchFlame")
    # Pulverfass auf dem Rücken
    Kg = rig.add("Keg", b.empty("Keg", (0, 0.15, 0.14), parent=H))
    b.cyl(0.11, 0.22, (0, 0, 0), verts=10, material="wood", parent=Kg, name="KegBody", bevel=0.01)
    for z in (-0.07, 0.07):
        b.cyl(0.115, 0.025, (0, 0, z), verts=10, material="iron", parent=Kg, name=f"KegBand{z}")
    b.cyl(0.012, 0.08, (0.05, 0, 0.14), verts=5, material="rope", parent=Kg, name="KegFuse")
    b.ico(0.022, (0.05, 0, 0.19), "spark", Kg, "KegSpark")
    b.rune((0, 0.112, 0), math.pi / 2, 0.25, Kg, "Keg") if False else None
    Bl = rig.add("KegBlast", b.empty("KegBlast", (0, 0.15, 0.14), parent=H))
    b.ico(0.4, (0, 0, 0), "powder", Bl, "BlastCore")
    for k in range(6):
        a = k * TAU / 6
        b.ico(0.22, (math.cos(a) * 0.35, math.sin(a) * 0.35, 0.05), "fire" if "fire" in b.M else "powder", Bl, f"BlastPuff{k}")
    Bl.scale = (0.0001,) * 3
    rig.snapshot()

    def extras(state, f0, f1):
        if state == "Death":
            rig.k("Keg", 1, scale=1); rig.k("Keg", 6, scale=1.15); rig.k("Keg", 7, scale=0.0001); rig.k("Keg", 25, scale=0.0001)
            rig.k("KegBlast", 1, scale=0.0001); rig.k("KegBlast", 6, scale=0.0001)
            rig.k("KegBlast", 9, scale=1.0); rig.k("KegBlast", 13, scale=1.3); rig.k("KegBlast", 16, scale=0.0001)
            rig.k("KegBlast", 25, scale=0.0001)
    biped_anims(rig, dict(period=14, stride=0.65, arm=0.5, bob=0.012, lean=0.2, sway=0.1, lay=0.1, extras=extras))
    return rig


def troll(b):
    rig = biped_rig(b, "CaveTroll", 0.55, 0.16, 0.6, 0.38, 0.62, 1.45)
    J = rig.J
    for n in ("Leg_L", "Leg_R"):
        limb_leg(b, J, n, 0.55, 0.17, "troll", "troll_dark", foot=0.1)
    H = J["Hips"]
    b.cyl(0.38, 0.62, (0, 0.04, 0.3), verts=8, r2=0.3, rot=(0.2, 0, 0), material="troll", parent=H, name="Torso")
    o = b.ico(0.36, (0, 0.12, 0.55), "troll_dark", H, "Hunch"); o.scale = (1.2, 1, 0.8)
    b.box((0.5, 0.06, 0.3), (0, -0.34, 0.02), material="leather", parent=H, name="Loincloth")
    for k in range(3):
        b.cone_dir((-0.2 + k * 0.2, 0.25, 0.75), (0, 0.4, 1), 0.18, 0.05, "rock", H, f"BackSpike{k}", verts=5)
    K = J["Head"]
    b.ico(0.2, (0, -0.12, 0.05), "troll", K, "HeadMesh")
    b.box((0.28, 0.12, 0.1), (0, -0.25, -0.02), material="troll", parent=K, name="Jaw")
    for s in (-1, 1):
        b.cone_dir((s * 0.1, -0.3, 0.0), (s * 0.2, -0.3, 1), 0.14, 0.035, "bone_w", K, f"Tusk{s}", verts=5)
        b.eye((s * 0.08, -0.3, 0.1), K, f"Eye{s}", "gob_eye", 0.025)
    b.box((0.3, 0.1, 0.05), (0, -0.28, 0.14), material="troll_dark", parent=K, name="Brow")
    limb_arm(b, J, "Shoulder_L", (0.05, -0.12, -0.7), 0.15, "troll", "troll_dark", fist=0.12)
    hr = limb_arm(b, J, "Shoulder_R", (-0.05, -0.15, -0.68), 0.15, "troll", "troll_dark", fist=0.12)
    S = J["Shoulder_R"]
    b.cone_dir(hr + Vector((0, 0.05, 0.1)), (0, -0.55, -1), 0.75, 0.13, "rock", S, "Club", verts=6, r2=0.05)
    rig.snapshot()
    biped_anims(rig, dict(period=28, stride=0.42, arm=0.35, bob=0.03, lean=0.32, sway=0.12, lay=0.25))
    return rig


def draugr(b):
    rig = biped_rig(b, "Draugr", 0.2, 0.075, 0.27, 0.2, 0.33, 0.78)
    J = rig.J
    for n in ("Leg_L", "Leg_R"):
        limb_leg(b, J, n, 0.2, 0.1, "rust", "leather")
    H = J["Hips"]
    b.cyl(0.21, 0.32, (0, 0, 0.16), verts=8, r2=0.18, material="rust", parent=H, name="Armor")
    b.box((0.3, 0.04, 0.22), (0, -0.2, 0.15), material="iron", parent=H, name="Breastplate")
    b.box((0.04, 0.05, 0.16), (0, -0.225, 0.15), material="ghost", parent=H, name="ChestRune")
    b.cyl(0.215, 0.1, (0, 0, -0.01), verts=8, r2=0.22, material="cape", parent=H, name="Tabard")
    for s in (-1, 1):
        o = b.ico(0.085, (s * 0.18, 0, 0.29), "rust", H, f"Pauldron{s}"); o.scale = (1.1, 1, 0.7)
    K = J["Head"]
    b.ico(0.11, (0, 0, 0.07), "undead", K, "HeadMesh")
    b.cone_dir((0, -0.07, 0.03), (0, -0.2, -1), 0.3, 0.12, "beard_dead", K, "Beard", verts=6)
    for s in (-1, 1):
        b.cone_dir((s * 0.06, -0.08, 0.0), (s * 0.2, -0.1, -1), 0.24, 0.035, "beard_dead", K, f"Braid{s}", verts=4)
        b.box((0.035, 0.012, 0.018), (s * 0.045, -0.105, 0.09), material="ghost", parent=K, name=f"Eye{s}")
    h = b.ico(0.125, (0, 0.005, 0.12), "rust", K, "Helmet"); h.scale = (1, 1, 0.75)
    b.box((0.03, 0.03, 0.09), (0, -0.125, 0.08), material="iron", parent=K, name="NoseGuard")
    b.cone_dir((0.11, 0, 0.14), (1, 0.1, 0.9), 0.2, 0.045, "bone_w", K, "HornR", verts=5)
    b.cone_dir((-0.11, 0, 0.14), (-1, 0.1, 0.4), 0.08, 0.04, "bone_w", K, "HornL_Broken", verts=5, r2=0.025)
    hl = limb_arm(b, J, "Shoulder_L", (0.08, -0.12, -0.18), 0.07, "rust", "undead")
    hr = limb_arm(b, J, "Shoulder_R", (-0.08, -0.06, -0.22), 0.07, "rust", "undead")
    SL, SR = J["Shoulder_L"], J["Shoulder_R"]
    sh = b.cyl(0.17, 0.03, tuple(hl + Vector((0, -0.05, 0.03))), verts=7, rot=(R(90), 0, 0), material="wood", parent=SL,
               name="ShieldBroken")
    b.ico(0.04, tuple(hl + Vector((0, -0.07, 0.03))), "rust", SL, "ShieldBoss")
    b.stick(hr + Vector((0, 0.02, -0.08)), hr + Vector((0, -0.05, 0.25)), 0.03, 0.03, "wood", SR, "AxeHandle")
    b.box((0.025, 0.16, 0.12), tuple(hr + Vector((0, -0.1, 0.2))), material="rust", parent=SR, name="AxeHead")
    rig.snapshot()
    biped_anims(rig, dict(period=22, stride=0.45, arm=0.25, bob=0.01, lean=0.08, sway=0.1, lay=0.12))
    return rig


def golem(b):
    rig = biped_rig(b, "StoneGolem", 0.42, 0.18, 0.55, 0.4, 0.62, 1.3)
    J = rig.J
    for n in ("Leg_L", "Leg_R"):
        b.rock(f"{n}_Rock", (0, 0, -0.2), 0.16, scale=(1, 1, 1.4), material="rock", parent=J[n])
        b.box((0.26, 0.3, 0.1), (0, -0.04, -0.38), material="rock_dark", parent=J[n], name=f"{n}_Foot")
    H = J["Hips"]
    b.rock("Torso", (0, 0, 0.3), 0.38, scale=(1.25, 0.85, 1.0), material="rock", parent=H)
    b.rock("ShoulderRock", (0, 0.05, 0.55), 0.3, scale=(1.6, 0.8, 0.6), material="rock_dark", parent=H)
    for k in range(5):
        a = -0.6 + k * 0.3
        b.stick((a * 0.6, -0.3, 0.1 + k * 0.08), (a * 0.6 + 0.1, -0.31, 0.25 + k * 0.08), 0.03, 0.03, "corrupt", H,
                f"Vein{k}")
    b.cone_dir((0.15, -0.2, 0.5), (0.3, -0.6, 1), 0.2, 0.06, "corrupt", H, "Crystal1", verts=5)
    b.cone_dir((-0.2, 0.1, 0.65), (-0.2, 0.3, 1), 0.25, 0.07, "corrupt", H, "Crystal2", verts=5)
    K = J["Head"]
    b.rock("HeadRock", (0, -0.05, 0.08), 0.15, scale=(1.1, 0.9, 0.8), material="rock_dark", parent=K)
    b.box((0.18, 0.02, 0.035), (0, -0.18, 0.1), material="corrupt", parent=K, name="EyeSlit")
    for s, n in ((-1, "Shoulder_L"), (1, "Shoulder_R")):
        hand = Vector((s * -0.02, -0.08, -0.62))
        b.rock(f"{n}_Upper", (0, 0, -0.18), 0.13, scale=(1, 1, 1.3), material="rock", parent=J[n])
        b.rock(f"{n}_Fist", tuple(hand), 0.17, scale=(1, 1, 1), material="rock_dark", parent=J[n])
    rig.snapshot()
    biped_anims(rig, dict(period=32, stride=0.32, arm=0.3, bob=0.035, lean=0.1, sway=0.14, lay=0.3))
    return rig


def shaman(b):
    rig = biped_rig(b, "GoblinShaman", 0.2, 0.065, 0.24, 0.15, 0.27, 0.68)
    J = rig.J
    for n in ("Leg_L", "Leg_R"):
        limb_leg(b, J, n, 0.2, 0.06, "gob", "leather")
    H = J["Hips"]
    b.cyl(0.19, 0.42, (0, 0.02, 0.05), verts=8, r2=0.1, material="cape", parent=H, name="Robe")
    for k in range(4):
        b.ico(0.03, (-0.09 + k * 0.06, -0.13, 0.2 - abs(k - 1.5) * 0.03), "bone_w", H, f"Necklace{k}")
    K = J["Head"]
    b.ico(0.1, (0, -0.04, 0.07), "gob", K, "HeadMesh")
    b.cone_dir((0, -0.13, 0.06), (0, -1, -0.4), 0.08, 0.032, "gob", K, "Nose", verts=5)
    for s in (-1, 1):
        b.cone_dir((s * 0.08, -0.03, 0.09), (s, 0.4, 0.3), 0.15, 0.03, "gob", K, f"Ear{s}", verts=4)
        b.eye((s * 0.042, -0.125, 0.1), K, f"Eye{s}", "corrupt", 0.017)
    b.cone_dir((0, 0.0, 0.12), (0, 0.2, 1), 0.25, 0.11, "cape", K, "Hood", verts=6)
    o = b.ico(0.08, (0, 0.02, 0.2), "bone_w", K, "SkullMask"); o.scale = (1, 1, 0.6)
    limb_arm(b, J, "Shoulder_L", (0.03, -0.08, -0.18), 0.05, "gob")
    hr = limb_arm(b, J, "Shoulder_R", (-0.02, -0.06, -0.19), 0.05, "gob")
    S = J["Shoulder_R"]
    b.stick(hr + Vector((0, 0, -0.25)), hr + Vector((0, 0, 0.45)), 0.03, 0.03, "wood", S, "Staff")
    for s in (-1, 1):
        b.cone_dir(hr + Vector((0, 0, 0.45)), (s * 0.5, 0, 1), 0.12, 0.02, "wood", S, f"StaffFork{s}", verts=4)
    Orb = rig.add("Orb", b.empty("Orb", tuple(hr + Vector((0, 0, 0.53))), parent=S))
    b.ico(0.055, (0, 0, 0), "corrupt", Orb, "OrbGlow")
    Ring = rig.add("HealRing", b.empty("HealRing", (0, 0, 0.02), parent=rig.root))
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.03, major_segments=36, minor_segments=4)
    o = bpy.context.active_object; o.scale = (1, 1, 0.3)
    b._finish(o, "corrupt", Ring, "HealRingMesh")
    for k in range(8):
        a = k * TAU / 8
        b.cone_dir((math.cos(a), math.sin(a), 0), (0, 0, 1), 0.2, 0.04, "corrupt", Ring, f"HealSpike{k}", verts=4)
    Ring.scale = (0.0001,) * 3
    rig.snapshot()

    def extras(state, f0, f1):
        if state == "Cast":
            for f, s in ((1, 1.0), (6, 1.8), (10, 1.3), (15, 1.8), (25, 1.0)):
                rig.k("Orb", f, scale=s)
            for f, s in ((1, 0.0001), (6, 0.3), (14, 2.5), (18, 3.0), (19, 0.0001), (25, 0.0001)):
                rig.k("HealRing", f, scale=s)
        elif state == "Walk":
            for i in range(5):
                rig.k("Orb", f0 + round(i * (f1 - f0) / 4), scale=1.0 + 0.15 * (i % 2))
    biped_anims(rig, dict(period=18, stride=0.5, arm=0.25, bob=0.012, lean=0.2, sway=0.08, lay=0.1, extras=extras,
                          cast=True))
    return rig


def bergkoenig(b):
    rig = biped_rig(b, "FallenMountainKing", 0.32, 0.12, 0.42, 0.32, 0.5, 1.3)
    J = rig.J
    for n in ("Leg_L", "Leg_R"):
        limb_leg(b, J, n, 0.32, 0.15, "rust", "iron", foot=0.08)
    H = J["Hips"]
    b.cyl(0.33, 0.5, (0, 0, 0.25), verts=8, r2=0.28, material="rust", parent=H, name="Armor")
    b.box((0.46, 0.05, 0.34), (0, -0.31, 0.24), material="gold_old", parent=H, name="Breastplate")
    b.rune((0, -0.34, 0.25), -math.pi / 2, 0.55, H, "Chest")
    for o in H.children:
        if o.name.startswith("Rune_Chest"):
            o.data.materials[0] = b.M["ghost"]
    b.cyl(0.34, 0.16, (0, 0, -0.02), verts=8, r2=0.36, material="cape", parent=H, name="Skirt")
    for s in (-1, 1):
        o = b.ico(0.14, (s * 0.3, 0, 0.45), "gold_old", H, f"Pauldron{s}"); o.scale = (1.1, 1, 0.7)
        for k in range(2):
            b.cone_dir((s * (0.32 + k * 0.05), 0, 0.52), (s * 0.5, 0, 1), 0.14, 0.035, "iron", H, f"PSpike{s}{k}", verts=4)
    Cp = rig.add("Cape", b.empty("Cape", (0, 0.24, 0.44), parent=H))
    b.box((0.6, 0.03, 0.85), (0, 0.02, -0.42), rot=(0.12, 0, 0), material="cape", parent=Cp, name="CapeMesh")
    for k in range(4):
        b.box((0.1, 0.035, 0.12), (-0.22 + k * 0.15, 0.08, -0.88), rot=(0.12, 0, 0.3 * (k % 2)), material="cape",
              parent=Cp, name=f"CapeTatter{k}")
    K = J["Head"]
    b.ico(0.17, (0, 0, 0.1), "undead", K, "HeadMesh")
    b.cone_dir((0, -0.1, 0.04), (0, -0.25, -1), 0.5, 0.19, "beard_dead", K, "Beard", verts=7)
    for s in (-1, 1):
        b.cone_dir((s * 0.1, -0.1, -0.02), (s * 0.25, -0.15, -1), 0.4, 0.05, "beard_dead", K, f"Braid{s}", verts=4)
        b.box((0.05, 0.015, 0.025), (s * 0.065, -0.16, 0.13), material="ghost", parent=K, name=f"Eye{s}")
    b.cyl(0.17, 0.07, (0, 0, 0.21), verts=10, material="gold_old", parent=K, name="CrownBand")
    for k in range(7):
        a = k * TAU / 7
        if k == 2:
            continue   # abgebrochene Zacke
        b.cone_dir((math.cos(a) * 0.16, math.sin(a) * 0.16, 0.24), (math.cos(a) * 0.15, math.sin(a) * 0.15, 1),
                   0.13 if k % 2 else 0.09, 0.035, "gold_old", K, f"CrownSpike{k}", verts=4)
    b.ico(0.03, (0, -0.17, 0.22), "ghost", K, "CrownGem")
    limb_arm(b, J, "Shoulder_L", (0.12, -0.18, -0.3), 0.11, "rust", "iron", fist=0.07)
    hr = limb_arm(b, J, "Shoulder_R", (-0.1, -0.16, -0.32), 0.11, "rust", "iron", fist=0.07)
    S = J["Shoulder_R"]
    b.stick(hr + Vector((0, -0.12, -0.15)), hr + Vector((0.02, 0.32, 0.6)), 0.05, 0.05, "wood", S, "HammerHandle")
    hp = hr + Vector((0.02, 0.36, 0.66))   # Hammer auf der Schulter, Kopf hinter dem König
    b.box((0.2, 0.42, 0.22), tuple(hp), material="iron", parent=S, name="HammerHead", bevel=0.02)
    for s in (-1, 1):
        b.box((0.22, 0.05, 0.24), tuple(hp + Vector((0, s * 0.18, 0))), material="gold_old", parent=S, name=f"HammerBand{s}")
    b.box((0.21, 0.04, 0.14), tuple(hp + Vector((0, 0, 0))), material="ghost", parent=S, name="HammerRune")
    rig.snapshot()

    def extras(state, f0, f1):
        if state == "Walk":
            for i in range(5):
                rig.k("Cape", f0 + round(i * (f1 - f0) / 4), drot=(0.15 + 0.08 * math.sin(i * math.pi / 2), 0, 0))
        elif state == "Held":
            for f in (f0, f1):
                rig.k("Cape", f, drot=(0.35, 0, 0))
    biped_anims(rig, dict(period=30, stride=0.4, arm=0.25, bob=0.025, lean=0.05, sway=0.1, lay=0.22, extras=extras))
    return rig


# ====================================================================== Spinne
def spider(b):
    rig = Rig()
    root = b.empty("ShadowSpider", (0, 0, 0)); rig.root = root
    Bd = rig.add("Body", b.empty("Body", (0, 0, 0), parent=root))
    h = 0.3
    T = rig.add("Thorax", b.empty("Thorax", (0, 0, h), parent=Bd))
    o = b.ico(0.17, (0, -0.05, 0), "chitin", T, "ThoraxMesh"); o.scale = (1, 1.2, 0.7)
    o = b.ico(0.27, (0, 0.33, 0.08), "chitin", T, "Abdomen"); o.scale = (1, 1.25, 0.85)
    for k in range(3):
        b.box((0.16 - k * 0.03, 0.05, 0.02), (0, 0.22 + k * 0.12, 0.3 - k * 0.01), material="chitin_hi", parent=T,
              name=f"Mark{k}")
    b.ico(0.1, (0, -0.24, 0.0), "chitin", T, "HeadMesh")
    for k, (x, z) in enumerate(((-0.04, 0.05), (0.04, 0.05), (-0.07, 0.02), (0.07, 0.02), (-0.025, 0.08), (0.025, 0.08))):
        b.eye((x, -0.32, z), T, f"Eye{k}", "corrupt", 0.018)
    for s in (-1, 1):
        b.cone_dir((s * 0.04, -0.3, -0.04), (s * 0.2, -1, -0.6), 0.12, 0.025, "bone_w", T, f"Fang{s}", verts=4)
    legs = []
    for side, sn in ((-1, "L"), (1, "R")):
        for i in range(4):
            y = -0.12 + i * 0.08
            yaw = (math.pi if side < 0 else 0) + side * (-0.7 + i * 0.45) * (1 if side > 0 else -1)
            yaw = (math.atan2(-0.6 + i * 0.4, side * 1.0))
            n = f"Leg_{sn}{i}"
            P = rig.add(n, b.empty(n, (side * 0.1, y, 0), parent=T, rot=(0, 0, yaw)))
            b.stick((0, 0, 0), (0.28, 0, 0.18), 0.04, 0.04, "chitin", P, f"{n}_A")
            b.stick((0.28, 0, 0.18), (0.55, 0, -h), 0.03, 0.03, "chitin", P, f"{n}_B")
            b.ico(0.03, (0.28, 0, 0.18), "chitin_hi", P, f"{n}_Knee")
            legs.append((n, side, i))
    b.empty("HitPoint", (0, 0.1, 0.1), parent=T)
    b.empty("HealthBarAnchor", (0, 0, 0.75), parent=root)
    rig.snapshot()
    groupA = {n for n, s, i in legs if (i + (s > 0)) % 2 == 0}

    def legs_key(f, swing, lift, extra_curl=0.0):
        for n, s, i in legs:
            sg = 1 if n in groupA else -1
            rig.k(n, f, drot=(0, -lift * max(0, sg * math.sin(swing)) + extra_curl, 0.32 * sg * math.sin(swing) * s))

    # Walk (12 Frames)
    rig.pose_base(1); rig.pose_base(13)
    for i in range(9):
        f = 1 + round(i * 12 / 8); ph = TAU * i / 8
        legs_key(f, ph, 0.25)
        rig.k("Thorax", f, dloc=(0, 0, 0.015 * math.cos(2 * ph)), drot=(0, 0.04 * math.sin(ph), 0))
    rig.push("Walk")
    # Hit
    rig.pose_base(1); rig.pose_base(9)
    rig.k("Thorax", 3, dloc=(0, 0.06, 0.04), drot=(-0.3, 0, 0))
    legs_key(3, math.pi / 2, 0.0, extra_curl=-0.2)
    rig.push("Hit")
    # Death: auf den Rücken, Beine einrollen
    rig.pose_base(1); rig.pose_base(25)
    rig.k("Thorax", 5, dloc=(0, 0, 0.12), drot=(-0.4, 0, 0))
    for f, ang in ((12, math.pi), (16, math.pi * 0.95), (25, math.pi)):
        rig.k("Body", f, loc=(0, 0, 2 * h - 0.05), rot=(0, ang, 0))
        legs_key(f, 0, 0, extra_curl=0.9)
    rig.push("Death")
    # Held
    rig.pose_base(1); rig.pose_base(17)
    for i in range(9):
        f = 1 + 2 * i
        legs_key(f, TAU * i / 4, 0.3)
        rig.k("Thorax", f, drot=(0.18, 0, 0.04 * (1 if i % 2 else -1)), dloc=(0, -0.02, 0))
    rig.push("Held")
    rig.restore()
    return rig


# ====================================================================== Rattenschwarm
def rats(b):
    rig = Rig()
    root = b.empty("RatSwarm", (0, 0, 0)); rig.root = root
    Bd = rig.add("Body", b.empty("Body", (0, 0, 0), parent=root))
    spots = [(0, -0.22, 0.0), (-0.24, -0.02, 0.6), (0.22, 0.05, 1.3), (-0.08, 0.27, 2.1), (0.2, 0.36, 2.9)]
    names = []
    for k, (x, y, off) in enumerate(spots):
        n = f"Rat_{k}"
        Rt = rig.add(n, b.empty(n, (x, y, 0), parent=Bd, rot=(0, 0, b.rng.uniform(-0.25, 0.25))))
        o = b.ico(0.08, (0, 0.02, 0.07), "fur", Rt, f"{n}_Body"); o.scale = (0.85, 1.5, 0.75)
        b.cone_dir((0, -0.08, 0.075), (0, -1, -0.15), 0.12, 0.05, "fur", Rt, f"{n}_Head", verts=6)
        b.ico(0.015, (0, -0.2, 0.06), "pink", Rt, f"{n}_Nose")
        for s in (-1, 1):
            b.cyl(0.03, 0.01, (s * 0.035, -0.08, 0.12), verts=8, rot=(R(80), 0, 0), material="pink", parent=Rt, name=f"{n}_Ear{s}")
            b.eye((s * 0.025, -0.14, 0.095), Rt, f"{n}_Eye{s}", "gob_eye", 0.011)
            for yy in (-0.06, 0.08):
                b.box((0.025, 0.03, 0.05), (s * 0.05, yy, 0.025), material="pink", parent=Rt, name=f"{n}_Leg{s}{yy}")
        Tl = rig.add(f"Tail_{k}", b.empty(f"Tail_{k}", (0, 0.13, 0.06), parent=Rt))
        b.cone_dir((0, 0, 0), (0, 1, -0.2), 0.22, 0.015, "pink", Tl, f"{n}_Tail", verts=4)
        names.append((n, off))
    b.empty("HitPoint", (0, 0.05, 0.08), parent=Bd)
    b.empty("HealthBarAnchor", (0, 0.05, 0.4), parent=root)
    rig.snapshot()
    P = 8
    rig.pose_base(1); rig.pose_base(P + 1)
    for i in range(9):
        f = 1 + i; ph = TAU * i / 8
        for n, off in names:
            rig.k(n, f, dloc=(0, 0, 0.025 * abs(math.sin(ph + off))), drot=(0.15 * math.sin(ph + off), 0, 0))
            rig.k(f"Tail_{n[-1]}", f, drot=(0, 0, 0.5 * math.sin(ph * 2 + off)))
    rig.push("Walk")
    rig.pose_base(1); rig.pose_base(9)
    for n, off in names:
        rig.k(n, 3, dloc=(0, 0.05, 0.05), drot=(-0.4, 0, 0))
    rig.push("Hit")
    rig.pose_base(1); rig.pose_base(25)
    for j, (n, off) in enumerate(names):
        s = 1 if j % 2 else -1
        rig.k(n, 4 + j, dloc=(0, 0, 0.06), drot=(0, s * 0.8, 0))
        rig.k(n, 10 + j, dloc=(0, 0, 0.0), drot=(0, s * 1.6, 0))
        rig.k(n, 25, dloc=(0, 0, 0.0), drot=(0, s * 1.6, 0))
    rig.push("Death")
    rig.pose_base(1); rig.pose_base(17)
    for i in range(9):
        f = 1 + 2 * i
        for n, off in names:
            rig.k(n, f, dloc=(0, -0.03, 0.03 * abs(math.sin(i + off))), drot=(0.25, 0, 0.15 * math.sin(i * 1.7 + off)))
            rig.k(f"Tail_{n[-1]}", f, drot=(0, 0, 0.8 * math.sin(i * 2 + off)))
    rig.push("Held")
    rig.restore()
    return rig


# ====================================================================== Tiefenwurm (Boss)
def worm(b):
    rig = Rig()
    root = b.empty("DeepWorm", (0, 0, 0)); rig.root = root
    Bd = rig.add("Body", b.empty("Body", (0, 0, 0), parent=root))
    n_seg = 8
    sp = 0.36
    segs = []
    for i in range(n_seg):
        r = 0.42 - i * 0.03 if i else 0.46
        y = -1.25 + i * sp
        n = "Head" if i == 0 else f"Seg_{i}"
        S = rig.add(n, b.empty(n, (0, y, r), parent=Bd))
        b.cyl(r, sp * 0.95, (0, 0, 0), verts=8, rot=ROT_Y, material="worm_flesh", parent=S, name=f"{n}_Flesh")
        b.cyl(r * 1.04, 0.05, (0, sp * 0.45, 0), verts=8, rot=ROT_Y, material="corrupt", parent=S, name=f"{n}_Glow") if i else None
        for k in range(3):
            a = math.pi / 2 + (k - 1) * 0.75
            p = Vector((math.cos(a) * r * 0.95, 0, math.sin(a) * r * 0.95))
            b.box((r * 0.75, sp * 0.8, 0.09), tuple(p), rot=(0, a - math.pi / 2, 0), material="worm_plate", parent=S,
                  name=f"{n}_Plate{k}", bevel=0.015)
        b.cone_dir((0, 0, r * 1.02), (0, 0.4, 1), 0.2 if i < 4 else 0.12, 0.06, "rock", S, f"{n}_Spike", verts=5)
        segs.append((n, r, y))
    Hd = rig.J["Head"]
    b.cyl(0.47, 0.12, (0, -0.2, 0), verts=8, rot=ROT_Y, material="worm_plate", parent=Hd, name="HeadRim")
    b.cyl(0.28, 0.05, (0, -0.26, 0), verts=8, rot=ROT_Y, material="dark", parent=Hd, name="Maw")
    b.cyl(0.12, 0.05, (0, -0.255, 0), verts=8, rot=ROT_Y, material="corrupt", parent=Hd, name="MawGlow")
    for k in range(8):
        a = k * TAU / 8
        b.cone_dir((math.cos(a) * 0.3, -0.24, math.sin(a) * 0.3), (-math.cos(a) * 0.5, -0.4, -math.sin(a) * 0.5), 0.14, 0.03,
                   "bone_w", Hd, f"Tooth{k}", verts=4)
    for s, n in ((-1, "Mandible_L"), (1, "Mandible_R")):
        Mn = rig.add(n, b.empty(n, (s * 0.38, -0.22, 0), parent=Hd))
        b.cone_dir((0, 0, 0), (s * 0.3, -1, 0), 0.45, 0.08, "bone_w", Mn, f"{n}_Mesh", verts=5)
    b.empty("HitPoint", (0, 0, 0.1), parent=rig.J["Seg_2"])
    b.empty("HealthBarAnchor", (0, -0.4, 1.35), parent=root)
    rig.snapshot()

    def mand(f, open_):
        rig.k("Mandible_L", f, drot=(0, 0, -open_)); rig.k("Mandible_R", f, drot=(0, 0, open_))
    P = 32
    rig.pose_base(1); rig.pose_base(P + 1)
    for i in range(9):
        f = 1 + i * 4; ph = TAU * i / 8
        for j, (n, r, y) in enumerate(segs):
            w = ph - j * 0.8
            rig.k(n, f, dloc=(0.06 * math.sin(ph - j * 0.6), 0, 0.08 * max(0, math.sin(w))), drot=(-0.12 * math.cos(w), 0, 0))
        mand(f, 0.25 + 0.2 * math.sin(ph * 2))
    rig.push("Walk")
    rig.pose_base(1); rig.pose_base(9)
    rig.k("Head", 3, dloc=(0, 0.08, 0.15), drot=(-0.4, 0, 0.15)); rig.k("Seg_1", 3, dloc=(0, 0.04, 0.08))
    mand(3, 0.6)
    rig.push("Hit")
    rig.pose_base(1); rig.pose_base(25)
    rig.k("Head", 6, dloc=(0, 0, 0.35), drot=(-0.6, 0, 0)); mand(6, 0.7)
    for j, (n, r, y) in enumerate(segs):
        f = 12 + j
        rig.k(n, f, dloc=(0, 0, -r * 0.35), drot=(0, 0.35 * (1 if j % 2 else -1), 0))
        rig.k(n, 25, dloc=(0, 0, -r * 0.35), drot=(0, 0.35 * (1 if j % 2 else -1), 0))
    rig.k("Head", 14, dloc=(0, -0.05, -0.2), drot=(0.4, 0, 0.3)); rig.k("Head", 25, dloc=(0, -0.05, -0.2), drot=(0.4, 0, 0.3))
    mand(25, 0.8)
    rig.push("Death")
    rig.pose_base(1); rig.pose_base(17)
    for i in range(9):
        f = 1 + 2 * i
        heave = math.sin(TAU * i / 4)
        for j, (n, r, y) in enumerate(segs):
            rig.k(n, f, dloc=(0, -j * 0.04, 0.05 * max(0, heave) * (1 if j % 2 else 0.5)), drot=(0.08 if j == 0 else 0, 0, 0))
        mand(f, 0.15 + 0.5 * (i % 2))
    rig.push("Held")
    rig.restore()
    return rig


# ====================================================================== Export
ENEMIES = {
    "goblin": goblin, "rat_swarm": rats, "kobold_sapper": kobold, "cave_troll": troll, "draugr": draugr,
    "stone_golem": golem, "shadow_spider": spider, "goblin_shaman": shaman, "deep_worm": worm,
    "fallen_king": bergkoenig,
}


def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    b = EnemyBuilder(random.Random(hash(name) % 1000))
    b.M["fire"] = dt.mat("Blast_Fire", "#ff7a2a", emit="#ff5a10", strength=5.0)
    rig = ENEMIES[name](b)
    return b, rig


def export(name):
    b, rig = build(name)
    path = os.path.join(OUT, f"enemy_{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_optimize_animation_size=False, export_optimize_animation_keep_anim_object=True)
    print("EXPORTED", name)


if __name__ == "__main__":
    for n in (sys.argv[1:] or ENEMIES):
        export(n)
