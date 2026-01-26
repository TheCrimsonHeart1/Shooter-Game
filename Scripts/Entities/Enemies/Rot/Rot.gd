extends CharacterBody3D

signal died(killer_node)

@export var health := 100
@export var is_screaming : bool
@export var skele_sim : PhysicalBoneSimulator3D
@export var skeleton : Skeleton3D
@export var speed := 1.0
@export var walk_speed := 2.2
@export var walk_distance_per_cycle := 0.7
@export var anim_player: AnimationPlayer
@export var knockback : int = 8
@export var attack_damage := 10
@export var attack_range := 2.0
@export var attack_cooldown := 1.2
@export var rotation_offset_degrees := 90
@export var is_animation_driven: bool = true
@export var meshenemy: MeshInstance3D
const BLOOD_EFFECT_SCENE = preload("res://Scenes/Effects/blood_splatter.tscn")
const BLOOD_EFFECT_SCENE2 = preload("res://Scenes/Effects/blood_particles.tscn")
const LIMB_KEYWORDS := ["arm", "hand", "leg", "foot", "thigh", "calf", "upperarm", "lowerarm"]

var is_dead := false
var can_attack := true
var gravity := 10.0
var ready_to_navigate := false
var target_player: CharacterBody3D = null

@onready var nav: NavigationAgent3D = $NavigationAgent3D

# This property should be in your MultiplayerSynchronizer
var current_anim_state := "Idle":
	set(value):
		if current_anim_state == value: return
		current_anim_state = value
		if anim_player: anim_player.play(value)

func _ready():
	if anim_player:
		anim_player.speed_scale = speed
	call_deferred("actor_setup")
	if is_screaming and is_instance_valid($AudioStreamPlayer3D2):
		$AudioStreamPlayer3D2.play()

func _physics_process(delta):
	# ONLY the server handles movement and AI logic
	if not multiplayer.is_server() or is_dead or not ready_to_navigate:
		return

	target_player = find_closest_player()
	if target_player == null:
		current_anim_state = "Idle"
		velocity.x = 0; velocity.z = 0
		move_and_slide()
		return

	nav.target_position = target_player.global_position
	current_anim_state = "walk"
	look_at_player(delta, target_player)

	var to_target := nav.get_next_path_position() - global_position
	to_target.y = 0
	var direction := to_target.normalized()

	var move_speed = walk_speed
	if is_animation_driven and anim_player.has_animation("walk"):
		var anim := anim_player.get_animation("walk")
		var cycle_time := anim.length / anim_player.speed_scale
		move_speed = walk_distance_per_cycle / cycle_time

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

	if can_attack and global_position.distance_to(target_player.global_position) <= attack_range:
		attack_player(target_player)

# --- COMBAT LOGIC ---

# Call this from the player's raycast script: 
# if hit_node.has_method("request_damage"): hit_node.request_damage.rpc_id(1, amount, is_headshot)
@rpc("any_peer", "call_local", "reliable")
func request_damage(amount: int, was_headshot: bool = false, dealer_node_path: NodePath = "", _unused_extra = null):
	# We only process damage on the server
	if not multiplayer.is_server():
		return
	
	# Optional: Get the player node if you need it for kill credit
	var dealer = get_node_or_null(dealer_node_path)
	
	if was_headshot:
		# Direct call to headshot logic
		take_headshot(amount, dealer)
	else:
		# Direct call to body damage logic
		take_damage(amount, dealer)

# Update these to match the "dealer" logic
func take_damage(damage_amount: int, dealer_node: Node = null) -> void:
	if is_dead: return
	health -= damage_amount
	play_hurt_effects.rpc(global_position, false)
	if health <= 0:
		die.rpc(dealer_node.global_position if dealer_node else global_position)

func take_headshot(damage_amount: int, dealer_node: Node = null) -> void:
	if is_dead: return
	health -= (damage_amount * 5) # Headshot multiplier
	play_hurt_effects.rpc(global_position, true)
	if health <= 0:
		die.rpc(dealer_node.global_position if dealer_node else global_position)

@rpc("authority", "call_local", "reliable")
func play_hurt_effects(impact_position: Vector3, headshot: bool):
	if headshot:
		remove_head()
	else:
		remove_random_limb()
	
	# 1. Instantiate
	var blood = BLOOD_EFFECT_SCENE2.instantiate()
	# 2. Add to tree BEFORE setting properties
	get_tree().current_scene.add_child(blood)
	blood.global_position = impact_position
	
	# 3. Trigger Emission
	# If your scene is just the particle node:
	if blood is GPUParticles3D or blood is CPUParticles3D:
		blood.emitting = true
	else:
		# If your scene has a script or child particles:
		for child in blood.find_children("*", "GPUParticles3D"):
			child.emitting = true
		for child in blood.find_children("*", "CPUParticles3D"):
			child.emitting = true

	# 4. Audio
	if has_node("AudioStreamPlayer3D"):
		$AudioStreamPlayer3D.play()
	
	# 5. Cleanup
	get_tree().create_timer(2.0).timeout.connect(blood.queue_free)

@rpc("authority", "call_local", "reliable")
func die(killer_position: Vector3):
	if is_dead: return
	is_dead = true
	died.emit(self)

	ready_to_navigate = false
	collision_layer = 0
	collision_mask = 0

	if skele_sim:
		skele_sim.active = true
		skele_sim.physical_bones_start_simulation()
		for bone in skele_sim.get_children():
			if bone is PhysicalBone3D:
				var dir = (bone.global_position - killer_position).normalized()
				bone.linear_velocity = dir * knockback
	elif anim_player.has_animation("die"):
		anim_player.play("die")

	await get_tree().create_timer(5.0).timeout
	if is_inside_tree() and multiplayer.is_server():
		queue_free()

# --- HELPER FUNCTIONS ---

func remove_head():
	if not skeleton: return
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).to_lower().contains("head"):
			skeleton.set_bone_pose_scale(i, Vector3.ZERO)
			break

func remove_random_limb():
	if not skeleton or randf() > 0.5: return
	var valid_indices = []
	for i in skeleton.get_bone_count():
		var b_name = skeleton.get_bone_name(i).to_lower()
		for kw in LIMB_KEYWORDS:
			if b_name.contains(kw):
				valid_indices.append(i)
				break
	if valid_indices.size() > 0:
		skeleton.set_bone_pose_scale(valid_indices.pick_random(), Vector3.ZERO)

func actor_setup():
	await get_tree().physics_frame
	ready_to_navigate = true

func find_closest_player() -> CharacterBody3D:
	var closest: CharacterBody3D = null
	var closest_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		var d := global_position.distance_squared_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = p
	return closest

func attack_player(p: CharacterBody3D):
	can_attack = false
	if p.has_method("take_damage"):
		p.take_damage(attack_damage)
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func look_at_player(delta, p: CharacterBody3D):
	var dir := p.global_position - global_position
	dir.y = 0
	if dir.length() < 0.01: return
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw + deg_to_rad(rotation_offset_degrees), delta * 8.0)
