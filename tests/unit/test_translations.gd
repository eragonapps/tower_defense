extends GutTest
## Übersetzungen: jede Zeile hat einen deutschen und einen englischen Text,
## und jeder im Projekt verwendete Schlüssel existiert.

const CSV := "res://locale/translations.csv"


func _read_rows() -> Array:
	var rows := []
	var f := FileAccess.open(CSV, FileAccess.READ)
	assert_not_null(f, "Übersetzungsdatei fehlt")
	if f == null:
		return rows
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 1 and row[0].strip_edges() == "":
			continue
		rows.append(row)
	return rows


func test_header_lists_both_languages() -> void:
	var rows := _read_rows()
	assert_eq(Array(rows[0]), ["keys", "de", "en"])


func test_every_key_has_german_and_english_text() -> void:
	var rows := _read_rows()
	var seen := {}
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		assert_eq(row.size(), 3, "Zeile %d hat nicht genau 3 Spalten" % (i + 1))
		if row.size() != 3:
			continue
		assert_false(seen.has(row[0]), "Schlüssel doppelt: %s" % row[0])
		seen[row[0]] = true
		assert_ne(row[1].strip_edges(), "", "Deutscher Text fehlt: %s" % row[0])
		assert_ne(row[2].strip_edges(), "", "Englischer Text fehlt: %s" % row[0])
	assert_gt(seen.size(), 0)


func test_translations_are_loaded_by_the_engine() -> void:
	var before := TranslationServer.get_locale()
	var rows := _read_rows()
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		TranslationServer.set_locale("de")
		assert_eq(tr(row[0]), row[1])
		TranslationServer.set_locale("en")
		assert_eq(tr(row[0]), row[2])
	TranslationServer.set_locale(before)


func test_keys_used_in_scenes_exist() -> void:
	var keys := {}
	for row in _read_rows():
		keys[row[0]] = true
	var re := RegEx.new()
	re.compile("text = \"([A-Z][A-Z0-9]*_[A-Z0-9_]+)\"")
	var checked := 0
	for file in DirAccess.get_files_at("res://scenes"):
		if not file.ends_with(".tscn"):
			continue
		var content := FileAccess.get_file_as_string("res://scenes/" + file)
		for m in re.search_all(content):
			checked += 1
			assert_true(keys.has(m.get_string(1)), "%s nutzt unbekannten Schlüssel %s" % [file, m.get_string(1)])
	assert_gt(checked, 0, "keine Schlüssel in Szenen gefunden")


func test_keys_used_in_scripts_exist() -> void:
	var keys := {}
	for row in _read_rows():
		keys[row[0]] = true
	var re := RegEx.new()
	re.compile("\"((?:HUD|END|MENU|LANG|GAME|TOWER|ENEMY|LEVEL)_[A-Z0-9_]+)\"")
	var checked := 0
	for dir in ["res://scripts/ui", "res://scripts/view", "res://scripts/core"]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			for m in re.search_all(FileAccess.get_file_as_string(dir + "/" + file)):
				checked += 1
				assert_true(keys.has(m.get_string(1)), "%s nutzt unbekannten Schlüssel %s" % [file, m.get_string(1)])
	assert_gt(checked, 10)


func test_placeholders_match_in_both_languages() -> void:
	var re := RegEx.new()
	re.compile("%[ds]")
	for row in _read_rows():
		assert_eq(re.search_all(row[1]).size(), re.search_all(row[2]).size(), "Platzhalter unterschiedlich: %s" % row[0])
