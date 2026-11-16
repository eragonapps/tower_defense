extends GutTest
## Zielwahl, Veredeln, Versetzen, Bauplätze im Endlosmodus, Schemen und Durchbruch.

var towers := {
	"bow": {"name_key": "T", "cost": 50, "range": 2.5, "cooldown": 0.5, "damage": 10, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "pierce",
		"upgrades": [{"ore": 5, "damage": 20}], "specs": [{"id": "a", "name_key": "S", "desc_key": "S", "ore": 5, "damage": 100}, {"id": "b", "name_key": "S", "desc_key": "S", "ore": 5, "range": 5.0}]},
	"fire": {"name_key": "T", "cost": 50, "range": 2.5, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "fire",
		"burn": {"dps": 10, "duration": 2.0}, "specs": [{"id": "a", "name_key": "S", "desc_key": "S", "ore": 5, "cooldown": 0.5}, {"id": "b", "name_key": "S", "desc_key": "S", "ore": 5, "range": 5.0}]},
	"rune": {"name_key": "T", "kind": "aura", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"slow": {"factor": 0.5, "duration": 1.5}, "specs": [{"id": "a", "name_key": "S", "desc_key": "S", "ore": 5, "cooldown": 0.5}, {"id": "b", "name_key": "S", "desc_key": "S", "ore": 5, "range": 3.0}]},
	"wall": {"name_key": "T", "kind": "block", "cost": 50, "range": 1.2, "cooldown": 1.0, "damage": 5, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"damage_type": "blunt", "capacity": 2, "hold_time": 5.0},
	"bomb": {"name_key": "T", "cost": 50, "range": 2.5, "cooldown": 0.5, "damage": 10, "splash": 1.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "blunt"},
}
var enemies := {
	"small": {"name_key": "E", "hp": 500, "speed": 1.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0},
	"big": {"name_key": "E", "hp": 5000, "speed": 1.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0},
	"fast": {"name_key": "E", "hp": 10, "speed": 200.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0},
}
const GRID := ["################", "E..............H", "#o:::o:::o:::::#", "#::::::::::::::#", "################"]


func _sim(groups: Array, extra := {}) -> GameSim:
	var level := {"start_gold": 5000, "start_ore": 500, "lives": 9999, "wave_pause": 2.0, "towers": towers.keys(), "grid": GRID,
		"rules": {"boon_every": 0, "endless_boon_every": 0, "endless_curse_every": 0, "endless_boss_every": 0, "endless_breach_every": 0},
		"waves": [{"reward": 0, "groups": groups}]}
	for key in extra:
		if key == "rules":
			level["rules"].merge(extra["rules"], true)
		else:
			level[key] = extra[key]
	return GameSim.new(level, towers, enemies, {}, {}, 1)


func _run(sim: GameSim, seconds: float) -> void:
	for i in int(round(seconds * GameSim.TICK_RATE)):
		sim.step()


func _endless(sim: GameSim) -> void:
	sim.wave_index = sim.wave_count - 1
	sim.status = GameSim.Status.WON
	assert_true(sim.continue_endless())


func _maxed(sim: GameSim, cell: Vector2i, type := "bow") -> GameSim.Tower:
	sim.build_tower(cell, type)
	while sim.upgrade_tower(cell) == GameSim.Result.OK:
		pass
	assert_eq(sim.specialize(cell, 0), GameSim.Result.OK)
	return sim.tower_at(cell)


# --- Zielwahl -------------------------------------------------------------

func test_target_mode_decides_who_gets_shot() -> void:
	var lost := {}
	for mode in GameSim.TARGET_MODES:
		# Der Kleine läuft vorn, der Große eine halbe Länge dahinter.
		var sim := _sim([{"enemy": "small", "count": 1}, {"enemy": "big", "count": 1, "delay": 0.5}])
		sim.build_tower(Vector2i(5, 2), "bow")
		assert_eq(sim.set_target_mode(Vector2i(5, 2), mode), GameSim.Result.OK)
		sim.start_next_wave()
		_run(sim, 6.5)
		lost[mode] = [500.0 - sim.enemies[0].hp, 5000.0 - sim.enemies[1].hp]
	assert_gt(lost["first"][0], 0.0)
	assert_eq(lost["first"][1], 0.0, "vorderster: nur der Kleine vorn")
	assert_gt(lost["strong"][1], 0.0)
	assert_lt(lost["strong"][0], lost["first"][0], "stärkster: der Große wird beschossen, sobald er in Reichweite ist")
	assert_gt(lost["weak"][0], 0.0)
	assert_eq(lost["weak"][1], 0.0, "schwächster: der Kleine hat weniger Leben")


func test_target_mode_is_rejected_where_it_makes_no_sense() -> void:
	var sim := _sim([{"enemy": "small", "count": 1}])
	assert_eq(sim.set_target_mode(Vector2i(1, 2), "strong"), GameSim.Result.NOT_ALLOWED, "kein Turm")
	sim.build_tower(Vector2i(1, 2), "rune")
	sim.build_tower(Vector2i(5, 2), "wall")
	sim.build_tower(Vector2i(9, 2), "bow")
	assert_eq(sim.set_target_mode(Vector2i(1, 2), "strong"), GameSim.Result.NOT_ALLOWED, "Runenstein wirkt auf alle")
	assert_eq(sim.set_target_mode(Vector2i(5, 2), "strong"), GameSim.Result.NOT_ALLOWED, "Schildwall")
	assert_eq(sim.set_target_mode(Vector2i(9, 2), "irgendwer"), GameSim.Result.NOT_ALLOWED)
	assert_eq(sim.tower_at(Vector2i(9, 2)).target_mode, "first")


func test_fire_tower_still_prefers_unburnt_enemies_in_every_mode() -> void:
	var sim := _sim([{"enemy": "big", "count": 3, "interval": 0.4}])
	sim.build_tower(Vector2i(5, 2), "fire")
	sim.set_target_mode(Vector2i(5, 2), "strong")
	sim.start_next_wave()
	_run(sim, 5.5)
	# Drei Schüsse im Abstand von 1 s: Jeder trifft einen anderen Gegner, statt dreimal denselben.
	assert_eq(sim.towers[0].shots, 3)
	for e in sim.enemies:
		assert_lt(e.hp, e.max_hp, "jeder hat einmal gebrannt")


func test_target_mode_survives_upgrade_specialization_and_move() -> void:
	var sim := _sim([{"enemy": "small", "count": 1}])
	sim.build_tower(Vector2i(1, 2), "bow")
	sim.set_target_mode(Vector2i(1, 2), "weak")
	sim.upgrade_tower(Vector2i(1, 2))
	sim.specialize(Vector2i(1, 2), 0)
	sim.move_tower(Vector2i(1, 2), Vector2i(5, 2))
	assert_eq(sim.tower_at(Vector2i(5, 2)).target_mode, "weak")


# --- Veredeln -------------------------------------------------------------

func test_refining_needs_a_specialized_tower_and_gets_dearer() -> void:
	var sim := _sim([{"enemy": "small", "count": 1}])
	assert_eq(sim.refine_tower(Vector2i(1, 2)), GameSim.Result.NOT_ALLOWED, "kein Turm")
	sim.build_tower(Vector2i(1, 2), "bow")
	assert_eq(sim.refine_tower(Vector2i(1, 2)), GameSim.Result.NOT_SPECIALIZED)
	sim.upgrade_tower(Vector2i(1, 2))
	assert_eq(sim.refine_tower(Vector2i(1, 2)), GameSim.Result.NOT_SPECIALIZED, "höchste Stufe allein reicht nicht")
	sim.specialize(Vector2i(1, 2), 0)
	var t := sim.towers[0]
	watch_signals(sim)
	var gold := sim.gold
	assert_eq(sim.refine_cost(t), 150)
	assert_eq(sim.refine_tower(Vector2i(1, 2)), GameSim.Result.OK)
	assert_eq(sim.gold, gold - 150)
	assert_almost_eq(t.stats["damage"], 104.0, 0.001)
	assert_eq(sim.refine_cost(t), 188, "150 × 1,25")
	assert_eq(sim.refine_tower(Vector2i(1, 2)), GameSim.Result.OK)
	assert_almost_eq(t.stats["damage"], 100.0 * 1.04 * 1.04, 0.001)
	assert_eq(t.refine, 2)
	assert_signal_emit_count(sim, "tower_refined", 2)
	sim.gold = 10
	assert_eq(sim.refine_tower(Vector2i(1, 2)), GameSim.Result.NOT_ENOUGH_GOLD)
	assert_eq(sim.sell_value(t), 35, "Veredelung wird beim Verkauf nicht erstattet")


func test_refining_raises_burn_and_gives_range_to_towers_without_damage() -> void:
	var sim := _sim([{"enemy": "small", "count": 1}])
	var fire := _maxed(sim, Vector2i(1, 2), "fire")
	var rune := _maxed(sim, Vector2i(5, 2), "rune")
	sim.refine_tower(Vector2i(1, 2))
	sim.refine_tower(Vector2i(5, 2))
	assert_almost_eq(fire.stats["burn"]["dps"], 10.4, 0.001)
	assert_eq(fire.stats["range"], 2.5)
	assert_almost_eq(rune.stats["range"], 2.04, 0.001, "ohne Schaden: 2 % mehr Reichweite")
	assert_eq(towers["fire"]["burn"]["dps"], 10, "die Grunddaten bleiben unverändert")


func test_refining_works_together_with_boons() -> void:
	var sim := _sim([{"enemy": "small", "count": 1}])
	var t := _maxed(sim, Vector2i(1, 2))
	sim.refine_tower(Vector2i(1, 2))
	sim._apply_effect({"type": "stat", "towers": ["bow"], "stat": "damage", "factor": 2.0})
	assert_almost_eq(t.stats["damage"], 208.0, 0.001)
	sim.refine_tower(Vector2i(1, 2))
	assert_almost_eq(t.stats["damage"], 100.0 * 1.04 * 1.04 * 2.0, 0.001)


# --- Versetzen ------------------------------------------------------------

func test_moving_keeps_everything_and_costs_gold() -> void:
	var sim := _sim([{"enemy": "small", "count": 1}])
	var t := _maxed(sim, Vector2i(1, 2))
	sim.refine_tower(Vector2i(1, 2))
	var stats := t.stats.duplicate(true)
	var gold := sim.gold
	watch_signals(sim)
	assert_eq(sim.move_tower(Vector2i(1, 2), Vector2i(9, 2)), GameSim.Result.OK)
	assert_eq(sim.gold, gold - 60)
	assert_null(sim.tower_at(Vector2i(1, 2)))
	assert_eq(sim.tower_at(Vector2i(9, 2)), t)
	assert_eq(t.cell, Vector2i(9, 2))
	assert_eq(t.pos, MineGrid.center(Vector2i(9, 2)))
	assert_eq(t.stats, stats)
	assert_eq(t.spec, "a")
	assert_eq(t.refine, 1)
	assert_signal_emitted(sim, "tower_moved")
	assert_eq(sim.build_tower(Vector2i(1, 2), "bow"), GameSim.Result.OK, "der alte Platz ist frei")


func test_move_is_rejected_with_reason() -> void:
	var sim := _sim([{"enemy": "small", "count": 1}])
	sim.build_tower(Vector2i(1, 2), "bow")
	sim.build_tower(Vector2i(5, 2), "bow")
	assert_eq(sim.move_tower(Vector2i(9, 2), Vector2i(1, 2)), GameSim.Result.NOT_ALLOWED, "dort steht kein Turm")
	assert_eq(sim.move_tower(Vector2i(1, 2), Vector2i(5, 2)), GameSim.Result.OCCUPIED)
	assert_eq(sim.move_tower(Vector2i(1, 2), Vector2i(2, 2)), GameSim.Result.NOT_ALLOWED, "Fels ist kein Bauplatz")
	assert_eq(sim.move_tower(Vector2i(1, 2), Vector2i(3, 1)), GameSim.Result.NOT_ALLOWED, "Stollen")
	sim.gold = 59
	assert_eq(sim.move_tower(Vector2i(1, 2), Vector2i(9, 2)), GameSim.Result.NOT_ENOUGH_GOLD)
	assert_eq(sim.gold, 59)
	assert_not_null(sim.tower_at(Vector2i(1, 2)))


func test_moving_a_shield_wall_releases_its_enemies_and_it_really_fights_from_the_new_place() -> void:
	var sim := _sim([{"enemy": "big", "count": 1}])
	sim.build_tower(Vector2i(5, 2), "wall")
	sim.start_next_wave()
	_run(sim, 5.5)
	var e := sim.enemies[0]
	assert_gt(e.hold_left, 0.0)
	var x := e.pos.x
	sim.move_tower(Vector2i(5, 2), Vector2i(9, 2))
	assert_eq(e.hold_left, 0.0)
	_run(sim, 1.0)
	assert_almost_eq(e.pos.x, x + 1.0, 0.05, "er läuft weiter")
	_run(sim, 4.0)
	assert_gt(e.hold_left, 0.0, "am neuen Platz hält der Schildwall ihn wieder auf")


# --- Bauplätze ------------------------------------------------------------

func test_new_build_sites_exist_only_in_endless_mode() -> void:
	var sim := _sim([{"enemy": "fast", "count": 1}])
	assert_eq(sim.create_slot(Vector2i(2, 2)), GameSim.Result.ONLY_ENDLESS)
	assert_eq(sim.remove_slot(Vector2i(1, 2)), GameSim.Result.ONLY_ENDLESS)
	_endless(sim)
	assert_eq(sim.create_slot(Vector2i(3, 1)), GameSim.Result.NOT_ALLOWED, "Stollen")
	assert_eq(sim.create_slot(Vector2i(0, 0)), GameSim.Result.NOT_ALLOWED, "Granit")
	watch_signals(sim)
	var gold := sim.gold
	var ore := sim.ore
	assert_eq(sim.slot_cost(), [300, 40] as Array[int])
	assert_eq(sim.create_slot(Vector2i(2, 2)), GameSim.Result.OK)
	assert_eq(sim.gold, gold - 300)
	assert_eq(sim.ore, ore - 40)
	assert_eq(sim.grid.get_cell(Vector2i(2, 2)), MineGrid.Cell.BUILD)
	assert_signal_emitted_with_parameters(sim, "grid_changed", [Vector2i(2, 2)])
	assert_eq(sim.build_tower(Vector2i(2, 2), "bow"), GameSim.Result.OK, "auf dem neuen Platz lässt sich bauen")
	assert_true(sim.grid.has_path(), "der Weg bleibt unberührt")


func test_every_further_build_site_costs_more_and_there_is_a_limit() -> void:
	var sim := _sim([{"enemy": "fast", "count": 1}], {"rules": {"max_slots": 5}})
	_endless(sim)
	sim.create_slot(Vector2i(2, 2))
	assert_eq(sim.slot_cost(), [450, 60] as Array[int])
	sim.create_slot(Vector2i(3, 2))
	assert_eq(sim.slot_cost(), [675, 90] as Array[int])
	assert_eq(sim.create_slot(Vector2i(4, 2)), GameSim.Result.LIMIT_REACHED, "3 vorhandene und 2 neue sind 5")
	sim.rules["max_slots"] = 30
	sim.gold = 100
	assert_eq(sim.create_slot(Vector2i(4, 2)), GameSim.Result.NOT_ENOUGH_GOLD)
	sim.gold = 5000
	sim.ore = 10
	assert_eq(sim.create_slot(Vector2i(4, 2)), GameSim.Result.NOT_ENOUGH_ORE)
	assert_eq(sim.slots_created, 2)


func test_removed_build_site_becomes_rock_that_can_be_dug() -> void:
	var sim := _sim([{"enemy": "fast", "count": 1}])
	_endless(sim)
	sim.build_tower(Vector2i(1, 2), "bow")
	assert_eq(sim.remove_slot(Vector2i(1, 2)), GameSim.Result.OCCUPIED, "erst den Turm versetzen oder verkaufen")
	assert_eq(sim.remove_slot(Vector2i(2, 2)), GameSim.Result.NOT_ALLOWED, "kein Bauplatz")
	var gold := sim.gold
	assert_eq(sim.remove_slot(Vector2i(5, 2)), GameSim.Result.OK)
	assert_eq(sim.gold, gold, "kostenlos, keine Erstattung")
	assert_eq(sim.grid.get_cell(Vector2i(5, 2)), MineGrid.Cell.ROCK)
	assert_eq(sim.dig(Vector2i(5, 2)), GameSim.Result.OK)
	_run(sim, 3.2)
	assert_true(sim.grid.is_walkable(Vector2i(5, 2)), "der Weg kann jetzt durch den früheren Bauplatz führen")


# --- Schemen --------------------------------------------------------------

func test_wraith_shrugs_off_area_and_fire_damage_but_not_bolts() -> void:
	var real_enemies := GameData.load_enemies()
	assert_true(real_enemies.has("wraith"))
	var lost := {}
	for tower in ["bow", "bomb", "fire"]:
		for enemy in ["small", "wraith"]:
			var pool := {"small": enemies["small"], "wraith": real_enemies["wraith"].duplicate()}
			pool["wraith"]["hp"] = 500
			pool["wraith"]["speed"] = 1.0
			var sim := GameSim.new({"start_gold": 500, "lives": 99, "wave_pause": 2.0, "towers": towers.keys(), "grid": GRID,
				"waves": [{"reward": 0, "groups": [{"enemy": enemy, "count": 1}]}]}, towers, pool)
			sim.build_tower(Vector2i(5, 2), tower)
			sim.start_next_wave()
			_run(sim, 12.0)
			lost["%s/%s" % [tower, enemy]] = 500.0 - sim.enemies[0].hp
	assert_almost_eq(lost["bow/wraith"], lost["bow/small"], 0.01, "Bolzen treffen voll")
	assert_gt(lost["bow/small"], 50.0)
	assert_almost_eq(lost["bomb/wraith"], lost["bomb/small"] * 0.25, 0.01)
	assert_almost_eq(lost["fire/wraith"], lost["fire/small"] * 0.25, 0.01)


func test_wraith_has_a_model_a_name_and_appears_in_levels_and_endless() -> void:
	assert_true(Models.ENEMIES.has("wraith"))
	assert_true(Models.has(Models.ENEMIES["wraith"]["model"]), "das Geist-Modell fehlt")
	var figure := Models.character(Models.ENEMIES["wraith"]["model"], [], Vector3.ONE)
	var ap := Models.player(figure)
	assert_not_null(ap)
	assert_true(ap.has_animation(Models.ENEMIES["wraith"]["walk"]))
	assert_true(ap.has_animation(Models.ENEMIES["wraith"]["death"]))
	figure.free()
	assert_ne(tr("ENEMY_WRAITH"), "ENEMY_WRAITH")
	var levels_with := 0
	for id in GameData.LEVEL_ORDER:
		for w in GameData.load_level(id)["waves"]:
			for g in w["groups"]:
				if g["enemy"] == "wraith":
					levels_with += 1
					break
	assert_gt(levels_with, 3)
	# Im Endlosmodus kommen Schemen ab Welle 6 dazu.
	var sim := GameData.create_sim("level_01")
	sim.wave_index = sim.wave_count - 1
	sim.status = GameSim.Status.WON
	sim.continue_endless()
	sim.endless_wave = 5
	var early := sim._make_endless_groups().filter(func(g): return g["enemy"] == "wraith")
	sim.endless_wave = 6
	var later := sim._make_endless_groups().filter(func(g): return g["enemy"] == "wraith")
	assert_eq(early.size(), 0)
	assert_eq(later.size(), 1)
	assert_eq(later[0]["count"], 6)


# --- Durchbruch -----------------------------------------------------------

func test_breach_opens_a_new_gate_with_a_way_to_the_heart() -> void:
	var sim := _sim([{"enemy": "fast", "count": 1}], {"rules": {"endless_breach_every": 2}})
	_endless(sim)
	watch_signals(sim)
	assert_eq(sim.grid.entrances.size(), 1)
	var spawned_at := {}
	sim.enemy_spawned.connect(func(e): spawned_at[MineGrid.cell_at(e.pos)] = true)
	while sim.endless_cleared < 6:
		sim.step()
	assert_eq(sim.grid.entrances.size(), 4, "nach den Endlos-Wellen 2, 4 und 6")
	assert_signal_emit_count(sim, "breached", 3)
	assert_true(sim.grid.has_path())
	for entrance in sim.grid.entrances:
		assert_eq(sim.grid.get_cell(entrance), MineGrid.Cell.ENTRANCE)
		assert_true(entrance.x == 0 or entrance.y == 0 or entrance.x == sim.grid.width - 1 or entrance.y == sim.grid.height - 1, "am Rand")
		assert_gte(sim.grid.distance(entrance), 8, "nicht direkt neben dem Herz")
	assert_gt(spawned_at.size(), 1, "Gegner kommen auch durch die neuen Tore")
	assert_eq(sim.grid.cells_of_type(MineGrid.Cell.BUILD).size(), 3, "Bauplätze bleiben unberührt")


func test_breach_is_repeatable_and_harmless_when_impossible() -> void:
	var cells := []
	for i in 2:
		var sim := _sim([{"enemy": "fast", "count": 1}])
		_endless(sim)
		assert_true(sim._breach())
		cells.append(sim.grid.entrances[-1])
	assert_eq(cells[0], cells[1], "gleicher Zufallswert, gleiche Stelle")
	# Ein Raster ohne Fels zwischen Rand und Stollen: kein Durchbruch, kein Fehler.
	var tight := _sim([{"enemy": "fast", "count": 1}], {"grid": ["#####", "E...H", "#o###"]})
	_endless(tight)
	assert_false(tight._breach())
	assert_eq(tight.grid.entrances.size(), 1)


func test_breach_cancels_dig_jobs_in_its_way_and_refunds_them() -> void:
	var sim := _sim([{"enemy": "fast", "count": 1}])
	_endless(sim)
	var candidates := sim.breach_candidates()
	assert_gt(candidates.size(), 0)
	var jobs := 0
	var gold := sim.gold
	for c in candidates:
		for cell in c["tunnel"]:
			if sim.dig(cell) == GameSim.Result.OK:
				jobs += 1
	assert_gt(jobs, 0)
	assert_eq(sim.gold, gold - 30 * jobs)
	var before := sim.dig_jobs.size()
	sim._breach()
	assert_lt(sim.dig_jobs.size(), before)
	assert_eq(sim.gold, gold - 30 * sim.dig_jobs.size(), "gestrichene Aufträge werden erstattet")


func test_breach_works_in_every_real_level() -> void:
	for id in GameData.LEVEL_ORDER:
		for rng_seed in 5:
			var sim := GameData.create_sim(id, "normal", rng_seed + 1)
			sim.wave_index = sim.wave_count - 1
			sim.status = GameSim.Status.WON
			sim.continue_endless()
			var before := sim.grid.entrances.size()
			for i in 3:
				sim._breach()
			if not sim.grid.has_path():
				fail_test("%s Zufall %d: kein Weg mehr" % [id, rng_seed])
				return
			for entrance in sim.grid.entrances:
				if sim.grid.distance(entrance) == MineGrid.UNREACHABLE:
					fail_test("%s Zufall %d: Tor %s ohne Weg" % [id, rng_seed, entrance])
					return
			assert_gte(sim.grid.entrances.size(), before)
	pass_test("jedes Level bleibt nach drei Durchbrüchen spielbar")


# --- Oberfläche -----------------------------------------------------------

func test_menus_offer_the_new_actions_and_moving_works_by_tapping() -> void:
	var real_save: String = Progress.save_path
	Progress.save_path = "user://test_rebuild_progress.json"
	LevelView.level_id = "level_02"
	LevelView.run_seed = 2
	var l: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l.set_process(false)
	var slots := l.sim.grid.cells_of_type(MineGrid.Cell.BUILD)
	l.sim.gold = 9000
	l.sim.ore = 900
	l.select_cell(slots[0])
	l.hud.action_requested.emit("build:crossbow")
	var ids := func(cell: Vector2i) -> Array: return l._menu_for(cell)["buttons"].map(func(b): return b["id"])
	assert_has(ids.call(slots[0]), "target")
	assert_has(ids.call(slots[0]), "move")
	assert_does_not_have(ids.call(slots[0]), "refine")
	l.hud.action_requested.emit("target")
	assert_eq(l.sim.towers[0].target_mode, "strong")
	# Ausbauen, spezialisieren, veredeln.
	while l.sim.upgrade_tower(slots[0]) == GameSim.Result.OK:
		pass
	l.sim.specialize(slots[0], 0)
	assert_has(ids.call(slots[0]), "refine")
	l.select_cell(slots[0])
	l.hud.action_requested.emit("refine")
	assert_eq(l.sim.towers[0].refine, 1)
	# Versetzen: Knopf, dann Zielplatz antippen.
	l.hud.action_requested.emit("move")
	assert_eq(l.moving_from, slots[0])
	assert_eq(l.hud.tip_text(), tr("HUD_MOVE_TIP"))
	l.select_cell(slots[3])
	assert_eq(l.moving_from, LevelView.NO_CELL)
	assert_eq(l.sim.towers[0].cell, slots[3])
	assert_almost_eq(l._tower_views[l.sim.towers[0].id].position.x, (slots[3].x + 0.5) * LevelView.CELL, 0.01)
	assert_eq(l.hud.tip_text(), "")
	# Abbruch: Antippen von Fels lässt den Turm stehen.
	l.select_cell(slots[3])
	l.hud.action_requested.emit("move")
	l.select_cell(Vector2i(1, 1))
	assert_eq(l.sim.towers[0].cell, slots[3])
	# Bauplätze gibt es erst im Endlosmodus.
	var rock := Vector2i(1, 1)
	assert_does_not_have(ids.call(rock), "create_slot")
	assert_does_not_have(ids.call(slots[1]), "remove_slot")
	l.sim.wave_index = l.sim.wave_count - 1
	l.sim.status = GameSim.Status.WON
	l.sim.continue_endless()
	assert_has(ids.call(rock), "create_slot")
	assert_has(ids.call(slots[1]), "remove_slot")
	l.select_cell(rock)
	l.hud.action_requested.emit("create_slot")
	assert_eq(l.sim.grid.get_cell(rock), MineGrid.Cell.BUILD)
	assert_eq(l.selected, rock, "der neue Bauplatz bleibt gewählt und zeigt das Baumenü")
	assert_has(ids.call(rock), "build:crossbow")
	# Durchbruch: neues Tor, Meldung.
	var gates := l.sim.grid.entrances.size()
	assert_true(l.sim._breach())
	assert_eq(l.sim.grid.entrances.size(), gates + 1)
	assert_eq(l.hud.notice_text(), tr("HUD_BREACH"))
	LevelView.run_seed = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))
	Progress.save_path = real_save
	Progress.load_progress()


func test_level_one_offers_build_sites_in_endless_although_digging_is_off() -> void:
	var real_save: String = Progress.save_path
	Progress.save_path = "user://test_rebuild_progress.json"
	LevelView.level_id = "level_01"
	LevelView.run_seed = 2
	var l: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l.set_process(false)
	assert_true(l._menu_for(Vector2i(1, 2)).is_empty(), "im normalen Spiel hat Fels in Level 1 kein Menü")
	l.sim.wave_index = l.sim.wave_count - 1
	l.sim.status = GameSim.Status.WON
	l.sim.continue_endless()
	var buttons: Array = l._menu_for(Vector2i(1, 2))["buttons"].map(func(b): return b["id"])
	assert_eq(buttons, ["create_slot"], "Bauplatz ja, Graben weiterhin nein")
	LevelView.run_seed = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))
	Progress.save_path = real_save
	Progress.load_progress()
