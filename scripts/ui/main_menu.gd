extends Control
## Hauptmenü: Titel, Levelauswahl, Sprachauswahl, Versionsanzeige.

@onready var _levels: VBoxContainer = %Levels
@onready var _btn_de: Button = %LangDe
@onready var _btn_en: Button = %LangEn
@onready var _btn_quit: Button = %Quit
@onready var _btn_sound: Button = %Sound
@onready var _version: Label = %Version


func _ready() -> void:
	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	_btn_de.pressed.connect(Settings.set_language.bind("de"))
	_btn_en.pressed.connect(Settings.set_language.bind("en"))
	_btn_quit.pressed.connect(get_tree().quit)
	_btn_sound.pressed.connect(_toggle_sound)
	Settings.language_changed.connect(_on_language_changed)
	_on_language_changed(Settings.language)


func _on_language_changed(locale: String) -> void:
	_btn_de.set_pressed_no_signal(locale == "de")
	_btn_en.set_pressed_no_signal(locale == "en")
	_btn_sound.text = tr("MENU_SOUND_ON") if Settings.sound_enabled else tr("MENU_SOUND_OFF")
	_build_level_buttons()


## Ein Knopf je Level. Die Namen hängen von der Sprache ab und werden deshalb neu erzeugt.
func _build_level_buttons() -> void:
	for c in _levels.get_children():
		_levels.remove_child(c)
		c.queue_free()
	for i in GameData.LEVEL_ORDER.size():
		var id := GameData.LEVEL_ORDER[i]
		var b := Button.new()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = tr("MENU_LEVEL") % [i + 1, tr(GameData.load_level(id).get("name_key", id))]
		b.custom_minimum_size = Vector2(0, 72)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_start_level.bind(id))
		_levels.add_child(b)


func _toggle_sound() -> void:
	Settings.set_sound_enabled(not Settings.sound_enabled)
	_btn_sound.text = tr("MENU_SOUND_ON") if Settings.sound_enabled else tr("MENU_SOUND_OFF")
	Sfx.play("click")


func _start_level(id: String) -> void:
	Sfx.play("click")
	LevelView.level_id = id
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
