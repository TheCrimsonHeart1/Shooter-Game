extends CharacterBody3D

@export var movementSpeed = 4
@export var defaultAccelerationRate = 7
@export var mouseSensitivity = 0.15
@export var gravityRate = 8
@export var jumpForce = 3
@export var accelerationRateInAir = 3
@export var headbobFrequency = 3.0
@export var headbobAmplitude = 0.04

@onready var playerCamera = $PlayerHead/PlayerCamera

var accelerationRate = 0
var pitch = 0.0
var headbobTime = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensitivity))
		
		pitch -= event.relative.y * mouseSensitivity
		playerCamera.rotation.x = deg_to_rad(pitch)

func _physics_process(delta: float) -> void:
	handleMovement(delta)
	applyGravity(delta)
	handleJump()
	
	if is_on_floor():
		headbobTime += delta * velocity.length() * float(is_on_floor())
		playerCamera.transform.origin = headbob(headbobTime)
	
func handleMovement(delta):
	var inputDirection := Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("back") - Input.get_action_strength("forward")
	)

	var direction := (transform.basis * Vector3(inputDirection.x, 0, inputDirection.y)).normalized()

	
	var targetVelocity : Vector3 = direction * movementSpeed
	velocity.x = lerp(velocity.x, targetVelocity.x, accelerationRate * delta)
	velocity.z = lerp(velocity.z, targetVelocity.z, accelerationRate * delta)
	
	move_and_slide()

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
		

func headbob(headbobTime):
	var headbobPosition = Vector3.ZERO
	headbobPosition.y = sin(headbobTime * headbobFrequency) * headbobAmplitude
	headbobPosition.x = sin(headbobTime * headbobFrequency / 2) * headbobAmplitude
	return headbobPosition
	
	
