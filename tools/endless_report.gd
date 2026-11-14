extends SceneTree
## Endlos-Bericht: Ein Bot spielt nach dem Sieg weiter. Zeigt, wie weit er kommt und wie voll der Bildschirm wird.
## Aufruf: godot --headless -s tools/endless_report.gd

func _initialize() -> void:
	for id in ["level_01", "level_03", "level_05", "level_08"]:
		for rng_seed in [1, 2]:
			var t0 := Time.get_ticks_msec()
			var sim := Bots.run(GameData.load_level(id), GameData.load_towers(), GameData.load_enemies(), Bots.MinerBot.new(["crossbow", "crossbow", "sling"]), 7200.0, GameData.load_rules(), false, 5.0, GameData.load_boons(), rng_seed, true, GameData.load_curses())
			print("%s Zufall %d: Status %d, Endlos-Welle %d überstanden, %d s Spielzeit, höchstens %d Gegner, %d Gaben, Flüche %s (%d ms)" % [id, rng_seed, sim.status, sim.endless_cleared, sim.tick / 60, sim.peak_enemies, sim.active_boons.size(), sim.active_curses, Time.get_ticks_msec() - t0])
	quit()
