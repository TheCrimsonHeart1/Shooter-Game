extends Node3D

@export var playerbody: CharacterBody3D
@export var max_waves: int = 10
@export var enemy_scene: PackedScene
@export var bone_rot_scene: PackedScene
@export var spawn_points: Array[Node3D] = []
@export var wave_label: Label  # drag your WaveLabel here


var current_wave: int = 0
var current_enemies: int = 0
var enemies_per_wave: int = 3
var wave_in_progress: bool = false
var bone_rot_percent = 0.2

# Keep track of enemies for safety
var enemy_list: Array = []

func _ready():
	start_next_wave()

func start_next_wave():
	if current_wave >= max_waves:
		print("All waves completed!")
		return

	if wave_in_progress:
		return  # already running a wave

	wave_in_progress = true
	current_wave += 1
	var num_to_spawn = enemies_per_wave + (current_wave - 1) * 2

	# Show wave text on screen
	if wave_label != null:
		wave_label.text = "Wave %d" % current_wave
		wave_label.visible = true
		# Hide after 2 seconds
		await get_tree().create_timer(2.0).timeout
		wave_label.visible = false

	print("Wave %d: Spawning %d enemies" % [current_wave, num_to_spawn])

	current_enemies = 0
	enemy_list.clear()

	for i in range(num_to_spawn):
		spawn_enemy()


func spawn_enemy():
	if enemy_scene == null:
		print("No enemy scene assigned!")
		return

	var spawn_point: Node3D
	if spawn_points.size() > 0:
		spawn_point = spawn_points[randi() % spawn_points.size()]
	else:
		spawn_point = self
	
	var enemy_instance
	if randf() <= bone_rot_percent:
		enemy_instance = bone_rot_scene.instantiate()
	else:
		enemy_instance = enemy_scene.instantiate()

	enemy_instance.player = playerbody

	# Set spawn position with offset to prevent overlapping
	if enemy_instance is CharacterBody3D:
		var offset = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		enemy_instance.global_position = spawn_point.global_position + offset + Vector3(0, 0.1, 0)
		enemy_instance.velocity = Vector3.ZERO
	else:
		enemy_instance.global_transform = Transform3D(enemy_instance.global_transform.basis, spawn_point.global_transform.origin)

	# Add to scene
	get_tree().current_scene.add_child(enemy_instance)

	# Add to list
	enemy_list.append(enemy_instance)
	current_enemies += 1

	# Connect died signal
	if enemy_instance.has_signal("died"):
		enemy_instance.died.connect(enemy_killed)
	else:
		# fallback: detect queue_free
		enemy_instance.connect("tree_exited", Callable(self, "enemy_killed"))

func enemy_killed():
	current_enemies -= 1
	playerbody.update_currency(1)
	if current_enemies <= 0:
		# Wave complete
		wave_in_progress = false
		enemy_list.clear()
		print("Wave %d complete!" % current_wave)
		await get_tree().create_timer(30.0).timeout
		start_next_wave()
