extends CharacterBody3D

signal died(killer_node)
@export var is_screaming : bool
@export var speed := 1.0
@export var health := 100
@export var attack_damage := 10
@export var attack_range := 2.0
@export var attack_cooldown := 1.2
@export var rotation_offset_degrees := 90
@export var walk_speed := 2.2
@export var walk_distance_per_cycle := 0.7
@export var anim_player: AnimationPlayer
const BLOOD_EFFECT_SCENE = preload("res://Scenes/Effects/blood_splatter.tscn")
const BLOOD_EFFECT_SCENE2 = preload("res://Scenes/Effects/blood_particles.tscn")
@export var is_animation_driven: bool = true
var can_attack := true
var gravity := 10.0
var ready_to_navigate := false
@export var limb_nodes: Array[NodePath] = []

var remaining_limbs: Array[Node3D] = []

var players: Array[CharacterBody3D] = []
var target_player: CharacterBody3D = null

@onready var nav: NavigationAgent3D = $NavigationAgent3D

@export var skeleton : Skeleton3D

var current_anim_state := "Idle":
	set(value):
		if current_anim_state == value:
			return
		current_anim_state = value
		anim_player.play(value)

func _ready():
	anim_player.speed_scale = speed
	call_deferred("actor_setup")
	if is_screaming:
		$AudioStreamPlayer3D2.play()
	
func _physics_process(delta):
	if not multiplayer.is_server():
		return
	if not ready_to_navigate:
		return

	# 1️⃣ Find target
	target_player = find_closest_player()
	if target_player == null:
		current_anim_state = "Idle"
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	# 2️⃣ Set navigation target
	nav.target_position = target_player.global_position

	# 3️⃣ Rotate toward target
	current_anim_state = "walk"
	look_at_player(delta, target_player)

	# 4️⃣ Move toward target
	var to_target := nav.get_next_path_position() - global_position
	to_target.y = 0
	var direction := to_target.normalized()  # Important to normalize!

	if is_animation_driven:
		# Use animation-driven movement
		var anim := anim_player.get_animation("walk")
		var cycle_time := anim.length / anim_player.speed_scale
		var move_speed := walk_distance_per_cycle / cycle_time
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		# Use normal movement
		velocity.x = direction.x * walk_speed
		velocity.z = direction.z * walk_speed

	# 5️⃣ Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

	# 6️⃣ Attack
	if can_attack and global_position.distance_to(target_player.global_position) <= attack_range:
		attack_player(target_player)



	# 5️⃣ Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

	if global_position.distance_to(target_player.global_position) <= 5:
		if $AudioStreamPlayer3D4 != null:
			$AudioStreamPlayer3D4.play()
	if can_attack and global_position.distance_to(target_player.global_position) <= attack_range:
		attack_player(target_player)


func take_damage(damage_amount: int, dealer_node: Node = null) -> void:
	if not multiplayer.is_server():
		return

	health -= damage_amount
	play_hurt_effects.rpc(global_position)
	
	if health <= 0:
		die.rpc()
		died.emit(dealer_node)


@rpc("authority", "call_local", "reliable")
func play_hurt_effects(impact_position: Vector3):
	$AudioStreamPlayer3D.play()
	var newparticles = BLOOD_EFFECT_SCENE2.instantiate()
	
	# 2. Add to the MAIN SCENE (not as a child of the enemy)
	# This prevents particles from vanishing when the enemy dies
	get_tree().current_scene.add_child(newparticles)
	
	# 3. Position them at the impact point
	newparticles.global_position = impact_position
	
	# 4. Trigger emission
	# Assuming your scene structure has a GPUParticles3D as the first child
	var particle_node = newparticles.get_child(0) 
	if particle_node is GPUParticles3D or particle_node is CPUParticles3D:
		particle_node.emitting = true
		
		# 5. Auto-cleanup: Free the particles after they finish (e.g., 2 seconds)
		get_tree().create_timer(2.0).timeout.connect(newparticles.queue_free)

	var space_state = get_world_3d().direct_space_state

	const SPLAT_COUNT := 6
	const SPLAT_RADIUS := 1

	for i in SPLAT_COUNT:
		var offset = Vector3(
			randf_range(-SPLAT_RADIUS, SPLAT_RADIUS),
			0,
			randf_range(-SPLAT_RADIUS, SPLAT_RADIUS)
		)
		await get_tree().create_timer(0.05).timeout

		var ray_params = PhysicsRayQueryParameters3D.new()
		ray_params.from = impact_position + offset + Vector3.UP * 0.5
		ray_params.to = impact_position + offset + Vector3.DOWN * 2.5
		ray_params.collide_with_areas = false
		ray_params.collide_with_bodies = true

		var result = space_state.intersect_ray(ray_params)

		if result:
			var decal: Decal = BLOOD_EFFECT_SCENE.instantiate()
			get_tree().current_scene.add_child(decal)

			# Position slightly above surface to avoid z-fighting
			decal.global_position = result.position + result.normal * 0.01


func attack_player(p: CharacterBody3D):
	if p == null:
		return

	can_attack = false
	p.take_damage(attack_damage)
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func look_at_player(delta, p: CharacterBody3D):
	var dir := p.global_position - global_position
	dir.y = 0

	if dir.length() < 0.001:
		return

	var target_yaw := atan2(dir.x, dir.z)
	var offset := deg_to_rad(rotation_offset_degrees)

	rotation.y = lerp_angle(
		rotation.y,
		target_yaw + offset,
		delta * 8.0
	)


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

	for p in get_tree().get_nodes_in_group("players"):
		if not (p is CharacterBody3D):
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = p

	return closest


@rpc("authority", "call_local", "reliable")
func die():
	ready_to_navigate = false
	set_physics_process(false)
	set_process(false)
	collision_layer = 0
	collision_mask = 0

	# Stop audio
	if $AudioStreamPlayer3D3 != null:
		$AudioStreamPlayer3D3.stop()
	if $AudioStreamPlayer3D4 != null:
		$AudioStreamPlayer3D4.stop()

	# Stop movement animations
	anim_player.stop()

	# Play death animation
	current_anim_state = "die"
	anim_player.play("die")

	# Spawn blood effect
	play_hurt_effects.rpc(global_position)

	# Optional: remove the enemy after 10 seconds
	await get_tree().create_timer(10.0).timeout
	queue_free()
