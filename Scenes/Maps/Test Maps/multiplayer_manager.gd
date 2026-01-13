extends Node3D

var connected_players := []
var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()

@export var game_scene_path: String = "res://Scenes/Maps/Test Maps/test_map1.tscn"
@export var min_players: int = 2
@export var player_scene : PackedScene
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var level_container: Node3D = $LevelContainer
@onready var main_menu_ui: CanvasLayer = $CanvasLayer
@onready var ip_input: LineEdit = $CanvasLayer/Panel/IPAddressInput
func _ready() -> void:
	spawner.spawn_function = _custom_spawn
	spawner.spawn_path = level_container.get_path()
	spawner.add_spawnable_scene(game_scene_path)
	spawner.add_spawnable_scene(player_scene.resource_path)
	spawner.add_spawnable_scene("res://Scenes/Weapons/AK47.tscn")
	spawner.add_spawnable_scene("res://Scenes/Weapons/Revolver.tscn")
func _on_host_pressed() -> void:
	# 1. Attempt to port forward automatically before starting the server
	setup_upnp(1027)
	
	# 2. Start the server as normal
	var error = peer.create_server(1027)
	if error != OK:
		print("Failed to host: ", error)
		return
		
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	connected_players.append(multiplayer.get_unique_id())
	print("Server started. Host ID:", multiplayer.get_unique_id())
	update_player_count_ui()
	check_start_game()
func _on_join_pressed() -> void:
	# Retrieve the text from the LineEdit
	var target_ip = ip_input.text
	
	# Fallback if the LineEdit is empty
	if target_ip == "":
		target_ip = "127.0.0.1"
	
	# Create the client using the entered IP
	var error = peer.create_client(target_ip, 1027)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("Client connecting to: ", target_ip)
	else:
		print("Failed to create client: ", error)
# --- Player Management ---
func _on_peer_connected(id: int) -> void:
	if not id in connected_players:
		connected_players.append(id)

	if multiplayer.is_server():
		update_player_count_ui()
		check_start_game()

func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	update_player_count_ui()


# --- Scene Loading Logic ---
func check_start_game():
	# Server authority check
	if multiplayer.is_server() and connected_players.size() >= min_players:
		# Check if level is already loaded to prevent double-spawning
		if level_container.get_child_count() == 0:
			load_game_scene()

func load_game_scene():
	if not multiplayer.is_server(): return
	
	hide_menu_and_capture_mouse.rpc()
	
	var map = load(game_scene_path).instantiate()
	level_container.add_child(map, true)
	
	# Use a loop index to create different offsets
	for i in range(connected_players.size()):
		var id = connected_players[i]
		# Pass the index 'i' to determine the position
		spawn_player(id, i)

func spawn_player(id: int, index: int = 0):
	if not multiplayer.is_server(): return
	
	# Get your spawn point
	var spawn_points = get_tree().get_nodes_in_group("spawn_points")
	var spawn_pos = Vector3(index * 5, 2, 0) # Default offset
	if spawn_points.size() > index:
		spawn_pos = spawn_points[index].global_position
		
	# Use the .spawn() method to trigger the custom function on all peers
	# We pass a dictionary containing the ID and the specific position
	var spawn_data = {"id": id, "pos": spawn_pos}
	spawner.spawn(spawn_data)
	

@rpc("call_local", "reliable")
func hide_menu_and_capture_mouse():
	main_menu_ui.hide()
	
	# Disable the menu camera specifically
	# Assuming your menu cam is a child of the root Node3D
	var menu_cam = $"../Camera3D"
	if menu_cam:
		menu_cam.current = false
		menu_cam.queue_free() # Get rid of it entirely so it can't interfere
		
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
func _custom_spawn(data: Variant) -> Node:
	var id = data.id
	# Add an offset to the Y axis (e.g., 1.5 units up)
	var pos = data.pos + Vector3(0, 1.5, 0) 
	
	var p = player_scene.instantiate()
	p.name = str(id)
	
	# Set the position before returning
	p.global_position = pos
	
	# Ensure authority is set so the player can move themselves immediately
	p.set_multiplayer_authority(id)
	
	return p
func setup_upnp(port: int):
	var upnp = UPNP.new()
	
	# Discover the router (IGD - Internet Gateway Device)
	var discover_result = upnp.discover()
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPNP Discover Failed! Error: ", discover_result)
		return

	# Check if a valid gateway (router) was found
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		# Open both UDP and TCP for the chosen port
		# "UDP" is usually what Godot's ENet uses
		var map_result = upnp.add_port_mapping(port, port, "Godot Game", "UDP")
		
		if map_result != UPNP.UPNP_RESULT_SUCCESS:
			print("UPNP Port Mapping Failed! Error: ", map_result)
		else:
			print("Port Forwarding Successful! Your Public IP is: ", upnp.query_external_address())
func update_player_count_ui():
	$CanvasLayer/Panel/Label2.text = str(connected_players.size()) + "/" + str(min_players)
