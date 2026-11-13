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
}

const TICK_RATE := 60
const DT := 1.0 / TICK_RATE
## Anteil der Baukosten, den ein Verkauf erstattet.
const SELL_REFUND := 0.7
## So nah am Ziel gilt ein Geschoss als angekommen.
const HIT_DISTANCE := 0.05
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


class Tower extends RefCounted:
	var id := 0
	var type := ""
	var def := {}
	var cell := Vector2i.ZERO
	var pos := Vector2.ZERO
	var cooldown_left := 0.0
	var shots := 0
	var level := 1
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

var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var projectiles: Array[Projectile] = []
var dig_jobs: Array[DigJob] = []
var workers: Array[Worker] = []
var digs_started := 0
var rules := {}

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


func _init(level: Dictionary, tower_defs: Dictionary, enemy_defs: Dictionary, global_rules := {}) -> void:
	_level = level
	rules = DEFAULT_RULES.duplicate()
	rules.merge(global_rules, true)
	rules.merge(level.get("rules", {}), true)
	ore = int(level.get("start_ore", 0))
	_tower_defs = tower_defs
	_enemy_defs = enemy_defs
	grid = MineGrid.from_rows(level["grid"])
	gold = roundi(float(level["start_gold"]) * float(rules["start_gold_factor"]))
	max_lives = int(level["lives"])
	lives = int(level["lives"])
	wave_count = level["waves"].size()


# --- Befehle des Spielers -------------------------------------------------

func allowed_towers() -> Array:
	return _level["towers"]


func tower_def(type: String) -> Dictionary:
	return _tower_defs.get(type, {})


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
	if gold < int(_tower_defs[type]["cost"]):
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
	t.stats = _stats_for(t.def, 1)
	t.cell = cell
	t.pos = MineGrid.center(cell)
	gold -= int(t.def["cost"])
	towers.append(t)
	_towers_by_cell[cell] = t
	tower_built.emit(t)
	return result


func sell_value(tower: Tower) -> int:
	return floori(int(tower.def["cost"]) * SELL_REFUND)


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


func max_level(tower: Tower) -> int:
	return 1 + tower.def.get("upgrades", []).size()


## Erzkosten der nächsten Stufe, oder -1 auf der höchsten Stufe.
func upgrade_cost(tower: Tower) -> int:
	if tower.level >= max_level(tower):
		return -1
	return int(tower.def["upgrades"][tower.level - 1]["ore"])


## Die Werte, die der Turm nach dem nächsten Ausbau hätte. Leer auf der höchsten Stufe.
func next_stats(tower: Tower) -> Dictionary:
	if tower.level >= max_level(tower):
		return {}
	return _stats_for(tower.def, tower.level + 1)


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
	t.stats = _stats_for(t.def, t.level)
	tower_upgraded.emit(t)
	return result


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
	if ore < int(specs_of(t)[index]["ore"]):
		return Result.NOT_ENOUGH_ORE
	return Result.OK


## Wählt eine der Spezialisierungen. Ihre Werte ersetzen die bisherigen, die Wahl ist endgültig.
func specialize(cell: Vector2i, index: int) -> Result:
	var result := can_specialize(cell, index)
	if result != Result.OK:
		return result
	var t: Tower = _towers_by_cell[cell]
	var spec: Dictionary = specs_of(t)[index]
	ore -= int(spec["ore"])
	t.spec = spec["id"]
	var stats := t.stats.duplicate()
	for key in spec:
		if key not in ["id", "name_key", "desc_key", "ore"]:
			stats[key] = spec[key]
	t.stats = stats
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
	return status == Status.RUNNING and not wave_active and wave_index + 1 < wave_count


func start_next_wave() -> bool:
	if not can_start_wave():
		return false
	wave_index += 1
	wave_active = true
	next_wave_in = 0.0
	_wave_time = 0.0
	_spawn_queue.clear()
	for g in _level["waves"][wave_index]["groups"]:
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
		w.active = grid.touches_walkable(w.cell)
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
		_wave_time += DT
		while not _spawn_queue.is_empty() and _spawn_queue[0]["time"] <= _wave_time:
			var s: Dictionary = _spawn_queue.pop_front()
			_spawn(s["enemy"], s["entrance"])
	elif wave_index >= 0 and wave_index + 1 < wave_count:
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
	e.max_hp = float(e.def["hp"]) * float(rules["enemy_hp_factor"])
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
		if e.hold_left > 0.0:
			e.hold_left -= DT
			if e.hold_left <= 0.0:
				e.hold_left = 0.0
				e.held_by = null
			continue
		var budget := float(e.def["speed"]) * DT
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
				e.target_cell = grid.next_step(e.target_cell)
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
	if e.def.has("steal") and not e.has_stolen and ore > 0:
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
	lives = maxi(0, lives - int(e.def["lives"]))
	enemy_removed.emit(e, "leaked")


func _step_towers() -> void:
	for t in towers:
		t.cooldown_left = maxf(0.0, t.cooldown_left - DT)
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


## Zielwahl "am weitesten vorn": der Gegner in Reichweite mit dem kürzesten Restweg.
## Türme, die in Brand setzen, bevorzugen Gegner, die noch nicht brennen.
func _pick_target(t: Tower) -> Enemy:
	var best: Enemy = null
	var best_fresh := false
	var prefers_fresh: bool = t.stats.has("burn")
	var range_sq := float(t.stats["range"]) ** 2
	for e in enemies:
		if e.alive and t.pos.distance_squared_to(e.pos) <= range_sq:
			var fresh := prefers_fresh and e.burn_left <= 0.0
			if best == null or (fresh and not best_fresh) or (fresh == best_fresh and e.remaining < best.remaining):
				best = e
				best_fresh = fresh
	return best


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
	if splash > 0.0:
		var r_sq := splash * splash
		for e in enemies:
			if e.alive and e.pos.distance_squared_to(p.pos) <= r_sq:
				_damage(e, damage, p.def.get("damage_type", ""))
				_apply_effects(e, p.def)
	elif p.target != null and p.target.alive:
		_damage(p.target, damage, p.def.get("damage_type", ""))
		_apply_effects(p.target, p.def)


## Fügt Schaden zu. Gegner können einzelnen Schadensarten widerstehen (resist: Art → Faktor).
func _damage(e: Enemy, amount: float, type := "") -> void:
	if not e.alive:
		return
	if type != "" and e.def.has("resist"):
		amount *= float(e.def["resist"].get(type, 1.0))
	e.hp -= amount
	if e.hp <= 0.0:
		e.hp = 0.0
		e.alive = false
		kills += 1
		gold += int(e.def["bounty"])
		enemy_removed.emit(e, "killed")


func _cleanup() -> void:
	enemies = enemies.filter(func(e: Enemy) -> bool: return e.alive)
	projectiles = projectiles.filter(func(p: Projectile) -> bool: return not p.done)


func _check_end() -> void:
	if lives <= 0:
		status = Status.LOST
		finished.emit(false)
		return
	if wave_active and _spawn_queue.is_empty() and enemies.is_empty():
		wave_active = false
		gold += int(_level["waves"][wave_index].get("reward", 0))
		wave_cleared.emit(wave_index)
		if wave_index + 1 >= wave_count:
			status = Status.WON
			finished.emit(true)
		else:
			next_wave_in = float(_level["wave_pause"])


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
