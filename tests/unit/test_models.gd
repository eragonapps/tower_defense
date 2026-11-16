extends GutTest
## Die eigenen Modelle: Zuordnung zu Türmen und Gegnern, Zusammenfassen der Teile, Darstellung im Level.


func test_every_tower_level_and_specialization_has_a_model() -> void:
	var towers := GameData.load_towers()
	for type in towers:
		assert_true(Models.TOWERS.has(type), "Turm %s hat keinen Eintrag in Models.TOWERS" % type)
		var def: Dictionary = Models.TOWERS[type]
		assert_eq(def["levels"].size(), 3, type)
		for file in def["levels"]:
			assert_true(Models.has(Models.TOWERS_DIR + file), "%s: %s fehlt" % [type, file])
		for spec in towers[type].get("specs", []):
			assert_true(def["specs"].has(spec["id"]), "%s: Spezialisierung %s ohne Modell" % [type, spec["id"]])
			assert_true(Models.has(Models.TOWERS_DIR + def["specs"][spec["id"]]), "%s: Modell fehlt" % spec["id"])
		for file in def.get("shot", {}).values():
			assert_not_null(Models.prop(file), "%s: Geschoss %s fehlt" % [type, file])
		for key in ["fx", "fx_hit", "muzzle_fx"]:
			if def.has(key):
				assert_not_null(Models.prop(def[key]), "%s: Effekt %s fehlt" % [type, def[key]])


func test_every_enemy_has_a_model_with_walk_and_death() -> void:
	for type in GameData.load_enemies():
		assert_true(Models.ENEMIES.has(type), "Gegner %s hat kein Modell" % type)
		var node := Models.enemy(type)
		var ap := Models.player(node)
		assert_not_null(ap, type)
		if ap != null:
			assert_true(ap.has_animation(Models.enemy_anim(type, "walk")), "%s: Laufen fehlt" % type)
			assert_true(ap.has_animation(Models.enemy_anim(type, "death")), "%s: Sterben fehlt" % type)
		assert_gt(Models.height(node), 0.2, "%s ist zu klein" % type)
		assert_lt(Models.height(node), 3.5, "%s ist zu groß" % type)
		node.free()


func test_baking_merges_parts_but_keeps_moving_pivots() -> void:
	var raw := Models.instance(Models.TOWERS_DIR + "cannon_tower_rapid")
	var raw_meshes := raw.find_children("*", "MeshInstance3D", true, false).size()
	raw.free()
	var tower := Models.tower("sling", 3, "hail")
	var meshes := tower.find_children("*", "MeshInstance3D", true, false).size()
	assert_gt(raw_meshes, 100)
	assert_lt(meshes, 8, "aus %d Teilen werden wenige Netze" % raw_meshes)
	for pivot in ["Turret", "Barrel", "Spin", "Muzzle"]:
		assert_not_null(tower.find_child(pivot, true, false), pivot)
	assert_not_null(tower.get_meta("turret"))
	assert_not_null(tower.get_meta("spin"))
	assert_gt(float(tower.get_meta("muzzle_height")), 0.8)
	tower.free()


func test_baked_enemy_animation_still_moves_body_parts() -> void:
	var node := Models.enemy("goblin_shaman")
	add_child_autofree(node)
	var ap := Models.player(node)
	assert_true(ap.has_animation("Cast"))
	var leg := node.find_child("Leg_L", true, false) as Node3D
	assert_not_null(leg)
	ap.play("Walk")
	ap.seek(0.0, true)
	var start := leg.transform
	ap.seek(0.25, true)
	assert_ne(leg.transform, start, "die Laufanimation bewegt das Bein")


func test_turret_aims_at_the_target() -> void:
	# Die Mündung zeigt in Ruhe in eine Richtung. Nach dem Zielen muss sie zum Ziel zeigen.
	for type in ["crossbow", "sling", "forge", "bomb"]:
		var tower := Models.tower(type, 1, "")
		add_child_autofree(tower)
		var turret: Node3D = tower.get_meta("turret")
		var muzzle := tower.find_child("Muzzle", true, false) as Node3D
		for dir in [Vector2(1, 0), Vector2(0, -1), Vector2(-0.6, 0.8)]:
			turret.rotation.y = atan2(dir.x, dir.y) - float(tower.get_meta("aim_offset"))
			var flat := muzzle.global_position - turret.global_position
			var aim := Vector2(flat.x, flat.z).normalized()
			assert_almost_eq(aim.dot(dir.normalized()), 1.0, 0.02, "%s zielt nicht auf %s" % [type, dir])


func test_level_scene_swaps_models_on_upgrade_and_plays_enemy_poses() -> void:
	var real_save: String = Progress.save_path
	Progress.save_path = "user://test_models_progress.json"
	LevelView.level_id = "level_04"
	LevelView.run_seed = 3
	var l: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l.set_process(false)
	var slot: Vector2i = l.sim.grid.cells_of_type(MineGrid.Cell.BUILD)[0]
	l.sim.gold = 9999
	l.sim.ore = 999
	l.sim.build_tower(slot, "crossbow")
	var view: Node3D = l._tower_views[l.sim.towers[0].id]
	var first: Node = view.get_node("Model")
	l.sim.upgrade_tower(slot)
	assert_ne(view.get_node("Model"), first, "beim Ausbau kommt das Modell der nächsten Stufe")
	l.sim.upgrade_tower(slot)
	l.sim.specialize(slot, 1)
	assert_eq(view.get_child_count(), 1, "kein altes Modell bleibt liegen")
	# Gegner im Schildwall wechseln in die Halte-Pose.
	l.sim.start_next_wave()
	l.sim._spawn("draugr", 0)
	var e: GameSim.Enemy = l.sim.enemies[-1]
	e.hp = 1e9
	e.max_hp = 1e9
	l.advance(0.1)
	e.hold_left = 2.0
	l.advance(0.02)
	var ev: Node3D = l._enemy_views[e.id]
	assert_eq(ev.get_meta("pose"), "held")
	assert_eq((ev.get_meta("anim") as AnimationPlayer).current_animation, "Held")
	e.hold_left = 0.0
	l.advance(0.05)
	assert_eq(ev.get_meta("pose"), "walk")
	LevelView.run_seed = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))
	Progress.save_path = real_save
	Progress.load_progress()


# --- Berserker-Lager ------------------------------------------------------

func _camp_level() -> LevelView:
	LevelView.level_id = "level_04"
	LevelView.run_seed = 3
	var l: LevelView = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l.set_process(false)
	l.sim.gold = 9999
	return l


func _slot_beside_straight_path(l: LevelView) -> Vector2i:
	for slot in l.sim.grid.cells_of_type(MineGrid.Cell.BUILD):
		for d in MineGrid.DIRS:
			var p := slot + d
			var side := Vector2i(-d.y, d.x)
			if l.sim.grid.is_walkable(p) and l.sim.grid.is_walkable(p + side) and l.sim.grid.is_walkable(p - side):
				return slot
	return LevelView.NO_CELL


func test_camp_keeps_its_moving_parts() -> void:
	var camp := Models.tower("shieldwall", 3, "")
	for part in ["Barricade", "Squad_Fight", "Squad_Idle", "RageAura", "HornBlast", "HoldPoint", "Berserker_F0"]:
		assert_not_null(camp.find_child(part, true, false), part)
	assert_null(camp.find_child("Berserker_F0_Leg-1", true, false), "Körperteile werden zusammengefasst")
	camp.free()


func test_camp_stands_on_the_path_and_its_slot_is_flat() -> void:
	var l := _camp_level()
	var slot := _slot_beside_straight_path(l)
	assert_ne(slot, LevelView.NO_CELL)
	assert_eq(l.cell_height(slot), LevelView.SLOT_HEIGHT)
	l.sim.build_tower(slot, "shieldwall")
	assert_eq(l.cell_height(slot), 0.0, "der Bauplatz des Lagers liegt auf Weghöhe")
	var view: Node3D = l._tower_views[l.sim.towers[0].id]
	assert_almost_eq(view.position.y, 0.0, 0.001)
	var model: Node3D = view.get_node("Model")
	# Der Ursprung des Modells liegt in der Mitte des Stollenfelds neben dem Bauplatz.
	var origin := view.position + model.position
	var cell := MineGrid.cell_at(Vector2(origin.x, origin.z) / LevelView.CELL)
	assert_true(l.sim.grid.is_walkable(cell), "Ursprung liegt auf dem Weg")
	assert_eq((cell - slot).length_squared(), 1, "direkt neben dem Bauplatz")
	# Das Lager selbst (im Modell -Z) zeigt vom Weg zum Bauplatz.
	var to_camp := -model.basis.z.normalized()
	assert_almost_eq(Vector2(to_camp.x, to_camp.z).dot(Vector2(slot - cell)), 1.0, 0.01)
	# Verkauf: der Bauplatz wird wieder ein Block.
	l.sim.sell_tower(slot)
	assert_eq(l.cell_height(slot), LevelView.SLOT_HEIGHT)


func test_camp_closes_the_path_while_holding_and_opens_again() -> void:
	var l := _camp_level()
	var slot := _slot_beside_straight_path(l)
	l.sim.build_tower(slot, "shieldwall")
	var t: GameSim.Tower = l.sim.towers[0]
	var model: Node3D = l._tower_views[t.id].get_node("Model")
	var barricade := model.find_child("Barricade", true, false) as Node3D
	var fight := model.find_child("Squad_Fight", true, false) as Node3D
	var idle := model.find_child("Squad_Idle", true, false) as Node3D
	assert_almost_eq(barricade.rotation.y, -PI / 2.0, 0.001, "offen: Sperre am Wegrand")
	assert_false(fight.visible)
	assert_true(idle.visible)
	l.sim.start_next_wave()
	l.sim._spawn("draugr", 0)
	var e: GameSim.Enemy = l.sim.enemies[-1]
	e.held_by = t
	e.hold_left = 3.0
	l._sync_views(1.0)
	assert_true(model.get_meta("holding"))
	assert_true(fight.visible, "der Kampftrupp steht vor der Sperre")
	assert_false(idle.visible)
	assert_true((model.find_child("RageAura", true, false) as Node3D).visible)
	await wait_seconds(0.4)
	assert_almost_eq(barricade.rotation.y, 0.0, 0.05, "festhalten: Sperre quer über dem Weg")
	e.hold_left = 0.0
	e.held_by = null
	l._sync_views(1.0)
	assert_false(model.get_meta("holding"))
	assert_true(idle.visible)
	LevelView.run_seed = 0


func test_moving_the_camp_turns_it_to_the_new_path() -> void:
	var l := _camp_level()
	var slots := l.sim.grid.cells_of_type(MineGrid.Cell.BUILD)
	var slot := _slot_beside_straight_path(l)
	l.sim.build_tower(slot, "shieldwall")
	var target := LevelView.NO_CELL
	for s in slots:
		if s != slot and l.sim.tower_at(s) == null:
			target = s
			break
	assert_eq(l.sim.move_tower(slot, target), GameSim.Result.OK)
	assert_eq(l.cell_height(slot), LevelView.SLOT_HEIGHT, "der alte Platz ist wieder ein Block")
	assert_eq(l.cell_height(target), 0.0)
	var view: Node3D = l._tower_views[l.sim.towers[0].id]
	var origin: Vector3 = view.position + (view.get_node("Model") as Node3D).position
	var cell := MineGrid.cell_at(Vector2(origin.x, origin.z) / LevelView.CELL)
	assert_eq((cell - target).length_squared(), 1)
	LevelView.run_seed = 0


func test_camp_at_a_corner_blocks_the_side_towards_the_entrance() -> void:
	for lv in ["level_06", "level_08"]:
		LevelView.level_id = lv
		LevelView.run_seed = 3
		var l: LevelView = load("res://scenes/level.tscn").instantiate()
		add_child_autofree(l)
		l.set_process(false)
		l.sim.gold = 9999
		var g := l.sim.grid
		var slot := LevelView.NO_CELL
		for s in g.cells_of_type(MineGrid.Cell.BUILD):
			for d in MineGrid.DIRS:
				var side := Vector2i(-d.y, d.x)
				if g.is_walkable(s + d) and not (g.is_walkable(s + d + side) and g.is_walkable(s + d - side)):
					slot = s
		assert_ne(slot, LevelView.NO_CELL, lv)
		if l.sim.tower_at(slot) != null:
			l.sim.sell_tower(slot)
		assert_eq(l.sim.build_tower(slot, "shieldwall"), GameSim.Result.OK)
		var t: GameSim.Tower = l.sim.tower_at(slot)
		var model: Node3D = l._tower_views[t.id].get_node("Model")
		var barricade := model.find_child("Barricade", true, false) as Node3D
		barricade.rotation.y = float(model.get_meta("barricade_hold"))
		# Mitte der geschlossenen Sperre in Weltkoordinaten.
		var mid := Vector3.ZERO
		var n := 0
		for m in barricade.find_children("*", "MeshInstance3D", true, false):
			mid += (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb().get_center()
			n += 1
		assert_gt(n, 0)
		mid /= n
		var origin: Vector3 = l._tower_views[t.id].position + model.position
		var path := MineGrid.cell_at(Vector2(origin.x, origin.z) / LevelView.CELL)
		# Das Nachbarfeld des Stollens, zu dem die Sperre zeigt, muss näher am Eingang liegen (größerer Abstand).
		var offset := Vector2(mid.x - origin.x, mid.z - origin.z)
		var toward := Vector2i(roundi(signf(offset.x)) if absf(offset.x) > absf(offset.y) else 0,
			roundi(signf(offset.y)) if absf(offset.y) >= absf(offset.x) else 0)
		assert_true(g.is_walkable(path + toward), "%s: Sperre liegt auf einem Wegarm" % lv)
		assert_gt(g.distance(path + toward), g.distance(path), "%s: Sperre zum Eingang hin" % lv)
	LevelView.run_seed = 0
	LevelView.level_id = "level_01"
