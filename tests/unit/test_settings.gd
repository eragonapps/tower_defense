extends GutTest
## Einstellungen: Sprachwahl, Speichern, Laden, beschädigte Dateien.

const SettingsScript := preload("res://scripts/core/settings.gd")
const TMP := "user://test_settings.cfg"

var _s: Node
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_s = SettingsScript.new()
	_s.config_path = TMP
	add_child_autofree(_s)


func after_each() -> void:
	TranslationServer.set_locale(_locale_before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_pick_locale_maps_device_language() -> void:
	assert_eq(SettingsScript.pick_locale("de_AT"), "de")
	assert_eq(SettingsScript.pick_locale("de"), "de")
	assert_eq(SettingsScript.pick_locale("en_US"), "en")
	assert_eq(SettingsScript.pick_locale("fr_FR"), "en", "unbekannte Sprache fällt auf Englisch zurück")
	assert_eq(SettingsScript.pick_locale(""), "en")


func test_set_language_switches_translation_and_emits() -> void:
	watch_signals(_s)
	_s.set_language("de")
	assert_eq(TranslationServer.get_locale(), "de")
	assert_eq(tr("MENU_QUIT"), "Beenden")
	assert_signal_emitted_with_parameters(_s, "language_changed", ["de"])
	_s.set_language("en")
	assert_eq(tr("MENU_QUIT"), "Quit")


func test_unsupported_language_is_ignored() -> void:
	_s.set_language("de")
	_s.set_language("xx")
	assert_eq(_s.language, "de")
	assert_push_warning("Nicht unterstützte Sprache")


func test_language_survives_save_and_load() -> void:
	_s.set_language("de")
	var other: Node = autofree(SettingsScript.new())
	other.config_path = TMP
	other.load_settings()
	assert_eq(other.language, "de")
	_s.set_language("en")
	other.load_settings()
	assert_eq(other.language, "en")


func test_corrupt_file_falls_back_without_crash() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("\u0000\u0001 das ist [keine gültige = Datei\n[[[")
	f.close()
	_s.load_settings()
	assert_engine_error("ConfigFile parse error")
	assert_true(_s.language in SettingsScript.SUPPORTED_LOCALES)


func test_invalid_stored_value_falls_back() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "language", 42)
	cfg.save(TMP)
	_s.load_settings()
	assert_true(_s.language in SettingsScript.SUPPORTED_LOCALES)
	cfg.set_value("general", "language", "klingonisch")
	cfg.save(TMP)
	_s.load_settings()
	assert_true(_s.language in SettingsScript.SUPPORTED_LOCALES)


func test_sound_setting_survives_save_and_load() -> void:
	watch_signals(_s)
	_s.set_sound_enabled(false)
	assert_signal_emitted_with_parameters(_s, "sound_changed", [false])
	var other: Node = autofree(SettingsScript.new())
	other.config_path = TMP
	other.load_settings()
	assert_false(other.sound_enabled)
	_s.set_sound_enabled(true)
	other.load_settings()
	assert_true(other.sound_enabled)


func test_every_sound_file_exists_and_loads() -> void:
	for name in Sfx.SOUNDS:
		assert_gt(Sfx.SOUNDS[name].size(), 0)
		for file in Sfx.SOUNDS[name]:
			assert_not_null(load(Sfx.DIR + file + ".ogg"), "%s: %s fehlt" % [name, file])


func test_muted_game_plays_nothing() -> void:
	var before: bool = Settings.sound_enabled
	Settings.sound_enabled = false
	var count := int(Sfx.played.get("click", 0))
	Sfx.play("click")
	assert_eq(int(Sfx.played.get("click", 0)), count)
	Settings.sound_enabled = true
	Sfx._last_played.erase("click")
	Sfx.play("click")
	assert_eq(int(Sfx.played.get("click", 0)), count + 1)
	Sfx.play("gibt_es_nicht")
	Settings.sound_enabled = before
