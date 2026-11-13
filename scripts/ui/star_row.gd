class_name StarRow
extends Control
## Zeichnet eine Reihe von Sternen, gefüllt bis zur erreichten Zahl.
## Gezeichnet statt als Schriftzeichen, damit es von keiner Schrift abhängt.

const FILLED := Color(0.96, 0.76, 0.3)
const EMPTY := Color(0.3, 0.28, 0.26)

var total := 3
var earned := 0:
	set(value):
		earned = value
		queue_redraw()
var star_size := 22.0:
	set(value):
		star_size = value
		custom_minimum_size = Vector2(total * value * 1.15, value)
		queue_redraw()


func _init(count := 0, size := 22.0) -> void:
	earned = count
	star_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var step := star_size * 1.15
	var start := (size.x - step * total) * 0.5 + step * 0.5
	for i in total:
		var center := Vector2(start + i * step, size.y * 0.5)
		draw_colored_polygon(_star(center, star_size * 0.5), FILLED if i < earned else EMPTY)


static func _star(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		var a := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(a), sin(a)) * r)
	return points
