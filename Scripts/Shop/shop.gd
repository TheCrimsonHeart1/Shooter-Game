extends Node3D

@export var shop_ui: CanvasLayer   # or Control
@export var interact_action := "interact"
@export var player : CharacterBody3D

var player_inside := false

func _ready():
	
	shop_ui.visible = false
	$Area3D.body_entered.connect(_on_body_entered)
	$Area3D.body_exited.connect(_on_body_exited)

func _input(event):
	if not player_inside:
		return

	if event.is_action_pressed(interact_action):
		toggle_shop()

func toggle_shop():
	shop_ui.visible = true
	player.isinshop = true
	if shop_ui.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_body_entered(body):
	if body is CharacterBody3D:
		player_inside = true

func _on_body_exited(body):
	if body is CharacterBody3D:
		player_inside = false
		close_shop()

func close_shop():
	player.isinshop = false
	shop_ui.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_button_2_pressed() -> void:
	close_shop()


func _on_button_3_pressed() -> void:
	if player.current_currency >= 3:
		player.hasak47 = true
		$ShopUI/Panel/Button3.visible = false
		player.update_currency(-3)



	# Update the current weapon instance
func _on_button_4_pressed() -> void:
	if player.current_currency < 3:
		return
	if not player or player.current_weapon_instance == null:
		return

	# Refill ammo in the player dictionary
	player.gunAmmo[0]["magazine"] = 30
	player.gunAmmo[0]["ammo"] = 120
	player.gunAmmo[1]["magazine"] = 6
	player.gunAmmo[1]["ammo"] = 36

	# Refill the currently equipped weapon instance
	player.current_weapon_instance.currentMagazine = player.gunAmmo[player.current_weapon]["magazine"]
	player.current_weapon_instance.currentAmmo = player.gunAmmo[player.current_weapon]["ammo"]
	player.current_weapon_instance.update_ammo_ui()
	player.update_currency(-3)
