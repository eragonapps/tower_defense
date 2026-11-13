class_name Models
extends RefCounted
## Lädt die 3D-Modelle und legt fest, welches Modell für welchen Turm und Gegner steht.
## Wer ein Modell tauschen will, ändert nur die Tabellen in dieser Datei
## und trägt die Quelle in ASSETS.md ein.

const DIR := "res://assets/"
const ADVENTURERS := "kaykit_adventurers/"
const SKELETONS := "kaykit_skeletons/"
const DUNGEON := "kaykit_dungeon/"

## Zwerge entstehen aus den Abenteurer-Figuren: kleiner, und in der Höhe stärker gestaucht als in der Breite.
const DWARF_SCALE := Vector3(0.62, 0.5, 0.62)
const ENEMY_SCALE := 0.62

## items: Ausrüstung in den Händen, die sichtbar bleibt. Alle anderen Teile werden ausgeblendet.
const TOWERS := {
	"crossbow": {"model": ADVENTURERS + "Rogue_Hooded", "items": ["2H_Crossbow"], "idle": "2H_Ranged_Aiming", "attack": "2H_Ranged_Shoot"},
	"sling": {"model": ADVENTURERS + "Barbarian", "items": [], "idle": "Idle", "attack": "Throw"},
	"runestone": {"model": ADVENTURERS + "Mage", "items": ["2H_Staff"], "idle": "Idle", "attack": "Spellcast_Raise"},
	"forge": {"model": ADVENTURERS + "Knight", "items": [], "idle": "Idle", "attack": "Throw"},
	"bomb": {"model": ADVENTURERS + "Barbarian", "items": ["Mug"], "idle": "Idle", "attack": "Throw"},
	"shieldwall": {"model": ADVENTURERS + "Knight", "items": ["1H_Sword", "Rectangle_Shield"], "idle": "Blocking", "attack": "1H_Melee_Attack_Chop"},
}
const ENEMIES := {
	"skeleton_minion": {"model": SKELETONS + "Skeleton_Minion", "walk": "Walking_A", "death": "Death_A"},
	"skeleton_warrior": {"model": SKELETONS + "Skeleton_Warrior", "walk": "Walking_B", "death": "Death_B"},
	"skeleton_rogue": {"model": SKELETONS + "Skeleton_Rogue", "walk": "Running_A", "death": "Death_A"},
	"skeleton_mage": {"model": SKELETONS + "Skeleton_Mage", "walk": "Walking_A", "death": "Death_B"},
	# tint färbt ein vorhandenes Modell um, solange es für diesen Gegner kein eigenes gibt.
	"skeleton_guard": {"model": SKELETONS + "Skeleton_Warrior", "walk": "Walking_B", "death": "Death_B", "tint": Color(0.55, 0.7, 1.0)},
	"bone_king": {"model": SKELETONS + "Skeleton_Mage", "walk": "Walking_C", "death": "Death_A", "tint": Color(1.0, 0.45, 0.4)},
}
const WORKER := {"model": ADVENTURERS + "Barbarian", "items": ["1H_Axe"], "work": "1H_Melee_Attack_Chop", "hide": "Sit_Floor_Idle"}

static var _scenes := {}
static var _meshes := {}
static var _tints := {}


static func has(path: String) -> bool:
	return ResourceLoader.exists(DIR + path + ".glb")


static func instance(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(DIR + path + ".glb")
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
static func tint(character_node: Node3D, color: Color) -> void:
	for mi in character_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var key := "%s/%s" % [mesh.resource_path + str(mesh.get_rid().get_id()), color.to_html()]
		if not _tints.has(key):
			var original := mesh.surface_get_material(0)
			if not original is StandardMaterial3D:
				continue
			var copy: StandardMaterial3D = original.duplicate()
			copy.albedo_color = color
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
