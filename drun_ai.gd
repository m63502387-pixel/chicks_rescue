extends Node3D
# Друн как герой сцены (его ведёт игра, а не игрок): летит за фургоном, помогает с охраной.

var rotors: Array = []
var t := 0.0
var mode := "idle"
var target_node: Node3D
var follow_off := Vector3(-7, 5.5, 3.5)

static func _mi(mesh: PrimitiveMesh, col: Color, pos: Vector3) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mesh.material = m
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.position = pos
	return n

func _ready() -> void:
	var body := BoxMesh.new()
	body.size = Vector3(0.9, 0.3, 1.1)
	add_child(_mi(body, Color(0.16, 0.18, 0.24), Vector3.ZERO))
	for ang in [45.0, -45.0]:
		var arm := BoxMesh.new()
		arm.size = Vector3(1.9, 0.08, 0.14)
		var a := _mi(arm, Color(0.3, 0.32, 0.4), Vector3(0, 0.05, 0))
		a.rotation_degrees.y = ang
		add_child(a)
	for sx in [-0.67, 0.67]:
		for sz in [-0.67, 0.67]:
			var disc := CylinderMesh.new()
			disc.top_radius = 0.42
			disc.bottom_radius = 0.42
			disc.height = 0.03
			var r := _mi(disc, Color(0.7, 0.9, 1.0, 0.7), Vector3(sx, 0.18, sz))
			var m: StandardMaterial3D = disc.material
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			add_child(r)
			rotors.append(r)
	var eye := SphereMesh.new()
	eye.radius = 0.16
	eye.height = 0.32
	var e := _mi(eye, Color(1, 0.2, 0.2), Vector3(0, -0.05, -0.5))
	var em: StandardMaterial3D = eye.material
	em.emission_enabled = true
	em.emission = Color(1, 0.1, 0.1)
	add_child(e)
	var l := Label3D.new()
	l.text = "ДРУН"
	l.font_size = 60
	l.pixel_size = 0.01
	l.outline_size = 12
	l.modulate = Color(0.5, 0.9, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 1.0, 0)
	add_child(l)

func _process(delta: float) -> void:
	t += delta
	for r in rotors:
		r.rotation.y += 40.0 * delta
	if mode == "follow" and is_instance_valid(target_node):
		var goal := target_node.global_position + follow_off + Vector3(0, sin(t * 2.0) * 0.4, 0)
		global_position = global_position.lerp(goal, minf(1.0, 3.0 * delta))
		var d := target_node.global_position - global_position
		rotation.y = atan2(-d.x, -d.z)
