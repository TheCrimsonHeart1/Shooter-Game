extends Label


func _ready():
	# Connect to the global signal
	GameEvents.timer_updated.connect(_on_timer_updated)

func _on_timer_updated(text_val: String, is_visible: bool):
	text = text_val
	visible = is_visible
