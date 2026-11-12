class_name CameraRig
extends Node3D
## Kamera für das Spielfeld: schräg von oben.
## Ein Finger verschiebt, zwei Finger zoomen, ein kurzes Antippen wählt aus.
## Am PC: Maus ziehen und Mausrad.

signal tapped(screen_pos: Vector2)

## So weit darf sich ein Finger bewegen, damit es noch als Antippen zählt (Bildpunkte der Spielansicht).
const TAP_MAX_MOVE := 16.0
const TAP_MAX_SECONDS := 0.4
const PITCH_DEG := 62.0

var camera: Camera3D
## Bereich in Weltkoordinaten (x, z), in dem sich der Blickpunkt bewegen darf.
var bounds := Rect2(0, 0, 10, 10)
var distance := 30.0
var min_distance := 9.0
var max_distance := 48.0

var _touches := {}
var _tap_possible := false
var _tap_moved := 0.0
var _tap_started_ms := 0
var _yaw_tween: Tween


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.5
	camera.far = 200.0
	add_child(camera)


func _ready() -> void:
	_apply()


## Stellt die Kamera so ein, dass der ganze Bereich sichtbar ist.
func frame(area: Rect2, viewport_aspect: float) -> void:
	bounds = area
	position = Vector3(area.get_center().x, 0, area.get_center().y)
	var half_v := deg_to_rad(camera.fov) * 0.5
	var half_h := atan(tan(half_v) * viewport_aspect)
	var for_width := (area.size.x * 0.5) / tan(half_h)
	# Die Tiefe erscheint durch die Neigung verkürzt.
	var for_depth := (area.size.y * 0.5) * sin(deg_to_rad(PITCH_DEG)) / tan(half_v)
	max_distance = maxf(for_width, for_depth) * 1.35 + 4.0
	distance = maxf(for_width, for_depth) * 1.16 + 3.0
	_apply()


func rotate_step() -> void:
	if _yaw_tween and _yaw_tween.is_running():
		return
	_yaw_tween = create_tween()
	_yaw_tween.tween_property(self, "rotation:y", rotation.y + PI / 2.0, 0.35).set_trans(Tween.TRANS_SINE)


## Der Punkt auf der Höhe plane_y, auf den eine Bildschirmposition zeigt.
func ground_point(screen_pos: Vector2, plane_y := 0.0) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return global_position
	var t := (plane_y - origin.y) / dir.y
	return origin + dir * t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / event.factor)


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		_tap_possible = _touches.size() == 1
		_tap_moved = 0.0
		_tap_started_ms = Time.get_ticks_msec()
	else:
		var quick := Time.get_ticks_msec() - _tap_started_ms <= int(TAP_MAX_SECONDS * 1000)
		if _tap_possible and _touches.size() == 1 and quick:
			tapped.emit(event.position)
		_touches.erase(event.index)
		_tap_possible = false


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var old: Vector2 = _touches[event.index]
	_touches[event.index] = event.position
	_tap_moved += old.distance_to(event.position)
	if _tap_moved > TAP_MAX_MOVE:
		_tap_possible = false
	var pan := ground_point(old) - ground_point(event.position)
	if _touches.size() == 1:
		if not _tap_possible:
			_pan(pan)
	elif _touches.size() == 2:
		var other := Vector2.ZERO
		for i in _touches:
			if i != event.index:
				other = _touches[i]
		var old_d := old.distance_to(other)
		var new_d := event.position.distance_to(other)
		if old_d > 1.0 and new_d > 1.0:
			_zoom(old_d / new_d)
		_pan(pan * 0.5)


func _pan(delta: Vector3) -> void:
	position.x = clampf(position.x + delta.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z + delta.z, bounds.position.y, bounds.end.y)


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func _apply() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0, 0)
