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
		assert_gt(Models.height(node), 0.4, "%s ist zu klein" % type)
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
