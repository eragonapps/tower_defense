class_name MineGrid
extends RefCounted
## Das Raster eines Levels und die Wegfindung darauf.
## Reine Logik ohne Grafik. Eine Zelle ist eine Längeneinheit breit.
##
## Die Wegfindung ist ein Abstandsfeld: Für jede begehbare Zelle ist gespeichert,
## wie viele Schritte es bis zum Herz sind. Gegner gehen immer zur Nachbarzelle
## mit dem kleinsten Abstand. Ändert sich das Raster, wird das Feld neu berechnet
## und alle Gegner haben sofort einen gültigen Weg.

enum Cell { GRANITE, ROCK, TUNNEL, BUILD, ENTRANCE, HEART, ORE }

const CHARS := {
	"#": Cell.GRANITE,
	":": Cell.ROCK,
	".": Cell.TUNNEL,
	"o": Cell.BUILD,
	"E": Cell.ENTRANCE,
	"H": Cell.HEART,
	"*": Cell.ORE,
}
const UNREACHABLE := -1
## Feste Reihenfolge, damit gleich lange Wege immer gleich entschieden werden.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

var width := 0
var height := 0
var heart := Vector2i(-1, -1)
var entrances: Array[Vector2i] = []
## Leer, wenn das Raster gültig ist. Sonst eine Beschreibung des Fehlers.
var error := ""

var _cells := PackedByteArray()
var _dist := PackedInt32Array()


## Baut ein Raster aus Textzeilen. Zeichen: siehe CHARS.
static func from_rows(rows: Array) -> MineGrid:
	var g := MineGrid.new()
	if rows.is_empty():
		g.error = "Raster ist leer"
		return g
	g.height = rows.size()
	g.width = String(rows[0]).length()
	g._cells.resize(g.width * g.height)
	var hearts := 0
	for y in g.height:
		var row := String(rows[y])
		if row.length() != g.width:
			g.error = "Zeile %d hat %d statt %d Zeichen" % [y, row.length(), g.width]
			return g
		for x in g.width:
			var ch := row[x]
			if not CHARS.has(ch):
				g.error = "Unbekanntes Zeichen '%s' in Zeile %d, Spalte %d" % [ch, y, x]
				return g
			var type: int = CHARS[ch]
			g._cells[y * g.width + x] = type
			if type == Cell.HEART:
				g.heart = Vector2i(x, y)
				hearts += 1
			elif type == Cell.ENTRANCE:
				g.entrances.append(Vector2i(x, y))
	if hearts != 1:
		g.error = "Raster braucht genau ein Herz, gefunden: %d" % hearts
		return g
	if g.entrances.is_empty():
		g.error = "Raster braucht mindestens einen Eingang"
		return g
	g._rebuild_distances()
	if not g.has_path():
		g.error = "Kein Weg von jedem Eingang zum Herz"
	return g


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func get_cell(c: Vector2i) -> int:
	return _cells[c.y * width + c.x] if in_bounds(c) else Cell.GRANITE


## Ändert eine Zelle und berechnet die Wege neu. Für Graben und Zuschütten.
func set_cell(c: Vector2i, type: int) -> void:
	if not in_bounds(c):
		return
	_cells[c.y * width + c.x] = type
	_rebuild_distances()


## Wahr, wenn eine der vier Nachbarzellen begehbar ist.
func touches_walkable(c: Vector2i) -> bool:
	for d in DIRS:
		if is_walkable(c + d):
			return true
	return false


func is_walkable(c: Vector2i) -> bool:
	var t := get_cell(c)
	return t == Cell.TUNNEL or t == Cell.ENTRANCE or t == Cell.HEART


## Mittelpunkt einer Zelle in Rasterkoordinaten.
static func center(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


static func cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


## Schritte bis zum Herz, oder UNREACHABLE.
func distance(c: Vector2i) -> int:
	return _dist[c.y * width + c.x] if in_bounds(c) else UNREACHABLE


## Die Nachbarzelle, die dem Herz am nächsten ist. Am Herz selbst: das Herz.
func next_step(c: Vector2i) -> Vector2i:
	var best := c
	var best_d := distance(c)
	if best_d <= 0:
		return c
	for d in DIRS:
		var n := c + d
		var nd := distance(n)
		if nd != UNREACHABLE and nd < best_d:
			best = n
			best_d = nd
	return best


## Der ganze Weg von einer Zelle zum Herz, beide eingeschlossen. Leer, wenn es keinen gibt.
func path_from(c: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if distance(c) == UNREACHABLE:
		return path
	var cur := c
	path.append(cur)
	while cur != heart:
		cur = next_step(cur)
		path.append(cur)
	return path


## Wahr, wenn jeder Eingang das Herz erreicht.
func has_path() -> bool:
	for e in entrances:
		if distance(e) == UNREACHABLE:
			return false
	return true


## Alle begehbaren Zellen, die auf dem Weg irgendeines Eingangs liegen.
func path_cells() -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for e in entrances:
		for c in path_from(e):
			if not seen.has(c):
				seen[c] = true
				out.append(c)
	return out


func cells_of_type(type: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if _cells[y * width + x] == type:
				out.append(Vector2i(x, y))
	return out


func _rebuild_distances() -> void:
	_dist.resize(width * height)
	_dist.fill(UNREACHABLE)
	var queue: Array[Vector2i] = [heart]
	_dist[heart.y * width + heart.x] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d := _dist[c.y * width + c.x]
		for dir in DIRS:
			var n := c + dir
			if is_walkable(n) and _dist[n.y * width + n.x] == UNREACHABLE:
				_dist[n.y * width + n.x] = d + 1
				queue.append(n)
