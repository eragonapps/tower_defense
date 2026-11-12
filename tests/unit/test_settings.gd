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
	assert_eq(tr("MENU_PLAY"), "Spielen")
	assert_signal_emitted_with_parameters(_s, "language_changed", ["de"])
	_s.set_language("en")
	assert_eq(tr("MENU_PLAY"), "Play")


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
