extends RefCounted
# Общие "строители" для режима битвы.

static func mi(mesh: PrimitiveMesh, col: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mesh.material = m
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.position = pos
	return n

static func box(parent: Node, pos: Vector3, size: Vector3, col: Color) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos
	var bm := BoxMesh.new()
	bm.size = size
	b.add_child(mi(bm, col))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	return b

static func label3d(text: String, pos: Vector3, size: int, col: Color) -> Label3D:
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

static func make_cage() -> StaticBody3D:
	var cage := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.name = "Col"
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.8, 2.4, 2.8)
	cs.shape = sh
	cs.position.y = 1.2
	cage.add_child(cs)
	var base := CylinderMesh.new()
	base.top_radius = 1.5
	base.bottom_radius = 1.5
	base.height = 0.2
	cage.add_child(mi(base, Color(0.3, 0.3, 0.35), Vector3(0, 0.1, 0)))
	var top := CylinderMesh.new()
	top.top_radius = 1.4
	top.bottom_radius = 1.4
	top.height = 0.12
	cage.add_child(mi(top, Color(0.3, 0.3, 0.35), Vector3(0, 2.35, 0)))
	for i in 12:
		var a := TAU * i / 12.0
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 2.3
		cage.add_child(mi(cm, Color(0.75, 0.75, 0.8), Vector3(cos(a) * 1.3, 1.2, sin(a) * 1.3)))
	return cage

static func make_mother() -> Node3D:
	var mother := Node3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.8
	bm.height = 1.6
	mother.add_child(mi(bm, Color(0.8, 0.4, 0.15), Vector3(0, 0.9, 0)))
	var hm := SphereMesh.new()
	hm.radius = 0.45
	hm.height = 0.9
	mother.add_child(mi(hm, Color(0.85, 0.45, 0.18), Vector3(0, 1.65, -0.5)))
	var beak := CylinderMesh.new()
	beak.top_radius = 0.0
	beak.bottom_radius = 0.17
	beak.height = 0.45
	var b := mi(beak, Color(1, 0.55, 0.1), Vector3(0, 1.6, -1.05))
	b.rotation_degrees.x = -90.0
	mother.add_child(b)
	for sx in [-1, 1]:
		var eye := SphereMesh.new()
		eye.radius = 0.07
		eye.height = 0.14
		mother.add_child(mi(eye, Color.BLACK, Vector3(0.22 * sx, 1.8, -0.85)))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.6, 0.12, 0.9)
	var t := mi(tail, Color(0.65, 0.3, 0.1), Vector3(0, 1.1, 0.85))
	t.rotation_degrees.x = 25.0
	mother.add_child(t)
	for sx in [-1, 1]:
		var pivot := Node3D.new()
		pivot.name = "WingL" if sx < 0 else "WingR"
		pivot.position = Vector3(0.7 * sx, 1.3, 0.0)
		var wm := BoxMesh.new()
		wm.size = Vector3(1.3, 0.08, 0.8)
		pivot.add_child(mi(wm, Color(0.7, 0.33, 0.12), Vector3(0.65 * sx, 0, 0)))
		mother.add_child(pivot)
	mother.rotation_degrees.y = 180.0
	return mother
