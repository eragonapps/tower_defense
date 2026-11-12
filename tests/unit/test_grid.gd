extends GutTest
## Raster und Wegfindung.

const ROWS := [
	"#######",
	"E...:.#",
	"#:#.#.#",
	"#:..:.#",
	"#:#.#.#",
	"#o....H",
	"#######",
]


func test_parses_cells_and_special_points() -> void:
	var g := MineGrid.from_rows(ROWS)
	assert_eq(g.error, "")
	assert_eq(g.width, 7)
	assert_eq(g.height, 7)
	assert_eq(g.heart, Vector2i(6, 5))
	assert_eq(g.entrances, [Vector2i(0, 1)] as Array[Vector2i])
	assert_eq(g.get_cell(Vector2i(1, 5)), MineGrid.Cell.BUILD)
	assert_eq(g.get_cell(Vector2i(4, 1)), MineGrid.Cell.ROCK)
	assert_eq(g.get_cell(Vector2i(-1, 99)), MineGrid.Cell.GRANITE, "außerhalb zählt als Granit")


func test_invalid_grids_report_an_error() -> void:
	assert_ne(MineGrid.from_rows([]).error, "")
	assert_ne(MineGrid.from_rows(["E.H", "##"]).error, "", "ungleiche Zeilenlängen")
	assert_ne(MineGrid.from_rows(["E.?H"]).error, "", "unbekanntes Zeichen")
	assert_ne(MineGrid.from_rows(["E..."]).error, "", "kein Herz")
	assert_ne(MineGrid.from_rows(["H..H", "E..."]).error, "", "zwei Herzen")
	assert_ne(MineGrid.from_rows(["...H"]).error, "", "kein Eingang")
	assert_ne(MineGrid.from_rows(["E.#.H"]).error, "", "kein Weg")
	assert_ne(MineGrid.from_rows(["E.:.H"]).error, "", "Fels ist nicht begehbar")
	assert_ne(MineGrid.from_rows(["E.o.H"]).error, "", "Bauplatz ist nicht begehbar")


func test_path_is_the_shortest_one() -> void:
	var g := MineGrid.from_rows(ROWS)
	var path := g.path_from(g.entrances[0])
	# Kürzester Weg: 3 nach rechts, 4 nach unten, 3 nach rechts = 10 Schritte.
	assert_eq(g.distance(g.entrances[0]), 10)
	assert_eq(path.size(), 11)
	assert_eq(path[0], Vector2i(0, 1))
	assert_eq(path[-1], g.heart)
	for i in range(1, path.size()):
		assert_eq((path[i] - path[i - 1]).length_squared(), 1, "Schritt %d ist keine Nachbarzelle" % i)
		assert_true(g.is_walkable(path[i]))
		assert_eq(g.distance(path[i]), g.distance(path[i - 1]) - 1)


func test_path_is_deterministic() -> void:
	var a := MineGrid.from_rows(ROWS).path_from(Vector2i(0, 1))
	var b := MineGrid.from_rows(ROWS).path_from(Vector2i(0, 1))
	assert_eq(a, b)


func test_unreachable_cells() -> void:
	var g := MineGrid.from_rows(ROWS)
	assert_eq(g.distance(Vector2i(0, 0)), MineGrid.UNREACHABLE)
	assert_eq(g.path_from(Vector2i(0, 0)).size(), 0)
	assert_eq(g.next_step(g.heart), g.heart)


func test_center_and_cell_at_are_inverse() -> void:
	for c in [Vector2i(0, 0), Vector2i(3, 5), Vector2i(17, 9)]:
		assert_eq(MineGrid.cell_at(MineGrid.center(c)), c)


func test_several_entrances() -> void:
	var g := MineGrid.from_rows(["E...H", "#:#.#", "E...#"])
	assert_eq(g.error, "")
	assert_eq(g.entrances.size(), 2)
	assert_eq(g.distance(Vector2i(0, 0)), 4)
	assert_eq(g.distance(Vector2i(0, 2)), 6)
	assert_eq(g.path_cells().size(), 5 + 5, "beide Wege zusammen, gemeinsame Zellen nur einmal")
