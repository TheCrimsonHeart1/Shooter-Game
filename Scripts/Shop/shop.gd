extends Node3D

@export var shop_ui: CanvasLayer
@export var interact_action := "interact"
var player : CharacterBody3D
var player_inside := false

func _ready():
	shop_ui.visible = false
	$Area3D.body_entered.connect(_on_body_entered)
	$Area3D.body_exited.connect(_on_body_exited)
	$StaticBody3D/SHOP/AnimationPlayer.play("idle")
func _input(event):
	if player_inside and event.is_action_pressed(interact_action):
		toggle_shop()

func toggle_shop():
	if player == null: return
	var new_state = !shop_ui.visible
	shop_ui.visible = new_state
	
	# RPC call ensures all peers (and the local player) update the variable
	player.sync_shop_state.rpc(new_state)
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if new_state else Input.MOUSE_MODE_CAPTURED
func close_shop():
	if player:
		player.sync_shop_state.rpc(false) # Sync the close
	shop_ui.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _on_body_exited(body):
	# Check if the player exiting is the one we are tracking
	if player and body == player:
		# ORDER MATTERS: Close first, then clear variables
		close_shop()
		player_inside = false
		player = null
func _on_body_entered(body):
	if body.is_in_group("players") and body.is_multiplayer_authority():
		player = body
		player_inside = true


# --- UI BUTTONS ---

func get_player_by_peer(peer_id: int) -> CharacterBody3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null

func _on_button_buy_ak47_pressed():
	if player and player.current_currency >= 10:
		request_purchase_ak47.rpc_id(1)

# --- SERVER LOGIC ---

@rpc("any_peer", "call_local", "reliable")
func request_ammo_refill():
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id() # host fix

	var buyer := get_player_by_peer(sender_id)
	if buyer == null:
		return

	if buyer.current_currency >= 3:
		buyer.update_currency(-3)
		buyer.request_refill_ammo()

@rpc("any_peer", "call_local", "reliable")
func request_purchase_ak47():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var buyer = get_node("/root/Main Menu/MultiplayerManager/LevelContainer/" + str(sender_id))
	
	if buyer and buyer.current_currency >= 10:
		buyer.update_currency(-10)
		buyer.hasak47 = true
		# Hide button for that specific client
		update_shop_ui_client.rpc_id(sender_id)

@rpc("authority", "call_local", "reliable")
func update_shop_ui_client():
	$ShopUI/Panel/ButtonBuyAK.visible = false


func _on_button_2_pressed() -> void:
	close_shop()


func _on_button_4_pressed() -> void:
	request_ammo_refill.rpc()
