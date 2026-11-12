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
signal projectile_fired(projectile: Projectile)
signal projectile_hit(projectile: Projectile)
signal wave_started(index: int)
signal wave_cleared(index: int)
signal finished(won: bool)

enum Status { RUNNING, WON, LOST }
enum BuildResult { OK, NOT_BUILDABLE, OCCUPIED, UNKNOWN_TOWER, NOT_ENOUGH_GOLD, GAME_OVER }

const TICK_RATE := 60
const DT := 1.0 / TICK_RATE
## Anteil der Baukosten, den ein Verkauf erstattet.
const SELL_REFUND := 0.7
## So nah am Ziel gilt ein Geschoss als angekommen.
const HIT_DISTANCE := 0.05


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


class Tower extends RefCounted:
	var id := 0
	var type := ""
	var def := {}
	var cell := Vector2i.ZERO
	var pos := Vector2.ZERO
	var cooldown_left := 0.0
	var shots := 0


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
var lives := 0
var tick := 0
var kills := 0

var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var projectiles: Array[Projectile] = []

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
var _spawn_queue: Array[Dictionary] = []
var _wave_time := 0.0
var _next_id := 1


func _init(level: Dictionary, tower_defs: Dictionary, enemy_defs: Dictionary) -> void:
	_level = level
	_tower_defs = tower_defs
	_enemy_defs = enemy_defs
	grid = MineGrid.from_rows(level["grid"])
	gold = int(level["start_gold"])
	lives = int(level["lives"])
	wave_count = level["waves"].size()


# --- Befehle des Spielers -------------------------------------------------

func allowed_towers() -> Array:
	return _level["towers"]


func tower_def(type: String) -> Dictionary:
	return _tower_defs.get(type, {})


func tower_at(cell: Vector2i) -> Tower:
	return _towers_by_cell.get(cell)


func can_build(cell: Vector2i, type: String) -> BuildResult:
	if status != Status.RUNNING:
		return BuildResult.GAME_OVER
	if not _tower_defs.has(type) or type not in _level["towers"]:
		return BuildResult.UNKNOWN_TOWER
	if grid.get_cell(cell) != MineGrid.Cell.BUILD:
		return BuildResult.NOT_BUILDABLE
	if _towers_by_cell.has(cell):
		return BuildResult.OCCUPIED
	if gold < int(_tower_defs[type]["cost"]):
		return BuildResult.NOT_ENOUGH_GOLD
	return BuildResult.OK


func build_tower(cell: Vector2i, type: String) -> BuildResult:
	var result := can_build(cell, type)
	if result != BuildResult.OK:
		return result
	var t := Tower.new()
	t.id = _take_id()
	t.type = type
	t.def = _tower_defs[type]
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
	towers.erase(t)
	_towers_by_cell.erase(cell)
	tower_sold.emit(t)
	return true


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
	_step_waves()
	_step_enemies()
	_step_towers()
	_step_projectiles()
	_cleanup()
	_check_end()


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
	var e := Enemy.new()
	e.id = _take_id()
	e.type = type
	e.def = _enemy_defs[type]
	e.max_hp = float(e.def["hp"])
	e.hp = e.max_hp
	var cell := grid.entrances[entrance]
	e.pos = MineGrid.center(cell)
	e.prev_pos = e.pos
	e.target_cell = grid.next_step(cell)
	_update_remaining(e)
	enemies.append(e)
	enemy_spawned.emit(e)


func _step_enemies() -> void:
	for e in enemies:
		if not e.alive:
			continue
		e.prev_pos = e.pos
		var budget := float(e.def["speed"]) * DT
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


func _update_remaining(e: Enemy) -> void:
	e.remaining = grid.distance(e.target_cell) + e.pos.distance_to(MineGrid.center(e.target_cell))


func _leak(e: Enemy) -> void:
	e.alive = false
	lives = maxi(0, lives - int(e.def["lives"]))
	enemy_removed.emit(e, "leaked")


func _step_towers() -> void:
	for t in towers:
		t.cooldown_left = maxf(0.0, t.cooldown_left - DT)
		if t.cooldown_left > 0.0:
			continue
		var target := _pick_target(t)
		if target == null:
			continue
		t.cooldown_left = float(t.def["cooldown"])
		t.shots += 1
		var p := Projectile.new()
		p.id = _take_id()
		p.def = t.def
		p.pos = t.pos
		p.prev_pos = t.pos
		p.target = target
		p.target_pos = target.pos
		projectiles.append(p)
		projectile_fired.emit(p)


## Zielwahl "am weitesten vorn": der Gegner in Reichweite mit dem kürzesten Restweg.
func _pick_target(t: Tower) -> Enemy:
	var best: Enemy = null
	var range_sq := float(t.def["range"]) ** 2
	for e in enemies:
		if e.alive and t.pos.distance_squared_to(e.pos) <= range_sq:
			if best == null or e.remaining < best.remaining:
				best = e
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
				_damage(e, damage)
	elif p.target != null and p.target.alive:
		_damage(p.target, damage)


func _damage(e: Enemy, amount: float) -> void:
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
		"tick": tick, "status": status, "gold": gold, "lives": lives, "kills": kills,
		"wave": wave_index, "enemies": es, "towers": towers.size(), "projectiles": projectiles.size(),
	}
