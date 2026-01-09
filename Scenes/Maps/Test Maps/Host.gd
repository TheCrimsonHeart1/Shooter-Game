extends Button

@onready var multiplayer_manager = get_parent().get_parent()
@onready var host_button = self

func _ready():
	host_button.pressed.connect(_on_host_pressed)

func _on_host_pressed():
	if multiplayer_manager:
		multiplayer_manager.host_game()
