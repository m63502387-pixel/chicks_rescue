extends Control
# Главное меню. Нажатия обрабатываются через touch-события (работает и мышью на ПК).

const StoryScript = preload("res://story.gd")
const Net = preload("res://net.gd")
const COLORS := [Color(1, 0.85, 0.2), Color(1, 0.45, 0.7), Color(0.4, 0.8, 1),
	Color(0.5, 1, 0.5), Color(0.75, 0.5, 1), Color(1, 0.55, 0.2)]

var t := 0.0
var _btns: Array = []
var _down := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Net.stop(get_tree())
	Input.emulate_mouse_from_touch = false

func _layout() -> void:
	var vp := get_viewport_rect().size
	var w := minf(vp.x * 0.8, 760.0)
	var x := (vp.x - w) / 2.0
	var y0 := vp.y * 0.26
	var h := 92.0
	var step := 108.0
	_btns = [
		{"rect": Rect2(x, y0, w, h), "title": "Сюжет",
			"sub": "Выбери героя: Птенцы или Друн", "scene": "res://chars.tscn", "col": Color(0.2, 0.7, 0.4)},
		{"rect": Rect2(x, y0 + step, w, h), "title": "Обычная игра",
			"sub": "Крадись мимо охраны и освободи маму", "scene": "res://main.tscn", "col": Color(0.2, 0.55, 0.9)},
		{"rect": Rect2(x, y0 + step * 2.0, w, h), "title": "Битва за маму птицу",
			"sub": "Миллионы птенцов из всех вселенных. Выведи раненых!", "scene": "res://battle.tscn", "col": Color(0.85, 0.3, 0.2)},
		{"rect": Rect2(x, y0 + step * 3.0, w, h), "title": "Мультиплеер по LAN",
			"sub": "Играй с друзьями по сети во всех режимах", "scene": "res://lan.tscn", "col": Color(0.55, 0.35, 0.85)},
	]

func _process(delta: float) -> void:
	t += delta
	_layout()
	queue_redraw()

func _go(i: int) -> void:
	get_tree().change_scene_to_file(_btns[i]["scene"])

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_down = -1
			for i in _btns.size():
				if _btns[i]["rect"].has_point(e.position):
					_down = i
		else:
			if _down != -1 and _btns[_down]["rect"].has_point(e.position):
				_go(_down)
			_down = -1
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_1:
			_go(0)
		elif e.keycode == KEY_2:
			_go(1)
		elif e.keycode == KEY_3:
			_go(2)
		elif e.keycode == KEY_4:
			_go(3)

func _chick(p: Vector2, s: float, col: Color) -> void:
	draw_circle(p, 30.0 * s, col)
	draw_circle(p + Vector2(10, -8) * s, 4.0 * s, Color.BLACK)
	draw_colored_polygon(PackedVector2Array([p + Vector2(26, -4) * s, p + Vector2(46, 4) * s, p + Vector2(26, 12) * s]), Color(1, 0.55, 0.1))

func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.08, 0.16))
	draw_rect(Rect2(0, vp.y * 0.8, vp.x, vp.y * 0.2), Color(0.1, 0.17, 0.2))
	for i in 40:
		var p := Vector2(fposmod(i * 197.0, vp.x), fposmod(i * 83.0, vp.y * 0.6))
		draw_circle(p, 1.5 + (i % 3), Color(1, 1, 1, 0.45 + 0.4 * sin(t * 2.0 + i)))

	var ty := vp.y * 0.16 + sin(t * 2.0) * 4.0
	draw_string(font, Vector2(0, ty), "ПТЕНЦЫ СПАСАЮТ МАМУ", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 64, Color(1, 0.9, 0.3))
	draw_string(font, Vector2(0, ty + 40), "стелс-приключение", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 24, Color(1, 1, 1, 0.7))

	for i in _btns.size():
		var b: Dictionary = _btns[i]
		var r: Rect2 = b["rect"]
		var c: Color = b["col"]
		var pressed := i == _down
		if pressed:
			r = r.grow(-4.0)
		draw_rect(r, c.lightened(0.15) if pressed else c.darkened(0.45))
		draw_rect(r, c, false, 4.0)
		draw_string(font, r.position + Vector2(0, 46), b["title"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 36, Color.WHITE)
		draw_string(font, r.position + Vector2(0, 80), b["sub"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color(1, 1, 1, 0.8))

	for i in 6:
		_chick(Vector2(vp.x * (0.08 + 0.1 * i), vp.y * 0.91 + sin(t * 3.0 + i) * 10.0), 1.0, COLORS[i])
	_chick(Vector2(vp.x * 0.88, vp.y * 0.86 + sin(t * 2.0) * 6.0), 2.0, Color(0.8, 0.4, 0.15))
