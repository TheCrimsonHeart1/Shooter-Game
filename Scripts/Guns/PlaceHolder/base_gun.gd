extends Node3D

var player: CharacterBody3D
var playerCamera: Camera3D

@onready var shootAudio = get_child(0).get_node("AudioStreamPlayer3D")
@onready var muzzleFlash: GPUParticles3D = get_child(0).get_node("GPUParticles3D")
@onready var ammoLabel: Label
@onready var reticle: TextureRect
var current_weapon: Node3D = null
var headbobOffset: Vector3 = Vector3.ZERO
@export var pellets: int = 8
@export var shotgunSpreadAngle: float = 6.0

@export var recoilamount: float = -0.5
@export var gunOffset: Vector3 = Vector3(0.25, -0.25, -0.4)
@export var adsOffset: Vector3 = Vector3(-0.2, 0.1, 0.15)
@export var adsSpeed: float = 10.0
@export var anim_tree: AnimationTree

# --- Headbob ---
@export var headbobFrequency: float = 4.0
@export var headbobAmplitude: Vector3 = Vector3(0.001, 0.006, 0.0)
var headbobTimer: float = 0.0

# --- Sway ---
@export var swayPosStrength: float = 0.001
@export var swayRotStrength: float = 0.2
@export var swaySmooth: float = 14.0
@export var adsSwayMultiplier: float = 0.3

var swayOffset: Vector3 = Vector3.ZERO
var swayRotation: Vector3 = Vector3.ZERO
var targetSwayOffset: Vector3 = Vector3.ZERO
var targetSwayRotation: Vector3 = Vector3.ZERO

@export var recoilPitch: float = 10.0
@export var recoilYaw: float = 2.0
@export var recoilRecoverySpeed: float = 10.0
var recoilOffset: Vector3 = Vector3.ZERO

@export var fireRate: float = 0.1
@export var damage: float = 25.0
@export var range: float = 100.0
@export var spreadAngle: float = 1.0
@export var bulletImpactScene: PackedScene
@export var isShotgun: bool = false
@export var magazineSize: int = 30
@export var maxAmmo: int = 120
@export var reloadTime: float = 1.5

var currentMagazine: int = 0
var currentAmmo: int = 0
var isReloading: bool = false
var reloadTimer: float = 0.0
var fireTimer: float = 0.0

var isAiming: bool = false
var currentOffset: Vector3 = Vector3.ZERO
func _enter_tree():
	# The name must be exactly the string version of the Peer ID (e.g. "1" or "123456")
	var id = name.to_int() 
	if id > 0:
		set_multiplayer_authority(id)
		# Ensure the synchronizer also knows who the boss is
		if has_node("MultiplayerSynchronizer"):
			$MultiplayerSynchronizer.set_multiplayer_authority(id)
func _ready():
	currentMagazine = magazineSize
	currentAmmo = maxAmmo
	currentOffset = gunOffset
	update_ammo_ui()
	if $"humanoid (3)1/AnimationPlayer" != null:
		$"humanoid (3)1/AnimationPlayer".speed_scale = 1.5
		$"humanoid (3)1/AnimationPlayer".play("reload")
	elif $"humanoid (4)Soldierprimary2/AnimationPlayer":
		$"humanoid (4)Soldierprimary2/AnimationPlayer".play("reload")
		
func _process(delta):
	if not player or not playerCamera: 
		return

	if not player.is_multiplayer_authority():
		return

	fireTimer -= delta

	if isReloading:
		reloadTimer -= delta
		if reloadTimer <= 0.0:
			finish_reload()

	handle_sway(delta)
	handle_headbob(delta)  # <-- add this
	handle_gun(delta)

	if Input.is_action_pressed("shoot") and fireTimer <= 0.0 and not isReloading:
		shoot()

	if Input.is_action_just_pressed("reload"):
		start_reload()


func _input(event):
	if not player or not player.is_multiplayer_authority() or not playerCamera:
		return
	
	if event is InputEventMouseMotion:
		var m := adsSwayMultiplier if isAiming else 1.0
		targetSwayOffset.x = -event.relative.x * swayPosStrength * m
		targetSwayOffset.y = -event.relative.y * swayPosStrength * m
		targetSwayRotation.x = -event.relative.y * swayRotStrength * m
		targetSwayRotation.y = -event.relative.x * swayRotStrength * m

func handle_sway(delta):
	swayOffset = swayOffset.lerp(targetSwayOffset, swaySmooth * delta)
	swayRotation = swayRotation.lerp(targetSwayRotation, swaySmooth * delta)
	targetSwayOffset = targetSwayOffset.lerp(Vector3.ZERO, swaySmooth * delta)
	targetSwayRotation = targetSwayRotation.lerp(Vector3.ZERO, swaySmooth * delta)

func handle_gun(delta):
	if player.isinshop or player.get_node("PauseMenu").visible:
		return

	isAiming = Input.is_action_pressed("aim")
	if playerCamera:
		var targetFOV = 70.0 if isAiming else 90.0
		playerCamera.fov = lerp(playerCamera.fov, targetFOV, 8.0 * delta)
	var targetOffset = gunOffset + (adsOffset if isAiming else Vector3.ZERO)
	currentOffset = currentOffset.lerp(targetOffset, adsSpeed * delta)
	recoilOffset = recoilOffset.lerp(Vector3.ZERO, recoilRecoverySpeed * delta)

	var offset_global = playerCamera.global_transform.basis * (currentOffset + swayOffset + headbobOffset)
	global_position = playerCamera.global_position + offset_global

	var camera_forward = -playerCamera.global_transform.basis.z
	var camera_up = playerCamera.global_transform.basis.y
	var forward = camera_forward

	forward = (Basis(camera_up, deg_to_rad(recoilOffset.y + swayRotation.y)) * forward).normalized()
	forward = (Basis(playerCamera.global_transform.basis.x, deg_to_rad(recoilOffset.x + swayRotation.x)) * forward).normalized()
	look_at(global_position + forward, camera_up)

func shoot():
	if player.isinshop or player.get_node("PauseMenu").visible:
		return
	if currentMagazine <= 0:
		start_reload()
		return

	currentMagazine -= 1
	fireTimer = fireRate
	update_ammo_ui()

	play_shoot_effects.rpc()

	recoilOffset.x += randf_range(recoilPitch * 0.7, recoilPitch)
	recoilOffset.y += randf_range(-recoilYaw, recoilYaw)

	if isShotgun:
		shoot_shotgun()
	else:
		shoot_ray()



@rpc("any_peer", "call_local", "unreliable") # Unreliable is better for fast sounds
func play_shoot_effects():
	if not is_instance_valid(self) or not is_inside_tree():
		return
	
	if shootAudio:
		# If the sound is already playing, restart it for a crisp "click" 
		# rather than stacking multiple instances of the same sound
		if shootAudio.playing:
			shootAudio.stop()
		shootAudio.play()
		
	if muzzleFlash:
		muzzleFlash.restart()
		muzzleFlash.emitting = true
func shoot_ray():
	if not player or not playerCamera:
		return

	player.apply_camera_recoil(recoilamount, 0)
	
	var forward = -playerCamera.global_transform.basis.z
	var spread = deg_to_rad(spreadAngle)
	var dir = (Basis(Vector3.UP, randf_range(-spread, spread)) * Basis(Vector3.RIGHT, randf_range(-spread, spread))) * forward

	var from = playerCamera.global_position
	var to = from + dir.normalized() * range

	var params = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [player.get_rid()]

	var result = get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return

	var target = result.collider
	
	# --- Unified Damage Logic ---
	if target and target.has_method("take_damage") and not target.is_in_group("players"):
		if multiplayer.is_server():
			# Server applies damage directly, passing the local player node
			target.take_damage(damage, player)
		else:
			# Client calls RPC with 3 arguments: Target, Damage, and Player Path
			request_damage_on_server.rpc_id(1, target.get_path(), damage, player.get_path())

	# Spawn impact locally for all
	spawn_impact.rpc(result.position, result.normal)
	

@rpc("any_peer", "call_local", "reliable")
func request_damage_on_server(node_path: NodePath, damage_to_deal: float, player_path: NodePath):
	if not multiplayer.is_server():
		return
	
	var target = get_node_or_null(node_path)
	var killer = get_node_or_null(player_path) # The 3rd argument
	
	if target and target.has_method("take_damage") and not target.is_in_group("players"):
		# Pass the killer node to the enemy's take_damage function
		target.take_damage(damage_to_deal, killer) 
@rpc("any_peer", "call_local", "reliable")
func spawn_impact(pos: Vector3, normal: Vector3):
	if bulletImpactScene:
		var decal = bulletImpactScene.instantiate()
		get_tree().current_scene.add_child(decal)
		decal.global_position = pos + normal * 0.01
		
		var up = normal
		var temp_fwd = Vector3.UP if abs(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var right = up.cross(temp_fwd).normalized()
		var fwd = right.cross(up).normalized()
		decal.global_transform.basis = Basis(right, up, fwd)
		decal.scale = Vector3(0.05, 0.05, 0.05)

func start_reload():
	if isReloading or currentAmmo <= 0: return
	isReloading = true
	reloadTimer = reloadTime
	if $"humanoid (3)1/AnimationPlayer" != null:
		$"humanoid (3)1/AnimationPlayer".play("reload")
	if $"humanoid (4)Soldierprimary2/AnimationPlayer" != null:
		$"humanoid (4)Soldierprimary2/AnimationPlayer".play("reload")
func finish_reload():
	isReloading = false
	var amount = min(magazineSize - currentMagazine, currentAmmo)
	currentMagazine += amount
	currentAmmo -= amount
	update_ammo_ui()

func update_ammo_ui():
	if ammoLabel and player.is_multiplayer_authority():
		ammoLabel.text = str(currentMagazine) + " / " + str(currentAmmo)
func request_weapon(weapon_scene: PackedScene):
	request_weapon_server.rpc_id(1, weapon_scene.resource_path)
@rpc("any_peer", "reliable")
func request_weapon_server(scene_path: String):
	if not multiplayer.is_server():
		return

	# Prevent duplication
	if current_weapon:
		current_weapon.queue_free()

	var scene: PackedScene = load(scene_path)
	var weapon = scene.instantiate()

	current_weapon = weapon
	add_child(weapon)

	# Authority belongs to the player
	weapon.set_multiplayer_authority(get_multiplayer_authority())
func handle_headbob(delta):
	# Use horizontal velocity (X and Z) so gravity (Y) doesn't affect the bob
	var horizontal_vel = Vector2(player.velocity.x, player.velocity.z).length()
	
	if player.is_on_floor() and horizontal_vel > 0.1:
		# Increase timer based on frequency and movement speed
		# Ensure player.movementSpeed is not zero to avoid crash
		var speed_factor = horizontal_vel / max(player.movementSpeed, 0.1)
		headbobTimer += delta * headbobFrequency * speed_factor
		
		headbobOffset.x = cos(headbobTimer * 0.5) * headbobAmplitude.x
		headbobOffset.y = sin(headbobTimer) * headbobAmplitude.y
	else:
		# Smoothly return to zero when not moving
		headbobTimer = 0
		headbobOffset = headbobOffset.lerp(Vector3.ZERO, 10 * delta)
func shoot_shotgun():
	if not player or not playerCamera:
		return
	
	player.apply_camera_recoil(recoilamount * 1.2, 0)

	var forward = -playerCamera.global_transform.basis.z
	var spread = deg_to_rad(shotgunSpreadAngle)

	for i in pellets:
		var dir = (Basis(Vector3.UP, randf_range(-spread, spread)) *
				   Basis(Vector3.RIGHT, randf_range(-spread, spread))) * forward

		var from = playerCamera.global_position
		var to = from + dir.normalized() * range

		var params = PhysicsRayQueryParameters3D.create(from, to)
		params.exclude = [player.get_rid()]

		var result = get_world_3d().direct_space_state.intersect_ray(params)
		if result.is_empty():
			continue

		var target = result.collider

		if target and target.has_method("take_damage") and not target.is_in_group("players"):
			if multiplayer.is_server():
				target.take_damage(damage, player)
			else:
				request_damage_on_server.rpc_id(
					1,
					target.get_path(),
					damage,
					player.get_path()
				)

		spawn_impact.rpc(result.position, result.normal)
