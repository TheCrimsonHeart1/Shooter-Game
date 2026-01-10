extends Node3D
var normal_color = Color(1, 1, 1)      # white
var hover_color = Color(1, 0.7, 0.2)   # orange-ish
@onready var camera = $Camera3D
var hovered_label: Label3D = null
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var from = camera.project_ray_origin(event.position)
		var to = from + camera.project_ray_normal(event.position) * 1000

		var params = PhysicsRayQueryParameters3D.new()
		params.from = from
		params.to = to
		params.exclude = []
		params.collide_with_bodies = true
		params.collide_with_areas = false
		params.collision_mask = 0x7FFFFFFF

		var result = get_world_3d().direct_space_state.intersect_ray(params)
		if result:
			var clicked = result.collider
			match clicked.name:
				"PlayButton":
					print("Start game")
					get_tree().change_scene_to_file("res://Scenes/Maps/Test Maps/test_map1.tscn")
				"SettingsButton":
					print("Open settings")
				"QuitButton":
					get_tree().quit()


func _on_quit_button_mouse_entered() -> void:
	$QuitButton/QuitButton.modulate = hover_color


func _on_quit_button_mouse_exited() -> void:
	$QuitButton/QuitButton.modulate = normal_color


func _on_play_button_mouse_entered() -> void:
	$PlayButton/PlayButton.modulate = hover_color


func _on_play_button_mouse_exited() -> void:
	$PlayButton/PlayButton.modulate = normal_color
