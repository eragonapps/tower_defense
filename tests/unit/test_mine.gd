extends GutTest
## Stollen graben und zuschütten, Arbeiter und Erz, Ausbau der Türme.

var towers := {
	"bow": {
		"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 0.0, "projectile_speed": 20.0, "color": "#fff",
		"upgrades": [{"ore": 5, "damage": 25}, {"ore": 8, "range": 3.0, "cooldown": 0.25}],
	},
}
var enemies := {
	"tank": {"name_key": "E", "hp": 100000, "speed": 1.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0},
	"slow": {"name_key": "E", "hp": 100000, "speed": 0.25, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0},
}

## Umweg um einen Felsblock bei (2,1). Mit dem Feld als Stollen wird der Weg von 9 auf 5 Schritte kürzer.
const DETOUR := [
	"#######",
	"E.:..H#",
	"#.:.#o#",
	"#...###",
	"#######",
]


func _sim(grid: Array, groups := [], rules := {}, extra := {}) -> GameSim:
	var level := {
		"start_gold": 200, "lives": 50, "wave_pause": 3.0, "towers": ["bow"], "grid": grid, "rules": rules,
		"waves": [{"reward": 0, "groups": groups if not groups.is_empty() else [{"enemy": "tank", "count": 1}]}],
	}
	level.merge(extra, true)
	return GameSim.new(level, towers, enemies)


func _run(sim: GameSim, seconds: float) -> void:
	for i in int(round(seconds * GameSim.TICK_RATE)):
		sim.step()


func _assert_enemies_on_walkable(sim: GameSim) -> void:
	for e in sim.enemies:
		if not sim.grid.is_walkable(MineGrid.cell_at(e.pos)):
			fail_test("Gegner steht in einer Wand bei %s (Tick %d)" % [e.pos, sim.tick])
			return


# --- Graben ---------------------------------------------------------------

func test_dig_costs_gold_takes_time_and_opens_a_shortcut() -> void:
	var sim := _sim(DETOUR)
	watch_signals(sim)
	assert_eq(sim.grid.distance(Vector2i(0, 1)), 9)
	assert_eq(sim.dig(Vector2i(2, 1)), GameSim.Result.OK)
	assert_eq(sim.gold, 170)
	assert_signal_emitted(sim, "dig_started")
	_run(sim, 2.9)
	assert_false(sim.grid.is_walkable(Vector2i(2, 1)), "noch nicht fertig")
	assert_eq(sim.grid.distance(Vector2i(0, 1)), 9)
	_run(sim, 0.2)
	assert_true(sim.grid.is_walkable(Vector2i(2, 1)))
	assert_eq(sim.grid.distance(Vector2i(0, 1)), 5)
	assert_eq(sim.dig_jobs.size(), 0)
	assert_signal_emitted_with_parameters(sim, "grid_changed", [Vector2i(2, 1)])


func test_dig_is_rejected_with_reason() -> void:
	var sim := _sim(DETOUR, [], {"max_digs": 2})
	assert_eq(sim.dig(Vector2i(0, 0)), GameSim.Result.NOT_ALLOWED, "Granit")
	assert_eq(sim.dig(Vector2i(5, 2)), GameSim.Result.NOT_ALLOWED, "Bauplatz")
	assert_eq(sim.dig(Vector2i(1, 1)), GameSim.Result.NOT_ALLOWED, "ist schon Stollen")
	assert_eq(sim.dig(Vector2i(2, 1)), GameSim.Result.OK)
	assert_eq(sim.dig(Vector2i(2, 1)), GameSim.Result.OCCUPIED, "wird schon gegraben")
	assert_eq(sim.dig(Vector2i(2, 2)), GameSim.Result.OK)
	assert_eq(sim.gold, 140)
	_run(sim, 4)
	sim.fill(Vector2i(2, 1))
	assert_eq(sim.dig(Vector2i(2, 1)), GameSim.Result.LIMIT_REACHED)
	assert_eq(sim.gold, 120, "abgelehntes Graben kostet nichts")


func test_dig_needs_a_neighbouring_tunnel_and_gold() -> void:
	var sim := _sim(["#####", "E..H#", "#:::#", "#:::#", "#####"], [], {}, {"start_gold": 40})
	assert_eq(sim.dig(Vector2i(2, 3)), GameSim.Result.NOT_CONNECTED)
	assert_eq(sim.dig(Vector2i(2, 2)), GameSim.Result.OK)
	assert_eq(sim.dig(Vector2i(2, 3)), GameSim.Result.NOT_CONNECTED, "das Nachbarfeld ist noch nicht fertig")
	_run(sim, 3.1)
	assert_eq(sim.dig(Vector2i(2, 3)), GameSim.Result.NOT_ENOUGH_GOLD)
	assert_eq(sim.gold, 10)


func test_digging_can_be_switched_off_per_level() -> void:
	var sim := _sim(DETOUR, [], {"digging": false})
	assert_eq(sim.dig(Vector2i(2, 1)), GameSim.Result.NOT_ALLOWED)
	assert_eq(sim.fill(Vector2i(1, 2)), GameSim.Result.NOT_ALLOWED)


func test_enemies_use_a_new_shortcut_at_once() -> void:
	var sim := _sim(DETOUR, [{"enemy": "tank", "count": 3, "interval": 2.0}], {"dig_time": 1.0})
	sim.start_next_wave()
	sim.dig(Vector2i(2, 1))
	# Der erste Gegner ist schon auf dem Umweg, die späteren nehmen die Abkürzung.
	var guard := 0
	while sim.status == GameSim.Status.RUNNING and guard < 3000:
		sim.step()
		guard += 1
		_assert_enemies_on_walkable(sim)
	assert_eq(sim.lives, 47, "alle drei kommen an")
	# Umweg 9 Schritte, Abkürzung 5. Drei Gegner im Abstand von 2 s: ohne Abkürzung bräuchte der letzte 13 s.
	assert_lt(sim.tick * GameSim.DT, 11.5)


# --- Zuschütten -----------------------------------------------------------

func test_fill_turns_tunnel_into_rock_and_costs_gold() -> void:
	var sim := _sim(DETOUR, [], {"dig_time": 0.0})
	sim.dig(Vector2i(2, 1))
	sim.step()
	watch_signals(sim)
	assert_eq(sim.grid.distance(Vector2i(0, 1)), 5)
	assert_eq(sim.fill(Vector2i(2, 1)), GameSim.Result.OK)
	assert_eq(sim.gold, 200 - 30 - 20)
	assert_eq(sim.grid.get_cell(Vector2i(2, 1)), MineGrid.Cell.ROCK)
	assert_eq(sim.grid.distance(Vector2i(0, 1)), 9)
	assert_signal_emitted_with_parameters(sim, "grid_changed", [Vector2i(2, 1)])


func test_fill_is_refused_when_it_blocks_the_only_way() -> void:
	var sim := _sim(DETOUR)
	for cell in [Vector2i(1, 1), Vector2i(1, 3), Vector2i(3, 2), Vector2i(4, 1)]:
		assert_eq(sim.fill(cell), GameSim.Result.BLOCKS_PATH, str(cell))
		assert_true(sim.grid.is_walkable(cell), "Feld bleibt Stollen")
	assert_eq(sim.gold, 200, "das Gold bleibt erhalten")
	assert_eq(sim.fill(Vector2i(0, 1)), GameSim.Result.NOT_ALLOWED, "Eingang")
	assert_eq(sim.fill(Vector2i(5, 1)), GameSim.Result.NOT_ALLOWED, "Herz")
	assert_eq(sim.fill(Vector2i(2, 1)), GameSim.Result.NOT_ALLOWED, "Fels")
	assert_eq(sim.grid.distance(Vector2i(0, 1)), 9)


func test_fill_is_refused_under_or_right_in_front_of_an_enemy() -> void:
	var sim := _sim(DETOUR, [{"enemy": "slow", "count": 1}], {"dig_time": 0.0})
	sim.dig(Vector2i(2, 1))
	sim.start_next_wave()
	_run(sim, 5.0)
	# Der Gegner ist bei x≈1.75 auf dem Weg von (1,1) nach (2,1).
	assert_eq(sim.fill(Vector2i(2, 1)), GameSim.Result.ENEMY_IN_THE_WAY, "sein nächstes Feld")
	assert_eq(sim.fill(Vector2i(1, 1)), GameSim.Result.ENEMY_IN_THE_WAY, "das Feld, auf dem er steht")
	assert_eq(sim.gold, 170)


func test_fill_ahead_makes_enemies_turn_around_but_never_traps_them() -> void:
	# Zwei Wege zum Herz: oben kurz, unten lang.
	var sim := _sim([
		"#########",
		"E......H#",
		"#.#####.#",
		"#.......#",
		"#########",
	], [{"enemy": "slow", "count": 1}])
	sim.start_next_wave()
	_run(sim, 10.0)
	var e := sim.enemies[0]
	assert_eq(e.target_cell, Vector2i(3, 1), "der Gegner geht oben entlang")
	# Vor ihm zuschütten: er muss umkehren und unten herum gehen.
	assert_eq(sim.fill(Vector2i(5, 1)), GameSim.Result.OK)
	assert_gt(e.remaining, 10.0, "sein Restweg ist jetzt der lange Weg")
	# Jetzt auch hinter ihm zuschütten würde ihn einsperren.
	assert_eq(sim.fill(Vector2i(1, 1)), GameSim.Result.BLOCKS_PATH)
	var guard := 0
	while sim.status == GameSim.Status.RUNNING and guard < 20000:
		sim.step()
		guard += 1
		_assert_enemies_on_walkable(sim)
	assert_eq(sim.lives, 49, "er kommt über den langen Weg an")


func test_random_digging_and_filling_never_breaks_the_path() -> void:
	var rows := ["##############"]
	rows.append("E::::::::::::#")
	for i in 6:
		rows.append("#::::::::::::#")
	rows.append("#:::::::::::H#")
	rows.append("##############")
	# Start: ein Weg am linken und unteren Rand.
	for y in range(1, 9):
		rows[y] = rows[y].substr(0, 1) + "." + rows[y].substr(2)
	rows[8] = "#" + ".".repeat(11) + "H#"
	rows[1] = "E" + rows[1].substr(1)
	var sim := _sim(rows, [{"enemy": "tank", "count": 40, "interval": 1.5}], {"dig_time": 0.5, "dig_cost": 1, "fill_cost": 1}, {"start_gold": 100000, "lives": 1000})
	assert_eq(sim.grid.error, "")
	sim.start_next_wave()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var done := {"dig": 0, "fill": 0}
	for i in 1000:
		var cell := Vector2i(rng.randi_range(1, 12), rng.randi_range(1, 8))
		if rng.randf() < 0.55:
			if sim.dig(cell) == GameSim.Result.OK:
				done["dig"] += 1
		elif sim.fill(cell) == GameSim.Result.OK:
			done["fill"] += 1
		for s in 4:
			sim.step()
		if not sim.grid.has_path():
			fail_test("Kein Weg mehr nach Aktion %d" % i)
			return
		_assert_enemies_on_walkable(sim)
		for e in sim.enemies:
			if sim.grid.distance(e.target_cell) == MineGrid.UNREACHABLE:
				fail_test("Gegner ohne Weg nach Aktion %d" % i)
				return
	gut.p("Zufallstest: %d gegraben, %d zugeschüttet, %d Gegner unterwegs" % [done["dig"], done["fill"], sim.enemies.size()])
	assert_gt(done["dig"], 50)
	assert_gt(done["fill"], 50)
	assert_gt(sim.enemies.size(), 0)
	assert_gte(sim.gold, 0)


# --- Arbeiter und Erz -----------------------------------------------------

const VEINS := [
	"#########",
	"E......H#",
	"#*:::::##",
	"#:::::*##",
	"#########",
]


func test_worker_can_only_stand_at_a_reachable_vein() -> void:
	var sim := _sim(VEINS)
	watch_signals(sim)
	assert_eq(sim.place_worker(Vector2i(2, 2)), GameSim.Result.NOT_ALLOWED, "Fels")
	assert_eq(sim.place_worker(Vector2i(6, 3)), GameSim.Result.NOT_CONNECTED, "kein Stollen daneben")
	assert_eq(sim.place_worker(Vector2i(1, 2)), GameSim.Result.OK)
	assert_eq(sim.gold, 160)
	assert_eq(sim.place_worker(Vector2i(1, 2)), GameSim.Result.OCCUPIED)
	assert_signal_emit_count(sim, "worker_placed", 1)
	# Nach dem Graben eines Zugangs ist auch die zweite Ader erreichbar.
	sim.dig(Vector2i(6, 2))
	_run(sim, 3.1)
	assert_eq(sim.place_worker(Vector2i(6, 3)), GameSim.Result.OK)
	assert_eq(sim.workers.size(), 2)


func test_worker_needs_gold() -> void:
	var sim := _sim(VEINS, [], {}, {"start_gold": 39})
	assert_eq(sim.place_worker(Vector2i(1, 2)), GameSim.Result.NOT_ENOUGH_GOLD)
	assert_eq(sim.gold, 39)


func test_worker_delivers_ore_at_the_expected_rate() -> void:
	var sim := _sim(VEINS, [], {"ore_interval": 2.0, "ore_amount": 3})
	sim.place_worker(Vector2i(1, 2))
	watch_signals(sim)
	_run(sim, 1.9)
	assert_eq(sim.ore, 0)
	_run(sim, 0.2)
	assert_eq(sim.ore, 3)
	_run(sim, 8.0)
	assert_eq(sim.ore, 15, "nach 10 s fünf Lieferungen")
	assert_signal_emit_count(sim, "ore_mined", 5)
	assert_eq(sim.workers[0].mined, 15)


func test_worker_stops_while_enemies_are_near() -> void:
	var sim := _sim(VEINS, [{"enemy": "tank", "count": 1}], {"ore_interval": 0.5})
	sim.place_worker(Vector2i(1, 2))
	sim.start_next_wave()
	sim.step()
	# Ader bei (1.5, 2.5), Gegner startet bei (0.5, 1.5): Abstand 1,41 und damit in der Gefahrenzone 1,6.
	assert_false(sim.workers[0].active)
	_run(sim, 1.5)
	assert_eq(sim.ore, 0, "nichts geliefert, solange der Gegner nah ist")
	_run(sim, 1.5)
	# Bei x=3.5 ist der Gegner 2,2 entfernt.
	assert_true(sim.workers[0].active)
	_run(sim, 1.0)
	assert_between(sim.ore, 2, 4)


func test_worker_stops_when_the_vein_is_cut_off() -> void:
	var sim := _sim(["######", "E...H#", "#:.:##", "#:*:##", "######"], [], {"ore_interval": 0.5})
	sim.place_worker(Vector2i(2, 3))
	_run(sim, 1.1)
	assert_eq(sim.ore, 2)
	assert_eq(sim.fill(Vector2i(2, 2)), GameSim.Result.OK)
	_run(sim, 2.0)
	assert_eq(sim.ore, 2)
	assert_false(sim.workers[0].active)


# --- Ausbau ---------------------------------------------------------------

func test_upgrade_costs_ore_and_improves_the_tower() -> void:
	var sim := _sim(DETOUR, [], {}, {"start_ore": 20})
	sim.build_tower(Vector2i(5, 2), "bow")
	var t := sim.towers[0]
	watch_signals(sim)
	assert_eq(t.level, 1)
	assert_eq(sim.upgrade_cost(t), 5)
	assert_eq(sim.next_stats(t)["damage"], 25)
	assert_eq(sim.upgrade_tower(Vector2i(5, 2)), GameSim.Result.OK)
	assert_eq(sim.ore, 15)
	assert_eq(t.level, 2)
	assert_eq(t.stats["damage"], 25)
	assert_eq(t.stats["range"], 2.0, "nicht genannte Werte bleiben")
	assert_eq(sim.upgrade_tower(Vector2i(5, 2)), GameSim.Result.OK)
	assert_eq(sim.ore, 7)
	assert_eq(t.stats["damage"], 25, "Werte früherer Stufen bleiben")
	assert_eq(t.stats["range"], 3.0)
	assert_eq(t.stats["cooldown"], 0.25)
	assert_eq(sim.upgrade_cost(t), -1)
	assert_eq(sim.upgrade_tower(Vector2i(5, 2)), GameSim.Result.MAX_LEVEL)
	assert_eq(sim.ore, 7)
	assert_signal_emit_count(sim, "tower_upgraded", 2)
	assert_eq(towers["bow"]["damage"], 10, "die Grunddaten bleiben unverändert")


func test_upgrade_is_rejected_without_ore_or_tower() -> void:
	var sim := _sim(DETOUR, [], {}, {"start_ore": 4})
	assert_eq(sim.upgrade_tower(Vector2i(5, 2)), GameSim.Result.NOT_ALLOWED, "kein Turm")
	sim.build_tower(Vector2i(5, 2), "bow")
	assert_eq(sim.upgrade_tower(Vector2i(5, 2)), GameSim.Result.NOT_ENOUGH_ORE)
	assert_eq(sim.towers[0].level, 1)
	assert_eq(sim.ore, 4)


func test_upgraded_tower_really_hits_harder_and_reaches_further() -> void:
	var grid := ["E.........H", "#o::::::::#"]
	var base := _sim(grid, [{"enemy": "tank", "count": 1}])
	var better := _sim(grid, [{"enemy": "tank", "count": 1}], {}, {"start_ore": 20})
	for sim in [base, better]:
		sim.build_tower(Vector2i(1, 1), "bow")
		sim.start_next_wave()
	better.upgrade_tower(Vector2i(1, 1))
	better.upgrade_tower(Vector2i(1, 1))
	_run(base, 8.0)
	_run(better, 8.0)
	var base_damage := 100000.0 - base.enemies[0].hp
	var better_damage := 100000.0 - better.enemies[0].hp
	# Stufe 3: Schaden 25 statt 10, doppelte Schussfolge, größere Reichweite.
	assert_gt(better_damage, base_damage * 5.0)
	assert_gt(better.towers[0].shots, base.towers[0].shots * 2)


func test_selling_an_upgraded_tower_refunds_gold_only() -> void:
	var sim := _sim(DETOUR, [], {}, {"start_ore": 20})
	sim.build_tower(Vector2i(5, 2), "bow")
	sim.upgrade_tower(Vector2i(5, 2))
	sim.sell_tower(Vector2i(5, 2))
	assert_eq(sim.gold, 200 - 50 + 35)
	assert_eq(sim.ore, 15)
