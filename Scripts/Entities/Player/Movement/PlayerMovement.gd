extends CharacterBody3D
var action_locked := false
var melee_hit_bodies := {}

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
@export var staminaRegenDelay: float = 0.4
@export var controller_look_sensitivity := 250.0
@export var controller_deadzone := 0.15
@onready var ak47_instance: Node3D = $WeaponContainer/AK47
@onready var revolver_instance: Node3D = $WeaponContainer/Revolver

const GRENADE_SCENE = preload("res://Scenes/Entities/Players/grenade.tscn")

@onready var currencylabel: Label = $PlayerUI/CurrencyLabel
@onready var playerCamera: Camera3D = $PlayerHead/PlayerCamera
@onready var staminaBar: TextureProgressBar = $PlayerUI/StaminaBar
@onready var ammoLabel: Label = $PlayerUI/AmmoLabel
@onready var healthBar: TextureProgressBar = $PlayerUI/HealthBar
@onready var weapon_container = $WeaponContainer
var current_weapon: int = 0
var hasak47 = false
var health = 100
var isinshop = false
var has_switched_weapon = false

@export var gunAmmo := {
	0: {"magazine": 30, "ammo": 120},
	1: {"magazine": 6, "ammo": 36}
}

var accelerationRate = 0.0
var headbobTime = 0.0
var stamina: float
var staminaRegenTimer = 0.0
var displayed_stamina: float
var stamina_velocity = 0.0
var camera_default_position: Vector3
var mouse_locked = true
var basePitch = 0.0
var heals = 3
var cameraRecoil := Vector2.ZERO
var cameraRecoilTarget := 0.0
var current_weapon_instance: Node3D = null

var current_currency := 0:
	set(value):
		current_currency = value
		if currencylabel:
			currencylabel.text = str(value)

func _enter_tree():
	var id = get_parent().name.to_int()
	if id > 0:
		set_multiplayer_authority(id)
	if has_node("MultiplayerSynchronizer"):
		$MultiplayerSynchronizer.set_multiplayer_authority(id)

func _ready():
	add_to_group("players")

	stamina = maxStamina
	displayed_stamina = maxStamina
	camera_default_position = playerCamera.transform.origin

	_setup_weapon(ak47_instance)
	_setup_weapon(revolver_instance)

	switch_gun(1) # start with revolver



	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		playerCamera.make_current()
		$PlayerUI.visible = true
		playerCamera.cull_mask &= ~(1 << 1) # Disables Layer 2 (index 1)
		$PlayerMesh.visible = false
	else:
		$PlayerUI.visible = false
		playerCamera.current = false
		$PlayerMesh.visible = true
func _input(event):
	if not is_multiplayer_authority() or isinshop or $PauseMenu.visible:
		return
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensitivity))
		basePitch -= event.relative.y * mouseSensitivity
		basePitch = clamp(basePitch, -89, 89)



func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	if isinshop or $PauseMenu.visible:
		$PlayerUI.visible = false
		return

	$PlayerUI.visible = true
	handleMovement(delta)
	applyGravity(delta)
	handleJump()
	handle_heal(delta)
	handle_grenade(delta)
	handle_melee(delta)
	if Input.is_action_just_pressed("switch"):
		switch_gun(1 - current_weapon)
	if is_on_floor() and velocity.length() > 0:
		headbobTime += delta * velocity.length()
		playerCamera.transform.origin = camera_default_position + headbob(headbobTime)
	else:
		playerCamera.transform.origin = camera_default_position

func _process(delta):
	if not is_multiplayer_authority():
		return
	if health <= 0:
		get_tree().change_scene_to_file("res://UI/Main Menu/main_menu.tscn")

	if Input.is_action_just_pressed("pause") and not isinshop:
		var pause_menu = $PauseMenu
		pause_menu.visible = !pause_menu.visible
		
	
		# SMART MOUSE CONTROL:
		if pause_menu.visible or isinshop:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	if isinshop:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	handle_controller_look(delta)

	cameraRecoil.x = lerp(cameraRecoil.x, cameraRecoilTarget, recoilSpeedUp * delta)
	cameraRecoilTarget = lerp(cameraRecoilTarget, 0.0, recoilRecoverySpeed * delta)
	playerCamera.rotation.x = deg_to_rad(basePitch - cameraRecoil.x)

	var stiffness = 35.0
	var damping = 14.0
	var force = (stamina - displayed_stamina) * stiffness
	stamina_velocity += force * delta
	stamina_velocity *= exp(-damping * delta)
	displayed_stamina += stamina_velocity * delta
	staminaBar.value = displayed_stamina

	if Input.is_action_just_pressed("ui_cancel"):
		toggle_mouse_lock()

func handleMovement(delta):
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


@rpc("any_peer", "call_local", "reliable")
func sync_shop_state(state: bool):
	isinshop = state
	
func applyGravity(delta):
	if not is_on_floor():
		accelerationRate = accelerationRateInAir
		velocity.y -= gravityRate * delta
	else:
		velocity.y = 0
		accelerationRate = defaultAccelerationRate

func handleJump():
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jumpForce
		$AudioStreamPlayer3D.play()

func handle_controller_look(delta):
	var look_vec = Vector2(
		Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
		Input.get_action_strength("look_up") - Input.get_action_strength("look_down")
	)
	if look_vec.length() < controller_deadzone:
		return
	rotate_y(deg_to_rad(-look_vec.x * controller_look_sensitivity * delta))
	basePitch -= look_vec.y * controller_look_sensitivity * delta
	basePitch = clamp(basePitch, -89, 89)

func headbob(time):
	var pos = Vector3.ZERO
	pos.y = sin(time * headbobFrequency) * headbobAmplitude
	pos.x = sin(time * headbobFrequency / 2) * headbobAmplitude
	return pos

func toggle_mouse_lock():
	mouse_locked = not mouse_locked
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_locked else Input.MOUSE_MODE_VISIBLE

func switch_gun(index: int):
	if action_locked:
		return
	if not is_multiplayer_authority():
		return
	if current_weapon == index:
		return

	# Save ammo
	var old_weapon = _get_weapon(current_weapon)
	if old_weapon:
		gunAmmo[current_weapon] = {
			"magazine": old_weapon.currentMagazine,
			"ammo": old_weapon.currentAmmo
		}
		old_weapon.visible = false
		old_weapon.set_process(false)

	# Enable new weapon
	var new_weapon = _get_weapon(index)
	current_weapon = index

	new_weapon.visible = true
	new_weapon.set_process(true)
	new_weapon.currentMagazine = gunAmmo[index]["magazine"]
	new_weapon.currentAmmo = gunAmmo[index]["ammo"]
	new_weapon.update_ammo_ui()



func _get_weapon(index: int) -> Node3D:
	return ak47_instance if index == 0 else revolver_instance


# The Spawner calls this on clients automatically when a child is added
func _on_weapon_container_child_entered_tree(node):
	_setup_gun_locally(node)
func _setup_gun_locally(node):
	current_weapon_instance = node
	node.player = self
	node.playerCamera = playerCamera
	node.ammoLabel = ammoLabel
	# Restore ammo from gunAmmo dictionary here if needed
func apply_camera_recoil(pitch_amount, yaw_amount):
	cameraRecoilTarget += pitch_amount

func update_currency(amount):
	if is_multiplayer_authority():
		current_currency += amount
	else:
		_request_currency_change.rpc(amount)

@rpc("any_peer", "call_local", "reliable")
func _request_currency_change(amount):
	current_currency += amount

func take_damage(amount):
	if not multiplayer.is_server():
		return
	health -= amount
	_sync_health_to_client.rpc_id(get_multiplayer_authority(), health)
@rpc("any_peer", "reliable")
func request_refill_ammo():
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if get_multiplayer_authority() != sender_id:
		return # safety check

	_refill_all_ammo_server()
func _refill_all_ammo_server():
	for weapon_id in gunAmmo.keys():
		var weapon = _get_weapon(weapon_id)
		if not weapon:
			continue

		gunAmmo[weapon_id]["magazine"] = weapon.magazineSize
		gunAmmo[weapon_id]["ammo"] = weapon.maxAmmo

	_sync_all_ammo_to_client.rpc_id(
		get_multiplayer_authority(),
		gunAmmo
	)
@rpc("any_peer", "call_local", "reliable")
func _sync_all_ammo_to_client(new_ammo_data):
	gunAmmo = new_ammo_data

	var weapon = _get_weapon(current_weapon)
	if weapon:
		weapon.currentMagazine = gunAmmo[current_weapon]["magazine"]
		weapon.currentAmmo = gunAmmo[current_weapon]["ammo"]
		weapon.update_ammo_ui()

@rpc("any_peer", "call_local", "reliable")
func _sync_health_to_client(new_health):
	health = new_health
	if healthBar:
		healthBar.value = health
	if health <= 0:
		get_tree().change_scene_to_file("res://UI/Main Menu/main_menu.tscn")


	# Apply to current weapon
	var weapon = _get_weapon(current_weapon)
	if weapon:
		weapon.currentMagazine = gunAmmo[current_weapon]["magazine"]
		weapon.currentAmmo = gunAmmo[current_weapon]["ammo"]
		weapon.update_ammo_ui()

func _setup_weapon(weapon: Node3D):
	weapon.player = self
	weapon.playerCamera = playerCamera
	weapon.ammoLabel = ammoLabel
	weapon.visible = false
	weapon.set_process(false)

func handle_heal(delta):
	if action_locked:
		return
	if Input.is_action_just_pressed("heal") and heals > 0:
		action_locked = true
		heals -= 1

		var weapon = _get_weapon(current_weapon)
		if weapon:
			weapon.visible = false
			weapon.set_process(false)

		$heal0.visible = true
		var anim = $heal0/AnimationPlayer
		anim.play("heal")

		await anim.animation_finished

		# Smooth heal
		var heal_amount := 25
		var duration := 1.0
		var rate := heal_amount / duration
		var healed := 0.0

		while healed < heal_amount:
			var step = rate * get_process_delta_time()
			health += step
			healed += step
			health = min(health, 100)
			healthBar.value = health
			await get_tree().process_frame

		$heal0.visible = false

		if weapon:
			weapon.visible = true
			weapon.set_process(true)
			weapon.update_ammo_ui()

		action_locked = false

func handle_grenade(delta):
	if Input.is_action_just_pressed("grenade"):
		var grenade = GRENADE_SCENE.instantiate()
		get_parent().add_child(grenade)

		# Spawn slightly in front of the player
		grenade.global_position = global_position + -global_transform.basis.z * 0.6

		# Throw direction (forward)
		var throw_dir = -global_transform.basis.z

		# Apply force
		grenade.get_child(0).apply_impulse(throw_dir * 12.0)
func get_pistol() -> Node3D:
	return $WeaponContainer/Revolver  # assuming your pistol is the revolver

func handle_melee(delta):
	if action_locked:
		return

	if Input.is_action_just_pressed("melee"):
		action_locked = true
		melee_hit_bodies.clear()

		var current_weapon_node = _get_weapon(current_weapon)
		if current_weapon_node:
			current_weapon_node.set_process(false)
			current_weapon_node.visible = false  # hide gun

		# Show knife
		$knife1.visible = true
		var anim := $knife1/AnimationPlayer
		anim.play("slice")

		# Enable hitbox
		$Area3D.monitoring = true
		var callable_hit = Callable(self, "_on_melee_body_entered")
		if not $Area3D.is_connected("body_entered", callable_hit):
			$Area3D.body_entered.connect(callable_hit)

		# Wait for swing animation to finish
		await anim.animation_finished

		# Cleanup after swing
		$Area3D.monitoring = false
		melee_hit_bodies.clear()
		$knife1.visible = false

		# Restore gun AFTER knife is gone
		if current_weapon_node:
			current_weapon_node.visible = true
			current_weapon_node.set_process(true)
			current_weapon_node.update_ammo_ui()

		action_locked = false

@rpc("any_peer", "reliable")
func request_melee_damage(enemy_path: NodePath, damage_to_deal: float, player_path: NodePath):
	if not multiplayer.is_server():
		return

	var enemy = get_node_or_null(enemy_path)
	var dealer = get_node_or_null(player_path)

	if enemy and dealer and enemy.has_method("take_damage"):
		enemy.take_damage(damage_to_deal, dealer)
func _on_melee_body_entered(body):
	if body in melee_hit_bodies:
		return
	melee_hit_bodies[body] = true

	if body.has_method("take_damage") and not body.is_in_group("players"):
		if multiplayer.is_server():
			body.take_damage(100, self)
		else:
			request_melee_damage.rpc_id(
				1,
				body.get_path(),
				100,
				self.get_path()
			)
		print("Enemy Hit:", body.name)
