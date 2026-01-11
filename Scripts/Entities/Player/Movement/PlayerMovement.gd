extends CharacterBody3D

# --- Player Config ---
var current_currency = 0
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
@export var ak47 : PackedScene
@export var revolver : PackedScene
@export var recoilSpeedUp: float = 10.0     # how fast the camera moves up when shooting
@export var recoilRecoverySpeed: float = 5.0  # how fast the camera returns to normal
@export var currencylabel = Label
var cameraRecoilTarget: float = 0.0  # target recoil from shooting
@export var staminaRegenDelay: float = 0.4
var current_weapon : int = 0
var hasak47 = false
var health = 100

var gunAmmo := {
	0: {"magazine": 30, "ammo": 120},  # AK47
	1: {"magazine": 6,  "ammo": 36}    # Revolver
}


@onready var playerCamera: Camera3D = $PlayerHead/PlayerCamera
@onready var staminaBar: TextureProgressBar = $PlayerUI/StaminaBar
@onready var ammoLabel: Label = $PlayerUI/AmmoLabel

var accelerationRate: float = 0
var pitch: float = 0.0
var headbobTime: float = 0.0
var stamina: float
var staminaRegenTimer: float = 0.0
var displayed_stamina: float
var stamina_velocity: float = 0.0
var camera_default_position: Vector3
var mouse_locked: bool = true
var cameraBaseRotation := Vector2.ZERO  # x = pitch, y = yaw
var basePitch: float = 0.0  # Player-controlled pitch without recoil
var isinshop = false

func _ready() -> void:
	stamina = maxStamina
	displayed_stamina = maxStamina
	camera_default_position = playerCamera.transform.origin
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	cameraBaseRotation.x = rad_to_deg(playerCamera.rotation.x)
	cameraBaseRotation.y = rad_to_deg(rotation.y)
	basePitch = rad_to_deg(playerCamera.rotation.x)


func _input(event: InputEvent) -> void:
	if isinshop:
		return
	if $PauseMenu.visible:
		return
	
	if event is InputEventMouseMotion:
		# Horizontal rotation (player-controlled)
		rotate_y(deg_to_rad(-event.relative.x * mouseSensitivity))
		
		# Vertical rotation (player-controlled)
		basePitch -= event.relative.y * mouseSensitivity
		basePitch = clamp(basePitch, -89, 89)


func _physics_process(delta: float) -> void:
	if isinshop:
		$PlayerUI.visible = false
		return
	else:
		$PlayerUI.visible = true
	if $PauseMenu.visible:
		$PlayerUI.visible = false
		return
	else:
		$PlayerUI.visible = true
	handleMovement(delta)
	applyGravity(delta)
	handleJump()
	if Input.is_action_just_pressed("switch"):
		if current_weapon == 1 and hasak47:
			switch_gun(0) # Revolver → AK (only if unlocked)
		elif current_weapon == 0:
			switch_gun(1) # AK → Revolver (always allowed)

	if is_on_floor() and velocity.length() > 0:
		headbobTime += delta * velocity.length()
		playerCamera.transform.origin = camera_default_position + headbob(headbobTime)
	else:
		playerCamera.transform.origin = camera_default_position

func handleMovement(delta: float) -> void:
	var inputDirection: Vector2 = Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("back") - Input.get_action_strength("forward")
	)
	var direction: Vector3 = (transform.basis * Vector3(inputDirection.x, 0, inputDirection.y)).normalized()
	var currentSpeed: float = movementSpeed
	var isSprinting: bool = false

	if Input.is_action_pressed("sprint") and direction != Vector3.ZERO and is_on_floor() and stamina > 0.0:
		isSprinting = true
		currentSpeed *= sprintMultiplier
		accelerationRate = sprintAcceleration
	else:
		accelerationRate = defaultAccelerationRate

	var targetVelocity: Vector3 = direction * currentSpeed
	velocity.x = lerp(velocity.x, targetVelocity.x, accelerationRate * delta)
	velocity.z = lerp(velocity.z, targetVelocity.z, accelerationRate * delta)
	move_and_slide()

	if isSprinting:
		stamina -= staminaDrainRate * delta
		stamina = max(stamina, 0.0)
		staminaRegenTimer = staminaRegenDelay
	else:
		if staminaRegenTimer > 0.0:
			staminaRegenTimer -= delta
		else:
			stamina += staminaRegenRate * delta
			stamina = min(stamina, maxStamina)

func _process(delta: float) -> void:
	if health <= 0:
		get_tree().change_scene_to_file("res://UI/Main Menu/main_menu.tscn")
	if Input.is_action_just_pressed("pause"):
		if isinshop:
			return

		var pause_menu = $PauseMenu
		pause_menu.visible = not pause_menu.visible

		if pause_menu.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Smoothly approach the target recoil (slower upward movement)
	cameraRecoil.x = lerp(cameraRecoil.x, cameraRecoilTarget, recoilSpeedUp * delta)

	# Slowly decay the target toward 0 (camera returning to normal)
	cameraRecoilTarget = lerp(cameraRecoilTarget, float(0), recoilRecoverySpeed * delta)

	# Apply recoil to camera
	playerCamera.rotation.x = deg_to_rad(basePitch - cameraRecoil.x)


	
	# Stamina handling etc.

	var stiffness: float = 35.0
	var damping: float = 14.0
	var force: float = (stamina - displayed_stamina) * stiffness
	stamina_velocity += force * delta
	stamina_velocity *= exp(-damping * delta)
	displayed_stamina += stamina_velocity * delta
	staminaBar.value = displayed_stamina

	# Toggle mouse
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_mouse_lock()



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

func headbob(headbobTime: float) -> Vector3:
	var headbobPosition: Vector3 = Vector3.ZERO
	headbobPosition.y = sin(headbobTime * headbobFrequency) * headbobAmplitude
	headbobPosition.x = sin(headbobTime * headbobFrequency / 2) * headbobAmplitude
	return headbobPosition

func toggle_mouse_lock() -> void:
	mouse_locked = not mouse_locked
	if mouse_locked:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func get_camera_base_position() -> Vector3:
	if not Input.is_action_pressed("aim"):
		return playerCamera.global_position - headbob(headbobTime)
	return playerCamera.global_position
	
var current_weapon_instance: Node3D = null

func switch_gun(index: int):
	if current_weapon == index:
		return

	# Save current gun ammo
	if current_weapon_instance != null:
		if current_weapon in gunAmmo:
			gunAmmo[current_weapon]["magazine"] = current_weapon_instance.currentMagazine
			gunAmmo[current_weapon]["ammo"] = current_weapon_instance.currentAmmo
		current_weapon_instance.queue_free()
		current_weapon_instance = null

	# Instantiate new weapon
	if index == 0 and hasak47 == true:
		current_weapon_instance = ak47.instantiate()
	elif index == 1:
		current_weapon_instance = revolver.instantiate()
	else:
		return

	add_child(current_weapon_instance)
	current_weapon = index

	# Assign references
	current_weapon_instance.player = self
	current_weapon_instance.playerCamera = playerCamera
	current_weapon_instance.reticle = $PlayerUI/Reticle
	current_weapon_instance.ammoLabel = $PlayerUI/AmmoLabel

	# Load ammo for this gun
	if index in gunAmmo:
		current_weapon_instance.currentMagazine = gunAmmo[index]["magazine"]
		current_weapon_instance.currentAmmo = gunAmmo[index]["ammo"]
		current_weapon_instance.update_ammo_ui()

	
var cameraRecoil := Vector2.ZERO

func apply_camera_recoil(pitch_amount: float, yaw_amount: float) -> void:
	cameraRecoilTarget += pitch_amount
	# horizontal recoil is ignored

func update_currency(amount):
	current_currency += amount
	currencylabel.text = str(current_currency)

func take_damage(amount):
	health -= amount
