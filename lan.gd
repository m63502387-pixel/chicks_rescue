extends Control
# Мультиплеер по LAN: создать игру / найти игру в сети / выбрать режим.
# Играть можно во всех режимах: Сюжет, Обычная игра, Битва за маму птицу.

const Net = preload("res://net.gd")
const StoryScript = preload("res://story.gd")
const DrunScript = preload("res://drun.gd")
const Save = preload("res://save.gd")
const MODES := [
	{"title": "Сюжет", "scene": "res://story.tscn"},
	{"title": "Обычная игра", "scene": "res://main.tscn"},
	{"title": "Битва за маму птицу", "scene": "res://battle.tscn"},
	{"title": "Сюжет: Друн", "scene": "res://drun.tscn"},
]

var box: VBoxContainer
var lbl_status: Label
var lbl_ips: Label
var ip_edit: LineEdit
var host_row: VBoxContainer
var join_row: VBoxContainer
var found_box: VBoxContainer
var mode_box: VBoxContainer
var lbl_wait: Label
var is_host := false
var in_lobby := false
var bcast := PacketPeerUDP.new()
var listen := PacketPeerUDP.new()
var bcast_t := 0.0
var found := {}

func _ready() -> void:
	Input.emulate_mouse_from_touch = true
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.16)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "МУЛЬТИПЛЕЕР ПО LAN"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	lbl_status = Label.new()
	lbl_status.text = "Все устройства должны быть в одной Wi-Fi / LAN сети"
	lbl_status.add_theme_font_size_override("font_size", 20)
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl_status)

	host_row = VBoxContainer.new()
	host_row.add_theme_constant_override("separation", 12)
	box.add_child(host_row)
	_btn(host_row, "Создать игру (хост)", _on_host)
	join_row = VBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	host_row.add_child(join_row)
	var sep := Label.new()
	sep.text = "— или подключись к игре —"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_row.add_child(sep)
	found_box = VBoxContainer.new()
	found_box.add_theme_constant_override("separation", 6)
	join_row.add_child(found_box)
	var hb := HBoxContainer.new()
	join_row.add_child(hb)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP хоста, например 192.168.1.5"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.add_theme_font_size_override("font_size", 24)
	hb.add_child(ip_edit)
	var jb := Button.new()
	jb.text = "Подключиться"
	jb.add_theme_font_size_override("font_size", 24)
	jb.pressed.connect(func(): _join(ip_edit.text.strip_edges()))
	hb.add_child(jb)

	lbl_ips = Label.new()
	lbl_ips.add_theme_font_size_override("font_size", 24)
	lbl_ips.add_theme_color_override("font_color", Color(0.6, 1, 0.7))
	lbl_ips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_ips.visible = false
	box.add_child(lbl_ips)
	lbl_wait = Label.new()
	lbl_wait.add_theme_font_size_override("font_size", 26)
	lbl_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_wait.visible = false
	box.add_child(lbl_wait)
	mode_box = VBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 10)
	mode_box.visible = false
	box.add_child(mode_box)
	for i in MODES.size():
		if i == 3 and not Save.is_drun_unlocked():
			continue
		_btn(mode_box, "Играть: " + MODES[i]["title"], _start_mode.bind(i))
	_btn(box, "Назад в меню", _back)

	multiplayer.peer_connected.connect(_on_peer_change)
	multiplayer.peer_disconnected.connect(_on_peer_change)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_failed)
	# поиск хостов в сети
	if listen.bind(Net.DISCOVERY_PORT, "*") != OK:
		listen = null

func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _on_host() -> void:
	var err := Net.host(get_tree())
	if err != OK:
		lbl_status.text = "Не удалось создать игру (порт %d занят?)" % Net.PORT
		return
	is_host = true
	in_lobby = true
	host_row.visible = false
	lbl_ips.visible = true
	lbl_ips.text = "Твой IP: " + ", ".join(Net.local_ips())
	bcast.set_broadcast_enabled(true)
	bcast.set_dest_address("255.255.255.255", Net.DISCOVERY_PORT)
	_refresh_lobby()

func _join(ip: String) -> void:
	if ip == "":
		lbl_status.text = "Введи IP хоста или выбери найденную игру"
		return
	var err := Net.join(get_tree(), ip)
	if err != OK:
		lbl_status.text = "Не удалось подключиться к " + ip
		return
	lbl_status.text = "Подключаемся к %s..." % ip

func _on_connected() -> void:
	is_host = false
	in_lobby = true
	host_row.visible = false
	_refresh_lobby()

func _on_failed() -> void:
	Net.stop(get_tree())
	in_lobby = false
	is_host = false
	host_row.visible = true
	lbl_ips.visible = false
	lbl_wait.visible = false
	mode_box.visible = false
	lbl_status.text = "Нет связи с хостом. Попробуй ещё раз."

func _on_peer_change(_id: int) -> void:
	_refresh_lobby()

func _refresh_lobby() -> void:
	if not in_lobby:
		return
	var n := multiplayer.get_peers().size() + 1
	if is_host:
		lbl_status.text = "Игра создана. Игроков в лобби: %d" % n
		mode_box.visible = true
		lbl_wait.visible = n < 2
		lbl_wait.text = "Ждём второго игрока... (можно начать и одному)"
	else:
		lbl_status.text = "Подключено к хосту! Игроков в лобби: %d" % n
		mode_box.visible = false
		lbl_wait.visible = true
		lbl_wait.text = "Ждём, пока хост выберет режим..."

func _start_mode(i: int) -> void:
	if not is_host:
		return
	_go.rpc(i)
	_go(i)

@rpc("authority", "call_remote", "reliable")
func _go(i: int) -> void:
	if i == 0:
		StoryScript.checkpoint = 0
	elif i == 3:
		DrunScript.dcheckpoint = 10
	Input.emulate_mouse_from_touch = false
	get_tree().change_scene_to_file(MODES[i]["scene"])

func _back() -> void:
	Net.stop(get_tree())
	Input.emulate_mouse_from_touch = false
	get_tree().change_scene_to_file("res://menu.tscn")

func _process(delta: float) -> void:
	if is_host and in_lobby:
		bcast_t -= delta
		if bcast_t <= 0.0:
			bcast_t = 1.0
			bcast.put_packet(("CHICKS|%d" % Net.PORT).to_utf8_buffer())
	if listen != null and not is_host and not in_lobby:
		var changed := false
		while listen.get_available_packet_count() > 0:
			var msg := listen.get_packet().get_string_from_utf8()
			var ip := listen.get_packet_ip()
			if msg.begins_with("CHICKS|") and not found.has(ip):
				found[ip] = true
				changed = true
		if changed:
			for c in found_box.get_children():
				c.queue_free()
			for ip in found:
				_btn(found_box, "Найдена игра: " + ip, _join.bind(ip))
