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
## Verbesserung der Zwergenhalle → gekaufte Stufe
var _hall := {}
## Level-Kennung → {Schwierigkeit → beste überstandene Endlos-Welle}
var _endless := {}


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


# --- Zwergenhalle ---------------------------------------------------------

## Alle verdienten Sterne: je Level der beste Wert über alle Schwierigkeiten, dazu die Bonus-Sterne aus dem Endlosmodus.
func total_stars() -> int:
	var total := 0
	for id in _stars:
		total += best_stars(id)
	for id in _endless:
		total += bonus_stars(id)
	return total


# --- Endlosmodus ----------------------------------------------------------

func endless_record(level_id: String, difficulty: String) -> int:
	return int(_endless.get(level_id, {}).get(difficulty, 0))


func best_endless(level_id: String) -> int:
	var best := 0
	for d in _endless.get(level_id, {}):
		best = maxi(best, int(_endless[level_id][d]))
	return best


## Bonus-Sterne eines Levels: einer für jede erreichte Marke, egal auf welcher Schwierigkeit.
func bonus_stars(level_id: String) -> int:
	var best := best_endless(level_id)
	var count := 0
	for mark in GameData.ENDLESS_STAR_WAVES:
		if best >= mark:
			count += 1
	return count


## Trägt eine überstandene Endlos-Welle ein. Liefert die Zahl der dadurch neu verdienten Bonus-Sterne.
func record_endless(level_id: String, difficulty: String, waves: int) -> int:
	if waves <= endless_record(level_id, difficulty):
		return 0
	var before := bonus_stars(level_id)
	if not _endless.has(level_id):
		_endless[level_id] = {}
	_endless[level_id][difficulty] = waves
	save_progress()
	changed.emit()
	return bonus_stars(level_id) - before


func hall_level(id: String) -> int:
	return int(_hall.get(id, 0))


## Sterne, die schon in die Halle geflossen sind.
func spent_stars(hall: Dictionary) -> int:
	var spent := 0
	for id in _hall:
		var costs: Array = hall.get(id, {}).get("costs", [])
		for i in mini(hall_level(id), costs.size()):
			spent += int(costs[i])
	return spent


func free_stars(hall: Dictionary) -> int:
	return total_stars() - spent_stars(hall)


## Kosten der nächsten Stufe, oder -1, wenn die Verbesserung voll ausgebaut ist.
func hall_cost(id: String, hall: Dictionary) -> int:
	var costs: Array = hall.get(id, {}).get("costs", [])
	return int(costs[hall_level(id)]) if hall_level(id) < costs.size() else -1


func buy_hall(id: String, hall: Dictionary) -> bool:
	var cost := hall_cost(id, hall)
	if cost < 0 or cost > free_stars(hall):
		return false
	_hall[id] = hall_level(id) + 1
	save_progress()
	changed.emit()
	return true


## Gibt alle Sterne aus der Halle zurück, damit man sie anders verteilen kann.
func reset_hall() -> void:
	_hall.clear()
	save_progress()
	changed.emit()


## Die Regeln, die sich aus den gekauften Verbesserungen ergeben, aufbauend auf den gegebenen Regeln.
func hall_rules(hall: Dictionary, base: Dictionary) -> Dictionary:
	var out := {}
	for id in hall:
		var level := mini(hall_level(id), hall[id].get("costs", []).size())
		if level <= 0:
			continue
		var effect: Dictionary = hall[id]["effect"]
		var rule: String = effect["rule"]
		var start: float = float(out.get(rule, base.get(rule, GameSim.DEFAULT_RULES.get(rule, 0))))
		out[rule] = start + float(effect["per_level"]) * level
	return out


func reset() -> void:
	_stars.clear()
	_hall.clear()
	_endless.clear()
	save_progress()
	changed.emit()


func load_progress() -> void:
	_stars.clear()
	_hall.clear()
	_endless.clear()
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
	var endless: Variant = json.data.get("endless", {})
	if endless is Dictionary:
		for id in endless:
			if not endless[id] is Dictionary:
				continue
			for d in endless[id]:
				if (endless[id][d] is float or endless[id][d] is int) and endless[id][d] >= 1:
					if not _endless.has(id):
						_endless[id] = {}
					_endless[id][d] = int(endless[id][d])
	var hall: Variant = json.data.get("hall", {})
	if hall is Dictionary:
		for id in hall:
			if (hall[id] is float or hall[id] is int) and hall[id] >= 1:
				_hall[id] = int(hall[id])
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
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "levels": _stars, "hall": _hall, "endless": _endless}, "  "))
	f.close()
