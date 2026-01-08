extends CharacterBody3D

@export var movementSpeed = 10
@export var accelerationRate = 7
@export var mouseSensitivity = 0.15
@export var gravityRate = 1
@export var jumpForce = 10

@onready var playerCamera = $PlayerCamera

var pitch := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensitivity))
		
		pitch -= event.relative.y * mouseSensitivity
		playerCamera.rotation.x = deg_to_rad(pitch)

func _physics_process(delta: float) -> void:
	handleMovement(delta)
	
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
