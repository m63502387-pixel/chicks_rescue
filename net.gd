extends RefCounted
# Сеть по LAN (ENet). Соединение живёт между сценами, пока не вернёшься в меню.

const PORT := 24566
const DISCOVERY_PORT := 24567
const SyncScript = preload("res://netsync.gd")

static func online(tree: SceneTree) -> bool:
	var p := tree.get_multiplayer().multiplayer_peer
	if p == null or p is OfflineMultiplayerPeer:
		return false
	return p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

static func stop(tree: SceneTree) -> void:
	var mp := tree.get_multiplayer()
	var p := mp.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	mp.multiplayer_peer = null

static func host(tree: SceneTree) -> int:
	stop(tree)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 3)
	if err == OK:
		tree.get_multiplayer().multiplayer_peer = peer
	return err

static func join(tree: SceneTree, ip: String) -> int:
	stop(tree)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err == OK:
		tree.get_multiplayer().multiplayer_peer = peer
	return err

static func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s: String = a
		if s.count(".") == 3 and not s.begins_with("127.") and not s.begins_with("169.254."):
			out.append(s)
	return out

# Подключает синхронизацию игроков к текущей сцене режима (если играем по сети).
static func attach(scene: Node, player: Node, key: String) -> void:
	if not online(scene.get_tree()):
		return
	var n = SyncScript.new()
	n.name = "NetSync"
	n.player = player
	n.key = key
	scene.add_child(n)
