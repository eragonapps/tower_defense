extends GutTest
## Zwergenhalle, Grafikstufen und die Einführung in Level 1.

const ProgressScript := preload("res://scripts/core/progress.gd")
const TMP := "user://test_hall_progress.json"
const HALL := {
	"gold": {"name_key": "H", "desc_key": "H", "costs": [1, 2], "effect": {"rule": "start_gold_bonus", "per_level": 25}},
	"cheap": {"name_key": "H", "desc_key": "H", "costs": [3], "effect": {"rule": "tower_cost_factor", "per_level": -0.1}},
}

var p: Node


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	p = ProgressScript.new()
	p.save_path = TMP
	add_child_autofree(p)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_stars_are_the_currency_of_the_hall() -> void:
	assert_eq(p.total_stars(), 0)
	assert_false(p.buy_hall("gold", HALL), "ohne Sterne kein Kauf")
	p.record("a", "easy", 2)
	p.record("a", "hard", 3)
	p.record("b", "normal", 1)
	assert_eq(p.total_stars(), 4, "je Level zählt der beste Wert")
	assert_eq(p.hall_cost("gold", HALL), 1)
	assert_true(p.buy_hall("gold", HALL))
	assert_eq(p.hall_level("gold"), 1)
	assert_eq(p.free_stars(HALL), 3)
	assert_eq(p.hall_cost("gold", HALL), 2)
	assert_true(p.buy_hall("gold", HALL))
	assert_eq(p.free_stars(HALL), 1)
	assert_eq(p.hall_cost("gold", HALL), -1, "voll ausgebaut")
	assert_false(p.buy_hall("gold", HALL))
	assert_false(p.buy_hall("cheap", HALL), "3 Sterne nötig, nur 1 frei")
	assert_false(p.buy_hall("gibt_es_nicht", HALL))
	assert_eq(p.free_stars(HALL), 1)


func test_hall_gives_rules_on_top_of_the_base_rules() -> void:
	p.record("a", "normal", 3)
	p.record("b", "normal", 3)
	assert_eq(p.hall_rules(HALL, {}), {})
	p.buy_hall("gold", HALL)
	p.buy_hall("gold", HALL)
	p.buy_hall("cheap", HALL)
	var rules: Dictionary = p.hall_rules(HALL, {"start_gold_bonus": 10, "tower_cost_factor": 1.0})
	assert_eq(rules["start_gold_bonus"], 60.0)
	assert_almost_eq(rules["tower_cost_factor"], 0.9, 0.0001)
	assert_eq(rules.size(), 2)


func test_hall_survives_save_and_load_and_can_be_reset() -> void:
	p.record("a", "normal", 3)
	p.buy_hall("gold", HALL)
	var other: Node = autofree(ProgressScript.new())
	other.save_path = TMP
	other.load_progress()
	assert_eq(other.hall_level("gold"), 1)
	assert_eq(other.free_stars(HALL), 2)
	other.reset_hall()
	assert_eq(other.hall_level("gold"), 0)
	assert_eq(other.free_stars(HALL), 3, "die Sterne kommen zurück")
	assert_eq(other.stars("a", "normal"), 3, "der Levelfortschritt bleibt")


func test_removed_hall_upgrade_in_an_old_save_does_no_harm() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"levels\": {\"a\": {\"normal\": 3}}, \"hall\": {\"abgeschafft\": 2, \"gold\": 9, \"cheap\": \"x\"}}")
	f.close()
	p.load_progress()
	assert_eq(p.spent_stars(HALL), 3, "gold zählt höchstens bis zur letzten Stufe, Unbekanntes kostet nichts")
	assert_eq(p.hall_rules(HALL, {})["start_gold_bonus"], 50.0)


func test_hall_effects_reach_the_game() -> void:
	var towers := GameData.load_towers()
	var level := GameData.load_level("level_01")
	var plain := GameSim.new(level, towers, GameData.load_enemies(), {})
	var rules := {"start_gold_bonus": 50, "lives_bonus": 4, "start_ore_bonus": 12, "tower_cost_factor": 0.8, "sell_refund": 0.9}
	var better := GameSim.new(level, towers, GameData.load_enemies(), rules)
	assert_eq(better.gold, plain.gold + 50)
	assert_eq(better.lives, plain.lives + 4)
	assert_eq(better.max_lives, plain.max_lives + 4, "drei Sterne gibt es weiter nur ohne Verlust")
	assert_eq(better.ore, 12)
	assert_eq(better.tower_cost("crossbow"), 40)
	var slot: Vector2i = better.grid.cells_of_type(MineGrid.Cell.BUILD)[0]
	var before := better.gold
	better.build_tower(slot, "crossbow")
	assert_eq(better.gold, before - 40)
	assert_eq(better.sell_value(better.towers[0]), 36, "90 % des bezahlten Preises")
	better.sell_tower(slot)
	assert_eq(better.gold, before - 4)


func test_real_hall_is_valid_translated_and_cannot_be_bought_out() -> void:
	var hall := GameData.load_hall()
	assert_gte(hall.size(), 5)
	assert_eq(GameData.validate_hall(hall), [] as Array[String])
	var total := 0
	var before := TranslationServer.get_locale()
	for id in hall:
		for c in hall[id]["costs"]:
			total += int(c)
		for locale in ["de", "en"]:
			TranslationServer.set_locale(locale)
			assert_ne(tr(hall[id]["name_key"]), hall[id]["name_key"], id)
			assert_ne(tr(hall[id]["desc_key"]), hall[id]["desc_key"], id)
	TranslationServer.set_locale(before)
	var max_stars := GameData.LEVEL_ORDER.size() * 3
	gut.p("Halle komplett: %d Sterne, erreichbar: %d" % [total, max_stars])
	assert_gt(total, max_stars, "man soll wählen müssen")
	assert_eq(GameData.validate_hall({"x": {"name_key": "H", "costs": [0], "effect": {"rule": "zauberei"}}}).size(), 3)


func test_hall_screen_buys_and_resets() -> void:
	var real_path: String = Progress.save_path
	Progress.save_path = TMP
	Progress.reset()
	Progress.record("level_01", "normal", 3)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu._hall_button.pressed.emit()
	assert_true(menu._hall.visible)
	assert_eq(menu.hall_buttons.size(), GameData.load_hall().size())
	assert_false(menu.hall_buttons["treasury"].disabled)
	assert_true(menu.hall_buttons["shrine"].disabled, "kostet 4 Sterne, 3 sind da")
	menu.hall_buttons["treasury"].pressed.emit()
	assert_eq(Progress.hall_level("treasury"), 1)
	assert_eq(Progress.free_stars(GameData.load_hall()), 2)
	assert_eq(LevelView._rules()["start_gold_bonus"], 25.0, "die Verbesserung gilt im nächsten Level")
	(menu._hall.find_child("Reset", true, false) as Button).pressed.emit()
	assert_eq(Progress.hall_level("treasury"), 0)
	Progress.reset()
	Progress.save_path = real_path
	Progress.load_progress()


# --- Grafik und Einführung ------------------------------------------------

func _level(id: String) -> LevelView:
	LevelView.level_id = id
	LevelView.run_seed = 3
	var l: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l.set_process(false)
	return l


func test_low_graphics_drops_shadows_torch_lights_and_particles() -> void:
	var before: String = Settings.graphics
	Settings.graphics = "high"
	var high := _level("level_02")
	var lights_high := high.find_children("*", "OmniLight3D", true, false).size()
	var sun_high: DirectionalLight3D = high.find_children("*", "DirectionalLight3D", true, false)[0]
	assert_true(sun_high.shadow_enabled)
	high._burst(Vector3.ZERO, Color.WHITE, 4)
	assert_eq(high.find_children("*", "CPUParticles3D", true, false).size(), 1)
	Settings.graphics = "low"
	var low := _level("level_02")
	var sun_low: DirectionalLight3D = low.find_children("*", "DirectionalLight3D", true, false)[0]
	assert_false(sun_low.shadow_enabled)
	assert_lt(low.find_children("*", "OmniLight3D", true, false).size(), lights_high, "keine Fackellichter")
	low._burst(Vector3.ZERO, Color.WHITE, 4)
	assert_eq(low.find_children("*", "CPUParticles3D", true, false).size(), 0)
	assert_lt(low.get_viewport().scaling_3d_scale, 1.0)
	Settings.graphics = before
	get_viewport().scaling_3d_scale = 1.0
	LevelView.run_seed = 0


func test_tutorial_follows_what_the_player_does_and_runs_only_once() -> void:
	var before: bool = Settings.tutorial_done
	Settings.tutorial_done = false
	var l := _level("level_01")
	assert_eq(l.tutorial_step, 0)
	l._update_tutorial()
	assert_eq(l.hud.tip_text(), tr("TUTORIAL_0"))
	var slot: Vector2i = l.sim.grid.cells_of_type(MineGrid.Cell.BUILD)[0]
	l.select_cell(slot)
	l._update_tutorial()
	assert_eq(l.hud.tip_text(), tr("TUTORIAL_1"))
	l._update_tutorial()
	assert_eq(l.tutorial_step, 1, "ohne Bau geht es nicht weiter")
	l.hud.action_requested.emit("build:crossbow")
	l._update_tutorial()
	assert_eq(l.hud.tip_text(), tr("TUTORIAL_2"))
	l.hud.wave_requested.emit()
	l._update_tutorial()
	assert_eq(l.hud.tip_text(), tr("TUTORIAL_3"))
	l.sim.wave_index = 2
	l._update_tutorial()
	l._update_tutorial()
	l._update_tutorial()
	assert_eq(l.tutorial_step, -1)
	assert_eq(l.hud.tip_text(), "")
	assert_true(Settings.tutorial_done)
	assert_eq(_level("level_01").tutorial_step, -1, "beim zweiten Mal gibt es keine Einführung")
	Settings.tutorial_done = false
	assert_eq(_level("level_02").tutorial_step, -1, "nur Level 1 hat eine Einführung")
	Settings.set_tutorial_done(before)
	LevelView.run_seed = 0
