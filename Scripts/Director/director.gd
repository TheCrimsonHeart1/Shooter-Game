extends Node3D

@export var max_waves: int = 10
@export var enemy_scene: PackedScene
@export var bone_rot_scene: PackedScene
@export var spawn_points: Array[Node3D] = []
@export var time_between_waves := 30.0
@onready var enemy_container = $EnemyContainer

@export var fast_rot_scene: PackedScene  # Add this at the top


var fast_rot_percent: float = 0.1  # Chance for fast_rot, adjust as needed

var current_wave: int = 0
var current_enemies: int = 0
var enemies_per_wave: int = 3
var wave_in_progress: bool = false
var bone_rot_percent: float = 0.2

func _ready() -> void:
	if multiplayer.is_server():
		# Wait a moment for all clients to connect and spawn players
		await get_tree().create_timer(1.0).timeout
		start_next_wave()

func start_next_wave() -> void:
	if current_wave >= max_waves or wave_in_progress: return
	if not multiplayer.is_server(): return

	wave_in_progress = true
	current_wave += 1
	var num_to_spawn: int = enemies_per_wave + (current_wave - 1) * 2

	# Notify all clients to show their LOCAL UI
	show_wave_text.rpc(current_wave)

	current_enemies = num_to_spawn
	for i in range(num_to_spawn):
		spawn_enemy()

@rpc("call_local", "reliable")
func show_wave_text(wave_num: int):
	var label = $UI/WaveLabel
	if label:
		label.text = "Wave %d" % wave_num
		label.visible = true
		await get_tree().create_timer(2.0).timeout
		label.visible = false

@rpc("call_local", "unreliable")
func update_timer_ui(text_val: String, is_visible: bool):
	var label = $UI/WaveTimerLabel
	if label:
		label.text = text_val
		label.visible = is_visible

# HELPER: Finds the UI node on the local machine only
func _get_local_ui_node(node_name: String) -> Label:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_multiplayer_authority():
			# Adjust this path to match your Player Scene structure
			return player.get_node_or_null("PlayerUI/" + node_name) as Label
	return null

func spawn_enemy() -> void:
	if not multiplayer.is_server(): return

	var rand_val = randf()
	var enemy_instance: Node3D

	if rand_val <= fast_rot_percent:
		enemy_instance = fast_rot_scene.instantiate()
	elif rand_val <= fast_rot_percent + bone_rot_percent:
		enemy_instance = bone_rot_scene.instantiate()
	else:
		enemy_instance = enemy_scene.instantiate()

	enemy_instance.name = "Zombie_%d" % Time.get_ticks_usec()

	# Connect death signal
	enemy_instance.died.connect(_on_enemy_died)

	# Add to container
	enemy_container.add_child(enemy_instance, true)

	# Set spawn position
	var spawn_point = spawn_points.pick_random() if spawn_points.size() > 0 else self
	enemy_instance.global_position = spawn_point.global_position + Vector3(randf(), 0.1, randf())

# The callback function for the signal
func _on_enemy_died(killer_node: Node):
	enemy_killed(killer_node)

func enemy_killed(killing_player_node: Node) -> void:
	# Update ONLY the specific node instance that made the kill
	if killing_player_node and killing_player_node.is_in_group("players"):
		killing_player_node.update_currency(1)
	
	# Wave progression logic
	current_enemies -= 1
	if current_enemies <= 0:
		wave_in_progress = false
		start_wave_countdown()

func start_wave_countdown() -> void:
	var time_left := time_between_waves
	while time_left > 0:
		var display_text = "Next wave in %d" % int(ceil(time_left))
		update_timer_ui.rpc(display_text, true)
		
		await get_tree().process_frame
		time_left -= get_process_delta_time()

	update_timer_ui.rpc("", false)
	start_next_wave()
