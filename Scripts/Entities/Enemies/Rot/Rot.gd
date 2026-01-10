extends CharacterBody3D

@export var speed = 1
@export var accel = 20
@export var health = 100

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@export var player : CharacterBody3D
signal died

var ready_to_navigate := false
var gravity := 10

func _ready():
	call_deferred("actor_setup")

func actor_setup():
	await get_tree().physics_frame
	ready_to_navigate = true

func _physics_process(delta):
	if not ready_to_navigate:
		return

	nav.target_position = player.global_position

	if not is_on_floor():
		velocity.y -= gravity * delta

	var next_pos = nav.get_next_path_position()
	var direction = next_pos - global_position
	direction.y = 0

	if direction.length() > 0.05:
		direction = direction.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = 0
		velocity.z = 0

	move_and_slide()
func take_damage(damage_amount: int) -> void:
	$AudioStreamPlayer3D.play()
	health -= damage_amount
	if health <= 0:
		if not is_queued_for_deletion():
			emit_signal("died")
			queue_free()
