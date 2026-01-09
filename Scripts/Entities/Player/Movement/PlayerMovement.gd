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
@export var staminaRegenDelay: float = 0.4


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

func _ready() -> void:
	stamina = maxStamina
	displayed_stamina = maxStamina
	camera_default_position = playerCamera.transform.origin
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensitivity))
		pitch -= event.relative.y * mouseSensitivity
		pitch = clamp(pitch, -89.0, 89.0)
		playerCamera.rotation.x = deg_to_rad(pitch)

func _physics_process(delta: float) -> void:
	handleMovement(delta)
	applyGravity(delta)
	handleJump()
	
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
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_mouse_lock()

	var stiffness: float = 35.0
	var damping: float = 14.0
	var force: float = (stamina - displayed_stamina) * stiffness
	stamina_velocity += force * delta
	stamina_velocity *= exp(-damping * delta)
	displayed_stamina += stamina_velocity * delta
	staminaBar.value = displayed_stamina

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
	
