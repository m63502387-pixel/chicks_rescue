extends CharacterBody3D
# Отряд птенцов: ведёт один, остальные идут следом. Чем больше птенцов — тем сильнее клюв.

signal hurt(remaining: int)
signal died

const RUN_SPEED := 6.0
const SNEAK_SPEED := 2.6
const PECK_COOLDOWN := 0.6
const PECK_RANGE := 2.1

var controls
var chicks := 3
var alive := true
var sneaking := false
var invuln := 0.0
var peck_cd := 0.0
var knock := Vector3.ZERO
var speed_mult := 1.0
var leader: Node3D
var followers: Array[Node3D] = []
var trail: Array[Vector3] = []

static func _mi(mesh: PrimitiveMesh, col: Color, pos: Vector3) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

static func make_chick(col: Color) -> Node3D:
	var n := Node3D.new()
	var body := SphereMesh.new()
	body.radius = 0.4
	body.height = 0.8
	n.add_child(_mi(body, col, Vector3(0, 0.4, 0)))
	var beak := CylinderMesh.new()
	beak.top_radius = 0.0
	beak.bottom_radius = 0.12
	beak.height = 0.3
	var b := _mi(beak, Color(1, 0.5, 0.1), Vector3(0, 0.5, -0.5))
	b.rotation_degrees.x = -90.0
	n.add_child(b)
	for sx in [-1, 1]:
		var eye := SphereMesh.new()
		eye.radius = 0.06
		eye.height = 0.12
		n.add_child(_mi(eye, Color.BLACK, Vector3(0.17 * sx, 0.62, -0.3)))
	return n

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.4
	sh.height = 1.0
	cs.shape = sh
	cs.position.y = 0.5
	add_child(cs)
	rotation.y = -PI / 2.0
	leader = make_chick(Color(1, 0.85, 0.2))
	add_child(leader)
	var cols := [Color(1, 0.92, 0.45), Color(1, 0.75, 0.3)]
	for i in range(chicks - 1):
		var f := make_chick(cols[i % 2])
		f.top_level = true
		add_child(f)
		f.global_position = global_position + Vector3(-0.9 * (i + 1), 0, 0)
		followers.append(f)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	invuln = maxf(0.0, invuln - delta)
	peck_cd = maxf(0.0, peck_cd - delta)
	sneaking = controls.sneak
	var inp: Vector2 = controls.get_move()
	var spd := (SNEAK_SPEED if sneaking else RUN_SPEED) * speed_mult
	if inp.length() > 0.15:
		rotation.y = lerp_angle(rotation.y, atan2(-inp.x, -inp.y), minf(1.0, 14.0 * delta))
	var want_peck: bool = controls.consume_peck()
	if want_peck and peck_cd <= 0.0:
		_peck()
	knock = knock.move_toward(Vector3.ZERO, 20.0 * delta)
	velocity = Vector3(inp.x, 0, inp.y) * spd + knock
	move_and_slide()

	leader.scale.y = lerpf(leader.scale.y, 0.7 if sneaking else 1.0, minf(1.0, 12.0 * delta))
	leader.visible = invuln <= 0.0 or int(invuln * 12.0) % 2 == 0

	if trail.is_empty() or trail[-1].distance_to(global_position) > 0.2:
		trail.append(global_position)
		if trail.size() > 120:
			trail.pop_front()
	for i in followers.size():
		var idx := trail.size() - 1 - (i + 1) * 6
		if idx >= 0:
			followers[i].global_position = followers[i].global_position.lerp(trail[idx], minf(1.0, 10.0 * delta))
		followers[i].rotation.y = rotation.y

func _peck() -> void:
	peck_cd = PECK_COOLDOWN
	var fwd := -global_transform.basis.z
	var dmg := 1.0 + 0.5 * (chicks - 1)
	for g in get_tree().get_nodes_in_group("guards"):
		var to: Vector3 = g.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < PECK_RANGE and (d < 0.8 or fwd.dot(to.normalized()) > 0.3):
			g.take_hit(global_position, dmg)
	knock += fwd * 4.0
	for n in [leader] + followers:
		var t := create_tween()
		t.tween_property(n, "rotation_degrees:x", -35.0, 0.07)
		t.tween_property(n, "rotation_degrees:x", 0.0, 0.12)

func hit(from: Vector3) -> void:
	if invuln > 0.0 or not alive:
		return
	chicks -= 1
	invuln = 1.3
	var away := global_position - from
	away.y = 0.0
	knock = away.normalized() * 9.0
	if followers.size() > 0:
		var f: Node3D = followers.pop_back()
		f.queue_free()
	hurt.emit(chicks)
	if chicks <= 0:
		alive = false
		leader.visible = false
		died.emit()
