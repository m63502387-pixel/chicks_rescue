extends Node3D
# Режим "Битва за маму птицу":
# 1) катсцена — миллионы птенцов из разных вселенных сражаются с Интерполом;
# 2) геймплей — вынеси раненых птенцов и маму в зону эвакуации, избегая подкрепления.

const PlayerScript = preload("res://player.gd")
const GuardScript = preload("res://guard.gd")
const Net = preload("res://net.gd")
const ControlsScript = preload("res://touch_controls.gd")
const Build = preload("res://build.gd")

const CAM_OFFSET := Vector3(0, 12.0, 8.4)
const CAGE_POS := Vector3(16, 0, -11)
const ZONE_POS := Vector3(-16, 0, 11)
const ZONE_R := 3.6
const MAX_CHICKS := 5
const CARRY_SLOTS := 2
const UNIVERSE_COLORS := [Color(1, 0.85, 0.2), Color(1, 0.45, 0.7), Color(0.4, 0.8, 1),
	Color(0.5, 1, 0.5), Color(0.75, 0.5, 1), Color(1, 0.55, 0.2)]

var player
var controls
var cam: Camera3D
var cam_pos := Vector3.ZERO
var cam_target := Vector3.ZERO
var cam_tw: Tween
var shake := 0.0
var in_cutscene := true
var skip := false
var skip_ok := false
var counting := false
var counter_val := 0.0
var counter_target := 12483907.0

var cage: StaticBody3D
var mother_root: Node3D
var mother: Node3D
var mama_lbl: Label3D
var portals: Array = []
var swarms: Array = []
var cutscene_agents: Array = []
var wounded: Array = []
var saved := 0
var slots_used := 0
var pick_cd := 0.0
var game_over := false
var can_restart := false
var restarting := false
var won := false

var ui: Control
var flash: ColorRect
var lbl_sub: Label
var lbl_counter: Label
var lbl_skip: Label
var lbl_chicks: Label
var lbl_state: Label
var lbl_saved: Label
var lbl_obj: Label
var msg: Label
var overlay: ColorRect
var end_lbl: Label
var msg_t := 0.0

func _ready() -> void:
	randomize()
	_build_env()
	_build_ui()
	_spawn_player()
	_build_level()
	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.make_current()
	cam_pos = Vector3(-8, 20, 24)
	cam_target = CAGE_POS
	cam.global_position = cam_pos
	cam.look_at(cam_target)
	Net.attach(self, player, "battle")
	_cutscene()

# ---------- построение мира ----------
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.85)
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true  # если тормозит на телефоне — поставь false
	add_child(sun)

func _spawn_player() -> void:
	player = PlayerScript.new()
	player.controls = controls
	player.chicks = MAX_CHICKS
	player.position = Vector3(-13, 0, 8)
	player.hurt.connect(_on_hurt)
	player.died.connect(_lose)
	add_child(player)
	player.set_physics_process(false)

func _build_level() -> void:
	var wall := Color(0.38, 0.42, 0.5)
	Build.box(self, Vector3(0, -0.1, 0), Vector3(42, 0.2, 32), Color(0.22, 0.3, 0.26))
	Build.box(self, Vector3(0, 1.25, -15.5), Vector3(42, 2.5, 1), wall)
	Build.box(self, Vector3(0, 1.25, 15.5), Vector3(42, 2.5, 1), wall)
	Build.box(self, Vector3(-20.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	Build.box(self, Vector3(20.5, 1.25, 0), Vector3(1, 2.5, 32), wall)
	Build.box(self, Vector3(-4, 1.25, 2), Vector3(1, 2.5, 14), wall)
	Build.box(self, Vector3(6, 1.25, -4), Vector3(1, 2.5, 14), wall)
	for p in [Vector2(-12, 4), Vector2(-6, -8), Vector2(3.5, 5), Vector2(3.5, -5), Vector2(8, 6),
			Vector2(8, -8), Vector2(13, 0), Vector2(16, -3), Vector2(-16, -8), Vector2(-10, 12)]:
		Build.box(self, Vector3(p.x, 1, p.y), Vector3(2, 2, 2), Color(0.55, 0.38, 0.2))

	# зона эвакуации
	var disc := CylinderMesh.new()
	disc.top_radius = ZONE_R
	disc.bottom_radius = ZONE_R
	disc.height = 0.05
	add_child(Build.mi(disc, Color(0.2, 1, 0.4, 0.35), ZONE_POS + Vector3(0, 0.03, 0)))
	var zmat: StandardMaterial3D = disc.material
	zmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(Build.label3d("ЭВАКУАЦИЯ", ZONE_POS + Vector3(0, 2.6, 0), 80, Color(0.5, 1, 0.6)))

	# клетка и мама
	cage = Build.make_cage()
	cage.position = CAGE_POS
	add_child(cage)
	mother_root = Node3D.new()
	mother_root.position = CAGE_POS
	add_child(mother_root)
	mother = Build.make_mother()
	mother_root.add_child(mother)
	mama_lbl = Build.label3d("МАМА", Vector3(0, 3.6, 0), 80, Color(1, 0.9, 0.4))
	mother_root.add_child(mama_lbl)

	_build_portals()
	_build_agents()

func _build_portals() -> void:
	for i in 6:
		var a := deg_to_rad(100.0 + i * 20.0)
		var pos := CAGE_POS + Vector3(cos(a), 0, sin(a)) * 9.0 + Vector3(0, 5.5, 0)
		var col: Color = UNIVERSE_COLORS[i]
		var pv := Node3D.new()
		add_child(pv)
		pv.look_at_from_position(pos, CAGE_POS + Vector3(0, 1, 0))
		var torus := TorusMesh.new()
		torus.inner_radius = 1.5
		torus.outer_radius = 2.1
		var tm := Build.mi(torus, col)
		tm.rotation_degrees.x = 90.0
		var tmat: StandardMaterial3D = torus.material
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pv.add_child(tm)
		var d := CylinderMesh.new()
		d.top_radius = 1.6
		d.bottom_radius = 1.6
		d.height = 0.05
		var dm := Build.mi(d, Color(col.r, col.g, col.b, 0.35))
		dm.rotation_degrees.x = 90.0
		var dmat: StandardMaterial3D = d.material
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pv.add_child(dm)
		pv.visible = false
		portals.append(pv)

		# рой птенцов этой вселенной
		var ps := CPUParticles3D.new()
		ps.amount = 500
		ps.lifetime = 1.6
		ps.local_coords = false
		ps.emitting = false
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		ps.emission_sphere_radius = 1.4
		ps.direction = Vector3(0, 1, 0)
		ps.spread = 180.0
		ps.initial_velocity_min = 0.5
		ps.initial_velocity_max = 3.0
		ps.gravity = Vector3.ZERO
		ps.scale_amount_min = 0.7
		ps.scale_amount_max = 1.4
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		sm.radial_segments = 6
		sm.rings = 3
		var smat := StandardMaterial3D.new()
		smat.albedo_color = col
		sm.material = smat
		ps.mesh = sm
		ps.position = pos
		add_child(ps)
		swarms.append(ps)

func _make_agent(pos: Vector3, boss := false):
	var g = GuardScript.new()
	g.is_boss = boss
	g.player = player
	g.waypoints = [pos]
	g.position = pos
	add_child(g)
	g.set_physics_process(false)
	g.cone.visible = false
	var d := pos - CAGE_POS
	g.rotation.y = atan2(-d.x, -d.z)
	return g

func _build_agents() -> void:
	var list: Array = []
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		list.append(CAGE_POS + Vector3(cos(a), 0, sin(a)) * 3.2)
	for i in 7:
		var a := deg_to_rad(90.0 + i * 30.0)
		list.append(CAGE_POS + Vector3(cos(a), 0, sin(a)) * 5.8)
	for i in list.size():
		var p: Vector3 = list[i]
		p.x = minf(p.x, 18.8)
		p.z = clampf(p.z, -14.2, 14.0)
		cutscene_agents.append(_make_agent(p))
	cutscene_agents.append(_make_agent(CAGE_POS + Vector3(-4.5, 0, 1.5), true))

func _spawn_guard(pts: Array):
	var g = GuardScript.new()
	g.player = player
	g.waypoints = pts
	g.position = pts[0]
	g.knocked_out.connect(_on_ko)
	add_child(g)
	return g

func _spawn_reinforcements() -> void:
	_spawn_guard([Vector3(-8, 0, 12), Vector3(-8, 0, -10)])
	_spawn_guard([Vector3(1, 0, 12), Vector3(1, 0, -12)])
	_spawn_guard([Vector3(10, 0, 12), Vector3(10, 0, -12)])
	_spawn_guard([Vector3(12, 0, -6), Vector3(19, 0, -6), Vector3(19, 0, -13), Vector3(12, 0, -13)])
	_spawn_guard([Vector3(-14, 0, -2), Vector3(-14, 0, -12)])

# ---------- интерфейс ----------
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

	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	lbl_chicks = _label(Vector2(24, 14), 28)
	lbl_state = _label(Vector2(24, 50), 22)
	lbl_saved = _label(Vector2(24, 80), 22, Color(0.6, 1, 0.7))
	lbl_obj = _label(Vector2(0, 14), 20, Color(1, 0.95, 0.7))
	lbl_obj.anchor_right = 1.0
	lbl_obj.offset_left = 300
	lbl_obj.offset_right = -130
	lbl_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	msg = _label(Vector2(0, 130), 30, Color(1, 0.9, 0.4))
	msg.anchor_right = 1.0
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	lbl_sub = _label(Vector2(0, 0), 32, Color.WHITE)
	lbl_sub.anchor_top = 1.0
	lbl_sub.anchor_bottom = 1.0
	lbl_sub.anchor_right = 1.0
	lbl_sub.offset_top = -120
	lbl_sub.offset_bottom = -60
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_counter = _label(Vector2(0, 24), 34, Color(1, 0.9, 0.3))
	lbl_counter.anchor_right = 1.0
	lbl_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_counter.visible = false
	lbl_skip = _label(Vector2(0, 16), 20, Color(1, 1, 1, 0.8))
	lbl_skip.anchor_right = 1.0
	lbl_skip.offset_right = -24
	lbl_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_skip.text = "Нажми, чтобы пропустить"

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

func _subtitle(t: String) -> void:
	lbl_sub.text = t
	lbl_sub.modulate.a = 0.0
	create_tween().tween_property(lbl_sub, "modulate:a", 1.0, 0.4)

func _flash(dur: float) -> void:
	flash.color.a = 0.85
	create_tween().tween_property(flash, "color:a", 0.0, dur)

func _hud() -> void:
	lbl_chicks.text = "Птенцы: %d / %d" % [player.chicks, MAX_CHICKS]
	lbl_saved.text = "Спасено: %d / %d    Несёшь: %d/%d" % [saved, wounded.size(), slots_used, CARRY_SLOTS]

func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = " " + out
	return out

# ---------- катсцена ----------
func _wait(t: float) -> void:
	var el := 0.0
	while el < t and not skip:
		await get_tree().process_frame
		el += get_process_delta_time()

func _move_cam(pos: Vector3, tgt: Vector3, dur: float) -> void:
	if cam_tw:
		cam_tw.kill()
	cam_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam_tw.tween_property(self, "cam_pos", pos, dur)
	cam_tw.tween_property(self, "cam_target", tgt, dur)

func _pop_text(pos: Vector3) -> void:
	var words := ["БАМ!", "ПАФ!", "КЛЮЮЮВ!", "ЧИК-ЧИРИК!", "БАХ!"]
	var l := Build.label3d(words[randi() % words.size()], pos, 70, Color(1, 0.9, 0.2))
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", pos.y + 2.0, 0.9)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	t.tween_callback(l.queue_free)

func _defeat(g, delay: float) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_callback(func():
		if g.is_down():
			return
		g._down(false)
		shake = maxf(shake, 0.35)
		var dir: Vector3 = g.global_position - CAGE_POS
		dir.y = 0.0
		dir = dir.normalized()
		var tgt: Vector3 = g.position + dir * 3.0
		tgt.x = minf(tgt.x, 19.0)
		tgt.z = clampf(tgt.z, -14.5, 14.5)
		create_tween().tween_property(g, "position", tgt, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_pop_text(g.global_position + Vector3(0, 2.2, 0))
	)

func _cutscene() -> void:
	controls.enabled = false
	controls.visible = false
	for l in [lbl_chicks, lbl_state, lbl_saved, lbl_obj]:
		l.visible = false
	get_tree().create_timer(0.8).timeout.connect(func(): skip_ok = true)

	_subtitle("Интерпол схватил маму-птицу...")
	_move_cam(Vector3(8, 13, 6), CAGE_POS + Vector3(0, 1, 0), 5.0)
	await _wait(5.0)

	_subtitle("Птенцы позвали на помощь ВСЕ вселенные!")
	_move_cam(Vector3(15, 15, 9), Vector3(11, 4, -8), 4.5)
	_flash(0.6)
	for i in portals.size():
		var p: Node3D = portals[i]
		p.visible = true
		p.scale = Vector3.ZERO
		var t := create_tween()
		t.tween_interval(i * 0.25)
		t.tween_property(p, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	counting = true
	lbl_counter.visible = true
	await _wait(4.5)

	_subtitle("МИЛЛИОНЫ ПТЕНЦОВ!")
	_flash(0.5)
	_move_cam(Vector3(24, 9, -3), CAGE_POS + Vector3(0, 1, 0), 4.0)
	for s in swarms:
		s.emitting = true
		var tgt := CAGE_POS + Vector3(randf_range(-3.5, 3.5), 1.2, randf_range(-3.5, 3.5))
		create_tween().tween_property(s, "position", tgt, 3.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await _wait(3.0)

	_subtitle("Интерпол не ожидал такого...")
	_move_cam(Vector3(8, 8, 2), CAGE_POS + Vector3(0, 1, 0), 4.0)
	for i in cutscene_agents.size():
		_defeat(cutscene_agents[i], i * 0.18 + (0.8 if i == cutscene_agents.size() - 1 else 0.0))
	await _wait(4.8)

	for s in swarms:
		s.emitting = false
	for p in portals:
		var t2 := create_tween()
		t2.tween_property(p, "scale", Vector3.ZERO, 0.8)
		t2.tween_callback(func(): p.visible = false)
	counting = false
	lbl_counter.visible = false
	_flash(0.8)
	cage.visible = false
	cage.get_node("Col").set_deferred("disabled", true)
	mama_lbl.queue_free()
	_setup_wounded()
	_subtitle("Победа! Но многие ранены. Выведи раненых к эвакуации!")
	_move_cam(Vector3(10, 16, 6), Vector3(6, 0, -4), 3.5)
	await _wait(4.5)
	await _end_cutscene()

func _end_cutscene() -> void:
	skip = true
	for g in cutscene_agents:
		if not g.is_down():
			g._down(true)
	for s in swarms:
		s.emitting = false
	for p in portals:
		p.visible = false
	lbl_counter.visible = false
	lbl_skip.visible = false
	lbl_sub.text = ""
	if wounded.is_empty():
		_setup_wounded()
	_spawn_reinforcements()
	for l in [lbl_chicks, lbl_state, lbl_saved, lbl_obj]:
		l.visible = true
	lbl_obj.text = "Неси раненых в зелёную зону эвакуации."
	_hud()
	controls.visible = true
	if cam_tw:
		cam_tw.kill()
	cam_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam_tw.tween_property(self, "cam_pos", player.global_position + CAM_OFFSET, 1.6)
	cam_tw.tween_property(self, "cam_target", player.global_position, 1.6)
	await cam_tw.finished
	cam.rotation_degrees = Vector3(-55, 0, 0)
	in_cutscene = false
	controls.enabled = true
	player.set_physics_process(true)
	show_msg("Подкрепление Интерпола! Подбирай раненых (ПОДНЯТЬ).", 4.5)

# ---------- раненые ----------
func _setup_wounded() -> void:
	var spots := [Vector3(12, 0, -9), Vector3(17, 0, -4), Vector3(8, 0, 2),
		Vector3(1, 0, -9), Vector3(-8, 0, -3), Vector3(-13, 0, -9)]
	for i in spots.size():
		var root := Node3D.new()
		root.position = spots[i]
		add_child(root)
		var vis := PlayerScript.make_chick(UNIVERSE_COLORS[i % UNIVERSE_COLORS.size()])
		root.add_child(vis)
		_add_wounded(root, vis, "chick", 1, 1.6)
	_add_wounded(mother_root, mother, "mother", 2, 3.2)

func _add_wounded(root: Node3D, vis: Node3D, kind: String, need: int, ly: float) -> void:
	var lbl := Build.label3d("+", Vector3(0, ly, 0), 110, Color(1, 0.2, 0.2))
	root.add_child(lbl)
	var w := {"root": root, "vis": vis, "kind": kind, "need": need, "state": 0, "label": lbl, "ly": ly}
	_lay(w)
	wounded.append(w)

func _lay(w: Dictionary) -> void:
	var vis: Node3D = w["vis"]
	vis.scale = Vector3.ONE
	if w["kind"] == "mother":
		vis.rotation_degrees = Vector3(0, 180, 75)
		vis.position = Vector3(0, 0.5, 0)
	else:
		vis.rotation_degrees = Vector3(0, 0, 90)
		vis.position = Vector3(0, 0.4, 0)
	var lbl: Label3D = w["label"]
	lbl.visible = true
	w["state"] = 0

func _fd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _set_speed() -> void:
	player.speed_mult = 1.0 - 0.14 * slots_used

func _update_wounded(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var ppos: Vector3 = player.global_position
	var near_idx := -1
	var best := 2.4
	var order := 0
	for i in wounded.size():
		var w: Dictionary = wounded[i]
		var root: Node3D = w["root"]
		var st := int(w["state"])
		if st == 0:
			var lbl: Label3D = w["label"]
			lbl.position.y = float(w["ly"]) + sin(t * 4.0) * 0.15
			var d := _fd(root.global_position, ppos)
			if d < best:
				best = d
				near_idx = i
		elif st == 1:
			var idx: int = player.trail.size() - 1 - (player.followers.size() + 1 + order) * 6
			var tp := ppos
			if idx >= 0:
				tp = player.trail[idx]
			root.global_position = root.global_position.lerp(tp, minf(1.0, 10.0 * delta))
			root.rotation.y = player.rotation.y
			order += int(w["need"])

	# подбор
	controls.use_text = "ПОДНЯТЬ"
	controls.use_visible = near_idx != -1
	if near_idx != -1 and controls.is_use_down() and pick_cd <= 0.0:
		pick_cd = 0.4
		var pw: Dictionary = wounded[near_idx]
		if slots_used + int(pw["need"]) <= CARRY_SLOTS:
			pw["state"] = 1
			var v: Node3D = pw["vis"]
			v.rotation_degrees = Vector3.ZERO
			v.position = Vector3.ZERO
			v.scale = Vector3.ONE * (0.55 if pw["kind"] == "mother" else 1.0)
			var l2: Label3D = pw["label"]
			l2.visible = false
			slots_used += int(pw["need"])
			_set_speed()
			_hud()
			show_msg("Раненый на руках! Неси в зелёную зону.", 2.0)
		else:
			show_msg("Руки заняты! Сначала отнеси раненых.", 2.0)

	# эвакуация
	if slots_used > 0 and _fd(ppos, ZONE_POS) < ZONE_R:
		for w in wounded:
			if int(w["state"]) == 1:
				w["state"] = 2
				saved += 1
				var r: Node3D = w["root"]
				r.global_position = ZONE_POS + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
				r.rotation.y = 0.0
				var v2: Node3D = w["vis"]
				v2.scale = Vector3.ONE * (0.75 if w["kind"] == "mother" else 1.0)
				var hop := create_tween().set_loops()
				hop.tween_property(v2, "position:y", 0.5, 0.25 + randf() * 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				hop.tween_property(v2, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		slots_used = 0
		_set_speed()
		_hud()
		show_msg("Раненые эвакуированы!", 2.0)
		if saved >= wounded.size():
			_win()

# ---------- события ----------
func _on_hurt(left: int) -> void:
	_hud()
	if left <= 0:
		return
	for i in range(wounded.size() - 1, -1, -1):
		var w: Dictionary = wounded[i]
		if int(w["state"]) == 1:
			slots_used -= int(w["need"])
			_set_speed()
			var r: Node3D = w["root"]
			r.global_position = player.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
			r.rotation = Vector3.ZERO
			_lay(w)
			_hud()
			show_msg("Раненый выпал! Подбери его снова!", 2.5)
			return
	show_msg("Птенца поймали! Осталось: %d" % left, 2.0)

func _on_ko(silent: bool, _was_boss: bool) -> void:
	show_msg("Тихий нокаут!" if silent else "Агент нокаутирован!", 2.0)

func _show_end(t: String, go_menu: bool) -> void:
	game_over = true
	won = go_menu
	overlay.visible = true
	end_lbl.text = t + ("\n\nНажми, чтобы вернуться в меню" if go_menu else "\n\nНажми, чтобы попробовать снова")
	get_tree().create_timer(1.2).timeout.connect(func(): can_restart = true)

func _stop_all() -> void:
	player.set_physics_process(false)
	controls.use_visible = false
	for g in get_tree().get_nodes_in_group("guards"):
		g.set_physics_process(false)

func _lose() -> void:
	_stop_all()
	_show_end("ПОРАЖЕНИЕ\nВсех птенцов поймали...", false)

func _win() -> void:
	_stop_all()
	_show_end("ПОБЕДА!\nВсе раненые в безопасности!", true)

func _input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventKey and e.pressed)
	if in_cutscene:
		if tap and skip_ok:
			skip = true
		return
	if not game_over or not can_restart or restarting or not tap:
		return
	restarting = true
	if won:
		get_tree().change_scene_to_file("res://menu.tscn")
	else:
		get_tree().reload_current_scene()

func _process(delta: float) -> void:
	pick_cd = maxf(0.0, pick_cd - delta)
	if msg_t > 0.0:
		msg_t -= delta
		msg.modulate.a = clampf(msg_t, 0.0, 1.0)
		if msg_t <= 0.0:
			msg.text = ""
	if in_cutscene:
		if counting:
			counter_val = lerpf(counter_val, counter_target, 1.0 - exp(-1.2 * delta))
			lbl_counter.text = "Птенцов из других вселенных: " + _fmt(int(counter_val))
		var off := Vector3.ZERO
		if shake > 0.0:
			off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake
			shake = maxf(0.0, shake - delta * 0.35)
		cam.global_position = cam_pos + off
		cam.look_at(cam_target)
		return
	cam.global_position = cam.global_position.lerp(player.global_position + CAM_OFFSET, minf(1.0, 6.0 * delta))
	if game_over:
		return
	var alert := false
	for g in get_tree().get_nodes_in_group("guards"):
		if g.is_alert():
			alert = true
			break
	lbl_state.text = "ТРЕВОГА!" if alert else "Скрытно"
	lbl_state.add_theme_color_override("font_color", Color(1, 0.3, 0.3) if alert else Color(0.5, 1, 0.5))
	if player.alive:
		_update_wounded(delta)
