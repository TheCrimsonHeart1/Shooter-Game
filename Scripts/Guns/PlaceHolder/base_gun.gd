extends Node3D

@export var followSpeed := 42.0
@export var gunOffset := Vector3(0.25, -0.25, -0.4)
@export var adsOffset := Vector3(-0.2, 0.1, 0.15) 
@export var adsSpeed := 8.0                       
@export var playerCamera: Camera3D
@export var player: CharacterBody3D 
@export var recoilPitch := 10.0      
@export var recoilYaw := 2.0       
@export var recoilRecoverySpeed := 10.0
@export var fireRate := 0.1  
@export var shakeIntensity := 0  
@export var shakeDuration := 0   
@onready var muzzleFlash: GPUParticles3D = $"AK47 Placeholder/GPUParticles3D"

@export var magazineSize: int = 30   # Bullets per magazine
@export var maxAmmo: int = 120       # Total ammo carried
@export var reloadTime: float = 1.5  # Seconds to reload


var currentMagazine: int
var currentAmmo: int
var isReloading: bool = false
var reloadTimer: float = 0.0

@onready var ammoLabel: Label = $"../PlayerBody/PlayerUI/AmmoLabel"



var isAiming = false
var current_offset: Vector3
var recoilOffset := Vector3.ZERO
var fireTimer := 0.0
var shakeTimer := 0.0
var originalCameraPos: Vector3

func _ready():
	currentMagazine = magazineSize
	currentAmmo = maxAmmo
	update_ammo_ui()
	current_offset = gunOffset
	originalCameraPos = playerCamera.position


func _process(delta):
	if playerCamera == null or player == null:
		return  

	fireTimer -= delta
	
	# Handle reload
	if isReloading:
		reloadTimer -= delta
		if reloadTimer <= 0.0:
			finish_reload()
	elif Input.is_action_just_pressed("reload") and currentMagazine < magazineSize and currentAmmo > 0:
		start_reload()

	if shakeTimer > 0:
		shakeTimer -= delta
	
	handleGun(delta)


func handleGun(delta):
	if Input.is_action_pressed("aim"):
		isAiming = true
		current_offset = current_offset.lerp(gunOffset + adsOffset, adsSpeed * delta)
	else:
		isAiming = false
		current_offset = current_offset.lerp(gunOffset, adsSpeed * delta)
		
	recoilOffset = recoilOffset.lerp(Vector3.ZERO, recoilRecoverySpeed * delta)
	
	var base_camera_pos = player.get_camera_base_position()
	global_position = base_camera_pos + playerCamera.global_transform.basis * current_offset  

	var target_pitch = playerCamera.global_rotation.x + deg_to_rad(recoilOffset.x)
	var target_yaw = playerCamera.global_rotation.y + deg_to_rad(recoilOffset.y)

	global_rotation.x = lerp_angle(global_rotation.x, target_pitch, followSpeed * delta * 0.8)
	global_rotation.y = lerp_angle(global_rotation.y, target_yaw, followSpeed * delta)
	global_rotation.z = 0.0
	
	if Input.is_action_pressed("shoot") and fireTimer <= 0.0 and not isReloading:
		if currentMagazine > 0:
			currentMagazine -= 1
			update_ammo_ui()

			$AudioStreamPlayer3D.play()
			if muzzleFlash:
				muzzleFlash.restart()
				muzzleFlash.emitting = true

			recoilOffset.x += randf_range(recoilPitch * 0.7, recoilPitch)
			recoilOffset.y += randf_range(-recoilYaw, recoilYaw)

			fireTimer = fireRate
			triggerScreenShake()
		else:
			start_reload()  # Automatically reload if magazine is empty


	if shakeTimer > 0:
		applyScreenShake()

func triggerScreenShake():
	shakeTimer = shakeDuration

func applyScreenShake():
	playerCamera.position = originalCameraPos + Vector3(
		randf_range(-shakeIntensity, shakeIntensity),
		randf_range(-shakeIntensity, shakeIntensity),
		0.0 
	)
	
func start_reload():
	isReloading = true
	reloadTimer = reloadTime

func finish_reload():
	isReloading = false
	var ammoNeeded = magazineSize - currentMagazine
	var ammoToLoad = min(ammoNeeded, currentAmmo)
	currentMagazine += ammoToLoad
	currentAmmo -= ammoToLoad
	update_ammo_ui()

func update_ammo_ui():
	if ammoLabel:
		ammoLabel.text = str(currentMagazine) + " / " + str(currentAmmo)
