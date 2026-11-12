extends Control
## Hauptmenü: Titel, Sprachauswahl, Versionsanzeige.

@onready var _btn_play: Button = %Play
@onready var _btn_de: Button = %LangDe
@onready var _btn_en: Button = %LangEn
@onready var _btn_quit: Button = %Quit
@onready var _version: Label = %Version


func _ready() -> void:
	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	_btn_play.pressed.connect(_start_game)
	_btn_de.pressed.connect(Settings.set_language.bind("de"))
	_btn_en.pressed.connect(Settings.set_language.bind("en"))
	_btn_quit.pressed.connect(get_tree().quit)
	Settings.language_changed.connect(_update_language_buttons)
	_update_language_buttons(Settings.language)


func _update_language_buttons(locale: String) -> void:
	_btn_de.set_pressed_no_signal(locale == "de")
	_btn_en.set_pressed_no_signal(locale == "en")


func _start_game() -> void:
	LevelView.level_id = GameData.LEVEL_ORDER[0]
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
