extends CharacterBody3D

# --- Player Config ---

@export var movementSpeed: float = 4
@export var defaultAccelerationRate: float = 7
@export var mouseSensitivity: float = 0.15
@export var gravityRate: float = 8
@export var jumpForce: float = 3
@export var accelerationRateInAir: float = 3
@export var headbobFrequency: float = 3.0
@export var headbobAmplitude: float = 0.04
@export var sprintMultiplier: float = 1.6
@export var sprintAcceleration: float = 10.0
@export var maxStamina: float = 100.0
@export var staminaDrainRate: float = 25.0
@export var staminaRegenRate: float = 15.0
@export var ak47: PackedScene
@export var revolver: PackedScene
@export var recoilSpeedUp: float = 10.0
@export var recoilRecoverySpeed: float = 5.0
@onready var currencylabel: Label = $PlayerUI/CurrencyLabel
@export var staminaRegenDelay: float = 0.4
@export var controller_look_sensitivity := 120.0
@export var controller_deadzone := 0.15

var current_weapon: int = 0
var hasak47 = false
var health = 100

var gunAmmo := {
	0: {"magazine": 30, "ammo": 120},
	1: {"magazine": 6,  "ammo": 36}
}

# --- Nodes ---
@onready var playerCamera: Camera3D = $PlayerHead/PlayerCamera
@onready var staminaBar: TextureProgressBar = $PlayerUI/StaminaBar
@onready var ammoLabel: Label = $PlayerUI/AmmoLabel
@onready var healthBar: TextureProgressBar = $PlayerUI/HealthBar

# --- State ---
var accelerationRate: float = 0
var headbobTime: float = 0.0
var stamina: float
var staminaRegenTimer: float = 0.0
var displayed_stamina: float
var stamina_velocity: float = 0.0
var camera_default_position: Vector3
var mouse_locked: bool = true
var basePitch: float = 0.0
var isinshop = false
var has_switched_weapon: bool = false # Tracks if the one-time switch was used

var cameraRecoil := Vector2.ZERO
var cameraRecoilTarget: float = 0.0

var current_weapon_instance: Node3D = null

# --- MULTIPLAYER SETUP ---
func _enter_tree():


	# The node knows its parent's name (the ID) automatically
	var id = get_parent().name.to_int()
	if id > 0:
		set_multiplayer_authority(id)
	# If the name is a random string (@... or Node3D), wait for the Spawner


	set_multiplayer_authority(id)
	if has_node("MultiplayerSynchronizer"):
		$MultiplayerSynchronizer.set_multiplayer_authority(id)
func _ready() -> void:
	add_to_group("players")
	stamina = maxStamina
	displayed_stamina = maxStamina
	camera_default_position = playerCamera.transform.origin
	
	# UI and Camera setup only for the owner
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		playerCamera.make_current()
		$PlayerUI.visible = true
	else:
		$PlayerUI.visible = false
		# Optimization: Disable camera and audio for other players
		playerCamera.current = false

	
# --- INPUT ---
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or isinshop or $PauseMenu.visible:
		return

	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensitivity))
		basePitch -= event.relative.y * mouseSensitivity
		basePitch = clamp(basePitch, -89, 89)

# --- PHYSICS ---
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if isinshop or $PauseMenu.visible:
		$PlayerUI.visible = false
		return

	$PlayerUI.visible = true
	handleMovement(delta)
	applyGravity(delta)
	handleJump()
	_cleanup_duplicate_weapons()

	# Weapon switching
	if Input.is_action_just_pressed("switch") and not has_switched_weapon:
		if current_weapon == 1 and hasak47:
			switch_gun(0)
			has_switched_weapon = true # Lock the ability forever
		elif current_weapon == 0:
			switch_gun(1)
			has_switched_weapon = true # Lock the ability forever

	if is_on_floor() and velocity.length() > 0:
		headbobTime += delta * velocity.length()
		playerCamera.transform.origin = camera_default_position + headbob(headbobTime)
	else:
		playerCamera.transform.origin = camera_default_position

# --- MOVEMENT ---
func handleMovement(delta: float) -> void:
	var inputDirection = Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("back") - Input.get_action_strength("forward")
	)
	var direction = (transform.basis * Vector3(inputDirection.x, 0, inputDirection.y)).normalized()
	var currentSpeed = movementSpeed
	var isSprinting = false

	if Input.is_action_pressed("sprint") and direction != Vector3.ZERO and is_on_floor() and stamina > 0:
		isSprinting = true
		currentSpeed *= sprintMultiplier
		accelerationRate = sprintAcceleration
	else:
		accelerationRate = defaultAccelerationRate

	var targetVelocity = direction * currentSpeed
	velocity.x = lerp(velocity.x, targetVelocity.x, accelerationRate * delta)
	velocity.z = lerp(velocity.z, targetVelocity.z, accelerationRate * delta)
	move_and_slide()

	if isSprinting:
		stamina -= staminaDrainRate * delta
		stamina = max(stamina, 0)
		staminaRegenTimer = staminaRegenDelay
	else:
		if staminaRegenTimer > 0:
			staminaRegenTimer -= delta
		else:
			stamina += staminaRegenRate * delta
			stamina = min(stamina, maxStamina)

# --- PROCESS ---
func _process(delta: float) -> void:
	if health <= 0:
		get_tree().change_scene_to_file("res://UI/Main Menu/main_menu.tscn")
	if Input.is_action_just_pressed("pause") and not isinshop:
		var pause_menu = $PauseMenu
		pause_menu.visible = not pause_menu.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_menu.visible else Input.MOUSE_MODE_CAPTURED

	handle_controller_look(delta)

	# Camera recoil
	cameraRecoil.x = lerp(cameraRecoil.x, cameraRecoilTarget, recoilSpeedUp * delta)
	cameraRecoilTarget = lerp(cameraRecoilTarget, 0.0, recoilRecoverySpeed * delta)
	playerCamera.rotation.x = deg_to_rad(basePitch - cameraRecoil.x)

	# Stamina smoothing
	var stiffness = 35.0
	var damping = 14.0
	var force = (stamina - displayed_stamina) * stiffness
	stamina_velocity += force * delta
	stamina_velocity *= exp(-damping * delta)
	displayed_stamina += stamina_velocity * delta
	staminaBar.value = displayed_stamina

	# Toggle mouse
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_mouse_lock()

# --- GRAVITY & JUMP ---
func applyGravity(delta: float) -> void:
	if not is_on_floor():
		accelerationRate = accelerationRateInAir
		velocity.y -= gravityRate * delta
	else:
		velocity.y = 0
		accelerationRate = defaultAccelerationRate

func handleJump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jumpForce

# --- HEADBOB ---
func headbob(time: float) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * headbobFrequency) * headbobAmplitude
	pos.x = sin(time * headbobFrequency / 2) * headbobAmplitude
	return pos

# --- MOUSE ---
func toggle_mouse_lock() -> void:
	mouse_locked = not mouse_locked
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_locked else Input.MOUSE_MODE_VISIBLE

func get_camera_base_position() -> Vector3:
	if not Input.is_action_pressed("aim"):
		return playerCamera.global_position - headbob(headbobTime)
	return playerCamera.global_position

# --- WEAPON SYSTEM ---


func switch_gun(index: int):
	if not is_multiplayer_authority(): return
	if current_weapon == index: return

	# Save ammo locally
	if current_weapon_instance:
		gunAmmo[current_weapon] = {
			"magazine": current_weapon_instance.currentMagazine, 
			"ammo": current_weapon_instance.currentAmmo
		}

	if multiplayer.is_server():
		# If host, just run the logic directly to avoid RPC loop
		execute_weapon_switch(index, 1)
	else:
		# If client, send to server
		request_server_weapon_switch.rpc_id(1, index)

@rpc("any_peer", "call_remote", "reliable") # Changed to call_remote
func request_server_weapon_switch(index: int):
	var sender_id = multiplayer.get_remote_sender_id()
	execute_weapon_switch(index, sender_id)

# Helper function to prevent code duplication and infinite loops
func execute_weapon_switch(index: int, sender_id: int):
	if not multiplayer.is_server(): return
	
	# 1. Cleanup old weapon
	if current_weapon_instance:
		current_weapon_instance.queue_free()
	
	# 2. Instantiate on Server
	var weapon_to_spawn = ak47 if index == 0 else revolver
	var weapon_instance = weapon_to_spawn.instantiate()
	
	# 3. Fixed Name (Matches across network)
	weapon_instance.name = "Weapon_Instance"
	
	# 4. Authority
	weapon_instance.set_multiplayer_authority(sender_id)
	
	# 5. Add to tree
	add_child(weapon_instance, true) # 'true' is vital for name syncing
	current_weapon_instance = weapon_instance
	current_weapon = index
	if gunAmmo.has(index):
		weapon_instance.currentMagazine = gunAmmo[index]["magazine"]
		weapon_instance.currentAmmo = gunAmmo[index]["ammo"]
		weapon_instance.call_deferred("update_ammo_ui")


	# 6. Sync to ALL clients
	_sync_weapon_add.rpc(index, sender_id)

@rpc("any_peer", "call_local", "reliable")
func _sync_weapon_add(index: int, auth_id: int):
	# PREVENTION: If this is the server, the gun already exists from execute_weapon_switch
	# We only need to run the setup, NOT spawn another one.
	if multiplayer.is_server():
		_setup_gun_locally(current_weapon_instance)
		return

	# If this is a client, spawn the visual gun
	var weapon_to_spawn = ak47 if index == 0 else revolver
	var weapon_instance = weapon_to_spawn.instantiate()
	weapon_instance.name = "Weapon_Instance"
	weapon_instance.set_multiplayer_authority(auth_id)
	
	add_child(weapon_instance, true)
	_setup_gun_locally(weapon_instance)
	if gunAmmo.has(index):
		weapon_instance.currentMagazine = gunAmmo[index]["magazine"]
		weapon_instance.currentAmmo = gunAmmo[index]["ammo"]
		weapon_instance.call_deferred("update_ammo_ui")


# --- CAMERA RECOIL ---
func apply_camera_recoil(pitch_amount: float, yaw_amount: float) -> void:
	cameraRecoilTarget += pitch_amount

var current_currency: int = 0:
	set(value):
		current_currency = value
		# This code now runs on *every* client's instance of the player node.
		# This updates the UI globally, so everyone sees everyone else's currency change.
		if currencylabel:
			currencylabel.text = str(value)

func update_currency(amount: int) -> void:
	# This function should only be called on the AUTHORITY (the killer's local game 
	# or the server's instance if the server initiated the kill logic)

	# Use 'is_multiplayer_authority()' for flow control here, 
	# not just 'is_server()'
	if is_multiplayer_authority():
		# The setter runs automatically here.
		current_currency += amount 
		print("Authority updated currency to: ", current_currency)
	else:
		# If a client calls this on their own node, they request the server 
		# (Peer 1) to execute the function on the server's copy of their node.
		# This function should be an RPC marked as 'authority'
		_request_currency_change.rpc(amount)


# Use the 'authority' mode here. The server is the authority by default, 
# but we set authority to the client who owns the player node earlier.
@rpc("any_peer", "call_local", "reliable")
func _request_currency_change(amount: int) -> void:
	# On the client instance, this will only run if it's the owner's machine
	# On the server instance, this will run and update the synchronized variable
	current_currency += amount

func take_damage(amount: int) -> void:
	# 1. Only the server should calculate the new health
	if not multiplayer.is_server():
		return

	health -= amount
	print("Server: Player ", name, " health is now ", health)

	# 2. Tell the specific client who owns this node to update their local UI
	# We use rpc_id to target the owner (multiplayer_authority)
	_sync_health_to_client.rpc_id(get_multiplayer_authority(), health)

@rpc("any_peer", "call_local", "reliable")
func _sync_health_to_client(new_health: int):
	# This runs on the client's machine to update their screen
	health = new_health
	if healthBar:
		healthBar.value = health
	
	# Death check on the client (local)
	if health <= 0:
		get_tree().change_scene_to_file("res://UI/Main Menu/main_menu.tscn")

# --- CONTROLLER LOOK ---
func handle_controller_look(delta: float) -> void:
	var look_x = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var look_y = Input.get_action_strength("look_up") - Input.get_action_strength("look_down")
	var look_vec = Vector2(look_x, look_y)
	if look_vec.length() < controller_deadzone:
		return
	rotate_y(deg_to_rad(-look_vec.x * controller_look_sensitivity * delta))
	basePitch -= look_vec.y * controller_look_sensitivity * delta
	basePitch = clamp(basePitch, -89, 89)
func _setup_gun_locally(node: Node):
	if not node: return
	
	current_weapon_instance = node
	# Assign references directly
	node.player = self
	node.playerCamera = $PlayerHead/PlayerCamera
	node.ammoLabel = $PlayerUI/AmmoLabel
	
	# Handle visibility
	node.visible = true
	
	if is_multiplayer_authority():
		node.update_ammo_ui()
	else:
		# Hide other players' high-FOV first person models if necessary
		# node.visible = false 
		pass
func _cleanup_duplicate_weapons():
	var weapons: Array[Node] = []

	for child in get_children():
		if child.has_method("shoot") and child.has_method("update_ammo_ui"):
			weapons.append(child)

	if weapons.size() <= 1:
		return

	for i in range(1, weapons.size()):
		weapons[i].queue_free()
func refill_all_ammo() -> void:
	# Update dictionary for all slots
	gunAmmo[0] = {"magazine": 30, "ammo": 120}
	gunAmmo[1] = {"magazine": 6, "ammo": 36}
	
	if current_weapon_instance:
		var slot = current_weapon
		current_weapon_instance.currentMagazine = gunAmmo[slot]["magazine"]
		current_weapon_instance.currentAmmo = gunAmmo[slot]["ammo"]
		
		# Tell the client to update their UI
		_sync_ammo_to_client.rpc_id(get_multiplayer_authority(), gunAmmo[slot]["magazine"], gunAmmo[slot]["ammo"])

@rpc("any_peer", "call_local", "reliable")
func _sync_ammo_to_client(mag: int, ammo: int):
	# This code runs on the Client's machine when the Server tells it to
	if current_weapon_instance:
		current_weapon_instance.currentMagazine = mag
		current_weapon_instance.currentAmmo = ammo
		current_weapon_instance.update_ammo_ui()
