class_name GameSim
extends RefCounted
## Die Spielsimulation eines Levels: Gegner, Türme, Geschosse, Gold, Leben, Wellen.
## Reine Logik ohne Grafik. Rechnet in festen Zeitschritten, damit ein Lauf mit
## denselben Eingaben immer dasselbe Ergebnis hat. Die Darstellung hört auf die Signale.

signal enemy_spawned(enemy: Enemy)
## reason: "killed" oder "leaked"
signal enemy_removed(enemy: Enemy, reason: String)
signal tower_built(tower: Tower)
signal tower_sold(tower: Tower)
signal tower_upgraded(tower: Tower)
signal tower_specialized(tower: Tower)
signal tower_refined(tower: Tower)
signal tower_moved(tower: Tower, from: Vector2i)
## Im Endlosmodus ist an dieser Randzelle ein neues Tor entstanden.
signal breached(entrance: Vector2i)
signal dig_started(job: DigJob)
## Eine Zelle wurde zu Stollen oder zu Fels. Die Wege sind schon neu berechnet.
signal grid_changed(cell: Vector2i)
signal worker_placed(worker: Worker)
signal ore_mined(worker: Worker, amount: int)
## Ein Turm ohne Geschoss hat gewirkt, zum Beispiel der Runenstein.
signal aura_pulsed(tower: Tower)
## Ein Gegner hat andere Gegner geheilt.
signal enemies_healed(healer: Enemy)
## Ein Schildwall hat einen Gegner aufgehalten.
signal enemy_held(tower: Tower, enemy: Enemy)
## Ein Dieb hat Erz gestohlen.
signal ore_stolen(thief: Enemy, worker: Worker, amount: int)
## Nach einer Welle stehen Gaben zur Wahl. ids sind Kennungen aus data/boons.json.
signal boons_offered(ids: Array)
signal boon_chosen(id: String)
## Im Endlosmodus kommt ein dauerhafter Fluch dazu. id ist eine Kennung aus data/curses.json.
signal curse_added(id: String)
## Der erste Gegner einer Welle am Herz wurde von der Schutzrune aufgehalten.
signal leak_warded(enemy: Enemy)
signal projectile_fired(projectile: Projectile)
signal projectile_hit(projectile: Projectile)
signal wave_started(index: int)
signal wave_cleared(index: int)
signal finished(won: bool)

enum Status { RUNNING, WON, LOST }
## Ergebnis eines Spielerbefehls. Alles außer OK bedeutet: nichts ist passiert, nichts wurde bezahlt.
enum Result {
	OK, NOT_BUILDABLE, OCCUPIED, UNKNOWN_TOWER, NOT_ENOUGH_GOLD, GAME_OVER,
	## Der Befehl passt nicht zu dieser Zelle oder ist in diesem Level abgeschaltet.
	NOT_ALLOWED,
	NOT_ENOUGH_ORE,
	## Zuschütten würde einem Eingang oder einem Gegner den Weg zum Herz nehmen.
	BLOCKS_PATH,
	ENEMY_IN_THE_WAY,
	LIMIT_REACHED,
	MAX_LEVEL,
	## Eine Spezialisierung gibt es erst auf der höchsten Stufe, und nur eine.
	NOT_MAX_LEVEL,
	ALREADY_SPECIALIZED,
	## Die Zelle grenzt an keinen Stollen.
	NOT_CONNECTED,
	## Diesen Umbau gibt es nur im Endlosmodus.
	ONLY_ENDLESS,
	## Erst spezialisierte Türme lassen sich veredeln.
	NOT_SPECIALIZED,
}

const TICK_RATE := 60
const DT := 1.0 / TICK_RATE
## So nah am Ziel gilt ein Geschoss als angekommen.
const HIT_DISTANCE := 0.05
const STUN_IMMUNITY := 2.5
## Worauf ein Turm schießt: vorderster, stärkster oder schwächster Gegner in Reichweite.
const TARGET_MODES: Array[String] = ["first", "strong", "weak"]
const ENDLESS_MAX_ENEMIES := 70
const WILDFIRE_RADIUS := 1.0
## Regeln, die für alle Levels gelten. data/rules.json und das Level können sie überschreiben.
const DEFAULT_RULES := {
	"digging": true,
	"dig_cost": 30,
	"dig_time": 3.0,
	"fill_cost": 20,
	"max_digs": -1,
	"worker_cost": 40,
	"ore_interval": 2.0,
	"ore_amount": 1,
	"worker_threat_radius": 1.6,
	## Schwierigkeitsgrad: Faktoren auf die Lebenspunkte der Gegner und das Startgold.
	"enemy_hp_factor": 1.0,
	"start_gold_factor": 1.0,
	## Arbeiter bauen nur Erz ab, solange eine Welle läuft. Sonst ließe sich vor dem Start beliebig viel Erz sammeln.
	"ore_only_during_waves": true,
	## Nach jeder so vielten Welle stehen Gaben zur Wahl. 0 schaltet sie ab.
	"boon_every": 2,
	"boon_choices": 3,
	## Anteil der Baukosten, den ein Verkauf erstattet.
	"sell_refund": 0.7,
	## Dauerhafte Verbesserungen aus der Zwergenhalle.
	"tower_cost_factor": 1.0,
	"start_gold_bonus": 0,
	"start_ore_bonus": 0,
	"lives_bonus": 0,
	## Endlosmodus: Wachstum je Welle. Leben der Gegner als Faktor, Anzahl und Kopfgeld als Zuschlag.
	"endless_hp_growth": 1.08,
	"endless_count_growth": 0.02,
	"endless_count_cap": 1.25,
	"endless_bounty_growth": 0.03,
	"endless_boss_every": 5,
	## Bosse im Endlosmodus haben diesen Anteil ihrer Lebenspunkte. Sie kommen oft und in Levels ohne starke Türme.
	"endless_boss_hp": 0.5,
	## So viele Leben kostet ein durchgekommener Boss im Endlosmodus. Im normalen Spiel beendet er das Level sofort.
	"endless_boss_lives": 8,
	## Im Endlosmodus gibt es Gaben in jedem Level, auch wenn es sonst keine anbietet.
	"endless_boon_every": 2,
	"endless_curse_every": 5,
	"endless_reward": 40,
	"endless_wraith_from": 6,
	"endless_breach_every": 10,
	## Der Weg von einem neuen Tor zum Herz ist mindestens so lang.
	"breach_min_path": 8,
	## Veredeln: Preis in Gold und Wachstum je Kauf, Gewinn je Kauf.
	"refine_base": 150,
	"refine_growth": 1.25,
	"refine_gain": 1.04,
	"move_cost": 60,
	## Neue Bauplätze im Endlosmodus: Preis des ersten, Wachstum je weiterem, Obergrenze aller Bauplätze.
	"slot_gold": 300,
	"slot_ore": 40,
	"slot_growth": 1.5,
	"max_slots": 30,
}


class Enemy extends RefCounted:
	var id := 0
	var type := ""
	var def := {}
	var hp := 0.0
	var max_hp := 0.0
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var target_cell := Vector2i.ZERO
	## Restweg bis zum Herz. Kleiner bedeutet: weiter vorn.
	var remaining := 0.0
	var alive := true
	## Verlangsamung: Restdauer und Tempofaktor (0.5 bedeutet halbes Tempo).
	var slow_left := 0.0
	var slow_factor := 1.0
	## Brennen: Restdauer und Schaden pro Sekunde.
	var burn_left := 0.0
	var burn_dps := 0.0
	var heal_timer := 0.0
	var summon_timer := 0.0
	## Restzeit, in der ein Schildwall den Gegner festhält.
	var hold_left := 0.0
	var held_by: Tower
	var has_stolen := false
	var stun_immune_left := 0.0


class Tower extends RefCounted:
	var id := 0
	var type := ""
	var def := {}
	var cell := Vector2i.ZERO
	var pos := Vector2.ZERO
	var cooldown_left := 0.0
	var shots := 0
	var level := 1
	var target_mode := "first"
	## Wie oft der Turm veredelt wurde.
	var refine := 0
	## Das beim Bau bezahlte Gold. Grundlage für die Erstattung beim Verkauf.
	var paid := 0
	## Kennung der gewählten Spezialisierung, leer ohne.
	var spec := ""
	## Gegner, die dieser Schildwall schon einmal aufgehalten hat. Jeder nur einmal.
	var held_ids := {}
	## Die aktuell gültigen Werte: Grundwerte plus alle Ausbaustufen bis level.
	var stats := {}


class DigJob extends RefCounted:
	var cell := Vector2i.ZERO
	var time_left := 0.0
	var total := 0.0


class Worker extends RefCounted:
	var id := 0
	## Die Erzader, an der der Arbeiter steht.
	var cell := Vector2i.ZERO
	var pos := Vector2.ZERO
	## Falsch, solange Gegner in der Nähe sind oder die Ader keinen Stollen mehr berührt.
	var active := true
	var progress := 0.0
	var mined := 0


class Projectile extends RefCounted:
	var id := 0
	var def := {}
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var target: Enemy
	var target_pos := Vector2.ZERO
	var done := false


var grid: MineGrid
var status := Status.RUNNING
var gold := 0
var ore := 0
var lives := 0
var max_lives := 0
var tick := 0
var kills := 0
## Die meisten Gegner, die je gleichzeitig unterwegs waren. Ein Maß für die Last auf dem Gerät.
var peak_enemies := 0

var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var projectiles: Array[Projectile] = []
var dig_jobs: Array[DigJob] = []
var workers: Array[Worker] = []
var digs_started := 0
var slots_created := 0
var rules := {}
## Gewählte Gaben in der Reihenfolge der Wahl, und die gerade angebotenen.
var active_boons: Array[String] = []
var pending_boons: Array[String] = []
## Faktor auf das Kopfgeld, verändert durch Gaben.
var bounty_factor := 1.0
## Endlosmodus: läuft er, und wie viele seiner Wellen sind überstanden.
var endless := false
var endless_wave := 0
var endless_cleared := 0
var active_curses: Array[String] = []
## Faktoren aus Gaben und Flüchen auf alle Gegner.
var enemy_hp_extra := 1.0
var enemy_speed_factor := 1.0
## Schadensart → Faktor, den alle Gegner zusätzlich abziehen.
var global_resist := {}
## Schalter aus Gaben, zum Beispiel "wildfire" oder "ward".
var flags := {}

## Index der laufenden oder zuletzt gelaufenen Welle. -1 vor der ersten.
var wave_index := -1
var wave_count := 0
var wave_active := false
## Sekunden bis zum automatischen Start der nächsten Welle. Nur zwischen zwei Wellen.
var next_wave_in := 0.0

var _level := {}
var _tower_defs := {}
var _enemy_defs := {}
var _towers_by_cell := {}
var _workers_by_cell := {}
var _spawn_queue: Array[Dictionary] = []
var _wave_time := 0.0
var _next_id := 1
## Gegner, die während eines Schritts entstehen, kommen erst danach dazu.
var _pending_spawns: Array[Dictionary] = []
var _boon_defs := {}
## Turmtyp oder "all" → {Wert → Faktor}. Verändert durch Gaben.
var _tower_factors := {}
var _rng := RandomNumberGenerator.new()
var _curse_defs := {}
var _endless_groups: Array = []
var _ward_used := false
var _tower_flags := {}


## rng_seed bestimmt, welche Gaben und Flüche kommen. Derselbe Wert ergibt denselben Verlauf.
func _init(level: Dictionary, tower_defs: Dictionary, enemy_defs: Dictionary, global_rules := {}, boon_defs := {}, rng_seed := 1, curse_defs := {}) -> void:
	_level = level
	_boon_defs = boon_defs
	_curse_defs = curse_defs
	_rng.seed = rng_seed
	rules = DEFAULT_RULES.duplicate()
	rules.merge(global_rules, true)
	rules.merge(level.get("rules", {}), true)
	ore = int(level.get("start_ore", 0)) + int(rules["start_ore_bonus"])
	_tower_defs = tower_defs
	_enemy_defs = enemy_defs
	grid = MineGrid.from_rows(level["grid"])
	gold = roundi(float(level["start_gold"]) * float(rules["start_gold_factor"])) + int(rules["start_gold_bonus"])
	max_lives = int(level["lives"]) + int(rules["lives_bonus"])
	lives = max_lives
	wave_count = level["waves"].size()


# --- Befehle des Spielers -------------------------------------------------

func allowed_towers() -> Array:
	return _level["towers"]


func tower_def(type: String) -> Dictionary:
	return _tower_defs.get(type, {})


## Was ein Turm in diesem Spiel kostet. Die Zwergenhalle kann den Preis senken.
func tower_cost(type: String) -> int:
	return maxi(1, roundi(float(_tower_defs[type]["cost"]) * float(rules["tower_cost_factor"])))


func tower_at(cell: Vector2i) -> Tower:
	return _towers_by_cell.get(cell)


func can_build(cell: Vector2i, type: String) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	if not _tower_defs.has(type) or type not in _level["towers"]:
		return Result.UNKNOWN_TOWER
	if grid.get_cell(cell) != MineGrid.Cell.BUILD:
		return Result.NOT_BUILDABLE
	if _towers_by_cell.has(cell):
		return Result.OCCUPIED
	if gold < tower_cost(type):
		return Result.NOT_ENOUGH_GOLD
	return Result.OK


func build_tower(cell: Vector2i, type: String) -> Result:
	var result := can_build(cell, type)
	if result != Result.OK:
		return result
	var t := Tower.new()
	t.id = _take_id()
	t.type = type
	t.def = _tower_defs[type]
	_refresh_stats(t)
	t.cell = cell
	t.pos = MineGrid.center(cell)
	gold -= tower_cost(t.type)
	t.paid = tower_cost(t.type)
	towers.append(t)
	_towers_by_cell[cell] = t
	tower_built.emit(t)
	return result


func sell_value(tower: Tower) -> int:
	return floori(tower.paid * float(rules["sell_refund"]))


func sell_tower(cell: Vector2i) -> bool:
	var t: Tower = _towers_by_cell.get(cell)
	if t == null or status != Status.RUNNING:
		return false
	gold += sell_value(t)
	for e in enemies:
		if e.held_by == t:
			e.held_by = null
			e.hold_left = 0.0
	towers.erase(t)
	_towers_by_cell.erase(cell)
	tower_sold.emit(t)
	return true


# --- Ausbau ---------------------------------------------------------------

static func _stats_for(def: Dictionary, level: int) -> Dictionary:
	var stats := def.duplicate()
	var upgrades: Array = def.get("upgrades", [])
	for i in mini(level - 1, upgrades.size()):
		stats.merge(upgrades[i], true)
	return stats


## Berechnet die gültigen Werte eines Turms neu: Grundwerte, Ausbaustufen, Spezialisierung, Gaben.
func _refresh_stats(t: Tower) -> void:
	var stats := _stats_for(t.def, t.level)
	for spec in t.def.get("specs", []):
		if spec["id"] == t.spec:
			for key in spec:
				if key not in ["id", "name_key", "desc_key", "ore"]:
					stats[key] = spec[key]
	if t.refine > 0:
		# Veredelung: mehr Schaden. Türme ohne Schaden gewinnen stattdessen etwas Reichweite.
		var gain := pow(float(rules["refine_gain"]), t.refine)
		if float(stats["damage"]) > 0.0 or stats.has("burn"):
			stats["damage"] = float(stats["damage"]) * gain
			if stats.has("burn"):
				var burn: Dictionary = stats["burn"].duplicate()
				burn["dps"] = float(burn["dps"]) * gain
				stats["burn"] = burn
		else:
			stats["range"] = float(stats["range"]) * pow(1.0 + (float(rules["refine_gain"]) - 1.0) * 0.5, t.refine)
	t.stats = _with_boons(t.type, stats)


## Wendet die Faktoren der gewählten Gaben auf Turmwerte an.
func _with_boons(type: String, stats: Dictionary) -> Dictionary:
	for scope in ["all", type]:
		var factors: Dictionary = _tower_factors.get(scope, {})
		for stat in factors:
			if stat == "burn":
				if stats.has("burn"):
					var burn: Dictionary = stats["burn"].duplicate()
					burn["dps"] = float(burn["dps"]) * float(factors[stat])
					stats["burn"] = burn
			elif stats.has(stat):
				stats[stat] = float(stats[stat]) * float(factors[stat])
		# Schalter aus Gaben, zum Beispiel durchschlagende Bolzen.
		for flag in _tower_flags.get(scope, {}):
			stats[flag] = _tower_flags[scope][flag]
	return stats


# --- Gaben ----------------------------------------------------------------

func boon_def(id: String) -> Dictionary:
	return _boon_defs.get(id, {})


## Die Wirkungen einer Gabe oder eines Fluchs als Liste. Die Daten erlauben "effect" oder "effects".
static func _effects_of(def: Dictionary) -> Array:
	return def["effects"] if def.has("effects") else [def["effect"]]


## Gaben, die in diesem Level etwas bewirken. Im normalen Spiel jede nur einmal.
## Im Endlosmodus dürfen sich Gaben wiederholen, außer reinen Schaltern.
func _available_boons() -> Array[String]:
	var out: Array[String] = []
	var has_ore := not grid.cells_of_type(MineGrid.Cell.ORE).is_empty()
	var ids := _boon_defs.keys()
	ids.sort()
	for id in ids:
		var def: Dictionary = _boon_defs[id]
		var effects := _effects_of(def)
		if id in active_boons:
			var stackable := endless
			for effect in effects:
				if effect["type"] in ["flag", "tower_flag"]:
					stackable = false
			if not stackable:
				continue
		var needs: Array = def.get("needs", [])
		if ("ore" in needs and not has_ore) or ("digging" in needs and not rules["digging"]):
			continue
		var useful := true
		for effect in effects:
			match effect["type"]:
				"stat", "tower_flag":
					var any := false
					for t in effect["towers"]:
						if t == "all" or t in _level["towers"]:
							any = true
					if not any:
						useful = false
				"ore":
					if not has_ore:
						useful = false
				"rule":
					if effect["key"] in ["dig_cost", "fill_cost"] and not rules["digging"]:
						useful = false
					if effect["key"] in ["ore_interval", "worker_cost", "worker_threat_radius"] and not has_ore:
						useful = false
		if useful:
			out.append(id)
	return out


func _offer_boons() -> void:
	var pool := _available_boons()
	pending_boons.clear()
	for i in mini(int(rules["boon_choices"]), pool.size()):
		var pick := _rng.randi_range(0, pool.size() - 1)
		pending_boons.append(pool[pick])
		pool.remove_at(pick)
	if not pending_boons.is_empty():
		boons_offered.emit(pending_boons.duplicate())


## Wählt eine der angebotenen Gaben. Sie gilt bis zum Ende des Levels.
func choose_boon(index: int) -> bool:
	if index < 0 or index >= pending_boons.size() or status != Status.RUNNING:
		return false
	var id := pending_boons[index]
	pending_boons.clear()
	active_boons.append(id)
	for effect in _effects_of(_boon_defs[id]):
		_apply_effect(effect)
	boon_chosen.emit(id)
	return true


## Wendet eine einzelne Wirkung einer Gabe oder eines Fluchs an.
func _apply_effect(effect: Dictionary) -> void:
	match effect["type"]:
		"stat":
			for t in effect["towers"]:
				if not _tower_factors.has(t):
					_tower_factors[t] = {}
				_tower_factors[t][effect["stat"]] = float(_tower_factors[t].get(effect["stat"], 1.0)) * float(effect["factor"])
			for t in towers:
				_refresh_stats(t)
		"tower_flag":
			for t in effect["towers"]:
				if not _tower_flags.has(t):
					_tower_flags[t] = {}
				_tower_flags[t][effect["flag"]] = effect["value"]
			for t in towers:
				_refresh_stats(t)
		"flag":
			flags[effect["flag"]] = effect.get("value", true)
		"gold":
			gold = maxi(0, gold + int(effect["amount"]))
		"ore":
			ore = maxi(0, ore + int(effect["amount"]))
		"heal":
			lives = mini(max_lives, lives + int(effect["amount"]))
		"lives":
			# Ein Preis in Leben lässt immer mindestens eines übrig.
			lives = maxi(1, lives + int(effect["amount"]))
		"bounty":
			bounty_factor *= float(effect["factor"])
		"enemy_hp":
			enemy_hp_extra *= float(effect["factor"])
		"enemy_speed":
			enemy_speed_factor *= float(effect["factor"])
		"resist":
			global_resist[effect["damage_type"]] = float(global_resist.get(effect["damage_type"], 1.0)) * float(effect["factor"])
		"rule":
			rules[effect["key"]] = float(rules[effect["key"]]) * float(effect["factor"])


# --- Endlosmodus ----------------------------------------------------------

## Nach dem Sieg mit allem Gebauten weiterkämpfen. Die Wellen entstehen ab jetzt von selbst und werden immer härter.
func continue_endless() -> bool:
	if status != Status.WON or endless:
		return false
	endless = true
	status = Status.RUNNING
	next_wave_in = float(_level["wave_pause"])
	return true


## Die laufende Nummer der Welle über das ganze Spiel, für die Anzeige.
func wave_number() -> int:
	return wave_index + 1


## Baut die Gruppen der nächsten Endlos-Welle: eine der letzten festen Wellen als Vorlage,
## mit etwas mehr Gegnern. Die eigentliche Steigerung kommt über die Lebenspunkte beim Erscheinen.
func _make_endless_groups() -> Array:
	var waves: Array = _level["waves"]
	var template: Dictionary = waves[waves.size() - 1 - _rng.randi_range(0, mini(2, waves.size() - 1))]
	var scale := minf(float(rules["endless_count_cap"]), 1.0 + float(rules["endless_count_growth"]) * endless_wave)
	var groups := []
	for g in template["groups"]:
		if _is_boss(g["enemy"]):
			continue
		var copy: Dictionary = g.duplicate()
		copy["count"] = maxi(1, roundi(int(g["count"]) * scale))
		copy["entrance"] = _rng.randi_range(0, grid.entrances.size() - 1)
		groups.append(copy)
	# Schemen: Flächenschaden prallt an ihnen ab. Sie zwingen zu Türmen, die einzelne Ziele treffen.
	var wraith_from := int(rules["endless_wraith_from"])
	if wraith_from > 0 and endless_wave >= wraith_from and _enemy_defs.has("wraith"):
		groups.append({"enemy": "wraith", "count": mini(14, 4 + endless_wave / 3), "interval": 0.9, "delay": 3.0,
			"entrance": _rng.randi_range(0, grid.entrances.size() - 1)})
	var boss_every := int(rules["endless_boss_every"])
	if boss_every > 0 and endless_wave % boss_every == 0:
		var boss := _boss_type()
		if boss != "":
			groups.append({"enemy": boss, "count": 1 + endless_wave / (boss_every * 3), "interval": 12.0, "delay": 2.0,
				"entrance": _rng.randi_range(0, grid.entrances.size() - 1)})
	return groups


func _is_boss(type: String) -> bool:
	return _enemy_defs.get(type, {}).get("unblockable", false)


func _boss_type() -> String:
	var ids := _enemy_defs.keys()
	ids.sort()
	for id in ids:
		if _is_boss(id):
			return id
	return ""


## Wählt zufällig einen Fluch. Jeder kann mehrfach kommen und wirkt dann stärker.
func _add_curse() -> void:
	if _curse_defs.is_empty():
		return
	var ids := _curse_defs.keys()
	ids.sort()
	var id: String = ids[_rng.randi_range(0, ids.size() - 1)]
	active_curses.append(id)
	for effect in _effects_of(_curse_defs[id]):
		_apply_effect(effect)
	curse_added.emit(id)


func curse_def(id: String) -> Dictionary:
	return _curse_defs.get(id, {})


func max_level(tower: Tower) -> int:
	return 1 + tower.def.get("upgrades", []).size()


## Erzkosten der nächsten Stufe, oder -1 auf der höchsten Stufe.
func upgrade_cost(tower: Tower) -> int:
	if tower.level >= max_level(tower):
		return -1
	return _ore_price(int(tower.def["upgrades"][tower.level - 1]["ore"]))


## Was eine Spezialisierung kostet.
func spec_cost(tower: Tower, index: int) -> int:
	return _ore_price(int(specs_of(tower)[index]["ore"]))


## Ein Erzpreis nach Abzug von Rabatten aus Gaben.
func _ore_price(base: int) -> int:
	return maxi(1, roundi(base * float(flags.get("ore_cost_factor", 1.0))))


## Die Werte, die der Turm nach dem nächsten Ausbau hätte. Leer auf der höchsten Stufe.
func next_stats(tower: Tower) -> Dictionary:
	if tower.level >= max_level(tower):
		return {}
	return _with_boons(tower.type, _stats_for(tower.def, tower.level + 1))


func can_upgrade(cell: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	var t: Tower = _towers_by_cell.get(cell)
	if t == null:
		return Result.NOT_ALLOWED
	if t.level >= max_level(t):
		return Result.MAX_LEVEL
	if ore < upgrade_cost(t):
		return Result.NOT_ENOUGH_ORE
	return Result.OK


func upgrade_tower(cell: Vector2i) -> Result:
	var result := can_upgrade(cell)
	if result != Result.OK:
		return result
	var t: Tower = _towers_by_cell[cell]
	ore -= upgrade_cost(t)
	t.level += 1
	_refresh_stats(t)
	tower_upgraded.emit(t)
	return result


# --- Zielwahl, Veredeln, Versetzen ----------------------------------------

## Stellt ein, worauf ein Turm schießt. Türme, die auf alles in Reichweite wirken, haben keine Zielwahl.
func set_target_mode(cell: Vector2i, mode: String) -> Result:
	var t: Tower = _towers_by_cell.get(cell)
	if t == null or mode not in TARGET_MODES or t.stats.get("kind", "projectile") != "projectile":
		return Result.NOT_ALLOWED
	t.target_mode = mode
	return Result.OK


## Goldpreis der nächsten Veredelung.
func refine_cost(tower: Tower) -> int:
	return roundi(float(rules["refine_base"]) * pow(float(rules["refine_growth"]), tower.refine))


func can_refine(cell: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	var t: Tower = _towers_by_cell.get(cell)
	if t == null:
		return Result.NOT_ALLOWED
	if t.spec == "":
		return Result.NOT_SPECIALIZED
	if gold < refine_cost(t):
		return Result.NOT_ENOUGH_GOLD
	return Result.OK


## Verbessert einen voll ausgebauten Turm weiter. Beliebig oft, jedes Mal teurer.
func refine_tower(cell: Vector2i) -> Result:
	var result := can_refine(cell)
	if result != Result.OK:
		return result
	var t: Tower = _towers_by_cell[cell]
	gold -= refine_cost(t)
	t.refine += 1
	_refresh_stats(t)
	tower_refined.emit(t)
	return result


func can_move_tower(from: Vector2i, to: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	if not _towers_by_cell.has(from) or grid.get_cell(to) != MineGrid.Cell.BUILD:
		return Result.NOT_ALLOWED
	if _towers_by_cell.has(to):
		return Result.OCCUPIED
	if gold < int(rules["move_cost"]):
		return Result.NOT_ENOUGH_GOLD
	return Result.OK


## Versetzt einen Turm auf einen freien Bauplatz. Er behält alles, was er hat.
func move_tower(from: Vector2i, to: Vector2i) -> Result:
	var result := can_move_tower(from, to)
	if result != Result.OK:
		return result
	var t: Tower = _towers_by_cell[from]
	gold -= int(rules["move_cost"])
	for e in enemies:
		if e.held_by == t:
			e.held_by = null
			e.hold_left = 0.0
	t.held_ids.clear()
	_towers_by_cell.erase(from)
	_towers_by_cell[to] = t
	t.cell = to
	t.pos = MineGrid.center(to)
	tower_moved.emit(t, from)
	return result


# --- Bauplätze im Endlosmodus ---------------------------------------------

## Preis des nächsten neuen Bauplatzes als [Gold, Erz].
func slot_cost() -> Array[int]:
	var factor := pow(float(rules["slot_growth"]), slots_created)
	return [roundi(float(rules["slot_gold"]) * factor), roundi(float(rules["slot_ore"]) * factor)]


func can_create_slot(cell: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	if grid.get_cell(cell) != MineGrid.Cell.ROCK:
		return Result.NOT_ALLOWED
	if not endless:
		return Result.ONLY_ENDLESS
	if dig_job_at(cell) != null:
		return Result.OCCUPIED
	if grid.cells_of_type(MineGrid.Cell.BUILD).size() >= int(rules["max_slots"]):
		return Result.LIMIT_REACHED
	var cost := slot_cost()
	if gold < cost[0]:
		return Result.NOT_ENOUGH_GOLD
	if ore < cost[1]:
		return Result.NOT_ENOUGH_ORE
	return Result.OK


## Macht aus Fels einen neuen Bauplatz. Sehr teuer, und jeder weitere kostet mehr.
func create_slot(cell: Vector2i) -> Result:
	var result := can_create_slot(cell)
	if result != Result.OK:
		return result
	var cost := slot_cost()
	gold -= cost[0]
	ore -= cost[1]
	slots_created += 1
	grid.set_cell(cell, MineGrid.Cell.BUILD)
	grid_changed.emit(cell)
	return result


func can_remove_slot(cell: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	if grid.get_cell(cell) != MineGrid.Cell.BUILD:
		return Result.NOT_ALLOWED
	if not endless:
		return Result.ONLY_ENDLESS
	if _towers_by_cell.has(cell):
		return Result.OCCUPIED
	return Result.OK


## Macht einen leeren Bauplatz wieder zu Fels. Dort lässt sich dann graben.
func remove_slot(cell: Vector2i) -> Result:
	var result := can_remove_slot(cell)
	if result != Result.OK:
		return result
	grid.set_cell(cell, MineGrid.Cell.ROCK)
	grid_changed.emit(cell)
	return result


# --- Durchbruch -----------------------------------------------------------

## Sucht die Randzellen, an denen ein neues Tor entstehen kann, samt dem Durchstich durch den Fels.
## Liefert eine Liste aus {"entrance": Zelle, "tunnel": [Zellen]}.
func breach_candidates() -> Array:
	var out := []
	var border: Array[Vector2i] = []
	for x in range(1, grid.width - 1):
		border.append(Vector2i(x, 0))
		border.append(Vector2i(x, grid.height - 1))
	for y in range(1, grid.height - 1):
		border.append(Vector2i(0, y))
		border.append(Vector2i(grid.width - 1, y))
	for edge in border:
		if grid.get_cell(edge) != MineGrid.Cell.GRANITE:
			continue
		# Breitensuche vom Rand durch Fels bis zur ersten Zelle, die einen Stollen berührt.
		var came := {edge: edge}
		var queue: Array[Vector2i] = [edge]
		var depth := {edge: 0}
		var goal := Vector2i(-1, -1)
		while not queue.is_empty() and goal.x < 0:
			var c: Vector2i = queue.pop_front()
			if c != edge and grid.touches_walkable(c):
				goal = c
				break
			if int(depth[c]) >= 6:
				continue
			for d in MineGrid.DIRS:
				var n: Vector2i = c + d
				if came.has(n) or grid.get_cell(n) != MineGrid.Cell.ROCK or n.x <= 0 or n.y <= 0 or n.x >= grid.width - 1 or n.y >= grid.height - 1:
					continue
				came[n] = c
				depth[n] = int(depth[c]) + 1
				queue.append(n)
		if goal.x < 0:
			continue
		var tunnel: Array[Vector2i] = []
		var cur := goal
		while cur != edge:
			tunnel.append(cur)
			cur = came[cur]
		# Weglänge vom neuen Tor zum Herz: Durchstich plus Restweg ab der Anschlusszelle.
		var join := 9999
		for d in MineGrid.DIRS:
			var dist := grid.distance(goal + d)
			if dist != MineGrid.UNREACHABLE:
				join = mini(join, dist)
		if tunnel.size() + join + 1 >= int(rules["breach_min_path"]):
			out.append({"entrance": edge, "tunnel": tunnel})
	return out


## Bricht an einer zufälligen Stelle ein neues Tor in die Mine. Ohne geeignete Stelle passiert nichts.
func _breach() -> bool:
	var candidates := breach_candidates()
	if candidates.is_empty():
		return false
	var pick: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
	for cell in pick["tunnel"]:
		var job := dig_job_at(cell)
		if job != null:
			# Dort wurde gerade gegraben: Auftrag streichen, Gold zurück.
			dig_jobs.erase(job)
			gold += int(rules["dig_cost"])
		grid.set_cell(cell, MineGrid.Cell.TUNNEL)
	grid.add_entrance(pick["entrance"])
	for e in enemies:
		if e.alive:
			_update_remaining(e)
	breached.emit(pick["entrance"])
	return true


# --- Spezialisierung ------------------------------------------------------

## Die Spezialisierungen, zwischen denen ein Turm auf der höchsten Stufe wählen kann.
func specs_of(tower: Tower) -> Array:
	return tower.def.get("specs", [])


func can_specialize(cell: Vector2i, index: int) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	var t: Tower = _towers_by_cell.get(cell)
	if t == null or index < 0 or index >= specs_of(t).size():
		return Result.NOT_ALLOWED
	if t.spec != "":
		return Result.ALREADY_SPECIALIZED
	if t.level < max_level(t):
		return Result.NOT_MAX_LEVEL
	if ore < spec_cost(t, index):
		return Result.NOT_ENOUGH_ORE
	return Result.OK


## Wählt eine der Spezialisierungen. Ihre Werte ersetzen die bisherigen, die Wahl ist endgültig.
func specialize(cell: Vector2i, index: int) -> Result:
	var result := can_specialize(cell, index)
	if result != Result.OK:
		return result
	var t: Tower = _towers_by_cell[cell]
	var spec: Dictionary = specs_of(t)[index]
	ore -= spec_cost(t, index)
	t.spec = spec["id"]
	_refresh_stats(t)
	tower_specialized.emit(t)
	return result


# --- Stollen --------------------------------------------------------------

func dig_job_at(cell: Vector2i) -> DigJob:
	for j in dig_jobs:
		if j.cell == cell:
			return j
	return null


func can_dig(cell: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	if not rules["digging"] or grid.get_cell(cell) != MineGrid.Cell.ROCK:
		return Result.NOT_ALLOWED
	if dig_job_at(cell) != null:
		return Result.OCCUPIED
	if not grid.touches_walkable(cell):
		return Result.NOT_CONNECTED
	if int(rules["max_digs"]) >= 0 and digs_started >= int(rules["max_digs"]):
		return Result.LIMIT_REACHED
	if gold < int(rules["dig_cost"]):
		return Result.NOT_ENOUGH_GOLD
	return Result.OK


## Beginnt, ein Felsfeld zum Stollen zu graben. Das Feld wird nach dig_time Sekunden begehbar.
func dig(cell: Vector2i) -> Result:
	var result := can_dig(cell)
	if result != Result.OK:
		return result
	gold -= int(rules["dig_cost"])
	digs_started += 1
	var job := DigJob.new()
	job.cell = cell
	job.total = float(rules["dig_time"])
	job.time_left = job.total
	dig_jobs.append(job)
	dig_started.emit(job)
	return result


func can_fill(cell: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	if not rules["digging"] or grid.get_cell(cell) != MineGrid.Cell.TUNNEL:
		return Result.NOT_ALLOWED
	for e in enemies:
		if e.alive and (e.target_cell == cell or MineGrid.cell_at(e.pos) == cell):
			return Result.ENEMY_IN_THE_WAY
	# Probeweise zuschütten und prüfen, ob jeder Eingang und jeder Gegner noch ans Ziel kommt.
	grid.set_cell(cell, MineGrid.Cell.ROCK)
	var ok := grid.has_path()
	if ok:
		for e in enemies:
			if e.alive and grid.distance(e.target_cell) == MineGrid.UNREACHABLE:
				ok = false
				break
	grid.set_cell(cell, MineGrid.Cell.TUNNEL)
	if not ok:
		return Result.BLOCKS_PATH
	if gold < int(rules["fill_cost"]):
		return Result.NOT_ENOUGH_GOLD
	return Result.OK


## Schüttet ein Stollenfeld sofort zu. Es wird wieder zu Fels.
func fill(cell: Vector2i) -> Result:
	var result := can_fill(cell)
	if result != Result.OK:
		return result
	gold -= int(rules["fill_cost"])
	grid.set_cell(cell, MineGrid.Cell.ROCK)
	for e in enemies:
		if e.alive:
			_update_remaining(e)
	grid_changed.emit(cell)
	return result


# --- Arbeiter -------------------------------------------------------------

func worker_at(cell: Vector2i) -> Worker:
	return _workers_by_cell.get(cell)


func can_place_worker(cell: Vector2i) -> Result:
	if status != Status.RUNNING:
		return Result.GAME_OVER
	if grid.get_cell(cell) != MineGrid.Cell.ORE:
		return Result.NOT_ALLOWED
	if _workers_by_cell.has(cell):
		return Result.OCCUPIED
	if not grid.touches_walkable(cell):
		return Result.NOT_CONNECTED
	if gold < int(rules["worker_cost"]):
		return Result.NOT_ENOUGH_GOLD
	return Result.OK


## Setzt einen Arbeiter an eine Erzader. Er baut Erz ab, solange keine Gegner in der Nähe sind.
func place_worker(cell: Vector2i) -> Result:
	var result := can_place_worker(cell)
	if result != Result.OK:
		return result
	gold -= int(rules["worker_cost"])
	var w := Worker.new()
	w.id = _take_id()
	w.cell = cell
	w.pos = MineGrid.center(cell)
	workers.append(w)
	_workers_by_cell[cell] = w
	worker_placed.emit(w)
	return result


func can_start_wave() -> bool:
	return status == Status.RUNNING and not wave_active and (wave_index + 1 < wave_count or endless)


func start_next_wave() -> bool:
	if not can_start_wave():
		return false
	# Wer die Welle startet, ohne zu wählen, verzichtet auf die Gabe.
	pending_boons.clear()
	wave_index += 1
	wave_active = true
	next_wave_in = 0.0
	_wave_time = 0.0
	_ward_used = false
	_spawn_queue.clear()
	var groups: Array
	if wave_index < wave_count:
		groups = _level["waves"][wave_index]["groups"]
	else:
		endless_wave += 1
		var curse_every := int(rules["endless_curse_every"])
		if curse_every > 0 and endless_wave % curse_every == 0:
			_add_curse()
		var breach_every := int(rules["endless_breach_every"])
		if breach_every > 0 and endless_wave % breach_every == 0:
			_breach()
		groups = _make_endless_groups()
	for g in groups:
		for i in int(g["count"]):
			_spawn_queue.append({
				"time": float(g.get("delay", 0.0)) + i * float(g.get("interval", 1.0)),
				"enemy": g["enemy"],
				"entrance": int(g.get("entrance", 0)),
			})
	_spawn_queue.sort_custom(func(a, b): return a["time"] < b["time"])
	wave_started.emit(wave_index)
	return true


# --- Zeitschritt ----------------------------------------------------------

## Rechnet genau einen Zeitschritt (DT Sekunden).
func step() -> void:
	if status != Status.RUNNING:
		return
	tick += 1
	_step_digs()
	_step_waves()
	_step_enemies()
	_step_workers()
	_step_towers()
	_step_projectiles()
	_cleanup()
	_check_end()


func _step_digs() -> void:
	if dig_jobs.is_empty():
		return
	var finished_jobs: Array[DigJob] = []
	for job in dig_jobs:
		job.time_left -= DT
		if job.time_left <= 0.0:
			finished_jobs.append(job)
	for job in finished_jobs:
		dig_jobs.erase(job)
		grid.set_cell(job.cell, MineGrid.Cell.TUNNEL)
		gold += int(flags.get("dig_gold", 0))
		for e in enemies:
			if e.alive:
				_update_remaining(e)
		grid_changed.emit(job.cell)


func _step_workers() -> void:
	if workers.is_empty():
		return
	var threat_sq := float(rules["worker_threat_radius"]) ** 2
	var interval := float(rules["ore_interval"])
	for w in workers:
		w.active = grid.touches_walkable(w.cell) and (wave_active or not rules["ore_only_during_waves"])
		if w.active:
			for e in enemies:
				if e.alive and e.pos.distance_squared_to(w.pos) <= threat_sq:
					w.active = false
					break
		if not w.active:
			continue
		w.progress += DT
		while w.progress >= interval:
			w.progress -= interval
			var amount := int(rules["ore_amount"])
			ore += amount
			w.mined += amount
			ore_mined.emit(w, amount)


func _step_waves() -> void:
	if wave_active:
		# Im Endlosmodus wartet der Nachschub, wenn schon sehr viele Gegner unterwegs sind. Das schützt die Bildrate.
		if endless_wave > 0 and enemies.size() >= ENDLESS_MAX_ENEMIES and not _spawn_queue.is_empty():
			return
		_wave_time += DT
		while not _spawn_queue.is_empty() and _spawn_queue[0]["time"] <= _wave_time:
			var s: Dictionary = _spawn_queue.pop_front()
			_spawn(s["enemy"], s["entrance"])
	elif wave_index >= 0 and (wave_index + 1 < wave_count or endless) and status == Status.RUNNING and pending_boons.is_empty():
		next_wave_in -= DT
		if next_wave_in <= 0.0:
			start_next_wave()


func _spawn(type: String, entrance: int) -> void:
	var cell := grid.entrances[entrance]
	_spawn_at(type, MineGrid.center(cell), grid.next_step(cell))


func _spawn_at(type: String, pos: Vector2, target_cell: Vector2i) -> void:
	var e := Enemy.new()
	e.id = _take_id()
	e.type = type
	e.def = _enemy_defs[type]
	# Lebenspunkte: Grundwert, mal Faktor des Levels, mal Faktor des Schwierigkeitsgrads.
	e.max_hp = float(e.def["hp"]) * float(_level.get("enemy_hp_scale", 1.0)) * float(rules["enemy_hp_factor"]) * enemy_hp_extra
	if endless_wave > 0:
		e.max_hp *= pow(float(rules["endless_hp_growth"]), endless_wave)
		if _is_boss(type):
			e.max_hp *= float(rules["endless_boss_hp"])
	e.hp = e.max_hp
	e.pos = pos
	e.prev_pos = e.pos
	e.target_cell = target_cell
	_update_remaining(e)
	enemies.append(e)
	enemy_spawned.emit(e)


func _step_enemies() -> void:
	for e in enemies:
		if not e.alive:
			continue
		e.prev_pos = e.pos
		_step_status(e)
		if not e.alive:
			continue
		_step_abilities(e)
		e.stun_immune_left = maxf(0.0, e.stun_immune_left - DT)
		if e.hold_left > 0.0:
			e.hold_left -= DT
			if e.hold_left <= 0.0:
				e.hold_left = 0.0
				e.held_by = null
			continue
		var budget := float(e.def["speed"]) * enemy_speed_factor * DT
		if e.slow_left > 0.0:
			budget *= e.slow_factor
		# Ein schneller Gegner kann in einem Schritt mehrere Zellenmitten passieren.
		while budget > 0.0:
			var goal := MineGrid.center(e.target_cell)
			var to_goal := e.pos.distance_to(goal)
			if to_goal > budget:
				e.pos = e.pos.move_toward(goal, budget)
				budget = 0.0
			else:
				e.pos = goal
				budget -= to_goal
				if e.target_cell == grid.heart:
					_leak(e)
					break
				var next := grid.next_step(e.target_cell)
				if next == e.target_cell:
					# Kein Weg von hier zum Herz. Das darf im Spiel nicht vorkommen, soll aber nie hängen bleiben.
					break
				e.target_cell = next
		if e.alive:
			_update_remaining(e)
	for spawn in _pending_spawns:
		_spawn_at(spawn["type"], spawn["pos"], spawn["target"])
	_pending_spawns.clear()


## Laufende Wirkungen auf einem Gegner: Brennen, Verlangsamung, eigene Heilkraft.
func _step_status(e: Enemy) -> void:
	if e.burn_left > 0.0:
		# Der letzte Schritt zählt nur anteilig, damit der Gesamtschaden genau stimmt.
		var t := minf(DT, e.burn_left)
		e.burn_left -= t
		_damage(e, e.burn_dps * t, "fire")
		if not e.alive:
			return
	if e.slow_left > 0.0:
		e.slow_left -= DT
		if e.slow_left <= 0.0:
			e.slow_left = 0.0
			e.slow_factor = 1.0
	if e.def.has("heal"):
		var heal: Dictionary = e.def["heal"]
		e.heal_timer += DT
		if e.heal_timer >= float(heal["interval"]):
			e.heal_timer = 0.0
			var r_sq := float(heal["radius"]) ** 2
			var healed := false
			for other in enemies:
				if other != e and other.alive and other.hp < other.max_hp and other.pos.distance_squared_to(e.pos) <= r_sq:
					other.hp = minf(other.max_hp, other.hp + float(heal["amount"]))
					healed = true
			if healed:
				enemies_healed.emit(e)


## Besondere Fähigkeiten eines Gegners: Verstärkung rufen und Erz stehlen.
func _step_abilities(e: Enemy) -> void:
	if e.def.has("summon"):
		var summon: Dictionary = e.def["summon"]
		e.summon_timer += DT
		if e.summon_timer >= float(summon["interval"]):
			e.summon_timer = 0.0
			for i in int(summon["count"]):
				_pending_spawns.append({"type": summon["enemy"], "pos": e.pos, "target": e.target_cell})
	if e.def.has("steal") and not e.has_stolen and ore > 0 and not flags.get("no_steal", false):
		var steal: Dictionary = e.def["steal"]
		var r_sq := float(steal["radius"]) ** 2
		for w in workers:
			if w.pos.distance_squared_to(e.pos) <= r_sq:
				var amount := mini(ore, int(steal["ore"]))
				ore -= amount
				e.has_stolen = true
				ore_stolen.emit(e, w, amount)
				break


## Wendet die Zusatzwirkungen eines Turms auf einen Gegner an.
## Gleiche Wirkungen stapeln sich nicht: es gilt die stärkere und die längere Restdauer.
func _apply_effects(e: Enemy, stats: Dictionary) -> void:
	if not e.alive:
		return
	if stats.has("slow"):
		var slow: Dictionary = stats["slow"]
		# Manche Gegner widerstehen der Verlangsamung teilweise.
		var factor := lerpf(float(slow["factor"]), 1.0, float(e.def.get("slow_resist", 0.0)))
		e.slow_factor = minf(e.slow_factor, factor) if e.slow_left > 0.0 else factor
		e.slow_left = maxf(e.slow_left, float(slow["duration"]))
	if stats.has("burn"):
		var burn: Dictionary = stats["burn"]
		e.burn_dps = maxf(e.burn_dps, float(burn["dps"])) if e.burn_left > 0.0 else float(burn["dps"])
		e.burn_left = maxf(e.burn_left, float(burn["duration"]))


func _update_remaining(e: Enemy) -> void:
	e.remaining = grid.distance(e.target_cell) + e.pos.distance_to(MineGrid.center(e.target_cell))


func _leak(e: Enemy) -> void:
	e.alive = false
	# Schutzrune: Der erste gewöhnliche Gegner jeder Welle am Herz kostet kein Leben. Bosse hält sie nicht auf.
	if flags.get("ward", false) and not _ward_used and not _is_boss(e.type):
		_ward_used = true
		leak_warded.emit(e)
	else:
		var cost := int(e.def["lives"])
		if endless_wave > 0 and _is_boss(e.type):
			cost = mini(cost, int(rules["endless_boss_lives"]))
		lives = maxi(0, lives - cost)
	enemy_removed.emit(e, "leaked")


func _step_towers() -> void:
	# Zwergenbräu: In den ersten Sekunden jeder Welle laden alle Türme schneller nach.
	var dt := DT
	if wave_active and flags.has("brew") and _wave_time <= float(flags["brew"]["seconds"]):
		dt *= float(flags["brew"]["factor"])
	for t in towers:
		t.cooldown_left = maxf(0.0, t.cooldown_left - dt)
		var kind: String = t.stats.get("kind", "projectile")
		if kind == "block":
			_step_block(t)
			continue
		if t.cooldown_left > 0.0:
			continue
		if kind == "aura":
			_pulse_aura(t)
			continue
		var target := _pick_target(t)
		if target == null:
			continue
		t.cooldown_left = float(t.stats["cooldown"])
		t.shots += 1
		var p := Projectile.new()
		p.id = _take_id()
		p.def = t.stats
		p.pos = t.pos
		p.prev_pos = t.pos
		p.target = target
		p.target_pos = target.pos
		projectiles.append(p)
		projectile_fired.emit(p)


## Der Schildwall hält Gegner in Reichweite fest und schlägt auf die Gehaltenen ein.
## Er hält höchstens capacity Gegner zugleich und jeden Gegner nur einmal.
func _step_block(t: Tower) -> void:
	var held: Array[Enemy] = []
	for e in enemies:
		if e.alive and e.held_by == t and e.hold_left > 0.0:
			held.append(e)
	var range_sq := float(t.stats["range"]) ** 2
	var capacity := int(t.stats["capacity"])
	if held.size() < capacity:
		for e in enemies:
			if held.size() >= capacity:
				break
			if not e.alive or e.hold_left > 0.0 or t.held_ids.has(e.id) or e.def.get("unblockable", false):
				continue
			if t.pos.distance_squared_to(e.pos) <= range_sq:
				e.held_by = t
				e.hold_left = float(t.stats["hold_time"])
				t.held_ids[e.id] = true
				held.append(e)
				enemy_held.emit(t, e)
	if t.cooldown_left <= 0.0 and not held.is_empty():
		t.cooldown_left = float(t.stats["cooldown"])
		t.shots += 1
		for e in held:
			_damage(e, float(t.stats["damage"]), t.stats.get("damage_type", ""))
		aura_pulsed.emit(t)


## Ein Turm ohne Geschoss wirkt auf alle Gegner in Reichweite zugleich.
func _pulse_aura(t: Tower) -> void:
	var range_sq := float(t.stats["range"]) ** 2
	var hit := false
	for e in enemies:
		if e.alive and t.pos.distance_squared_to(e.pos) <= range_sq:
			hit = true
			if float(t.stats["damage"]) > 0.0:
				_damage(e, float(t.stats["damage"]), t.stats.get("damage_type", ""))
			_apply_effects(e, t.stats)
	if hit:
		t.cooldown_left = float(t.stats["cooldown"])
		t.shots += 1
		aura_pulsed.emit(t)


## Wählt das Ziel nach der Einstellung des Turms: vorderster (kürzester Restweg), stärkster oder
## schwächster Gegner in Reichweite. Türme, die in Brand setzen, bevorzugen zuerst Gegner, die noch nicht brennen.
func _pick_target(t: Tower) -> Enemy:
	var best: Enemy = null
	var best_fresh := false
	var prefers_fresh: bool = t.stats.has("burn")
	var range_sq := float(t.stats["range"]) ** 2
	for e in enemies:
		if e.alive and t.pos.distance_squared_to(e.pos) <= range_sq:
			var fresh := prefers_fresh and e.burn_left <= 0.0
			if best == null or (fresh and not best_fresh) or (fresh == best_fresh and _better_target(t.target_mode, e, best)):
				best = e
				best_fresh = fresh
	return best


static func _better_target(mode: String, e: Enemy, best: Enemy) -> bool:
	match mode:
		"strong":
			return e.hp > best.hp or (e.hp == best.hp and e.remaining < best.remaining)
		"weak":
			return e.hp < best.hp or (e.hp == best.hp and e.remaining < best.remaining)
	return e.remaining < best.remaining


func _step_projectiles() -> void:
	for p in projectiles:
		p.prev_pos = p.pos
		if p.target != null and p.target.alive:
			p.target_pos = p.target.pos
		var splash := float(p.def["splash"])
		if (p.target == null or not p.target.alive) and splash <= 0.0:
			# Ein Einzelschuss ohne Ziel verfällt. Flächenschaden fliegt zum letzten Ort weiter.
			p.done = true
			continue
		p.pos = p.pos.move_toward(p.target_pos, float(p.def["projectile_speed"]) * DT)
		if p.pos.distance_to(p.target_pos) <= HIT_DISTANCE:
			p.pos = p.target_pos
			p.done = true
			_apply_hit(p, splash)
			projectile_hit.emit(p)


func _apply_hit(p: Projectile, splash: float) -> void:
	var damage := float(p.def["damage"])
	var type: String = p.def.get("damage_type", "")
	if splash > 0.0:
		var r_sq := splash * splash
		for e in enemies:
			var d_sq := e.pos.distance_squared_to(p.pos)
			if e.alive and d_sq <= r_sq:
				# falloff: Anteil des Schadens am Rand der Fläche. 1.0 bedeutet überall voller Schaden.
				var share := lerpf(1.0, float(p.def.get("falloff", 1.0)), sqrt(d_sq) / splash)
				_damage(e, damage * share, type)
				_apply_effects(e, p.def)
				_stun(e, float(p.def.get("stun", 0.0)))
	elif p.target != null and p.target.alive:
		var first := p.target
		_damage(first, damage, type)
		_apply_effects(first, p.def)
		if float(p.def.get("pierce", 0.0)) > 0.0:
			# Der Bolzen durchschlägt und trifft noch den nächsten Gegner in der Nähe.
			var next: Enemy = null
			var best := float(p.def["pierce"]) ** 2
			for e in enemies:
				if e != first and e.alive:
					var d := e.pos.distance_squared_to(first.pos)
					if d <= best:
						best = d
						next = e
			if next != null:
				_damage(next, damage, type)
				_apply_effects(next, p.def)


## Betäubt einen Gegner kurz. Danach ist er eine Weile dagegen gefeit, damit niemand dauerhaft festsitzt.
func _stun(e: Enemy, seconds: float) -> void:
	if seconds <= 0.0 or not e.alive or e.stun_immune_left > 0.0 or _is_boss(e.type):
		return
	e.hold_left = maxf(e.hold_left, seconds)
	e.stun_immune_left = STUN_IMMUNITY


## Fügt Schaden zu. Gegner können einzelnen Schadensarten widerstehen (resist: Art → Faktor).
func _damage(e: Enemy, amount: float, type := "") -> void:
	if not e.alive:
		return
	if type != "":
		if e.def.has("resist"):
			amount *= float(e.def["resist"].get(type, 1.0))
		amount *= float(global_resist.get(type, 1.0))
	if e.slow_left > 0.0:
		amount *= float(flags.get("frostbite", 1.0))
	if flags.has("last_stand") and lives < int(flags["last_stand"]["lives"]):
		amount *= float(flags["last_stand"]["factor"])
	e.hp -= amount
	if e.hp <= 0.0:
		e.hp = 0.0
		e.alive = false
		kills += 1
		var bounty := float(e.def["bounty"]) * bounty_factor
		if endless_wave > 0:
			bounty *= 1.0 + float(rules["endless_bounty_growth"]) * endless_wave
		gold += roundi(bounty)
		if flags.get("wildfire", false) and e.burn_left > 0.0:
			# Lauffeuer: Das Feuer springt auf Gegner in der Nähe über.
			for other in enemies:
				if other != e and other.alive and other.pos.distance_squared_to(e.pos) <= WILDFIRE_RADIUS * WILDFIRE_RADIUS:
					_apply_effects(other, {"burn": {"dps": e.burn_dps, "duration": maxf(e.burn_left, 2.0)}})
		enemy_removed.emit(e, "killed")


func _cleanup() -> void:
	peak_enemies = maxi(peak_enemies, enemies.size())
	enemies = enemies.filter(func(e: Enemy) -> bool: return e.alive)
	projectiles = projectiles.filter(func(p: Projectile) -> bool: return not p.done)


func _check_end() -> void:
	if lives <= 0:
		status = Status.LOST
		finished.emit(false)
		return
	if wave_active and _spawn_queue.is_empty() and enemies.is_empty():
		wave_active = false
		if wave_index < wave_count:
			gold += int(_level["waves"][wave_index].get("reward", 0))
		else:
			endless_cleared = endless_wave
			gold += int(rules["endless_reward"]) + 5 * endless_wave
		if flags.has("interest"):
			# Zinsen: ein Anteil des Goldes, bis zu einer Obergrenze.
			gold += mini(int(flags["interest"]["cap"]), floori(gold * float(flags["interest"]["rate"])))
		wave_cleared.emit(wave_index)
		if wave_index + 1 >= wave_count and not endless:
			status = Status.WON
			finished.emit(true)
		else:
			next_wave_in = float(_level["wave_pause"])
			var every := int(rules["endless_boon_every"]) if endless else int(rules["boon_every"])
			if every > 0 and (wave_index + 1) % every == 0:
				_offer_boons()


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Kompakter Zustand für Vergleiche in Tests.
func snapshot() -> Dictionary:
	var es := []
	for e in enemies:
		es.append([e.id, e.type, e.hp, e.pos])
	return {
		"tick": tick, "status": status, "gold": gold, "ore": ore, "lives": lives, "kills": kills,
		"wave": wave_index, "enemies": es, "towers": towers.size(), "projectiles": projectiles.size(),
	}
