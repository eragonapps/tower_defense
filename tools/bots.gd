class_name Bots
extends RefCounted
## Skript-Spieler für Tests und Balancing. Sie spielen ein Level ohne Grafik durch.

## Baut nichts.
class NoneBot extends RefCounted:
	func act(_sim: GameSim) -> void:
		pass


## Baut, sobald das Gold reicht, auf den Bauplatz mit den meisten Wegzellen in Reichweite.
## pattern legt die Reihenfolge der Turmtypen fest und wird wiederholt.
class BuilderBot extends RefCounted:
	var pattern: Array = []
	var _built := 0

	func _init(tower_pattern: Array) -> void:
		pattern = tower_pattern

	func act(sim: GameSim) -> void:
		var type: String = pattern[_built % pattern.size()]
		if sim.gold < int(sim.tower_def(type)["cost"]):
			return
		var best := Vector2i(-1, -1)
		var best_score := -1
		var path := sim.grid.path_cells()
		var range_sq := float(sim.tower_def(type)["range"]) ** 2
		for cell in sim.grid.cells_of_type(MineGrid.Cell.BUILD):
			if sim.tower_at(cell) != null:
				continue
			var score := 0
			for p in path:
				if MineGrid.center(cell).distance_squared_to(MineGrid.center(p)) <= range_sq:
					score += 1
			if score > best_score:
				best_score = score
				best = cell
		if best_score >= 0 and sim.build_tower(best, type) == GameSim.BuildResult.OK:
			_built += 1


## Spielt ein Level bis zum Ende. Der Bot handelt einmal pro Spielsekunde.
static func run(level: Dictionary, towers: Dictionary, enemies: Dictionary, bot: Object, max_seconds := 1800.0) -> GameSim:
	var sim := GameSim.new(level, towers, enemies)
	var max_ticks := int(max_seconds * GameSim.TICK_RATE)
	while sim.status == GameSim.Status.RUNNING and sim.tick < max_ticks:
		if sim.tick % GameSim.TICK_RATE == 0:
			bot.act(sim)
			if sim.can_start_wave():
				sim.start_next_wave()
		sim.step()
	return sim
