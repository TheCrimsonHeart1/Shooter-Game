extends Control



func _ready():
	visible = false
	get_tree().paused = false

func _on_resume_pressed():
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_main_menu_pressed():
	multiplayer.multiplayer_peer = null # Reset networking to prevent ghost sessions
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://UI/Main Menu/main_menu.tscn")
	
func _on_quit_pressed():
	get_tree().quit()
