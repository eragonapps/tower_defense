extends SceneTree
## Balancing-Bericht: lässt mehrere Bots jedes Level spielen und gibt das Ergebnis aus.
## Aufruf: godot --headless -s tools/balance_report.gd

func _initialize() -> void:
	var towers := GameData.load_towers()
	var enemies := GameData.load_enemies()
	var bots := {
		"baut nichts": func(): return Bots.NoneBot.new(),
		"nur Armbrust": func(): return Bots.BuilderBot.new(["crossbow"]),
		"nur Schleuder": func(): return Bots.BuilderBot.new(["sling"]),
		"gemischt": func(): return Bots.BuilderBot.new(["crossbow", "crossbow", "sling"]),
	}
	for id in GameData.LEVEL_ORDER:
		var level := GameData.load_level(id)
		print("\n== %s ==" % id)
		print("%-16s %-10s %6s %6s %7s %6s %8s" % ["Bot", "Ergebnis", "Leben", "Welle", "Türme", "Gold", "Dauer"])
		for name in bots:
			var t0 := Time.get_ticks_msec()
			var sim := Bots.run(level, towers, enemies, bots[name].call())
			var result := "Sieg" if sim.status == GameSim.Status.WON else ("Niederlage" if sim.status == GameSim.Status.LOST else "offen")
			print("%-16s %-10s %6d %3d/%-2d %7d %6d %6.0f s  (%d ms)" % [name, result, sim.lives, sim.wave_index + 1, sim.wave_count, sim.towers.size(), sim.gold, sim.tick * GameSim.DT, Time.get_ticks_msec() - t0])
	quit()
