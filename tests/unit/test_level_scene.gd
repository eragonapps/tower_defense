extends GutTest
## Das Level als ganze Szene: Darstellung, Oberfläche und Simulation greifen ineinander.
## Läuft ohne Bildschirm. Geprüft wird das Verhalten, nicht das Aussehen.

var level: LevelView


func before_each() -> void:
	LevelView.level_id = "level_01"
	level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	level.set_process(false)


func _slot(i: int) -> Vector2i:
	return level.sim.grid.cells_of_type(MineGrid.Cell.BUILD)[i]


func test_scene_starts_with_level_data() -> void:
	assert_not_null(level.sim)
	assert_eq(level.sim.gold, 110)
	assert_eq(level.sim.lives, 20)
	assert_false(level.hud.is_context_visible())
	assert_false(level.hud.is_end_visible())


func test_selecting_a_slot_opens_build_menu_and_building_places_a_tower() -> void:
	level.select_cell(_slot(0))
	assert_true(level.hud.is_context_visible())
	level.hud.action_requested.emit("build:crossbow")
	assert_eq(level.sim.towers.size(), 1)
	assert_eq(level.sim.gold, 60)
	assert_eq(level._tower_views.size(), 1)
	assert_true(level._range_marker.visible, "nach dem Bau ist der Turm ausgewählt")
	level.hud.action_requested.emit("sell")
	assert_eq(level.sim.towers.size(), 0)
	assert_eq(level._tower_views.size(), 0)
	assert_eq(level.sim.gold, 95)


func test_selecting_anything_else_closes_the_menu() -> void:
	level.select_cell(_slot(0))
	level.select_cell(level.sim.grid.heart)
	assert_false(level.hud.is_context_visible())
	level.select_cell(_slot(0))
	level.select_cell(Vector2i(1, 2))
	assert_false(level.hud.is_context_visible(), "in Level 1 ist Graben abgeschaltet, Fels hat kein Menü")
	level.select_cell(_slot(0))
	level.select_cell(Vector2i(0, 0))
	assert_false(level.hud.is_context_visible())
	assert_eq(level.selected, LevelView.NO_CELL)
	level.hud.action_requested.emit("build:crossbow")
	assert_eq(level.sim.towers.size(), 0, "ohne Auswahl wird nichts gebaut")


func test_building_without_gold_does_nothing() -> void:
	level.sim.gold = 10
	level.select_cell(_slot(0))
	level.hud.action_requested.emit("build:crossbow")
	assert_eq(level.sim.towers.size(), 0)
	assert_eq(level.sim.gold, 10)


func test_views_follow_the_simulation() -> void:
	level.select_cell(_slot(0))
	level.hud.action_requested.emit("build:crossbow")
	level.hud.wave_requested.emit()
	assert_eq(level.sim.wave_index, 0)
	for i in 40:
		level.advance(0.1)
		assert_eq(level._enemy_views.size(), level.sim.enemies.size())
		assert_eq(level._projectile_views.size(), level.sim.projectiles.size())
	assert_gt(level.sim.enemies.size(), 0)
	var e: GameSim.Enemy = level.sim.enemies[0]
	var view: Node3D = level._enemy_views[e.id]
	assert_almost_eq(view.position.x, e.pos.x * LevelView.CELL, 0.2)
	assert_almost_eq(view.position.z, e.pos.y * LevelView.CELL, 0.2)


func test_speed_button_cycles_and_pause_toggles() -> void:
	assert_eq(level.speed_index, 0)
	level.hud.speed_requested.emit()
	level.hud.speed_requested.emit()
	assert_eq(LevelView.SPEEDS[level.speed_index], 3.0)
	level.hud.speed_requested.emit()
	assert_eq(level.speed_index, 0)
	level.hud.pause_requested.emit()
	assert_true(level.paused)
	level.hud.pause_requested.emit()
	assert_false(level.paused)


func test_app_in_background_pauses_the_game() -> void:
	level.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(level.paused)


func test_whole_level_can_be_played_to_defeat_and_shows_end_screen() -> void:
	level.hud.wave_requested.emit()
	var guard := 0
	while level.sim.status == GameSim.Status.RUNNING and guard < 20000:
		level.advance(0.15)
		guard += 1
	assert_eq(level.sim.status, GameSim.Status.LOST)
	assert_true(level.hud.is_end_visible())
	assert_false(level.hud.is_context_visible())


func test_whole_level_can_be_won_through_the_interface() -> void:
	var bot := Bots.BuilderBot.new(["crossbow", "crossbow", "sling"])
	level.hud.wave_requested.emit()
	var guard := 0
	var acted_at := -1
	while level.sim.status == GameSim.Status.RUNNING and guard < 40000:
		var second := level.sim.tick / GameSim.TICK_RATE
		if second != acted_at:
			acted_at = second
			bot.act(level.sim)
		level.advance(0.15)
		guard += 1
	assert_eq(level.sim.status, GameSim.Status.WON)
	assert_true(level.hud.is_end_visible())
	assert_eq(level._tower_views.size(), level.sim.towers.size())
	assert_eq(level._enemy_views.size(), 0)


func test_tapping_the_top_of_any_cell_picks_that_cell() -> void:
	await wait_process_frames(2)
	var g := level.sim.grid
	var checked := 0
	for y in range(1, g.height - 1):
		for x in range(1, g.width - 1):
			var cell := Vector2i(x, y)
			var top := LevelView.to_world(MineGrid.center(cell), level.cell_height(cell))
			var screen := level.rig.camera.unproject_position(top)
			assert_eq(level.pick_cell(screen), cell, "Zelle %s (Typ %d)" % [cell, g.get_cell(cell)])
			checked += 1
	assert_gt(checked, 100)


# --- Level 2: Mine ---------------------------------------------------------

func _level_02() -> LevelView:
	LevelView.level_id = "level_02"
	var l: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l.set_process(false)
	return l


func test_mine_actions_work_through_the_menu() -> void:
	var l := _level_02()
	var rock := Vector2i(4, 3)
	var vein := Vector2i(6, 5)
	# Fels graben.
	l.select_cell(rock)
	assert_true(l.hud.is_context_visible())
	l.hud.action_requested.emit("dig")
	assert_eq(l.sim.dig_jobs.size(), 1)
	assert_eq(l._dig_views.size(), 1)
	l.advance(3.2)
	for i in 30:
		l.advance(0.15)
	assert_true(l.sim.grid.is_walkable(rock))
	assert_eq(l._dig_views.size(), 0)
	assert_eq(l.selected, rock, "die Auswahl bleibt, das Menü zeigt jetzt Zuschütten")
	# Wieder zuschütten.
	l.hud.action_requested.emit("fill")
	assert_eq(l.sim.grid.get_cell(rock), MineGrid.Cell.ROCK)
	# Arbeiter an die Ader am Hauptweg.
	l.select_cell(vein)
	l.hud.action_requested.emit("worker")
	assert_eq(l.sim.workers.size(), 1)
	assert_eq(l._worker_views.size(), 1)
	for i in 80:
		l.advance(0.15)
	assert_gt(l.sim.ore, 5)
	# Turm bauen und ausbauen.
	var slot: Vector2i = l.sim.grid.cells_of_type(MineGrid.Cell.BUILD)[0]
	l.sim.gold = 500
	l.sim.ore = 100
	l.select_cell(slot)
	l.hud.action_requested.emit("build:crossbow")
	l.hud.action_requested.emit("upgrade")
	l.hud.action_requested.emit("upgrade")
	l.hud.action_requested.emit("upgrade")
	assert_eq(l.sim.towers[0].level, 3)
	assert_eq(l.sim.ore, 100 - 15 - 30)


func test_menu_updates_when_gold_arrives() -> void:
	var l := _level_02()
	l.sim.gold = 0
	l.select_cell(Vector2i(4, 3))
	var before := l._menu_signature
	assert_string_contains(before, tr("REASON_GOLD"))
	l.sim.gold = 100
	l._refresh_menu()
	assert_ne(l._menu_signature, before)
	assert_false(l._menu_for(Vector2i(4, 3))["buttons"][0]["disabled"])


func test_blocking_fill_is_explained_and_disabled() -> void:
	var l := _level_02()
	var menu := l._menu_for(Vector2i(3, 4))
	assert_true(menu["buttons"][0]["disabled"])
	assert_eq(menu["info"], tr("REASON_BLOCKS_PATH"))
	var far_rock := l._menu_for(Vector2i(2, 1))
	assert_true(far_rock["buttons"][0]["disabled"])
	assert_eq(far_rock["info"], tr("REASON_NOT_CONNECTED"))


func test_level_two_can_be_won_through_the_interface() -> void:
	var l := _level_02()
	var bot := Bots.MinerBot.new(["crossbow", "crossbow", "sling"], [Vector2i(4, 3), Vector2i(4, 2), Vector2i(12, 3)])
	var guard := 0
	var acted_at := -1
	while l.sim.status == GameSim.Status.RUNNING and guard < 60000:
		var second := l.sim.tick / GameSim.TICK_RATE
		if second != acted_at:
			acted_at = second
			bot.act(l.sim)
			if l.sim.wave_index < 0 and second >= 5:
				l.hud.wave_requested.emit()
		l.advance(0.15)
		guard += 1
	assert_eq(l.sim.status, GameSim.Status.WON)
	assert_eq(l._worker_views.size(), 3)
	assert_true(l.hud.is_end_visible())
