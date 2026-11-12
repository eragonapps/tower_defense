extends SceneTree
## Balancing-Bericht: lässt mehrere Bots jedes Level spielen und gibt das Ergebnis aus.
## Aufruf: godot --headless -s tools/balance_report.gd

## Zugang zu den beiden sicheren Erzadern in Level 2.
const MINE_DIGS := [Vector2i(4, 3), Vector2i(4, 2), Vector2i(12, 3)]
## Verbindet den alten Seitenstollen mit dem unteren Weg und sperrt danach den kurzen Weg.
const DETOUR_DIGS := [Vector2i(14, 3), Vector2i(14, 4), Vector2i(14, 5), Vector2i(14, 6)]
const DETOUR_FILLS := [Vector2i(9, 5)]


func _initialize() -> void:
	var towers := GameData.load_towers()
	var enemies := GameData.load_enemies()
	var bots := {
		"baut nichts": func(): return Bots.NoneBot.new(),
		"nur Armbrust": func(): return Bots.BuilderBot.new(["crossbow"]),
		"nur Schleuder": func(): return Bots.BuilderBot.new(["sling"]),
		"gemischt": func(): return Bots.BuilderBot.new(["crossbow", "crossbow", "sling"]),
		"mit Mine": func(): return Bots.MinerBot.new(["crossbow", "crossbow", "sling"], MINE_DIGS),
		"Mine+Umweg": func(): return Bots.MinerBot.new(["crossbow", "crossbow", "sling"], MINE_DIGS + DETOUR_DIGS, DETOUR_FILLS),
	}
	var rules := GameData.load_rules()
	for id in GameData.LEVEL_ORDER:
		var level := GameData.load_level(id)
		print("\n== %s ==" % id)
		print("%-16s %-10s %6s %6s %7s %6s %5s %8s" % ["Bot", "Ergebnis", "Leben", "Welle", "Türme", "Gold", "Erz", "Dauer"])
		for name in bots:
			var t0 := Time.get_ticks_msec()
			var sim := Bots.run(level, towers, enemies, bots[name].call(), 1800.0, rules)
			var result := "Sieg" if sim.status == GameSim.Status.WON else ("Niederlage" if sim.status == GameSim.Status.LOST else "offen")
			print("%-16s %-10s %6d %3d/%-2d %7d %6d %5d %6.0f s  (%d ms)" % [name, result, sim.lives, sim.wave_index + 1, sim.wave_count, sim.towers.size(), sim.gold, sim.ore, sim.tick * GameSim.DT, Time.get_ticks_msec() - t0])
	quit()
