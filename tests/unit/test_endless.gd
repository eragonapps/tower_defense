extends GutTest
## Endlosmodus, Flüche, Rekorde mit Bonus-Sternen und die Mechaniken der neuen Gaben.

const ProgressScript := preload("res://scripts/core/progress.gd")
const TMP := "user://test_endless_progress.json"

var towers := {
	"bow": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "pierce",
		"upgrades": [{"ore": 20, "damage": 20}], "specs": [{"id": "a", "name_key": "S", "desc_key": "S", "ore": 40, "damage": 50}, {"id": "b", "name_key": "S", "desc_key": "S", "ore": 40, "range": 5.0}]},
	"sling": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 1.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "blunt"},
	"fire": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 30.0, "damage": 0, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "fire",
		"burn": {"dps": 10, "duration": 3.0}},
	"rune": {"name_key": "T", "kind": "aura", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"slow": {"factor": 0.5, "duration": 1.5}},
}
var enemies := {
	"fast": {"name_key": "E", "hp": 10, "speed": 200.0, "bounty": 10, "lives": 1, "color": "#fff", "size": 1.0},
	"walker": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 10, "lives": 1, "color": "#fff", "size": 1.0},
	"frail": {"name_key": "E", "hp": 15, "speed": 1.0, "bounty": 10, "lives": 1, "color": "#fff", "size": 1.0},
	"weak": {"name_key": "E", "hp": 25, "speed": 1.0, "bounty": 10, "lives": 1, "color": "#fff", "size": 1.0},
	"king": {"name_key": "E", "hp": 5000, "speed": 200.0, "bounty": 0, "lives": 20, "color": "#fff", "size": 2.0, "unblockable": true},
	"thief": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 0, "lives": 1, "color": "#fff", "size": 1.0, "steal": {"ore": 6, "radius": 1.6}},
}
var curses := {
	"swift": {"name_key": "C", "desc_key": "C", "effect": {"type": "enemy_speed", "factor": 1.5}},
}
const GRID := ["E..............H", "#o:::o:::o:*:::#"]


func _sim(wave_enemy := "fast", extra := {}, boons := {}, rng_seed := 1) -> GameSim:
	var level := {"start_gold": 1000, "start_ore": 100, "lives": 30, "wave_pause": 2.0, "towers": towers.keys(), "grid": GRID,
		"rules": {"ore_only_during_waves": false, "boon_every": 0, "endless_boon_every": 0},
		"waves": [{"reward": 0, "groups": [{"enemy": wave_enemy, "count": 1}]}, {"reward": 0, "groups": [{"enemy": wave_enemy, "count": 2, "interval": 0.5}]}]}
	for key in extra:
		if key == "rules":
			level["rules"].merge(extra["rules"], true)
		else:
			level[key] = extra[key]
	return GameSim.new(level, towers, enemies, {}, boons, rng_seed, curses)


func _run(sim: GameSim, seconds: float) -> void:
	for i in int(round(seconds * GameSim.TICK_RATE)):
		sim.step()


## Spielt beide festen Wellen durch. Die schnellen Gegner laufen sofort ins Herz.
func _win(sim: GameSim) -> void:
	sim.start_next_wave()
	_run(sim, 0.5)
	sim.start_next_wave()
	_run(sim, 1.5)
	assert_eq(sim.status, GameSim.Status.WON)


func _flag(sim: GameSim, effects: Array) -> void:
	for e in effects:
		sim._apply_effect(e)


# --- Endlosmodus ----------------------------------------------------------

func test_endless_can_only_start_after_a_win_and_keeps_everything() -> void:
	var sim := _sim()
	assert_false(sim.continue_endless(), "vor dem Sieg nicht")
	sim.build_tower(Vector2i(1, 1), "bow")
	_win(sim)
	var gold := sim.gold
	var lives := sim.lives
	assert_true(sim.continue_endless())
	assert_true(sim.endless)
	assert_eq(sim.status, GameSim.Status.RUNNING)
	assert_eq(sim.gold, gold)
	assert_eq(sim.lives, lives)
	assert_eq(sim.towers.size(), 1)
	assert_false(sim.continue_endless(), "nur einmal")
	assert_true(sim.can_start_wave())


func test_endless_waves_start_by_themselves_and_never_end_in_victory() -> void:
	var sim := _sim("fast", {"lives": 9999})
	_win(sim)
	sim.continue_endless()
	watch_signals(sim)
	_run(sim, 30.0)
	assert_gt(sim.endless_wave, 5)
	assert_eq(sim.endless_cleared, sim.endless_wave - (1 if sim.wave_active else 0))
	assert_ne(sim.status, GameSim.Status.WON)
	assert_eq(sim.wave_number(), 2 + sim.endless_wave)
	assert_signal_not_emitted(sim, "finished")


func test_endless_enemies_get_tougher_every_wave() -> void:
	var sim := _sim("walker", {"lives": 9999})
	sim.status = GameSim.Status.WON
	sim.wave_index = 1
	sim.continue_endless()
	var hp := []
	for n in 3:
		sim.start_next_wave()
		sim.step()
		hp.append(sim.enemies[-1].max_hp)
		while sim.wave_active:
			sim.step()
	assert_almost_eq(hp[0], 1000.0 * 1.08, 0.01)
	assert_almost_eq(hp[1], 1000.0 * 1.08 * 1.08, 0.01)
	assert_gt(hp[2], hp[1])


func test_endless_bounty_grows_slower_than_health() -> void:
	# Ohne Boss und Fluch, damit nur das Kopfgeld des einen Gegners zählt.
	var sim := _sim("weak", {"lives": 9999, "rules": {"endless_boss_every": 0, "endless_curse_every": 0}})
	sim.build_tower(Vector2i(1, 1), "bow")
	sim.status = GameSim.Status.WON
	sim.wave_index = 1
	sim.continue_endless()
	sim.endless_wave = 9
	var before := sim.gold
	sim.start_next_wave()
	var guard := 0
	while sim.kills == 0 and guard < 6000:
		sim.step()
		guard += 1
	# Welle 10: Kopfgeld 10 × 1,3 = 13. Die Lebenspunkte sind dagegen mehr als doppelt so hoch.
	# War es der letzte Gegner der Welle, kommt im selben Schritt die Wellenprämie dazu: 40 + 5 × 10.
	var reward := 0 if sim.wave_active else 90
	assert_eq(sim.gold - before - reward, 13)
	assert_gt(pow(1.08, 10), 2.0)


func test_endless_brings_a_boss_and_a_curse_every_fifth_wave() -> void:
	var sim := _sim("fast", {"lives": 9999})
	_win(sim)
	sim.continue_endless()
	var bosses := {}
	sim.enemy_spawned.connect(func(e): 
		if e.type == "king":
			bosses[sim.endless_wave] = int(bosses.get(sim.endless_wave, 0)) + 1)
	var curse_waves := []
	sim.curse_added.connect(func(_id): curse_waves.append(sim.endless_wave))
	while sim.endless_cleared < 11:
		sim.step()
	assert_eq(bosses.keys(), [5, 10])
	assert_eq(curse_waves, [5, 10])
	assert_eq(sim.active_curses, ["swift", "swift"] as Array[String])
	assert_almost_eq(sim.enemy_speed_factor, 2.25, 0.001, "derselbe Fluch stapelt sich")


func test_endless_boss_costs_fewer_lives_and_has_less_health() -> void:
	var sim := _sim("fast", {"lives": 30})
	_win(sim)
	sim.continue_endless()
	sim.endless_wave = 4
	var lives := sim.lives
	var boss_hp := [0.0]
	sim.enemy_spawned.connect(func(e): 
		if e.type == "king":
			boss_hp[0] = e.max_hp)
	sim.start_next_wave()
	while sim.wave_active and sim.status == GameSim.Status.RUNNING:
		sim.step()
	assert_almost_eq(boss_hp[0], 5000.0 * pow(1.08, 5) * 0.5, 0.01)
	# Ein oder zwei schnelle Gegner (je nach Vorlage) und der Boss kommen durch: der Boss kostet 8 statt 20.
	assert_between(lives - sim.lives, 9, 10)


func test_endless_ends_in_defeat_when_lives_run_out() -> void:
	var sim := _sim("fast", {"lives": 4})
	_win(sim)
	assert_eq(sim.lives, 1)
	sim.continue_endless()
	watch_signals(sim)
	_run(sim, 10.0)
	assert_eq(sim.status, GameSim.Status.LOST)
	assert_signal_emitted_with_parameters(sim, "finished", [false])
	assert_eq(sim.endless_cleared, 0)


func test_endless_holds_back_reinforcements_when_the_screen_is_full() -> void:
	var sim := _sim("walker", {"lives": 99999, "waves": [{"reward": 0, "groups": [{"enemy": "walker", "count": 400, "interval": 0.01}]}]})
	sim.status = GameSim.Status.WON
	sim.wave_index = 0
	sim.continue_endless()
	sim.start_next_wave()
	var peak := 0
	for i in 600:
		sim.step()
		peak = maxi(peak, sim.enemies.size())
	assert_between(peak, GameSim.ENDLESS_MAX_ENEMIES, GameSim.ENDLESS_MAX_ENEMIES + 1)


func test_boons_repeat_in_endless_but_switches_do_not() -> void:
	var boons := {
		"dmg": {"name_key": "B", "desc_key": "B", "effect": {"type": "stat", "towers": ["bow"], "stat": "damage", "factor": 2.0}},
		"ward": {"name_key": "B", "desc_key": "B", "effect": {"type": "flag", "flag": "ward", "value": true}},
	}
	var sim := _sim("fast", {"lives": 9999, "rules": {"endless_boon_every": 1, "boon_choices": 9}}, boons)
	_win(sim)
	sim.active_boons.assign(["dmg", "ward"])
	assert_eq(sim._available_boons().size(), 0, "im normalen Spiel jede Gabe nur einmal")
	sim.continue_endless()
	assert_eq(sim._available_boons(), ["dmg"] as Array[String])
	sim.build_tower(Vector2i(1, 1), "bow")
	sim.pending_boons.assign(["dmg"])
	sim.choose_boon(0)
	sim.pending_boons.assign(["dmg"])
	sim.choose_boon(0)
	assert_eq(sim.towers[0].stats["damage"], 40.0, "zweimal gewählt wirkt doppelt")


func test_endless_run_with_real_data_is_repeatable_and_finite() -> void:
	var runs := []
	for i in 2:
		var sim := Bots.run(GameData.load_level("level_01"), GameData.load_towers(), GameData.load_enemies(), Bots.BuilderBot.new(["crossbow", "crossbow", "sling"]),
			3600.0, GameData.load_rules(), false, 5.0, GameData.load_boons(), 5, true, GameData.load_curses())
		runs.append(sim)
	assert_eq(runs[0].snapshot(), runs[1].snapshot(), "gleicher Zufallswert, gleicher Verlauf")
	assert_eq(runs[0].status, GameSim.Status.LOST, "irgendwann bricht jede Verteidigung")
	assert_gt(runs[0].endless_cleared, 2)
	assert_lt(runs[0].peak_enemies, 90)
	gut.p("Level 1 endlos: %d Wellen überstanden, höchstens %d Gegner" % [runs[0].endless_cleared, runs[0].peak_enemies])


# --- Rekord und Bonus-Sterne ----------------------------------------------

func test_endless_record_gives_bonus_stars_once_per_mark() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var p: Node = autofree(ProgressScript.new())
	p.save_path = TMP
	p.record("a", "normal", 2)
	assert_eq(p.record_endless("a", "normal", 9), 0)
	assert_eq(p.endless_record("a", "normal"), 9)
	assert_eq(p.record_endless("a", "normal", 10), 1, "Marke 10")
	assert_eq(p.record_endless("a", "normal", 10), 0, "kein Stern für denselben Rekord")
	assert_eq(p.record_endless("a", "normal", 5), 0, "schlechter als der Rekord")
	assert_eq(p.endless_record("a", "normal"), 10)
	assert_eq(p.record_endless("a", "hard", 31), 2, "Marken 20 und 30, die 10 gab es schon")
	assert_eq(p.bonus_stars("a"), 3)
	assert_eq(p.total_stars(), 2 + 3)
	assert_eq(p.best_endless("a"), 31)
	var other: Node = autofree(ProgressScript.new())
	other.save_path = TMP
	other.load_progress()
	assert_eq(other.endless_record("a", "hard"), 31)
	assert_eq(other.total_stars(), 5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_winning_then_continuing_in_the_level_scene() -> void:
	var real_save: String = Progress.save_path
	Progress.save_path = TMP
	Progress.reset()
	LevelView.level_id = "level_01"
	LevelView.run_seed = 4
	var level: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	level.set_process(false)
	level.sim.wave_index = level.sim.wave_count - 1
	level.sim.status = GameSim.Status.WON
	level.sim.finished.emit(true)
	assert_true(level.hud.is_end_visible())
	assert_eq(Progress.stars("level_01", Settings.difficulty), 3, "die Sterne sind vor dem Weiterkämpfen gutgeschrieben")
	level.hud.endless_requested.emit()
	assert_false(level.hud.is_end_visible())
	assert_true(level.sim.endless)
	assert_eq(level.hud.notice_text(), tr("HUD_ENDLESS_START"))
	# Zehn Endlos-Wellen als überstanden melden: Rekord und Bonus-Stern.
	level.sim.endless_cleared = 10
	level.sim.wave_cleared.emit(level.sim.wave_index)
	assert_eq(Progress.endless_record("level_01", Settings.difficulty), 10)
	assert_eq(Progress.bonus_stars("level_01"), 1)
	assert_string_contains(level.hud.notice_text(), "10")
	# Ein Fluch wird gemeldet.
	level.sim._add_curse()
	assert_string_contains(level.hud.notice_text(), tr("HUD_CURSE"))
	# Das Ende des Laufs ist keine Niederlage und nimmt die Sterne nicht weg.
	level.sim.lives = 0
	level.sim.status = GameSim.Status.LOST
	level.sim.finished.emit(false)
	assert_true(level.hud.is_end_visible())
	assert_eq(Progress.stars("level_01", Settings.difficulty), 3)
	LevelView.run_seed = 0
	Progress.reset()
	Progress.save_path = real_save
	Progress.load_progress()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


# --- Neue Gaben -----------------------------------------------------------

func test_piercing_bolts_hit_a_second_enemy_nearby() -> void:
	var plain := _sim("walker")
	var pierce := _sim("walker")
	_flag(pierce, [{"type": "tower_flag", "towers": ["bow"], "flag": "pierce", "value": 1.3}])
	for sim in [plain, pierce]:
		sim.build_tower(Vector2i(5, 1), "bow")
		sim.wave_index = 0
		sim.start_next_wave()
		# Nach 6 s sind beide in Reichweite, der vordere ist das Ziel.
		_run(sim, 6.0)
	assert_eq(plain.enemies[1].hp, 1000.0, "ohne die Gabe trifft der Bolzen nur den vordersten")
	assert_lt(pierce.enemies[1].hp, 1000.0)
	assert_almost_eq(1000.0 - pierce.enemies[1].hp, 1000.0 - pierce.enemies[0].hp, 20.0)


func test_aftershock_stuns_briefly_but_not_permanently() -> void:
	var plain := _sim("walker")
	var stun := _sim("walker")
	_flag(stun, [{"type": "tower_flag", "towers": ["sling"], "flag": "stun", "value": 0.5}])
	for sim in [plain, stun]:
		sim.build_tower(Vector2i(5, 1), "sling")
		sim.start_next_wave()
		_run(sim, 9.0)
	var lag: float = plain.enemies[0].pos.x - stun.enemies[0].pos.x
	# Rund 3,5 s in Reichweite, alle 0,5 s ein Treffer: ohne Schonfrist stünde der Gegner fast die ganze Zeit.
	assert_between(lag, 0.4, 1.3)


func test_wildfire_spreads_when_a_burning_enemy_dies() -> void:
	# 15 Leben: Der erste verbrennt nach 1,5 s. Das überspringende Feuer brennt mindestens 2 s und reicht für den zweiten.
	var sim := _sim("frail")
	_flag(sim, [{"type": "flag", "flag": "wildfire", "value": true}])
	sim.build_tower(Vector2i(5, 1), "fire")
	sim.wave_index = 0
	sim.start_next_wave()
	var guard := 0
	while sim.kills == 0 and guard < 3000:
		sim.step()
		guard += 1
	assert_eq(sim.kills, 1, "der erste verbrennt")
	assert_gt(sim.enemies[0].burn_left, 0.0, "der zweite, einen halben Schritt dahinter, fängt Feuer")
	_run(sim, 4.0)
	assert_eq(sim.kills, 2)


func test_frostbite_makes_slowed_enemies_take_more_damage() -> void:
	var results := []
	for with_boon in [false, true]:
		var sim := _sim("walker")
		if with_boon:
			_flag(sim, [{"type": "flag", "flag": "frostbite", "value": 1.2}])
		sim.build_tower(Vector2i(5, 1), "rune")
		sim.build_tower(Vector2i(9, 1), "bow")
		sim.start_next_wave()
		_run(sim, 6.5)
		var e := sim.enemies[0]
		e.hp = 1000.0
		e.slow_left = 5.0
		e.slow_factor = 0.5
		sim._damage(e, 100.0, "pierce")
		results.append(1000.0 - e.hp)
	assert_eq(results[0], 100.0)
	assert_almost_eq(results[1], 120.0, 0.001)


func test_brew_speeds_up_towers_only_at_the_start_of_a_wave() -> void:
	var plain := _sim("walker", {"lives": 999})
	var brew := _sim("walker", {"lives": 999})
	_flag(brew, [{"type": "flag", "flag": "brew", "value": {"seconds": 5.0, "factor": 2.0}}])
	for sim in [plain, brew]:
		sim.build_tower(Vector2i(1, 1), "bow")
		sim.start_next_wave()
		_run(sim, 2.0)
	assert_almost_eq(float(brew.towers[0].shots), plain.towers[0].shots * 2.0, 1.0)
	var late_plain := plain.towers[0].shots
	var late_brew := brew.towers[0].shots
	_run(plain, 4.0)
	_run(brew, 4.0)
	_run(plain, 1.0)
	_run(brew, 1.0)
	gut.p("Schüsse: ohne %d, mit Bräu %d" % [plain.towers[0].shots, brew.towers[0].shots])
	assert_gt(late_brew, late_plain)


func test_interest_pays_a_capped_share_after_each_wave() -> void:
	var sim := _sim("fast")
	_flag(sim, [{"type": "flag", "flag": "interest", "value": {"rate": 0.05, "cap": 50}}])
	sim.gold = 400
	sim.start_next_wave()
	_run(sim, 0.5)
	assert_eq(sim.gold, 420)
	sim.gold = 5000
	sim.start_next_wave()
	_run(sim, 1.5)
	assert_eq(sim.gold, 5050, "höchstens 50")


func test_treasure_hunters_pay_for_every_dug_tile() -> void:
	var sim := _sim()
	_flag(sim, [{"type": "flag", "flag": "dig_gold", "value": 15}])
	var before := sim.gold
	assert_eq(sim.dig(Vector2i(2, 1)), GameSim.Result.OK)
	_run(sim, 3.2)
	assert_eq(sim.gold, before - 30 + 15)


func test_fearless_miners_keep_working_next_to_enemies() -> void:
	var sim := _sim("walker", {"rules": {"ore_interval": 0.5}})
	_flag(sim, [{"type": "rule", "key": "worker_threat_radius", "factor": 0.0}])
	sim.ore = 0
	sim.place_worker(Vector2i(11, 1))
	sim.start_next_wave()
	_run(sim, 11.0)
	assert_true(sim.workers[0].active, "der Gegner steht direkt daneben")
	assert_between(sim.ore, 21, 22)


func test_guard_dogs_stop_thieves() -> void:
	var sim := _sim("thief", {"rules": {"ore_interval": 1000.0}})
	_flag(sim, [{"type": "flag", "flag": "no_steal", "value": true}])
	sim.place_worker(Vector2i(11, 1))
	sim.start_next_wave()
	_run(sim, 13.0)
	assert_eq(sim.ore, 100)
	assert_false(sim.enemies[0].has_stolen)


func test_master_smith_lowers_ore_prices() -> void:
	var sim := _sim()
	sim.build_tower(Vector2i(1, 1), "bow")
	var t := sim.towers[0]
	assert_eq(sim.upgrade_cost(t), 20)
	_flag(sim, [{"type": "flag", "flag": "ore_cost_factor", "value": 0.75}])
	assert_eq(sim.upgrade_cost(t), 15)
	sim.upgrade_tower(Vector2i(1, 1))
	assert_eq(sim.ore, 85)
	assert_eq(sim.spec_cost(t, 0), 30)
	sim.specialize(Vector2i(1, 1), 0)
	assert_eq(sim.ore, 55)


func test_last_stand_only_helps_when_lives_are_low() -> void:
	var sim := _sim("walker")
	_flag(sim, [{"type": "flag", "flag": "last_stand", "value": {"lives": 6, "factor": 1.4}}])
	sim.start_next_wave()
	sim.step()
	var e := sim.enemies[0]
	sim._damage(e, 100.0)
	assert_eq(e.hp, 900.0)
	sim.lives = 5
	sim._damage(e, 100.0)
	assert_almost_eq(e.hp, 760.0, 0.001)


func test_ward_rune_blocks_the_first_leak_of_each_wave_but_no_boss() -> void:
	var sim := _sim("fast")
	_flag(sim, [{"type": "flag", "flag": "ward", "value": true}])
	watch_signals(sim)
	sim.start_next_wave()
	_run(sim, 0.5)
	assert_eq(sim.lives, 30, "der einzige Gegner der Welle kostet nichts")
	sim.start_next_wave()
	_run(sim, 1.5)
	assert_eq(sim.lives, 29, "von zweien kostet nur der zweite")
	assert_signal_emit_count(sim, "leak_warded", 2)
	var boss := _sim("king")
	_flag(boss, [{"type": "flag", "flag": "ward", "value": true}])
	boss.start_next_wave()
	_run(boss, 0.5)
	assert_eq(boss.lives, 10, "einen Boss hält die Rune nicht auf")


func test_boons_with_a_price() -> void:
	var real := GameData.load_boons()
	var sim := GameSim.new({"start_gold": 500, "start_ore": 10, "lives": 20, "wave_pause": 2.0, "towers": ["crossbow", "forge"],
		"grid": ["E....H", "#oo*:#"], "waves": [{"reward": 0, "groups": [{"enemy": "walker", "count": 1}]}]}, GameData.load_towers(), enemies, {}, real)
	assert_eq(sim.grid.error, "")
	sim.build_tower(Vector2i(1, 1), "crossbow")
	sim.build_tower(Vector2i(2, 1), "forge")
	var damage: float = sim.towers[0].stats["damage"]
	var burn: float = sim.towers[1].stats["burn"]["dps"]
	sim.pending_boons.assign(["blood_pact"])
	sim.choose_boon(0)
	assert_almost_eq(sim.towers[0].stats["damage"], damage * 1.35, 0.001)
	assert_almost_eq(sim.towers[1].stats["burn"]["dps"], burn * 1.35, 0.001)
	assert_eq(sim.lives, 15)
	sim.lives = 3
	sim.pending_boons.assign(["blood_pact"])
	sim.choose_boon(0)
	assert_eq(sim.lives, 1, "der Preis lässt immer ein Leben übrig")
	sim.pending_boons.assign(["greed"])
	sim.choose_boon(0)
	assert_eq(sim.bounty_factor, 2.0)
	sim.start_next_wave()
	sim.step()
	assert_almost_eq(sim.enemies[0].max_hp, 1150.0, 0.001)
	var gold := sim.gold
	sim.pending_boons.assign(["all_in_ore"])
	sim.choose_boon(0)
	assert_eq(sim.ore, 90)
	assert_eq(sim.gold, gold - 100)
	sim.gold = 30
	sim.pending_boons.assign(["all_in_ore"])
	sim.choose_boon(0)
	assert_eq(sim.gold, 0, "Gold wird nie negativ")


func test_all_real_boons_and_curses_are_valid_translated_and_apply_without_error() -> void:
	var real := GameData.load_boons()
	var real_curses := GameData.load_curses()
	var real_towers := GameData.load_towers()
	assert_eq(real.size(), 28)
	assert_gte(real_curses.size(), 6)
	assert_eq(GameData.validate_boons(real, real_towers), [] as Array[String])
	assert_eq(GameData.validate_boons(real_curses, real_towers), [] as Array[String])
	var before := TranslationServer.get_locale()
	for locale in ["de", "en"]:
		TranslationServer.set_locale(locale)
		for defs in [real, real_curses]:
			for id in defs:
				assert_ne(tr(defs[id]["name_key"]), defs[id]["name_key"], "%s (%s)" % [id, locale])
				assert_ne(tr(defs[id]["desc_key"]), defs[id]["desc_key"], "%s (%s)" % [id, locale])
	TranslationServer.set_locale(before)
	# Jede Gabe und jeder Fluch lässt sich in einem echten Level anwenden, und das Spiel läuft danach weiter.
	var sim := GameData.create_sim("level_04")
	for slot in sim.grid.cells_of_type(MineGrid.Cell.BUILD).slice(0, 6):
		sim.gold = 999
		sim.build_tower(slot, sim.allowed_towers()[sim.towers.size() % 6])
	for id in real:
		sim.pending_boons.assign([id])
		assert_true(sim.choose_boon(0), id)
	for id in real_curses:
		for effect in GameSim._effects_of(real_curses[id]):
			sim._apply_effect(effect)
	sim.start_next_wave()
	_run(sim, 20.0)
	assert_gt(sim.kills, 0)
	assert_eq(sim.active_boons.size(), 28)
