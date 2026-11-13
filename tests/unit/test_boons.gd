extends GutTest
## Gaben der Ahnen: Angebot nach Wellen, Wahl, Wirkung.

var towers := {
	"bow": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 10, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff"},
	"fire": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff",
		"burn": {"dps": 10, "duration": 2.0}, "upgrades": [{"ore": 1, "burn": {"dps": 20, "duration": 2.0}}]},
}
var enemies := {
	"fast": {"name_key": "E", "hp": 10, "speed": 200.0, "bounty": 10, "lives": 1, "color": "#fff", "size": 1.0},
	"weak": {"name_key": "E", "hp": 1, "speed": 1.0, "bounty": 10, "lives": 1, "color": "#fff", "size": 1.0},
}
var boons := {
	"dmg": {"name_key": "B", "desc_key": "B", "effect": {"type": "stat", "towers": ["bow"], "stat": "damage", "factor": 2.0}},
	"speed": {"name_key": "B", "desc_key": "B", "effect": {"type": "stat", "towers": ["all"], "stat": "cooldown", "factor": 0.5}},
	"burn": {"name_key": "B", "desc_key": "B", "effect": {"type": "stat", "towers": ["fire"], "stat": "burn", "factor": 1.5}},
	"gold": {"name_key": "B", "desc_key": "B", "effect": {"type": "gold", "amount": 100}},
	"heal": {"name_key": "B", "desc_key": "B", "effect": {"type": "heal", "amount": 4}},
	"bounty": {"name_key": "B", "desc_key": "B", "effect": {"type": "bounty", "factor": 2.0}},
	"ore": {"name_key": "B", "desc_key": "B", "effect": {"type": "ore", "amount": 40}},
	"dig": {"name_key": "B", "desc_key": "B", "effect": {"type": "rule", "key": "dig_cost", "factor": 0.5}},
	"cannon": {"name_key": "B", "desc_key": "B", "effect": {"type": "stat", "towers": ["cannon"], "stat": "damage", "factor": 2.0}},
}


func _sim(rules := {}, rng_seed := 1, waves := 5, grid := ["E....H", "#oo::#"]) -> GameSim:
	var list := []
	for i in waves:
		list.append({"reward": 0, "groups": [{"enemy": "fast", "count": 1}]})
	return GameSim.new({"start_gold": 500, "start_ore": 10, "lives": 20, "wave_pause": 5.0, "towers": ["bow", "fire"], "grid": grid,
		"rules": rules, "waves": list}, towers, enemies, {}, boons, rng_seed)


## Spielt eine Welle zu Ende. Der schnelle Gegner erreicht das Herz sofort.
func _finish_wave(sim: GameSim) -> void:
	sim.start_next_wave()
	for i in 30:
		sim.step()


func _take(sim: GameSim, id: String) -> void:
	sim.pending_boons.assign([id])
	assert_true(sim.choose_boon(0))


func test_boons_are_offered_after_every_second_wave() -> void:
	var sim := _sim()
	watch_signals(sim)
	_finish_wave(sim)
	assert_eq(sim.pending_boons.size(), 0, "nach Welle 1 noch nicht")
	_finish_wave(sim)
	assert_eq(sim.pending_boons.size(), 3)
	assert_signal_emit_count(sim, "boons_offered", 1)
	var seen := {}
	for id in sim.pending_boons:
		assert_true(boons.has(id))
		assert_false(seen.has(id), "keine Gabe doppelt im Angebot")
		seen[id] = true


func test_boons_can_be_switched_off_and_are_not_offered_after_the_last_wave() -> void:
	var off := _sim({"boon_every": 0})
	_finish_wave(off)
	_finish_wave(off)
	assert_eq(off.pending_boons.size(), 0)
	var short := _sim({}, 1, 2)
	_finish_wave(short)
	_finish_wave(short)
	assert_eq(short.status, GameSim.Status.WON)
	assert_eq(short.pending_boons.size(), 0)


func test_only_useful_boons_are_offered() -> void:
	# Ohne Erzadern und mit abgeschaltetem Graben fallen Erz- und Grab-Gaben weg, ebenso die für fremde Türme.
	var sim := _sim({"boon_choices": 99, "digging": false})
	_finish_wave(sim)
	_finish_wave(sim)
	for id in ["ore", "dig", "cannon"]:
		assert_does_not_have(sim.pending_boons, id)
	assert_eq(sim.pending_boons.size(), 6)
	var with_ore := _sim({"boon_choices": 99}, 1, 5, ["E....H", "#oo*:#"])
	_finish_wave(with_ore)
	_finish_wave(with_ore)
	assert_has(with_ore.pending_boons, "ore")
	assert_has(with_ore.pending_boons, "dig")


func test_same_seed_gives_same_offer_and_other_seeds_differ() -> void:
	var offers := {}
	for rng_seed in [1, 1, 2, 3, 4, 5, 6, 7]:
		var sim := _sim({}, rng_seed)
		_finish_wave(sim)
		_finish_wave(sim)
		var key := str(sim.pending_boons)
		if rng_seed == 1 and offers.has("first"):
			assert_eq(key, offers["first"], "gleicher Zufallswert, gleiches Angebot")
		elif rng_seed == 1:
			offers["first"] = key
		offers[key] = true
	assert_gt(offers.size(), 3, "verschiedene Zufallswerte ergeben verschiedene Angebote")


func test_waiting_for_a_choice_stops_the_countdown() -> void:
	var sim := _sim()
	_finish_wave(sim)
	_finish_wave(sim)
	var before := sim.next_wave_in
	for i in 600:
		sim.step()
	assert_eq(sim.next_wave_in, before)
	assert_eq(sim.wave_index, 1)
	sim.choose_boon(0)
	for i in 400:
		sim.step()
	assert_eq(sim.wave_index, 2, "nach der Wahl läuft die Pause normal weiter")


func test_choice_is_recorded_and_not_offered_again() -> void:
	var sim := _sim({"boon_choices": 99})
	_finish_wave(sim)
	_finish_wave(sim)
	watch_signals(sim)
	var chosen := sim.pending_boons[1]
	assert_false(sim.choose_boon(99))
	assert_true(sim.choose_boon(1))
	assert_eq(sim.active_boons, [chosen] as Array[String])
	assert_eq(sim.pending_boons.size(), 0)
	assert_signal_emitted_with_parameters(sim, "boon_chosen", [chosen])
	assert_false(sim.choose_boon(0), "nur eine Wahl je Angebot")
	_finish_wave(sim)
	_finish_wave(sim)
	assert_does_not_have(sim.pending_boons, chosen)


func test_starting_the_wave_without_choosing_forfeits_the_boon() -> void:
	var sim := _sim()
	_finish_wave(sim)
	_finish_wave(sim)
	sim.start_next_wave()
	assert_eq(sim.pending_boons.size(), 0)
	assert_eq(sim.active_boons.size(), 0)


func test_stat_boons_change_existing_and_future_towers() -> void:
	var sim := _sim()
	sim.build_tower(Vector2i(1, 1), "bow")
	_take(sim, "dmg")
	_take(sim, "speed")
	sim.build_tower(Vector2i(2, 1), "bow")
	for t in sim.towers:
		assert_eq(t.stats["damage"], 20.0)
		assert_eq(t.stats["cooldown"], 0.5)
		assert_eq(t.stats["range"], 2.0)
	assert_eq(towers["bow"]["damage"], 10, "die Grunddaten bleiben unverändert")
	sim.sell_tower(Vector2i(2, 1))
	sim.build_tower(Vector2i(2, 1), "fire")
	assert_eq(sim.tower_at(Vector2i(2, 1)).stats["cooldown"], 0.5, "gilt für alle Türme")
	assert_eq(sim.tower_at(Vector2i(2, 1)).stats["damage"], 0, "der Schadensbonus gilt nur für den genannten Turm")


func test_burn_boon_survives_upgrades_and_shows_in_the_preview() -> void:
	var sim := _sim()
	sim.build_tower(Vector2i(1, 1), "fire")
	_take(sim, "burn")
	var t := sim.towers[0]
	assert_eq(t.stats["burn"]["dps"], 15.0)
	assert_eq(sim.next_stats(t)["burn"]["dps"], 30.0, "die Vorschau rechnet die Gabe ein")
	sim.upgrade_tower(Vector2i(1, 1))
	assert_eq(t.stats["burn"]["dps"], 30.0)
	assert_eq(towers["fire"]["burn"]["dps"], 10)


func test_instant_boons() -> void:
	var sim := _sim()
	_take(sim, "gold")
	assert_eq(sim.gold, 600)
	_take(sim, "ore")
	assert_eq(sim.ore, 50)
	sim.lives = 18
	_take(sim, "heal")
	assert_eq(sim.lives, 20, "heilt höchstens bis zum Anfangswert")
	_take(sim, "dig")
	assert_eq(sim.rules["dig_cost"], 15.0)


func test_bounty_boon_pays_more_gold() -> void:
	var sim := GameSim.new({"start_gold": 500, "lives": 20, "wave_pause": 5.0, "towers": ["bow"], "grid": ["E....H", "#oo::#"],
		"waves": [{"reward": 0, "groups": [{"enemy": "weak", "count": 1}]}]}, towers, enemies, {}, boons)
	sim.build_tower(Vector2i(1, 1), "bow")
	_take(sim, "bounty")
	sim.start_next_wave()
	for i in 300:
		sim.step()
	assert_eq(sim.kills, 1)
	assert_eq(sim.gold, 500 - 50 + 20)


func test_real_boons_are_valid_and_translated() -> void:
	var real := GameData.load_boons()
	assert_gte(real.size(), 9)
	assert_eq(GameData.validate_boons(real, GameData.load_towers()), [] as Array[String])
	var before := TranslationServer.get_locale()
	for locale in ["de", "en"]:
		TranslationServer.set_locale(locale)
		for id in real:
			assert_ne(tr(real[id]["name_key"]), real[id]["name_key"], "%s (%s)" % [id, locale])
			assert_ne(tr(real[id]["desc_key"]), real[id]["desc_key"], "%s (%s)" % [id, locale])
	TranslationServer.set_locale(before)
	var broken := {"x": {"name_key": "B", "effect": {"type": "stat", "towers": ["kanone"], "stat": "glück", "factor": 2}}}
	assert_eq(GameData.validate_boons(broken, GameData.load_towers()).size(), 3)


func test_boon_choice_in_the_level_scene_pauses_and_resumes() -> void:
	var real_save: String = Progress.save_path
	Progress.save_path = "user://test_boons_progress.json"
	LevelView.level_id = "level_02"
	LevelView.run_seed = 7
	var level: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	level.set_process(false)
	level.sim.pending_boons.assign(["gold_vein", "eagle_eye"])
	level.sim.boons_offered.emit(level.sim.pending_boons.duplicate())
	assert_true(level.hud.is_boons_visible())
	var gold := level.sim.gold
	level.hud.boon_requested.emit(0)
	assert_false(level.hud.is_boons_visible())
	assert_eq(level.sim.gold, gold + 120)
	assert_eq(level.sim.active_boons, ["gold_vein"] as Array[String])
	LevelView.run_seed = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))
	Progress.save_path = real_save
	Progress.load_progress()
