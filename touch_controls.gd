extends Control
# Виртуальный джойстик (левая половина экрана) + кнопки справа.
# На ПК: WASD/стрелки, Пробел = клюв, Shift/C = тихий режим, E = открыть.

signal menu_pressed

const STICK_R := 80.0

var move := Vector2.ZERO
var sneak := false
var use_visible := false
var use_text := "ОТКРЫТЬ"
var enabled := true

var _peck := false
var _stick_id := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _btn := {
	"peck": {"pos": Vector2.ZERO, "r": 80.0, "text": "КЛЮВ", "id": -1},
	"sneak": {"pos": Vector2.ZERO, "r": 58.0, "text": "ТИХО", "id": -1},
	"use": {"pos": Vector2.ZERO, "r": 66.0, "text": "ОТКРЫТЬ", "id": -1},
	"menu": {"pos": Vector2.ZERO, "r": 44.0, "text": "МЕНЮ", "id": -1},
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_d: float) -> void:
	var vp := get_viewport_rect().size
	if size != vp:
		size = vp
	_btn["peck"]["pos"] = Vector2(vp.x - 150, vp.y - 140)
	_btn["sneak"]["pos"] = Vector2(vp.x - 320, vp.y - 100)
	_btn["use"]["pos"] = Vector2(vp.x - 130, vp.y - 320)
	_btn["use"]["text"] = use_text
	_btn["menu"]["pos"] = Vector2(vp.x - 70, 70)
	queue_redraw()

func get_move() -> Vector2:
	var k := Vector2(
		int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if k != Vector2.ZERO:
		return k.limit_length(1.0)
	return move

func consume_peck() -> bool:
	var p := _peck
	_peck = false
	return p

func is_use_down() -> bool:
	return Input.is_key_pressed(KEY_E) or (use_visible and _btn["use"]["id"] != -1)

func _hit_btn(p: Vector2) -> String:
	for k in _btn:
		if k == "use" and not use_visible:
			continue
		if p.distance_to(_btn[k]["pos"]) <= _btn[k]["r"] + 12.0:
			return k
	return ""

func _input(e: InputEvent) -> void:
	if not enabled:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			var b := _hit_btn(e.position)
			if b != "":
				_btn[b]["id"] = e.index
				if b == "peck":
					_peck = true
				elif b == "sneak":
					sneak = not sneak
				elif b == "menu":
					menu_pressed.emit()
			elif _stick_id == -1 and e.position.x < size.x * 0.55:
				_stick_id = e.index
				_origin = e.position
				_knob = e.position
		else:
			if e.index == _stick_id:
				_stick_id = -1
				move = Vector2.ZERO
			for k in _btn:
				if _btn[k]["id"] == e.index:
					_btn[k]["id"] = -1
	elif e is InputEventScreenDrag and e.index == _stick_id:
		var d: Vector2 = (e.position - _origin).limit_length(STICK_R)
		_knob = _origin + d
		move = d / STICK_R
		if move.length() < 0.15:
			move = Vector2.ZERO
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_SPACE:
			_peck = true
		elif e.keycode == KEY_SHIFT or e.keycode == KEY_C:
			sneak = not sneak

func _draw() -> void:
	if not enabled:
		return
	if _stick_id != -1:
		draw_circle(_origin, STICK_R, Color(1, 1, 1, 0.12))
		draw_arc(_origin, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(_knob, 34, Color(1, 1, 1, 0.45))
	else:
		var h := Vector2(170, size.y - 150)
		draw_arc(h, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.18), 3.0)
		draw_circle(h, 34, Color(1, 1, 1, 0.15))
	var font := ThemeDB.fallback_font
	for k in _btn:
		if k == "use" and not use_visible:
			continue
		var b = _btn[k]
		var on: bool = b["id"] != -1 or (k == "sneak" and sneak)
		draw_circle(b["pos"], b["r"], Color(1, 0.85, 0.2, 0.5) if on else Color(1, 1, 1, 0.15))
		draw_arc(b["pos"], b["r"], 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_string(font, b["pos"] + Vector2(-b["r"], 8), b["text"], HORIZONTAL_ALIGNMENT_CENTER, b["r"] * 2.0, 22, Color.WHITE)
