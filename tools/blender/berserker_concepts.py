"""
Konzept-Renders: Zwergenberserkerwall – 3 Varianten × 2 Zustände (Festhalten / Offen)
Aufruf: python3 berserker_concepts.py [konzept zustand]   (ohne Argumente: alle 6)
"""
import bpy, math, os, random, sys
from mathutils import Vector, Euler
import dwarf_towers as dt

OUT = os.path.dirname(os.path.abspath(__file__))
W = 2.4          # Wegbreite
GOLD = "#ffc53a"


class SceneBuilder(dt.Builder):
    def __init__(self, rng, rage):
        cfg = dict(dt.BASE, rune_color=GOLD, rune_strength=6.0 if rage else 2.5)
        super().__init__(cfg, rng)
        M = self.M
        M["wood"] = dt.mat("Wood_Dark", "#4a3324", rough=0.85)
        M["wood_light"] = dt.mat("Wood", "#6b4a32", rough=0.8)
        M["skin"] = dt.mat("Skin", "#b98262", rough=0.7)
        M["leather"] = dt.mat("Leather", "#3a2418", rough=0.9)
        M["mail"] = dt.mat("Chainmail", "#5f6066", metal=0.8, rough=0.55)
        M["tunic"] = dt.mat("Tunic", "#4a1d16", rough=0.9)
        M["bone"] = dt.mat("Horn", "#d6c9a8", rough=0.6)
        M["beard_r"] = dt.mat("Beard_Red", "#a8461d", rough=0.9)
        M["beard_b"] = dt.mat("Beard_Brown", "#5b3a22", rough=0.9)
        M["beard_g"] = dt.mat("Beard_Grey", "#8d8a85", rough=0.9)
        M["paint"] = dt.mat("WarPaint", "#ff2a1a", emit="#ff2010", strength=5.0 if rage else 0.6)
        M["eyes"] = dt.mat("RageEyes", "#ffd060", emit="#ffc040", strength=8.0 if rage else 0.0)
        M["aura"] = dt.mat("RageAura", "#ff3020", emit="#ff2a10", strength=3.0)
        M["gob"] = dt.mat("Goblin_Skin", "#55613c", rough=0.8)
        M["gob_cloth"] = dt.mat("Goblin_Rags", "#2b2622", rough=1.0)
        M["gob_eye"] = dt.mat("Goblin_Eyes", "#ff3020", emit="#ff2010", strength=6.0)
        M["dirt"] = dt.mat("Path_Dirt", "#3a2e24", rough=1.0)
        M["ground"] = dt.mat("Ground", "#1b1d1a", rough=1.0)
        M["banner_r"] = dt.mat("Banner_Red", "#6a1612", rough=0.9)
        M["ember"] = dt.mat("Brazier", "#ff7a20", emit="#ff6010", strength=8.0)

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

    # ------------------------------------------------------------ Zwerg (Blick nach lokal -Y)
    def dwarf(self, name, loc, yaw, pose="fight", beard="beard_r", scale=1.0, left="shield", parent=None):
        R = self.empty(name, loc, rot=(0, 0, yaw), parent=parent)
        R.scale = (scale, scale, scale)
        fight = pose == "fight"
        for s in (-1, 1):
            self.box((0.1, 0.12, 0.2), (s * 0.075, 0, 0.1), material="leather", parent=R, name=f"{name}_Leg{s}")
            self.box((0.11, 0.17, 0.06), (s * 0.075, -0.03, 0.03), material="leather", parent=R, name=f"{name}_Boot{s}")
        self.cyl(0.21, 0.32, (0, 0, 0.36), verts=8, r2=0.17, material="mail", parent=R, name=f"{name}_Body")
        self.cyl(0.215, 0.1, (0, 0, 0.23), verts=8, r2=0.21, material="tunic", parent=R, name=f"{name}_Skirt")
        self.cyl(0.2, 0.05, (0, 0, 0.3), verts=8, material="leather", parent=R, name=f"{name}_Belt")
        self.box((0.07, 0.03, 0.06), (0, -0.2, 0.3), material="bronze", parent=R, name=f"{name}_Buckle")
        for s in (-1, 1):
            self.ico(0.08, (s * 0.17, 0, 0.5), "bronze", R, f"{name}_Pauldron{s}")
        # Kopf, Bart, Helm
        self.ico(0.115, (0, 0, 0.6), "skin", R, f"{name}_Head")
        self.box((0.045, 0.06, 0.06), (0, -0.115, 0.585), material="skin", parent=R, name=f"{name}_Nose")
        for s in (-1, 1):
            self.box((0.03, 0.01, 0.018), (s * 0.045, -0.105, 0.625), material="eyes", parent=R, name=f"{name}_Eye{s}")
        self.cone_dir((0, -0.08, 0.56), (0, -0.25, -1), 0.3, 0.12, beard, R, f"{name}_Beard", verts=6)
        for s in (-1, 1):
            self.cone_dir((s * 0.07, -0.07, 0.52), (s * 0.15, -0.15, -1), 0.24, 0.04, beard, R, f"{name}_Braid{s}", verts=4)
        h = self.ico(0.13, (0, 0.005, 0.66), "iron", R, f"{name}_Helmet")
        h.scale = (1, 1, 0.75)
        self.cyl(0.128, 0.035, (0, 0, 0.635), verts=10, material="bronze", parent=R, name=f"{name}_HelmBand")
        self.box((0.03, 0.03, 0.09), (0, -0.125, 0.62), material="iron", parent=R, name=f"{name}_NoseGuard")
        for s in (-1, 1):
            self.cone_dir((s * 0.11, 0, 0.68), (s * 1, 0.1, 0.9), 0.2, 0.045, "bone", R, f"{name}_Horn{s}", verts=5)
        # Arme
        sh_l, sh_r = Vector((-0.2, 0, 0.47)), Vector((0.2, 0, 0.47))
        hand_l = Vector((-0.17, -0.2, 0.36)) if fight else Vector((-0.22, -0.06, 0.28))
        hand_r = Vector((0.2, 0.0, 0.8)) if fight else Vector((0.23, -0.04, 0.27))
        self.stick(sh_l, hand_l, 0.075, 0.075, "skin", R, f"{name}_ArmL")
        self.stick(sh_r, hand_r, 0.075, 0.075, "skin", R, f"{name}_ArmR")
        for k, (arm0, arm1) in enumerate(((sh_l, hand_l), (sh_r, hand_r))):
            m = arm0.lerp(arm1, 0.45)
            self.stick(m - (arm1 - arm0) * 0.08, m + (arm1 - arm0) * 0.08, 0.08, 0.08, "paint", R, f"{name}_Paint{k}")
            self.ico(0.045, tuple(arm1), "leather", R, f"{name}_Fist{k}")
        if left == "axe":   # zweite Axt statt Schild
            if fight:
                t2, b2 = hand_l + Vector((0, -0.1, 0.25)), hand_l + Vector((0, 0.04, -0.12))
            else:
                t2, b2 = hand_l + Vector((0, -0.02, 0.05)), hand_l + Vector((-0.02, -0.04, -0.27))
            self.stick(b2, t2, 0.035, 0.035, "wood_light", R, f"{name}_AxeHandleL")
            hd2 = t2 - (t2 - b2).normalized() * 0.06
            self.box((0.03, 0.2, 0.14), tuple(hd2 + Vector((0, -0.07, 0)) if fight else hd2 + Vector((-0.08, 0, 0))),
                     rot=(0, 0, 0) if fight else (0, 0, math.radians(90)), material="iron", parent=R,
                     name=f"{name}_AxeHeadL")
        elif left == "tower":   # großer Turmschild
            tc = hand_l + (Vector((0.06, -0.08, 0.0)) if fight else Vector((-0.05, 0, 0.02)))
            T = self.empty(f"{name}_Shield", tuple(tc), parent=R, rot=(0, 0, 0) if fight else (0, 0, math.radians(90)))
            self.box((0.36, 0.05, 0.56), (0, 0, 0), material="iron", parent=T, name=f"{name}_TowerShield", bevel=0.015)
            self.box((0.3, 0.06, 0.48), (0, -0.005, 0), material="wood", parent=T, name=f"{name}_TowerShieldWood")
            self.box((0.04, 0.07, 0.44), (0, -0.01, 0), material="rune", parent=T, name=f"{name}_TowerShieldRune")
            self.box((0.26, 0.07, 0.04), (0, -0.01, 0.1), material="rune", parent=T, name=f"{name}_TowerShieldRune2")
        if left != "shield":
            pass
        else:
            self._shield(name, R, hand_l, fight)
        # Axt (rechts)
        if fight:
            top, bot = hand_r + Vector((0, 0.1, 0.25)), hand_r + Vector((0, -0.05, -0.12))
        else:
            top, bot = hand_r + Vector((0.0, -0.02, 0.05)), hand_r + Vector((0.02, -0.04, -0.27))
        self.stick(bot, top, 0.035, 0.035, "wood_light", R, f"{name}_AxeHandle")
        hd = top - (top - bot).normalized() * 0.06
        self.box((0.03, 0.2, 0.14), tuple(hd + Vector((0, -0.07, 0)) if fight else hd + Vector((0.08, 0, 0))),
                 rot=(0, 0, 0) if fight else (0, 0, math.radians(90)), material="iron", parent=R, name=f"{name}_AxeHead")
        return R

    def _shield(self, name, R, hand_l, fight):
        sc = hand_l + (Vector((0, -0.05, 0.03)) if fight else Vector((-0.05, 0, 0.05)))
        sh = self.empty(f"{name}_Shield", tuple(sc), parent=R, rot=(math.radians(90), 0, 0) if fight else
                        (math.radians(90), 0, math.radians(-90)))
        self.cyl(0.2, 0.035, (0, 0, 0), verts=12, material="wood", parent=sh, name=f"{name}_ShieldDisc")
        bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.018, major_segments=12, minor_segments=4)
        self._finish(bpy.context.active_object, "iron", sh, f"{name}_ShieldRim")
        self.ico(0.05, (0, 0, 0.025), "bronze", sh, f"{name}_ShieldBoss")
        self.rune((0, 0, 0.02), 0, 0.32, sh, f"{name}_SR") if False else None
        for k in range(3):   # einfache Rune als Leuchtstreifen auf der Front (+Z lokal = Außenseite)
            a = k * math.pi / 3
            self.box((0.012, 0.25, 0.01), (0, 0, 0.022), rot=(0, 0, a), material="rune", parent=sh,
                     name=f"{name}_ShieldRune{k}")

    # ------------------------------------------------------------ Gegner (Blick nach lokal -Y)
    def goblin(self, name, loc, yaw, rng):
        R = self.empty(name, loc, rot=(0, 0, yaw))
        for s in (-1, 1):
            self.stick((s * 0.06, 0, 0.0), (s * 0.06, 0.02, 0.2), 0.06, 0.06, "gob", R, f"{name}_Leg{s}")
        self.cyl(0.17, 0.3, (0, 0.02, 0.33), verts=7, r2=0.11, rot=(0.3, 0, 0), material="gob_cloth", parent=R,
                 name=f"{name}_Body")
        self.ico(0.12, (0, -0.1, 0.52), "gob", R, f"{name}_Head")
        for s in (-1, 1):
            self.cone_dir((s * 0.1, -0.1, 0.55), (s, 0.3, 0.35), 0.16, 0.035, "gob", R, f"{name}_Ear{s}", verts=4)
            self.box((0.03, 0.01, 0.02), (s * 0.045, -0.215, 0.54), material="gob_eye", parent=R, name=f"{name}_Eye{s}")
            self.stick((s * 0.14, -0.02, 0.43), (s * 0.18, -0.2, 0.3), 0.05, 0.05, "gob", R, f"{name}_Arm{s}")
        self.stick((0.18, -0.2, 0.3), (0.2, -0.32 + rng.uniform(-0.05, 0.05), 0.6), 0.05, 0.05, "wood", R,
                   f"{name}_Club")
        self.ico(0.07, (0.2, -0.33, 0.62), "wood", R, f"{name}_ClubHead")
        return R

    def chain(self, p0, p1, name, link=0.15, parent=None):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        n = max(2, int(d.length / (link * 0.8)))
        q = d.normalized().to_track_quat("Y", "Z")
        for i in range(n):
            p = p0 + d * (i + 0.5) / n
            bpy.ops.mesh.primitive_torus_add(major_radius=link * 0.5, minor_radius=0.024, major_segments=8,
                                             minor_segments=4, location=p)
            o = bpy.context.active_object
            o.scale = (0.7, 1.0, 1.0)
            o.rotation_mode = "QUATERNION"
            o.rotation_quaternion = q @ Euler((0, math.pi / 2 * (i % 2), 0)).to_quaternion()
            self._finish(o, "iron", parent, f"{name}_{i}")

    def ring(self, center, r, material, name, minor=0.03):
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=minor, major_segments=40, minor_segments=4,
                                         location=center)
        o = bpy.context.active_object
        o.scale = (1, 1, 0.3)
        return self._finish(o, material, None, name)


# ============================================================ Umgebung
def environment(b, rng):
    bpy.ops.mesh.primitive_plane_add(size=40)
    b._finish(bpy.context.active_object, "ground", None, "Ground")
    o = b.box((30, W, 0.02), (0, 0, 0.0), material="dirt", name="Path")
    for side in (-1, 1):
        for i in range(34):
            x = -8 + i * 0.5 + rng.uniform(-0.1, 0.1)
            st = b.ico(rng.uniform(0.06, 0.12), (x, side * (W / 2 + 0.05), 0.02), "stone_alt", None, f"Edge_{side}_{i}")
            st.scale = (1.2, 1, 0.6)
    for i in range(14):
        x, y = rng.uniform(-6, 6), rng.choice((-1, 1)) * rng.uniform(2.2, 4.5)
        r = b.ico(rng.uniform(0.12, 0.3), (x, y, 0.05), "stone_alt", None, f"Rock_{i}")
        r.scale = (1, rng.uniform(0.7, 1.3), 0.6)


def goblins_held(b, rng, x0=0.45, n=7):
    pts = []
    for i in range(n):
        row = i // 4
        y = -0.85 + (i % 4) * 0.57 + rng.uniform(-0.08, 0.08) + (0.28 if row else 0)
        x = x0 + row * 0.5 + rng.uniform(-0.05, 0.08)
        if abs(y) < W / 2 - 0.15:
            b.goblin(f"Gob_{i}", (x, y, 0), math.radians(-90) + rng.uniform(-0.25, 0.25), rng)
            pts.append(Vector((x, y, 0)))
    return pts


def goblins_passing(b, rng, n=7):
    for i in range(n):
        x = 2.6 - i * 0.95 + rng.uniform(-0.15, 0.15)
        y = rng.uniform(-0.75, 0.75)
        b.goblin(f"Gob_{i}", (x, y, 0), math.radians(-90) + rng.uniform(-0.2, 0.2), rng)


def brazier(b, loc, name):
    x, y, z = loc
    for k in range(3):
        a = k * 2 * math.pi / 3
        b.stick((x + math.cos(a) * 0.15, y + math.sin(a) * 0.15, 0), (x, y, z - 0.08), 0.03, 0.03, "iron", None,
                f"{name}_Leg{k}")
    b.cyl(0.13, 0.1, (x, y, z), verts=8, r2=0.17, material="iron", name=f"{name}_Bowl")
    for k in range(3):
        b.cone_dir((x + (k - 1) * 0.05, y, z + 0.04), (0, 0, 1), 0.2 - k * 0.03, 0.06, "ember", None,
                   f"{name}_Fire{k}", verts=5)
    ld = bpy.data.lights.new(name + "L", "POINT"); ld.energy = 30; ld.color = (1, 0.5, 0.2)
    ld.shadow_soft_size = 0.2
    o = bpy.data.objects.new(ld.name, ld); o.location = (x, y, z + 0.4)
    bpy.context.scene.collection.objects.link(o)


# ============================================================ Konzepte
def stone_post(b, x, y, h, name):
    for k in range(int(h / 0.3)):
        b.box((0.42, 0.42, 0.28), (x, y, 0.15 + k * 0.3), rot=(0, 0, b.rng.uniform(-0.08, 0.08)),
              material="stone" if k % 2 else "stone_alt", name=f"{name}_B{k}", bevel=0.03)
    b.box((0.5, 0.5, 0.08), (x, y, 0.15 + int(h / 0.3) * 0.3 - 0.1), material="iron", name=f"{name}_Cap")
    b.rune((x, y - 0.215 * (1 if y > 0 else -1), 0.6), -math.pi / 2 if y > 0 else math.pi / 2, 0.55, None, name)


def concept_shieldwall(b, rng, hold):
    for s in (-1, 1):
        stone_post(b, 0, s * (W / 2 + 0.35), 1.2, f"Post{s}")
        b.stick((0, s * (W / 2 + 0.35), 1.15), (0, s * (W / 2 + 0.35), 2.0), 0.05, 0.05, "wood", None, f"Pole{s}")
        b.box((0.03, 0.4, 0.55), (0.0, s * (W / 2 + 0.35) - s * 0.2, 1.68), material="banner_r", name=f"Flag{s}")
    beards = ["beard_r", "beard_b", "beard_g", "beard_r", "beard_b"]
    if hold:
        for i in range(4):
            y = -0.9 + i * 0.6
            b.dwarf(f"Dwarf_{i}", (0.0 + rng.uniform(-0.04, 0.04), y, 0), math.radians(90), "fight", beards[i])
        r = b.ring((0.45, 0, 0.01), 1.0, "aura", "Aura")
        r.scale = (0.75, 1.25, 0.3)
        goblins_held(b, rng, x0=0.5)
    else:
        spots = [(-0.5, 1.75, 0), (0.5, 1.8, 0), (-0.4, -1.75, math.pi), (0.45, -1.8, math.pi)]
        for i, (x, y, yaw) in enumerate(spots):
            b.dwarf(f"Dwarf_{i}", (x, y, 0), yaw + rng.uniform(-0.3, 0.3), "idle", beards[i])
        goblins_passing(b, rng)
    brazier(b, (-0.8, W / 2 + 0.6, 0.55), "Brazier1")
    brazier(b, (-0.8, -(W / 2 + 0.6), 0.55), "Brazier2")


def concept_bulwark(b, rng, hold):
    cx, cy = 0.0, W / 2 + 0.95
    # Bollwerk aus Steinlagen
    for row in range(5):
        for i in range(4):
            x = cx - 0.75 + i * 0.5 + (0.25 if row % 2 else 0) - (0.25 if (row % 2 and i == 3) else 0)
            b.box((0.48, 1.1, 0.29), (x, cy, 0.16 + row * 0.3), rot=(0, 0, rng.uniform(-0.03, 0.03)),
                  material="stone" if rng.random() > 0.35 else "stone_alt", name=f"BW_{row}_{i}", bevel=0.035)
    top = 0.16 + 5 * 0.3
    b.box((1.9, 1.25, 0.12), (cx, cy, top - 0.05), material="stone_alt", name="BW_Top", bevel=0.03)
    for i in range(4):
        b.box((0.3, 0.3, 0.32), (cx - 0.75 + i * 0.5, cy - 0.45, top + 0.16), material="stone", name=f"BW_Merlon{i}",
              bevel=0.03)
    # Riesiger Zwergenhelm als Relief (Front zum Weg = -Y)
    fy = cy - 0.56
    hz = 1.05
    h = b.ico(0.42, (cx, fy, hz + 0.1), "iron", None, "Relief_Helm")
    h.scale = (1, 0.45, 0.8)
    b.cyl(0.42, 0.08, (cx, fy - 0.02, hz - 0.08), verts=12, rot=(math.radians(90), 0, 0), material="bronze",
          name="Relief_Band") if False else None
    b.box((0.86, 0.12, 0.08), (cx, fy - 0.1, hz - 0.05), material="bronze", name="Relief_Brow")
    for s in (-1, 1):
        b.box((0.16, 0.05, 0.06), (cx + s * 0.18, fy - 0.17, hz - 0.15), material="eyes", name=f"Relief_Eye{s}")
        b.cone_dir((cx + s * 0.38, fy - 0.05, hz + 0.25), (s, -0.2, 0.8), 0.6, 0.12, "bone", None, f"Relief_Horn{s}",
                   verts=6)
    b.box((0.08, 0.1, 0.3), (cx, fy - 0.18, hz - 0.28), material="iron", name="Relief_Nose")
    b.cone_dir((cx, fy - 0.12, hz - 0.35), (0, -0.25, -1), 0.7, 0.36, "bronze", None, "Relief_Beard", verts=6)
    for s in (-1, 1):
        b.cone_dir((cx + s * 0.25, fy - 0.1, hz - 0.35), (s * 0.2, -0.2, -1), 0.6, 0.12, "bronze", None,
                   f"Relief_Braid{s}", verts=5)
    mouth = Vector((cx, fy - 0.22, 0.62))
    b.box((0.36, 0.1, 0.14), tuple(mouth + Vector((0, 0.04, 0))), material="slit" if "slit" in b.M else "iron",
          name="Relief_Mouth")
    for s in (-1, 1):
        b.rune((cx + s * 0.82, fy + 0.01, 0.95), -math.pi / 2, 0.75, None, f"BW{s}")
    if hold:
        held = goblins_held(b, rng, x0=-0.2, n=6)
        for i, p in enumerate(held[:4]):
            tgt = p + Vector((0, 0, 0.32))
            b.chain(mouth, tgt, f"Chain_{i}")
            b.ring(tuple(tgt), 0.2, "rune", f"Shackle_{i}", minor=0.025).scale = (1, 1, 0.5)
        r = b.ring((0.2, 0, 0.01), 1.1, "rune", "RuneCircle", minor=0.025)
        r.scale = (0.9, 1.05, 0.3)
    else:
        for i, xo in enumerate((-0.12, 0.12)):
            p1 = mouth + Vector((xo * 2, -0.35, -0.62))
            b.chain(mouth + Vector((xo, 0, 0)), p1, f"Chain_{i}")
            b.cone_dir(p1 + Vector((0, 0, 0.02)), (0, -1, 0.4), 0.18, 0.05, "iron", None, f"Hook_{i}", verts=4)
        goblins_passing(b, rng)
    brazier(b, (cx - 1.25, cy - 0.3, 0.55), "Brazier1")
    brazier(b, (cx + 1.25, cy - 0.3, 0.55), "Brazier2")


def cheval(b, center, along_y, name):
    cx, cy = center
    L = W + 0.2
    d = Vector((0, 1, 0)) if along_y else Vector((1, 0, 0))
    p0 = Vector((cx, cy, 0.32)) - d * L / 2
    p1 = Vector((cx, cy, 0.32)) + d * L / 2
    b.stick(p0, p1, 0.14, 0.14, "wood", None, f"{name}_Log")
    side = Vector((1, 0, 0)) if along_y else Vector((0, 1, 0))
    n = 6
    for i in range(n):
        p = p0 + (p1 - p0) * (i + 0.5) / n
        for s in (-1, 1):
            dirv = (side * s + Vector((0, 0, 0.9))).normalized()
            b.cone_dir(p - dirv * 0.3, dirv, 0.75, 0.05, "wood_light", None, f"{name}_Stake_{i}_{s}", verts=5, r2=0.0)
        b.cyl(0.085, 0.05, tuple(p), verts=8, rot=(math.radians(90), 0, 0) if not along_y else (0, 0, 0),
              material="iron", name=f"{name}_Band_{i}") if False else None
        b.box((0.17, 0.17, 0.05) if along_y else (0.05, 0.17, 0.17), tuple(p), material="iron", name=f"{name}_Band_{i}")


def concept_camp(b, rng, hold):
    cx, cy = 0.0, W / 2 + 1.25
    # Palisade (Halbkreis, offen zum Weg)
    for i in range(15):
        a = math.radians(-10 + i * 200 / 14)
        r = 1.05
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        h = rng.uniform(0.85, 1.05)
        b.cyl(0.075, h, (x, y, h / 2), verts=7, material="wood", name=f"Palisade_{i}")
        b.cyl(0.075, 0.18, (x, y, h + 0.09), verts=7, r2=0.0, material="wood_light", name=f"PalisadeTip_{i}")
    b.stick((cx + 1.0, cy - 0.15, 0.6), (cx - 1.0, cy - 0.15, 0.6), 0.0001, 0.0001, "wood", None, "Dummy") if False else None
    # Banner + Kriegshorn
    b.stick((cx, cy + 0.3, 0), (cx, cy + 0.3, 2.3), 0.07, 0.07, "wood", None, "BannerPole")
    b.stick((cx - 0.3, cy + 0.3, 2.2), (cx + 0.3, cy + 0.3, 2.2), 0.04, 0.04, "wood", None, "BannerBar")
    b.box((0.55, 0.03, 0.85), (cx, cy + 0.28, 1.75), material="banner_r", name="Banner")
    b.rune((cx, cy + 0.26, 1.78), -math.pi / 2, 0.8, None, "Banner")
    # Horn auf Ständer (geschwungen aus Kegelstücken)
    hx, hy, hz = cx + 0.55, cy + 0.05, 0.9
    for k in range(3):
        b.stick((hx - 0.25 + k * 0.25, hy, 0), (hx, hy, hz - 0.05), 0.04, 0.04, "wood", None, f"HornStand{k}")
    pts = [Vector((hx + 0.25, hy, hz + 0.05)), Vector((hx + 0.05, hy - 0.05, hz)), Vector((hx - 0.2, hy - 0.15, hz + 0.08)),
           Vector((hx - 0.35, hy - 0.3, hz + 0.3))]
    rads = [0.05, 0.08, 0.12, 0.17]
    for k in range(3):
        d = pts[k + 1] - pts[k]
        b.cone_dir(pts[k], d, d.length + 0.03, rads[k], "bone", None, f"Horn_{k}", verts=8, r2=rads[k + 1])
    b.cyl(0.19, 0.05, tuple(pts[3]), verts=10, material="bronze", name="Horn_Bell") if False else None
    for k in range(2):
        p = pts[k + 1]
        b.ico(rads[k + 1] + 0.012, tuple(p), "bronze", None, f"Horn_Ring{k}").scale = (1, 1, 0.35)
    if hold:
        b.ico(0.12, tuple(pts[3] + Vector((-0.05, -0.08, 0.06))), "rune", None, "Horn_Blast")
    brazier(b, (cx - 0.65, cy - 0.15, 0.55), "Brazier1")
    beards = ["beard_r", "beard_b", "beard_g"]
    if hold:
        cheval(b, (0.0, 0.0), True, "Cheval")
        for i, y in enumerate((-0.75, 0.0, 0.75)):
            b.dwarf(f"Dwarf_{i}", (0.42, y + rng.uniform(-0.05, 0.05), 0), math.radians(90), "fight", beards[i])
        r = b.ring((0.95, 0, 0.01), 1.15, "aura", "Aura")
        r.scale = (0.85, 1.05, 0.3)
        goblins_held(b, rng, x0=0.9)
    else:
        cheval(b, (0.0, W / 2 + 0.05), False, "Cheval")   # beiseite gerollt, längs am Wegrand
        spots = [(cx - 0.35, cy + 0.35, -1.6), (cx + 0.15, cy + 0.6, 3.6), (cx + 0.45, cy - 0.45, -0.4)]
        for i, (x, y, yaw) in enumerate(spots):
            b.dwarf(f"Dwarf_{i}", (x, y, 0), yaw, "idle", beards[i])
        goblins_passing(b, rng)


CONCEPTS = {"schildwall": concept_shieldwall, "bollwerk": concept_bulwark, "lager": concept_camp}


def render(concept, hold):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    rng = random.Random(5)
    b = SceneBuilder(rng, hold)
    b.M["slit"] = dt.mat("Mouth_Dark", "#070605", rough=1.0)
    environment(b, rng)
    CONCEPTS[concept](b, rng, hold)
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.01, 0.012, 0.02, 1)
    def light(kind, loc, e, col, rot=(0, 0, 0), size=1):
        ld = bpy.data.lights.new(f"{kind}{loc}", kind); ld.energy = e; ld.color = col
        if kind == "AREA": ld.size = size
        o = bpy.data.objects.new(ld.name, ld); o.location = loc; o.rotation_euler = rot
        sc.collection.objects.link(o)
    light("SUN", (0, 0, 10), 2.4, (0.55, 0.65, 0.95), rot=(math.radians(48), 0, math.radians(-40)))
    light("AREA", (-3, 5, 5), 500, (0.45, 0.55, 0.9), rot=(math.radians(-50), 0, math.radians(200)), size=6)
    light("AREA", (4, -4, 3), 120, (1.0, 0.6, 0.35), rot=(math.radians(60), 0, math.radians(45)), size=4)
    cd = bpy.data.cameras.new("C"); cd.lens = 30
    cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (1.3, -5.3, 5.6)
    cam.rotation_euler = (Vector((0.45, 0.55, 0.25)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 48; sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "AgX"; sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = 1.3
    sc.render.resolution_x, sc.render.resolution_y = 1200, 820
    sc.render.filepath = os.path.join(OUT, f"concept_{concept}_{'hold' if hold else 'open'}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath)


if __name__ == "__main__":
    args = sys.argv[1:]
    jobs = [(args[0], args[1] == "hold")] if len(args) == 2 else [(c, h) for c in CONCEPTS for h in (True, False)]
    for c, h in jobs:
        render(c, h)
