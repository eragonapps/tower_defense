"""
Zwergen-Bombenwerfer (Katapult) – nutzt den Basis-Builder aus dwarf_towers.py

  bomb_tower_lvl1.glb, _lvl2, _lvl3
  bomb_tower_big.glb          Spezialisierung „Große Bombe“ (Trebuchet mit Gegengewicht)
  bomb_tower_cluster.glb      Spezialisierung „Clusterbombe“ (Wurfkorb, Federspannwerk)
  projectile_bomb.glb         Bombe Stufe 1–3
  projectile_bomb_big.glb     große Stachelbombe
  projectile_bomb_cluster.glb kleine Bombe (Cluster) – mehrere gleichzeitig spawnen
  fx_bomb_blast.glb           Explosion (Radius 1) – in Godot auf AoE skalieren und ausblenden

Nodes für Godot:
  Turret       -> um Y drehen zum Zielen
  Arm          -> Wurfarm. Ruhe-/Ladeposition = rotation.x 0; Wurf = rotation.x auf ca. +1.9 rad
                  (Arm schwingt nach oben/vorn, Prellbalken bei ca. 2.1 rad), danach zurück.
  LoadedBomb   -> Bombe in der Schale (beim Wurf ausblenden, Projektil an Muzzle spawnen)
  LoadedBombs  -> nur Cluster: fünf kleine Bomben im Korb
  Muzzle       -> Spawnpunkt des Projektils (bewegt sich mit dem Arm)
  Counterweight-> nur Große Bombe: Gegengewicht (kann beim Wurf gegen den Arm gedreht werden)
Wurfrichtung -Z (Godot forward), Ursprung = Mitte Boden.
"""
import bpy, math, os, random
from mathutils import Vector
import dwarf_towers as dt

OUT = os.path.dirname(os.path.abspath(__file__))
OCT = dt.OCT

BOMB_BASE = dict(
    name_prefix="BombTower", turret="catapult", turret_r=0.6,
    rune_color="#b45cff", rune_strength=6.5, banner_color="#22123a",
    furnace=False, chimneys=0, cat_scale=1.0, winch=True, iron_fittings=True, ammo_pile=True,
    bomb_r=0.12, mode="normal",
)
BOMB_VARIANTS = {
    "lvl1": dict(rows=3, r_bot=0.96, r_top=0.84, plinth_r=1.2, bands=("low",), rune_angles=(-1,),
                 rune_strength=3.5, banner=False, merlon_cap=None, corbels=False, turret_r=0.5,
                 cat_scale=0.8, winch=False, iron_fittings=False, ammo_pile=False, bomb_r=0.1),
    "lvl2": dict(rows=4, r_bot=1.02, r_top=0.87, plinth_r=1.28, rune_angles=(-1, 5), rune_strength=4.5,
                 turret_r=0.55, cat_scale=0.9, iron_fittings=False, bomb_r=0.11),
    "lvl3": dict(),
    "big": dict(mode="big", r_bot=1.12, r_top=0.95, plinth_r=1.5, turret_r=0.72, cat_scale=1.2,
                merlon_cap="spike", rune_color="#d24bff", rune_strength=7.5, bomb_r=0.2),
    "cluster": dict(mode="cluster", rune_color="#8f7bff", rune_strength=7.0, cat_scale=1.0, bomb_r=0.06),
}


class BombBuilder(dt.Builder):
    def __init__(self, cfg, rng):
        super().__init__(cfg, rng)
        M = self.M
        M["wood"] = dt.mat("Wood_Dark", "#4a3324", rough=0.85)
        M["wood_light"] = dt.mat("Wood", "#6b4a32", rough=0.8)
        M["rope"] = dt.mat("Rope", "#5c4a33", rough=1.0)
        M["bomb"] = dt.mat("Bomb_Iron", "#1d1d22", metal=0.7, rough=0.5)
        M["spark"] = dt.mat("Fuse_Spark", "#ffb040", emit="#ff9a20", strength=10.0)
        M["fire"] = dt.mat("Blast_Fire", "#ff8a2a", emit="#ff6a10", strength=2.0)
        M["fire_hot"] = dt.mat("Blast_Hot", "#ffd870", emit="#ffc040", strength=2.6)
        M["smoke"] = dt.mat("Blast_Smoke", "#2a2628", rough=1.0)
        M["rune_soft"] = dt.mat("Blast_Rune", cfg["rune_color"], emit=cfg["rune_color"], strength=2.0)

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

    # ---------------------------------------------------------------- Bombe
    def bomb(self, parent, r, loc, name, spikes=False, fuse=True):
        B = self.empty(name, loc, parent=parent)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r)
        self._finish(bpy.context.active_object, "bomb", B, f"{name}_Shell")
        self.cyl(r * 1.02, r * 0.22, (0, 0, 0), verts=12, rot=(0.35, 0, 0), material="rune", parent=B,
                 name=f"{name}_RuneBand")
        if spikes:
            for k in range(8):
                a = k * math.pi / 4
                for zz in (-0.45, 0.45):
                    d = Vector((math.cos(a), math.sin(a), zz)).normalized()
                    self.cone_dir(d * r * 0.9, d, r * 0.45, r * 0.13, "iron", B, f"{name}_Spike_{k}_{zz}",
                                  verts=4)
            for zz in (-1, 1):
                self.cyl(r * 0.75, r * 0.12, (0, 0, zz * r * 0.66), verts=12, material="iron", parent=B,
                         name=f"{name}_Band_{zz}")
        if fuse:
            self.cyl(r * 0.32, r * 0.25, (0, 0, r * 0.95), verts=8, material="bronze", parent=B,
                     name=f"{name}_FuseCap")
            self.cyl(r * 0.08, r * 0.5, (0, r * 0.08, r * 1.25), verts=5, rot=(-0.4, 0, 0), material="rope",
                     parent=B, name=f"{name}_Fuse")
            self.ico(r * 0.13, (0, r * 0.19, r * 1.48), "spark", B, f"{name}_Spark")
        return B

    # ---------------------------------------------------------------- Katapult
    def t_catapult(self):
        c, T, rng = self.cfg, self.turret, self.rng
        self.turret_mount()
        s = c["cat_scale"]
        mode = c["mode"]
        h = 0.78 * s + 0.1            # Achshöhe über Turret
        fx = 0.3 * s                  # Gestellbreite (halb)
        fit = "iron" if c["iron_fittings"] or mode != "normal" else "wood"
        # Gestell: zwei A-Böcke + Querbalken
        for side in (-1, 1):
            x = side * fx
            for yy in (-0.38 * s, 0.38 * s):
                self.stick((x, yy, 0.26), (x, 0, h + 0.04), 0.075 * s, 0.075 * s, "wood", T,
                           f"FrameLeg_{side}_{yy:.2f}")
            self.stick((x, -0.34 * s, 0.32), (x, 0.34 * s, 0.32), 0.07 * s, 0.07 * s, "wood", T, f"FrameBase_{side}")
            self.box((0.1 * s, 0.14 * s, 0.14 * s), (x, 0, h), material=fit, parent=T, name=f"AxleBlock_{side}",
                     bevel=0.01)
            if c["iron_fittings"] or mode != "normal":
                for yy in (-0.2 * s, 0.2 * s):
                    self.box((0.09 * s, 0.03, 0.09 * s), (x, yy, 0.32 + (h - 0.32) * 0.5), material="iron",
                             parent=T, name=f"FrameBracket_{side}_{yy:.2f}")
        # Prellbalken vorne oben (stoppt den Arm)
        stop_z, stop_y = h + 0.36 * s, -0.13 * s
        for side in (-1, 1):
            self.stick((side * fx, 0, h + 0.04), (side * fx, stop_y, stop_z), 0.06 * s, 0.06 * s, "wood", T,
                       f"StopBrace_{side}")
        self.stick((-fx - 0.03, stop_y, stop_z), (fx + 0.03, stop_y, stop_z), 0.09 * s, 0.09 * s, "wood", T,
                   "StopBeam")
        self.box((0.2 * s, 0.1 * s, 0.1 * s), (0, stop_y + 0.03 * s, stop_z - 0.02 * s), material="leather",
                 parent=T, name="StopPad")
        # Achse + Torsionsbündel
        self.cyl(0.04 * s, 2 * fx + 0.14 * s, (0, 0, h), verts=8, rot=(0, math.radians(90), 0), material="iron",
                 parent=T, name="Axle")
        for side in (-1, 1):
            for k in range(3):
                self.cyl(0.075 * s - k * 0.008, 0.04 * s, (side * (0.1 + k * 0.045) * s, 0, h), verts=8,
                         rot=(0, math.radians(90), k * 0.4), material="rope", parent=T, name=f"Torsion_{side}_{k}")
        if mode == "cluster":   # Federspannwerk statt nur Seil
            for side in (-1, 1):
                for k in range(6):
                    bpy.ops.mesh.primitive_torus_add(major_radius=0.07 * s, minor_radius=0.012, major_segments=10,
                                                     minor_segments=4, location=(side * fx, 0.18 * s, 0.4 + k * 0.05),
                                                     rotation=(0, 0, 0))
                    self._finish(bpy.context.active_object, "iron", T, f"Spring_{side}_{k}")
                self.stick((side * fx, 0.18 * s, 0.68), (side * 0.06, 0.12 * s, h - 0.05), 0.025, 0.025, "iron", T,
                           f"SpringRod_{side}")
        # Wurfarm
        A = self.empty("Arm", (0, 0, h), parent=T)
        ang = math.radians(-10)
        d = Vector((0, math.cos(ang), math.sin(ang)))       # Ladeposition: nach hinten
        n = Vector((0, -math.sin(ang), math.cos(ang)))      # „oben“ senkrecht zum Arm
        L = 0.95 * s
        self.stick(-d * 0.28 * s, d * L, 0.08 * s, 0.1 * s, "wood_light", A, "Arm_Beam")
        for k, t in enumerate((0.15, 0.55)):
            self.stick(d * (t * L) - Vector((0.05 * s, 0, 0)), d * (t * L) + Vector((0.05 * s, 0, 0)),
                       0.04 * s, 0.11 * s, "iron", A, f"Arm_Band_{k}")
        if mode != "normal" or c["iron_fittings"]:
            self.stick(d * 0.2 * L + n * 0.055 * s, d * 0.8 * L + n * 0.055 * s, 0.02 * s, 0.012 * s, "rune", A,
                       "Arm_Rune")
        end = d * L
        # Schale / Korb
        if mode == "cluster":
            bk = end + n * 0.05 * s
            w = 0.34 * s
            K = self.empty("Basket", tuple(bk), parent=A)
            self.box((w, w * 0.8, 0.03 * s), (0, 0, 0), material="iron", parent=K, name="Basket_Floor")
            for sx in (-1, 1):
                self.box((0.03 * s, w * 0.8, 0.12 * s), (sx * w / 2, 0, 0.06 * s), material="wood", parent=K,
                         name=f"Basket_Side_{sx}")
                self.box((w, 0.03 * s, 0.12 * s), (0, sx * w * 0.4, 0.06 * s), material="wood", parent=K,
                         name=f"Basket_End_{sx}")
            K.rotation_euler = (ang, 0, 0)
            LB = self.empty("LoadedBombs", (0, 0, 0), parent=K)
            br = c["bomb_r"]
            for k, (bx, by) in enumerate(((-0.08, -0.06), (0.08, -0.06), (-0.08, 0.06), (0.08, 0.06), (0, 0))):
                self.bomb(LB, br, (bx * s, by * s, br + (0.07 if k == 4 else 0.02)), f"Bomblet_{k}")
            self.empty("Muzzle", (0, 0, 0.12 * s), parent=K)
        else:
            bucket_r = (0.16 if mode == "normal" else 0.26) * s
            Bk = self.empty("Bucket", tuple(end + n * 0.04 * s), parent=A)
            Bk.rotation_euler = (ang, 0, 0)
            self.cyl(bucket_r * 0.7, bucket_r * 0.75, (0, 0, bucket_r * 0.37), verts=10, r2=bucket_r, material="iron",
                     parent=Bk, name="Bucket_Bowl", bevel=0.01)
            bpy.ops.mesh.primitive_torus_add(major_radius=bucket_r, minor_radius=0.02 * s, major_segments=12,
                                             minor_segments=4, location=(0, 0, bucket_r * 0.75))
            self._finish(bpy.context.active_object, "bronze", Bk, "Bucket_Rim")
            br = c["bomb_r"]
            self.bomb(Bk, br, (0, 0, bucket_r * 0.75 + br * 0.55), "LoadedBomb", spikes=(mode == "big"))
            self.empty("Muzzle", (0, 0, bucket_r * 0.75 + br * 0.6), parent=Bk)
        # Gegengewicht (Große Bombe)
        if mode == "big":
            pv = -d * 0.28 * s
            CW = self.empty("Counterweight", tuple(pv), parent=A)
            for side in (-1, 1):
                self.stick((side * 0.12 * s, 0, 0), (side * 0.12 * s, 0, -0.3 * s), 0.035, 0.035, "iron", CW,
                           f"CW_Hanger_{side}")
            self.box((0.36 * s, 0.3 * s, 0.32 * s), (0, 0, -0.44 * s), material="wood", parent=CW, name="CW_Box",
                     bevel=0.015)
            for zz in (-0.32, -0.56):
                self.box((0.38 * s, 0.32 * s, 0.04 * s), (0, 0, zz * s), material="iron", parent=CW,
                         name=f"CW_Band_{zz}")
            self.rune((0, -0.155 * s, -0.44 * s), -math.pi / 2, 0.45 * s, CW, "CW")
        # Spannwinde hinten
        if c["winch"]:
            wy, wz = 0.5 * s, 0.42
            for side in (-1, 1):
                self.stick((side * 0.2 * s, wy, 0.26), (side * 0.2 * s, wy, wz + 0.05), 0.06, 0.06, "wood", T,
                           f"WinchPost_{side}")
            self.cyl(0.07 * s, 0.34 * s, (0, wy, wz), verts=8, rot=(0, math.radians(90), 0), material="wood",
                     parent=T, name="WinchDrum")
            self.cyl(0.075 * s, 0.12 * s, (0, wy, wz), verts=8, rot=(0, math.radians(90), 0), material="rope",
                     parent=T, name="WinchRope")
            for side in (-1, 1):
                self.cyl(0.11 * s, 0.03, (side * 0.19 * s, wy, wz), verts=10, rot=(0, math.radians(90), 0),
                         material="bronze", parent=T, name=f"WinchWheel_{side}")
                for k in range(4):
                    a = k * math.pi / 2
                    self.stick((side * 0.21 * s, wy, wz), (side * 0.21 * s, wy + math.cos(a) * 0.17 * s,
                               wz + math.sin(a) * 0.17 * s), 0.025, 0.025, "wood", T, f"WinchSpoke_{side}_{k}")
        # Bombenvorrat / Munitionskiste
        if mode == "cluster":
            cx, cy = 0.5, 0.3
            self.box((0.3, 0.26, 0.2), (cx, cy, 0.38), material="wood", parent=T, name="AmmoCrate", bevel=0.01)
            self.box((0.32, 0.28, 0.03), (cx, cy, 0.3), material="iron", parent=T, name="AmmoCrateBand")
            for k in range(6):
                self.bomb(T, 0.05, (cx - 0.08 + (k % 3) * 0.08, cy - 0.05 + (k // 3) * 0.1, 0.52), f"AmmoBomblet_{k}",
                          fuse=False)
        elif c["ammo_pile"]:
            r = 0.09 if mode == "normal" else 0.13
            px, py = (0.48, 0.28) if mode == "normal" else (0.58, 0.32)
            pos = [(-1, 0), (1, 0), (0, 1.7), (0, 0.6)]
            for k, (ox, oz) in enumerate(pos):
                z = 0.28 + r + (r * 1.6 if k == 3 else 0)
                self.bomb(T, r, (px + ox * r * 1.05, py + (oz if k == 2 else 0) * r * 0.6, z), f"AmmoBomb_{k}",
                          spikes=(mode == "big"), fuse=(k == 3))


def build_variant(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cfg = dict(dt.BASE, **BOMB_BASE)
    cfg.update(BOMB_VARIANTS[variant])
    b = BombBuilder(cfg, random.Random(41))
    b.M["leather"] = dt.mat("Leather", "#3a1a12", rough=0.9)
    b.build(variant)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"bomb_tower_{variant}.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    print("EXPORTED", variant)


def build_projectiles_fx():
    for name, r, spikes, col in (("bomb", 0.12, False, "#b45cff"), ("bomb_big", 0.2, True, "#d24bff"),
                                 ("bomb_cluster", 0.06, False, "#8f7bff")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        b = BombBuilder(dict(dt.BASE, **dict(BOMB_BASE, rune_color=col)), random.Random(1))
        b.bomb(None, r, (0, 0, 0), name.title().replace("_", ""), spikes=spikes)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"projectile_{name}.glb"), export_format="GLB",
                                  export_apply=True, export_yup=True)
        print("EXPORTED", name)

    # Explosion: flacher Druckring + Feuerball-Puffs + Rauchkrone + violette Runenfunken
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = BombBuilder(dict(dt.BASE, **BOMB_BASE), random.Random(4)); rng = b.rng
    R = b.empty("BombBlast", (0, 0, 0))
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.05, major_segments=40, minor_segments=4)
    o = bpy.context.active_object; o.scale = (1, 1, 0.35)
    b._finish(o, "rune_soft", R, "Shockwave")
    F = b.empty("Fireball", (0, 0, 0), parent=R)
    for k in range(18):
        a = rng.uniform(0, 2 * math.pi); rr = rng.uniform(0, 0.45); z = rng.uniform(0.1, 0.55)
        b.ico(rng.uniform(0.14, 0.26), (math.cos(a) * rr, math.sin(a) * rr, z),
              "fire_hot" if rr < 0.2 else "fire", F, f"FirePuff_{k}")
    S = b.empty("Smoke", (0, 0, 0), parent=R)
    for k in range(12):
        a = k * 2 * math.pi / 12 + rng.uniform(-0.2, 0.2); rr = rng.uniform(0.45, 0.7)
        b.ico(rng.uniform(0.15, 0.24), (math.cos(a) * rr, math.sin(a) * rr, rng.uniform(0.1, 0.5)), "smoke", S,
              f"SmokePuff_{k}")
    for k in range(10):
        a = rng.uniform(0, 2 * math.pi)
        d = (math.cos(a), math.sin(a), rng.uniform(0.3, 1.0))
        b.cone_dir((0, 0, 0.3), d, rng.uniform(0.4, 0.75), 0.03, "rune_soft", R, f"Spark_{k}", verts=4)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "fx_bomb_blast.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    print("EXPORTED fx_bomb_blast")


if __name__ == "__main__":
    for v in BOMB_VARIANTS:
        build_variant(v)
    build_projectiles_fx()
