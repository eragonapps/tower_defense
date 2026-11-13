class_name GameData
extends RefCounted
## Lädt und prüft die Spieldaten aus dem Ordner data/.
## Alle Werte für das Balancing stehen dort, nicht im Code.

const TOWERS_PATH := "res://data/towers.json"
const ENEMIES_PATH := "res://data/enemies.json"
const LEVEL_PATH := "res://data/levels/%s.json"
const RULES_PATH := "res://data/rules.json"
const DIFFICULTIES_PATH := "res://data/difficulties.json"
const DIFFICULTY_ORDER: Array[String] = ["easy", "normal", "hard"]
const LEVEL_ORDER: Array[String] = ["level_01", "level_02", "level_03", "level_04"]

const TOWER_FIELDS := ["name_key", "cost", "range", "cooldown", "damage", "splash", "projectile_speed", "color"]
## Zusatzwirkungen eines Turms: kind (projectile oder aura), slow {factor, duration}, burn {dps, duration}.
const TOWER_OPTIONAL := ["kind", "slow", "burn", "damage_type", "capacity", "hold_time"]
const DAMAGE_TYPES := ["pierce", "blunt", "fire", "magic"]
const ENEMY_FIELDS := ["name_key", "hp", "speed", "bounty", "lives", "color", "size"]


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Datei fehlt: %s" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("%s, Zeile %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func load_towers() -> Dictionary:
	var d: Variant = load_json(TOWERS_PATH)
	return d if d is Dictionary else {}


static func load_enemies() -> Dictionary:
	var d: Variant = load_json(ENEMIES_PATH)
	return d if d is Dictionary else {}


static func load_rules() -> Dictionary:
	var d: Variant = load_json(RULES_PATH)
	return d if d is Dictionary else {}


static func load_difficulties() -> Dictionary:
	var d: Variant = load_json(DIFFICULTIES_PATH)
	return d if d is Dictionary else {}


## Die allgemeinen Regeln mit den Faktoren eines Schwierigkeitsgrads.
static func rules_for(difficulty: String) -> Dictionary:
	var rules := load_rules()
	var diff: Dictionary = load_difficulties().get(difficulty, {})
	for key in diff:
		if GameSim.DEFAULT_RULES.has(key):
			rules[key] = diff[key]
	return rules


## Erzeugt die Simulation für ein Level mit allen Daten aus data/.
static func create_sim(level_id: String, difficulty := "normal") -> GameSim:
	return GameSim.new(load_level(level_id), load_towers(), load_enemies(), rules_for(difficulty))


static func load_level(id: String) -> Dictionary:
	var d: Variant = load_json(LEVEL_PATH % id)
	if d is Dictionary:
		d["id"] = id
		return d
	return {}


## Liefert eine Liste von Fehlern. Leer bedeutet: die Daten sind in Ordnung.
static func validate(level: Dictionary, towers: Dictionary, enemies: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if towers.is_empty():
		errors.append("Keine Türme definiert")
	if enemies.is_empty():
		errors.append("Keine Gegner definiert")
	for id in towers:
		for f in TOWER_FIELDS:
			if not towers[id].has(f):
				errors.append("Turm %s: Feld %s fehlt" % [id, f])
		if towers[id].get("cooldown", 1.0) <= 0.0:
			errors.append("Turm %s: cooldown muss größer als 0 sein" % id)
		if towers[id].get("cost", 1) <= 0:
			errors.append("Turm %s: cost muss größer als 0 sein" % id)
		for stats in [towers[id]] + towers[id].get("upgrades", []):
			if stats.has("slow") and not (stats["slow"].has("factor") and stats["slow"].has("duration")):
				errors.append("Turm %s: slow braucht factor und duration" % id)
			if stats.has("burn") and not (stats["burn"].has("dps") and stats["burn"].has("duration")):
				errors.append("Turm %s: burn braucht dps und duration" % id)
		if towers[id].get("damage_type", "blunt") not in DAMAGE_TYPES:
			errors.append("Turm %s: unbekannte Schadensart %s" % [id, towers[id]["damage_type"]])
		if towers[id].get("kind", "") == "block" and not (towers[id].has("capacity") and towers[id].has("hold_time")):
			errors.append("Turm %s: ein Schildwall braucht capacity und hold_time" % id)
		var spec_ids := {}
		for spec in towers[id].get("specs", []):
			for f in ["id", "name_key", "desc_key", "ore"]:
				if not spec.has(f):
					errors.append("Turm %s: Spezialisierung braucht %s" % [id, f])
			if spec_ids.has(spec.get("id", "")):
				errors.append("Turm %s: Spezialisierung %s doppelt" % [id, spec.get("id", "")])
			spec_ids[spec.get("id", "")] = true
			for key in spec:
				if key not in ["id", "name_key", "desc_key", "ore"] and key not in TOWER_FIELDS and key not in TOWER_OPTIONAL:
					errors.append("Turm %s: Spezialisierung ändert unbekannten Wert %s" % [id, key])
		if towers[id].has("specs") and towers[id]["specs"].size() != 2:
			errors.append("Turm %s: es müssen genau zwei Spezialisierungen sein" % id)
		for u in towers[id].get("upgrades", []):
			if int(u.get("ore", 0)) <= 0:
				errors.append("Turm %s: jede Ausbaustufe braucht Erzkosten (ore) größer als 0" % id)
			for key in u:
				if key != "ore" and key not in TOWER_FIELDS and key not in TOWER_OPTIONAL:
					errors.append("Turm %s: Ausbaustufe ändert unbekannten Wert %s" % [id, key])
	for id in enemies:
		for f in ENEMY_FIELDS:
			if not enemies[id].has(f):
				errors.append("Gegner %s: Feld %s fehlt" % [id, f])
		if enemies[id].get("speed", 1.0) <= 0.0:
			errors.append("Gegner %s: speed muss größer als 0 sein" % id)
		if enemies[id].get("hp", 1.0) <= 0.0:
			errors.append("Gegner %s: hp muss größer als 0 sein" % id)
		for type in enemies[id].get("resist", {}):
			if type not in DAMAGE_TYPES:
				errors.append("Gegner %s: unbekannte Schadensart %s in resist" % [id, type])
		if enemies[id].has("summon") and not enemies.has(enemies[id]["summon"].get("enemy", "")):
			errors.append("Gegner %s: ruft unbekannten Gegner" % id)
		if enemies[id].has("heal"):
			for f in ["amount", "interval", "radius"]:
				if not enemies[id]["heal"].has(f):
					errors.append("Gegner %s: heal braucht %s" % [id, f])
	for f in ["grid", "start_gold", "lives", "waves", "wave_pause", "towers"]:
		if not level.has(f):
			errors.append("Level: Feld %s fehlt" % f)
	if not errors.is_empty():
		return errors
	var grid := MineGrid.from_rows(level["grid"])
	if grid.error != "":
		errors.append("Level-Raster: %s" % grid.error)
		return errors
	if grid.cells_of_type(MineGrid.Cell.BUILD).is_empty():
		errors.append("Level hat keine Bauplätze")
	for key in level.get("rules", {}):
		if not GameSim.DEFAULT_RULES.has(key):
			errors.append("Level setzt unbekannte Regel %s" % key)
	for id in level["towers"]:
		if not towers.has(id):
			errors.append("Level erlaubt unbekannten Turm %s" % id)
	if level["waves"].is_empty():
		errors.append("Level hat keine Wellen")
	for w in level["waves"].size():
		var wave: Dictionary = level["waves"][w]
		if wave.get("groups", []).is_empty():
			errors.append("Welle %d hat keine Gruppen" % (w + 1))
		for g in wave.get("groups", []):
			if not enemies.has(g.get("enemy", "")):
				errors.append("Welle %d: unbekannter Gegner %s" % [w + 1, g.get("enemy", "")])
			if int(g.get("count", 0)) <= 0:
				errors.append("Welle %d: count muss größer als 0 sein" % (w + 1))
			if int(g.get("entrance", 0)) >= grid.entrances.size():
				errors.append("Welle %d: Eingang %d gibt es nicht" % [w + 1, int(g.get("entrance", 0))])
	return errors
