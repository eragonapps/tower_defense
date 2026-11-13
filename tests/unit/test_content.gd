extends GutTest
## Schadensarten und Panzerung, Schildwall, Boss-Fähigkeiten, Erzdiebe.

const GRID := ["E..............H", "#o:::o:::o:*:::#"]

var towers := {
	"bow": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "pierce"},
	"bomb": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 0.5, "projectile_speed": 50.0, "color": "#fff", "damage_type": "blunt"},
	"fire": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 20.0, "damage": 0, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "fire",
		"burn": {"dps": 10, "duration": 2.0}},
	"rune": {"name_key": "T", "kind": "aura", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"slow": {"factor": 0.5, "duration": 1.5}},
	"wall": {"name_key": "T", "kind": "block", "cost": 50, "range": 1.2, "cooldown": 1.0, "damage": 5, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"damage_type": "blunt", "capacity": 2, "hold_time": 3.0},
}
var enemies := {
	"plain": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0},
	"armored": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0, "resist": {"pierce": 0.25, "fire": 0.5}},
	"boss": {"name_key": "E", "hp": 5000, "speed": 1.0, "bounty": 0, "lives": 9, "color": "#fff", "size": 2.0,
		"slow_resist": 0.6, "unblockable": true, "summon": {"enemy": "plain", "count": 2, "interval": 2.0}},
	"thief": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0, "steal": {"ore": 6, "radius": 1.6}},
}


func _sim(groups: Array, build: Dictionary, extra := {}) -> GameSim:
	var level := {
		"start_gold": 1000, "lives": 50, "wave_pause": 3.0, "towers": towers.keys(), "grid": GRID,
		"waves": [{"reward": 0, "groups": groups}],
	}
	level.merge(extra, true)
	var sim := GameSim.new(level, towers, enemies)
	for cell in build:
		assert_eq(sim.build_tower(cell, build[cell]), GameSim.Result.OK)
	sim.start_next_wave()
	return sim


func _run(sim: GameSim, seconds: float) -> void:
	for i in int(round(seconds * GameSim.TICK_RATE)):
		sim.step()


func _lost(sim: GameSim, index := 0) -> float:
	return sim.enemies[index].max_hp - sim.enemies[index].hp


# --- Schadensarten --------------------------------------------------------

func test_armor_reduces_arrow_damage_but_not_bomb_damage() -> void:
	var results := {}
	for tower in ["bow", "bomb"]:
		for enemy in ["plain", "armored"]:
			var sim := _sim([{"enemy": enemy, "count": 1}], {Vector2i(5, 1): tower})
			_run(sim, 9.0)
			results[tower + "/" + enemy] = _lost(sim)
	assert_gt(results["bow/plain"], 50.0)
	assert_almost_eq(results["bow/armored"], results["bow/plain"] * 0.25, 0.01)
	assert_almost_eq(results["bomb/armored"], results["bomb/plain"], 0.01)


func test_burn_counts_as_fire_damage() -> void:
	var plain := _sim([{"enemy": "plain", "count": 1}], {Vector2i(5, 1): "fire"})
	var armored := _sim([{"enemy": "armored", "count": 1}], {Vector2i(5, 1): "fire"})
	_run(plain, 9.0)
	_run(armored, 9.0)
	assert_almost_eq(_lost(plain), 20.0, 0.001)
	assert_almost_eq(_lost(armored), 10.0, 0.001)


# --- Schildwall -----------------------------------------------------------

func test_wall_holds_enemies_for_its_hold_time() -> void:
	var free := _sim([{"enemy": "plain", "count": 1}], {})
	var blocked := _sim([{"enemy": "plain", "count": 1}], {Vector2i(5, 1): "wall"})
	watch_signals(blocked)
	_run(free, 10.0)
	_run(blocked, 10.0)
	assert_signal_emit_count(blocked, "enemy_held", 1)
	assert_almost_eq(free.enemies[0].pos.x - blocked.enemies[0].pos.x, 3.0, 0.05, "genau 3 Sekunden Rückstand")
	# Drei Sekunden gehalten, ein Schlag pro Sekunde zu 5 Schaden.
	assert_between(_lost(blocked), 15.0, 20.0)


func test_wall_holds_at_most_its_capacity_and_each_enemy_once() -> void:
	var sim := _sim([{"enemy": "plain", "count": 4, "interval": 0.3}], {Vector2i(5, 1): "wall"})
	var max_held := 0
	var held_ever := {}
	for i in 900:
		sim.step()
		var held := 0
		for e in sim.enemies:
			if e.hold_left > 0.0:
				held += 1
				held_ever[e.id] = true
		max_held = maxi(max_held, held)
	assert_eq(max_held, 2)
	assert_gte(held_ever.size(), 2)
	assert_eq(sim.towers[0].held_ids.size(), held_ever.size(), "kein Gegner wurde zweimal gehalten")


func test_selling_the_wall_releases_its_enemies() -> void:
	var sim := _sim([{"enemy": "plain", "count": 1}], {Vector2i(5, 1): "wall"})
	_run(sim, 5.0)
	var e := sim.enemies[0]
	assert_gt(e.hold_left, 0.0)
	var x := e.pos.x
	sim.sell_tower(Vector2i(5, 1))
	assert_eq(e.hold_left, 0.0)
	_run(sim, 1.0)
	assert_almost_eq(e.pos.x, x + 1.0, 0.05)


func test_held_enemy_can_still_be_shot() -> void:
	var sim := _sim([{"enemy": "plain", "count": 1}], {Vector2i(5, 1): "wall", Vector2i(4, 1): "bow"}, {"grid": ["E..............H", "#o::oo:::::::::#"]})
	_run(sim, 6.5)
	assert_gt(sim.enemies[0].hold_left, 0.0)
	var before := sim.enemies[0].hp
	_run(sim, 1.0)
	assert_lt(sim.enemies[0].hp, before - 10.0)


# --- Boss -----------------------------------------------------------------

func test_boss_cannot_be_held() -> void:
	var sim := _sim([{"enemy": "boss", "count": 1}], {Vector2i(5, 1): "wall"}, {"lives": 500})
	var boss := sim.enemies[0] if not sim.enemies.is_empty() else null
	_run(sim, 0.1)
	boss = sim.enemies[0]
	_run(sim, 7.8)
	assert_eq(boss.hold_left, 0.0)
	assert_false(sim.towers[0].held_ids.has(boss.id))
	assert_almost_eq(boss.pos.x, 0.5 + 7.9, 0.05)


func test_boss_summons_minions_at_its_position() -> void:
	var sim := _sim([{"enemy": "boss", "count": 1}], {})
	_run(sim, 1.9)
	assert_eq(sim.enemies.size(), 1)
	_run(sim, 0.2)
	assert_eq(sim.enemies.size(), 3, "zwei Schergen nach 2 Sekunden")
	var boss := sim.enemies[0]
	for i in [1, 2]:
		assert_eq(sim.enemies[i].type, "plain")
		assert_almost_eq(sim.enemies[i].pos.x, boss.pos.x, 0.2)
		assert_eq(sim.enemies[i].target_cell, boss.target_cell)
	_run(sim, 4.0)
	assert_eq(sim.enemies.size(), 7)
	# Das Level endet erst, wenn auch die Gerufenen weg sind.
	_run(sim, 30.0)
	assert_eq(sim.status, GameSim.Status.WON)
	assert_lt(sim.lives, 50 - 9)


func test_boss_resists_part_of_the_slow() -> void:
	var sim := _sim([{"enemy": "boss", "count": 1}, {"enemy": "plain", "count": 1, "delay": 0.2}], {Vector2i(5, 1): "rune"}, {"lives": 500})
	_run(sim, 4.5)
	var boss: GameSim.Enemy
	var plain: GameSim.Enemy
	for e in sim.enemies:
		if e.type == "boss":
			boss = e
		elif e.slow_left > 0.0 and plain == null:
			plain = e
	assert_almost_eq(boss.slow_factor, 0.8, 0.001, "0,5 mit 60 % Widerstand ergibt 0,8")
	assert_not_null(plain)
	assert_eq(plain.slow_factor, 0.5)


# --- Erzdiebe -------------------------------------------------------------

func test_thief_steals_ore_once_when_passing_a_worker() -> void:
	var sim := _sim([{"enemy": "thief", "count": 1}], {}, {"start_ore": 10, "rules": {"ore_interval": 1000.0}})
	assert_eq(sim.place_worker(Vector2i(11, 1)), GameSim.Result.OK)
	watch_signals(sim)
	_run(sim, 9.0)
	assert_eq(sim.ore, 10, "noch nicht in der Nähe")
	_run(sim, 3.0)
	assert_signal_emit_count(sim, "ore_stolen", 1)
	assert_eq(sim.ore, 4)
	assert_true(sim.enemies[0].has_stolen)
	_run(sim, 2.0)
	assert_eq(sim.ore, 4, "jeder Dieb stiehlt nur einmal")


func test_thief_cannot_steal_more_than_there_is() -> void:
	var sim := _sim([{"enemy": "thief", "count": 3, "interval": 0.3}], {}, {"start_ore": 8, "rules": {"ore_interval": 1000.0}})
	sim.place_worker(Vector2i(11, 1))
	_run(sim, 13.0)
	assert_eq(sim.ore, 0, "zwei Diebe nehmen 6 und 2, der dritte geht leer aus")
	assert_true(sim.enemies[0].has_stolen)
	assert_true(sim.enemies[1].has_stolen)
	assert_false(sim.enemies[2].has_stolen)


func test_thief_ignores_veins_without_a_worker() -> void:
	var sim := _sim([{"enemy": "thief", "count": 1}], {}, {"start_ore": 10})
	_run(sim, 14.0)
	assert_eq(sim.ore, 10)
