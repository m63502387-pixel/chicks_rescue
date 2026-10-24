extends Control
# Выбор персонажа для сюжета: Птенцы (открыты сразу) и Друн (открывается после сюжета птенцов).

const StoryScript = preload("res://story.gd")
const DrunScript = preload("res://drun.gd")
const Save = preload("res://save.gd")

var t := 0.0
var _cards: Array = []
var _back: Rect2
var _down := -2
var unlocked := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	unlocked = Save.is_drun_unlocked()

func _layout() -> void:
	var vp := get_viewport_rect().size
	var w := minf(vp.x * 0.4, 440.0)
	var h := minf(vp.y * 0.55, 380.0)
	var gap := 36.0
	var x0 := (vp.x - (w * 2.0 + gap)) / 2.0
	var y := vp.y * 0.27
	_cards = [
		{"rect": Rect2(x0, y, w, h), "title": "ПТЕНЦЫ", "col": Color(1, 0.85, 0.2), "open": true,
			"sub": "Спаси маму птицу из лап Интерпола"},
		{"rect": Rect2(x0 + w + gap, y, w, h), "title": "ДРУН", "col": Color(0.4, 0.8, 1.0), "open": unlocked,
			"sub": "Выследи фургон и вырубай Интерпол" if unlocked else "Закрыто. Пройди сюжет за птенцов"},
	]
	_back = Rect2(24, 24, 150, 56)

func _process(delta: float) -> void:
	t += delta
	_layout()
	queue_redraw()

func _pick(i: int) -> void:
	if i == 0:
		StoryScript.checkpoint = 0
		get_tree().change_scene_to_file("res://story.tscn")
	elif i == 1 and unlocked:
		DrunScript.dcheckpoint = 10
		get_tree().change_scene_to_file("res://drun.tscn")

func _go_back() -> void:
	get_tree().change_scene_to_file("res://menu.tscn")

func _hit(p: Vector2) -> int:
	if _back.has_point(p):
		return -1
	for i in _cards.size():
		if _cards[i]["rect"].has_point(p):
			return i
	return -2

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_down = _hit(e.position)
		else:
			var up := _hit(e.position)
			if up == _down and up != -2:
				if up == -1:
					_go_back()
				else:
					_pick(up)
			_down = -2
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_1:
			_pick(0)
		elif e.keycode == KEY_2:
			_pick(1)
		elif e.keycode == KEY_ESCAPE:
			_go_back()

func _draw_chick(p: Vector2, s: float, col: Color) -> void:
	draw_circle(p, 34.0 * s, col)
	draw_circle(p + Vector2(11, -9) * s, 4.5 * s, Color.BLACK)
	draw_colored_polygon(PackedVector2Array([p + Vector2(30, -4) * s, p + Vector2(52, 5) * s, p + Vector2(30, 14) * s]), Color(1, 0.55, 0.1))

func _draw_drone(p: Vector2, s: float, col: Color) -> void:
	draw_rect(Rect2(p - Vector2(30, 12) * s, Vector2(60, 24) * s), Color(0.16, 0.18, 0.24))
	draw_line(p + Vector2(-50, -22) * s, p + Vector2(50, 22) * s, Color(0.4, 0.42, 0.5), 4.0 * s)
	draw_line(p + Vector2(-50, 22) * s, p + Vector2(50, -22) * s, Color(0.4, 0.42, 0.5), 4.0 * s)
	for c in [Vector2(-50, -22), Vector2(50, -22), Vector2(-50, 22), Vector2(50, 22)]:
		draw_circle(p + c * s, 17.0 * s, Color(col.r, col.g, col.b, 0.55))
	draw_circle(p + Vector2(0, 2) * s, 7.0 * s, Color(1, 0.2, 0.2))

func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.08, 0.16))
	for i in 40:
		var p := Vector2(fposmod(i * 197.0, vp.x), fposmod(i * 83.0, vp.y * 0.9))
		draw_circle(p, 1.5 + (i % 3), Color(1, 1, 1, 0.4 + 0.4 * sin(t * 2.0 + i)))
	draw_string(font, Vector2(0, vp.y * 0.14), "ВЫБЕРИ ПЕРСОНАЖА", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 52, Color(1, 0.9, 0.3))
	draw_rect(_back, Color(0.2, 0.2, 0.3))
	draw_rect(_back, Color(0.6, 0.6, 0.8), false, 3.0)
	draw_string(font, _back.position + Vector2(0, 37), "НАЗАД", HORIZONTAL_ALIGNMENT_CENTER, _back.size.x, 26, Color.WHITE)
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var r: Rect2 = c["rect"]
		var col: Color = c["col"]
		var open: bool = c["open"]
		if i == _down:
			r = r.grow(-4.0)
		var base := col if open else Color(0.45, 0.45, 0.5)
		draw_rect(r, base.darkened(0.6))
		draw_rect(r, base, false, 5.0)
		var cen := r.position + Vector2(r.size.x / 2.0, r.size.y * 0.38)
		if i == 0:
			_draw_chick(cen + Vector2(-40, 8 + sin(t * 3.0) * 6.0), 1.5, Color(1, 0.85, 0.2))
			_draw_chick(cen + Vector2(40, 20 + sin(t * 3.0 + 1.0) * 6.0), 1.0, Color(1, 0.45, 0.7))
		else:
			_draw_drone(cen + Vector2(0, sin(t * 3.0) * 6.0), 1.6, Color(0.7, 0.9, 1.0) if open else Color(0.5, 0.5, 0.55))
			if not open:
				draw_rect(Rect2(cen + Vector2(-26, -4), Vector2(52, 42)), Color(0.9, 0.75, 0.2))
				draw_arc(cen + Vector2(0, -4), 16.0, PI, TAU, 16, Color(0.9, 0.75, 0.2), 8.0)
				draw_circle(cen + Vector2(0, 17), 6.0, Color(0.2, 0.15, 0.0))
		draw_string(font, r.position + Vector2(0, r.size.y * 0.72), c["title"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 44, Color.WHITE if open else Color(0.75, 0.75, 0.8))
		draw_string(font, r.position + Vector2(12, r.size.y * 0.72 + 14), c["sub"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 24, 20, Color(1, 1, 1, 0.8), 2)
