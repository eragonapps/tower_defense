extends SceneTree
## Balancing-Bericht: lässt mehrere Bots jedes Level spielen und gibt das Ergebnis aus.
## Aufruf: godot --headless -s tools/balance_report.gd

## Felder, die der Minen-Bot je Level gräbt, um die sicheren Erzadern zu erreichen.
const MINE_DIGS := {
	"level_02": [Vector2i(4, 3), Vector2i(4, 2), Vector2i(12, 3)],
	"level_03": [Vector2i(3, 3), Vector2i(10, 4), Vector2i(14, 6)],
	"level_04": [Vector2i(8, 5), Vector2i(12, 2), Vector2i(5, 2)],
}
const ALL_TOWERS := ["crossbow", "forge", "sling", "crossbow", "bomb", "runestone", "shieldwall"]


func _initialize() -> void:
	var towers := GameData.load_towers()
	var enemies := GameData.load_enemies()
	var rules := GameData.load_rules()
	for id in GameData.LEVEL_ORDER:
		var level := GameData.load_level(id)
		var allowed: Array = level["towers"]
		var digs: Array = MINE_DIGS.get(id, [])
		var mixed: Array = ALL_TOWERS.filter(func(t): return t in allowed)
		var bots := {
			"baut nichts": func(): return Bots.NoneBot.new(),
			"nur Armbrust": func(): return Bots.BuilderBot.new(["crossbow"]),
			"nur Schleuder": func(): return Bots.BuilderBot.new(["sling"]),
			"Armbr.+Schl.": func(): return Bots.BuilderBot.new(["crossbow", "crossbow", "sling"]),
			"alle Türme": func(): return Bots.BuilderBot.new(mixed),
			"A+S mit Mine": func(): return Bots.MinerBot.new(["crossbow", "crossbow", "sling"], digs),
			"alle mit Mine": func(): return Bots.MinerBot.new(mixed, digs),
		}
		print("\n== %s ==" % id)
		print("%-16s %-10s %6s %6s %7s %6s %5s %8s" % ["Bot", "Ergebnis", "Leben", "Welle", "Türme", "Gold", "Erz", "Dauer"])
		for name in bots:
			var t0 := Time.get_ticks_msec()
			var sim := Bots.run(level, towers, enemies, bots[name].call(), 1800.0, rules)
			var result := "Sieg" if sim.status == GameSim.Status.WON else ("Niederlage" if sim.status == GameSim.Status.LOST else "offen")
			print("%-16s %-10s %6d %3d/%-2d %7d %6d %5d %6.0f s  (%d ms)" % [name, result, sim.lives, sim.wave_index + 1, sim.wave_count, sim.towers.size(), sim.gold, sim.ore, sim.tick * GameSim.DT, Time.get_ticks_msec() - t0])
	quit()
