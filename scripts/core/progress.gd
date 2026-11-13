extends Node
## Spielfortschritt: Sterne je Level und Schwierigkeit. Als Autoload "Progress" registriert.
## Speichert als JSON im Nutzerordner. Die Datei trägt eine Versionsnummer,
## damit spätere Fassungen des Spiels alte Spielstände lesen können.

signal changed

const SAVE_VERSION := 1
const MAX_STARS := 3

var save_path := "user://progress.json"
## Level-Kennung → {Schwierigkeit → Sterne}
var _stars := {}


func _ready() -> void:
	load_progress()


## Sterne für einen Sieg: 3 ohne Verlust, 2 mit mindestens der Hälfte der Leben, sonst 1.
static func stars_for(lives: int, max_lives: int) -> int:
	if lives <= 0 or max_lives <= 0:
		return 0
	if lives >= max_lives:
		return 3
	if lives * 2 >= max_lives:
		return 2
	return 1


func stars(level_id: String, difficulty: String) -> int:
	return int(_stars.get(level_id, {}).get(difficulty, 0))


## Die meisten Sterne, die in einem Level auf irgendeiner Schwierigkeit erreicht wurden.
func best_stars(level_id: String) -> int:
	var best := 0
	for d in _stars.get(level_id, {}):
		best = maxi(best, int(_stars[level_id][d]))
	return best


## Das erste Level ist immer offen. Jedes weitere öffnet sich mit einem Sieg im Level davor.
func is_unlocked(level_id: String, order: Array) -> bool:
	var i := order.find(level_id)
	if i <= 0:
		return i == 0
	return best_stars(order[i - 1]) > 0


## Trägt ein Ergebnis ein. Ein schlechteres Ergebnis überschreibt kein besseres.
## Liefert wahr, wenn es ein neuer Bestwert war.
func record(level_id: String, difficulty: String, earned: int) -> bool:
	earned = clampi(earned, 0, MAX_STARS)
	if earned <= stars(level_id, difficulty):
		return false
	if not _stars.has(level_id):
		_stars[level_id] = {}
	_stars[level_id][difficulty] = earned
	save_progress()
	changed.emit()
	return true


func reset() -> void:
	_stars.clear()
	save_progress()
	changed.emit()


func load_progress() -> void:
	_stars.clear()
	if not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not json.data is Dictionary:
		# Beschädigte Datei: mit leerem Fortschritt weitermachen statt abzustürzen.
		push_warning("Spielstand ist beschädigt und wird ignoriert")
		return
	var levels: Variant = json.data.get("levels", {})
	if not levels is Dictionary:
		return
	# Nur übernehmen, was die erwartete Form hat. So schadet auch eine fremde oder neuere Datei nicht.
	for id in levels:
		if not levels[id] is Dictionary:
			continue
		for d in levels[id]:
			var value: Variant = levels[id][d]
			if (value is float or value is int) and value >= 1:
				if not _stars.has(id):
					_stars[id] = {}
				_stars[id][d] = clampi(int(value), 0, MAX_STARS)


func save_progress() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("Spielstand konnte nicht gespeichert werden (Fehler %d)" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "levels": _stars}, "  "))
	f.close()
