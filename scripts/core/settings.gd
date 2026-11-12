extends Node
## Spieleinstellungen (Sprache, später Ton und Grafik).
## Als Autoload "Settings" registriert. Speichert in einer Datei im Nutzerordner.

signal language_changed(locale: String)

const SUPPORTED_LOCALES: Array[String] = ["de", "en"]
const FALLBACK_LOCALE := "en"
const SAVE_VERSION := 1

var config_path := "user://settings.cfg"
var language := FALLBACK_LOCALE


func _ready() -> void:
	load_settings()


## Wählt aus einer Gerätesprache wie "de_AT" die passende unterstützte Sprache.
static func pick_locale(device_locale: String) -> String:
	var short := device_locale.substr(0, 2).to_lower()
	return short if short in SUPPORTED_LOCALES else FALLBACK_LOCALE


func set_language(locale: String) -> void:
	if locale not in SUPPORTED_LOCALES:
		push_warning("Nicht unterstützte Sprache: %s" % locale)
		return
	language = locale
	TranslationServer.set_locale(locale)
	language_changed.emit(locale)
	save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var chosen := pick_locale(OS.get_locale())
	# Eine fehlende oder beschädigte Datei ist kein Fehler: dann gelten die Standardwerte.
	if cfg.load(config_path) == OK:
		var stored: Variant = cfg.get_value("general", "language", chosen)
		if stored is String and stored in SUPPORTED_LOCALES:
			chosen = stored
	language = chosen
	TranslationServer.set_locale(language)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("general", "language", language)
	var err := cfg.save(config_path)
	if err != OK:
		push_warning("Einstellungen konnten nicht gespeichert werden (Fehler %d)" % err)
