extends CharacterBody3D

signal died(killer_node)  

@export var speed = 1
@export var accel = 20
@export var health = 100
@export var attack_damage := 10
@export var attack_range := 2.0
@export var attack_cooldown := 1.2  # seconds between hits
const BLOOD_EFFECT_SCENE = preload("res://Scenes/Effects/blood_particles.tscn")
var can_attack := true
var current_anim_state: String = "Idle":
	set(value):
		current_anim_state = value
		# This code runs on EVERY client when the value is synced
		if has_node("FleshRot/AnimationPlayer"):
			$FleshRot/AnimationPlayer.play(value)

@onready var nav: NavigationAgent3D = $NavigationAgent3D
var players: Array[CharacterBody3D] = []
var target_player: CharacterBody3D = null



var ready_to_navigate := false
var gravity := 10

func _ready():
	call_deferred("actor_setup")

func _physics_process(delta):
	if not multiplayer.is_server():
		return
	if not ready_to_navigate:
		return

	target_player = find_closest_player()
	if target_player == null:
		return

	current_anim_state = "Walk"
	look_at_player(delta, target_player)

	nav.target_position = target_player.global_position

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

	if can_attack and global_position.distance_to(target_player.global_position) <= attack_range:
		attack_player(target_player)


func take_damage(damage_amount: int, dealer_node: Node = null) -> void:
	if not multiplayer.is_server():
		return

	health -= damage_amount

	# Emit the visual effect globally via RPC when hit
	# You could pass the impact direction here for more realism
	play_hurt_effects.rpc(global_transform.origin) 

	if health <= 0:
		if not is_queued_for_deletion():
			died.emit(dealer_node) 
			queue_free()

# signal died(attacker_id: int) 

@rpc("authority", "call_local", "reliable")
func play_hurt_effects(impact_position: Vector3):
	$AudioStreamPlayer3D.play()
	
	# Instance and place the blood effect scene
	var blood_instance = BLOOD_EFFECT_SCENE.instantiate()
	get_tree().current_scene.add_child(blood_instance)
	
	# Position the blood where the enemy is standing (you might refine this 
	# if your damage system knows the exact impact point/normal)
	blood_instance.global_position = impact_position
	
	# Start the one-shot particle effect if it didn't autostart
	blood_instance.get_child(0).restart() 
func attack_player(p: CharacterBody3D):
	if p == null:
		return

	can_attack = false
	p.take_damage(attack_damage)

	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func look_at_player(delta, p: CharacterBody3D):
	if p == null:
		return

	var to_player = p.global_position - global_position
	to_player.y = 0

	if to_player.length() > 0.001:
		var target_yaw = atan2(to_player.x, to_player.z)
		
		# --- OFFSET ADJUSTMENT ---
		# If it's sideways, add PI/2 (90 degrees). 
		# If it's backwards, add PI (180 degrees).
		var offset = -80 # Start at 0 and test
		# offset = PI       # Try this if it looks backwards
		# offset = PI / 2   # Try this if it looks left
		# offset = -PI / 2  # Try this if it looks right
		
		rotation.y = lerp_angle(rotation.y, target_yaw + offset, delta * 8.0)
func actor_setup():
	await get_tree().physics_frame
	players.clear()

	for n in get_tree().get_nodes_in_group("players"):
		if n is CharacterBody3D:
			players.append(n)

	ready_to_navigate = true
func find_closest_player() -> CharacterBody3D:
	var closest: CharacterBody3D = null
	var closest_dist := INF

	# --- FIX: Refresh the list to include newly joined players ---
	players = []
	for n in get_tree().get_nodes_in_group("players"):
		if n is CharacterBody3D:
			players.append(n)
	# -------------------------------------------------------------

	for p in players:
		if not is_instance_valid(p):
			continue

		var d = global_position.distance_squared_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = p

	return closest
