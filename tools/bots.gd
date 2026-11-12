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
		if best_score >= 0 and sim.build_tower(best, type) == GameSim.Result.OK:
			_built += 1


## Wie BuilderBot, nutzt aber auch die Mine: gräbt eine feste Liste von Feldern, setzt Arbeiter
## an jede erreichbare Erzader und baut Türme aus, sobald das Erz reicht.
class MinerBot extends RefCounted:
	var builder: BuilderBot
	var digs: Array = []
	var fills: Array = []
	var use_upgrades := true
	## So viele Türme stehen vor der ersten Welle. Mit jeder Welle kommt einer dazu, bevor Gold in die Mine fließt.
	var towers_first := 4

	func _init(tower_pattern: Array, dig_cells: Array = [], fill_cells: Array = []) -> void:
		builder = BuilderBot.new(tower_pattern)
		digs = dig_cells.duplicate()
		fills = fill_cells.duplicate()

	func act(sim: GameSim) -> void:
		# Erst eine Grundverteidigung, dann der Zugang zum Erz, dann Arbeiter, dann weitere Türme.
		if sim.towers.size() < towers_first + maxi(sim.wave_index, 0) * 2:
			builder.act(sim)
			return
		if not digs.is_empty():
			var r := sim.dig(digs[0])
			if r == GameSim.Result.OK or r == GameSim.Result.NOT_ALLOWED:
				digs.pop_front()
			elif r == GameSim.Result.NOT_ENOUGH_GOLD:
				return
		elif not fills.is_empty() and sim.dig_jobs.is_empty():
			var r := sim.fill(fills[0])
			if r == GameSim.Result.OK or r == GameSim.Result.NOT_ALLOWED:
				fills.pop_front()
		for vein in sim.grid.cells_of_type(MineGrid.Cell.ORE):
			var r := sim.place_worker(vein)
			if r == GameSim.Result.NOT_ENOUGH_GOLD:
				return
		if use_upgrades:
			for t in sim.towers:
				if sim.upgrade_tower(t.cell) == GameSim.Result.OK:
					break
		builder.act(sim)


## Spielt ein Level bis zum Ende. Der Bot handelt einmal pro Spielsekunde.
## Er startet die erste Welle nach prepare_seconds und nutzt danach die normalen Pausen.
## Mit rush startet er jede Welle sofort, das ist deutlich härter als ein Mensch spielt.
static func run(level: Dictionary, towers: Dictionary, enemies: Dictionary, bot: Object, max_seconds := 1800.0, rules := {}, rush := false, prepare_seconds := 5.0) -> GameSim:
	var sim := GameSim.new(level, towers, enemies, rules)
	var max_ticks := int(max_seconds * GameSim.TICK_RATE)
	while sim.status == GameSim.Status.RUNNING and sim.tick < max_ticks:
		if sim.tick % GameSim.TICK_RATE == 0:
			bot.act(sim)
			if sim.can_start_wave() and (rush or (sim.wave_index < 0 and sim.tick >= prepare_seconds * GameSim.TICK_RATE)):
				sim.start_next_wave()
		sim.step()
	return sim
