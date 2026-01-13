extends Node3D

@onready var camera: Camera3D = $Camera3D

var normal_color = Color(1, 1, 1)      # white
var hover_color = Color(1, 0.7, 0.2)   # orange-ish

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Connect signals for multiplayer events
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# Called automatically when a client joins
func _on_peer_connected(id: int) -> void:
	print("Player with ID %d has joined the lobby!" % id)

# Called automatically when a client leaves
func _on_peer_disconnected(id: int) -> void:
	print("Player with ID %d has left the lobby." % id)


# Example input: raycast clicks on buttons
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var from = camera.project_ray_origin(event.position)
		var to = from + camera.project_ray_normal(event.position) * 1000

		var params = PhysicsRayQueryParameters3D.new()
		params.from = from
		params.to = to
		params.collide_with_bodies = true

		var result = get_world_3d().direct_space_state.intersect_ray(params)
		if result:
			var clicked = result.collider
			match clicked.name:
				"PlayButton":
					if multiplayer.is_server():
						print("SinglePlayer being made")
				"QuitButton":
					get_tree().quit()
