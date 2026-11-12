extends GutTest
## Prüft die echten Spieldaten und lässt Bots jedes Level spielen.

var towers: Dictionary
var enemies: Dictionary


func before_all() -> void:
	towers = GameData.load_towers()
	enemies = GameData.load_enemies()


func test_all_levels_are_valid() -> void:
	assert_gt(GameData.LEVEL_ORDER.size(), 0)
	for id in GameData.LEVEL_ORDER:
		var level := GameData.load_level(id)
		assert_eq(GameData.validate(level, towers, enemies), [] as Array[String], id)


func test_validation_finds_broken_data() -> void:
	var level := GameData.load_level("level_01")
	level["waves"][0]["groups"][0]["enemy"] = "drache"
	level["towers"].append("kanone")
	var errors := GameData.validate(level, towers, enemies)
	assert_eq(errors.size(), 2)
	level.erase("lives")
	assert_eq(GameData.validate(level, towers, enemies).size(), 1)


func test_every_data_name_has_a_translation() -> void:
	var before := TranslationServer.get_locale()
	var keys := []
	for d in towers.values() + enemies.values():
		keys.append(d["name_key"])
	for id in GameData.LEVEL_ORDER:
		keys.append(GameData.load_level(id)["name_key"])
	for locale in ["de", "en"]:
		TranslationServer.set_locale(locale)
		for key in keys:
			assert_ne(tr(key), key, "Übersetzung fehlt (%s): %s" % [locale, key])
	TranslationServer.set_locale(before)


func test_every_build_slot_can_reach_the_path() -> void:
	var min_range := 999.0
	for t in towers.values():
		min_range = minf(min_range, t["range"])
	for id in GameData.LEVEL_ORDER:
		var grid := MineGrid.from_rows(GameData.load_level(id)["grid"])
		var path := grid.path_cells()
		for slot in grid.cells_of_type(MineGrid.Cell.BUILD):
			var reachable := false
			for p in path:
				if MineGrid.center(slot).distance_to(MineGrid.center(p)) <= min_range:
					reachable = true
					break
			assert_true(reachable, "%s: Bauplatz %s erreicht den Weg nicht" % [id, slot])


func test_building_nothing_loses_every_level() -> void:
	for id in GameData.LEVEL_ORDER:
		var sim := Bots.run(GameData.load_level(id), towers, enemies, Bots.NoneBot.new())
		assert_eq(sim.status, GameSim.Status.LOST, id)


func test_sensible_play_wins_every_level() -> void:
	for id in GameData.LEVEL_ORDER:
		var sim := Bots.run(GameData.load_level(id), towers, enemies, Bots.BuilderBot.new(["crossbow", "crossbow", "sling"]))
		assert_eq(sim.status, GameSim.Status.WON, id)
		assert_gt(sim.lives, int(GameData.load_level(id)["lives"]) / 2, "%s: zu knapp für das Einstiegsniveau" % id)


func test_stress_300_enemies_40_towers_stays_fast() -> void:
	var rows := ["##########################################"]
	rows.append("E" + ".".repeat(40) + "H")
	rows.append("#" + "o".repeat(40) + "#")
	var big := {"name_key": "E", "hp": 100000, "speed": 0.1, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0}
	var level := {
		"start_gold": 100000, "lives": 999, "wave_pause": 1.0, "towers": towers.keys(), "grid": rows,
		"waves": [{"reward": 0, "groups": [{"enemy": "big", "count": 300, "interval": 0.02}]}],
	}
	var sim := GameSim.new(level, towers, {"big": big})
	var types := towers.keys()
	for x in 40:
		assert_eq(sim.build_tower(Vector2i(x + 1, 2), types[x % types.size()]), GameSim.BuildResult.OK)
	sim.start_next_wave()
	for i in 600:
		sim.step()
	assert_eq(sim.enemies.size(), 300)
	var t0 := Time.get_ticks_usec()
	for i in 300:
		sim.step()
	var ms_per_step := (Time.get_ticks_usec() - t0) / 1000.0 / 300.0
	gut.p("Belastung: %.2f ms pro Schritt bei %d Gegnern, %d Türmen" % [ms_per_step, sim.enemies.size(), sim.towers.size()])
	# Ein Schritt darf höchstens ein Viertel eines Bildes bei 60 Bildern pro Sekunde kosten.
	assert_lt(ms_per_step, 4.0)
