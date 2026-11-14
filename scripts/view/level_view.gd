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
## Fester Zufallswert für Tests und Screenshots. 0 bedeutet: jedes Mal ein neuer.
static var run_seed := 0

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
var _torch_cells: Array[Vector2i] = []
var _enemy_pool := {}
var _rock_material: StandardMaterial3D
var _floor_material: Material
var _dig_views := {}
var _worker_views := {}
var _menu_signature := ""
var _has_ore := false
var _low_graphics := false
## Schritt der Einführung in Level 1. -1 bedeutet: keine Einführung.
var tutorial_step := -1
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
	# Jeder Versuch bekommt einen eigenen Zufallswert: Die angebotenen Gaben sind jedes Mal andere.
	sim = GameSim.new(level, towers, enemies, _rules(), GameData.load_boons(), run_seed if run_seed != 0 else randi())
	_has_ore = not sim.grid.cells_of_type(MineGrid.Cell.ORE).is_empty() or sim.ore > 0
	_low_graphics = Settings.graphics == "low"
	# Niedrige Grafikstufe rechnet die 3D-Ansicht kleiner und vergrößert sie wieder. Die Oberfläche bleibt scharf.
	get_viewport().scaling_3d_scale = 0.7 if _low_graphics else 1.0
	_build_environment()
	_torch_cells = _choose_torch_cells()
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
	sim.tower_specialized.connect(_on_tower_specialized)
	sim.dig_started.connect(_on_dig_started)
	sim.grid_changed.connect(_on_grid_changed)
	sim.worker_placed.connect(_on_worker_placed)
	sim.aura_pulsed.connect(_on_aura_pulsed)
	sim.enemies_healed.connect(_on_enemies_healed)
	sim.ore_stolen.connect(_on_ore_stolen)
	sim.boons_offered.connect(_on_boons_offered)
	sim.boon_chosen.connect(_on_boon_chosen)
	sim.wave_started.connect(func(_i: int) -> void: Sfx.play("wave", -4.0))
	hud.set_hint(level.get("hint_key", "HUD_HINT_BUILD"))
	if level.get("tutorial", false) and not Settings.tutorial_done:
		tutorial_step = 0
	hud.show_state(sim, paused, SPEEDS[speed_index], _has_ore)


## Regeln für diesen Versuch: allgemeine Regeln, Schwierigkeitsgrad und die Verbesserungen aus der Zwergenhalle.
static func _rules() -> Dictionary:
	var rules := GameData.rules_for(Settings.difficulty)
	rules.merge(Progress.hall_rules(GameData.load_hall(), rules), true)
	return rules


func _process(delta: float) -> void:
	if sim == null:
		return
	# Solange Gaben zur Wahl stehen, steht das Spiel.
	if not paused and sim.pending_boons.is_empty():
		advance(delta * SPEEDS[speed_index])
	if _heart_crystal:
		_heart_crystal.rotate_y(delta * 0.6)
	_refresh_menu()
	hud.show_state(sim, paused, SPEEDS[speed_index], _has_ore)
	_update_tutorial()


## Die Einführung führt Schritt für Schritt durch das erste Level. Jeder Schritt endet,
## sobald der Spieler das Gezeigte getan hat.
func _update_tutorial() -> void:
	if tutorial_step < 0:
		return
	var done := false
	match tutorial_step:
		0:
			done = selected != NO_CELL
		1:
			done = not sim.towers.is_empty()
		2:
			done = sim.wave_index >= 0
		3:
			done = sim.towers.size() >= 3 or sim.wave_index >= 1
		4:
			done = sim.wave_index >= 2
	if done:
		tutorial_step += 1
	if tutorial_step > 4 or sim.status != GameSim.Status.RUNNING:
		tutorial_step = -1
		hud.show_tip("")
		Settings.set_tutorial_done(true)
		return
	hud.show_tip(tr("TUTORIAL_%d" % tutorial_step))


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
						"text": "%s\n%s" % [tr(def["name_key"]), tr("HUD_COST") % sim.tower_cost(type)],
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
			var info := _stats_text(tower.stats, sim.next_stats(tower))
			var title := "%s · %s" % [tr(tower.def["name_key"]), tr("HUD_TOWER_LEVEL") % [tower.level, sim.max_level(tower)]]
			var specs := sim.specs_of(tower)
			if tower.spec != "":
				for spec in specs:
					if spec["id"] == tower.spec:
						title = "%s · %s" % [tr(tower.def["name_key"]), tr(spec["name_key"])]
			elif cost < 0 and not specs.is_empty():
				# Höchste Stufe erreicht: zwei Spezialisierungen zur Wahl, mit kurzer Beschreibung.
				for i in specs.size():
					buttons.append({
						"id": "spec:%d" % i,
						"text": "%s\n%s" % [tr(specs[i]["name_key"]), tr("HUD_COST_ORE") % int(specs[i]["ore"])],
						"disabled": sim.can_specialize(cell, i) != GameSim.Result.OK,
					})
					info += "\n%s: %s" % [tr(specs[i]["name_key"]), tr(specs[i]["desc_key"])]
			buttons.append({"id": "sell", "text": tr("HUD_SELL") % sim.sell_value(tower), "disabled": false})
			return {"title": title, "info": info, "buttons": buttons}
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
				var state := tr("HUD_WORKER_MINING")
				if not worker.active:
					# Zwischen den Wellen ruht die Arbeit. Während einer Welle versteckt er sich nur vor Gegnern.
					state = tr("HUD_WORKER_HIDING") if sim.wave_active or not sim.rules["ore_only_during_waves"] else tr("HUD_WORKER_WAITING")
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
	var parts := []
	if float(stats["damage"]) > 0.0 or float(next.get("damage", 0.0)) > 0.0:
		parts.append(_stat("HUD_STAT_DAMAGE", stats, next, "damage"))
	parts.append(_stat("HUD_STAT_RANGE", stats, next, "range"))
	parts.append(_stat("HUD_STAT_COOLDOWN", stats, next, "cooldown"))
	if float(stats["splash"]) > 0.0 or float(next.get("splash", 0.0)) > 0.0:
		parts.append(_stat("HUD_STAT_SPLASH", stats, next, "splash"))
	if stats.has("slow"):
		var text := "%s %d %%" % [tr("HUD_STAT_SLOW"), roundi(float(stats["slow"]["factor"]) * 100.0)]
		if next.has("slow") and next["slow"] != stats["slow"]:
			text += " → %d %%" % roundi(float(next["slow"]["factor"]) * 100.0)
		parts.append(text)
	if stats.has("capacity"):
		parts.append(_stat("HUD_STAT_CAPACITY", stats, next, "capacity"))
		parts.append(_stat("HUD_STAT_HOLD", stats, next, "hold_time"))
	if stats.has("burn"):
		var text := "%s %s/s" % [tr("HUD_STAT_BURN"), _number(stats["burn"]["dps"])]
		if next.has("burn") and next["burn"] != stats["burn"]:
			text += " → %s/s" % _number(next["burn"]["dps"])
		parts.append(text)
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
	elif id.begins_with("spec:"):
		sim.specialize(selected, int(id.trim_prefix("spec:")))
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
	Sfx.play("victory" if won else "defeat")
	var earned := Progress.stars_for(sim.lives, sim.max_lives) if won else 0
	if won:
		Progress.record(level_id, Settings.difficulty, earned)
	hud.show_end(won, sim.lives, _next_level_id() != "", earned)


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
		view.get_node("Slow").visible = e.slow_left > 0.0
		view.get_node("Burn").visible = e.burn_left > 0.0
		if view.has_meta("anim"):
			var ap: AnimationPlayer = view.get_meta("anim")
			# Die Schritte passen zum Tempo: verlangsamte Gegner laufen sichtbar langsamer.
			# Vom Schildwall gehaltene Gegner stehen still.
			ap.speed_scale = 0.0 if e.hold_left > 0.0 else view.get_meta("walk_speed", 1.0) * (e.slow_factor if e.slow_left > 0.0 else 1.0)
		var bar: Node3D = view.get_node("Bar")
		bar.visible = e.hp < e.max_hp
		if bar.visible:
			bar.global_basis = cam_basis
			var ratio := clampf(e.hp / e.max_hp, 0.0, 1.0)
			var fill: Node3D = bar.get_node("Fill")
			fill.scale.x = maxf(ratio, 0.001)
			fill.position.x = -(1.0 - ratio) * 0.45
			# Die Figur ist skaliert, der Balken soll es nicht sein.
			bar.scale = Vector3.ONE
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
		var wv: Node3D = _worker_views[w.id]
		wv.get_node("Lamp").visible = w.active
		if not wv.has_meta("active") or wv.get_meta("active") != w.active:
			wv.set_meta("active", w.active)
			var figure: Node3D = wv.get_node_or_null("Figure")
			if figure != null:
				Models.animate(figure, Models.WORKER["work"] if w.active else Models.WORKER["hide"], true, 0.8)
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
	var view := _take_enemy_view(e)
	view.position = to_world(e.pos)
	view.visible = true
	_enemy_views[e.id] = view


func _on_enemy_removed(e: GameSim.Enemy, reason: String) -> void:
	var view: Node3D = _enemy_views.get(e.id)
	if view == null:
		return
	_enemy_views.erase(e.id)
	view.get_node("Bar").visible = false
	view.get_node("Slow").visible = false
	view.get_node("Burn").visible = false
	if reason != "killed":
		Sfx.play("leak")
		_release_enemy_view(view)
		return
	Sfx.play("bones", -6.0)
	_burst(view.position + Vector3(0, 0.5, 0), Color(0.85, 0.82, 0.72), 8)
	var figure: Node3D = view.get_node_or_null("Figure")
	var visual: Dictionary = Models.ENEMIES.get(e.type, {})
	if figure != null and visual.has("death"):
		Models.animate(figure, visual["death"], false, 1.4)
		var tween := view.create_tween()
		tween.tween_interval(0.7)
		tween.tween_property(view, "position:y", -0.8, 0.35)
		tween.tween_callback(_release_enemy_view.bind(view))
	else:
		var tween := view.create_tween()
		tween.tween_property(view, "scale", Vector3(1.2, 0.05, 1.2), 0.22)
		tween.tween_callback(_release_enemy_view.bind(view))


## Gegner-Figuren werden wiederverwendet statt jedes Mal neu erzeugt. Das vermeidet Ruckler beim Erscheinen.
func _take_enemy_view(e: GameSim.Enemy) -> Node3D:
	var pool: Array = _enemy_pool.get(e.type, [])
	var view: Node3D
	if pool.is_empty():
		view = _make_enemy(e)
		view.set_meta("type", e.type)
		add_child(view)
	else:
		view = pool.pop_back()
		view.scale = Vector3.ONE
	var figure: Node3D = view.get_node_or_null("Figure")
	var visual: Dictionary = Models.ENEMIES.get(e.type, {})
	if figure != null:
		Models.animate(figure, visual["walk"], true, view.get_meta("walk_speed", 1.0))
	return view


func _release_enemy_view(view: Node3D) -> void:
	view.visible = false
	var type: String = view.get_meta("type", "")
	if not _enemy_pool.has(type):
		_enemy_pool[type] = []
	_enemy_pool[type].append(view)


func _on_tower_built(t: GameSim.Tower) -> void:
	var view := _make_tower(t)
	view.position = to_world(t.pos, SLOT_HEIGHT)
	add_child(view)
	_tower_views[t.id] = view
	Sfx.play("build")
	_burst(view.position + Vector3(0, 0.3, 0), Color(0.6, 0.55, 0.5), 10)


func _on_tower_upgraded(t: GameSim.Tower) -> void:
	var view: Node3D = _tower_views.get(t.id)
	if view == null:
		return
	# Jede Stufe macht den Zwerg größer und setzt einen leuchtenden Stein auf den Sockel.
	view.get_node("Head").scale = Vector3.ONE * (1.0 + 0.14 * (t.level - 1))
	var gem := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 0.16)
	gem.mesh = mesh
	gem.material_override = _material(Color(0.45, 0.85, 1.0), 2.2)
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var angle := (t.level - 2) * TAU / 3.0
	gem.position = Vector3(sin(angle) * 0.66, 0.62, cos(angle) * 0.66)
	view.add_child(gem)
	Sfx.play("upgrade")
	_burst(view.position + Vector3(0, 1.0, 0), Color(0.45, 0.85, 1.0), 12)
	if selected == t.cell:
		_show_range(t)


func _on_tower_specialized(t: GameSim.Tower) -> void:
	var view: Node3D = _tower_views.get(t.id)
	if view == null:
		return
	# Ein goldener Ring um den Sockel zeigt den Meister seines Fachs.
	view.get_node("Head").scale = Vector3.ONE * 1.42
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.8
	mesh.outer_radius = 0.9
	mesh.rings = 20
	mesh.ring_segments = 6
	ring.mesh = mesh
	ring.position.y = 0.3
	ring.material_override = _material(Color(1.0, 0.8, 0.3), 2.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(ring)
	Sfx.play("upgrade")
	_burst(view.position + Vector3(0, 1.0, 0), Color(1.0, 0.8, 0.3), 18)
	if selected == t.cell:
		_show_range(t)


func _on_dig_started(job: GameSim.DigJob) -> void:
	var marker := _flat_disc(0.8, Color(1.0, 0.75, 0.25, 0.75), true)
	marker.visible = true
	marker.position = to_world(MineGrid.center(job.cell), cell_height(job.cell) + 0.05)
	add_child(marker)
	_dig_views[job.cell] = marker
	Sfx.play("dig")


func _on_grid_changed(cell: Vector2i) -> void:
	if _dig_views.has(cell):
		_dig_views[cell].queue_free()
		_dig_views.erase(cell)
	_rebuild_terrain()
	Sfx.play("dig" if sim.grid.is_walkable(cell) else "fill")
	_burst(to_world(MineGrid.center(cell), 0.5), Color(0.4, 0.34, 0.28), 16)
	if selected != NO_CELL:
		select_cell(selected)


func _on_worker_placed(w: GameSim.Worker) -> void:
	var view := _make_worker()
	view.position = to_world(w.pos, cell_height(w.cell))
	add_child(view)
	_worker_views[w.id] = view
	Sfx.play("build")


func _on_tower_sold(t: GameSim.Tower) -> void:
	var view: Node3D = _tower_views.get(t.id)
	if view != null:
		view.queue_free()
		_tower_views.erase(t.id)
	Sfx.play("sell")


func _on_projectile_fired(p: GameSim.Projectile) -> void:
	var view := _make_projectile(p)
	view.position = to_world(p.pos, 1.1)
	var dir := p.target_pos - p.pos
	view.rotation.y = atan2(dir.x, dir.y)
	add_child(view)
	_projectile_views[p.id] = view
	if p.def.has("burn"):
		Sfx.play("shoot_fire", -5.0)
	elif float(p.def["splash"]) > 0.0:
		Sfx.play("shoot_stone", -5.0)
	else:
		Sfx.play("shoot_bolt", -9.0)
	# Der Zwerg dreht sich zum Ziel und schießt.
	for t in sim.towers:
		if t.pos == p.pos and _tower_views.has(t.id):
			_tower_attack(t, dir)
			break


func _tower_attack(t: GameSim.Tower, dir: Vector2) -> void:
	var view: Node3D = _tower_views[t.id]
	var head: Node3D = view.get_node("Head")
	if dir.length_squared() > 0.0001:
		head.rotation.y = atan2(dir.x, dir.y)
	var figure: Node3D = head.get_node_or_null("Figure")
	var visual: Dictionary = Models.TOWERS.get(t.type, {})
	if figure != null:
		Models.animate(figure, visual["attack"], false, 1.6, visual["idle"])


func _on_aura_pulsed(t: GameSim.Tower) -> void:
	if not _tower_views.has(t.id):
		return
	if t.stats.get("kind", "") == "block":
		# Der Schildwall schlägt auf einen der Gehaltenen ein.
		var dir := Vector2.ZERO
		for e in sim.enemies:
			if e.held_by == t:
				dir = e.pos - t.pos
				break
		_tower_attack(t, dir)
		Sfx.play("hit", -8.0)
		return
	_tower_attack(t, Vector2.ZERO)
	_show_ring(to_world(t.pos, 0.12), float(t.stats["range"]) * CELL, Color(0.45, 0.75, 1.0, 0.35))
	Sfx.play("rune", -16.0)


func _on_boons_offered(ids: Array) -> void:
	select_cell(NO_CELL)
	var choices := []
	for id in ids:
		var def := sim.boon_def(id)
		choices.append({"name": tr(def["name_key"]), "desc": tr(def["desc_key"])})
	hud.show_boons(choices)
	Sfx.play("wave", -8.0)


func _on_boon_chosen(_id: String) -> void:
	hud.hide_boons()
	var names := []
	for id in sim.active_boons:
		names.append(tr(sim.boon_def(id)["name_key"]))
	hud.show_active_boons(names)
	Sfx.play("upgrade")


func _on_ore_stolen(_thief: GameSim.Enemy, worker: GameSim.Worker, _amount: int) -> void:
	_show_ring(to_world(worker.pos, cell_height(worker.cell) + 0.1), CELL * 0.9, Color(1.0, 0.25, 0.2, 0.6))
	Sfx.play("sell", -4.0)


func _on_enemies_healed(healer: GameSim.Enemy) -> void:
	var heal: Dictionary = healer.def["heal"]
	_show_ring(to_world(healer.pos, 0.12), float(heal["radius"]) * CELL, Color(0.4, 1.0, 0.5, 0.4))


func _on_projectile_hit(p: GameSim.Projectile) -> void:
	var view: Node3D = _projectile_views.get(p.id)
	if view != null:
		view.queue_free()
		_projectile_views.erase(p.id)
	var splash := float(p.def["splash"])
	var fire: bool = p.def.has("burn")
	if splash > 0.0:
		_show_ring(to_world(p.pos, 0.15), splash * CELL, Color(1.0, 0.45, 0.15, 0.6) if fire else Color(0.8, 0.75, 0.65, 0.55))
		_burst(to_world(p.pos, 0.3), Color(1.0, 0.5, 0.15) if fire else Color(0.55, 0.5, 0.45), 12)
		Sfx.play("blast", -4.0)
	else:
		if fire:
			_burst(to_world(p.pos, 0.7), Color(1.0, 0.5, 0.15), 6)
		Sfx.play("hit", -12.0)


func _show_range(tower: GameSim.Tower) -> void:
	var r := float(tower.stats["range"]) * CELL
	_range_marker.scale = Vector3(r, 1, r)
	_range_marker.position = to_world(tower.pos, 0.08)
	_range_marker.visible = true


## Ein flacher Ring, der sich vom Mittelpunkt aus ausbreitet und verblasst.
func _show_ring(at: Vector3, radius: float, color: Color) -> void:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.06
	mesh.radial_segments = 32
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = at
	m.scale = Vector3(0.2, 1, 0.2)
	add_child(m)
	var tween := m.create_tween().set_parallel()
	tween.tween_property(m, "scale", Vector3(radius, 1, radius), 0.28).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.34)
	tween.chain().tween_callback(m.queue_free)


## Ein kurzer Stoß kleiner Teilchen, zum Beispiel Staub oder Funken.
func _burst(at: Vector3, color: Color, count: int) -> void:
	if _low_graphics:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.1)
	p.mesh = mesh
	p.material_override = _material(color, 0.6)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# --- Platzhalter-Formen ---------------------------------------------------

func _make_enemy(e: GameSim.Enemy) -> Node3D:
	var size := float(e.def["size"])
	var root := Node3D.new()
	var height := 1.35 * size
	var visual: Dictionary = Models.ENEMIES.get(e.type, {})
	if visual.has("model") and Models.has(visual["model"]):
		var figure := Models.character(visual["model"], [], Vector3.ONE * Models.ENEMY_SCALE * size)
		figure.name = "Figure"
		if visual.has("tint"):
			Models.tint(figure, visual["tint"])
		root.add_child(figure)
		root.set_meta("anim", Models.player(figure))
		# Schnelle Gegner bewegen die Beine schneller.
		root.set_meta("walk_speed", clampf(float(e.def["speed"]) * 0.9, 0.7, 1.8))
	else:
		# Ersatzform für Gegner ohne Modell.
		var body := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.3 * size
		mesh.height = height
		body.mesh = mesh
		body.position.y = height * 0.5
		body.material_override = _material(Color(String(e.def["color"])))
		root.add_child(body)

	# Anzeigen für Verlangsamung (blauer Ring am Boden) und Brennen (Flamme über dem Kopf).
	var slow := _flat_disc(0.42 * size, Color(0.4, 0.75, 1.0, 0.55), true)
	slow.name = "Slow"
	slow.position.y = 0.12
	root.add_child(slow)
	var burn := MeshInstance3D.new()
	burn.name = "Burn"
	var flame := PrismMesh.new()
	flame.size = Vector3(0.28, 0.4, 0.28)
	burn.mesh = flame
	burn.material_override = _material(Color(1.0, 0.5, 0.12), 3.0)
	burn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burn.position.y = height + 0.1
	burn.visible = false
	root.add_child(burn)

	var bar := Node3D.new()
	bar.name = "Bar"
	bar.position.y = height + 0.5
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
	# Steinsockel.
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.7
	base_mesh.bottom_radius = 0.8
	base_mesh.height = 0.55
	base_mesh.radial_segments = 10
	base.mesh = base_mesh
	base.position.y = 0.275
	base.material_override = _rock_mat(Color(0.5, 0.47, 0.44))
	root.add_child(base)
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.74
	band_mesh.bottom_radius = 0.74
	band_mesh.height = 0.07
	band_mesh.radial_segments = 10
	band.mesh = band_mesh
	band.position.y = 0.5
	band.material_override = _material(color, 0.5)
	root.add_child(band)

	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 0.55
	root.add_child(head)
	var visual: Dictionary = Models.TOWERS.get(t.type, {})
	if visual.has("model") and Models.has(visual["model"]):
		var figure := Models.character(visual["model"], visual["items"], Models.DWARF_SCALE)
		figure.name = "Figure"
		head.add_child(figure)
		Models.animate(figure, visual["idle"])
	else:
		var body := MeshInstance3D.new()
		var body_mesh := CylinderMesh.new()
		body_mesh.top_radius = 0.34
		body_mesh.bottom_radius = 0.42
		body_mesh.height = 0.7
		body.mesh = body_mesh
		body.position.y = 0.35
		body.material_override = _material(color)
		head.add_child(body)

	# Beiwerk, das den Turmtyp auch von Weitem erkennbar macht.
	if t.stats.get("kind", "") == "aura":
		var stone := MeshInstance3D.new()
		var stone_mesh := BoxMesh.new()
		stone_mesh.size = Vector3(0.3, 0.95, 0.16)
		stone.mesh = stone_mesh
		stone.position = Vector3(-0.42, 1.0, -0.3)
		stone.rotation.y = 0.5
		stone.material_override = _material(Color(0.35, 0.7, 1.0), 1.8)
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(stone)
	elif t.type == "bomb" and Models.has(Models.DUNGEON + "keg"):
		var keg := Models.instance(Models.DUNGEON + "keg")
		keg.scale = Vector3.ONE * 0.26
		keg.position = Vector3(-0.42, 0.55, -0.3)
		root.add_child(keg)
	elif t.stats.has("burn"):
		var bowl := MeshInstance3D.new()
		var bowl_mesh := CylinderMesh.new()
		bowl_mesh.top_radius = 0.24
		bowl_mesh.bottom_radius = 0.14
		bowl_mesh.height = 0.5
		bowl_mesh.radial_segments = 8
		bowl.mesh = bowl_mesh
		bowl.position = Vector3(-0.44, 0.8, -0.3)
		bowl.material_override = _material(Color(0.16, 0.15, 0.15))
		root.add_child(bowl)
		var embers := MeshInstance3D.new()
		var ember_mesh := SphereMesh.new()
		ember_mesh.radius = 0.2
		ember_mesh.height = 0.3
		embers.mesh = ember_mesh
		embers.position = Vector3(-0.44, 1.08, -0.3)
		embers.material_override = _material(Color(1.0, 0.45, 0.1), 3.0)
		embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(embers)
	return root


## Ein Zwerg mit Axt und Laterne, der auf der Erzader steht.
func _make_worker() -> Node3D:
	var root := Node3D.new()
	if Models.has(Models.WORKER["model"]):
		var figure := Models.character(Models.WORKER["model"], Models.WORKER["items"], Models.DWARF_SCALE * 0.9)
		figure.name = "Figure"
		root.add_child(figure)
	else:
		var body := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.26
		mesh.height = 0.8
		body.mesh = mesh
		body.position.y = 0.4
		body.material_override = _material(Color(0.55, 0.33, 0.18))
		root.add_child(body)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.14, 0.2, 0.14)
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(0.5, 0.2, 0.3)
	lamp.material_override = _material(Color(1.0, 0.8, 0.35), 3.0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lamp)
	return root


func _make_projectile(p: GameSim.Projectile) -> Node3D:
	var m := MeshInstance3D.new()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if p.def.has("burn"):
		# Feuerkugel.
		var ball := SphereMesh.new()
		ball.radius = 0.17
		ball.height = 0.34
		ball.radial_segments = 8
		ball.rings = 4
		m.mesh = ball
		m.material_override = _material(Color(1.0, 0.5, 0.12), 3.5)
	elif float(p.def["splash"]) > 0.0:
		# Steinbrocken. Je größer die Fläche, desto größer das Geschoss.
		var rock := SphereMesh.new()
		rock.radius = 0.2 if float(p.def["splash"]) < 1.5 else 0.32
		rock.height = rock.radius * 1.8
		rock.radial_segments = 6
		rock.rings = 3
		m.mesh = rock
		m.material_override = _material(Color(0.5, 0.48, 0.46))
	else:
		# Armbrustbolzen, zeigt in Flugrichtung.
		var bolt := BoxMesh.new()
		bolt.size = Vector3(0.05, 0.05, 0.55)
		m.mesh = bolt
		m.material_override = _material(Color(1.0, 0.9, 0.65), 1.6)
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
	# Ohne Fackellichter wäre es zu dunkel, deshalb auf niedriger Stufe mehr Grundlicht.
	env.ambient_light_energy = 0.9 if _low_graphics else 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.045, 0.06)
	env.fog_density = 0.006
	env.glow_enabled = not _low_graphics
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	# Kaltes, schwaches Licht von oben, damit Formen und Schatten lesbar bleiben.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.62, 0.7, 0.9)
	sun.light_energy = 0.6
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.shadow_enabled = not _low_graphics
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

	_add_floors(floors, floor_colors)
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(CELL, 1.0, CELL)
	var block_node := _add_multimesh(block_mesh, blocks, block_colors)
	block_node.material_override = _rock_mat(Color.WHITE)
	_terrain_nodes.append(block_node)
	_add_props()
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


## Stollenboden aus den Bodenplatten des Dungeon-Pakets, je Zelle eine von vier Varianten in zufälliger Drehung.
func _add_floors(transforms: Array[Transform3D], colors: Array[Color]) -> void:
	var variants := ["floor_dirt_small_A", "floor_dirt_small_B", "floor_dirt_small_C", "floor_dirt_small_D"]
	if not Models.has(Models.DUNGEON + variants[0]):
		var floor_mesh := BoxMesh.new()
		floor_mesh.size = Vector3(CELL, 0.2, CELL)
		_terrain_nodes.append(_add_multimesh(floor_mesh, transforms, colors))
		return
	var groups := {}
	for t in transforms:
		var cell := MineGrid.cell_at(Vector2(t.origin.x, t.origin.z) / CELL)
		var v := int(_variation(cell) * 255.0)
		var name: String = variants[v % variants.size()]
		if not groups.has(name):
			groups[name] = [] as Array[Transform3D]
		var basis := Basis(Vector3.UP, (v / 4 % 4) * PI / 2.0)
		groups[name].append(Transform3D(basis, Vector3(t.origin.x, -0.08, t.origin.z)))
	for name in groups:
		var list: Array[Transform3D] = groups[name]
		var node := _add_multimesh(Models.mesh(Models.DUNGEON + name), list, _white(list.size()))
		# Das Material des Modells, abgedunkelt, damit es zum düsteren Stollen passt.
		node.material_override = _floor_mat(Models.mesh(Models.DUNGEON + name))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_terrain_nodes.append(node)


func _floor_mat(source: Mesh) -> Material:
	if _floor_material == null:
		var original := source.surface_get_material(0)
		if original is StandardMaterial3D:
			_floor_material = original.duplicate()
			_floor_material.albedo_color = Color(0.5, 0.44, 0.4)
		else:
			_floor_material = original
	return _floor_material


## Fackeln und Kisten auf dem Fels. Sie hängen an der Zelle und verschwinden, wenn dort gegraben wird.
func _add_props() -> void:
	var g := sim.grid
	for cell in _torch_cells:
		if g.get_cell(cell) != MineGrid.Cell.ROCK or sim.dig_job_at(cell) != null:
			continue
		var at := to_world(MineGrid.center(cell), cell_height(cell))
		var holder := Node3D.new()
		holder.position = at
		if Models.has(Models.DUNGEON + "torch_lit"):
			var torch := Models.instance(Models.DUNGEON + "torch_lit")
			torch.position.y = 0.4
			torch.scale = Vector3.ONE * 0.9
			holder.add_child(torch)
		if not _low_graphics:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.62, 0.3)
			light.light_energy = 2.4
			light.omni_range = 6.5
			light.position.y = 1.3
			holder.add_child(light)
		add_child(holder)
		_terrain_nodes.append(holder)
	var props := ["barrel_small", "box_large", "keg", "crates_stacked", "rubble_half"]
	var scales := [0.55, 0.42, 0.34, 0.34, 0.22]
	for y in range(1, g.height - 1):
		for x in range(1, g.width - 1):
			var cell := Vector2i(x, y)
			var pick := int(_variation(cell + Vector2i(7, 3)) * 255.0)
			if g.get_cell(cell) != MineGrid.Cell.ROCK or pick % 9 != 0 or cell in _torch_cells:
				continue
			var i := (pick / 9) % props.size()
			if not Models.has(Models.DUNGEON + props[i]):
				continue
			var prop := Models.instance(Models.DUNGEON + props[i])
			prop.scale = Vector3.ONE * scales[i]
			prop.position = to_world(MineGrid.center(cell), cell_height(cell))
			prop.rotation.y = _variation(cell) * TAU
			add_child(prop)
			_terrain_nodes.append(prop)


## Wählt wenige Felsfelder am Stollenrand für Fackeln, gleichmäßig über das Level verteilt.
## Es bleiben wenige, weil jedes Licht auf Mobilgeräten Rechenzeit kostet.
func _choose_torch_cells() -> Array[Vector2i]:
	var g := sim.grid
	var chosen: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	for cell in g.cells_of_type(MineGrid.Cell.ROCK):
		if g.touches_walkable(cell):
			candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _variation(a * 3) < _variation(b * 3))
	for cell in candidates:
		var far_enough := true
		for other in chosen:
			if (other - cell).length() < 5.0:
				far_enough = false
				break
		if far_enough:
			chosen.append(cell)
		if chosen.size() >= 5:
			break
	return chosen


## Felsmaterial mit einer Rauschtextur, damit die Blöcke nicht wie glatte Würfel aussehen.
## Die Farbe je Block kommt weiter aus den Instanzfarben.
func _rock_mat(tint: Color) -> StandardMaterial3D:
	if _rock_material == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.035
		noise.seed = 7
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.55, 0.55))
		ramp.set_color(1, Color(1.25, 1.25, 1.25))
		tex.color_ramp = ramp
		_rock_material = StandardMaterial3D.new()
		_rock_material.albedo_texture = tex
		_rock_material.uv1_triplanar = true
		_rock_material.uv1_scale = Vector3(0.45, 0.45, 0.45)
		_rock_material.vertex_color_use_as_albedo = true
		_rock_material.roughness = 1.0
	if tint == Color.WHITE:
		return _rock_material
	var mat: StandardMaterial3D = _rock_material.duplicate()
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = tint
	return mat


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
	# Das Tor steht am äußeren Rand der Zelle und zeigt in Laufrichtung.
	var cell := MineGrid.cell_at(Vector2(at.x, at.z) / CELL)
	var step := sim.grid.next_step(cell) - cell
	var dir := Vector3(step.x, 0, step.y)
	var holder := Node3D.new()
	holder.position = at - dir * (CELL * 0.4)
	holder.rotation.y = atan2(dir.x, dir.z)
	add_child(holder)
	if Models.has(Models.DUNGEON + "wall_doorway"):
		var gate := Models.instance(Models.DUNGEON + "wall_doorway")
		gate.scale = Vector3(0.5, 0.5, 0.5)
		holder.add_child(gate)
	var glow := MeshInstance3D.new()
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(0.9, 1.3, 0.08)
	glow.mesh = glow_mesh
	glow.material_override = _material(Color(0.25, 0.95, 0.7), 1.6)
	glow.position = Vector3(0, 0.7, -0.12)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(glow)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.95, 0.72)
	light.light_energy = 2.2
	light.omni_range = 7.0
	light.position = Vector3(0, 1.4, 1.0)
	holder.add_child(light)


func _build_heart(at: Vector3) -> void:
	# Die Schatzkammer: Truhe und Münzen, darüber der glühende Kern.
	if Models.has(Models.DUNGEON + "chest_gold"):
		var chest := Models.instance(Models.DUNGEON + "chest_gold")
		chest.scale = Vector3.ONE * 0.6
		chest.position = at + Vector3(0.15, 0.1, -0.2)
		chest.rotation.y = -0.6
		add_child(chest)
		for offset in [Vector3(-0.55, 0, 0.35), Vector3(0.55, 0, 0.5)]:
			var coins := Models.instance(Models.DUNGEON + "coin_stack_large" if offset.x < 0 else Models.DUNGEON + "coin_stack_small")
			coins.scale = Vector3.ONE * 0.45
			coins.position = at + offset
			add_child(coins)
	_heart_crystal = Node3D.new()
	_heart_crystal.position = at + Vector3(0, 1.7, 0)
	add_child(_heart_crystal)
	var crystal := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	crystal.mesh = mesh
	crystal.rotation = Vector3(deg_to_rad(54.7), 0, deg_to_rad(45))
	crystal.material_override = _material(Color(1.0, 0.55, 0.15), 2.4)
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heart_crystal.add_child(crystal)
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
	hud.boon_requested.connect(func(index: int) -> void: sim.choose_boon(index))
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
	for i in mini(3 if state == "fight" else (6 if state == "boss" else 8), slots.size()):
		sim.build_tower(slots[i], types[i % types.size()])
		for u in i % 3:
			sim.upgrade_tower(slots[i])
	if state == "build":
		select_cell(slots[9])
		return
	if state == "boons":
		sim.pending_boons.assign(["sharp_bolts", "master_miners", "ancestors_guard"])
		sim.boons_offered.emit(sim.pending_boons.duplicate())
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
	if state == "boss":
		# Alle besonderen Gegner auf einmal, zum Ansehen.
		for type in ["bone_king", "skeleton_guard", "skeleton_guard", "skeleton_mage", "skeleton_rogue"]:
			sim._spawn(type, 0)
			for i in 50:
				sim.step()
	for i in 1200:
		sim.step()
		if sim.enemies.size() >= 6 and sim.projectiles.size() >= 2:
			break
	select_cell(slots[1])
	# Näher heran, damit die Figuren zu erkennen sind.
	rig.distance *= 0.55
	rig.position = to_world(sim.enemies[0].pos if not sim.enemies.is_empty() else MineGrid.center(slots[1]))
	rig._apply()
	_sync_views(1.0)
	if state == "end":
		sim.lives = 0
		sim.step()
