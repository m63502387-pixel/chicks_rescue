extends "res://story.gd"
# СЮЖЕТ ДРУНА. Играем за дрона-разведчика. Идёт параллельно сюжету птенцов:
# 10 Слежка за фургоном (пока птенцы едут на крыше) -> 11 Склад Интерпола (тот же двор, что в главе «Грузовик»:
# Друн вырубает охрану, пока птенцы взламывают грузовик) -> 12 Финал у убежища (птенцы приезжают на машине,
# мама улетает с документами, Друн звонит в штаб)

const DrunPlayer = preload("res://drun_player.gd")

static var dcheckpoint := 10

const VAN_SPEED := 7.0
const TRACK_R := 16.0

var path_pts: Array = []
var seg_lens: Array = []
var path_len := 0.0
var van_prog := 0.0
var far_t := 0.0
var sentries: Array = []
var stage := 0
var phone: Node3D
var phone_lbl: Label3D
var d_done := false

func _init() -> void:
	start_hp = 3

# ---------- точки расширения ----------
func _start_phase() -> int:
	return dcheckpoint

func _new_player():
	return DrunPlayer.new()

func _phase_extra() -> void:
	controls._btn["peck"]["text"] = "РАЗРЯД"
	if phase == 12:
		_phase_final()
	elif phase == 11:
		_phase_depot()
	else:
		_phase_track()

func _update_extra(delta: float) -> void:
	if phase == 12:
		_update_final(delta)
	elif phase == 11:
		_update_depot(delta)
	else:
		_update_track(delta)

func _hud() -> void:
	if player:
		lbl_chicks.text = "Заряд Друна: %d / %d" % [player.chicks, start_hp]

func _on_hurt(left: int) -> void:
	_hud()
	if left > 0:
		show_msg("Друна задели! Заряд: %d" % left, 2.0)

func _lose() -> void:
	_stop_all()
	_show_end("ПОРАЖЕНИЕ\nДрун потерял заряд...", "Нажми, чтобы попробовать снова")

func _goto(next: int) -> void:
	if busy:
		return
	busy = true
	dcheckpoint = next
	controls.enabled = false
	controls.use_visible = false
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.6)
	t.tween_callback(func(): get_tree().reload_current_scene())

# ---------- общее ----------
func _path_at(d: float) -> Array:
	d = clampf(d, 0.0, path_len)
	for i in seg_lens.size():
		var l: float = seg_lens[i]
		if d <= l or i == seg_lens.size() - 1:
			var a: Vector3 = path_pts[i]
			var b: Vector3 = path_pts[i + 1]
			var dir := (b - a).normalized()
			return [a + dir * minf(d, l), dir]
		d -= l
	return [path_pts[0], Vector3(0, 0, -1)]

func _dist_to_path(p: Vector3) -> float:
	var best := 9999.0
	for i in path_pts.size() - 1:
		var a: Vector3 = path_pts[i]
		var b: Vector3 = path_pts[i + 1]
		var c := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
		best = minf(best, Vector2(p.x, p.z).distance_to(c))
	return best

func _van_riders() -> void:
	van.collision_layer = 0
	(van.get_child(0) as CollisionShape3D).disabled = true
	for i in 5:
		var c := PlayerScript.make_chick(COLORS[i])
		c.position = Vector3(-1.6 + i * 0.75, 2.3, (i % 2) * 0.5 - 0.25)
		c.rotation.y = -PI / 2.0
		van.add_child(c)
	mother_root = Node3D.new()
	mother_root.position = Vector3(1.3, 2.2, 0)
	mother_root.scale = Vector3.ONE * 0.5
	mother_root.rotation_degrees.y = 90.0
	van.add_child(mother_root)
	mother = Build.make_mother()
	mother_root.add_child(mother)

func _arena(w: float, d: float, wall: Color) -> void:
	Build.box(self, Vector3(0, 1.25, -d / 2.0), Vector3(w, 2.5, 1), wall)
	Build.box(self, Vector3(0, 1.25, d / 2.0), Vector3(w, 2.5, 1), wall)
	Build.box(self, Vector3(-w / 2.0, 1.25, 0), Vector3(1, 2.5, d + 1), wall)
	Build.box(self, Vector3(w / 2.0, 1.25, 0), Vector3(1, 2.5, d + 1), wall)

# ---------- глава 1 (10): слежка за фургоном ----------
func _phase_track() -> void:
	_set_sky(Color(0.07, 0.09, 0.2), Color(0.6, 0.65, 0.9), 0.65, 0.7)
	path_pts = [Vector3(-8, 0, 24), Vector3(-8, 0, -50), Vector3(14, 0, -80), Vector3(14, 0, -150),
		Vector3(-10, 0, -180), Vector3(-10, 0, -250), Vector3(0, 0, -285)]
	seg_lens.clear()
	path_len = 0.0
	for i in path_pts.size() - 1:
		var l: float = (path_pts[i + 1] - path_pts[i]).length()
		seg_lens.append(l)
		path_len += l
	Build.box(self, Vector3(0, -0.15, -140), Vector3(140, 0.2, 400), Color(0.14, 0.22, 0.17))
	for i in path_pts.size() - 1:
		var a: Vector3 = path_pts[i]
		var b: Vector3 = path_pts[i + 1]
		var rd := BoxMesh.new()
		rd.size = Vector3(8.0, 0.05, (b - a).length() + 8.0)
		var rn := Build.mi(rd, Color(0.13, 0.13, 0.16), (a + b) / 2.0 + Vector3(0, 0.0, 0))
		rn.rotation.y = atan2((b - a).x, (b - a).z)
		add_child(rn)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var s := 0.0
	while s < path_len:
		var pd: Array = _path_at(s)
		var p: Vector3 = pd[0]
		var dir: Vector3 = pd[1]
		var nrm := Vector3(-dir.z, 0, dir.x)
		for side in [-1.0, 1.0]:
			var w := rng.randf_range(6.0, 11.0)
			var dd := rng.randf_range(6.0, 11.0)
			var h := rng.randf_range(6.0, 16.0)
			var c: Vector3 = p + nrm * side * rng.randf_range(12.0, 22.0)
			if _dist_to_path(c) < 8.0 + maxf(w, dd) * 0.75:
				continue
			var tint := rng.randf_range(0.25, 0.42)
			Build.box(self, Vector3(c.x, h / 2.0, c.z), Vector3(w, h, dd), Color(tint, tint + 0.04, tint + 0.12))
		s += 14.0
	# фургон Интерпола с мамой и птенцами на крыше
	_build_van(path_pts[0])
	van_prog = 0.0
	_van_riders()
	_van_place()
	# патрульные дроны Интерпола
	for sd in [60.0, 105.0, 150.0, 195.0, 240.0]:
		var pd2: Array = _path_at(sd)
		var bp: Vector3 = pd2[0]
		var dr: Vector3 = pd2[1]
		var sph := SphereMesh.new()
		sph.radius = 0.7
		sph.height = 1.4
		var node := Build.mi(sph, Color(0.85, 0.12, 0.12), bp + Vector3(0, 2.4, 0))
		var mt: StandardMaterial3D = sph.material
		mt.emission_enabled = true
		mt.emission = Color(0.9, 0.1, 0.1)
		node.add_child(Build.label3d("INTERPOL", Vector3(0, 1.4, 0), 40, Color(1, 0.5, 0.5)))
		add_child(node)
		sentries.append({"node": node, "base": bp + Vector3(0, 2.4, 0), "n": Vector3(-dr.z, 0, dr.x),
			"ph": rng.randf() * 6.0, "off": 0.0})
	_add_player(path_pts[0] + Vector3(5, 0, 12))
	player.zapped.connect(_on_zap)
	lbl_timer.visible = true
	lbl_obj.text = "Следи за фургоном и не отставай!"
	_chapter("ДРУН · ГЛАВА 1 · СЛЕЖКА", "Птенцы запрыгнули на крышу фургона с мамой! Лети следом, держись рядом (до %d м), облетай дронов Интерпола. РАЗРЯД отключает дрона." % int(TRACK_R))

func _van_place() -> void:
	var pd: Array = _path_at(van_prog)
	var p: Vector3 = pd[0]
	var d: Vector3 = pd[1]
	van.position = p
	van.rotation.y = atan2(-d.z, d.x)

func _on_zap(pos: Vector3) -> void:
	for sn in sentries:
		var n: Node3D = sn["node"]
		if n.visible and _fd(n.global_position, pos) < 3.4:
			sn["off"] = 5.0
			n.visible = false
			show_msg("Дрон Интерпола отключён!", 1.5)

func _update_track(delta: float) -> void:
	if time > 3.0:
		van_prog += VAN_SPEED * delta
	_van_place()
	var dpos: Vector3 = player.global_position
	for sn in sentries:
		var n: Node3D = sn["node"]
		if sn["off"] > 0.0:
			sn["off"] -= delta
			if sn["off"] <= 0.0:
				n.visible = true
		var base: Vector3 = sn["base"]
		var nv: Vector3 = sn["n"]
		n.position = base + nv * sin(time * 1.5 + sn["ph"]) * 10.0
		if n.visible and player.alive and _fd(n.global_position, dpos) < 1.6:
			player.hit(n.global_position)
	var d := _fd(dpos, van.global_position)
	if d > TRACK_R:
		far_t += delta
	else:
		far_t = maxf(0.0, far_t - delta * 2.0)
	var pct := int(clampf(van_prog / path_len, 0.0, 1.0) * 100.0)
	lbl_timer.text = "Фургон: %d м" % int(d)
	lbl_timer.add_theme_color_override("font_color", Color(1, 0.3, 0.3) if far_t > 0.0 else Color(0.5, 1, 0.6))
	lbl_state.text = ("СЛИШКОМ ДАЛЕКО! Догоняй!" if far_t > 0.0 else "Слежка: %d%%" % pct)
	lbl_state.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if far_t > 0.0 else Color(0.6, 1, 0.7))
	if far_t > 5.0:
		busy = true
		_stop_all()
		lbl_timer.visible = false
		_show_end("ПОРАЖЕНИЕ\nФургон потерян...", "Нажми, чтобы попробовать снова")
		return
	if van_prog >= path_len and not d_done:
		d_done = true
		_track_done()

func _track_done() -> void:
	lbl_timer.visible = false
	_begin_cutscene()
	_move_cam(van.position + Vector3(-8, 9, 12), van.position + Vector3(0, 1, 0), 1.5)
	_sub("Фургон остановился у склада Интерпола!")
	await _wait(2.8)
	_sub("Друн: «Передаю координаты. Приступаю к зачистке.»")
	await _wait(3.0)
	await _fade_to(1.0, 0.7).finished
	busy = false
	_goto(11)

# ---------- глава 2 (11): склад Интерпола (двор из главы «Грузовик») ----------
func _spawn_boss(pts: Array) -> void:
	var g = GuardScript.new()
	g.is_boss = true
	g.player = player
	g.waypoints = pts
	g.position = pts[0]
	g.knocked_out.connect(_on_ko)
	add_child(g)

func _phase_depot() -> void:
	_set_sky(Color(0.05, 0.06, 0.12), Color(0.55, 0.6, 0.85), 0.6, 0.8)
	_build_truck_yard()
	# птенцы уже у задних дверей грузовика
	for i in 5:
		var c := PlayerScript.make_chick(COLORS[i])
		c.position = door_pos + Vector3(-0.6 - (i % 2) * 0.8, 0, (i - 2) * 0.55)
		c.rotation.y = -PI / 2.0
		add_child(c)
		var hop := create_tween().set_loops()
		hop.tween_interval(i * 0.15)
		hop.tween_property(c, "position:y", 0.3, 0.2)
		hop.tween_property(c, "position:y", 0.0, 0.2)
	add_child(Build.label3d("ПТЕНЦЫ", door_pos + Vector3(-1.2, 2.6, 0), 60, Color(1, 0.9, 0.4)))
	_add_player(Vector3(-19, 0, 12))
	_spawn_guard([Vector3(-16, 0, 5), Vector3(-16, 0, -11)])
	_spawn_guard([Vector3(-6, 0, 12), Vector3(-6, 0, -12)])
	_spawn_guard([Vector3(-1, 0, -9), Vector3(15, 0, -9), Vector3(15, 0, 2), Vector3(-1, 0, 2)])
	_spawn_guard([Vector3(-20, 0, -13), Vector3(-8, 0, -13)])
	_spawn_boss([Vector3(-14, 0, 10), Vector3(0, 0, 10)])
	lbl_obj.text = "Вырубай агентов Интерпола (РАЗРЯД)."
	_chapter("ДРУН · ГЛАВА 2 · СКЛАД", "Птенцы уже у грузовика! Выруби всю охрану Интерпола, пока они взламывают замок. Со спины разряд бьёт тихо и сильнее. Босс крепче остальных!")

func _update_depot(_delta: float) -> void:
	_update_state()
	controls.use_visible = false
	var n := get_tree().get_nodes_in_group("guards").size()
	lbl_obj.text = "Агентов Интерпола осталось: %d" % n
	if n == 0 and stage == 0:
		stage = 1
		_depot_cleared()

func _depot_cleared() -> void:
	_begin_cutscene()
	_move_cam(door_pos + Vector3(-7, 6, 9), door_pos + Vector3(0, 1.2, 0), 1.6)
	_sub("Все агенты Интерпола вырублены!")
	await _wait(2.6)
	_sub("Птенцы взламывают замок грузовика...")
	await _wait(2.4)
	_door_open()
	_sub("Двери открыты! Птенцы бегут к маме!")
	await _wait(3.2)
	_sub("Дальше птенцы справятся сами. Друн следит за ними сверху...")
	await _wait(3.2)
	await _fade_to(1.0, 0.8).finished
	_sub("Позже. Птенцы и мама бегут на машине к убежищу...")
	await _wait(3.0)
	busy = false
	_goto(12)

# ---------- глава 3 (12): финал у убежища ----------
func _phase_final() -> void:
	_set_sky(Color(0.45, 0.32, 0.45), Color(1.0, 0.8, 0.75), 0.8, 0.9)
	Build.box(self, Vector3(0, -0.3, -30), Vector3(160, 0.2, 240), Color(0.18, 0.34, 0.2))
	var road := BoxMesh.new()
	road.size = Vector3(ROAD_HALF * 2.0, 0.1, 240.0)
	add_child(Build.mi(road, Color(0.14, 0.14, 0.17), Vector3(0, -0.15, -30)))
	var zz := 60.0
	while zz > -90.0:
		for lx in [-2.0, 2.0]:
			var dash := BoxMesh.new()
			dash.size = Vector3(0.2, 0.04, 3.0)
			add_child(Build.mi(dash, Color(0.95, 0.95, 0.8), Vector3(lx, -0.08, zz)))
		zz -= 8.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	zz = 60.0
	while zz > -100.0:
		for sx in [-1.0, 1.0]:
			var x: float = sx * rng.randf_range(9.0, 18.0)
			var tk := CylinderMesh.new()
			tk.top_radius = 0.25
			tk.bottom_radius = 0.3
			tk.height = 2.0
			add_child(Build.mi(tk, Color(0.35, 0.22, 0.1), Vector3(x, 1.0, zz)))
			var lv := SphereMesh.new()
			lv.radius = 1.5
			lv.height = 3.0
			add_child(Build.mi(lv, Color(0.12, 0.4, 0.15), Vector3(x, 3.0, zz)))
		zz -= 14.0
	_build_refuge(-80.0)
	car = _make_car(Color(0.9, 0.3, 0.2))
	add_child(car)
	car.position = Vector3(0, 0, 60)
	_car_passengers()
	lbl_timer.visible = false
	_add_player(Vector3(18, 0, -66))
	lbl_obj.text = "Жди птенцов у убежища."
	_chapter("ДРУН · ГЛАВА 3 · ФИНАЛ", "Друн ждёт у убежища.")
	_final_scene()

func _final_scene() -> void:
	_begin_cutscene()
	_move_cam(Vector3(-9, 7, -58), Vector3(0, 1, -78), 1.0)
	_sub("Друн облетел окрестности. Тихо... Скоро должны приехать птенцы.")
	await _wait(3.2)
	_sub("Вдали показалась красная машина!")
	var drive := create_tween()
	drive.tween_property(car, "position:z", -68.0, 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_move_cam(Vector3(-9, 7, -30), Vector3(0, 1, -50), 1.5)
	await _wait(6.2)
	await _arrival_scene(false)
	_end_cutscene()
	stage = 2
	cam_mode = "free"
	lbl_obj.text = "Позвони в штаб и доложи."
	show_msg("Все в безопасности. Нажми ПОЗВОНИТЬ.", 5.0)

func _update_final(_delta: float) -> void:
	if stage == 2 and not cutscene:
		controls.use_text = "ПОЗВОНИТЬ"
		controls.use_visible = true
		if controls.is_use_down():
			stage = 3
			controls.use_visible = false
			_call_hq()

func _call_hq() -> void:
	_begin_cutscene()
	phone_lbl = Build.label3d("ЗВОНОК...", player.global_position + Vector3(0, 3.4, 0), 70, Color(0.5, 0.95, 1))
	add_child(phone_lbl)
	_move_cam(player.global_position + Vector3(-4, 6, 8), player.global_position + Vector3(0, 2, 0), 1.2)
	_sub("Друн набирает штаб...")
	await _wait(2.4)
	phone_lbl.text = "ШТАБ НА СВЯЗИ"
	_sub("Штаб: «Слушаю, Друн. Докладывай!»")
	await _wait(2.8)
	_sub("Друн: «Агенты Интерпола вырублены.»")
	await _wait(3.0)
	_sub("Друн: «Птенцы уехали. Мама птица в безопасности!»")
	await _wait(3.4)
	_sub("Штаб: «Отличная работа, Друн! Возвращайся домой.»")
	await _wait(3.2)
	finished = true
	_show_end("КОНЕЦ\nДрун выполнил задание!\nПтенцы уехали, мама птица в безопасности.", "Нажми, чтобы вернуться в меню")
