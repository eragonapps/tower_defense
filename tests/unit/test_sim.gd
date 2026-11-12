extends GutTest
## Spielsimulation: Türme, Kampf, Wirtschaft, Wellen, Sieg und Niederlage.

const DT := GameSim.DT

var _ticks := [0]
var towers := {
	"bow": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 0.0, "projectile_speed": 20.0, "color": "#fff"},
	"bomb": {"name_key": "T", "cost": 80, "range": 3.0, "cooldown": 2.0, "damage": 20, "splash": 1.0, "projectile_speed": 10.0, "color": "#fff"},
}
var enemies := {
	"walker": {"name_key": "E", "hp": 30, "speed": 1.0, "bounty": 7, "lives": 1, "color": "#fff", "size": 1.0},
	"tank": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 50, "lives": 3, "color": "#fff", "size": 1.0},
	"runner": {"name_key": "E", "hp": 10, "speed": 200.0, "bounty": 1, "lives": 1, "color": "#fff", "size": 1.0},
}


func _level(groups: Array, extra := {}) -> Dictionary:
	var level := {
		"start_gold": 100, "lives": 5, "wave_pause": 3.0, "towers": ["bow", "bomb"],
		"grid": [
			"############",
			"E..........H",
			"#o:::o:::::#",
			"############",
		],
		"waves": [{"reward": 10, "groups": groups}],
	}
	level.merge(extra, true)
	return level


func _sim(groups: Array, extra := {}) -> GameSim:
	return GameSim.new(_level(groups, extra), towers, enemies)


func _run(sim: GameSim, seconds: float) -> void:
	for i in int(round(seconds * GameSim.TICK_RATE)):
		sim.step()


# --- Wirtschaft -----------------------------------------------------------

func test_building_costs_gold_and_places_tower() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}])
	watch_signals(sim)
	assert_eq(sim.build_tower(Vector2i(1, 2), "bow"), GameSim.Result.OK)
	assert_eq(sim.gold, 50)
	assert_eq(sim.towers.size(), 1)
	assert_not_null(sim.tower_at(Vector2i(1, 2)))
	assert_signal_emitted(sim, "tower_built")


func test_build_is_rejected_with_reason() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}])
	assert_eq(sim.build_tower(Vector2i(2, 2), "bow"), GameSim.Result.NOT_BUILDABLE, "Fels")
	assert_eq(sim.build_tower(Vector2i(3, 1), "bow"), GameSim.Result.NOT_BUILDABLE, "Stollen")
	assert_eq(sim.build_tower(Vector2i(1, 2), "laser"), GameSim.Result.UNKNOWN_TOWER)
	assert_eq(sim.build_tower(Vector2i(1, 2), "bow"), GameSim.Result.OK)
	assert_eq(sim.build_tower(Vector2i(1, 2), "bow"), GameSim.Result.OCCUPIED)
	assert_eq(sim.build_tower(Vector2i(5, 2), "bomb"), GameSim.Result.NOT_ENOUGH_GOLD)
	assert_eq(sim.gold, 50, "abgelehnte Bauten kosten nichts")
	assert_eq(sim.towers.size(), 1)


func test_tower_not_allowed_in_level_is_rejected() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}], {"towers": ["bow"]})
	assert_eq(sim.build_tower(Vector2i(1, 2), "bomb"), GameSim.Result.UNKNOWN_TOWER)


func test_selling_refunds_the_fixed_share() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}])
	sim.build_tower(Vector2i(1, 2), "bow")
	assert_true(sim.sell_tower(Vector2i(1, 2)))
	assert_eq(sim.gold, 50 + 35)
	assert_eq(sim.towers.size(), 0)
	assert_null(sim.tower_at(Vector2i(1, 2)))
	assert_false(sim.sell_tower(Vector2i(1, 2)), "leerer Platz")
	assert_eq(sim.build_tower(Vector2i(1, 2), "bow"), GameSim.Result.OK, "Platz ist wieder frei")


func test_kill_pays_bounty_and_wave_pays_reward() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}])
	sim.build_tower(Vector2i(1, 2), "bow")
	sim.start_next_wave()
	_run(sim, 10)
	assert_eq(sim.kills, 1)
	assert_eq(sim.gold, 50 + 7 + 10)


# --- Türme und Kampf ------------------------------------------------------

func test_tower_only_shoots_enemies_in_range() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}])
	sim.build_tower(Vector2i(5, 2), "bow")
	var tower := sim.towers[0]
	sim.start_next_wave()
	# Reichweite 2 um (5.5, 2.5): der Gegner auf Höhe y=1.5 ist ab x ≈ 3.77 erreichbar.
	_run(sim, 3.0)
	assert_eq(tower.shots, 0, "bei x=3.5 noch außer Reichweite")
	_run(sim, 0.5)
	assert_gt(tower.shots, 0, "bei x=4.0 in Reichweite")
	_run(sim, 4.0)
	var shots := tower.shots
	_run(sim, 1.0)
	assert_eq(tower.shots, shots, "hinter x≈7.23 wieder außer Reichweite")


func test_fire_rate_matches_cooldown() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}], {"grid": ["E..........H", "#o:::::::::#"]})
	# Gegner bleibt lange in Reichweite 2 um (1.5, 1.5): x von 0.5 bis ≈3.23.
	sim.build_tower(Vector2i(1, 1), "bow")
	sim.start_next_wave()
	_run(sim, 2.0)
	assert_between(sim.towers[0].shots, 4, 5, "alle 0,5 s ein Schuss")


func test_targets_the_enemy_furthest_along() -> void:
	var sim := _sim([{"enemy": "tank", "count": 2, "interval": 1.0}], {"grid": ["E..........H", "#:o::::::::#"]})
	sim.build_tower(Vector2i(2, 1), "bow")
	sim.start_next_wave()
	_run(sim, 2.5)
	var first: GameSim.Enemy = sim.enemies[0]
	var second: GameSim.Enemy = sim.enemies[1]
	assert_lt(first.remaining, second.remaining)
	assert_lt(first.hp, first.max_hp, "der vordere wird beschossen")
	assert_eq(second.hp, second.max_hp, "der hintere nicht")


func test_splash_hits_everything_in_radius_and_nothing_outside() -> void:
	var sim := _sim([
		{"enemy": "tank", "count": 2, "interval": 0.5},
		{"enemy": "tank", "count": 1, "delay": 3.0},
	], {"grid": ["E..........H", "#:::::::o::#"]})
	sim.build_tower(Vector2i(8, 1), "bomb")
	sim.start_next_wave()
	watch_signals(sim)
	while sim.towers[0].shots == 0 or not sim.projectiles.is_empty():
		sim.step()
	assert_signal_emit_count(sim, "projectile_hit", 1)
	# Die ersten beiden laufen 0,5 Längen auseinander (Radius 1), der dritte 3 Längen dahinter.
	assert_eq(sim.enemies[0].hp, 980.0)
	assert_eq(sim.enemies[1].hp, 980.0)
	assert_eq(sim.enemies[2].hp, 1000.0)


func test_extra_shots_at_a_dead_enemy_expire_and_bounty_is_paid_once() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}], {"start_gold": 1000, "grid": ["#ooo#######", "E.........H", "#ooo#######"]})
	for x in range(1, 4):
		sim.build_tower(Vector2i(x, 0), "bow")
		sim.build_tower(Vector2i(x, 2), "bow")
	sim.start_next_wave()
	var fired := [0]
	var count := func(_p): fired[0] += 1
	sim.projectile_fired.connect(count)
	_run(sim, 10)
	sim.projectile_fired.disconnect(count)
	assert_gt(fired[0], 3, "mehr Schüsse als zum Töten nötig (3)")
	assert_eq(sim.kills, 1)
	assert_eq(sim.projectiles.size(), 0, "übrige Geschosse verfallen")
	assert_eq(sim.gold, 1000 - 300 + 7 + 10)


# --- Bewegung -------------------------------------------------------------

func test_enemy_walks_at_its_speed() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}])
	sim.start_next_wave()
	_run(sim, 4.0)
	assert_almost_eq(sim.enemies[0].pos.x, 0.5 + 4.0, 0.03)
	assert_almost_eq(sim.enemies[0].pos.y, 1.5, 0.001)
	assert_almost_eq(sim.enemies[0].remaining, 11.0 - 4.0, 0.03)


func test_enemy_follows_corners_and_never_enters_walls() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}], {"grid": [
		"E..#####",
		"##.#...H",
		"##...###",
	]})
	sim.start_next_wave()
	while sim.status == GameSim.Status.RUNNING and sim.tick < 5000:
		sim.step()
		for e in sim.enemies:
			assert_true(sim.grid.is_walkable(MineGrid.cell_at(e.pos)), "Gegner steht in einer Wand bei %s" % e.pos)
	assert_eq(sim.lives, 2, "der Gegner hat das Herz erreicht")


func test_very_fast_enemy_does_not_skip_the_heart() -> void:
	var sim := _sim([{"enemy": "runner", "count": 1}])
	sim.start_next_wave()
	_run(sim, 1.0)
	assert_eq(sim.lives, 4)
	assert_eq(sim.enemies.size(), 0)


# --- Wellen, Sieg, Niederlage ---------------------------------------------

func test_wave_spawns_exactly_the_listed_enemies_in_order() -> void:
	var sim := _sim([
		{"enemy": "tank", "count": 2, "interval": 1.0},
		{"enemy": "walker", "count": 3, "interval": 0.5, "delay": 0.25},
	])
	var spawned := []
	var record := func(e): spawned.append([e.type, snappedf(e.id * 0.0 + _ticks[0] * DT, 0.05)])
	sim.enemy_spawned.connect(record)
	sim.start_next_wave()
	for i in 300:
		_ticks[0] = i
		sim.step()
	sim.enemy_spawned.disconnect(record)
	assert_eq(spawned, [["tank", 0.0], ["walker", 0.25], ["walker", 0.75], ["tank", 1.0], ["walker", 1.25]])


func test_nothing_happens_before_the_first_wave_is_started() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}])
	_run(sim, 30)
	assert_eq(sim.wave_index, -1)
	assert_eq(sim.enemies.size(), 0)
	assert_true(sim.can_start_wave())


func test_leak_costs_lives_and_zero_lives_is_defeat() -> void:
	var sim := _sim([{"enemy": "tank", "count": 2, "interval": 1.0}])
	watch_signals(sim)
	sim.start_next_wave()
	_run(sim, 11.5)
	assert_eq(sim.lives, 2, "ein Panzer kostet 3 Leben")
	assert_eq(sim.status, GameSim.Status.RUNNING)
	_run(sim, 1.0)
	assert_eq(sim.lives, 0, "Leben werden nicht negativ")
	assert_eq(sim.status, GameSim.Status.LOST)
	assert_signal_emitted_with_parameters(sim, "finished", [false])
	var tick := sim.tick
	sim.step()
	assert_eq(sim.tick, tick, "nach dem Ende läuft nichts weiter")
	assert_eq(sim.build_tower(Vector2i(1, 2), "bow"), GameSim.Result.GAME_OVER)


func test_last_wave_cleared_is_victory() -> void:
	var sim := _sim([{"enemy": "walker", "count": 2, "interval": 1.0}])
	watch_signals(sim)
	sim.build_tower(Vector2i(1, 2), "bow")
	sim.start_next_wave()
	_run(sim, 20)
	assert_eq(sim.status, GameSim.Status.WON)
	assert_eq(sim.lives, 5)
	assert_signal_emitted_with_parameters(sim, "finished", [true])


func test_surviving_a_leak_still_wins() -> void:
	var sim := _sim([{"enemy": "walker", "count": 1}])
	sim.start_next_wave()
	_run(sim, 20)
	assert_eq(sim.lives, 4)
	assert_eq(sim.status, GameSim.Status.WON)


func test_next_wave_starts_automatically_after_the_pause() -> void:
	var level := _level([{"enemy": "runner", "count": 1}])
	level["waves"].append({"reward": 0, "groups": [{"enemy": "tank", "count": 1}]})
	var sim := GameSim.new(level, towers, enemies)
	sim.start_next_wave()
	_run(sim, 1.0)
	assert_false(sim.wave_active)
	assert_almost_eq(sim.next_wave_in, 3.0, 1.0)
	assert_eq(sim.wave_index, 0)
	_run(sim, 3.0)
	assert_eq(sim.wave_index, 1)
	assert_true(sim.wave_active)


func test_wave_can_be_called_early_but_not_while_one_runs() -> void:
	var level := _level([{"enemy": "runner", "count": 1}])
	level["waves"].append({"reward": 0, "groups": [{"enemy": "tank", "count": 1}]})
	var sim := GameSim.new(level, towers, enemies)
	assert_true(sim.start_next_wave())
	assert_false(sim.start_next_wave(), "Welle läuft schon")
	_run(sim, 1.0)
	assert_true(sim.start_next_wave(), "vorzeitig gestartet")
	assert_eq(sim.wave_index, 1)
	assert_false(sim.can_start_wave(), "keine weitere Welle")


# --- Wiederholbarkeit -----------------------------------------------------

func test_same_inputs_give_the_same_result() -> void:
	var level := GameData.load_level("level_01")
	var t := GameData.load_towers()
	var e := GameData.load_enemies()
	var a := Bots.run(level, t, e, Bots.BuilderBot.new(["crossbow", "sling"]), 90)
	var b := Bots.run(level, t, e, Bots.BuilderBot.new(["crossbow", "sling"]), 90)
	assert_eq(a.snapshot(), b.snapshot())
	assert_gt(a.kills, 0)
