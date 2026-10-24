extends CharacterBody3D
# Агент Интерпола: патруль -> подозрение (шкала "?") -> погоня ("!") -> потеря цели.
# Босс — тот же скрипт, только сильнее и с ключом от клетки.

signal knocked_out(silent: bool, boss: bool)

enum S { PATROL, CHASE, STUN, DOWN }

var state := S.PATROL
var waypoints: Array = []
var wp := 0
var player
var is_boss := false

var hp := 4.0
var speed_patrol := 2.0
var speed_chase := 4.2
var view_dist := 9.0
var hearing := 0.0
var fov_half := 40.0
var stun_time := 0.35

var detect := 0.0
var lose_t := 0.0
var atk_cd := 0.0
var wait_t := 0.0
var stun_t := 0.0
var knock := Vector3.ZERO
var last_seen := Vector3.ZERO

var body: Node3D
var base_scale := Vector3.ONE
var cone: MeshInstance3D
var cone_mat: StandardMaterial3D
var mark: Label3D

func _mi(mesh: PrimitiveMesh, col: Color, pos: Vector3) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

func _ready() -> void:
	if is_boss:
		hp = 12.0
		speed_patrol = 2.2
		speed_chase = 5.0
		view_dist = 10.0
		stun_time = 0.12
	add_to_group("guards")
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var s := 1.3 if is_boss else 1.0
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45 * s
	sh.height = 1.8 * s
	cs.shape = sh
	cs.position.y = 0.9 * s
	add_child(cs)

	body = Node3D.new()
	body.scale = Vector3.ONE * s
	base_scale = body.scale
	add_child(body)
	var suit := Color(0.6, 0.08, 0.1) if is_boss else Color(0.1, 0.15, 0.4)
	var cap_m := CapsuleMesh.new()
	cap_m.radius = 0.4
	cap_m.height = 1.5
	body.add_child(_mi(cap_m, suit, Vector3(0, 0.8, 0)))
	var head := SphereMesh.new()
	head.radius = 0.27
	head.height = 0.54
	body.add_child(_mi(head, Color(0.9, 0.72, 0.58), Vector3(0, 1.68, 0)))
	var hat := CylinderMesh.new()
	hat.top_radius = 0.26
	hat.bottom_radius = 0.3
	hat.height = 0.16
	body.add_child(_mi(hat, Color(0.05, 0.05, 0.1), Vector3(0, 1.92, 0)))
	var glasses := BoxMesh.new()
	glasses.size = Vector3(0.42, 0.08, 0.1)
	body.add_child(_mi(glasses, Color.BLACK, Vector3(0, 1.7, -0.25)))
	var tag := Label3D.new()
	tag.text = "INTERPOL"
	tag.font_size = 40
	tag.pixel_size = 0.008
	tag.position = Vector3(0, 1.0, 0.42)
	body.add_child(tag)

	mark = Label3D.new()
	mark.font_size = 96
	mark.pixel_size = 0.01
	mark.outline_size = 14
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.position = Vector3(0, 2.7 * s, 0)
	mark.visible = false
	add_child(mark)

	_make_cone()
	if waypoints.size() > 1:
		var d: Vector3 = waypoints[1] - position
		rotation.y = atan2(-d.x, -d.z)

func _make_cone() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var span := deg_to_rad(fov_half * 2.0)
	var a0 := -deg_to_rad(fov_half)
	for i in n:
		var a1 := a0 + span * float(i) / n
		var a2 := a0 + span * float(i + 1) / n
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a2), 0, -cos(a2)) * view_dist)
		st.add_vertex(Vector3(sin(a1), 0, -cos(a1)) * view_dist)
	cone = MeshInstance3D.new()
	cone.mesh = st.commit()
	cone_mat = StandardMaterial3D.new()
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_mat.albedo_color = Color(1, 0.95, 0.3, 0.22)
	cone.material_override = cone_mat
	cone.position.y = 0.06
	add_child(cone)

func is_alert() -> bool:
	return state == S.CHASE or state == S.STUN

func is_down() -> bool:
	return state == S.DOWN

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _face(d: Vector3, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(1.0, 8.0 * delta))

func _move_to(target: Vector3, spd: float, delta: float) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.01:
		velocity = Vector3.ZERO
		return
	d = d.normalized()
	_face(d, delta)
	velocity = d * spd
	move_and_slide()

func _can_see(f: float, dist: float, omni: bool) -> bool:
	var maxd := view_dist * (1.2 if omni else f)
	if dist > maxd:
		return false
	if not omni and dist > 1.5:
		var to: Vector3 = player.global_position - global_position
		to.y = 0.0
		var fwd: Vector3 = -global_transform.basis.z
		if fwd.dot(to.normalized()) < cos(deg_to_rad(fov_half)):
			return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1, 0), player.global_position + Vector3(0, 0.5, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _physics_process(delta: float) -> void:
	if state == S.DOWN:
		return
	atk_cd -= delta
	var f := 0.55 if player.sneaking else 1.0
	cone.scale = cone.scale.lerp(Vector3(f, 1.0, f), minf(1.0, 6.0 * delta))
	var dist := 999.0
	var sees := false
	if player.alive:
		dist = _flat_dist(player.global_position)
		sees = _can_see(f, dist, state == S.CHASE)
	match state:
		S.PATROL:
			_patrol(delta, sees, dist, f)
		S.CHASE:
			_chase(delta, sees, dist)
		S.STUN:
			_stun(delta)
	_update_visual()

func _patrol(delta: float, sees: bool, dist: float, f: float) -> void:
	if sees:
		detect += (0.8 + (1.0 - dist / (view_dist * f)) * 2.2) * delta
	elif hearing > 0.0 and not player.sneaking and player.velocity.length() > 1.0 and dist < hearing:
		detect += 1.6 * delta
	else:
		detect = maxf(0.0, detect - 0.4 * delta)
	if detect >= 1.0:
		state = S.CHASE
		lose_t = 4.0
		last_seen = player.global_position
		return
	if waypoints.is_empty():
		return
	if wait_t > 0.0:
		wait_t -= delta
		velocity = Vector3.ZERO
		var d: Vector3 = waypoints[wp] - global_position
		_face(d, delta)
		return
	var target: Vector3 = waypoints[wp]
	if _flat_dist(target) < 0.6:
		wp = (wp + 1) % waypoints.size()
		wait_t = 1.2
		return
	_move_to(target, speed_patrol, delta)

func _chase(delta: float, sees: bool, dist: float) -> void:
	if sees:
		last_seen = player.global_position
		lose_t = 4.0
	else:
		lose_t -= delta
		if lose_t <= 0.0:
			state = S.PATROL
			detect = 0.0
			wait_t = 1.0
			return
	if player.alive and dist < 1.6 and atk_cd <= 0.0:
		atk_cd = 1.0 if is_boss else 1.3
		player.hit(global_position)
	if _flat_dist(last_seen) > 0.8:
		_move_to(last_seen, speed_chase, delta)
	else:
		velocity = Vector3.ZERO

func _stun(delta: float) -> void:
	stun_t -= delta
	velocity = knock
	knock = knock.move_toward(Vector3.ZERO, 25.0 * delta)
	move_and_slide()
	if stun_t <= 0.0:
		state = S.CHASE
		lose_t = 5.0
		last_seen = player.global_position

func take_hit(from: Vector3, dmg: float) -> void:
	if state == S.DOWN:
		return
	var to := from - global_position
	to.y = 0.0
	to = to.normalized()
	var behind: bool = (-global_transform.basis.z).dot(to) < -0.2 and state == S.PATROL
	if behind:
		if is_boss:
			dmg *= 3.0
		else:
			_down(true)
			return
	hp -= dmg
	_flash()
	if hp <= 0.0:
		_down(false)
		return
	state = S.STUN
	stun_t = stun_time
	knock = -to * (5.0 if is_boss else 8.0)
	detect = 1.0

func _flash() -> void:
	var t := create_tween()
	t.tween_property(body, "scale", base_scale * 1.2, 0.05)
	t.tween_property(body, "scale", base_scale, 0.1)

func _down(silent: bool) -> void:
	state = S.DOWN
	remove_from_group("guards")
	collision_layer = 0
	collision_mask = 0
	cone.visible = false
	mark.visible = false
	var t := create_tween()
	t.tween_property(body, "rotation_degrees:z", 90.0, 0.25)
	t.parallel().tween_property(body, "position:y", 0.45, 0.25)
	knocked_out.emit(silent, is_boss)

func _update_visual() -> void:
	if is_alert():
		mark.text = "!"
		mark.modulate = Color(1, 0.2, 0.2)
		mark.scale = Vector3.ONE
		mark.visible = true
		cone_mat.albedo_color = Color(1, 0.1, 0.1, 0.32)
	elif detect > 0.05:
		mark.text = "?"
		mark.modulate = Color(1, 1.0 - detect * 0.6, 0.1)
		mark.scale = Vector3.ONE * (0.7 + detect * 0.6)
		mark.visible = true
		cone_mat.albedo_color = Color(1, 0.9 - 0.6 * detect, 0.1, 0.25)
	else:
		mark.visible = false
		cone_mat.albedo_color = Color(1, 0.95, 0.3, 0.22)
