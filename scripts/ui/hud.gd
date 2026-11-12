class_name Hud
extends CanvasLayer
## Bedienoberfläche im Level: Anzeigen oben, Baumenü unten, Ende-Bildschirm.
## Die Oberfläche kennt die Spielregeln nicht. Sie zeigt den Zustand an und meldet Wünsche per Signal.

signal build_requested(type: String)
signal sell_requested
signal wave_requested
signal speed_requested
signal pause_requested
signal rotate_requested
signal retry_requested
signal menu_requested

const BUTTON_HEIGHT := 76.0
const FONT := 24
const EDGE := 16.0
const COLOR_PANEL := Color(0.09, 0.08, 0.07, 0.88)
const COLOR_TEXT := Color(0.9, 0.86, 0.78)
const COLOR_GOLD := Color(0.95, 0.74, 0.3)
const COLOR_LIVES := Color(0.9, 0.42, 0.36)

var _margin: MarginContainer
var _lives: Label
var _gold: Label
var _wave: Label
var _pause: Button
var _speed: Button
var _wave_button: Button
var _context: PanelContainer
var _context_title: Label
var _context_buttons: HBoxContainer
var _hint: Label
var _end: Control
var _end_title: Label
var _end_text: Label

var _build_buttons := {}
var _sell_button: Button


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


# --- Aktualisieren --------------------------------------------------------

func show_state(sim: GameSim, paused: bool, speed: float) -> void:
	_lives.text = tr("HUD_LIVES") % sim.lives
	_gold.text = tr("HUD_GOLD") % sim.gold
	_wave.text = tr("HUD_WAVE") % [maxi(sim.wave_index + 1, 0), sim.wave_count]
	_pause.text = tr("HUD_RESUME") if paused else tr("HUD_PAUSE")
	_speed.text = "%d×" % int(speed)
	_wave_button.visible = sim.can_start_wave()
	if _wave_button.visible:
		if sim.wave_index < 0:
			_wave_button.text = tr("HUD_START_WAVE")
		else:
			_wave_button.text = tr("HUD_NEXT_WAVE") % ceili(sim.next_wave_in)
	for type in _build_buttons:
		_build_buttons[type].disabled = sim.gold < int(sim.tower_def(type)["cost"])
	_hint.visible = sim.towers.is_empty() and not _context.visible and sim.status == GameSim.Status.RUNNING


## Zeigt das Baumenü für einen freien Bauplatz.
func show_build_menu(sim: GameSim) -> void:
	_clear_context()
	_context_title.text = tr("HUD_BUILD_TITLE")
	for type in sim.allowed_towers():
		var def := sim.tower_def(type)
		var b := _button("%s\n%s" % [tr(def["name_key"]), tr("HUD_COST") % int(def["cost"])])
		b.custom_minimum_size = Vector2(210, BUTTON_HEIGHT + 12)
		b.pressed.connect(build_requested.emit.bind(type))
		_context_buttons.add_child(b)
		_build_buttons[type] = b
	_context.visible = true


## Zeigt die Auswahl für einen gebauten Turm.
func show_tower_menu(sim: GameSim, tower: GameSim.Tower) -> void:
	_clear_context()
	_context_title.text = tr(tower.def["name_key"])
	_sell_button = _button(tr("HUD_SELL") % sim.sell_value(tower))
	_sell_button.custom_minimum_size = Vector2(210, BUTTON_HEIGHT)
	_sell_button.pressed.connect(sell_requested.emit)
	_context_buttons.add_child(_sell_button)
	_context.visible = true


func hide_context() -> void:
	_clear_context()
	_context.visible = false


func show_end(won: bool, lives: int) -> void:
	hide_context()
	_end_title.text = tr("END_VICTORY") if won else tr("END_DEFEAT")
	_end_title.add_theme_color_override("font_color", COLOR_GOLD if won else COLOR_LIVES)
	_end_text.text = (tr("END_LIVES_LEFT") % lives) if won else tr("END_DEFEAT_TEXT")
	_end.visible = true


func is_end_visible() -> bool:
	return _end.visible


func is_context_visible() -> bool:
	return _context.visible


func _clear_context() -> void:
	_build_buttons.clear()
	_sell_button = null
	for c in _context_buttons.get_children():
		_context_buttons.remove_child(c)
		c.queue_free()


# --- Aufbau ---------------------------------------------------------------

func _build() -> void:
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(area)

	# Oben links: Leben, Gold, Welle.
	var stats_panel := _panel()
	area.add_child(stats_panel)
	stats_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 28)
	stats_panel.add_child(stats)
	_lives = _label("", COLOR_LIVES)
	_gold = _label("", COLOR_GOLD)
	_wave = _label("", COLOR_TEXT)
	for l in [_lives, _gold, _wave]:
		stats.add_child(l)

	# Oben rechts: Drehen, Tempo, Pause, Menü.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(tools)
	tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var rotate := _button(tr("HUD_ROTATE"))
	rotate.pressed.connect(rotate_requested.emit)
	_speed = _button("1×")
	_speed.custom_minimum_size.x = 84
	_speed.pressed.connect(speed_requested.emit)
	_pause = _button(tr("HUD_PAUSE"))
	_pause.custom_minimum_size.x = 130
	_pause.pressed.connect(pause_requested.emit)
	var menu := _button(tr("HUD_MENU"))
	menu.pressed.connect(menu_requested.emit)
	for b in [rotate, _speed, _pause, menu]:
		tools.add_child(b)

	# Unten links: Baumenü oder Turmauswahl.
	_context = _panel()
	_context.visible = false
	area.add_child(_context)
	_context.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_context.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_context.add_child(box)
	_context_title = _label("", COLOR_TEXT)
	box.add_child(_context_title)
	_context_buttons = HBoxContainer.new()
	_context_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_context_buttons)

	_hint = _label(tr("HUD_HINT_BUILD"), COLOR_TEXT)
	area.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Unten rechts: Welle starten.
	_wave_button = _button(tr("HUD_START_WAVE"))
	_wave_button.custom_minimum_size = Vector2(260, BUTTON_HEIGHT + 12)
	_wave_button.pressed.connect(wave_requested.emit)
	area.add_child(_wave_button)
	_wave_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_wave_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_wave_button.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_build_end_screen()


func _build_end_screen() -> void:
	_end = ColorRect.new()
	_end.color = Color(0, 0, 0, 0.72)
	_end.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end.visible = false
	add_child(_end)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 420
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	_end_title = _label("", COLOR_GOLD)
	_end_title.add_theme_font_size_override("font_size", 72)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_text = _label("", COLOR_TEXT)
	_end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var retry := _button(tr("END_RETRY"))
	retry.pressed.connect(retry_requested.emit)
	var menu := _button(tr("END_MENU"))
	menu.pressed.connect(menu_requested.emit)
	for c in [_end_title, _end_text, retry, menu]:
		box.add_child(c)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", style)
	return p


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", FONT)
	b.focus_mode = Control.FOCUS_NONE
	return b


## Hält Abstand zu Kamera-Aussparung und abgerundeten Ecken.
func _apply_safe_area() -> void:
	var view := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var left := EDGE
	var top := EDGE
	var right := EDGE
	var bottom := EDGE
	if window.x > 0 and window.y > 0 and safe.size.x > 0 and safe.size.y > 0 and OS.has_feature("mobile"):
		var scale := view / window
		left = maxf(EDGE, safe.position.x * scale.x + 8)
		top = maxf(EDGE, safe.position.y * scale.y + 8)
		right = maxf(EDGE, (window.x - safe.end.x) * scale.x + 8)
		bottom = maxf(EDGE, (window.y - safe.end.y) * scale.y + 8)
	_margin.add_theme_constant_override("margin_left", int(left))
	_margin.add_theme_constant_override("margin_top", int(top))
	_margin.add_theme_constant_override("margin_right", int(right))
	_margin.add_theme_constant_override("margin_bottom", int(bottom))
