extends Node3D
# СЮЖЕТ. Каждая глава — отдельная загрузка сцены, прогресс хранится в checkpoint.
# 0 База (бесшумно) -> 1 Вентиляция -> 2 Фургон (запрыгнуть) -> 3 Грузовик (взлом, мама улетает, её подстреливают)
# -> 4 Поляна (вылечить маму и отбиться от Интерпола; птенцов ловят) -> 5 Камера (побег, мама)
# -> 6 Гараж (собрать машину) -> 7 Дорога (рулить, не врезаться; мама улетает с документами, финал)

const PlayerScript = preload("res://player.gd")
const GuardScript = preload("res://guard.gd")
const ControlsScript = preload("res://touch_controls.gd")
const MiniScript = preload("res://minigame.gd")
const Build = preload("res://build.gd")
const Net = preload("res://net.gd")
const Save = preload("res://save.gd")
const DrunAI = preload("res://drun_ai.gd")

static var checkpoint := 0

const CAM_OFFSET := Vector3(0, 12.0, 8.4)
const MAX_CHICKS := 5
const CELL := 2.5
const COLORS := [Color(1, 0.85, 0.2), Color(1, 0.45, 0.7), Color(0.4, 0.8, 1), Color(0.5, 1, 0.5), Color(0.75, 0.5, 1)]

var phase := 0
var start_hp := 5
var player
var controls
var mini
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var time := 0.0

var ui: Control
var lbl_chicks: Label
var lbl_state: Label
var lbl_obj: Label
var lbl_timer: Label
var lbl_title: Label
var lbl_sub: Label
var msg: Label
var fade: ColorRect
var overlay: ColorRect
var end_lbl: Label
var msg_t := 0.0

var busy := false
var cutscene := false
var cam_mode := "free"
var cam_pos := Vector3.ZERO
var cam_target := Vector3.ZERO
var cam_tw: Tween
var game_over := false
var can_restart := false
var restarting := false
var finished := false
var pick_cd := 0.0

# глава 0
var hatch_pos := Vector3(19.5, 0, -13.5)
# глава 1
var jets: Array = []
var vent_ox := 0.0
var vent_oz := 0.0
var exit_pos := Vector3.ZERO
# глава 2
var van: StaticBody3D
var gate: StaticBody3D
var yard_time := 50.0
# глава 3
var tr := Vector3(6, 0, -4)
var door_pos := Vector3.ZERO
var cage_pos := Vector3.ZERO
var door_l: StaticBody3D
var door_r: StaticBody3D
var door_light: MeshInstance3D
var door_lbl: Label3D
var door_open := false
var cage_opened := false
var cage: StaticBody3D
var mother_root: Node3D
var mother: Node3D
var mama_lbl: Label3D
var mini_kind := ""
var drun_ai: Node3D
var drun_t := 12.0
var drun_kills := 0
var drun_target: Node3D
var flap_tw: Tween
# глава 5 (камера)
var cell_door: StaticBody3D
# глава 4 (поляна)
var herbs: Array = []
var herb_count := 0
var heal := 0
var heal_cd := 0.0
var wave_t := 4.0
var field_done := false
var mother_pos := Vector3.ZERO
# глава 6 (гараж)
var car: Node3D
var parts: Array = []
var carried: Array = []
var installed := 0
var install_cd := 0.0
# глава 7 (дорога)
const ROAD_LEN := 460.0
const ROAD_HALF := 6.0
var car_speed := 0.0
var car_hp := 5
var car_inv := 0.0
var drive_t := 0.0
var obstacles: Array = []
var docs: Node3D
var car_chicks: Array = []

func _ready() -> void:
	randomize()
	phase = _start_phase()
	_build_env()
	_build_ui()
	cam = Camera3D.new()
	cam.rotation_degrees = Vector3(-55, 0, 0)
	cam.fov = 55
	add_child(cam)
	cam.make_current()
	match phase:
		0: _phase_base()
		1: _phase_vent()
		2: _phase_yard()
		4: _phase_field()
		5: _phase_cell()
		6: _phase_garage()
		7: _phase_drive()
		3: _phase_truck()
		_: _phase_extra()
	_hud()
	Net.attach(self, player, "story%d" % phase)
	var t := create_tween()
	fade.color.a = 1.0
	t.tween_property(fade, "color:a", 0.0, 0.8)

# ---------- общее ----------
func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.shadow_enabled = true  # если тормозит на телефоне — поставь false
	add_child(sun)

func _set_sky(bg: Color, amb: Color, amb_e: float, sun_e: float) -> void:
	env.background_color = bg
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	sun.light_energy = sun_e

func _label(pos: Vector2, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	ui.add_child(l)
	return l

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	controls = ControlsScript.new()
	layer.add_child(controls)
	controls.menu_pressed.connect(func(): get_tree().change_scene_to_file("res://menu.tscn"))
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	lbl_chicks = _label(Vector2(24, 14), 28)
	lbl_state = _label(Vector2(24, 50), 22)
	lbl_obj = _label(Vector2(0, 14), 20, Color(1, 0.95, 0.7))
	lbl_obj.anchor_right = 1.0
	lbl_obj.offset_left = 300
	lbl_obj.offset_right = -130
	lbl_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_timer = _label(Vector2(0, 60), 34, Color(1, 0.5, 0.3))
	lbl_timer.anchor_right = 1.0
	lbl_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_timer.visible = false
	lbl_title = _label(Vector2(0, 0), 46, Color(1, 0.9, 0.4))
	lbl_title.anchor_right = 1.0
	lbl_title.anchor_top = 0.3
	lbl_title.anchor_bottom = 0.3
	lbl_title.offset_top = 0
	lbl_title.offset_bottom = 60
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.modulate.a = 0.0
	msg = _label(Vector2(0, 110), 28, Color(1, 0.9, 0.4))
	msg.anchor_right = 1.0
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub = _label(Vector2(0, 0), 32)
	lbl_sub.anchor_top = 1.0
	lbl_sub.anchor_bottom = 1.0
	lbl_sub.anchor_right = 1.0
	lbl_sub.offset_top = -120
	lbl_sub.offset_bottom = -60
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	var l2 := CanvasLayer.new()
	l2.layer = 5
	add_child(l2)
	mini = MiniScript.new()
	l2.add_child(mini)
	mini.done.connect(_on_mini_done)

func show_msg(t: String, dur := 2.5) -> void:
	msg.text = t
	msg_t = dur
	msg.modulate.a = 1.0

func _sub(t: String) -> void:
	lbl_sub.text = t
	lbl_sub.modulate.a = 0.0
	create_tween().tween_property(lbl_sub, "modulate:a", 1.0, 0.4)

func _chapter(title: String, hint: String) -> void:
	lbl_title.text = title
	var t := create_tween()
	t.tween_property(lbl_title, "modulate:a", 1.0, 0.5)
	t.tween_interval(2.5)
	t.tween_property(lbl_title, "modulate:a", 0.0, 0.8)
	show_msg(hint, 6.0)

# --- точки расширения (переопределяются в drun.gd) ---
func _start_phase() -> int:
	return checkpoint

func _new_player():
	return PlayerScript.new()

func _phase_extra() -> void:
	_phase_truck()

func _update_extra(delta: float) -> void:
	_update_truck(delta)

func _hud() -> void:
	if player:
		lbl_chicks.text = "Птенцы: %d / %d" % [player.chicks, MAX_CHICKS]

func _hud_visible(v: bool) -> void:
	for l in [lbl_chicks, lbl_state, lbl_obj]:
		l.visible = v

func _add_player(pos: Vector3) -> void:
	player = _new_player()
	player.controls = controls
	player.chicks = start_hp
	player.position = pos
	player.hurt.connect(_on_hurt)
	player.died.connect(_lose)
	add_child(player)
	cam.global_position = pos + CAM_OFFSET

func _spawn_guard(pts: Array, hear := 6.5):
	var g = GuardScript.new()
	g.player = player
	g.waypoints = pts
	g.position = pts[0]
	g.hearing = hear
	g.knocked_out.connect(_on_ko)
	add_child(g)
	return g

func _fd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _fade_to(a: float, dur: float) -> Tween:
	var t := create_tween()
	t.tween_property(fade, "color:a", a, dur)
	return t

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _move_cam(pos: Vector3, tgt: Vector3, dur: float) -> void:
	cam_mode = "free"
	if cam_tw:
		cam_tw.kill()
	cam_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam_tw.tween_property(self, "cam_pos", pos, dur)
	cam_tw.tween_property(self, "cam_target", tgt, dur)

func _begin_cutscene() -> void:
	busy = true
	cutscene = true
	controls.enabled = false
	controls.visible = false
	controls.use_visible = false
	_hud_visible(false)
	lbl_timer.visible = false
	player.set_physics_process(false)
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(false)
	cam_mode = "free"
	cam_pos = cam.global_position
	cam_target = player.global_position

func _goto(next: int) -> void:
	if busy:
		return
	busy = true
	checkpoint = next
	controls.enabled = false
	controls.use_visible = false
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.6)
	t.tween_callback(func(): get_tree().reload_current_scene())

func _update_state() -> void:
	var alert := false
	for g in get_tree().get_nodes_in_group("guards"):
		if g.is_alert():
			alert = true
			break
	var moving: bool = player.velocity.length() > 1.0
	if alert:
		lbl_state.text = "ТРЕВОГА!"
		lbl_state.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	elif moving and not player.sneaking:
		lbl_state.text = "ШУМ! Включи ТИХО"
		lbl_state.add_theme_color_override("font_color", Color(1, 0.7, 0.2))
	else:
		lbl_state.text = "Тихо"
		lbl_state.add_theme_color_override("font_color", Color(0.5, 1, 0.5))

func _on_hurt(left: int) -> void:
	_hud()
	if left > 0:
		show_msg("Птенца поймали! Осталось: %d" % left, 2.0)

func _on_ko(silent: bool, _boss: bool) -> void:
	show_msg("Тихий нокаут!" if silent else "Агент нокаутирован!", 2.0)

func _show_end(t: String, tail: String) -> void:
	game_over = true
	overlay.visible = true
	end_lbl.text = t + "\n\n" + tail
	get_tree().create_timer(1.2).timeout.connect(func(): can_restart = true)

func _lose() -> void:
	_stop_all()
	_show_end("ПОРАЖЕНИЕ\nВсех птенцов поймали...", "Нажми, чтобы попробовать снова")

func _stop_all() -> void:
	player.set_physics_process(false)
	controls.use_visible = false
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(false)

func _input(e: InputEvent) -> void:
	if not game_over or not can_restart or restarting:
		return
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventKey and e.pressed):
		restarting = true
		if finished:
			checkpoint = 0
			get_tree().change_scene_to_file("res://menu.tscn")
		else:
			get_tree().reload_current_scene()

# ---------- глава 0: база ----------
func _phase_base() -> void:
	_set_sky(Color(0.04, 0.05, 0.09), Color(0.55, 0.6, 0.8), 0.6, 0.6)
	var wall := Color(0.3, 0.34, 0.42)
	Build.box(self, Vector3(0, -0.1, 0), Vector3(46, 0.2, 34), Color(0.2, 0.22, 0.26))
	Build.box(self, Vector3(0, 1.5, -16.5), Vector3(46, 3, 1), wall)
	Build.box(self, Vector3(0, 1.5, 16.5), Vector3(46, 3, 1), wall)
	Build.box(self, Vector3(-22.5, 1.5, 0), Vector3(1, 3, 34), wall)
	Build.box(self, Vector3(22.5, 1.5, 0), Vector3(1, 3, 34), wall)
	Build.box(self, Vector3(-12, 1.5, -5), Vector3(1, 3, 22), wall)
	Build.box(self, Vector3(-2, 1.5, 5), Vector3(1, 3, 22), wall)
	Build.box(self, Vector3(8, 1.5, -5), Vector3(1, 3, 22), wall)
	Build.box(self, Vector3(16, 1.5, 5), Vector3(1, 3, 22), wall)
	for p in [Vector2(-9, 3), Vector2(-5, -3), Vector2(0.5, -2), Vector2(5.5, 3), Vector2(10, 2),
			Vector2(14.5, -3), Vector2(20.5, -7), Vector2(-18, 4), Vector2(-16, -6)]:
		Build.box(self, Vector3(p.x, 1, p.y), Vector3(2, 2, 2), Color(0.5, 0.38, 0.22))

	# люк вентиляции
	var hb := BoxMesh.new()
	hb.size = Vector3(2.2, 0.12, 2.2)
	add_child(Build.mi(hb, Color(0.12, 0.12, 0.14), hatch_pos + Vector3(0, 0.06, 0)))
	for i in 5:
		var bar := BoxMesh.new()
		bar.size = Vector3(2.0, 0.08, 0.1)
		add_child(Build.mi(bar, Color(0.6, 0.6, 0.65), hatch_pos + Vector3(0, 0.15, -0.8 + i * 0.4)))
	var gl := CylinderMesh.new()
	gl.top_radius = 1.6
	gl.bottom_radius = 1.6
	gl.height = 0.03
	add_child(Build.mi(gl, Color(0.3, 1, 0.5, 0.3), hatch_pos + Vector3(0, 0.03, 0)))
	var gm: StandardMaterial3D = gl.material
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(Build.label3d("ВЕНТИЛЯЦИЯ", hatch_pos + Vector3(0, 2.6, 0), 70, Color(0.5, 1, 0.6)))

	_add_player(Vector3(-19, 0, 13))
	_spawn_guard([Vector3(-7, 0, 12), Vector3(-7, 0, -10)])
	_spawn_guard([Vector3(3, 0, -12), Vector3(3, 0, 12)])
	_spawn_guard([Vector3(12, 0, 12), Vector3(12, 0, -10)])
	_spawn_guard([Vector3(18, 0, -2), Vector3(18, 0, -10)])
	controls.sneak = true
	lbl_obj.text = "Пройди базу БЕСШУМНО и найди вентиляцию."
	_chapter("ГЛАВА 1 · БАЗА", "Интерпол увёз маму! Бег шумит — агенты услышат. Крадись!")

func _update_base() -> void:
	_update_state()
	var near := _fd(player.global_position, hatch_pos) < 2.6
	controls.use_text = "ПОЛЗТИ"
	controls.use_visible = near
	if near and controls.is_use_down():
		_goto(1)

# ---------- глава 1: вентиляция ----------
func _cell(c: int, r: int) -> Vector3:
	return Vector3(vent_ox + (c + 0.5) * CELL, 0, vent_oz + (r + 0.5) * CELL)

func _phase_vent() -> void:
	_set_sky(Color(0.02, 0.02, 0.04), Color(0.7, 0.75, 0.9), 0.55, 0.3)
	var W := 20
	var H := 13
	vent_ox = -W * CELL / 2.0
	vent_oz = -H * CELL / 2.0
	var solid: Array = []
	for r in H:
		var row: Array = []
		for c in W:
			row.append(true)
		solid.append(row)
	var wps := [Vector2i(1, 1), Vector2i(8, 1), Vector2i(8, 5), Vector2i(2, 5), Vector2i(2, 9),
		Vector2i(12, 9), Vector2i(12, 3), Vector2i(17, 3), Vector2i(17, 11)]
	for i in wps.size() - 1:
		var a: Vector2i = wps[i]
		var b: Vector2i = wps[i + 1]
		var st := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var cur := a
		while true:
			solid[cur.y][cur.x] = false
			if cur == b:
				break
			cur += st
	Build.box(self, Vector3(0, -0.1, 0), Vector3(W * CELL, 0.2, H * CELL), Color(0.25, 0.27, 0.3))
	for r in H:
		var c := 0
		while c < W:
			if solid[r][c]:
				var c2 := c
				while c2 + 1 < W and solid[r][c2 + 1]:
					c2 += 1
				var n := c2 - c + 1
				Build.box(self, Vector3(vent_ox + (c + n / 2.0) * CELL, 1.25, vent_oz + (r + 0.5) * CELL),
					Vector3(n * CELL, 2.5, CELL), Color(0.32, 0.35, 0.4))
				c = c2 + 1
			else:
				c += 1

	# паровые клапаны: [клетка c, клетка r, сдвиг по времени]
	for j in [[5, 1, 0.0], [5, 5, 1.1], [2, 7, 2.2], [7, 9, 0.6], [12, 6, 1.7]]:
		var pos := _cell(j[0], j[1])
		var pad := CylinderMesh.new()
		pad.top_radius = 0.9
		pad.bottom_radius = 0.9
		pad.height = 0.05
		add_child(Build.mi(pad, Color(0.2, 0.2, 0.22), pos + Vector3(0, 0.03, 0)))
		var pm: StandardMaterial3D = pad.material
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var steam := CylinderMesh.new()
		steam.top_radius = 1.1
		steam.bottom_radius = 1.1
		steam.height = 2.4
		var sm := Build.mi(steam, Color(1, 1, 1, 0.55), pos + Vector3(0, 1.2, 0))
		var smat: StandardMaterial3D = steam.material
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.visible = false
		add_child(sm)
		jets.append({"pos": pos, "off": j[2], "mat": pm, "steam": sm})

	exit_pos = _cell(17, 11)
	var ex := CylinderMesh.new()
	ex.top_radius = 1.1
	ex.bottom_radius = 1.1
	ex.height = 0.03
	add_child(Build.mi(ex, Color(0.3, 1, 0.5, 0.35), exit_pos + Vector3(0, 0.03, 0)))
	var em: StandardMaterial3D = ex.material
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(Build.label3d("ВЫХОД", exit_pos + Vector3(0, 2.2, 0), 70, Color(0.5, 1, 0.6)))

	_add_player(_cell(1, 1))
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 1.4
	lamp.position = Vector3(0, 2.2, 0)
	player.add_child(lamp)
	lbl_obj.text = "Ползи по вентиляции к выходу."
	_chapter("ГЛАВА 2 · ВЕНТИЛЯЦИЯ", "Паровые клапаны! Жди, пока красный сигнал погаснет.")

func _update_vent() -> void:
	controls.sneak = true
	lbl_state.text = "Ползём..."
	lbl_state.add_theme_color_override("font_color", Color(0.7, 0.9, 1))
	for j in jets:
		var t: float = fmod(time + j["off"], 3.6)
		var st := 0
		if t >= 2.9:
			st = 2
		elif t >= 2.2:
			st = 1
		var steam: MeshInstance3D = j["steam"]
		steam.visible = st == 2
		var m: StandardMaterial3D = j["mat"]
		if st == 0:
			m.albedo_color = Color(0.2, 0.2, 0.22)
		elif st == 1:
			m.albedo_color = Color(1, 0.45, 0.1) if int(time * 10.0) % 2 == 0 else Color(0.6, 0.15, 0.05)
		else:
			m.albedo_color = Color(1, 0.9, 0.7)
			if player.alive and _fd(player.global_position, j["pos"]) < 1.4:
				player.hit(j["pos"])
	if _fd(player.global_position, exit_pos) < 1.6:
		show_msg("Выход! Вылезаем...", 1.5)
		_goto(2)

# ---------- глава 2: фургон ----------
func _build_van(pos: Vector3) -> void:
	van = StaticBody3D.new()
	van.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(6.4, 2.2, 2.3)
	cs.shape = sh
	cs.position = Vector3(0.7, 1.1, 0)
	van.add_child(cs)
	var body := BoxMesh.new()
	body.size = Vector3(5.0, 2.0, 2.3)
	van.add_child(Build.mi(body, Color(0.85, 0.87, 0.92), Vector3(0, 1.3, 0)))
	var cab := BoxMesh.new()
	cab.size = Vector3(1.5, 1.4, 2.2)
	van.add_child(Build.mi(cab, Color(0.15, 0.25, 0.6), Vector3(3.2, 0.9, 0)))
	var ws := BoxMesh.new()
	ws.size = Vector3(0.08, 0.7, 1.8)
	van.add_child(Build.mi(ws, Color(0.1, 0.15, 0.3), Vector3(3.97, 1.2, 0)))
	for wx in [-1.7, 2.8]:
		for wz in [-1.2, 1.2]:
			var wh := CylinderMesh.new()
			wh.top_radius = 0.5
			wh.bottom_radius = 0.5
			wh.height = 0.4
			var w := Build.mi(wh, Color(0.05, 0.05, 0.05), Vector3(wx, 0.5, wz))
			w.rotation_degrees.x = 90.0
			van.add_child(w)
	var tag := Label3D.new()
	tag.text = "INTERPOL"
	tag.font_size = 60
	tag.pixel_size = 0.01
	tag.position = Vector3(0, 1.5, 1.17)
	van.add_child(tag)
	add_child(van)

func _phase_yard() -> void:
	_set_sky(Color(0.1, 0.1, 0.2), Color(0.7, 0.7, 0.9), 0.7, 0.8)
	var wall := Color(0.4, 0.42, 0.48)
	Build.box(self, Vector3(0, -0.1, 0), Vector3(46, 0.2, 32), Color(0.24, 0.28, 0.24))
	Build.box(self, Vector3(0, 1.25, -16.5), Vector3(46, 2.5, 1), wall)
	Build.box(self, Vector3(0, 1.25, 16.5), Vector3(46, 2.5, 1), wall)
	Build.box(self, Vector3(-23.5, 1.25, 0), Vector3(1, 2.5, 34), wall)
	Build.box(self, Vector3(23.5, 1.25, -14.25), Vector3(1, 2.5, 4.5), wall)
	Build.box(self, Vector3(23.5, 1.25, 5), Vector3(1, 2.5, 22), wall)
	gate = Build.box(self, Vector3(23.5, 1.25, -9), Vector3(1, 2.5, 6), Color(0.3, 0.3, 0.35))
	Build.box(self, Vector3(-7, 1.25, 3), Vector3(1, 2.5, 14), wall)
	Build.box(self, Vector3(4, 1.25, -3), Vector3(1, 2.5, 14), wall)
	for p in [Vector2(-11, 5), Vector2(-10, -8), Vector2(-3.5, -6), Vector2(1.5, 6), Vector2(6.5, 3),
			Vector2(15, 2), Vector2(18, 5), Vector2(9, -9)]:
		Build.box(self, Vector3(p.x, 1, p.y), Vector3(2, 2, 2), Color(0.5, 0.38, 0.22))
	_build_van(Vector3(18.5, 0, -9))
	add_child(Build.label3d("ФУРГОН", Vector3(18.5, 4.0, -9), 70, Color(1, 0.8, 0.3)))

	_add_player(Vector3(-20, 0, 13.5))
	_spawn_guard([Vector3(-14, 0, 8), Vector3(-14, 0, -12)])
	_spawn_guard([Vector3(-1, 0, 12), Vector3(-1, 0, -12)])
	_spawn_guard([Vector3(9, 0, 12), Vector3(9, 0, -2)])
	_spawn_guard([Vector3(12, 0, -14), Vector3(12, 0, -4)])
	lbl_timer.visible = true
	lbl_obj.text = "Запрыгни на фургон, пока он не уехал!"
	_chapter("ГЛАВА 3 · ФУРГОН", "Фургон скоро уедет с мамой! Добеги и запрыгни (ПРЫГНУТЬ).")

func _update_yard(delta: float) -> void:
	_update_state()
	yard_time -= delta
	lbl_timer.text = "Фургон уедет через: %d" % int(ceil(maxf(yard_time, 0.0)))
	van.position.y = sin(time * 40.0) * 0.015
	var d: Vector3 = player.global_position - van.global_position
	var near: bool = d.x > -4.5 and d.x < 5.5 and absf(d.z) < 3.3
	controls.use_text = "ПРЫГНУТЬ"
	controls.use_visible = near
	if near and controls.is_use_down():
		_ride()
	elif yard_time <= 0.0:
		_van_leaves()

func _van_leaves() -> void:
	busy = true
	_stop_all()
	lbl_timer.visible = false
	show_msg("Фургон уехал!", 3.0)
	var t := create_tween()
	t.tween_property(van, "position:x", van.position.x + 45.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): _show_end("ПОРАЖЕНИЕ\nФургон уехал без птенцов...", "Нажми, чтобы попробовать снова"))

func _build_road() -> void:
	Build.box(self, Vector3(80, -0.15, -9), Vector3(140, 0.2, 70), Color(0.18, 0.3, 0.18))
	Build.box(self, Vector3(75, -0.05, -9), Vector3(110, 0.2, 9), Color(0.14, 0.14, 0.16))
	for i in 20:
		var m := BoxMesh.new()
		m.size = Vector3(2.5, 0.02, 0.25)
		add_child(Build.mi(m, Color(0.9, 0.9, 0.8), Vector3(26 + i * 5.5, 0.07, -9)))
	for x in range(30, 130, 12):
		var pole := CylinderMesh.new()
		pole.top_radius = 0.12
		pole.bottom_radius = 0.15
		pole.height = 6.0
		add_child(Build.mi(pole, Color(0.3, 0.3, 0.35), Vector3(x, 3.0, -3.5)))
		var lamp := SphereMesh.new()
		lamp.radius = 0.35
		lamp.height = 0.7
		add_child(Build.mi(lamp, Color(1, 0.95, 0.6), Vector3(x, 6.1, -3.5)))
	for x in range(26, 130, 9):
		var z := -17.0 if randf() < 0.5 else 0.0
		var tk := CylinderMesh.new()
		tk.top_radius = 0.25
		tk.bottom_radius = 0.3
		tk.height = 2.0
		add_child(Build.mi(tk, Color(0.35, 0.22, 0.1), Vector3(x + randf_range(-2, 2), 1.0, z)))
		var lv := SphereMesh.new()
		lv.radius = 1.4
		lv.height = 2.8
		add_child(Build.mi(lv, Color(0.12, 0.4, 0.15), Vector3(x + randf_range(-2, 2), 3.0, z)))

func _ride() -> void:
	_begin_cutscene()
	await _fade_to(1.0, 0.4).finished
	player.visible = false
	for i in 5:
		var c := PlayerScript.make_chick(COLORS[i])
		c.position = Vector3(-1.6 + i * 0.75, 2.3, (i % 2) * 0.5 - 0.25)
		c.rotation.y = -PI / 2.0
		van.add_child(c)
	if gate:
		gate.queue_free()
	_build_road()
	var dr = DrunAI.new()
	add_child(dr)
	dr.mode = "follow"
	dr.target_node = van
	dr.global_position = van.global_position + dr.follow_off
	_set_sky(Color(0.35, 0.22, 0.3), Color(1, 0.75, 0.7), 0.8, 0.9)
	cam_mode = "van"
	cam.global_position = van.global_position + Vector3(-9, 6, 10)
	await _fade_to(0.0, 0.5).finished
	_sub("Прыжок! Птенцы на крыше фургона!")
	var tw := create_tween()
	tw.tween_property(van, "position:x", 112.0, 11.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await _wait(3.5)
	_sub("Фургон везёт маму-птицу на склад Интерпола. За ним летит дрон Друн: он следит!")
	await _wait(3.8)
	_sub("Друн: «Вижу фургон и птенцов на крыше. Лечу следом, передаю координаты.»")
	await _wait(3.8)
	_sub("Держитесь крепче, птенцы!")
	await tw.finished
	_sub("Приехали на склад Интерпола...")
	await _wait(1.0)
	busy = false
	_goto(3)

# ---------- глава 3: грузовик ----------
func _build_truck_yard() -> void:
	var wall := Color(0.38, 0.42, 0.5)
	Build.box(self, Vector3(0, -0.1, 0), Vector3(44, 0.2, 30), Color(0.22, 0.26, 0.24))
	Build.box(self, Vector3(0, 1.25, -15.5), Vector3(44, 2.5, 1), wall)
	Build.box(self, Vector3(0, 1.25, 15.5), Vector3(44, 2.5, 1), wall)
	Build.box(self, Vector3(-22.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	Build.box(self, Vector3(22.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	Build.box(self, Vector3(-11.5, 1.25, 3), Vector3(6, 2.5, 2.5), Color(0.2, 0.4, 0.5))
	Build.box(self, Vector3(16, 1.25, 8), Vector3(6, 2.5, 2.5), Color(0.5, 0.25, 0.2))
	for p in [Vector2(-2, 8), Vector2(6, 9), Vector2(-18, -6), Vector2(-10, -9), Vector2(12, -12), Vector2(19, -11)]:
		Build.box(self, Vector3(p.x, 1, p.y), Vector3(2, 2, 2), Color(0.5, 0.38, 0.22))
	_build_truck()

func _phase_truck() -> void:
	_set_sky(Color(0.05, 0.06, 0.12), Color(0.55, 0.6, 0.85), 0.6, 0.8)
	_build_truck_yard()
	_add_player(Vector3(-19, 0, 12))
	_spawn_guard([Vector3(-16, 0, 5), Vector3(-16, 0, -11)])
	_spawn_guard([Vector3(-6, 0, 12), Vector3(-6, 0, -12)])
	_spawn_guard([Vector3(-1, 0, -9), Vector3(15, 0, -9), Vector3(15, 0, 2), Vector3(-1, 0, 2)])
	drun_ai = DrunAI.new()
	add_child(drun_ai)
	drun_ai.global_position = Vector3(-24, 5, -18)
	lbl_obj.text = "Взломай двери грузовика."
	_chapter("ГЛАВА 4 · ГРУЗОВИК", "Мама в этом грузовике! Взломай замок. За вами следом прилетел дрон Друн, он поможет с охраной.")

func _build_truck() -> void:
	var met := Color(0.7, 0.72, 0.78)
	var fl := BoxMesh.new()
	fl.size = Vector3(9.2, 0.15, 3.2)
	add_child(Build.mi(fl, Color(0.25, 0.25, 0.3), tr + Vector3(0, 0.07, 0)))
	Build.box(self, tr + Vector3(0, 0.9, 1.6), Vector3(9.2, 1.8, 0.3), met)
	Build.box(self, tr + Vector3(0, 0.9, -1.6), Vector3(9.2, 1.8, 0.3), met)
	Build.box(self, tr + Vector3(4.7, 0.9, 0), Vector3(0.3, 1.8, 3.2), met)
	door_l = Build.box(self, tr + Vector3(-4.6, 0.9, 0.75), Vector3(0.3, 1.8, 1.5), Color(0.55, 0.57, 0.65))
	door_r = Build.box(self, tr + Vector3(-4.6, 0.9, -0.75), Vector3(0.3, 1.8, 1.5), Color(0.55, 0.57, 0.65))
	Build.box(self, tr + Vector3(5.9, 1.1, 0), Vector3(2.6, 2.2, 3.0), Color(0.15, 0.25, 0.6))
	var ws := BoxMesh.new()
	ws.size = Vector3(0.1, 0.8, 2.4)
	add_child(Build.mi(ws, Color(0.1, 0.15, 0.3), tr + Vector3(7.2, 1.5, 0)))
	for wx in [-3.0, 0.5, 5.5]:
		for wz in [-1.75, 1.75]:
			var wh := CylinderMesh.new()
			wh.top_radius = 0.55
			wh.bottom_radius = 0.55
			wh.height = 0.4
			var w := Build.mi(wh, Color(0.05, 0.05, 0.05), tr + Vector3(wx, 0.55, wz))
			w.rotation_degrees.x = 90.0
			add_child(w)
	door_pos = tr + Vector3(-4.6, 0, 0)
	var ls := SphereMesh.new()
	ls.radius = 0.18
	ls.height = 0.36
	door_light = Build.mi(ls, Color(1, 0.2, 0.2), tr + Vector3(-4.9, 1.6, 0))
	var lm: StandardMaterial3D = ls.material
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(door_light)
	door_lbl = Build.label3d("ЗАПЕРТО", tr + Vector3(-4.9, 2.8, 0), 70, Color(1, 0.4, 0.4))
	add_child(door_lbl)

	_build_cage_mother(tr + Vector3(2.3, 0, 0))

func _build_cage_mother(pos: Vector3) -> void:
	cage_pos = pos
	cage = Build.make_cage()
	cage.position = cage_pos
	cage.scale = Vector3.ONE * 0.85
	add_child(cage)
	mother_root = Node3D.new()
	mother_root.position = cage_pos
	add_child(mother_root)
	mother = Build.make_mother()
	mother_root.add_child(mother)
	mama_lbl = Build.label3d("МАМА", Vector3(0, 3.4, 0), 70, Color(1, 0.9, 0.4))
	mother_root.add_child(mama_lbl)

func _update_drun_helper(delta: float) -> void:
	if drun_ai == null or drun_kills >= 2:
		return
	if drun_target == null:
		drun_t -= delta
		var idle := Vector3(sin(time * 0.6) * 18.0, 5.0, -12.0 + cos(time * 0.6) * 5.0)
		drun_ai.global_position = drun_ai.global_position.lerp(idle, minf(1.0, 2.0 * delta))
		if drun_t <= 0.0:
			var best: Node3D = null
			var bd := 7.0
			for g in get_tree().get_nodes_in_group("guards"):
				if g.is_down():
					continue
				var d := _fd(g.global_position, player.global_position)
				if d > bd:
					best = g
					bd = d
			if best:
				drun_target = best
				show_msg("Друн атакует агента с воздуха!", 2.0)
			else:
				drun_t = 3.0
	else:
		if not is_instance_valid(drun_target) or drun_target.is_down():
			drun_target = null
			drun_t = 3.0
			return
		var tp: Vector3 = drun_target.global_position + Vector3(0, 3.0, 0)
		drun_ai.global_position = drun_ai.global_position.move_toward(tp, 12.0 * delta)
		if _fd(drun_ai.global_position, drun_target.global_position) < 1.2:
			drun_target._down(true)
			drun_kills += 1
			drun_target = null
			drun_t = 14.0
			show_msg("Друн вырубил агента!", 2.5)
			if drun_kills >= 2:
				show_msg("Друн: «Дальше вы сами! Я слежу сверху.»", 3.5)
				create_tween().tween_property(drun_ai, "position:y", 40.0, 4.0)

func _update_truck(delta: float) -> void:
	if phase == 3:
		_update_drun_helper(delta)
	_update_state()
	var ppos: Vector3 = player.global_position
	controls.use_text = "ВЗЛОМАТЬ"
	controls.use_visible = false
	var target := ""
	if not door_open and _fd(ppos, door_pos) < 3.4:
		target = "simon"
	elif door_open and not cage_opened and _fd(ppos, cage_pos) < 3.8:
		target = "pins"
	controls.use_visible = target != ""
	if target != "" and controls.is_use_down() and pick_cd <= 0.0:
		_open_mini(target)

func _open_mini(kind: String) -> void:
	busy = true
	mini_kind = kind
	controls.enabled = false
	controls.visible = false
	controls.use_visible = false
	player.set_physics_process(false)
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(false)
	mini.start(kind)

func _on_mini_done(ok: bool) -> void:
	busy = false
	pick_cd = 0.6
	controls.enabled = true
	controls.visible = true
	player.set_physics_process(true)
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(true)
	if not ok:
		return
	if mini_kind == "simon":
		_door_open()
	else:
		_cage_open()

func _door_open() -> void:
	if phase == 5:
		_cell_open()
		return
	door_open = true
	var lm: StandardMaterial3D = door_light.mesh.material
	lm.albedo_color = Color(0.2, 1, 0.4)
	door_lbl.text = "ОТКРЫТО"
	door_lbl.modulate = Color(0.5, 1, 0.6)
	create_tween().tween_property(door_l, "position:z", tr.z + 2.35, 0.8)
	create_tween().tween_property(door_r, "position:z", tr.z - 2.35, 0.8)
	lbl_obj.text = "Зайди внутрь и взломай клетку мамы."
	show_msg("Двери открыты! Внутри — мама!", 3.0)

func _end_cutscene() -> void:
	cutscene = false
	busy = false
	cam.rotation_degrees = Vector3(-55, 0, 0)
	controls.enabled = true
	controls.visible = true
	_hud_visible(true)
	player.set_physics_process(true)
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(true)

func _flap() -> void:
	var wl: Node3D = mother.get_node("WingL")
	var wr: Node3D = mother.get_node("WingR")
	flap_tw = create_tween().set_loops()
	flap_tw.tween_property(wl, "rotation_degrees:z", 35.0, 0.18)
	flap_tw.parallel().tween_property(wr, "rotation_degrees:z", -35.0, 0.18)
	flap_tw.tween_property(wl, "rotation_degrees:z", -25.0, 0.18)
	flap_tw.parallel().tween_property(wr, "rotation_degrees:z", 25.0, 0.18)

func _cage_open() -> void:
	cage_opened = true
	_begin_cutscene()
	cage.visible = false
	cage.get_node("Col").set_deferred("disabled", true)
	mama_lbl.queue_free()
	_move_cam(cage_pos + Vector3(-5, 5, 7), cage_pos + Vector3(0, 1.2, 0), 2.0)
	_sub("Клетка открыта!")
	var hop := create_tween().set_loops(3)
	hop.tween_property(mother_root, "position:y", 0.7, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(mother_root, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(2.2)

	if phase == 5:
		_sub("Мама свободна! Но она слишком слаба, чтобы лететь...")
		await _wait(3.2)
		_sub("Нужна машина! Бежим в гараж!")
		await _wait(2.6)
		await _fade_to(1.0, 0.8).finished
		busy = false
		_goto(6)
		return

	_sub("Мама зовёт птенцов!")
	player.visible = false
	for i in 5:
		var c := PlayerScript.make_chick(COLORS[i])
		add_child(c)
		var start: Vector3 = player.global_position + Vector3(0, 0, (i - 2) * 0.3)
		var end: Vector3 = mother_root.global_position + Vector3((i - 2) * 0.35, 1.55, 0.1)
		c.global_position = start
		var tw := create_tween()
		tw.tween_interval(i * 0.45)
		tw.tween_method(func(k: float):
			var p := start.lerp(end, k)
			p.y += sin(k * PI) * 2.0
			c.global_position = p, 0.0, 1.0, 0.7)
		tw.tween_callback(func():
			c.reparent(mother_root)
			c.position = Vector3((i - 2) * 0.35, 1.55, 0.1)
			c.rotation = Vector3.ZERO)
	await _wait(3.4)

	_sub("Мама подхватила птенцов — и взлетела!")
	_flap()
	create_tween().tween_property(mother_root, "rotation_degrees:y", 90.0, 0.8)
	create_tween().tween_property(env, "background_color", Color(1.0, 0.6, 0.35), 7.0)
	create_tween().tween_property(env, "ambient_light_color", Color(1.0, 0.8, 0.65), 7.0)
	cam_mode = "mother"
	if phase == 3:
		var fly3 := create_tween()
		fly3.tween_interval(0.6)
		fly3.tween_property(mother_root, "position", cage_pos + Vector3(14, 13, -6), 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await _wait(4.8)
		await _mother_shot()
		return

# выстрел Интерпола: мама падает -> глава 4
func _mother_shot() -> void:
	_sub("БАХ! Интерпол подстрелил маму!")
	fade.color = Color(1, 1, 1, 0.9)
	create_tween().tween_property(fade, "color", Color(0, 0, 0, 0), 0.5)
	if flap_tw:
		flap_tw.kill()
	var land := Vector3(16, 0.9, 1)
	var fall := create_tween().set_parallel(true)
	fall.tween_property(mother_root, "position", land, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(mother_root, "rotation_degrees:z", 450.0, 1.8)
	await _wait(2.4)
	_sub("Мама упала! Её нужно срочно вылечить...")
	await _wait(3.2)
	_sub("А Интерпол уже идёт по следу!")
	await _wait(2.6)
	busy = false
	_goto(4)

# ---------- глава 4: поляна (лечим маму, отбиваемся) ----------
func _phase_field() -> void:
	_set_sky(Color(0.05, 0.07, 0.14), Color(0.5, 0.6, 0.8), 0.6, 0.55)
	var wall := Color(0.12, 0.2, 0.14)
	Build.box(self, Vector3(0, -0.1, 0), Vector3(46, 0.2, 32), Color(0.16, 0.34, 0.18))
	Build.box(self, Vector3(0, 1.0, -16.0), Vector3(46, 2.0, 1), wall)
	Build.box(self, Vector3(0, 1.0, 16.0), Vector3(46, 2.0, 1), wall)
	Build.box(self, Vector3(-23.0, 1.0, 0), Vector3(1, 2.0, 33), wall)
	Build.box(self, Vector3(23.0, 1.0, 0), Vector3(1, 2.0, 33), wall)
	for p in [Vector2(-9, -6), Vector2(8, -9), Vector2(10, 7), Vector2(-8, 8), Vector2(17, -2), Vector2(-17, -3)]:
		Build.box(self, Vector3(p.x, 1.5, p.y), Vector3(0.9, 3.0, 0.9), Color(0.35, 0.22, 0.1))
		var lv := SphereMesh.new()
		lv.radius = 1.8
		lv.height = 3.6
		add_child(Build.mi(lv, Color(0.1, 0.38, 0.14), Vector3(p.x, 3.6, p.y)))
	# мама лежит в центре
	mother_pos = Vector3(0, 0, 0)
	mother_root = Node3D.new()
	mother_root.position = Vector3(0, 0.9, 0)
	mother_root.rotation_degrees = Vector3(0, 30, 90)
	add_child(mother_root)
	mother = Build.make_mother()
	mother_root.add_child(mother)
	mama_lbl = Build.label3d("МАМА (ранена)", Vector3(0, 3.0, 0), 70, Color(1, 0.5, 0.4))
	add_child(mama_lbl)
	mama_lbl.position = Vector3(0, 3.2, 0)
	var ring := CylinderMesh.new()
	ring.top_radius = 3.2
	ring.bottom_radius = 3.2
	ring.height = 0.03
	add_child(Build.mi(ring, Color(0.3, 1, 0.5, 0.25), Vector3(0, 0.03, 0)))
	var rm: StandardMaterial3D = ring.material
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# лечебные травы
	for p in [Vector3(-15, 0, -9), Vector3(15, 0, 10), Vector3(13, 0, -11), Vector3(-14, 0, 6)]:
		var hm := SphereMesh.new()
		hm.radius = 0.45
		hm.height = 0.9
		var node := Build.mi(hm, Color(0.3, 1, 0.45), p + Vector3(0, 0.6, 0))
		var mat: StandardMaterial3D = hm.material
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.9, 0.3)
		add_child(node)
		var lb := Build.label3d("ТРАВА", p + Vector3(0, 1.8, 0), 50, Color(0.5, 1, 0.6))
		add_child(lb)
		herbs.append({"pos": p, "node": node, "lbl": lb})
	_add_player(Vector3(-19, 0, 12))
	lbl_obj.text = "Собери травы и лечи маму. Отбивайся от Интерпола!"
	_chapter("ГЛАВА 5 · СПАСЕНИЕ МАМЫ", "Собери 3 травы, неси к маме и жми ЛЕЧИТЬ. Агенты уже близко — бей клювом!")

func _spawn_chaser() -> void:
	var p := Vector3.ZERO
	match randi() % 4:
		0: p = Vector3(randf_range(-20, 20), 0, -14)
		1: p = Vector3(randf_range(-20, 20), 0, 14)
		2: p = Vector3(-21, 0, randf_range(-13, 13))
		_: p = Vector3(21, 0, randf_range(-13, 13))
	var g = GuardScript.new()
	g.player = player
	g.waypoints = [p]
	g.position = p
	g.view_dist = 60.0
	g.hp = 4.0
	g.knocked_out.connect(_on_ko)
	add_child(g)
	g.cone.visible = false
	g.state = 1  # CHASE
	g.lose_t = 6.0
	g.last_seen = player.global_position

func _update_field(delta: float) -> void:
	_update_state()
	heal_cd = maxf(0.0, heal_cd - delta)
	wave_t -= delta
	if wave_t <= 0.0:
		wave_t = 7.0
		for i in 2:
			if get_tree().get_nodes_in_group("guards").size() < 6:
				_spawn_chaser()
		show_msg("Новые агенты Интерпола!", 1.5)
	var ppos: Vector3 = player.global_position
	for h in herbs.duplicate():
		h["node"].position.y = 0.6 + sin(time * 3.0) * 0.12
		if _fd(ppos, h["pos"]) < 1.6:
			herbs.erase(h)
			h["node"].queue_free()
			h["lbl"].queue_free()
			herb_count += 1
			show_msg("Трава собрана! Неси к маме.", 2.0)
	lbl_obj.text = "Трав: %d · Мама вылечена: %d/3 · Отбивайся от Интерпола!" % [herb_count, heal]
	var near := _fd(ppos, mother_pos) < 3.4
	controls.use_text = "ЛЕЧИТЬ"
	controls.use_visible = near and herb_count > 0
	if controls.use_visible and controls.is_use_down() and heal_cd <= 0.0:
		heal_cd = 0.8
		herb_count -= 1
		heal += 1
		show_msg("Маме лучше! (%d/3)" % heal, 2.0)
		var pulse := create_tween()
		pulse.tween_property(mother_root, "scale", Vector3.ONE * 1.15, 0.15)
		pulse.tween_property(mother_root, "scale", Vector3.ONE, 0.2)
		if heal >= 3:
			_field_end()
	elif herbs.is_empty() and herb_count + heal < 3 and not field_done:
		# на случай, если травы кончились раньше времени — вырастает новая
		var np := Vector3(randf_range(-15, 15), 0, randf_range(-11, 11))
		var hm := SphereMesh.new()
		hm.radius = 0.45
		hm.height = 0.9
		var node := Build.mi(hm, Color(0.3, 1, 0.45), np + Vector3(0, 0.6, 0))
		add_child(node)
		var lb := Build.label3d("ТРАВА", np + Vector3(0, 1.8, 0), 50, Color(0.5, 1, 0.6))
		add_child(lb)
		herbs.append({"pos": np, "node": node, "lbl": lb})

func _field_end() -> void:
	field_done = true
	_begin_cutscene()
	for g in get_tree().get_nodes_in_group("guards"):
		g.queue_free()
	var heal_tw := create_tween().set_parallel(true)
	heal_tw.tween_property(mother_root, "rotation_degrees:z", 0.0, 1.2)
	heal_tw.tween_property(mother_root, "position:y", 0.0, 1.2)
	mama_lbl.text = "МАМА"
	mama_lbl.modulate = Color(1, 0.9, 0.4)
	_move_cam(Vector3(-5, 5, 9), Vector3(0, 1.2, 0), 1.5)
	_sub("Мама пришла в себя!")
	await _wait(2.8)
	_sub("Но Интерпол окружил поляну...")
	for i in 10:
		var a := TAU * i / 10.0
		var gp := Vector3(cos(a) * 9.0, 0, sin(a) * 6.5)
		var g = GuardScript.new()
		g.player = player
		g.waypoints = [gp]
		g.position = gp
		add_child(g)
		g.set_physics_process(false)
		g.cone.visible = false
		g.rotation.y = atan2(-(-gp.x), -(-gp.z))
	_move_cam(Vector3(-4, 14, 16), Vector3(0, 0, 0), 2.0)
	await _wait(3.2)
	_sub("Птенцов и маму поймали!")
	player.visible = true
	for pos in [player.global_position, mother_root.global_position]:
		var c := Build.make_cage()
		c.scale = Vector3.ONE * 0.9
		c.position = pos + Vector3(0, 7, 0)
		add_child(c)
		var pp: Vector3 = pos
		pp.y = 0.0
		create_tween().tween_property(c, "position", pp, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_move_cam(Vector3(-5, 7, 10), Vector3(-3, 1, 0), 1.5)
	await _wait(3.0)
	await _fade_to(1.0, 0.8).finished
	_sub("Птенцов заперли в камере Интерпола...")
	await _wait(2.5)
	busy = false
	_goto(5)

# ---------- глава 5: камера Интерпола (побег) ----------
func _phase_cell() -> void:
	_set_sky(Color(0.04, 0.04, 0.07), Color(0.6, 0.55, 0.7), 0.6, 0.7)
	var wall := Color(0.34, 0.36, 0.44)
	Build.box(self, Vector3(0, -0.1, 0), Vector3(44, 0.2, 30), Color(0.2, 0.2, 0.24))
	Build.box(self, Vector3(0, 1.25, -15.5), Vector3(44, 2.5, 1), wall)
	Build.box(self, Vector3(0, 1.25, 15.5), Vector3(44, 2.5, 1), wall)
	Build.box(self, Vector3(-22.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	Build.box(self, Vector3(22.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	# камера птенцов (слева внизу)
	Build.box(self, Vector3(-15.8, 1.25, 11.6), Vector3(0.4, 2.5, 7.8), Color(0.3, 0.3, 0.38))
	Build.box(self, Vector3(-21, 1.25, 7.7), Vector3(2.0, 2.5, 0.4), Color(0.3, 0.3, 0.38))
	Build.box(self, Vector3(-16.9, 1.25, 7.7), Vector3(1.8, 2.5, 0.4), Color(0.3, 0.3, 0.38))
	cell_door = Build.box(self, Vector3(-19, 1.25, 7.7), Vector3(2.0, 2.5, 0.4), Color(0.8, 0.2, 0.2))
	door_pos = Vector3(-19, 0, 7.7)
	door_lbl = Build.label3d("ЗАПЕРТО", door_pos + Vector3(0, 3.2, 0), 70, Color(1, 0.4, 0.4))
	add_child(door_lbl)
	for p in [Vector2(-9, -2), Vector2(0, 0), Vector2(7, 5), Vector2(10, -12), Vector2(18, 6), Vector2(-14, -8)]:
		Build.box(self, Vector3(p.x, 1, p.y), Vector3(2, 2, 2), Color(0.5, 0.38, 0.22))
	_build_cage_mother(Vector3(15, 0, -9))
	mama_lbl.text = "МАМА!"
	_add_player(Vector3(-19, 0, 12))
	_spawn_guard([Vector3(-12, 0, 12), Vector3(-12, 0, -11)])
	_spawn_guard([Vector3(-4, 0, -12), Vector3(-4, 0, 10)])
	_spawn_guard([Vector3(5, 0, 10), Vector3(5, 0, -8)])
	_spawn_guard([Vector3(10, 0, -4), Vector3(20, 0, -4)])
	lbl_obj.text = "Взломай замок камеры и выбирайся."
	_chapter("ГЛАВА 6 · ПОБЕГ", "Вы заперты! Взломай замок камеры. Мама — в клетке на другом конце!")
	_cell_intro()

func _cell_intro() -> void:
	_begin_cutscene()
	_move_cam(cage_pos + Vector3(-5, 7, 9), cage_pos + Vector3(0, 1.2, 0), 1.6)
	_sub("Птенцы заперты... но вдалеке они видят маму!")
	await _wait(3.6)
	_move_cam(player.global_position + CAM_OFFSET, player.global_position, 1.2)
	await _wait(1.4)
	_end_cutscene()

func _cell_open() -> void:
	door_open = true
	door_lbl.text = "ОТКРЫТО"
	door_lbl.modulate = Color(0.5, 1, 0.6)
	var t := create_tween()
	t.tween_property(cell_door, "position:y", 5.0, 0.8)
	t.tween_callback(func(): cell_door.queue_free())
	lbl_obj.text = "Тихо проберись к маме и взломай её клетку."
	show_msg("Камера открыта! Крадись к маме!", 3.0)

# ---------- машина (общая модель) ----------
func _make_car(col: Color, full := true) -> Node3D:
	var c := Node3D.new()
	var ch := BoxMesh.new()
	ch.size = Vector3(2.0, 0.6, 4.2)
	c.add_child(Build.mi(ch, col, Vector3(0, 0.65, 0)))
	var cab := BoxMesh.new()
	cab.size = Vector3(1.8, 0.7, 2.0)
	c.add_child(Build.mi(cab, col.lightened(0.15), Vector3(0, 1.3, 0.35)))
	var gl := BoxMesh.new()
	gl.size = Vector3(1.7, 0.45, 1.9)
	c.add_child(Build.mi(gl, Color(0.15, 0.22, 0.35), Vector3(0, 1.35, 0.35)))
	var eng := Node3D.new()
	eng.name = "Engine"
	var hood := BoxMesh.new()
	hood.size = Vector3(1.8, 0.35, 1.3)
	eng.add_child(Build.mi(hood, Color(0.7, 0.7, 0.75), Vector3(0, 1.1, -1.5)))
	var lamp := BoxMesh.new()
	lamp.size = Vector3(1.6, 0.18, 0.1)
	eng.add_child(Build.mi(lamp, Color(1, 0.95, 0.6), Vector3(0, 0.85, -2.13)))
	c.add_child(eng)
	var wh := Node3D.new()
	wh.name = "Wheels"
	for wx in [-1.05, 1.05]:
		for wz in [-1.3, 1.4]:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.42
			cm.bottom_radius = 0.42
			cm.height = 0.35
			var w := Build.mi(cm, Color(0.05, 0.05, 0.05), Vector3(wx, 0.42, wz))
			w.rotation_degrees.z = 90.0
			wh.add_child(w)
	c.add_child(wh)
	var st := Node3D.new()
	st.name = "Steer"
	var sm := CylinderMesh.new()
	sm.top_radius = 0.25
	sm.bottom_radius = 0.25
	sm.height = 0.05
	var sw := Build.mi(sm, Color(0.1, 0.1, 0.1), Vector3(0, 1.75, -0.4))
	sw.rotation_degrees.x = 70.0
	st.add_child(sw)
	c.add_child(st)
	var tk := Node3D.new()
	tk.name = "Tank"
	var tm := CylinderMesh.new()
	tm.top_radius = 0.3
	tm.bottom_radius = 0.3
	tm.height = 1.2
	var tb := Build.mi(tm, Color(0.8, 0.15, 0.15), Vector3(0, 0.75, 2.2))
	tb.rotation_degrees.z = 90.0
	tk.add_child(tb)
	c.add_child(tk)
	if not full:
		for n in ["Engine", "Wheels", "Steer", "Tank"]:
			c.get_node(n).visible = false
	return c

# ---------- глава 6: гараж (собери машину) ----------
func _phase_garage() -> void:
	_set_sky(Color(0.05, 0.05, 0.08), Color(0.65, 0.6, 0.7), 0.65, 0.7)
	var wall := Color(0.36, 0.38, 0.46)
	Build.box(self, Vector3(0, -0.1, 0), Vector3(44, 0.2, 30), Color(0.22, 0.22, 0.25))
	Build.box(self, Vector3(0, 1.25, -15.5), Vector3(44, 2.5, 1), wall)
	Build.box(self, Vector3(0, 1.25, 15.5), Vector3(44, 2.5, 1), wall)
	Build.box(self, Vector3(-22.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	Build.box(self, Vector3(22.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	for p in [Vector2(-5, 4), Vector2(4, -5), Vector2(13, 2), Vector2(-13, -3)]:
		Build.box(self, Vector3(p.x, 1, p.y), Vector3(2, 2, 2), Color(0.5, 0.38, 0.22))
	# рама машины в центре
	car = _make_car(Color(0.9, 0.3, 0.2), false)
	add_child(car)
	var cb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.4, 2.0, 4.6)
	cs.shape = sh
	cs.position.y = 1.0
	cb.add_child(cs)
	add_child(cb)
	add_child(Build.label3d("МАШИНА (рама)", Vector3(0, 3.6, 0), 60, Color(1, 0.8, 0.3)))
	# мама ждёт у машины
	mother_root = Node3D.new()
	mother_root.position = Vector3(-3.5, 0, 3.0)
	mother_root.rotation_degrees.y = 40.0
	add_child(mother_root)
	mother = Build.make_mother()
	mother_root.add_child(mother)
	mother_root.add_child(Build.label3d("МАМА (ранена)", Vector3(0, 3.2, 0), 60, Color(1, 0.9, 0.4)))
	# детали
	var defs := [
		{"id": "Wheels", "name": "КОЛЁСА", "pos": Vector3(-17, 0, -10), "col": Color(0.2, 0.2, 0.2)},
		{"id": "Engine", "name": "ДВИГАТЕЛЬ", "pos": Vector3(17, 0, -11), "col": Color(0.8, 0.8, 0.9)},
		{"id": "Steer", "name": "РУЛЬ", "pos": Vector3(18, 0, 10), "col": Color(0.3, 0.6, 1)},
		{"id": "Tank", "name": "БАК", "pos": Vector3(-3, 0, -12), "col": Color(0.9, 0.2, 0.2)},
	]
	for d in defs:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.9, 0.9)
		var node := Build.mi(bm, d["col"], d["pos"] + Vector3(0, 0.7, 0))
		var mat: StandardMaterial3D = bm.material
		mat.emission_enabled = true
		mat.emission = d["col"]
		mat.emission_energy_multiplier = 0.6
		add_child(node)
		var lb := Build.label3d(d["name"], d["pos"] + Vector3(0, 2.0, 0), 50, Color(1, 0.95, 0.5))
		add_child(lb)
		parts.append({"id": d["id"], "name": d["name"], "pos": d["pos"], "node": node, "lbl": lb})
	_add_player(Vector3(-19, 0, 12))
	_spawn_guard([Vector3(-9, 0, 12), Vector3(-9, 0, -12)])
	_spawn_guard([Vector3(8, 0, -12), Vector3(8, 0, 12)])
	_spawn_guard([Vector3(-14, 0, -7), Vector3(14, 0, -7)])
	lbl_obj.text = "Найди 4 детали и собери машину."
	_chapter("ГЛАВА 7 · СБОРКА МАШИНЫ", "Мама слаба и не может лететь. Найди детали (колёса, двигатель, руль, бак) и неси к машине.")

func _update_garage(delta: float) -> void:
	_update_state()
	install_cd = maxf(0.0, install_cd - delta)
	var ppos: Vector3 = player.global_position
	for pt in parts.duplicate():
		pt["node"].position.y = 0.7 + sin(time * 3.0) * 0.12
		pt["node"].rotation.y = time
		if _fd(ppos, pt["pos"]) < 1.6:
			parts.erase(pt)
			pt["node"].queue_free()
			pt["lbl"].queue_free()
			carried.append(pt)
			show_msg("Деталь «%s» взята! Неси к машине." % pt["name"], 2.5)
	lbl_obj.text = "Деталей несёшь: %d · Установлено: %d/4" % [carried.size(), installed]
	var near := _fd(ppos, Vector3.ZERO) < 4.4
	controls.use_text = "СОБРАТЬ"
	controls.use_visible = near and carried.size() > 0
	if controls.use_visible and controls.is_use_down() and install_cd <= 0.0:
		install_cd = 0.7
		var pt: Dictionary = carried.pop_back()
		car.get_node(pt["id"]).visible = true
		installed += 1
		show_msg("Установлено: %s (%d/4)" % [pt["name"], installed], 2.0)
		var pop := create_tween()
		pop.tween_property(car, "scale", Vector3.ONE * 1.08, 0.12)
		pop.tween_property(car, "scale", Vector3.ONE, 0.15)
		if installed >= 4:
			_garage_done()

func _garage_done() -> void:
	_begin_cutscene()
	_move_cam(Vector3(-7, 6, 10), Vector3(0, 1, 0), 1.5)
	_sub("Машина собрана! Мотор заработал!")
	var shake := create_tween().set_loops(10)
	shake.tween_property(car, "position:y", 0.06, 0.06)
	shake.tween_property(car, "position:y", 0.0, 0.06)
	await _wait(2.8)
	_sub("Все в машину — и вперёд, подальше от Интерпола!")
	await _wait(2.6)
	await _fade_to(1.0, 0.8).finished
	busy = false
	_goto(7)

# ---------- глава 7: дорога (рулим и не врезаемся) ----------
func _obstacle(node: Node3D, hx: float, hz: float, vel: float) -> void:
	add_child(node)
	obstacles.append({"node": node, "hx": hx, "hz": hz, "vel": vel, "alive": true})

func _build_refuge(fz: float) -> void:
	for fx in [-ROAD_HALF, ROAD_HALF]:
		var pole := BoxMesh.new()
		pole.size = Vector3(0.6, 6.0, 0.6)
		add_child(Build.mi(pole, Color(0.9, 0.8, 0.2), Vector3(fx, 3.0, fz)))
	var beam := BoxMesh.new()
	beam.size = Vector3(ROAD_HALF * 2.0 + 0.6, 0.6, 0.6)
	add_child(Build.mi(beam, Color(0.9, 0.8, 0.2), Vector3(0, 6.0, fz)))
	add_child(Build.label3d("УБЕЖИЩЕ", Vector3(0, 8.0, fz), 90, Color(0.5, 1, 0.6)))
	var hut := BoxMesh.new()
	hut.size = Vector3(8, 4, 6)
	add_child(Build.mi(hut, Color(0.55, 0.4, 0.3), Vector3(14, 2.0, fz - 8)))

func _car_passengers() -> void:
	# пассажиры: мама, птенцы и документы
	mother_root = Node3D.new()
	mother_root.position = Vector3(0, 1.65, 0.5)
	mother_root.scale = Vector3.ONE * 0.5
	mother_root.rotation_degrees.y = 180.0
	car.add_child(mother_root)
	mother = Build.make_mother()
	mother_root.add_child(mother)
	for i in 5:
		var c := PlayerScript.make_chick(COLORS[i])
		c.scale = Vector3.ONE * 0.6
		c.position = Vector3(-0.6 + (i % 3) * 0.6, 1.62, -0.6 - (i / 3) * 0.7)
		c.rotation.y = 0.0
		car.add_child(c)
		car_chicks.append(c)
	docs = Node3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.9, 0.3, 0.6)
	docs.add_child(Build.mi(dm, Color(0.55, 0.35, 0.15), Vector3.ZERO))
	var sheet := BoxMesh.new()
	sheet.size = Vector3(0.8, 0.05, 0.5)
	docs.add_child(Build.mi(sheet, Color(1, 1, 1), Vector3(0, 0.18, 0)))
	docs.add_child(Build.label3d("ДОКУМЕНТЫ", Vector3(0, 0.9, 0), 40, Color(1, 0.95, 0.5)))
	docs.position = Vector3(0, 1.0, 1.9)
	car.add_child(docs)

func _phase_drive() -> void:
	_set_sky(Color(0.45, 0.32, 0.45), Color(1.0, 0.8, 0.75), 0.8, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mid := -ROAD_LEN / 2.0
	var rlen := ROAD_LEN + 120.0
	Build.box(self, Vector3(0, -0.3, mid), Vector3(160, 0.2, rlen), Color(0.18, 0.34, 0.2))
	var road := BoxMesh.new()
	road.size = Vector3(ROAD_HALF * 2.0, 0.1, rlen)
	add_child(Build.mi(road, Color(0.14, 0.14, 0.17), Vector3(0, -0.15, mid)))
	for ex in [-ROAD_HALF, ROAD_HALF]:
		var edge := BoxMesh.new()
		edge.size = Vector3(0.25, 0.04, rlen)
		add_child(Build.mi(edge, Color(0.95, 0.95, 0.85), Vector3(ex * 0.97, -0.08, mid)))
	var z := 30.0
	while z > -ROAD_LEN - 50.0:
		for lx in [-2.0, 2.0]:
			var dash := BoxMesh.new()
			dash.size = Vector3(0.2, 0.04, 3.0)
			add_child(Build.mi(dash, Color(0.95, 0.95, 0.8), Vector3(lx, -0.08, z)))
		z -= 8.0
	z = 30.0
	while z > -ROAD_LEN - 50.0:
		for sx in [-1.0, 1.0]:
			var x: float = sx * rng.randf_range(9.0, 16.0)
			var tk := CylinderMesh.new()
			tk.top_radius = 0.25
			tk.bottom_radius = 0.3
			tk.height = 2.0
			add_child(Build.mi(tk, Color(0.35, 0.22, 0.1), Vector3(x, 1.0, z)))
			var lv := SphereMesh.new()
			lv.radius = 1.5
			lv.height = 3.0
			add_child(Build.mi(lv, Color(0.12, 0.4, 0.15), Vector3(x, 3.0, z)))
		z -= 14.0
	_build_refuge(-ROAD_LEN)
	# препятствия
	var cz := -45.0
	while cz > -ROAD_LEN + 25.0:
		var kind := rng.randi() % 4
		var x := rng.randf_range(-4.2, 4.2)
		if kind == 0:
			for i in 3:
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.4
				cm.height = 0.9
				var cn := Build.mi(cm, Color(1, 0.5, 0.1), Vector3(x + (i - 1) * 0.9, 0.45, cz))
				_obstacle(cn, 0.4, 0.4, 0.0)
		elif kind == 1:
			var bm := BoxMesh.new()
			bm.size = Vector3(3.2, 0.9, 0.6)
			var bn := Build.mi(bm, Color(0.9, 0.2, 0.2), Vector3(x, 0.45, cz))
			_obstacle(bn, 1.6, 0.3, 0.0)
		elif kind == 2:
			var pc := _make_car(Color(rng.randf(), rng.randf(), rng.randf()).lightened(0.2))
			pc.position = Vector3(x, 0, cz)
			_obstacle(pc, 1.0, 2.1, -5.0)
		else:
			var oc := _make_car(Color(0.2, 0.5, 0.9))
			oc.position = Vector3(x, 0, cz)
			oc.rotation_degrees.y = 180.0
			_obstacle(oc, 1.0, 2.1, 9.0)
		cz -= rng.randf_range(9.0, 13.0)
	# наша машина
	car = _make_car(Color(0.9, 0.3, 0.2))
	add_child(car)
	car.position = Vector3(0, 0, 0)
	_add_player(Vector3(0, 0, 0))
	player.visible = false
	player.set_physics_process(false)
	_car_passengers()
	car_hp = 5
	car_speed = 0.0
	lbl_timer.visible = true
	lbl_obj.text = "Рули: ВВЕРХ/ВНИЗ — скорость, ВЛЕВО/ВПРАВО — поворот. Не врежься!"
	_chapter("ГЛАВА 8 · ПОБЕГ НА МАШИНЕ", "Рули джойстиком! Объезжай конусы, барьеры и машины. Жми вверх — быстрее.")

func _update_drive(delta: float) -> void:
	drive_t += delta
	car_inv = maxf(0.0, car_inv - delta)
	controls.use_visible = false
	var inp: Vector2 = controls.get_move()
	var go := drive_t > 2.5
	var target := 0.0
	var vx := 0.0
	if go:
		target = 13.0 - inp.y * 6.0
		vx = inp.x * 9.0
	car_speed = move_toward(car_speed, target, 14.0 * delta)
	car.position.z -= car_speed * delta
	car.position.x = clampf(car.position.x + vx * delta, -ROAD_HALF + 1.2, ROAD_HALF - 1.2)
	car.rotation.y = lerp_angle(car.rotation.y, -inp.x * 0.25, minf(1.0, 8.0 * delta))
	car.visible = car_inv <= 0.0 or int(car_inv * 12.0) % 2 == 0
	player.global_position = car.global_position
	lbl_timer.text = "До убежища: %d м" % int(maxf(0.0, ROAD_LEN + car.position.z))
	lbl_state.text = "Прочность: %d / 5" % maxi(car_hp, 0)
	lbl_state.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	for ob in obstacles:
		if not ob["alive"]:
			continue
		var n: Node3D = ob["node"]
		n.position.z += ob["vel"] * delta
		if car_inv > 0.0:
			continue
		var d: Vector3 = n.position - car.position
		if absf(d.x) < 1.0 + ob["hx"] and absf(d.z) < 2.1 + ob["hz"]:
			ob["alive"] = false
			n.visible = false
			car_hp -= 1
			car_inv = 1.5
			car_speed *= 0.3
			if car_hp <= 0:
				_stop_all()
				lbl_timer.visible = false
				_show_end("ПОРАЖЕНИЕ\nМашина разбита...", "Нажми, чтобы попробовать снова")
				return
			show_msg("Врезались! Прочность: %d" % car_hp, 1.5)
	if car.position.z <= -ROAD_LEN:
		_drive_end()

func _drive_end() -> void:
	await _arrival_scene(true)
	finished = true
	Save.unlock_drun()
	_show_end("КОНЕЦ ГЛАВЫ\nОткрыт новый персонаж: ДРУН!\nПродолжение — в МУЛЬТИПЛЕЕРЕ!", "Нажми, чтобы вернуться в меню\n(Сюжет → выбор персонажа; «Мультиплеер по LAN» в меню)")

# Приезд к убежищу: птенцы улетают, мама берёт документы и улетает. Используется и в сюжете Друна.
func _arrival_scene(cameo: bool) -> void:
	lbl_timer.visible = false
	_begin_cutscene()
	var stop_z := car.position.z - 10.0
	create_tween().tween_property(car, "position:z", stop_z, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	car.rotation.y = 0.0
	car.visible = true
	_move_cam(Vector3(-7, 5, stop_z + 9), Vector3(0, 1.5, stop_z), 1.8)
	_sub("Приехали! Убежище рядом.")
	if cameo:
		var dn = DrunAI.new()
		add_child(dn)
		dn.global_position = Vector3(6, 6, stop_z + 6)
		dn.mode = "idle"
	await _wait(2.6)
	if cameo:
		_sub("В небе над убежищем кружит Друн: он видит, что все добрались.")
		await _wait(2.4)
	_sub("Мама: «Птенцы, улетайте! Скорее!»")
	await _wait(3.0)
	_sub("Птенцы улетают!")
	for i in car_chicks.size():
		var c: Node3D = car_chicks[i]
		c.reparent(self)
		var dest := c.global_position + Vector3(randf_range(-16.0, 16.0), 26.0 + i * 2.0, randf_range(-30.0, -14.0))
		var tw := create_tween()
		tw.tween_interval(i * 0.25)
		tw.tween_property(c, "global_position", dest, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var sp := create_tween().set_loops(8)
		sp.tween_property(c, "rotation_degrees:z", 25.0, 0.15)
		sp.tween_property(c, "rotation_degrees:z", -25.0, 0.15)
	_move_cam(Vector3(-7, 9, stop_z + 12), Vector3(0, 6, stop_z - 6), 2.5)
	await _wait(4.2)
	_sub("Мама берёт документы...")
	mother_root.reparent(self)
	docs.reparent(mother_root)
	create_tween().tween_property(docs, "position", Vector3(0, 1.0, -1.1), 0.8)
	var hop := create_tween()
	hop.tween_property(mother_root, "position:y", mother_root.position.y + 1.2, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _wait(1.6)
	_sub("Мама взлетает и уносит документы!")
	_flap()
	create_tween().tween_property(env, "background_color", Color(1.0, 0.65, 0.4), 6.0)
	cam_mode = "mother"
	mother_root.rotation_degrees.y = 180.0
	var fly := create_tween()
	fly.tween_property(mother_root, "position", mother_root.position + Vector3(10, 45, -60), 6.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(6.0)
	_sub("Мама и птенцы на свободе. Документы спасены!")
	await _wait(3.0)

# ---------- цикл ----------
func _process(delta: float) -> void:
	time += delta
	pick_cd = maxf(0.0, pick_cd - delta)
	if msg_t > 0.0:
		msg_t -= delta
		msg.modulate.a = clampf(msg_t, 0.0, 1.0)
		if msg_t <= 0.0:
			msg.text = ""
	if cutscene:
		if cam_mode == "van":
			cam_pos = van.global_position + Vector3(-9, 6, 10)
			cam_target = van.global_position + Vector3(3, 1, 0)
		elif cam_mode == "mother":
			cam_pos = mother_root.global_position + Vector3(-6, 3, 12)
			cam_target = mother_root.global_position
		cam.global_position = cam.global_position.lerp(cam_pos, minf(1.0, 5.0 * delta))
		cam.look_at(cam_target)
		return
	var follow: Vector3 = player.global_position
	if phase == 7 and car:
		follow = car.global_position + Vector3(0, 0, -6)
	cam.global_position = cam.global_position.lerp(follow + CAM_OFFSET, minf(1.0, 6.0 * delta))
	if game_over or busy:
		return
	match phase:
		0: _update_base()
		1: _update_vent()
		2: _update_yard(delta)
		4: _update_field(delta)
		6: _update_garage(delta)
		7: _update_drive(delta)
		3: _update_truck(delta)
		_: _update_extra(delta)
