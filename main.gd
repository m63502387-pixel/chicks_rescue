extends Node3D
# Строит весь уровень, UI и логику победы/поражения кодом.

const PlayerScript = preload("res://player.gd")
const GuardScript = preload("res://guard.gd")
const Net = preload("res://net.gd")
const ControlsScript = preload("res://touch_controls.gd")

const CAM_OFFSET := Vector3(0, 12.0, 8.4)
const CAGE_POS := Vector3(16, 0, -11)
const FREE_TIME := 2.0  # сколько секунд держать "ОТКРЫТЬ"

var player
var boss
var cam: Camera3D
var controls
var cage: StaticBody3D
var cage_col: CollisionShape3D
var mother: Node3D
var lbl_chicks: Label
var lbl_state: Label
var lbl_obj: Label
var msg: Label
var bar: ProgressBar
var overlay: ColorRect
var end_lbl: Label
var msg_t := 0.0
var free_t := 0.0
var game_over := false
var can_restart := false
var restarting := false

func _ready() -> void:
	_build_env()
	_build_level()
	_build_cage()
	_build_ui()
	_spawn()
	cam = Camera3D.new()
	cam.rotation_degrees = Vector3(-55, 0, 0)
	cam.fov = 55
	add_child(cam)
	cam.global_position = player.global_position + CAM_OFFSET
	cam.make_current()
	Net.attach(self, player, "main")
	show_msg("Крадись (ТИХО) и бей клювом со спины!", 5.0)

# ---------- мир ----------
func _mi(mesh: PrimitiveMesh, col: Color, pos: Vector3) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

func _box(pos: Vector3, size: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	b.position = pos
	var bm := BoxMesh.new()
	bm.size = size
	b.add_child(_mi(bm, col, Vector3.ZERO))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.7, 0.85)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true  # если тормозит на телефоне — поставь false
	add_child(sun)

func _build_level() -> void:
	var wall := Color(0.38, 0.42, 0.5)
	_box(Vector3(0, -0.1, 0), Vector3(42, 0.2, 32), Color(0.25, 0.32, 0.28))
	# внешние стены
	_box(Vector3(0, 1.25, -15.5), Vector3(42, 2.5, 1), wall)
	_box(Vector3(0, 1.25, 15.5), Vector3(42, 2.5, 1), wall)
	_box(Vector3(-20.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	_box(Vector3(20.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	# внутренние стены — получается "змейка"
	_box(Vector3(-10, 1.25, -5), Vector3(1, 2.5, 20), wall)
	_box(Vector3(0, 1.25, 6), Vector3(1, 2.5, 18), wall)
	_box(Vector3(10, 1.25, -5.5), Vector3(1, 2.5, 19), wall)
	# ящики-укрытия (закрывают обзор охране)
	for p in [Vector2(-14, 4), Vector2(-15, -6), Vector2(-7.5, -2), Vector2(-2.5, 5), Vector2(2.5, 3),
			Vector2(7.5, -6), Vector2(15, 6), Vector2(15, -5), Vector2(19, -3)]:
		_box(Vector3(p.x, 1, p.y), Vector3(2, 2, 2), Color(0.55, 0.38, 0.2))

func _label3d(text: String, pos: Vector3, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l

func _build_cage() -> void:
	cage = StaticBody3D.new()
	cage.position = CAGE_POS
	cage_col = CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.8, 2.4, 2.8)
	cage_col.shape = sh
	cage_col.position.y = 1.2
	cage.add_child(cage_col)
	var base := CylinderMesh.new()
	base.top_radius = 1.5
	base.bottom_radius = 1.5
	base.height = 0.2
	cage.add_child(_mi(base, Color(0.3, 0.3, 0.35), Vector3(0, 0.1, 0)))
	var top := CylinderMesh.new()
	top.top_radius = 1.4
	top.bottom_radius = 1.4
	top.height = 0.12
	cage.add_child(_mi(top, Color(0.3, 0.3, 0.35), Vector3(0, 2.35, 0)))
	for i in 12:
		var a := TAU * i / 12.0
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 2.3
		cage.add_child(_mi(cm, Color(0.75, 0.75, 0.8), Vector3(cos(a) * 1.3, 1.2, sin(a) * 1.3)))
	add_child(cage)

	mother = Node3D.new()
	mother.position = CAGE_POS
	mother.rotation_degrees.y = 180.0
	add_child(mother)
	var bm := SphereMesh.new()
	bm.radius = 0.8
	bm.height = 1.6
	mother.add_child(_mi(bm, Color(0.8, 0.4, 0.15), Vector3(0, 0.9, 0)))
	var hm := SphereMesh.new()
	hm.radius = 0.45
	hm.height = 0.9
	mother.add_child(_mi(hm, Color(0.85, 0.45, 0.18), Vector3(0, 1.65, -0.5)))
	var beak := CylinderMesh.new()
	beak.top_radius = 0.0
	beak.bottom_radius = 0.17
	beak.height = 0.45
	var b := _mi(beak, Color(1, 0.55, 0.1), Vector3(0, 1.6, -1.05))
	b.rotation_degrees.x = -90.0
	mother.add_child(b)
	for sx in [-1, 1]:
		var eye := SphereMesh.new()
		eye.radius = 0.07
		eye.height = 0.14
		mother.add_child(_mi(eye, Color.BLACK, Vector3(0.22 * sx, 1.8, -0.85)))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.6, 0.12, 0.9)
	var t := _mi(tail, Color(0.65, 0.3, 0.1), Vector3(0, 1.1, 0.85))
	t.rotation_degrees.x = 25.0
	mother.add_child(t)
	add_child(_label3d("МАМА", CAGE_POS + Vector3(0, 3.6, 0), 80, Color(1, 0.9, 0.4)))

func _spawn_guard(pts: Array, is_boss_flag := false):
	var g = GuardScript.new()
	g.is_boss = is_boss_flag
	g.player = player
	g.waypoints = pts
	g.position = pts[0]
	g.knocked_out.connect(_on_ko)
	add_child(g)
	return g

func _spawn() -> void:
	player = PlayerScript.new()
	player.controls = controls
	player.position = Vector3(-17, 0, 12)
	player.hurt.connect(_on_hurt)
	player.died.connect(_lose)
	add_child(player)
	_spawn_guard([Vector3(-5, 0, 12), Vector3(-5, 0, -10)])
	_spawn_guard([Vector3(5, 0, -12), Vector3(5, 0, 10)])
	_spawn_guard([Vector3(12, 0, 10), Vector3(18, 0, 10), Vector3(18, 0, 2), Vector3(12, 0, 2)])
	boss = _spawn_guard([Vector3(13, 0, -8), Vector3(13, 0, -14), Vector3(19, 0, -14), Vector3(19, 0, -8)], true)

# ---------- интерфейс ----------
func _label(parent: Control, pos: Vector2, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	controls = ControlsScript.new()
	layer.add_child(controls)
	controls.menu_pressed.connect(func(): get_tree().change_scene_to_file("res://menu.tscn"))
	var ui := Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	lbl_chicks = _label(ui, Vector2(24, 14), 28)
	lbl_chicks.text = "Птенцы: 3 / 3"
	lbl_state = _label(ui, Vector2(24, 50), 22)
	lbl_obj = _label(ui, Vector2(0, 14), 20, Color(1, 0.95, 0.7))
	lbl_obj.anchor_right = 1.0
	lbl_obj.offset_left = 300
	lbl_obj.offset_right = -130
	lbl_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_obj.text = "Найди маму в клетке. Ключ у главного агента."
	msg = _label(ui, Vector2(0, 90), 30, Color(1, 0.9, 0.4))
	msg.anchor_right = 1.0
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	bar = ProgressBar.new()
	bar.anchor_left = 0.35
	bar.anchor_right = 0.65
	bar.anchor_top = 0.65
	bar.anchor_bottom = 0.65
	bar.offset_bottom = 26
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.visible = false
	ui.add_child(bar)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	ui.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_lbl = Label.new()
	end_lbl.add_theme_font_size_override("font_size", 40)
	end_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_child(end_lbl)
	end_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_msg(t: String, dur := 2.5) -> void:
	msg.text = t
	msg_t = dur
	msg.modulate.a = 1.0

func _show_end(t: String) -> void:
	game_over = true
	overlay.visible = true
	end_lbl.text = t + "\n\nНажми на экран, чтобы сыграть снова"
	get_tree().create_timer(1.2).timeout.connect(func(): can_restart = true)

# ---------- события ----------
func _on_hurt(left: int) -> void:
	lbl_chicks.text = "Птенцы: %d / 3" % left
	if left > 0:
		show_msg("Птенца поймали! Осталось: %d" % left, 2.0)

func _on_ko(silent: bool, was_boss: bool) -> void:
	if was_boss:
		show_msg("Агент повержен! Ключ у тебя — освободи маму!", 4.0)
		lbl_obj.text = "Держи ОТКРЫТЬ у клетки, чтобы освободить маму."
	elif silent:
		show_msg("Тихий нокаут!", 2.0)
	else:
		show_msg("Агент нокаутирован!", 2.0)

func _lose() -> void:
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(false)
	_show_end("ПОРАЖЕНИЕ\nВсех птенцов поймали...")

func _win() -> void:
	player.set_physics_process(false)
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(false)
	cage.visible = false
	cage_col.set_deferred("disabled", true)
	bar.visible = false
	controls.use_visible = false
	var t := create_tween().set_loops()
	t.tween_property(mother, "position:y", 1.2, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mother, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_show_end("ПОБЕДА!\nМама свободна — птенцы спасли её!")

func _input(e: InputEvent) -> void:
	if not game_over or not can_restart or restarting:
		return
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventKey and e.pressed):
		restarting = true
		get_tree().reload_current_scene()

func _process(delta: float) -> void:
	var target: Vector3 = player.global_position + CAM_OFFSET
	cam.global_position = cam.global_position.lerp(target, minf(1.0, 6.0 * delta))
	if msg_t > 0.0:
		msg_t -= delta
		msg.modulate.a = clampf(msg_t, 0.0, 1.0)
		if msg_t <= 0.0:
			msg.text = ""
	if game_over:
		return

	var alert := false
	for g in get_tree().get_nodes_in_group("guards"):
		if g.is_alert():
			alert = true
			break
	lbl_state.text = "ТРЕВОГА!" if alert else "Скрытно"
	lbl_state.add_theme_color_override("font_color", Color(1, 0.3, 0.3) if alert else Color(0.5, 1, 0.5))

	var near: bool = player.alive and player.global_position.distance_to(CAGE_POS) < 3.8
	controls.use_visible = near
	if near and controls.is_use_down():
		if not boss.is_down():
			free_t = 0.0
			bar.visible = false
			show_msg("Клетка заперта! Ключ у главного агента.", 1.5)
		else:
			free_t += delta / FREE_TIME
			bar.visible = true
			bar.value = free_t
			if free_t >= 1.0:
				_win()
	else:
		free_t = maxf(0.0, free_t - delta)
		bar.visible = free_t > 0.0
		bar.value = free_t
