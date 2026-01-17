extends Node3D

var connected_players := []
var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var current_class = 0
@export var game_scene_path: String = "res://Scenes/Maps/Test Maps/test_map1.tscn"
@export var min_players: int = 2
@export var player_scene : PackedScene
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var level_container: Node3D = $LevelContainer
@onready var main_menu_ui: CanvasLayer = $CanvasLayer
@onready var ip_input: LineEdit = $CanvasLayer/Panel/IPAddressInput
@export var bushwacker_scene : PackedScene
@export var soldier_scene : PackedScene
var player_classes := {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -10)
	spawner.spawn_function = _custom_spawn
	spawner.spawn_path = level_container.get_path()
	spawner.add_spawnable_scene(game_scene_path)
	spawner.add_spawnable_scene(player_scene.resource_path)
	spawner.add_spawnable_scene("res://Scenes/Weapons/AK47.tscn")
	spawner.add_spawnable_scene("res://Scenes/Weapons/Revolver.tscn")
	player_classes.clear()
	connected_players.clear()

func _on_host_pressed():
	start_network_as_server(32)
	register_host_class()

func _on_join_pressed():
	var target_ip = ip_input.text
	if target_ip == "":
		target_ip = "127.0.0.1"
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, 1027)
	if error != OK:
		print("Failed to create client")
		return
	multiplayer.multiplayer_peer = peer
	print("Client connecting...")
	await multiplayer.connected_to_server
	await get_tree().process_frame
	send_class_to_server.rpc(current_class)

func _on_peer_connected(id: int) -> void:
	if not id in connected_players:
		connected_players.append(id)
	if multiplayer.is_server():
		update_player_count_ui()
		if all_connected_players_have_class():
			check_start_game()

func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	update_player_count_ui()

func check_start_game():
	if multiplayer.is_server() and connected_players.size() >= min_players:
		if level_container.get_child_count() == 0:
			load_game_scene()

func load_game_scene():
	if not multiplayer.is_server(): return
	hide_menu_and_capture_mouse.rpc()
	if level_container.get_child_count() > 0:
		return
	var map = load(game_scene_path).instantiate()
	level_container.add_child(map, true)
	for i in range(connected_players.size()):
		spawn_player(connected_players[i], i)

func spawn_player(id: int, index: int):
	var spawn_pos = Vector3(index * 5, 2, 0)
	var spawn_points = get_tree().get_nodes_in_group("spawn_points")
	if spawn_points.size() > index:
		spawn_pos = spawn_points[index].global_position
	var selected_class = player_classes.get(id, 0)
	spawner.spawn({
		"id": id,
		"pos": spawn_pos,
		"class": selected_class
	})

@rpc("call_local", "reliable")
func hide_menu_and_capture_mouse():
	main_menu_ui.hide()
	var menu_cam = $"../Camera3D"
	if menu_cam:
		menu_cam.current = false
		menu_cam.queue_free()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _custom_spawn(data: Variant) -> Node:
	var id = data.id
	var pos = data.pos + Vector3(0, 1.5, 0)
	var p_class = data.get("class", 0)
	var p
	if p_class == 1:
		p = bushwacker_scene.instantiate()
	else:
		p = soldier_scene.instantiate()
	p.name = str(id)
	p.global_position = pos
	p.set_multiplayer_authority(id)
	return p

func setup_upnp(port: int):
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPNP Discover Failed! Error: ", discover_result)
		return
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		var map_result = upnp.add_port_mapping(port, port, "Godot Game", "UDP")
		if map_result != UPNP.UPNP_RESULT_SUCCESS:
			print("UPNP Port Mapping Failed! Error: ", map_result)
		else:
			print("Port Forwarding Successful! Your Public IP is: ", upnp.query_external_address())

func update_player_count_ui():
	$CanvasLayer/Panel/Label2.text = str(connected_players.size()) + "/" + str(min_players)

func _on_singleplayer_pressed() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	start_network_as_server(1)
	register_host_class() # Ensure host class is registered
	load_game_scene()

func start_network_as_server(max_players: int):
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(1027, max_players)
	if error != OK:
		print("Failed to host: ", error)
		return
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	connected_players.clear()
	connected_players.append(multiplayer.get_unique_id())
	print("Network started as Server. Mode: ", "Singleplayer" if max_players == 1 else "Multiplayer")
	update_player_count_ui()

func _on_multiplayer_pressed() -> void:
	$CanvasLayer/Panel/IPAddressInput.visible = true
	$CanvasLayer/Panel/Label.visible = true
	$CanvasLayer/Panel/Label2.visible = true
	$CanvasLayer/Panel/Host.visible = true
	$CanvasLayer/Panel/Join.visible = true
	$CanvasLayer/Panel/Singleplayer.visible = false
	$CanvasLayer/Panel/Multiplayer.visible = false
	$CanvasLayer/Panel/Back.visible = true
	$CanvasLayer/Panel/ChooseClass.visible = false

@rpc("any_peer", "call_local", "reliable")
func set_player_class(class_index: int):
	current_class = class_index
	if multiplayer.is_server():
		var id = multiplayer.get_remote_sender_id()
		if id == 0: id = multiplayer.get_unique_id()
		player_classes[id] = class_index
		print("Server: Registered Class ", class_index, " for Player ", id)

func _on_soldier_pressed():
	current_class = 0
	print("Selected Soldier (local)")

func _on_bushwacker_pressed():
	current_class = 1
	print("Selected Bushwacker (local)")

func _on_choose_class_pressed() -> void:
	$CanvasLayer/Panel/IPAddressInput.visible = false
	$CanvasLayer/Panel/Label.visible = false
	$CanvasLayer/Panel/Label2.visible = false
	$CanvasLayer/Panel/Host.visible = false
	$CanvasLayer/Panel/Join.visible = false
	$CanvasLayer/Panel/Singleplayer.visible = false
	$CanvasLayer/Panel/Multiplayer.visible = false
	$CanvasLayer/Panel/Bushwacker.visible = true
	$CanvasLayer/Panel/Soldier.visible = true
	$CanvasLayer/Panel/Back.visible = true
	$CanvasLayer/Panel/ChooseClass.visible = false

func _on_back_pressed() -> void:
	$CanvasLayer/Panel/Singleplayer.visible = true
	$CanvasLayer/Panel/Multiplayer.visible = true
	$CanvasLayer/Panel/ChooseClass.visible = true
	$CanvasLayer/Panel/Soldier.visible = false
	$CanvasLayer/Panel/Bushwacker.visible = false
	$CanvasLayer/Panel/Back.visible = false
	$CanvasLayer/Panel/Join.visible = false
	$CanvasLayer/Panel/IPAddressInput.visible = false
	$CanvasLayer/Panel/Label.visible = false
	$CanvasLayer/Panel/Label2.visible = false
	$CanvasLayer/Panel/Host.visible = false

@rpc("any_peer", "reliable")
func send_class_to_server(class_index: int):
	if not multiplayer.is_server():
		return
	var id = multiplayer.get_remote_sender_id()
	player_classes[id] = class_index
	print("Server: Player", id, "class =", class_index)
	if all_connected_players_have_class() and connected_players.size() >= min_players:
		check_start_game()

func register_host_class():
	var host_id = multiplayer.get_unique_id()
	player_classes[host_id] = current_class
	print("Server: Host registered class =", current_class)
	if all_connected_players_have_class() and connected_players.size() >= min_players:
		check_start_game()

func all_connected_players_have_class() -> bool:
	for id in connected_players:
		if not player_classes.has(id):
			return false
	return true
