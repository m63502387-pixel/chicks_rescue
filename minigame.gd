extends Control
# Мини-игры взлома: "simon" (код замка дверей) и "pins" (замок клетки мамы).

signal done(success: bool)

const COLORS := [Color(0.9, 0.25, 0.25), Color(0.25, 0.8, 0.35), Color(0.3, 0.5, 1.0), Color(1.0, 0.85, 0.2)]
const PIN_COUNT := 4

var mode := ""
var running := false
var closing := false
var close_t := 0.0
var title := ""
var hint := ""
var msg := ""
var msg_t := 0.0
var flash_t := 0.0
# simon
var seq: Array = []
var step := 0
var showing := false
var show_i := -1
var show_t := 0.0
var lit := -1
var press_t := 0.0
var press_i := -1
# pins
var pins := 0
var mark := 0.0
var dir := 1.0
var zone_c := 0.5
var zone_w := 0.25
var speed := 0.8

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func start(m: String) -> void:
	var is_phone := m == "phone"
	if is_phone:
		m = "simon"
	mode = m
	running = true
	closing = false
	visible = true
	msg = ""
	if m == "simon":
		title = "ВЗЛОМ ЗАМКА ДВЕРЕЙ"
		hint = "Запомни комбинацию и повтори её"
		_new_seq(4)
		if is_phone:
			title = "РАЗБЛОКИРОВКА ТЕЛЕФОНА"
			hint = "Повтори код, чтобы разблокировать телефон агента"
	else:
		title = "ВЗЛОМ КЛЕТКИ МАМЫ"
		hint = "Нажми, когда метка в зелёной зоне"
		pins = 0
		_new_pin()

func _new_seq(n: int) -> void:
	seq.clear()
	for i in n:
		seq.append(randi() % 4)
	_replay(0.8)

func _replay(delay: float) -> void:
	step = 0
	showing = true
	show_i = -1
	show_t = delay
	lit = -1

func _new_pin() -> void:
	zone_w = 0.26 - 0.04 * pins
	zone_c = randf_range(0.2, 0.8)
	speed = 0.7 + 0.2 * pins
	mark = 0.0
	dir = 1.0

func _btn_rects() -> Array:
	var vp := get_viewport_rect().size
	var s := minf(vp.x * 0.2, 170.0)
	var gap := 24.0
	var x0 := (vp.x - (s * 4.0 + gap * 3.0)) / 2.0
	var arr: Array = []
	for i in 4:
		arr.append(Rect2(x0 + i * (s + gap), vp.y * 0.45, s, s))
	return arr

func _cancel_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(vp.x - 160, 20, 140, 60)

func _finish(ok: bool) -> void:
	closing = true
	close_t = 0.9
	msg = "ЗАМОК ВЗЛОМАН!" if ok else ""
	msg_t = 2.0

func _close(ok: bool) -> void:
	running = false
	closing = false
	visible = false
	done.emit(ok)

func _press(i: int) -> void:
	press_i = i
	press_t = 0.2
	if i == seq[step]:
		step += 1
		if step >= seq.size():
			_finish(true)
	else:
		msg = "Неверно! Смотри ещё раз"
		msg_t = 1.2
		flash_t = 0.3
		_replay(1.0)

func _attempt() -> void:
	if absf(mark - zone_c) <= zone_w / 2.0:
		pins += 1
		if pins >= PIN_COUNT:
			_finish(true)
		else:
			msg = "Штифт встал!"
			msg_t = 0.8
			_new_pin()
	else:
		pins = maxi(0, pins - 1)
		msg = "Мимо!"
		msg_t = 0.8
		flash_t = 0.25
		_new_pin()

func _process(delta: float) -> void:
	if not running:
		return
	var vp := get_viewport_rect().size
	if size != vp:
		size = vp
	flash_t = maxf(0.0, flash_t - delta)
	press_t = maxf(0.0, press_t - delta)
	msg_t = maxf(0.0, msg_t - delta)
	if closing:
		close_t -= delta
		if close_t <= 0.0:
			_close(true)
		queue_redraw()
		return
	if mode == "simon":
		if showing:
			show_t -= delta
			if show_t <= 0.0:
				if lit != -1:
					lit = -1
					show_t = 0.2
				else:
					show_i += 1
					if show_i >= seq.size():
						showing = false
					else:
						lit = seq[show_i]
						show_t = 0.45
	else:
		mark += dir * speed * delta
		if mark >= 1.0:
			mark = 1.0
			dir = -1.0
		elif mark <= 0.0:
			mark = 0.0
			dir = 1.0
	queue_redraw()

func _input(e: InputEvent) -> void:
	if not running or closing:
		return
	var pos := Vector2(-1000, -1000)
	var tapped := false
	var key := -1
	if e is InputEventScreenTouch and e.pressed:
		pos = e.position
		tapped = true
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			_close(false)
			return
		if e.keycode >= KEY_1 and e.keycode <= KEY_4:
			key = e.keycode - KEY_1
		elif e.keycode == KEY_SPACE:
			tapped = true
	if tapped and _cancel_rect().has_point(pos):
		_close(false)
		return
	if mode == "simon":
		if showing:
			return
		var idx := key
		if tapped:
			var rects := _btn_rects()
			for i in 4:
				if rects[i].has_point(pos):
					idx = i
		if idx >= 0:
			_press(idx)
	elif tapped or key >= 0:
		_attempt()

func _draw() -> void:
	if not running:
		return
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.05, 0.1, 0.94))
	draw_string(font, Vector2(0, vp.y * 0.14), title, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 44, Color(0.5, 1, 0.7))
	draw_string(font, Vector2(0, vp.y * 0.14 + 40), hint, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 24, Color(1, 1, 1, 0.8))
	var cr := _cancel_rect()
	draw_rect(cr, Color(1, 1, 1, 0.12))
	draw_rect(cr, Color(1, 1, 1, 0.5), false, 3.0)
	draw_string(font, cr.position + Vector2(0, 38), "НАЗАД", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 24, Color.WHITE)

	if mode == "simon":
		var rects := _btn_rects()
		for i in 4:
			var on := lit == i or (press_t > 0.0 and press_i == i)
			var c: Color = COLORS[i]
			draw_rect(rects[i], c.lightened(0.45) if on else c.darkened(0.45))
			draw_rect(rects[i], c, false, 6.0 if on else 3.0)
		var n := seq.size()
		for i in n:
			var p := Vector2(vp.x / 2.0 + (i - (n - 1) / 2.0) * 44.0, vp.y * 0.3)
			draw_circle(p, 14.0, Color(0.3, 1, 0.5) if i < step else Color(1, 1, 1, 0.2))
		var st := "Смотри..." if showing else "Повторяй!"
		draw_string(font, Vector2(0, vp.y * 0.8), st, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 32, Color(1, 1, 1, 0.9))
	else:
		for i in PIN_COUNT:
			var p := Vector2(vp.x / 2.0 + (i - (PIN_COUNT - 1) / 2.0) * 70.0, vp.y * 0.3)
			draw_circle(p, 22.0, Color(0.3, 1, 0.5) if i < pins else Color(1, 1, 1, 0.2))
		var bx := vp.x * 0.15
		var bw := vp.x * 0.7
		var by := vp.y * 0.45
		draw_rect(Rect2(bx, by, bw, 70), Color(0.15, 0.17, 0.25))
		draw_rect(Rect2(bx + (zone_c - zone_w / 2.0) * bw, by, zone_w * bw, 70), Color(0.2, 0.8, 0.35, 0.85))
		draw_rect(Rect2(bx, by, bw, 70), Color(1, 1, 1, 0.5), false, 3.0)
		draw_rect(Rect2(bx + mark * bw - 4, by - 12, 8, 94), Color.WHITE)
		draw_circle(Vector2(vp.x / 2.0, vp.y * 0.78), 80.0, Color(1, 0.85, 0.2, 0.35))
		draw_arc(Vector2(vp.x / 2.0, vp.y * 0.78), 80.0, 0, TAU, 48, Color(1, 0.85, 0.2), 4.0)
		draw_string(font, Vector2(vp.x / 2.0 - 80, vp.y * 0.78 + 10), "ВЗЛОМ", HORIZONTAL_ALIGNMENT_CENTER, 160.0, 30, Color.WHITE)

	if msg_t > 0.0:
		draw_string(font, Vector2(0, vp.y * 0.65), msg, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 34, Color(1, 0.9, 0.4))
	if flash_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 0.1, 0.1, flash_t))
