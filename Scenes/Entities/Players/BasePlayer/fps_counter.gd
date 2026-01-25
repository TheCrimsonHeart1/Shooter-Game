extends Label

@onready var fps_label = self # Reference your Label node

func _process(delta):
	fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
