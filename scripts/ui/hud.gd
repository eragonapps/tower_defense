class_name Hud
extends CanvasLayer
## Bedienoberfläche im Level: Anzeigen oben, Baumenü unten, Ende-Bildschirm.
## Die Oberfläche kennt die Spielregeln nicht. Sie zeigt den Zustand an und meldet Wünsche per Signal.

## Ein Knopf im Auswahlmenü wurde gedrückt. id ist die Kennung aus show_menu.
signal action_requested(id: String)
signal wave_requested
signal speed_requested
signal pause_requested
signal rotate_requested
signal retry_requested
signal next_requested
## Eine der angebotenen Gaben wurde gewählt.
signal boon_requested(index: int)
signal menu_requested

const BUTTON_HEIGHT := 76.0
const FONT := 24
const EDGE := 16.0
const COLOR_PANEL := Color(0.09, 0.08, 0.07, 0.88)
const COLOR_TEXT := Color(0.9, 0.86, 0.78)
const COLOR_GOLD := Color(0.95, 0.74, 0.3)
const COLOR_LIVES := Color(0.9, 0.42, 0.36)
const COLOR_ORE := Color(0.45, 0.8, 0.95)

var _margin: MarginContainer
var _lives: Label
var _gold: Label
var _ore: Label
var _wave: Label
var _pause: Button
var _speed: Button
var _wave_button: Button
var _context: PanelContainer
var _context_title: Label
var _context_info: Label
var _context_buttons: GridContainer
var _hint: Label
var _end: Control
var _end_title: Label
var _end_text: Label
var _end_next: Button
var _end_stars: StarRow
var _hint_key := "HUD_HINT_BUILD"
var _fps: Label
var _boons: Control
var _boon_box: HBoxContainer
var _active_boons: Label
var _tip: PanelContainer
var _tip_label: Label


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


# --- Aktualisieren --------------------------------------------------------

func show_state(sim: GameSim, paused: bool, speed: float, show_ore: bool) -> void:
	_lives.text = tr("HUD_LIVES") % sim.lives
	_gold.text = tr("HUD_GOLD") % sim.gold
	_ore.visible = show_ore
	_ore.text = tr("HUD_ORE") % sim.ore
	_wave.text = tr("HUD_WAVE") % [maxi(sim.wave_index + 1, 0), sim.wave_count]
	_pause.text = tr("HUD_RESUME") if paused else tr("HUD_PAUSE")
	_speed.text = "%d×" % int(speed)
	_wave_button.visible = sim.can_start_wave()
	if _wave_button.visible:
		if sim.wave_index < 0:
			_wave_button.text = tr("HUD_START_WAVE")
		else:
			_wave_button.text = tr("HUD_NEXT_WAVE") % ceili(sim.next_wave_in)
	if _fps:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	# Während der Einführung führt der Hinweis oben, der allgemeine unten bleibt aus.
	_hint.visible = sim.wave_index < 0 and not _context.visible and sim.status == GameSim.Status.RUNNING and not _tip.visible


## Legt den Hinweistext fest, der vor der ersten Welle unten links steht.
func set_hint(key: String) -> void:
	_hint_key = key
	if _hint:
		_hint.text = tr(key)


## Zeigt das Auswahlmenü unten links.
## buttons: Liste aus {"id": Kennung, "text": Beschriftung, "disabled": bool}.
func show_menu(title: String, info: String, buttons: Array) -> void:
	_clear_context()
	_context_title.text = title
	_context_info.text = info
	_context_info.visible = info != ""
	for def in buttons:
		var b := _button(def["text"])
		b.custom_minimum_size = Vector2(200, BUTTON_HEIGHT + 12)
		b.disabled = def.get("disabled", false)
		b.pressed.connect(action_requested.emit.bind(def["id"]))
		_context_buttons.add_child(b)
	# Bis zu vier Knöpfe in einer Reihe. Mehr werden auf zwei Reihen verteilt, damit das Menü
	# nicht unter den Wellen-Knopf am rechten Rand läuft.
	_context_buttons.columns = maxi(1, buttons.size() if buttons.size() <= 4 else ceili(buttons.size() / 2.0))
	_context_buttons.visible = not buttons.is_empty()
	_context.visible = true


func hide_context() -> void:
	_clear_context()
	_context.visible = false


func show_end(won: bool, lives: int, has_next: bool, stars := 0) -> void:
	hide_context()
	_end_stars.visible = won
	_end_stars.earned = stars
	_end_next.visible = won and has_next
	_end_title.text = tr("END_VICTORY") if won else tr("END_DEFEAT")
	_end_title.add_theme_color_override("font_color", COLOR_GOLD if won else COLOR_LIVES)
	_end_text.text = (tr("END_LIVES_LEFT") % lives) if won else tr("END_DEFEAT_TEXT")
	_end.visible = true


## Zeigt die Auswahl der Gaben über dem Spielfeld. choices: Liste aus {"name", "desc"}.
func show_boons(choices: Array) -> void:
	hide_context()
	for c in _boon_box.get_children():
		_boon_box.remove_child(c)
		c.queue_free()
	for i in choices.size():
		var b := _button("")
		b.custom_minimum_size = Vector2(330, 190)
		b.pressed.connect(boon_requested.emit.bind(i))
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 10)
		b.add_child(box)
		var name_label := _label(choices[i]["name"], COLOR_GOLD)
		name_label.add_theme_font_size_override("font_size", 28)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name_label)
		var desc := _label(choices[i]["desc"], COLOR_TEXT)
		desc.add_theme_font_size_override("font_size", 20)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)
		_boon_box.add_child(b)
	_boons.visible = true


func hide_boons() -> void:
	_boons.visible = false


func is_boons_visible() -> bool:
	return _boons.visible


## Zeigt einen Hinweis der Einführung oben in der Mitte. Ein leerer Text blendet ihn aus.
func show_tip(text: String) -> void:
	_tip.visible = text != ""
	_tip_label.text = text


func tip_text() -> String:
	return _tip_label.text if _tip.visible else ""


## Zeigt die Namen der gewählten Gaben klein unter den Anzeigen.
func show_active_boons(names: Array) -> void:
	_active_boons.text = " · ".join(names)
	_active_boons.visible = not names.is_empty()


func is_end_visible() -> bool:
	return _end.visible


func is_context_visible() -> bool:
	return _context.visible


func _clear_context() -> void:
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
	_ore = _label("", COLOR_ORE)
	_wave = _label("", COLOR_TEXT)
	for l in [_lives, _gold, _ore, _wave]:
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
	_context_info = _label("", COLOR_TEXT.darkened(0.2))
	_context_info.add_theme_font_size_override("font_size", 20)
	_context_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_info.custom_minimum_size.x = 640
	box.add_child(_context_info)
	_context_buttons = GridContainer.new()
	_context_buttons.add_theme_constant_override("h_separation", 12)
	_context_buttons.add_theme_constant_override("v_separation", 10)
	box.add_child(_context_buttons)

	_hint = _label(tr(_hint_key), COLOR_TEXT)
	# Feste Breite mit Umbruch, damit lange Hinweise nicht unter den Wellen-Knopf laufen.
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 780
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
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

	# Bildrate, nur in Test-Builds sichtbar.
	if OS.is_debug_build():
		_fps = _label("", COLOR_TEXT.darkened(0.4))
		_fps.add_theme_font_size_override("font_size", 16)
		area.add_child(_fps)
		_fps.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)

	_active_boons = _label("", COLOR_GOLD.darkened(0.15))
	_active_boons.add_theme_font_size_override("font_size", 17)
	_active_boons.visible = false
	area.add_child(_active_boons)
	_active_boons.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_active_boons.position = Vector2(6, 84)

	_tip = _panel()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style: StyleBoxFlat = _tip.get_theme_stylebox("panel").duplicate()
	tip_style.border_color = COLOR_GOLD
	tip_style.set_border_width_all(2)
	_tip.add_theme_stylebox_override("panel", tip_style)
	area.add_child(_tip)
	_tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip.position.y = 110
	_tip_label = _label("", COLOR_TEXT)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size.x = 620
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_child(_tip_label)

	_build_boon_screen()
	_build_end_screen()


func _build_boon_screen() -> void:
	_boons = ColorRect.new()
	_boons.color = Color(0, 0, 0, 0.6)
	_boons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boons.visible = false
	add_child(_boons)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boons.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)
	var title := _label(tr("HUD_BOON_TITLE"), COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label(tr("HUD_BOON_TEXT"), COLOR_TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_boon_box = HBoxContainer.new()
	_boon_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_boon_box.add_theme_constant_override("separation", 18)
	box.add_child(_boon_box)


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
	_end_stars = StarRow.new(0, 56.0)
	_end_next = _button(tr("END_NEXT"))
	_end_next.pressed.connect(next_requested.emit)
	var retry := _button(tr("END_RETRY"))
	retry.pressed.connect(retry_requested.emit)
	var menu := _button(tr("END_MENU"))
	menu.pressed.connect(menu_requested.emit)
	for c in [_end_title, _end_stars, _end_text, _end_next, retry, menu]:
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
	b.pressed.connect(Sfx.play.bind("click", -8.0))
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
