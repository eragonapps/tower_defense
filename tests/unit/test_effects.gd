extends GutTest
## Zusatzwirkungen: Verlangsamung, Brennen, Türme ohne Geschoss, heilende Gegner.

const GRID := ["E..............H", "#o:::o:::o:::::#"]

var towers := {
	"rune": {"name_key": "T", "kind": "aura", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"slow": {"factor": 0.5, "duration": 1.5}},
	"rune_strong": {"name_key": "T", "kind": "aura", "cost": 50, "range": 2.0, "cooldown": 1.0, "damage": 0, "splash": 0.0, "projectile_speed": 0.0, "color": "#fff",
		"slow": {"factor": 0.25, "duration": 0.5}},
	"fire": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 10.0, "damage": 5, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff",
		"burn": {"dps": 10, "duration": 3.0}},
	"fire_fast": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 0.5, "damage": 0, "splash": 0.0, "projectile_speed": 50.0, "color": "#fff",
		"burn": {"dps": 10, "duration": 3.0}},
	"fire_area": {"name_key": "T", "cost": 50, "range": 2.0, "cooldown": 10.0, "damage": 0, "splash": 1.0, "projectile_speed": 50.0, "color": "#fff",
		"burn": {"dps": 4, "duration": 1.0}},
}
var enemies := {
	"tank": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 9, "lives": 1, "color": "#fff", "size": 1.0},
	"weak": {"name_key": "E", "hp": 20, "speed": 1.0, "bounty": 9, "lives": 1, "color": "#fff", "size": 1.0},
	"healer": {"name_key": "E", "hp": 1000, "speed": 1.0, "bounty": 9, "lives": 1, "color": "#fff", "size": 1.0,
		"heal": {"amount": 30, "interval": 1.0, "radius": 1.2}},
}


func _sim(groups: Array, build: Dictionary) -> GameSim:
	var sim := GameSim.new({
		"start_gold": 1000, "lives": 50, "wave_pause": 3.0, "towers": towers.keys(), "grid": GRID,
		"waves": [{"reward": 0, "groups": groups}],
	}, towers, enemies)
	for cell in build:
		assert_eq(sim.build_tower(cell, build[cell]), GameSim.Result.OK)
	sim.start_next_wave()
	return sim


func _run(sim: GameSim, seconds: float) -> void:
	for i in int(round(seconds * GameSim.TICK_RATE)):
		sim.step()


# --- Verlangsamung --------------------------------------------------------

func test_aura_slows_enemies_in_range_only() -> void:
	var sim := _sim([{"enemy": "tank", "count": 2, "interval": 3.0}], {Vector2i(5, 1): "rune"})
	watch_signals(sim)
	_run(sim, 3.5)
	# Reichweite 2 um (5.5, 1.5): der erste Gegner ist bei x≈4 drin, der zweite bei x≈1 nicht.
	assert_eq(sim.enemies[0].slow_factor, 0.5)
	assert_gt(sim.enemies[0].slow_left, 0.0)
	assert_eq(sim.enemies[1].slow_left, 0.0)
	assert_signal_emitted(sim, "aura_pulsed")
	assert_eq(sim.projectiles.size(), 0, "ein Runenstein schießt nicht")


func test_slowed_enemy_really_walks_slower() -> void:
	var free := _sim([{"enemy": "tank", "count": 1}], {})
	var slowed := _sim([{"enemy": "tank", "count": 1}], {Vector2i(5, 1): "rune"})
	_run(free, 9.0)
	_run(slowed, 9.0)
	# Im Wirkbereich von x≈3.77 bis x≈7.23 (3,46 Längen) braucht der Gegner bei halbem Tempo doppelt so lang.
	assert_almost_eq(free.enemies[0].pos.x, 9.5, 0.05)
	assert_lt(slowed.enemies[0].pos.x, 7.5)
	assert_gt(slowed.enemies[0].pos.x, 5.5)


func test_slow_ends_after_its_duration() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}], {Vector2i(1, 1): "rune"})
	# Reichweite 2 um (1.5, 1.5): der Gegner verlässt sie bei x≈3.23.
	var e: GameSim.Enemy
	var left_range_at := -1.0
	var slow_ended_at := -1.0
	for i in 1200:
		sim.step()
		e = sim.enemies[0]
		var t := sim.tick * GameSim.DT
		if left_range_at < 0.0 and e.pos.distance_to(Vector2(1.5, 1.5)) > 2.0:
			left_range_at = t
		if left_range_at >= 0.0 and slow_ended_at < 0.0 and e.slow_left <= 0.0:
			slow_ended_at = t
			break
	assert_gt(left_range_at, 0.0)
	# Der letzte Puls kam höchstens 1 s vor dem Verlassen und wirkt 1,5 s.
	assert_between(slow_ended_at - left_range_at, 0.4, 1.55)
	assert_eq(e.slow_factor, 1.0)


func test_slows_do_not_stack_beyond_the_strongest() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}], {Vector2i(1, 1): "rune", Vector2i(5, 1): "rune_strong", Vector2i(9, 1): "rune"})
	var slowest := 1.0
	for i in 900:
		sim.step()
		var e := sim.enemies[0]
		if e.slow_left > 0.0:
			slowest = minf(slowest, e.slow_factor)
		assert_gte(e.slow_factor, 0.25, "nie langsamer als die stärkste einzelne Wirkung")
	assert_eq(slowest, 0.25)
	# Zwei gleiche Runensteine nebeneinander wirken wie einer.
	var one := _sim([{"enemy": "tank", "count": 1}], {Vector2i(5, 1): "rune"})
	var grid2 := ["E..............H", "#::::oo::::::::#"]
	var two := GameSim.new({"start_gold": 1000, "lives": 50, "wave_pause": 3.0, "towers": ["rune"], "grid": grid2,
		"waves": [{"reward": 0, "groups": [{"enemy": "tank", "count": 1}]}]}, towers, enemies)
	two.build_tower(Vector2i(5, 1), "rune")
	two.build_tower(Vector2i(6, 1), "rune")
	two.start_next_wave()
	_run(one, 4.5)
	_run(two, 4.5)
	assert_eq(two.enemies[0].slow_factor, 0.5)
	assert_almost_eq(two.enemies[0].pos.x, one.enemies[0].pos.x, 0.01, "bis hierher wirkt nur der erste Stein")


# --- Brennen --------------------------------------------------------------

func test_burn_deals_exactly_its_total_damage() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}], {Vector2i(5, 1): "fire"})
	_run(sim, 12.0)
	var e := sim.enemies[0]
	assert_eq(sim.towers[0].shots, 1)
	assert_eq(e.burn_left, 0.0)
	# 5 Treffer + 10 pro Sekunde über 3 Sekunden.
	assert_almost_eq(e.hp, 1000.0 - 5.0 - 30.0, 0.001)


func test_burn_refreshes_instead_of_stacking() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}], {Vector2i(5, 1): "fire_fast"})
	_run(sim, 12.0)
	var e := sim.enemies[0]
	assert_gt(sim.towers[0].shots, 5)
	# Der Gegner ist 3,46 s in Reichweite und brennt danach noch bis zu 3 s weiter:
	# höchstens 6,5 s zu 10 pro Sekunde, egal wie oft er getroffen wurde.
	var lost := 1000.0 - e.hp
	assert_between(lost, 55.0, 65.5)


func test_burn_kills_and_pays_bounty_once() -> void:
	var sim := _sim([{"enemy": "weak", "count": 1}], {Vector2i(5, 1): "fire"})
	watch_signals(sim)
	_run(sim, 12.0)
	assert_eq(sim.kills, 1)
	assert_eq(sim.gold, 1000 - 50 + 9)
	assert_signal_emit_count(sim, "enemy_removed", 1)
	assert_eq(sim.status, GameSim.Status.WON)


func test_fire_tower_prefers_enemies_that_are_not_burning() -> void:
	var sim := _sim([{"enemy": "tank", "count": 3, "interval": 0.4}], {Vector2i(5, 1): "fire_fast"})
	_run(sim, 5.6)
	var burning := 0
	for e in sim.enemies:
		if e.burn_left > 0.0:
			burning += 1
	assert_eq(burning, 3, "alle drei brennen, statt dass nur der vorderste immer wieder getroffen wird")


func test_area_burn_ignites_everything_in_the_blast() -> void:
	var sim := _sim([{"enemy": "tank", "count": 2, "interval": 0.5}, {"enemy": "tank", "count": 1, "delay": 4.0}], {Vector2i(9, 1): "fire_area"})
	_run(sim, 13.0)
	assert_almost_eq(sim.enemies[0].hp, 996.0, 0.001)
	assert_almost_eq(sim.enemies[1].hp, 996.0, 0.001)
	assert_eq(sim.enemies[2].hp, 1000.0)


# --- Heilende Gegner ------------------------------------------------------

func test_healer_restores_nearby_allies_but_not_itself() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}, {"enemy": "healer", "count": 1, "delay": 0.5}, {"enemy": "tank", "count": 1, "delay": 4.0}], {})
	_run(sim, 4.5)
	var near := sim.enemies[0]
	var healer := sim.enemies[1]
	var far := sim.enemies[2]
	near.hp = 500.0
	healer.hp = 500.0
	far.hp = 500.0
	watch_signals(sim)
	_run(sim, 1.1)
	assert_eq(near.hp, 530.0)
	assert_eq(healer.hp, 500.0, "heilt sich nicht selbst")
	assert_eq(far.hp, 500.0, "zu weit weg")
	assert_signal_emitted(sim, "enemies_healed")


func test_heal_never_exceeds_max_hp() -> void:
	var sim := _sim([{"enemy": "tank", "count": 1}, {"enemy": "healer", "count": 1, "delay": 0.5}], {})
	_run(sim, 1.0)
	sim.enemies[0].hp = 990.0
	_run(sim, 3.0)
	assert_eq(sim.enemies[0].hp, 1000.0)
