extends Button

@onready var multiplayer_manager = get_parent().get_parent()
@onready var join_button = self
@onready var ip_field = $IPField

func _ready():
	join_button.pressed.connect(_on_join_pressed)

func _on_join_pressed():
	if multiplayer_manager and ip_field.text != "":
		multiplayer_manager.join_game(ip_field.text)
