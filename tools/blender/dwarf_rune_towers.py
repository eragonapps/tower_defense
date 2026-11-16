"""
Zwergen-Runenturm (Frost / Verlangsamung) – nutzt den Basis-Builder aus dwarf_towers.py

  rune_tower_lvl1.glb, _lvl2, _lvl3
  rune_tower_permafrost.glb    Spezialisierung „Permafrost“ (stärkere Verlangsamung)
  rune_tower_froststurm.glb    Spezialisierung „Froststurm“ (zusätzlicher AoE-Schaden)
  fx_frost_pulse_ring.glb      Puls-Ring (Radius 1) – in Godot hochskalieren + ausblenden
  fx_ice_shard.glb             Eissplitter für Froststurm-Treffer (fällt entlang -Y in Godot)

Nodes für Godot:
  Top          -> Spitze des Turms (statisch)
  Crystal      -> schwebender Kristall: langsam um Y drehen + auf/ab wippen
  RuneRing_N   -> Runenringe: um ihre lokale Y-Achse drehen (gegenläufig sieht gut aus)
  Storm        -> nur Froststurm: um Y drehen (Eissplitter kreisen)
  PulseOrigin  -> Mittelpunkt für den Verlangsamungs-Puls (auf Bodenhöhe)
Ursprung = Mitte Boden.
"""
import bpy, math, os, random
import dwarf_towers as dt

OUT = os.path.dirname(os.path.abspath(__file__))
OCT = dt.OCT

RUNE_BASE = dict(
    name_prefix="RuneTower", top_name="Top", turret="rune",
    rune_color="#47b8ff", rune_strength=6.0, banner_color="#1b2738",
    furnace=False, chimneys=0,
    crystal_r=0.3, crystal_h=0.95, crystal_z=1.05, rings=2, ring_r=0.62,
    claws=True, shards=True, frost=0.0, permafrost=False, storm=False,
)
RUNE_VARIANTS = {
    "lvl1": dict(rows=3, r_bot=0.96, r_top=0.84, plinth_r=1.2, bands=("low",),
                 rune_angles=(-1,), rune_strength=3.5, banner=False, merlon_cap=None,
                 corbels=False, crystal_r=0.19, crystal_h=0.6, crystal_z=0.78, rings=0,
                 claws=False, shards=False),
    "lvl2": dict(rows=4, r_bot=1.02, r_top=0.87, plinth_r=1.28, rune_angles=(-1, 5),
                 rune_strength=4.5, crystal_r=0.24, crystal_h=0.78, crystal_z=0.92, rings=1,
                 ring_r=0.52, shards=False),
    "lvl3": dict(),
    "permafrost": dict(rune_color="#bfeeff", rune_strength=7.0, merlon_cap="ice", frost=0.35,
                       permafrost=True, crystal_r=0.36, crystal_h=1.1, crystal_z=1.05, rings=1,
                       ring_r=0.7),
    "froststurm": dict(rune_color="#4f86ff", rune_strength=7.5, storm=True, crystal_z=1.45,
                       rings=3, ring_r=0.66),
}


class RuneBuilder(dt.Builder):
    def __init__(self, cfg, rng):
        super().__init__(cfg, rng)
        M = self.M
        M["ice"] = dt.mat("Ice", "#8cc8f0", rough=0.15, emit="#4aa8ff", strength=0.35)
        M["crystal"] = dt.mat("Rune_Crystal", "#3d8fd6", rough=0.1, metal=0.0, emit=cfg["rune_color"],
                              strength=cfg["rune_strength"] * 0.3)
        M["frost_stone"] = dt.mat("Stone_Frosted", "#7f8d99", rough=0.7)
        M["snow"] = dt.mat("Snow_Mote", "#e8f6ff", emit="#cfeeff", strength=4.0)

    # ---------------------------------------------------------------- Helfer
    def crystal(self, r, h, loc, parent, name, material="crystal", rot=(0, 0, 0), verts=6):
        """Doppelpyramide (oben länger) als Kristall."""
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0, depth=h * 0.62,
                                        location=(0, 0, h * 0.31))
        top = bpy.context.active_object
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0, depth=h * 0.38,
                                        location=(0, 0, -h * 0.19), rotation=(math.pi, 0, 0))
        bot = bpy.context.active_object
        bpy.ops.object.select_all(action="DESELECT")
        top.select_set(True); bot.select_set(True)
        bpy.context.view_layer.objects.active = top
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.join()
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.001)
        bpy.ops.object.mode_set(mode="OBJECT")
        o = bpy.context.active_object
        o.location, o.rotation_euler = loc, rot
        return self._finish(o, material, parent, name)

    def ice_spike(self, base, direction, length, r, parent, name):
        """Eisdorn von base in Richtung direction."""
        from mathutils import Vector
        d = Vector(direction).normalized()
        center = Vector(base) + d * (length / 2)
        o = self.cyl(r, length, center, verts=5, r2=0.0, material="ice", parent=parent, name=name)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = d.to_track_quat("Z", "Y")
        return o

    def rune_ring(self, idx, radius, z, tilt, parent):
        R = self.empty(f"RuneRing_{idx}", (0, 0, z), parent=parent, rot=tilt)
        bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=0.025,
                                         major_segments=24, minor_segments=4)
        self._finish(bpy.context.active_object, "bronze", R, f"RuneRing_{idx}_Band")
        n = 8
        for i in range(n):
            a = i * 2 * math.pi / n
            # Runentafel (Bronze) + leuchtende Glyphe
            self.box((0.05, 0.13, 0.17), (math.cos(a) * radius, math.sin(a) * radius, 0), (0, 0, a),
                     material="iron", parent=R, name=f"RuneRing_{idx}_Tile{i}", bevel=0.01)
            for k, (dz, ln, ang) in enumerate(((0.0, 0.12, 0), (0.03, 0.07, 0.8), (0.03, 0.07, -0.8))):
                rr = radius + 0.03
                o = self.box((0.015, 0.018, ln), (math.cos(a) * rr, math.sin(a) * rr, dz),
                             material="rune", parent=R, name=f"RuneRing_{idx}_Glyph{i}_{k}")
                o.rotation_euler = (ang * math.cos(a + math.pi / 2) * 0 , 0, a)
                o.rotation_mode = "XYZ"
                from mathutils import Euler, Quaternion, Vector
                out = Vector((math.cos(a), math.sin(a), 0))
                o.rotation_mode = "QUATERNION"
                o.rotation_quaternion = Quaternion(out, ang) @ Euler((0, 0, a)).to_quaternion()
        return R

    # ---------------------------------------------------------------- Spitze
    def t_rune(self):
        c, T, rng = self.cfg, self.turret, self.rng
        self.empty("PulseOrigin", (0, 0, 0), parent=self.root)
        # Altar
        self.cyl(0.5, 0.12, (0, 0, 0.06), rot=(0, 0, OCT), material="stone_alt", parent=T,
                 name="Altar_Base", bevel=0.03)
        self.cyl(0.38, 0.32, (0, 0, 0.28), r2=0.3, rot=(0, 0, OCT), material="stone", parent=T,
                 name="Altar", bevel=0.03)
        self.cyl(0.36, 0.06, (0, 0, 0.47), rot=(0, 0, OCT), material="bronze", parent=T,
                 name="Altar_Rim", bevel=0.01)
        self.cyl(0.24, 0.04, (0, 0, 0.51), verts=16, material="rune", parent=T, name="Altar_Glow")
        # Runen an den Altarseiten
        for k in range(4):
            a = k * math.pi / 2 - math.pi / 2
            rr = 0.36
            self.rune((math.cos(a) * rr, math.sin(a) * rr, 0.28), a, 0.45, T, f"Altar{k}")
        # Bronzeklauen, die den Kristall halten
        if c["claws"]:
            for k in range(4):
                a = k * math.pi / 2 + math.pi / 4
                self.box((0.07, 0.07, 0.55), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.75),
                         (0, -0.38, a), material="bronze", parent=T, name=f"Claw_{k}", bevel=0.015)
                self.cyl(0.05, 0.16, (math.cos(a) * 0.21, math.sin(a) * 0.21, 1.05), verts=4, r2=0.0,
                         rot=(0, -0.7, a), material="bronze", parent=T, name=f"ClawTip_{k}")
        # Kristall (schwebend)
        K = self.empty("Crystal", (0, 0, c["crystal_z"]), parent=T)
        self.crystal(c["crystal_r"], c["crystal_h"], (0, 0, 0), K, "Crystal_Main")
        for k in range(3 if c["shards"] else 0):
            a = k * 2 * math.pi / 3 + 0.4
            self.crystal(c["crystal_r"] * 0.38, c["crystal_h"] * 0.42,
                         (math.cos(a) * c["crystal_r"] * 0.85, math.sin(a) * c["crystal_r"] * 0.85, -0.12),
                         K, f"Crystal_Side_{k}", rot=(math.cos(a) * 0.45, math.sin(a) * -0.45, 0))
        # Runenringe
        tilts = [(0.0, 0.0, 0.0), (0.35, 0.0, 0.5), (-0.35, 0.2, -0.6)]
        for i in range(c["rings"]):
            r = c["ring_r"] + i * 0.1
            self.rune_ring(i, r, c["crystal_z"] - 0.05 + i * 0.04, tilts[i], T)
        # Eissplitter um den Altar
        if c["shards"]:
            for k in range(6):
                a = k * math.pi / 3 + 0.3
                base = (math.cos(a) * 0.55, math.sin(a) * 0.55, 0.0)
                d = (math.cos(a) * 0.5, math.sin(a) * 0.5, 1.0)
                self.ice_spike(base, d, rng.uniform(0.2, 0.32), 0.06, T, f"AltarIce_{k}")
        if c["permafrost"]:
            self.permafrost()
        if c["storm"]:
            self.storm()

    def permafrost(self):
        c, T, rng, root = self.cfg, self.turret, self.rng, self.root
        # Kristall im Eis eingeschlossen: Eis-Cluster um den Altar
        for k in range(10):
            a = k * 2 * math.pi / 10 + rng.uniform(-0.2, 0.2)
            rr = rng.uniform(0.25, 0.6)
            base = (math.cos(a) * rr, math.sin(a) * rr, 0.05)
            d = (math.cos(a) * rng.uniform(0.25, 0.7), math.sin(a) * rng.uniform(0.25, 0.7), 1.0)
            self.ice_spike(base, d, rng.uniform(0.45, 0.95), rng.uniform(0.08, 0.14), T, f"IceCluster_{k}")
        # große Eisschale um den Kristall
        for k in range(6):
            a = k * math.pi / 3
            base = (math.cos(a) * 0.22, math.sin(a) * 0.22, 0.5)
            self.ice_spike(base, (math.cos(a) * 0.35, math.sin(a) * 0.35, 1.0), 0.75, 0.11, T,
                           f"IceShell_{k}")
        # Eiszapfen unter der Plattform
        TOP, rt = self.TOP, c["r_top"]
        for k in range(16):
            a = k * 2 * math.pi / 16 + rng.uniform(-0.1, 0.1)
            rr = rt + 0.22
            ln = rng.uniform(0.18, 0.42)
            o = self.cyl(0.045, ln, (math.cos(a) * rr, math.sin(a) * rr, TOP - ln / 2), verts=5, r2=0.0,
                         rot=(math.pi, 0, 0), material="ice", parent=root, name=f"Icicle_{k}")
        # Eis am Fuß des Turms
        for k in range(8):
            a = k * 2 * math.pi / 8 + rng.uniform(-0.3, 0.3)
            rr = c["r_bot"] + 0.12
            base = (math.cos(a) * rr, math.sin(a) * rr, 0.25)
            self.ice_spike(base, (math.cos(a) * 0.6, math.sin(a) * 0.6, 1.0), rng.uniform(0.3, 0.6),
                           rng.uniform(0.07, 0.12), root, f"GroundIce_{k}")

    def storm(self):
        c, T, rng = self.cfg, self.turret, self.rng
        S = self.empty("Storm", (0, 0, c["crystal_z"]), parent=T)
        for k in range(10):
            a = k * 2 * math.pi / 10
            rr = 0.95 + 0.12 * math.sin(k * 1.7)
            z = -0.45 + (k % 5) * 0.22
            tang = (-math.sin(a), math.cos(a), 0.25)
            self.ice_spike((math.cos(a) * rr, math.sin(a) * rr, z), tang, rng.uniform(0.22, 0.34),
                           0.055, S, f"StormShard_{k}")
        for k in range(16):
            a = rng.uniform(0, 2 * math.pi); rr = rng.uniform(0.6, 1.15)
            self.ico(0.025, (math.cos(a) * rr, math.sin(a) * rr, rng.uniform(-0.5, 0.6)), "snow", S,
                     f"Snow_{k}")
        # Runen-Säulen auf den hohen Zinnen (Sturmanker)
        TOP, mr = self.TOP, c["r_top"] + 0.15
        for i in range(0, 8, 2):
            a = i * math.pi / 4
            self.crystal(0.07, 0.32, (math.cos(a) * mr, math.sin(a) * mr, TOP + 0.18 + 0.42 + 0.2),
                         self.root, f"MerlonCrystal_{i}")


def build_variant(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cfg = dict(dt.BASE, **RUNE_BASE)
    cfg.update(RUNE_VARIANTS[variant])
    b = RuneBuilder(cfg, random.Random(11))
    b.build(variant)
    path = os.path.join(OUT, f"rune_tower_{variant}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("EXPORTED", variant, path)


def build_fx():
    # Puls-Ring
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cfg = dict(dt.BASE, **RUNE_BASE)
    b = RuneBuilder(cfg, random.Random(5))
    R = b.empty("FrostPulseRing", (0, 0, 0))
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.03, major_segments=48,
                                     minor_segments=4)
    o = bpy.context.active_object; o.scale = (1, 1, 0.3)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    b._finish(o, "rune", R, "Ring_Outer")
    bpy.ops.mesh.primitive_torus_add(major_radius=0.86, minor_radius=0.012, major_segments=48,
                                     minor_segments=4)
    b._finish(bpy.context.active_object, "rune", R, "Ring_Inner")
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        rr = 0.93
        # flache Rune liegend auf dem Boden
        for k, (x0, y0, x1, y1) in enumerate(((0, -0.05, 0, 0.05), (0, 0.0, -0.035, 0.045),
                                              (0, 0.0, 0.035, 0.045))):
            from mathutils import Vector
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            ln = math.hypot(x1 - x0, y1 - y0) + 0.01
            loc = Vector((math.cos(a) * rr, math.sin(a) * rr, 0)) + \
                Vector((-math.sin(a), math.cos(a), 0)) * cx + Vector((math.cos(a), math.sin(a), 0)) * cy
            ang = a + math.atan2(-(x1 - x0), (y1 - y0))
            b.box((0.012, ln, 0.01), tuple(loc), (0, 0, ang), material="rune", parent=R,
                  name=f"Glyph_{i}_{k}")
    for k in range(12):
        a = k * 2 * math.pi / 12
        b.ice_spike((math.cos(a) * 0.97, math.sin(a) * 0.97, 0), (math.cos(a) * 0.3, math.sin(a) * 0.3, 1),
                    0.12, 0.03, R, f"PulseIce_{k}")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "fx_frost_pulse_ring.glb"),
                              export_format="GLB", export_apply=True, export_yup=True)
    print("EXPORTED fx_frost_pulse_ring")

    # Eissplitter (fällt nach unten: Spitze zeigt -Z in Blender = -Y in Godot)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = RuneBuilder(dict(cfg, rune_color="#4f86ff"), random.Random(5))
    R = b.empty("IceShard", (0, 0, 0))
    b.crystal(0.08, 0.5, (0, 0, 0), R, "Shard_Main", material="ice", rot=(math.pi, 0, 0), verts=5)
    for k in range(3):
        a = k * 2 * math.pi / 3
        b.crystal(0.035, 0.22, (math.cos(a) * 0.07, math.sin(a) * 0.07, 0.08), R, f"Shard_Side_{k}",
                  material="ice", rot=(math.pi + math.cos(a) * 0.4, math.sin(a) * 0.4, 0), verts=4)
    b.crystal(0.03, 0.18, (0, 0, -0.02), R, "Shard_Core", material="crystal", rot=(math.pi, 0, 0), verts=4)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "fx_ice_shard.glb"),
                              export_format="GLB", export_apply=True, export_yup=True)
    print("EXPORTED fx_ice_shard")


if __name__ == "__main__":
    for v in RUNE_VARIANTS:
        build_variant(v)
    build_fx()
