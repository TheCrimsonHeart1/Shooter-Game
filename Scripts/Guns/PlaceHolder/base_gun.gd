extends Node3D

var player: CharacterBody3D
var playerCamera: Camera3D
@onready var shootAudio = get_child(0).get_node("AudioStreamPlayer3D")
@onready var muzzleFlash: GPUParticles3D = get_child(0).get_node("GPUParticles3D")
@onready var ammoLabel: Label
@onready var reticle: TextureRect
@export var recoilamount = -0.5
@export var followSpeed := 40.0
@export var gunOffset := Vector3(0.25, -0.25, -0.4)
@export var adsOffset := Vector3(-0.2, 0.1, 0.15)
@export var adsSpeed := 10.0

@export var headbobFrequency := 4.0
@export var headbobAmplitude := Vector3(0.001, 0.006, 0.0)
var headbobTimer := 0.0

@export var swayPosStrength := 0.001
@export var swayRotStrength := 0.2
@export var swaySmooth := 14.0
@export var adsSwayMultiplier := 0.3
@export var recoilPitch := 10.0
@export var recoilYaw := 2.0
@export var recoilRecoverySpeed := 10.0
var cameraRecoilOffset := Vector2.ZERO
@export var cameraRecoilPitch := 1.5
@export var cameraRecoilYaw := 0.7
@export var cameraRecoilRecoverySpeed := 10.0

@export var fireRate := 0.1
@export var damage := 25.0
@export var range := 100.0
@export var spreadAngle := 1.0
@export var bulletImpactScene: PackedScene

@export var magazineSize := 30
@export var maxAmmo := 120
@export var reloadTime := 1.5

var currentMagazine := 0
var currentAmmo := 0
var isReloading := false
var reloadTimer := 0.0
var fireTimer := 0.0

var isAiming := false
var currentOffset := Vector3.ZERO

var swayOffset := Vector3.ZERO
var swayRotation := Vector3.ZERO
var targetSwayOffset := Vector3.ZERO
var targetSwayRotation := Vector3.ZERO

var recoilOffset := Vector3.ZERO

func _ready():
	currentMagazine = magazineSize
	currentAmmo = maxAmmo
	currentOffset = gunOffset
	update_ammo_ui()

func _process(delta):
	if not player or not playerCamera:
		return

	fireTimer -= delta

	# Handle reload timer
	if isReloading:
		reloadTimer -= delta
		if reloadTimer <= 0.0:
			finish_reload()

	handle_sway(delta)
	handle_gun(delta)
	handle_headbob(delta)

	# --- Shooting ---
	if Input.is_action_pressed("shoot") and fireTimer <= 0.0 and not isReloading:
		shoot()

	# --- Reload key ---
	if Input.is_action_just_pressed("reload"):
		start_reload()
		
	

func _input(event):
	if not playerCamera:
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
	if not playerCamera:
		return

	isAiming = Input.is_action_pressed("aim")
	var targetOffset = gunOffset + (adsOffset if isAiming else Vector3.ZERO)
	currentOffset = currentOffset.lerp(targetOffset, adsSpeed * delta)
	recoilOffset = recoilOffset.lerp(Vector3.ZERO, recoilRecoverySpeed * delta)

	# Compute final position in front of camera
	var offset_global = playerCamera.global_transform.basis * (currentOffset + swayOffset)
	global_position = playerCamera.global_position + offset_global

	# Compute rotation
	var camera_forward = -playerCamera.global_transform.basis.z
	var camera_up = playerCamera.global_transform.basis.y
	var forward = camera_forward

	# Apply recoil and sway
	forward = (Basis(camera_up, deg_to_rad(recoilOffset.y + swayRotation.y)) * forward).normalized()
	forward = (Basis(playerCamera.global_transform.basis.x, deg_to_rad(recoilOffset.x + swayRotation.x)) * forward).normalized()

	# Look in the final forward direction
	look_at(global_position + forward, camera_up)
func shoot():
	if currentMagazine <= 0:
		start_reload()
		return
	currentMagazine -= 1
	fireTimer = fireRate
	update_ammo_ui()

	if shootAudio:
		shootAudio.play()

	if muzzleFlash:
		muzzleFlash.restart()
		muzzleFlash.emitting = true

	recoilOffset.x += randf_range(recoilPitch * 0.7, recoilPitch)
	recoilOffset.y += randf_range(-recoilYaw, recoilYaw)

	shoot_ray()

func shoot_ray():
	player.apply_camera_recoil(recoilamount, 0)
	# Apply gun recoil
	recoilOffset.x += randf_range(recoilPitch * 0.7, recoilPitch)
	recoilOffset.y += randf_range(-recoilYaw, recoilYaw)

	# Apply camera recoil
	cameraRecoilOffset.x += randf_range(cameraRecoilPitch * 0.7, cameraRecoilPitch)
	cameraRecoilOffset.y += randf_range(-cameraRecoilYaw, cameraRecoilYaw)

	if not playerCamera or not player:
		return

	var forward = -playerCamera.global_transform.basis.z
	var spread = deg_to_rad(spreadAngle)
	var rotX = Basis(Vector3.RIGHT, randf_range(-spread, spread))
	var rotY = Basis(Vector3.UP, randf_range(-spread, spread))
	var dir = (rotY * rotX) * forward

	var from = playerCamera.global_position
	var to = from + dir.normalized() * range

	var params = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [player.get_rid()]

	var result = get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return

	if result.collider.has_method("take_damage"):
		result.collider.take_damage(damage)

	if bulletImpactScene:
		var decal = bulletImpactScene.instantiate()
		get_tree().current_scene.add_child(decal)
		decal.global_position = result.position + result.normal * 0.01

		var up_dir = result.normal
		var forward_dir = result.collider.global_transform.origin - decal.global_position
		if forward_dir.length() < 0.01:
			forward_dir = Vector3.FORWARD
		forward_dir = (forward_dir - up_dir * up_dir.dot(forward_dir)).normalized()
		var right_dir = up_dir.cross(forward_dir).normalized()

		var basis = Basis(right_dir, up_dir, forward_dir)
		decal.global_transform = Transform3D(basis, decal.global_position)
		decal.scale = Vector3(0.05, 0.05, 0.05)

func start_reload():
	if isReloading or currentAmmo <= 0:
		return
	isReloading = true
	reloadTimer = reloadTime

func finish_reload():
	isReloading = false
	var needed = magazineSize - currentMagazine
	var amount = min(needed, currentAmmo)
	currentMagazine += amount
	currentAmmo -= amount
	update_ammo_ui()

func update_ammo_ui():
	if ammoLabel:
		ammoLabel.text = str(currentMagazine) + " / " + str(currentAmmo)

func handle_headbob(delta):
	if not player or isAiming:
		return

	var horizontal_velocity = player.velocity
	horizontal_velocity.y = 0
	var speed = horizontal_velocity.length()
	var speed_ratio = clamp(speed / player.movementSpeed, 0.0, 1.0)

	headbobTimer += delta * headbobFrequency

	var bobX = sin(headbobTimer) * headbobAmplitude.x * speed_ratio
	var bobY = abs(sin(headbobTimer * 2)) * headbobAmplitude.y * speed_ratio
	var bobZ = 0.0

	# Only affect local sway offset for position, not rotation
	swayOffset.x = bobX
	swayOffset.y = bobY
