extends "res://player.gd"
# Друн — дрон-разведчик. Летает быстрее птенцов, вместо клюва бьёт электро-разрядом вокруг себя.
# "Здоровье" (chicks) — это заряд батареи.

signal zapped(pos: Vector3)

var rotors: Array = []
var hover_t := 0.0

func _ready() -> void:
	super._ready()
	speed_mult = 1.7
	for f in followers:
		f.queue_free()
	followers.clear()
	for c in leader.get_children():
		c.queue_free()
	var dark := Color(0.16, 0.18, 0.24)
	var body := BoxMesh.new()
	body.size = Vector3(0.9, 0.3, 1.1)
	leader.add_child(_mi(body, dark, Vector3(0, 1.5, 0)))
	var arm1 := BoxMesh.new()
	arm1.size = Vector3(1.9, 0.08, 0.14)
	var a1 := _mi(arm1, Color(0.3, 0.32, 0.4), Vector3(0, 1.55, 0))
	a1.rotation_degrees.y = 45.0
	leader.add_child(a1)
	var arm2 := BoxMesh.new()
	arm2.size = Vector3(1.9, 0.08, 0.14)
	var a2 := _mi(arm2, Color(0.3, 0.32, 0.4), Vector3(0, 1.55, 0))
	a2.rotation_degrees.y = -45.0
	leader.add_child(a2)
	for sx in [-0.67, 0.67]:
		for sz in [-0.67, 0.67]:
			var disc := CylinderMesh.new()
			disc.top_radius = 0.42
			disc.bottom_radius = 0.42
			disc.height = 0.03
			var r := _mi(disc, Color(0.7, 0.9, 1.0, 0.7), Vector3(sx, 1.68, sz))
			var m: StandardMaterial3D = disc.material
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			leader.add_child(r)
			rotors.append(r)
	var eye := SphereMesh.new()
	eye.radius = 0.16
	eye.height = 0.32
	var e := _mi(eye, Color(1, 0.2, 0.2), Vector3(0, 1.45, -0.5))
	var em: StandardMaterial3D = eye.material
	em.emission_enabled = true
	em.emission = Color(1, 0.1, 0.1)
	leader.add_child(e)
	var sh := CylinderMesh.new()
	sh.top_radius = 0.7
	sh.bottom_radius = 0.7
	sh.height = 0.02
	var shadow := _mi(sh, Color(0, 0, 0, 0.35), Vector3(0, 0.03, 0))
	var sm: StandardMaterial3D = sh.material
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(shadow)

func _process(delta: float) -> void:
	hover_t += delta
	for r in rotors:
		r.rotation.y += 40.0 * delta
	leader.position.y = sin(hover_t * 3.0) * 0.08

func _peck() -> void:
	peck_cd = 0.7
	zapped.emit(global_position)
	for g in get_tree().get_nodes_in_group("guards"):
		var to: Vector3 = g.global_position - global_position
		to.y = 0.0
		if to.length() < 3.0:
			g.take_hit(global_position, 2.0)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.05
	var ring := _mi(disc, Color(0.4, 0.9, 1.0, 0.6), Vector3.ZERO)
	var rm: StandardMaterial3D = disc.material
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.4, 0)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(3.0, 1.0, 3.0), 0.3)
	t.tween_property(rm, "albedo_color:a", 0.0, 0.3)
	t.chain().tween_callback(ring.queue_free)
