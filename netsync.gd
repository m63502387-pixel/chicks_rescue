extends Node
# Синхронизация второго игрока (призрак-птенец) и нокаутов охраны между участниками LAN.
# Охрана у каждого игрока считается у себя, но нокауты стартовой охраны передаются всем.

const PlayerScript = preload("res://player.gd")
const COLORS := [Color(0.4, 0.8, 1), Color(1, 0.45, 0.7), Color(0.5, 1, 0.5), Color(0.75, 0.5, 1)]

var player
var key := ""
var ghosts := {}
var guards: Array = []
var send_t := 0.0
var applying := false
var ready_peers := {}
var hello_t := 0.0

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_left)
	multiplayer.server_disconnected.connect(_on_server_gone)
	for c in get_parent().get_children():
		if c != player and c is CharacterBody3D and c.has_method("take_hit"):
			guards.append(c)
			c.knocked_out.connect(_on_ko.bind(guards.size() - 1))

func _on_ko(silent: bool, _boss: bool, idx: int) -> void:
	if applying or not Net_online():
		return
	for id in ready_peers:
		_guard_down.rpc_id(id, key, idx, silent)

func Net_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

@rpc("any_peer", "call_remote", "reliable")
func _guard_down(k: String, idx: int, silent: bool) -> void:
	if k != key or idx < 0 or idx >= guards.size():
		return
	var g = guards[idx]
	if is_instance_valid(g) and not g.is_down():
		applying = true
		g._down(silent)
		applying = false

@rpc("any_peer", "call_remote", "reliable")
func _hello() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not ready_peers.has(id):
		ready_peers[id] = true
		_hello.rpc_id(id)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pos(k: String, p: Vector3, ry: float, sneak: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	var gh: Node3D = ghosts.get(id)
	if gh == null:
		gh = _make_ghost(id)
		ghosts[id] = gh
		gh.position = p
	gh.visible = (k == key)
	gh.set_meta("tp", p)
	gh.set_meta("try", ry)
	gh.scale.y = 0.7 if sneak else 1.0

func _make_ghost(id: int) -> Node3D:
	var g := Node3D.new()
	var ci := (id + ghosts.size()) % COLORS.size()
	g.add_child(PlayerScript.make_chick(COLORS[ci]))
	var l := Label3D.new()
	l.text = "Игрок %d" % ghosts.size()
	l.font_size = 60
	l.pixel_size = 0.01
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 1.7, 0)
	g.add_child(l)
	get_parent().add_child(g)
	return g

func _on_left(id: int) -> void:
	var gh = ghosts.get(id)
	if gh != null and is_instance_valid(gh):
		gh.queue_free()
	ghosts.erase(id)
	ready_peers.erase(id)

func _on_server_gone() -> void:
	for id in ghosts.keys():
		_on_left(id)

func _process(delta: float) -> void:
	if not Net_online():
		return
	send_t += delta
	hello_t -= delta
	var peers := multiplayer.get_peers()
	if hello_t <= 0.0:
		hello_t = 0.7
		for id in peers:
			if not ready_peers.has(id):
				_hello.rpc_id(id)
	if send_t >= 0.06 and is_instance_valid(player):
		send_t = 0.0
		for id in ready_peers:
			if peers.has(id):
				_pos.rpc_id(id, key, player.global_position, player.rotation.y, player.sneaking)
	for id in ghosts:
		var g: Node3D = ghosts[id]
		if is_instance_valid(g) and g.has_meta("tp"):
			g.position = g.position.lerp(g.get_meta("tp"), minf(1.0, 12.0 * delta))
			g.rotation.y = lerp_angle(g.rotation.y, g.get_meta("try"), minf(1.0, 12.0 * delta))
