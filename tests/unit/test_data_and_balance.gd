extends GutTest
## Prüft die echten Spieldaten und lässt Bots jedes Level spielen.

## Felder, die der Minen-Bot je Level gräbt, um die sicheren Erzadern zu erreichen.
const MINE_DIGS := {
	"level_02": [Vector2i(4, 3), Vector2i(4, 2), Vector2i(12, 3)],
	"level_03": [Vector2i(3, 3), Vector2i(10, 4), Vector2i(14, 6)],
	"level_04": [Vector2i(8, 5), Vector2i(12, 2), Vector2i(5, 2)],
}
const ALL_TOWERS := ["crossbow", "forge", "sling", "crossbow", "bomb", "runestone", "shieldwall"]

var towers: Dictionary
var enemies: Dictionary
var rules: Dictionary


func before_all() -> void:
	towers = GameData.load_towers()
	enemies = GameData.load_enemies()
	rules = GameData.load_rules()


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


func test_every_build_slot_can_reach_a_tunnel() -> void:
	# Auch Sackgassen zählen: sie können durch Graben zum Weg der Gegner werden.
	var min_range := 999.0
	for t in towers.values():
		# Der Schildwall wirkt nur direkt neben dem Stollen und wird unten eigens geprüft.
		if t.get("kind", "") != "block":
			min_range = minf(min_range, t["range"])
	for id in GameData.LEVEL_ORDER:
		var grid := MineGrid.from_rows(GameData.load_level(id)["grid"])
		var tunnels := grid.cells_of_type(MineGrid.Cell.TUNNEL)
		for slot in grid.cells_of_type(MineGrid.Cell.BUILD):
			var reachable := false
			for p in tunnels:
				if MineGrid.center(slot).distance_to(MineGrid.center(p)) <= min_range:
					reachable = true
					break
			assert_true(reachable, "%s: Bauplatz %s erreicht keinen Stollen" % [id, slot])


func test_levels_with_shield_wall_have_slots_right_next_to_the_path() -> void:
	for id in GameData.LEVEL_ORDER:
		var level := GameData.load_level(id)
		for type in level["towers"]:
			if towers[type].get("kind", "") != "block":
				continue
			var grid := MineGrid.from_rows(level["grid"])
			var usable := 0
			for slot in grid.cells_of_type(MineGrid.Cell.BUILD):
				for p in grid.path_cells():
					if MineGrid.center(slot).distance_to(MineGrid.center(p)) <= float(towers[type]["range"]):
						usable += 1
						break
			assert_gte(usable, 5, "%s: zu wenige Bauplätze, an denen %s wirkt" % [id, type])


func _play(id: String, bot: Object) -> GameSim:
	return Bots.run(GameData.load_level(id), towers, enemies, bot, 1800.0, rules)


func test_rules_file_only_uses_known_rules() -> void:
	assert_gt(rules.size(), 0)
	for key in rules:
		assert_true(GameSim.DEFAULT_RULES.has(key), "unbekannte Regel %s" % key)


func test_building_nothing_loses_every_level() -> void:
	for id in GameData.LEVEL_ORDER:
		assert_eq(_play(id, Bots.NoneBot.new()).status, GameSim.Status.LOST, id)


func _pattern(id: String) -> Array:
	var allowed: Array = GameData.load_level(id)["towers"]
	return ALL_TOWERS.filter(func(t): return t in allowed)


func test_sensible_play_wins_every_level() -> void:
	for id in GameData.LEVEL_ORDER:
		var sim := _play(id, Bots.MinerBot.new(_pattern(id), MINE_DIGS.get(id, [])))
		assert_eq(sim.status, GameSim.Status.WON, id)
		assert_gt(sim.lives, int(GameData.load_level(id)["lives"]) / 3, "%s: zu knapp" % id)


func test_using_the_mine_pays_off() -> void:
	for id in MINE_DIGS:
		for pattern in [["crossbow", "crossbow", "sling"], _pattern(id)]:
			var without := _play(id, Bots.BuilderBot.new(pattern))
			var with_mine := _play(id, Bots.MinerBot.new(pattern, MINE_DIGS[id]))
			assert_eq(with_mine.status, GameSim.Status.WON, "%s %s" % [id, pattern])
			assert_gt(with_mine.lives, without.lives, "%s %s: die Mine bringt keinen Vorteil" % [id, pattern])


func test_every_allowed_tower_and_listed_enemy_is_used_somewhere() -> void:
	var used_towers := {}
	var used_enemies := {}
	for id in GameData.LEVEL_ORDER:
		var level := GameData.load_level(id)
		for t in level["towers"]:
			used_towers[t] = true
		for w in level["waves"]:
			for g in w["groups"]:
				used_enemies[g["enemy"]] = true
	for t in towers:
		assert_true(used_towers.has(t), "Turm %s kommt in keinem Level vor" % t)
	for e in enemies:
		assert_true(used_enemies.has(e), "Gegner %s kommt in keiner Welle vor" % e)


func test_level_two_ore_pays_for_upgrades() -> void:
	var sim := _play("level_02", Bots.MinerBot.new(["crossbow", "crossbow", "sling"], MINE_DIGS["level_02"]))
	var upgraded := 0
	var mined := 0
	for t in sim.towers:
		if t.level > 1:
			upgraded += 1
	for w in sim.workers:
		mined += w.mined
		assert_gt(w.mined, 0, "Arbeiter an %s hat nichts abgebaut" % w.cell)
	assert_eq(sim.workers.size(), 3)
	assert_gt(upgraded, 5)
	assert_gt(mined, 100)


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
		assert_eq(sim.build_tower(Vector2i(x + 1, 2), types[x % types.size()]), GameSim.Result.OK)
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
