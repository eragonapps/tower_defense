class_name Models
extends RefCounted
## Lädt die 3D-Modelle und legt fest, welches Modell für welchen Turm und Gegner steht.
## Wer ein Modell tauschen will, ändert nur die Tabellen in dieser Datei
## und trägt die Quelle in ASSETS.md ein.

const DIR := "res://assets/"
const ADVENTURERS := "kaykit_adventurers/"
const DUNGEON := "kaykit_dungeon/"
const MONSTERS := "quaternius_monsters/"
const TOWERS_DIR := "dwarf_towers/"
const ENEMIES_DIR := "dwarf_enemies/"
const PROJECTILES_DIR := "dwarf_projectiles/"
const FX_DIR := "dwarf_fx/"
## Die eigenen Turmmodelle sind etwa 3,1 m breit, ein Feld ist 2 m. So passen sie auf einen Bauplatz.
const TOWER_SCALE := 0.57
## Knoten, die beim Zusammenfassen der Teile erhalten bleiben, weil sie sich bewegen.
const PIVOTS := ["Turret", "Barrel", "Spin", "Muzzle", "Crystal", "Orb",
	# Berserker-Lager: Sperre, beide Trupps, Wutring, Hornleuchten, Haltepunkt.
	"Barricade", "Squad_Fight", "Squad_Idle", "RageAura", "HornBlast", "HoldPoint"]


## Einzelne Berserker des Kampftrupps (Berserker_F0, Berserker_F1, …) bleiben beweglich, ihre Körperteile nicht.
static func _is_pivot(name: String) -> bool:
	if name in PIVOTS:
		return true
	return name.begins_with("Berserker_F") and name.trim_prefix("Berserker_F").is_valid_int()

## Zwerge entstehen aus den Abenteurer-Figuren: kleiner, und in der Höhe stärker gestaucht als in der Breite.
const DWARF_SCALE := Vector3(0.62, 0.5, 0.62)
const ENEMY_SCALE := 0.62

## Je Turmtyp: Modell je Ausbaustufe und je Spezialisierung, Geschoss und Effekte.
## shot: Geschossmodell je Spezialisierung ("" für Stufe 1 bis 3), fx: Effekt beim Treffer oder Puls.
const TOWERS := {
	"crossbow": {
		"levels": ["crossbow_tower_lvl1", "crossbow_tower_lvl2", "crossbow_tower_lvl3"],
		"specs": {"sniper": "crossbow_tower_sniper", "repeater": "crossbow_tower_rapid"},
		"shot": {"": "projectile_bolt", "sniper": "projectile_bolt_sniper", "repeater": "projectile_bolt_rapid"},
	},
	"sling": {
		"levels": ["cannon_tower_lvl1", "cannon_tower_lvl2", "cannon_tower_lvl3"],
		"specs": {"boulder": "cannon_tower_heavy", "hail": "cannon_tower_rapid"},
		"shot": {"": "projectile_cannonball", "boulder": "projectile_mortar_bomb", "hail": "projectile_rapid_slug"},
	},
	"runestone": {
		"levels": ["rune_tower_lvl1", "rune_tower_lvl2", "rune_tower_lvl3"],
		"specs": {"frost": "rune_tower_permafrost", "storm": "rune_tower_froststurm"},
		"fx": "fx_frost_pulse_ring", "fx_hit": "fx_ice_shard",
	},
	"forge": {
		"levels": ["fire_tower_lvl1", "fire_tower_lvl2", "fire_tower_lvl3"],
		"specs": {"inferno": "fire_tower_inferno", "ember": "fire_tower_rapid"},
		"shot": {"": "fx_firebolt"}, "fx": "fx_lava_pool", "muzzle_fx": "fx_flame_stream",
	},
	"bomb": {
		"levels": ["bomb_tower_lvl1", "bomb_tower_lvl2", "bomb_tower_lvl3"],
		"specs": {"mega": "bomb_tower_big", "cluster": "bomb_tower_cluster"},
		"shot": {"": "projectile_bomb", "mega": "projectile_bomb_big", "cluster": "projectile_bomb_cluster"},
		"fx": "fx_bomb_blast",
	},
	"shieldwall": {
		"levels": ["berserker_camp_lvl1", "berserker_camp_lvl2", "berserker_camp_lvl3"],
		"specs": {"bulwark": "berserker_camp_ironwall", "berserker": "berserker_camp_bloodrage"},
		# Das Lager steht mit seinem Ursprung in der Mitte des Stollens daneben, die Sperre schwenkt über den Weg.
		# Der Weg im Modell ist 2,4 m breit, ein Feld 2 m.
		"scale": 0.8, "on_path": true,
	},
}
## scale: Maßstab des Modells, unabhängig von der Größe in den Spieldaten. hover: Abstand zum Boden.
const ENEMIES := {
	"goblin": {"model": ENEMIES_DIR + "enemy_goblin", "scale": 1.5},
	"draugr": {"model": ENEMIES_DIR + "enemy_draugr", "scale": 1.45},
	"kobold_sapper": {"model": ENEMIES_DIR + "enemy_kobold_sapper", "scale": 1.6},
	"goblin_shaman": {"model": ENEMIES_DIR + "enemy_goblin_shaman", "scale": 1.4, "cast": "Cast"},
	"stone_golem": {"model": ENEMIES_DIR + "enemy_stone_golem", "scale": 1.15},
	"fallen_king": {"model": ENEMIES_DIR + "enemy_fallen_king", "scale": 1.6},
	"rat_swarm": {"model": ENEMIES_DIR + "enemy_rat_swarm", "scale": 1.5},
	"cave_troll": {"model": ENEMIES_DIR + "enemy_cave_troll", "scale": 1.25},
	"shadow_spider": {"model": ENEMIES_DIR + "enemy_shadow_spider", "scale": 1.2},
	"deep_worm": {"model": ENEMIES_DIR + "enemy_deep_worm", "scale": 0.8},
	# Noch kein eigenes Modell: einfache Fledermäuse, im Spiel erzeugt. hover: Flughöhe.
	"cave_bats": {"model": "", "builtin": "bats", "hover": 1.3},
	# scale gleicht den anderen Maßstab des Pakets aus, hover lässt die Figur über dem Boden schweben.
	"wraith": {"model": MONSTERS + "Ghost", "walk": "Flying_Idle", "death": "Death", "scale": 0.29, "hover": 0.35,
		"tint": Color(0.7, 0.9, 1.0), "glow": 0.9},
}
## Die Animationen der eigenen Gegner-Modelle.
const ENEMY_ANIMS := {"walk": "Walk", "death": "Death", "hit": "Hit", "held": "Held"}
const WORKER := {"model": ADVENTURERS + "Barbarian", "items": ["1H_Axe"], "work": "1H_Melee_Attack_Chop", "hide": "Sit_Floor_Idle"}

static var _scenes := {}
static var _baked := {}
static var _meshes := {}
static var _tints := {}


## Der Dateipfad eines Modells. Die Pakete liefern teils .glb, teils .gltf.
static func _file(path: String) -> String:
	for ext in [".glb", ".gltf"]:
		if ResourceLoader.exists(DIR + path + ext):
			return DIR + path + ext
	return ""


static func has(path: String) -> bool:
	return path != "" and _file(path) != ""


static func instance(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(_file(path))
	return _scenes[path].instantiate()


## Das erste Netz eines Modells, zum Beispiel für viele gleiche Bodenplatten.
static func mesh(path: String) -> Mesh:
	if not _meshes.has(path):
		var node := instance(path)
		var found := _find_mesh(node)
		_meshes[path] = found.mesh if found != null else null
		node.free()
	return _meshes[path]


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _find_mesh(c)
		if found != null:
			return found
	return null


## Eine Figur mit Skelett. Blendet alle Handgegenstände aus, die nicht in items stehen.
static func character(path: String, items: Array, scale: Vector3) -> Node3D:
	var node := instance(path)
	node.scale = scale
	for slot in node.find_children("handslot_*", "", true, false):
		for item in slot.get_children():
			item.visible = String(item.name) in items
	return node


## Färbt alle Teile einer Figur ein. Die Textur bleibt erhalten, die Farbe wird damit multipliziert.
## glow lässt die Figur zusätzlich in dieser Farbe leuchten, damit sie im Dunkeln zu sehen ist.
static func tint(character_node: Node3D, color: Color, glow := 0.0) -> void:
	for mi in character_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var key := "%s/%s/%.2f" % [mesh.resource_path + str(mesh.get_rid().get_id()), color.to_html(), glow]
		if not _tints.has(key):
			var original := mesh.surface_get_material(0)
			if not original is StandardMaterial3D:
				continue
			var copy: StandardMaterial3D = original.duplicate()
			copy.albedo_color = color
			if glow > 0.0:
				copy.emission_enabled = true
				copy.emission = color
				copy.emission_energy_multiplier = glow
			_tints[key] = copy
		mi.material_override = _tints[key]


static func player(character_node: Node3D) -> AnimationPlayer:
	return character_node.find_child("AnimationPlayer", true, false) as AnimationPlayer


## Spielt eine Animation. then: Animation, die danach in Schleife weiterläuft.
static func animate(character_node: Node3D, anim: String, loop := true, speed := 1.0, then := "") -> void:
	var ap := player(character_node)
	if ap == null or not ap.has_animation(anim):
		return
	ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	ap.speed_scale = speed
	ap.play(anim, 0.12)
	if then != "" and ap.has_animation(then):
		ap.get_animation(then).loop_mode = Animation.LOOP_LINEAR
		ap.queue(then)


# --- Zusammengefasste Modelle ---------------------------------------------

## Eine Kopie des Modells, in der alle unbeweglichen Teile je Material zu einem Netz zusammengefasst sind.
## Beweglich bleiben die Knoten aus PIVOTS und alle, die eine Animation bewegt, samt ihren Eltern.
## Das senkt die Zahl der Zeichenaufrufe von mehreren hundert auf wenige je Modell.
static func baked(path: String) -> Node3D:
	if not _baked.has(path):
		_baked[path] = _bake(instance(path))
	return _baked[path].duplicate()


static func _bake(src: Node3D) -> Node3D:
	# 1. Welche Knoten bleiben erhalten?
	var keep := {src: true}
	for n in src.find_children("*", "Node3D", true, false):
		if _is_pivot(String(n.name)):
			keep[n] = true
	var player := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		var anim_root := player.get_node(player.root_node)
		for anim_name in player.get_animation_list():
			var anim := player.get_animation(anim_name)
			for i in anim.get_track_count():
				var path := anim.track_get_path(i)
				var target := anim_root.get_node_or_null(NodePath(String(path.get_concatenated_names())))
				if target != null:
					keep[target] = true
	for n in keep.keys():
		var p: Node = n.get_parent()
		while p != null and p != src.get_parent():
			keep[p] = true
			p = p.get_parent()
	# 2. Neue Knoten für die erhaltenen, mit derselben Lage und denselben Namen.
	var made := {}
	var root := Node3D.new()
	root.name = src.name
	made[src] = root
	_copy_kept(src, src, Transform3D(), keep, made)
	# 3. Alle Netze je nächstem erhaltenen Vorfahren und Material sammeln.
	var groups := {}
	_collect(src, src, Transform3D(), keep, groups)
	for owner_node in groups:
		var mesh := ArrayMesh.new()
		for mat in groups[owner_node]:
			var st: SurfaceTool = groups[owner_node][mat]
			st.set_material(mat)
			mesh = st.commit(mesh)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		made[owner_node].add_child(mi)
	if player != null:
		var copy := player.duplicate() as AnimationPlayer
		root.add_child(copy)
		copy.root_node = copy.get_path_to(root) if copy.is_inside_tree() else NodePath("..")
	src.free()
	return root


## Legt für jeden erhaltenen Knoten einen leeren Node3D an der richtigen Stelle des neuen Baums an.
static func _copy_kept(node: Node, src: Node3D, xf: Transform3D, keep: Dictionary, made: Dictionary) -> void:
	for c in node.get_children():
		if not c is Node3D:
			continue
		var here: Transform3D = xf * (c as Node3D).transform
		if keep.has(c):
			var n := Node3D.new()
			n.name = c.name
			# Lage relativ zum nächsten erhaltenen Vorfahren.
			var anc: Node = c.get_parent()
			var rel: Transform3D = (c as Node3D).transform
			while not keep.has(anc):
				rel = (anc as Node3D).transform * rel
				anc = anc.get_parent()
			n.transform = rel
			made[anc].add_child(n)
			made[c] = n
			_copy_kept(c, src, Transform3D(), keep, made)
		else:
			_copy_kept(c, src, here, keep, made)


static func _collect(node: Node, owner_node: Node, xf: Transform3D, keep: Dictionary, groups: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		var own: Transform3D = xf if keep.has(node) and node != owner_node else xf
		for i in mesh.get_surface_count():
			var mat: Material = (node as MeshInstance3D).get_active_material(i)
			if not groups.has(owner_node):
				groups[owner_node] = {}
			if not groups[owner_node].has(mat):
				var st := SurfaceTool.new()
				groups[owner_node][mat] = st
			(groups[owner_node][mat] as SurfaceTool).append_from(mesh, i, own)
	for c in node.get_children():
		if not c is Node3D:
			continue
		if keep.has(c):
			# Ein erhaltener Knoten sammelt seine eigenen Netze. Sein eigenes Netz liegt in seinem Ursprung.
			_collect(c, c, Transform3D() if not c is MeshInstance3D else Transform3D(), keep, groups)
		else:
			_collect(c, owner_node, xf * (c as Node3D).transform, keep, groups)


## Ein Turm im Spiel: zusammengefasstes Modell, verkleinert, mit Drehkopf und Mündung.
## Liefert den Knoten. Metadaten: "turret" (Node3D oder null), "aim_offset" (Winkel der Mündung).
static func tower(type: String, level: int, spec: String) -> Node3D:
	var def: Dictionary = TOWERS.get(type, {})
	var file: String = def["specs"][spec] if spec != "" and def.get("specs", {}).has(spec) else def["levels"][clampi(level - 1, 0, 2)]
	var node := baked(TOWERS_DIR + file)
	node.scale = Vector3.ONE * float(def.get("scale", TOWER_SCALE))
	var turret := node.find_child("Turret", true, false) as Node3D
	var muzzle := node.find_child("Muzzle", true, false) as Node3D
	node.set_meta("turret", turret)
	node.set_meta("barrel", node.find_child("Barrel", true, false))
	node.set_meta("spin", node.find_child("Spin", true, false))
	node.set_meta("crystal", node.find_child("Crystal", true, false))
	# Wohin zeigt die Mündung in Ruhe? Danach richtet sich das Zielen.
	var offset := 0.0
	if turret != null and muzzle != null:
		var local := _offset_in(turret, muzzle)
		offset = atan2(local.x, local.z)
	node.set_meta("aim_offset", offset)
	node.set_meta("muzzle_height", _height_of(node, muzzle) if muzzle != null else 1.2)
	return node


static func _offset_in(ancestor: Node3D, node: Node3D) -> Vector3:
	var xf := Transform3D()
	var n: Node = node
	while n != ancestor and n != null:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin


static func _height_of(root: Node3D, node: Node3D) -> float:
	return (_offset_in(root, node) * root.scale).y


## Ein Gegner: zusammengefasstes Modell mit Animationen.
static func enemy(type: String) -> Node3D:
	var visual: Dictionary = ENEMIES.get(type, {})
	var node: Node3D
	if visual.get("builtin", "") == "bats":
		node = bat_swarm()
	elif String(visual.get("model", "")).begins_with(ENEMIES_DIR):
		node = baked(visual["model"])
	else:
		node = character(visual["model"], [], Vector3.ONE)
	node.scale = Vector3.ONE * float(visual.get("scale", 1.0))
	node.position.y = float(visual.get("hover", 0.0))
	return node


## Name einer Animation eines Gegners: die eigenen Modelle haben einheitliche Namen.
static func enemy_anim(type: String, what: String) -> String:
	var visual: Dictionary = ENEMIES.get(type, {})
	if visual.has(what):
		return visual[what]
	return ENEMY_ANIMS.get(what, "")


## Geschoss- oder Effektmodell. Leer, wenn es keines gibt.
static func prop(file: String) -> Node3D:
	for dir in [PROJECTILES_DIR, FX_DIR]:
		if has(dir + file):
			return baked(dir + file)
	return null



## Höhe eines Modells über seinem Ursprung, mit Maßstab. Für die Lage der Lebensanzeige.
static func height(node: Node3D) -> float:
	var box := _aabb(node, Transform3D())
	return box.end.y * node.scale.y if box.size != Vector3.ZERO else 1.0


static func _aabb(node: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	if node is MeshInstance3D and node.mesh != null:
		box = xf * node.mesh.get_aabb()
	for c in node.get_children():
		if c is Node3D:
			var b := _aabb(c, xf * (c as Node3D).transform)
			if b.size != Vector3.ZERO:
				box = b if box.size == Vector3.ZERO else box.merge(b)
	return box



## Platzhalter für den Fledermaus-Schwarm, bis ein eigenes Modell da ist: drei Fledermäuse aus
## einfachen Formen mit schlagenden Flügeln. Hat dieselben Animationen wie die eigenen Gegner.
static func bat_swarm() -> Node3D:
	var root := Node3D.new()
	root.name = "BatSwarm"
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.13, 0.11, 0.14)
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.2, 0.15, 0.2)
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.3, 0.2)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.3, 0.2)
	eye_mat.emission_energy_multiplier = 2.5
	var walk := Animation.new()
	walk.length = 0.3
	walk.loop_mode = Animation.LOOP_LINEAR
	var death := Animation.new()
	death.length = 0.5
	var offsets := [Vector3(0, 0, 0), Vector3(-0.35, 0.2, -0.3), Vector3(0.35, -0.15, -0.25)]
	for i in offsets.size():
		var bat := Node3D.new()
		bat.name = "Bat%d" % i
		bat.position = offsets[i]
		root.add_child(bat)
		var body := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.09
		sphere.height = 0.2
		sphere.radial_segments = 8
		sphere.rings = 4
		body.mesh = sphere
		body.material_override = body_mat
		bat.add_child(body)
		var eyes := MeshInstance3D.new()
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.1, 0.03, 0.03)
		eyes.mesh = eye_mesh
		eyes.position = Vector3(0, 0.03, 0.08)
		eyes.material_override = eye_mat
		bat.add_child(eyes)
		for side in [-1, 1]:
			var wing := MeshInstance3D.new()
			wing.name = "Wing%s" % ("L" if side < 0 else "R")
			var wing_mesh := PrismMesh.new()
			wing_mesh.size = Vector3(0.36, 0.2, 0.02)
			wing.mesh = wing_mesh
			wing.material_override = wing_mat
			var pivot := Node3D.new()
			pivot.name = "Pivot%s" % ("L" if side < 0 else "R")
			pivot.rotation.x = -PI / 2.0
			bat.add_child(pivot)
			wing.position = Vector3(side * 0.18, 0, 0)
			pivot.add_child(wing)
			var track := walk.add_track(Animation.TYPE_ROTATION_3D)
			walk.track_set_path(track, NodePath("Bat%d/%s" % [i, pivot.name]))
			var phase := float(i) * 0.07
			walk.rotation_track_insert_key(track, 0.0, Quaternion.from_euler(Vector3(-PI / 2.0, 0, side * (0.5 + phase))))
			walk.rotation_track_insert_key(track, 0.15, Quaternion.from_euler(Vector3(-PI / 2.0, 0, -side * 0.6)))
			walk.rotation_track_insert_key(track, 0.3, Quaternion.from_euler(Vector3(-PI / 2.0, 0, side * (0.5 + phase))))
		var fall := death.add_track(Animation.TYPE_POSITION_3D)
		death.track_set_path(fall, NodePath("Bat%d" % i))
		death.position_track_insert_key(fall, 0.0, offsets[i])
		death.position_track_insert_key(fall, 0.5, offsets[i] + Vector3(0, -1.2, 0))
	var library := AnimationLibrary.new()
	library.add_animation("Walk", walk)
	library.add_animation("Death", death)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.add_animation_library("", library)
	return root
