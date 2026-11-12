class_name LevelView
extends Node3D
## Stellt ein Level in 3D dar und verbindet Eingaben, Oberfläche und Simulation.
## Die Grafik besteht in dieser Ausbaustufe aus einfachen Platzhalter-Formen.
## Jede Form entsteht in einer eigenen _make_…-Funktion und lässt sich dort später
## gegen ein richtiges Modell tauschen.

## Kantenlänge einer Rasterzelle in Metern.
const CELL := 2.0
const SLOT_HEIGHT := 0.6
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
	sim = GameSim.new(level, towers, enemies)
	_build_environment()
	_build_terrain()
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
	hud.show_state(sim, paused, SPEEDS[speed_index])


func _process(delta: float) -> void:
	if sim == null:
		return
	if not paused:
		advance(delta * SPEEDS[speed_index])
	if _heart_crystal:
		_heart_crystal.rotate_y(delta * 0.6)
	hud.show_state(sim, paused, SPEEDS[speed_index])


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
	var p := rig.ground_point(screen_pos, SLOT_HEIGHT * 0.5)
	select_cell(MineGrid.cell_at(Vector2(p.x, p.z) / CELL))


## Wählt einen Bauplatz aus. Jede andere Zelle hebt die Auswahl auf.
func select_cell(cell: Vector2i) -> void:
	if sim.grid.get_cell(cell) != MineGrid.Cell.BUILD:
		cell = NO_CELL
	selected = cell
	_selection_marker.visible = cell != NO_CELL
	_range_marker.visible = false
	if cell == NO_CELL:
		hud.hide_context()
		return
	_selection_marker.position = to_world(MineGrid.center(cell), SLOT_HEIGHT + 0.06)
	var tower := sim.tower_at(cell)
	if tower == null:
		hud.show_build_menu(sim)
	else:
		hud.show_tower_menu(sim, tower)
		_show_range(tower)


func _on_build_requested(type: String) -> void:
	if selected != NO_CELL and sim.build_tower(selected, type) == GameSim.BuildResult.OK:
		select_cell(selected)


func _on_sell_requested() -> void:
	if selected != NO_CELL and sim.sell_tower(selected):
		select_cell(selected)


func _on_speed_requested() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()


func _on_pause_requested() -> void:
	paused = not paused


func _on_retry() -> void:
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_finished(won: bool) -> void:
	select_cell(NO_CELL)
	hud.show_end(won, sim.lives)


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
	var r := float(tower.def["range"]) * CELL
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


func _build_terrain() -> void:
	var g := sim.grid
	var floors: Array[Transform3D] = []
	var floor_colors: Array[Color] = []
	var blocks: Array[Transform3D] = []
	var block_colors: Array[Color] = []
	var pads: Array[Transform3D] = []
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			var type := g.get_cell(c)
			var at := to_world(MineGrid.center(c))
			var v := _variation(c)
			match type:
				MineGrid.Cell.TUNNEL, MineGrid.Cell.ENTRANCE, MineGrid.Cell.HEART:
					floors.append(Transform3D(Basis(), at + Vector3(0, -0.1, 0)))
					floor_colors.append(Color(0.37, 0.29, 0.22).lerp(Color(0.31, 0.25, 0.2), v))
				MineGrid.Cell.BUILD:
					blocks.append(_block(at, SLOT_HEIGHT))
					block_colors.append(Color(0.36, 0.34, 0.33))
					pads.append(Transform3D(Basis(), at + Vector3(0, SLOT_HEIGHT + 0.03, 0)))
				MineGrid.Cell.ROCK:
					blocks.append(_block(at, 0.75 + v * 0.45))
					block_colors.append(Color(0.2, 0.175, 0.155).lerp(Color(0.15, 0.135, 0.125), v))
				MineGrid.Cell.GRANITE:
					blocks.append(_block(at, 1.5 + v * 0.6))
					block_colors.append(Color(0.115, 0.12, 0.14).lerp(Color(0.09, 0.095, 0.115), v))

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(CELL, 0.2, CELL)
	_add_multimesh(floor_mesh, floors, floor_colors)
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(CELL, 1.0, CELL)
	_add_multimesh(block_mesh, blocks, block_colors)
	# Freie Bauplätze leuchten schwach, damit man sie im Dunkeln findet.
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.72
	pad_mesh.bottom_radius = 0.72
	pad_mesh.height = 0.06
	pad_mesh.radial_segments = 20
	var pad_colors: Array[Color] = []
	pad_colors.resize(pads.size())
	pad_colors.fill(Color.WHITE)
	var pad_node := _add_multimesh(pad_mesh, pads, pad_colors)
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.5, 0.36, 0.16)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.95, 0.6, 0.2)
	pad_mat.emission_energy_multiplier = 0.55
	pad_node.material_override = pad_mat
	pad_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for e in g.entrances:
		_build_entrance(to_world(MineGrid.center(e)))
	_build_heart(to_world(MineGrid.center(g.heart)))


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
	hud.build_requested.connect(_on_build_requested)
	hud.sell_requested.connect(_on_sell_requested)
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
	var types := sim.allowed_towers()
	for i in mini(8, slots.size()):
		sim.build_tower(slots[i], types[i % types.size()])
	if state == "build":
		select_cell(slots[9])
		return
	sim.start_next_wave()
	for i in 1200:
		sim.step()
		if sim.enemies.size() >= 6 and sim.projectiles.size() >= 2:
			break
	select_cell(slots[0])
	_sync_views(1.0)
	if state == "end":
		sim.lives = 0
		sim.step()
