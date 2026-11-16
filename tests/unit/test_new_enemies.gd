extends GutTest
## Die neuen Gegner: fliegende Schwärme, Spinnen über der Sperre, Pulverfass-Kobolde, Ratten als Diebe.

const GRID := ["E..............H", "#o:::o:::o:*:::#"]

var towers := {
	"bow": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "pierce", "anti_air": true},
	"sling": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 1.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "blunt"},
	"cannon": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 10, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff", "damage_type": "blunt"},
	"rune": {"name_key": "T", "kind": "aura", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 5, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"slow": {"factor": 0.5, "duration": 1.5}, "anti_air": true},
	"fire_aura": {"name_key": "T", "kind": "aura", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 5, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff"},
	"wall": {"name_key": "T", "kind": "block", "cost": 50, "range": 1.2, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"capacity": 3, "hold_time": 4.0},
}


func _sim(enemy: String, build: Dictionary, pool := {}) -> GameSim:
	var enemies := GameData.load_enemies()
	enemies.merge(pool, true)
	var def: Dictionary = enemies[enemy].duplicate(true)
	def["hp"] = 100000
	def["speed"] = 1.0
	def.erase("summon")
	enemies["test"] = def
	var sim := GameSim.new({"start_gold": 1000, "start_ore": 30, "lives": 99, "wave_pause": 2.0, "towers": towers.keys(), "grid": GRID,
		"rules": {"ore_only_during_waves": false, "ore_interval": 1000.0},
		"waves": [{"reward": 0, "groups": [{"enemy": "test", "count": 1}]}]}, towers, enemies)
	for cell in build:
		assert_eq(sim.build_tower(cell, build[cell]), GameSim.Result.OK)
	sim.start_next_wave()
	return sim


func _run(sim: GameSim, seconds: float) -> void:
	for i in int(round(seconds * GameSim.TICK_RATE)):
		sim.step()


func _lost(sim: GameSim) -> float:
	return sim.enemies[0].max_hp - sim.enemies[0].hp


func test_only_anti_air_towers_hit_flying_bats() -> void:
	var results := {}
	for tower in ["bow", "sling", "cannon", "rune", "fire_aura"]:
		var sim := _sim("cave_bats", {Vector2i(5, 1): tower})
		_run(sim, 9.0)
		results[tower] = _lost(sim)
	assert_gt(results["bow"], 0.0, "Armbrust trifft")
	assert_gt(results["rune"], 0.0, "Runenstein trifft")
	assert_eq(results["sling"], 0.0, "Flächenschaden erreicht keine Flieger")
	assert_eq(results["cannon"], 0.0, "andere Türme zielen nicht auf Flieger")
	assert_eq(results["fire_aura"], 0.0)


func test_bats_cannot_be_held_and_spiders_only_briefly() -> void:
	var bats := _sim("cave_bats", {Vector2i(5, 1): "wall"})
	var spider := _sim("shadow_spider", {Vector2i(5, 1): "wall"})
	var plain := _sim("goblin", {Vector2i(5, 1): "wall"})
	var held := {}
	for pair in [["bats", bats], ["spider", spider], ["plain", plain]]:
		var sim: GameSim = pair[1]
		var longest := 0.0
		for i in 600:
			sim.step()
			longest = maxf(longest, sim.enemies[0].hold_left)
		held[pair[0]] = longest
	assert_eq(held["bats"], 0.0)
	assert_almost_eq(held["plain"], 4.0, 0.05)
	assert_almost_eq(held["spider"], 1.0, 0.05, "ein Viertel der Haltezeit")


func test_kobold_explodes_on_death_and_hurts_nearby_enemies() -> void:
	var enemies := GameData.load_enemies()
	var level := {"start_gold": 1000, "lives": 99, "wave_pause": 2.0, "towers": ["bow"], "grid": GRID,
		"waves": [{"reward": 0, "groups": [{"enemy": "kobold_sapper", "count": 1}, {"enemy": "draugr", "count": 2, "interval": 0.2, "delay": 0.1}]}]}
	var sim := GameSim.new(level, towers, enemies)
	watch_signals(sim)
	sim.start_next_wave()
	_run(sim, 1.0)
	var kobold := sim.enemies[0]
	var others := [sim.enemies[1], sim.enemies[2]]
	kobold.pos = Vector2(5.5, 1.5)
	others[0].pos = Vector2(6.0, 1.5)
	others[1].pos = Vector2(9.0, 1.5)
	sim._damage(kobold, 9999.0)
	assert_signal_emitted(sim, "enemy_exploded")
	var blast: Dictionary = enemies["kobold_sapper"]["death_blast"]
	assert_almost_eq(others[0].max_hp - others[0].hp, float(blast["damage"]), 0.01, "nah dran: voller Schaden")
	assert_eq(others[1].hp, others[1].max_hp, "zu weit weg")
	# Wer ins Herz läuft, explodiert nicht.
	var leak := GameSim.new(level, towers, enemies)
	watch_signals(leak)
	leak.start_next_wave()
	_run(leak, 30.0)
	assert_signal_not_emitted(leak, "enemy_exploded")


func test_rats_steal_ore_and_kobolds_no_longer_do() -> void:
	var enemies := GameData.load_enemies()
	assert_true(enemies["rat_swarm"].has("steal"))
	assert_false(enemies["kobold_sapper"].has("steal"))
	var sim := _sim("rat_swarm", {})
	sim.place_worker(Vector2i(11, 1))
	_run(sim, 13.0)
	assert_lt(sim.ore, 30)


func test_draugr_resist_bolts_and_golems_shrug_off_slow() -> void:
	var enemies := GameData.load_enemies()
	assert_lt(float(enemies["draugr"]["resist"]["pierce"]), 1.0)
	assert_gt(float(enemies["stone_golem"].get("slow_resist", 0.0)), 0.7)
	var golem := _sim("stone_golem", {Vector2i(5, 1): "rune"})
	_run(golem, 5.0)
	assert_gt(golem.enemies[0].slow_factor, 0.9, "fast immun gegen Verlangsamung")


func test_endless_bosses_take_turns() -> void:
	var sim := GameData.create_sim("level_01")
	sim.wave_index = sim.wave_count - 1
	sim.status = GameSim.Status.WON
	sim.continue_endless()
	var bosses := []
	for w in [5, 10, 15, 20]:
		sim.endless_wave = w
		bosses.append(sim._boss_type())
	assert_eq(bosses, ["deep_worm", "fallen_king", "deep_worm", "fallen_king"])


func test_bat_placeholder_has_animations() -> void:
	var bats := Models.enemy("cave_bats")
	var ap := Models.player(bats)
	assert_true(ap.has_animation("Walk"))
	assert_true(ap.has_animation("Death"))
	assert_almost_eq(bats.position.y, 1.3, 0.01, "fliegt über dem Boden")
	bats.free()
