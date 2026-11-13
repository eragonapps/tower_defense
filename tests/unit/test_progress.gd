extends GutTest
## Spielstand, Sterne, Freischaltung, Schwierigkeitsgrade und Levelkarte.

const ProgressScript := preload("res://scripts/core/progress.gd")
const TMP := "user://test_progress.json"
const ORDER := ["a", "b", "c"]

var p: Node


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	p = ProgressScript.new()
	p.save_path = TMP
	add_child_autofree(p)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _fresh() -> Node:
	var other: Node = autofree(ProgressScript.new())
	other.save_path = TMP
	other.load_progress()
	return other


func test_stars_depend_on_lives_left() -> void:
	assert_eq(ProgressScript.stars_for(20, 20), 3)
	assert_eq(ProgressScript.stars_for(19, 20), 2)
	assert_eq(ProgressScript.stars_for(10, 20), 2)
	assert_eq(ProgressScript.stars_for(9, 20), 1)
	assert_eq(ProgressScript.stars_for(1, 20), 1)
	assert_eq(ProgressScript.stars_for(0, 20), 0)


func test_first_level_is_open_and_wins_unlock_the_next() -> void:
	assert_true(p.is_unlocked("a", ORDER))
	assert_false(p.is_unlocked("b", ORDER))
	assert_false(p.is_unlocked("c", ORDER))
	assert_false(p.is_unlocked("gibt_es_nicht", ORDER))
	p.record("a", "easy", 1)
	assert_true(p.is_unlocked("b", ORDER), "ein Sieg auf irgendeiner Schwierigkeit reicht")
	assert_false(p.is_unlocked("c", ORDER))


func test_stars_are_kept_per_difficulty_and_never_get_worse() -> void:
	watch_signals(p)
	assert_true(p.record("a", "normal", 2))
	assert_false(p.record("a", "normal", 1), "schlechteres Ergebnis")
	assert_false(p.record("a", "normal", 2), "gleiches Ergebnis")
	assert_eq(p.stars("a", "normal"), 2)
	assert_eq(p.stars("a", "hard"), 0)
	assert_true(p.record("a", "hard", 3))
	assert_eq(p.best_stars("a"), 3)
	assert_true(p.record("a", "normal", 99), "wird auf 3 begrenzt")
	assert_eq(p.stars("a", "normal"), 3)
	assert_signal_emit_count(p, "changed", 3)


func test_progress_survives_save_and_load() -> void:
	p.record("a", "normal", 3)
	p.record("b", "hard", 1)
	var other := _fresh()
	assert_eq(other.stars("a", "normal"), 3)
	assert_eq(other.stars("b", "hard"), 1)
	assert_true(other.is_unlocked("c", ORDER))
	other.reset()
	assert_eq(_fresh().best_stars("a"), 0)


func test_corrupt_save_file_gives_empty_progress_without_crash() -> void:
	for content in ["", "{", "[1, 2, 3]", "\"text\"", "{\"levels\": 5}", "{\"version\": 99, \"levels\": {\"a\": 7, \"b\": {\"normal\": \"viele\", \"hard\": -3}}}"]:
		var f := FileAccess.open(TMP, FileAccess.WRITE)
		f.store_string(content)
		f.close()
		var other := _fresh()
		assert_eq(other.best_stars("a"), 0, content)
		assert_eq(other.best_stars("b"), 0, content)
		assert_true(other.record("a", "normal", 1), "danach lässt sich normal weiterspielen")
	assert_push_warning("Spielstand ist beschädigt")


func test_newer_save_file_keeps_what_is_understood() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{\"version\": 2, \"neu\": true, \"levels\": {\"a\": {\"normal\": 2, \"albtraum\": 3, \"x\": 9}}}")
	f.close()
	var other := _fresh()
	assert_eq(other.stars("a", "normal"), 2)
	assert_eq(other.stars("a", "albtraum"), 3)
	assert_eq(other.stars("a", "x"), 3, "zu hohe Werte werden begrenzt")


# --- Schwierigkeitsgrade --------------------------------------------------

func test_difficulty_files_are_complete() -> void:
	var diffs := GameData.load_difficulties()
	for id in GameData.DIFFICULTY_ORDER:
		assert_true(diffs.has(id), id)
		assert_ne(tr(diffs[id]["name_key"]), diffs[id]["name_key"], "Übersetzung fehlt: %s" % id)
		for key in diffs[id]:
			assert_true(key == "name_key" or GameSim.DEFAULT_RULES.has(key), "unbekannter Wert %s" % key)
	assert_eq(GameData.rules_for("normal")["enemy_hp_factor"], 1.0)
	assert_eq(GameData.rules_for("normal")["start_gold_factor"], 1.0)


func test_difficulty_changes_enemy_health_and_start_gold() -> void:
	var easy := GameData.create_sim("level_01", "easy")
	var normal := GameData.create_sim("level_01", "normal")
	var hard := GameData.create_sim("level_01", "hard")
	assert_gt(easy.gold, normal.gold)
	assert_lt(hard.gold, normal.gold)
	for sim in [easy, normal, hard]:
		sim.start_next_wave()
		sim.step()
	assert_lt(easy.enemies[0].max_hp, normal.enemies[0].max_hp)
	assert_gt(hard.enemies[0].max_hp, normal.enemies[0].max_hp)
	assert_eq(hard.enemies[0].hp, hard.enemies[0].max_hp)


func test_harder_difficulty_is_really_harder() -> void:
	var results := {}
	for d in GameData.DIFFICULTY_ORDER:
		var sim := GameData.create_sim("level_01", d)
		var bot := Bots.BuilderBot.new(["crossbow", "crossbow", "sling"])
		while sim.status == GameSim.Status.RUNNING and sim.tick < 60 * 1800:
			if sim.tick % GameSim.TICK_RATE == 0:
				bot.act(sim)
				if sim.wave_index < 0 and sim.tick >= 300:
					sim.start_next_wave()
			sim.step()
		results[d] = sim.lives
	gut.p("Leben am Ende von Level 1: %s" % results)
	assert_gte(results["easy"], results["normal"])
	assert_gte(results["normal"], results["hard"])
	assert_gt(results["easy"], results["hard"])


# --- Levelkarte -----------------------------------------------------------

func test_level_map_shows_locks_and_updates_after_a_win() -> void:
	var real_path: String = Progress.save_path
	Progress.save_path = TMP
	Progress.reset()
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	assert_eq(menu.tiles.size(), GameData.LEVEL_ORDER.size())
	assert_false(menu.tiles["level_01"].disabled)
	assert_true(menu.tiles["level_02"].disabled)
	Progress.record("level_01", Settings.difficulty, 2)
	assert_false(menu.tiles["level_02"].disabled, "die Karte baut sich nach dem Sieg neu auf")
	assert_true(menu.tiles["level_03"].disabled)
	Progress.reset()
	Progress.save_path = real_path
	Progress.load_progress()


func test_winning_a_level_records_stars() -> void:
	var real_path: String = Progress.save_path
	Progress.save_path = TMP
	Progress.reset()
	LevelView.level_id = "level_01"
	var level: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	level.set_process(false)
	level.sim.lives = 12
	level.sim.status = GameSim.Status.WON
	level.sim.finished.emit(true)
	assert_eq(Progress.stars("level_01", Settings.difficulty), 2)
	assert_true(Progress.is_unlocked("level_02", GameData.LEVEL_ORDER))
	Progress.reset()
	Progress.save_path = real_path
	Progress.load_progress()
