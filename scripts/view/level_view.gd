class_name LevelView
extends Node3D
## Stellt ein Level in 3D dar und verbindet Eingaben, Oberfläche und Simulation.
## Die Grafik besteht in dieser Ausbaustufe aus einfachen Platzhalter-Formen.
## Jede Form entsteht in einer eigenen _make_…-Funktion und lässt sich dort später
## gegen ein richtiges Modell tauschen.

## Kantenlänge einer Rasterzelle in Metern.
const CELL := 2.0
const SLOT_HEIGHT := 0.6
const LEVEL_SCENE := "res://scenes/level.tscn"
const SPEEDS: Array[float] = [1.0, 2.0, 3.0]
## Schutz gegen Aufschaukeln, falls ein Bild sehr lange dauert.
const MAX_STEPS_PER_FRAME := 12
const MENU_SCENE := "res://scenes/main_menu.tscn"
const NO_CELL := Vector2i(-1, -1)

## Welches Level als Nächstes geladen wird. Wird vom Menü gesetzt.
static var level_id := "level_01"

var sim: GameSim
var hud: Hud
var rig: CameraRig
var paused := false
var speed_index := 0
var selected := NO_CELL

var _acc := 0.0
var _enemy_views := {}
var _projectile_views := {}
var _tower_views := {}
var _selection_marker: MeshInstance3D
var _range_marker: MeshInstance3D
var _heart_crystal: Node3D
var _terrain_nodes: Array[Node] = []
var _dig_views := {}
var _worker_views := {}
var _menu_signature := ""
var _has_ore := false
var _materials := {}


func _ready() -> void:
	var level := GameData.load_level(level_id)
	var towers := GameData.load_towers()
	var enemies := GameData.load_enemies()
	var errors := GameData.validate(level, towers, enemies)
	if not errors.is_empty():
		push_error("Level %s ist fehlerhaft: %s" % [level_id, ", ".join(errors)])
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return
	sim = GameSim.new(level, towers, enemies, GameData.load_rules())
	_has_ore = not sim.grid.cells_of_type(MineGrid.Cell.ORE).is_empty() or sim.ore > 0
	_build_environment()
	_rebuild_terrain()
	for e in sim.grid.entrances:
		_build_entrance(to_world(MineGrid.center(e)))
	_build_heart(to_world(MineGrid.center(sim.grid.heart)))
	_build_markers()
	_build_camera()
	_build_hud()
	sim.enemy_spawned.connect(_on_enemy_spawned)
	sim.enemy_removed.connect(_on_enemy_removed)
	sim.tower_built.connect(_on_tower_built)
	sim.tower_sold.connect(_on_tower_sold)
	sim.projectile_fired.connect(_on_projectile_fired)
	sim.projectile_hit.connect(_on_projectile_hit)
	sim.finished.connect(_on_finished)
	sim.tower_upgraded.connect(_on_tower_upgraded)
	sim.dig_started.connect(_on_dig_started)
	sim.grid_changed.connect(_on_grid_changed)
	sim.worker_placed.connect(_on_worker_placed)
	hud.set_hint(level.get("hint_key", "HUD_HINT_BUILD"))
	hud.show_state(sim, paused, SPEEDS[speed_index], _has_ore)


func _process(delta: float) -> void:
	if sim == null:
		return
	if not paused:
		advance(delta * SPEEDS[speed_index])
	if _heart_crystal:
		_heart_crystal.rotate_y(delta * 0.6)
	_refresh_menu()
	hud.show_state(sim, paused, SPEEDS[speed_index], _has_ore)


## Rechnet die Simulation um die angegebene Spielzeit weiter und zieht die Darstellung nach.
func advance(game_seconds: float) -> void:
	_acc += game_seconds
	var steps := 0
	while _acc >= GameSim.DT and steps < MAX_STEPS_PER_FRAME and sim.status == GameSim.Status.RUNNING:
		sim.step()
		_acc -= GameSim.DT
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_acc = 0.0
	_sync_views(clampf(_acc / GameSim.DT, 0.0, 1.0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		# App im Hintergrund oder Anruf: das Spiel hält an.
		if sim != null and sim.status == GameSim.Status.RUNNING:
			paused = true
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_to_menu()


# --- Eingaben -------------------------------------------------------------

func _on_tapped(screen_pos: Vector2) -> void:
	if sim.status != GameSim.Status.RUNNING:
		return
	select_cell(pick_cell(screen_pos))


## Die Zelle unter einer Bildschirmposition. Berücksichtigt, dass Fels höher ist als der Stollenboden.
func pick_cell(screen_pos: Vector2) -> Vector2i:
	for h in [2.1, 1.5, 0.95, SLOT_HEIGHT, 0.0]:
		var p := rig.ground_point(screen_pos, h)
		var cell := MineGrid.cell_at(Vector2(p.x, p.z) / CELL)
		if sim.grid.in_bounds(cell) and cell_height(cell) >= h - 0.05:
			return cell
	return NO_CELL


## Wählt eine Zelle aus und öffnet das passende Menü. Zellen ohne Aktion heben die Auswahl auf.
func select_cell(cell: Vector2i) -> void:
	if _menu_for(cell).is_empty():
		cell = NO_CELL
	selected = cell
	_menu_signature = ""
	_selection_marker.visible = cell != NO_CELL
	_range_marker.visible = false
	if cell == NO_CELL:
		hud.hide_context()
		return
	_selection_marker.position = to_world(MineGrid.center(cell), cell_height(cell) + 0.06)
	var tower := sim.tower_at(cell)
	if tower != null:
		_show_range(tower)
	_refresh_menu()


## Baut das Menü neu auf, sobald sich sein Inhalt ändert, zum Beispiel weil das Gold jetzt reicht.
func _refresh_menu() -> void:
	if selected == NO_CELL:
		return
	var menu := _menu_for(selected)
	if menu.is_empty():
		select_cell(NO_CELL)
		return
	var signature := str(menu)
	if signature != _menu_signature:
		_menu_signature = signature
		hud.show_menu(menu["title"], menu["info"], menu["buttons"])


## Beschreibt das Menü für eine Zelle: Titel, Hinweiszeile und Knöpfe. Leer, wenn es dort nichts zu tun gibt.
func _menu_for(cell: Vector2i) -> Dictionary:
	if sim == null or not sim.grid.in_bounds(cell):
		return {}
	var rules := sim.rules
	match sim.grid.get_cell(cell):
		MineGrid.Cell.BUILD:
			var tower := sim.tower_at(cell)
			var buttons := []
			if tower == null:
				for type in sim.allowed_towers():
					var def := sim.tower_def(type)
					buttons.append({
						"id": "build:" + type,
						"text": "%s\n%s" % [tr(def["name_key"]), tr("HUD_COST") % int(def["cost"])],
						"disabled": sim.can_build(cell, type) != GameSim.Result.OK,
					})
				return {"title": tr("HUD_BUILD_TITLE"), "info": "", "buttons": buttons}
			var cost := sim.upgrade_cost(tower)
			if cost >= 0:
				buttons.append({
					"id": "upgrade",
					"text": "%s\n%s" % [tr("HUD_UPGRADE"), tr("HUD_COST_ORE") % cost],
					"disabled": sim.can_upgrade(cell) != GameSim.Result.OK,
				})
			buttons.append({"id": "sell", "text": tr("HUD_SELL") % sim.sell_value(tower), "disabled": false})
			return {
				"title": "%s · %s" % [tr(tower.def["name_key"]), tr("HUD_TOWER_LEVEL") % [tower.level, sim.max_level(tower)]],
				"info": _stats_text(tower.stats, sim.next_stats(tower)),
				"buttons": buttons,
			}
		MineGrid.Cell.ROCK:
			if not rules["digging"]:
				return {}
			var result := sim.can_dig(cell)
			var info := tr("HUD_DIGGING") if result == GameSim.Result.OCCUPIED else _reason(result)
			return {"title": tr("HUD_ROCK"), "info": info, "buttons": [{
				"id": "dig",
				"text": "%s\n%s" % [tr("HUD_DIG"), tr("HUD_COST") % int(rules["dig_cost"])],
				"disabled": result != GameSim.Result.OK,
			}]}
		MineGrid.Cell.TUNNEL:
			if not rules["digging"]:
				return {}
			var result := sim.can_fill(cell)
			return {"title": tr("HUD_TUNNEL"), "info": _reason(result), "buttons": [{
				"id": "fill",
				"text": "%s\n%s" % [tr("HUD_FILL"), tr("HUD_COST") % int(rules["fill_cost"])],
				"disabled": result != GameSim.Result.OK,
			}]}
		MineGrid.Cell.ORE:
			var worker := sim.worker_at(cell)
			if worker != null:
				var state := tr("HUD_WORKER_MINING") if worker.active else tr("HUD_WORKER_HIDING")
				return {"title": tr("HUD_ORE_VEIN"), "info": state, "buttons": []}
			var result := sim.can_place_worker(cell)
			return {"title": tr("HUD_ORE_VEIN"), "info": _reason(result), "buttons": [{
				"id": "worker",
				"text": "%s\n%s" % [tr("HUD_PLACE_WORKER"), tr("HUD_COST") % int(rules["worker_cost"])],
				"disabled": result != GameSim.Result.OK,
			}]}
	return {}


## Kurzer Text, warum ein Befehl gerade nicht geht. Leer, wenn er geht.
func _reason(result: GameSim.Result) -> String:
	match result:
		GameSim.Result.NOT_ENOUGH_GOLD:
			return tr("REASON_GOLD")
		GameSim.Result.NOT_ENOUGH_ORE:
			return tr("REASON_ORE")
		GameSim.Result.BLOCKS_PATH:
			return tr("REASON_BLOCKS_PATH")
		GameSim.Result.ENEMY_IN_THE_WAY:
			return tr("REASON_ENEMY")
		GameSim.Result.NOT_CONNECTED:
			return tr("REASON_NOT_CONNECTED")
		GameSim.Result.LIMIT_REACHED:
			return tr("REASON_LIMIT")
	return ""


func _stats_text(stats: Dictionary, next: Dictionary) -> String:
	var parts := [
		_stat("HUD_STAT_DAMAGE", stats, next, "damage"),
		_stat("HUD_STAT_RANGE", stats, next, "range"),
		_stat("HUD_STAT_COOLDOWN", stats, next, "cooldown"),
	]
	if float(stats["splash"]) > 0.0:
		parts.append(_stat("HUD_STAT_SPLASH", stats, next, "splash"))
	return "   ".join(parts)


## Ein Wert mit Vorschau auf die nächste Stufe, zum Beispiel "Schaden 10 → 17".
func _stat(key: String, stats: Dictionary, next: Dictionary, field: String) -> String:
	var text := "%s %s" % [tr(key), _number(stats[field])]
	if next.has(field) and next[field] != stats[field]:
		text += " → %s" % _number(next[field])
	return text


static func _number(v: Variant) -> String:
	return String.num(float(v), 2)


func _on_action(id: String) -> void:
	if selected == NO_CELL:
		return
	if id.begins_with("build:"):
		sim.build_tower(selected, id.trim_prefix("build:"))
	elif id == "sell":
		sim.sell_tower(selected)
	elif id == "upgrade":
		sim.upgrade_tower(selected)
	elif id == "dig":
		sim.dig(selected)
	elif id == "fill":
		sim.fill(selected)
	elif id == "worker":
		sim.place_worker(selected)
	select_cell(selected)


func _on_speed_requested() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()


func _on_pause_requested() -> void:
	paused = not paused


func _on_retry() -> void:
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _next_level_id() -> String:
	var i := GameData.LEVEL_ORDER.find(level_id)
	return GameData.LEVEL_ORDER[i + 1] if i >= 0 and i + 1 < GameData.LEVEL_ORDER.size() else ""


func _on_next_level() -> void:
	var next := _next_level_id()
	if next != "":
		level_id = next
		get_tree().change_scene_to_file(LEVEL_SCENE)


func _on_finished(won: bool) -> void:
	select_cell(NO_CELL)
	hud.show_end(won, sim.lives, _next_level_id() != "")


# --- Darstellung der Spielobjekte -----------------------------------------

static func to_world(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x * CELL, y, p.y * CELL)


func _sync_views(alpha: float) -> void:
	var cam_basis := rig.camera.global_basis
	for e in sim.enemies:
		var view: Node3D = _enemy_views.get(e.id)
		if view == null:
			continue
		var pos := e.prev_pos.lerp(e.pos, alpha)
		var dir := e.pos - e.prev_pos
		view.position = to_world(pos)
		if dir.length_squared() > 0.000001:
			view.rotation.y = atan2(dir.x, dir.y)
		var bar: Node3D = view.get_node("Bar")
		bar.visible = e.hp < e.max_hp
		if bar.visible:
			bar.global_basis = cam_basis
			var ratio := clampf(e.hp / e.max_hp, 0.0, 1.0)
			var fill: Node3D = bar.get_node("Fill")
			fill.scale.x = maxf(ratio, 0.001)
			fill.position.x = -(1.0 - ratio) * 0.45
	for p in sim.projectiles:
		var view: Node3D = _projectile_views.get(p.id)
		if view != null:
			view.position = to_world(p.prev_pos.lerp(p.pos, alpha), 1.1)
	for cell in _dig_views:
		var job := sim.dig_job_at(cell)
		if job != null:
			# Die Markierung sinkt beim Graben langsam ein.
			var done := 1.0 - clampf(job.time_left / maxf(job.total, 0.001), 0.0, 1.0)
			_dig_views[cell].position.y = cell_height(cell) * (1.0 - done) + 0.05
	for w in sim.workers:
		var lamp: Node3D = _worker_views[w.id].get_node("Lamp")
		lamp.visible = w.active
	# Geschosse, die die Simulation ohne Treffer entfernt hat.
	if _projectile_views.size() > sim.projectiles.size():
		var alive := {}
		for p in sim.projectiles:
			alive[p.id] = true
		for id in _projectile_views.keys():
			if not alive.has(id):
				_projectile_views[id].queue_free()
				_projectile_views.erase(id)


func _on_enemy_spawned(e: GameSim.Enemy) -> void:
	var view := _make_enemy(e)
	view.position = to_world(e.pos)
	add_child(view)
	_enemy_views[e.id] = view


func _on_enemy_removed(e: GameSim.Enemy, reason: String) -> void:
	var view: Node3D = _enemy_views.get(e.id)
	if view == null:
		return
	_enemy_views.erase(e.id)
	view.get_node("Bar").visible = false
	if reason == "killed":
		var tween := view.create_tween()
		tween.tween_property(view, "scale", Vector3(1.2, 0.05, 1.2), 0.22)
		tween.tween_callback(view.queue_free)
	else:
		view.queue_free()


func _on_tower_built(t: GameSim.Tower) -> void:
	var view := _make_tower(t)
	view.position = to_world(t.pos, SLOT_HEIGHT)
	add_child(view)
	_tower_views[t.id] = view


func _on_tower_upgraded(t: GameSim.Tower) -> void:
	var view: Node3D = _tower_views.get(t.id)
	if view == null:
		return
	# Jede Stufe macht den Turmkopf größer und setzt einen leuchtenden Stein auf den Sockel.
	view.get_node("Head").scale = Vector3.ONE * (1.0 + 0.14 * (t.level - 1))
	var gem := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 0.16)
	gem.mesh = mesh
	gem.material_override = _material(Color(0.45, 0.85, 1.0), 2.2)
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var angle := (t.level - 2) * TAU / 3.0
	gem.position = Vector3(sin(angle) * 0.62, 0.92, cos(angle) * 0.62)
	view.add_child(gem)
	if selected == t.cell:
		_show_range(t)


func _on_dig_started(job: GameSim.DigJob) -> void:
	var marker := _flat_disc(0.8, Color(1.0, 0.75, 0.25, 0.75), true)
	marker.visible = true
	marker.position = to_world(MineGrid.center(job.cell), cell_height(job.cell) + 0.05)
	add_child(marker)
	_dig_views[job.cell] = marker


func _on_grid_changed(cell: Vector2i) -> void:
	if _dig_views.has(cell):
		_dig_views[cell].queue_free()
		_dig_views.erase(cell)
	_rebuild_terrain()
	if selected != NO_CELL:
		select_cell(selected)


func _on_worker_placed(w: GameSim.Worker) -> void:
	var view := _make_worker()
	view.position = to_world(w.pos, cell_height(w.cell))
	add_child(view)
	_worker_views[w.id] = view


func _on_tower_sold(t: GameSim.Tower) -> void:
	var view: Node3D = _tower_views.get(t.id)
	if view != null:
		view.queue_free()
		_tower_views.erase(t.id)


func _on_projectile_fired(p: GameSim.Projectile) -> void:
	var view := _make_projectile(p)
	view.position = to_world(p.pos, 1.1)
	add_child(view)
	_projectile_views[p.id] = view
	# Der Turmkopf dreht sich zum Ziel.
	for t in sim.towers:
		if t.pos == p.pos and _tower_views.has(t.id):
			var dir := p.target_pos - t.pos
			_tower_views[t.id].get_node("Head").rotation.y = atan2(dir.x, dir.y)
			break


func _on_projectile_hit(p: GameSim.Projectile) -> void:
	var view: Node3D = _projectile_views.get(p.id)
	if view != null:
		view.queue_free()
		_projectile_views.erase(p.id)
	var splash := float(p.def["splash"])
	if splash > 0.0:
		_show_splash(to_world(p.pos, 0.15), splash * CELL)


func _show_range(tower: GameSim.Tower) -> void:
	var r := float(tower.stats["range"]) * CELL
	_range_marker.scale = Vector3(r, 1, r)
	_range_marker.position = to_world(tower.pos, 0.08)
	_range_marker.visible = true


func _show_splash(at: Vector3, radius: float) -> void:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.1
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.62, 0.25, 0.55)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = at
	m.scale = Vector3(0.2, 1, 0.2)
	add_child(m)
	var tween := m.create_tween().set_parallel()
	tween.tween_property(m, "scale", Vector3(radius, 1, radius), 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(m.queue_free)


# --- Platzhalter-Formen ---------------------------------------------------

func _make_enemy(e: GameSim.Enemy) -> Node3D:
	var size := float(e.def["size"])
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3 * size
	mesh.height = 1.35 * size
	body.mesh = mesh
	body.position.y = mesh.height * 0.5
	body.material_override = _material(Color(String(e.def["color"])))
	root.add_child(body)
	# Augen zeigen die Laufrichtung.
	var eyes := MeshInstance3D.new()
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.34, 0.08, 0.1) * size
	eyes.mesh = eye_mesh
	eyes.position = Vector3(0, mesh.height * 0.78, mesh.radius * 0.92)
	eyes.material_override = _material(Color(0.35, 1.0, 0.8), 2.5)
	root.add_child(eyes)

	var bar := Node3D.new()
	bar.name = "Bar"
	bar.position.y = mesh.height + 0.35
	bar.visible = false
	var back := _quad(Vector2(0.96, 0.16), Color(0.03, 0.03, 0.03))
	var fill := _quad(Vector2(0.9, 0.1), Color(0.85, 0.2, 0.15), 11)
	fill.name = "Fill"
	fill.position.z = 0.01
	bar.add_child(back)
	bar.add_child(fill)
	root.add_child(bar)
	return root


func _make_tower(t: GameSim.Tower) -> Node3D:
	var color := Color(String(t.def["color"]))
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.6
	base_mesh.bottom_radius = 0.75
	base_mesh.height = 0.9
	base.mesh = base_mesh
	base.position.y = 0.45
	base.material_override = _material(Color(0.34, 0.31, 0.28))
	root.add_child(base)

	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 0.9
	root.add_child(head)
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.34
	body_mesh.bottom_radius = 0.42
	body_mesh.height = 0.7
	body.mesh = body_mesh
	body.position.y = 0.35
	body.material_override = _material(color)
	head.add_child(body)
	var weapon := MeshInstance3D.new()
	if float(t.def["splash"]) > 0.0:
		var arm := BoxMesh.new()
		arm.size = Vector3(0.22, 0.22, 1.1)
		weapon.mesh = arm
		weapon.position = Vector3(0, 0.75, 0.25)
		weapon.rotation.x = -0.5
	else:
		var bow := BoxMesh.new()
		bow.size = Vector3(1.0, 0.1, 0.16)
		weapon.mesh = bow
		weapon.position = Vector3(0, 0.6, 0.4)
	weapon.material_override = _material(color.lightened(0.25))
	head.add_child(weapon)
	return root


## Ein Zwerg mit Laterne, der auf der Erzader steht.
func _make_worker() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.26
	mesh.height = 0.8
	body.mesh = mesh
	body.position.y = 0.4
	body.material_override = _material(Color(0.55, 0.33, 0.18))
	root.add_child(body)
	var helmet := MeshInstance3D.new()
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.24
	helmet_mesh.height = 0.3
	helmet.mesh = helmet_mesh
	helmet.position.y = 0.82
	helmet.material_override = _material(Color(0.6, 0.6, 0.62))
	root.add_child(helmet)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.14, 0.2, 0.14)
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(0.36, 0.55, 0.0)
	lamp.material_override = _material(Color(1.0, 0.8, 0.35), 3.0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lamp)
	return root


func _make_projectile(p: GameSim.Projectile) -> Node3D:
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var big := float(p.def["splash"]) > 0.0
	mesh.radius = 0.2 if big else 0.1
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	m.mesh = mesh
	m.material_override = _material(Color(0.5, 0.5, 0.52)) if big else _material(Color(1.0, 0.85, 0.5), 2.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _quad(size: Vector2, color: Color, priority := 10) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = priority
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Materialien werden nach Farbe geteilt, damit gleiche Objekte gemeinsam gezeichnet werden.
func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s/%.1f" % [color.to_html(), emission]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	_materials[key] = mat
	return mat


# --- Aufbau der Szene -----------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.024, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.38, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.045, 0.06)
	env.fog_density = 0.006
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	# Kaltes, schwaches Licht von oben, damit Formen und Schatten lesbar bleiben.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.62, 0.7, 0.9)
	sun.light_energy = 0.75
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


## Höhe der Oberseite einer Zelle über dem Stollenboden.
func cell_height(c: Vector2i) -> float:
	match sim.grid.get_cell(c):
		MineGrid.Cell.BUILD:
			return SLOT_HEIGHT
		MineGrid.Cell.ROCK, MineGrid.Cell.ORE:
			return 0.75 + _variation(c) * 0.45
		MineGrid.Cell.GRANITE:
			return 1.5 + _variation(c) * 0.6
	return 0.0


## Baut Boden, Fels, Bauplätze und Erz neu auf. Nötig nach jedem Graben oder Zuschütten.
func _rebuild_terrain() -> void:
	for n in _terrain_nodes:
		n.queue_free()
	_terrain_nodes.clear()
	var g := sim.grid
	var floors: Array[Transform3D] = []
	var floor_colors: Array[Color] = []
	var blocks: Array[Transform3D] = []
	var block_colors: Array[Color] = []
	var pads: Array[Transform3D] = []
	var nuggets: Array[Transform3D] = []
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			var at := to_world(MineGrid.center(c))
			var v := _variation(c)
			var h := cell_height(c)
			match g.get_cell(c):
				MineGrid.Cell.TUNNEL, MineGrid.Cell.ENTRANCE, MineGrid.Cell.HEART:
					floors.append(Transform3D(Basis(), at + Vector3(0, -0.1, 0)))
					floor_colors.append(Color(0.37, 0.29, 0.22).lerp(Color(0.31, 0.25, 0.2), v))
				MineGrid.Cell.BUILD:
					blocks.append(_block(at, h))
					block_colors.append(Color(0.36, 0.34, 0.33))
					pads.append(Transform3D(Basis(), at + Vector3(0, h + 0.03, 0)))
				MineGrid.Cell.ROCK:
					blocks.append(_block(at, h))
					block_colors.append(Color(0.2, 0.175, 0.155).lerp(Color(0.15, 0.135, 0.125), v))
				MineGrid.Cell.ORE:
					blocks.append(_block(at, h))
					block_colors.append(Color(0.2, 0.2, 0.24))
					# Erzbrocken, im Kreis um die Mitte verteilt. Die Mitte bleibt frei für den Arbeiter.
					for i in 5:
						var a := i * TAU / 5.0 + v * TAU
						var size := 0.24 + 0.1 * float((i * 7 + x) % 3)
						var basis := Basis(Vector3.UP, a * 1.7).scaled(Vector3.ONE * size)
						nuggets.append(Transform3D(basis, at + Vector3(sin(a) * 0.62, h + size * 0.35, cos(a) * 0.62)))
				MineGrid.Cell.GRANITE:
					blocks.append(_block(at, h))
					block_colors.append(Color(0.115, 0.12, 0.14).lerp(Color(0.09, 0.095, 0.115), v))

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(CELL, 0.2, CELL)
	_terrain_nodes.append(_add_multimesh(floor_mesh, floors, floor_colors))
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(CELL, 1.0, CELL)
	_terrain_nodes.append(_add_multimesh(block_mesh, blocks, block_colors))
	# Freie Bauplätze leuchten schwach, damit man sie im Dunkeln findet.
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.72
	pad_mesh.bottom_radius = 0.72
	pad_mesh.height = 0.06
	pad_mesh.radial_segments = 20
	var pad_node := _add_multimesh(pad_mesh, pads, _white(pads.size()))
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.5, 0.36, 0.16)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.95, 0.6, 0.2)
	pad_mat.emission_energy_multiplier = 0.55
	pad_node.material_override = pad_mat
	pad_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain_nodes.append(pad_node)
	if not nuggets.is_empty():
		var nugget_mesh := BoxMesh.new()
		nugget_mesh.size = Vector3.ONE
		var nugget_node := _add_multimesh(nugget_mesh, nuggets, _white(nuggets.size()))
		nugget_node.material_override = _material(Color(0.35, 0.75, 1.0), 1.4)
		nugget_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_terrain_nodes.append(nugget_node)


static func _white(count: int) -> Array[Color]:
	var colors: Array[Color] = []
	colors.resize(count)
	colors.fill(Color.WHITE)
	return colors


func _block(at: Vector3, height: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(1, height, 1)), at + Vector3(0, height * 0.5, 0))


## Gleichmäßig verteilter Wert von 0 bis 1 je Zelle, für leichte Unterschiede in Farbe und Höhe.
static func _variation(c: Vector2i) -> float:
	return float(((c.x * 73856093) ^ (c.y * 19349663)) & 0xff) / 255.0


func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	node.material_override = mat
	add_child(node)
	return node


func _build_entrance(at: Vector3) -> void:
	var stone := _material(Color(0.1, 0.11, 0.12))
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.4, 2.6, 0.4)
		pillar.mesh = mesh
		pillar.material_override = stone
		pillar.position = at + Vector3(0, 1.3, side * 0.8)
		add_child(pillar)
	var lintel := MeshInstance3D.new()
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(0.5, 0.4, 2.2)
	lintel.mesh = lintel_mesh
	lintel.material_override = stone
	lintel.position = at + Vector3(0, 2.7, 0)
	add_child(lintel)
	var glow := MeshInstance3D.new()
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(0.1, 2.2, 1.2)
	glow.mesh = glow_mesh
	glow.material_override = _material(Color(0.25, 0.95, 0.7), 1.6)
	glow.position = at + Vector3(-0.3, 1.2, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.95, 0.72)
	light.light_energy = 2.2
	light.omni_range = 7.0
	light.position = at + Vector3(0.6, 1.4, 0)
	add_child(light)


func _build_heart(at: Vector3) -> void:
	_heart_crystal = Node3D.new()
	_heart_crystal.position = at + Vector3(0, 1.3, 0)
	add_child(_heart_crystal)
	var crystal := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.9, 0.9)
	crystal.mesh = mesh
	crystal.rotation = Vector3(deg_to_rad(54.7), 0, deg_to_rad(45))
	crystal.material_override = _material(Color(1.0, 0.55, 0.15), 2.4)
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heart_crystal.add_child(crystal)
	var socket := MeshInstance3D.new()
	var socket_mesh := CylinderMesh.new()
	socket_mesh.top_radius = 0.5
	socket_mesh.bottom_radius = 0.8
	socket_mesh.height = 0.5
	socket.mesh = socket_mesh
	socket.material_override = _material(Color(0.3, 0.27, 0.24))
	socket.position = at + Vector3(0, 0.25, 0)
	add_child(socket)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.position = at + Vector3(0, 1.6, 0)
	add_child(light)


func _build_markers() -> void:
	_selection_marker = _flat_disc(0.98, Color(1.0, 0.9, 0.55, 0.6), true)
	_range_marker = _flat_disc(1.0, Color(1.0, 0.9, 0.7, 0.13), false)
	add_child(_selection_marker)
	add_child(_range_marker)


func _flat_disc(radius: float, color: Color, depth_test: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 48
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = not depth_test
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	return m


func _build_camera() -> void:
	rig = CameraRig.new()
	add_child(rig)
	var view := get_viewport().get_visible_rect().size
	rig.frame(Rect2(0, 0, sim.grid.width * CELL, sim.grid.height * CELL), view.x / maxf(view.y, 1.0))
	rig.camera.make_current()
	rig.tapped.connect(_on_tapped)


func _build_hud() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.action_requested.connect(_on_action)
	hud.next_requested.connect(_on_next_level)
	hud.wave_requested.connect(func() -> void: sim.start_next_wave())
	hud.speed_requested.connect(_on_speed_requested)
	hud.pause_requested.connect(_on_pause_requested)
	hud.rotate_requested.connect(func() -> void: rig.rotate_step())
	hud.retry_requested.connect(_on_retry)
	hud.menu_requested.connect(_go_to_menu)


# --- Für Bild-Tests -------------------------------------------------------

## Bringt das Level in einen vorzeigbaren Zustand. Nur für tools/screenshot.gd.
func demo(state: String) -> void:
	if state == "start":
		return
	var slots := sim.grid.cells_of_type(MineGrid.Cell.BUILD)
	sim.gold = 2000
	sim.ore = 200
	var types := sim.allowed_towers()
	for i in mini(8, slots.size()):
		sim.build_tower(slots[i], types[i % types.size()])
		for u in i % 3:
			sim.upgrade_tower(slots[i])
	if state == "build":
		select_cell(slots[9])
		return
	if state == "mine":
		# Zugang zu einer Erzader graben, Arbeiter setzen, ein weiteres Feld ist in Arbeit.
		var veins := sim.grid.cells_of_type(MineGrid.Cell.ORE)
		for vein in veins:
			sim.place_worker(vein)
		var rock := NO_CELL
		for cell in sim.grid.cells_of_type(MineGrid.Cell.ROCK):
			if sim.can_dig(cell) == GameSim.Result.OK:
				rock = cell
				break
		if rock != NO_CELL:
			sim.dig(rock)
			for i in 60:
				sim.step()
			select_cell(rock)
		_sync_views(1.0)
		return
	sim.start_next_wave()
	for i in 1200:
		sim.step()
		if sim.enemies.size() >= 6 and sim.projectiles.size() >= 2:
			break
	select_cell(slots[1])
	_sync_views(1.0)
	if state == "end":
		sim.lives = 0
		sim.step()
