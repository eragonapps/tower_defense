extends Control
## Hauptmenü: Titel, Levelkarte mit Sternen, Schwierigkeit, Sprache, Ton.
## Die Oberfläche entsteht im Code, weil die Levelkacheln von den Daten und dem Spielstand abhängen.

const LEVEL_SCENE := "res://scenes/level.tscn"
const COLOR_BG := Color(0.078, 0.067, 0.059)
const COLOR_TITLE := Color(0.91, 0.66, 0.31)
const COLOR_TEXT := Color(0.72, 0.68, 0.62)
const TILE_SIZE := Vector2(190, 118)

var _tiles: GridContainer
var _subtitle: Label
var _difficulty: Button
var _btn_de: Button
var _btn_en: Button
var _sound: Button
var _graphics: Button
var _hall_button: Button
var _hall: Control
var _hall_list: VBoxContainer
var _hall_stars: Label
## Verbesserung → Kaufknopf. Für Tests.
var hall_buttons := {}
var _quit: Button
var _version: Label
## Level-Kennung → Kachel. Für Tests.
var tiles := {}


func _ready() -> void:
	_build()
	Settings.language_changed.connect(func(_l: String) -> void: _refresh())
	Progress.changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.text = "DURNHAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	box.add_child(title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(_subtitle)

	_tiles = GridContainer.new()
	_tiles.columns = 5
	_tiles.add_theme_constant_override("h_separation", 12)
	_tiles.add_theme_constant_override("v_separation", 12)
	var tiles_center := CenterContainer.new()
	tiles_center.add_child(_tiles)
	box.add_child(tiles_center)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_difficulty = _button(250)
	_difficulty.pressed.connect(_cycle_difficulty)
	_btn_de = _button(140)
	_btn_de.text = "Deutsch"
	_btn_de.toggle_mode = true
	_btn_de.pressed.connect(Settings.set_language.bind("de"))
	_btn_en = _button(140)
	_btn_en.text = "English"
	_btn_en.toggle_mode = true
	_btn_en.pressed.connect(Settings.set_language.bind("en"))
	_sound = _button(160)
	_sound.pressed.connect(func() -> void:
		Settings.set_sound_enabled(not Settings.sound_enabled)
		_refresh())
	_quit = _button(150)
	_quit.pressed.connect(get_tree().quit)
	for b in [_difficulty, _btn_de, _btn_en, _sound, _quit]:
		row.add_child(b)

	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	box.add_child(row2)
	box.move_child(row2, row.get_index())
	_hall_button = _button(420)
	_hall_button.pressed.connect(func() -> void:
		_hall.visible = true
		_refresh())
	_graphics = _button(250)
	_graphics.pressed.connect(func() -> void:
		Settings.set_graphics("low" if Settings.graphics == "high" else "high")
		_refresh())
	row2.add_child(_hall_button)
	row2.add_child(_graphics)
	_build_hall()

	_version = Label.new()
	_version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	_version.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	add_child(_version)
	_version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Die Zwergenhalle: dauerhafte Verbesserungen, bezahlt mit verdienten Sternen.
func _build_hall() -> void:
	_hall = ColorRect.new()
	_hall.color = Color(0.05, 0.045, 0.04, 0.97)
	_hall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hall.visible = false
	add_child(_hall)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hall.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	box.add_child(title)
	_hall_stars = Label.new()
	_hall_stars.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hall_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hall_stars.add_theme_font_size_override("font_size", 22)
	_hall_stars.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(_hall_stars)
	_hall_list = VBoxContainer.new()
	_hall_list.add_theme_constant_override("separation", 8)
	box.add_child(_hall_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var reset := _button(300)
	reset.name = "Reset"
	reset.pressed.connect(Progress.reset_hall)
	var back := _button(200)
	back.name = "Back"
	back.pressed.connect(func() -> void: _hall.visible = false)
	row.add_child(reset)
	row.add_child(back)


func _refresh_hall() -> void:
	var hall := GameData.load_hall()
	var free := Progress.free_stars(hall)
	_hall_button.text = "%s (%s)" % [tr("MENU_HALL"), tr("HALL_FREE_STARS") % free]
	if not _hall.visible:
		return
	(_hall.find_child("Title", true, false) as Label).text = tr("MENU_HALL")
	(_hall.find_child("Reset", true, false) as Button).text = tr("HALL_RESET")
	(_hall.find_child("Back", true, false) as Button).text = tr("HALL_BACK")
	_hall_stars.text = tr("HALL_STARS") % [free, Progress.total_stars()]
	for c in _hall_list.get_children():
		_hall_list.remove_child(c)
		c.queue_free()
	hall_buttons.clear()
	for id in hall:
		var def: Dictionary = hall[id]
		var level := Progress.hall_level(id)
		var max_level: int = def["costs"].size()
		var cost := Progress.hall_cost(id, hall)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var text := Label.new()
		text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		text.text = "%s  %d/%d\n%s" % [tr(def["name_key"]), level, max_level, tr(def["desc_key"])]
		text.custom_minimum_size = Vector2(620, 0)
		text.add_theme_font_size_override("font_size", 20)
		text.add_theme_color_override("font_color", COLOR_TEXT)
		row.add_child(text)
		var buy := _button(230)
		buy.custom_minimum_size.y = 62
		buy.text = tr("HALL_MAXED") if cost < 0 else tr("HALL_BUY") % cost
		buy.disabled = cost < 0 or cost > free
		buy.pressed.connect(Progress.buy_hall.bind(id, hall))
		row.add_child(buy)
		_hall_list.add_child(row)
		hall_buttons[id] = buy


func _button(width: float) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(width, 68)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(Sfx.play.bind("click", -8.0))
	return b


## Setzt alle Texte und baut die Levelkacheln neu. Nötig nach Sprachwechsel und neuem Spielstand.
func _refresh() -> void:
	_subtitle.text = tr("GAME_SUBTITLE")
	var diffs := GameData.load_difficulties()
	var diff_name := tr(diffs.get(Settings.difficulty, {}).get("name_key", Settings.difficulty))
	_difficulty.text = "%s: %s" % [tr("MENU_DIFFICULTY"), diff_name]
	_btn_de.set_pressed_no_signal(Settings.language == "de")
	_btn_en.set_pressed_no_signal(Settings.language == "en")
	_sound.text = tr("MENU_SOUND_ON") if Settings.sound_enabled else tr("MENU_SOUND_OFF")
	_quit.text = tr("MENU_QUIT")
	_graphics.text = "%s: %s" % [tr("MENU_GRAPHICS"), tr("MENU_GRAPHICS_HIGH") if Settings.graphics == "high" else tr("MENU_GRAPHICS_LOW")]
	_refresh_hall()
	for c in _tiles.get_children():
		_tiles.remove_child(c)
		c.queue_free()
	tiles.clear()
	for i in GameData.LEVEL_ORDER.size():
		var id := GameData.LEVEL_ORDER[i]
		var tile := _make_tile(i + 1, id)
		_tiles.add_child(tile)
		tiles[id] = tile


## Eine Kachel der Levelkarte: Nummer, Name und die Sterne auf der gewählten Schwierigkeit.
func _make_tile(number: int, id: String) -> Button:
	var unlocked := Progress.is_unlocked(id, GameData.LEVEL_ORDER)
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = TILE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not unlocked
	b.pressed.connect(_start_level.bind(id))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	b.add_child(box)
	var num := Label.new()
	num.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	num.text = str(number)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 34)
	num.add_theme_color_override("font_color", COLOR_TITLE if unlocked else COLOR_TEXT.darkened(0.5))
	box.add_child(num)
	var name_label := Label.new()
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.text = tr(GameData.load_level(id).get("name_key", id)) if unlocked else tr("MENU_LOCKED")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", COLOR_TEXT if unlocked else COLOR_TEXT.darkened(0.5))
	name_label.clip_text = true
	box.add_child(name_label)
	var stars := StarRow.new(Progress.stars(id, Settings.difficulty), 22.0)
	stars.visible = unlocked
	box.add_child(stars)
	return b


func _cycle_difficulty() -> void:
	var order := GameData.DIFFICULTY_ORDER
	Settings.set_difficulty(order[(order.find(Settings.difficulty) + 1) % order.size()])
	_refresh()


func _start_level(id: String) -> void:
	Sfx.play("click")
	LevelView.level_id = id
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
