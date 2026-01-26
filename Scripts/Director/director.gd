extends Node3D

@export var max_waves: int = 10
@export var enemy_scene: PackedScene
@export var bone_rot_scene: PackedScene
@export var spawn_points: Array[Node3D] = []
@export var time_between_waves := 30.0
@onready var enemy_container = $EnemyContainer
@export var hardened_rot_scene: PackedScene
@export var fast_rot_scene: PackedScene  # Add this at the top
@export var crawler_scene: PackedScene
@export var wave_music: Array[AudioStream] = []
@onready var music_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var countdown_player: AudioStreamPlayer3D = $AudioStreamPlayer3D_Countdown
@export var countdown_sound: AudioStream
@export var combat_music: AudioStream  # Music that plays during waves

var wave_ending := false
var enemies_alive: int = 0
var fast_rot_percent: float = 0.2  # Chance for fast_rot, adjust as needed
var hardened_rot_percent = 0.
var current_wave: int = 0

var enemies_per_wave: int = 20
var wave_in_progress: bool = false
var bone_rot_percent: float = 0.3
var crawler_percent: float = 0.2



func _ready() -> void:
	if multiplayer.is_server():
		await get_tree().create_timer(1.0).timeout
		start_next_wave()

func start_next_wave() -> void:
	if current_wave >= max_waves or wave_in_progress:
		return
	if not multiplayer.is_server():
		return

	wave_in_progress = true
	current_wave += 1


	play_combat_music.rpc()

	var num_to_spawn: int = enemies_per_wave + (current_wave - 1) * 3
	enemies_alive = num_to_spawn

	show_wave_text.rpc(current_wave)

	for i in range(num_to_spawn):
		await get_tree().create_timer(randf_range(0.1, 1.0)).timeout
		spawn_enemy()



@rpc("call_local", "reliable")
func show_wave_text(wave_num: int):
	var label = $UI/WaveLabel
	if label:
		label.text = "Wave %d" % wave_num
		label.visible = true
		$AudioStreamPlayer3D2.play()
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
	if not multiplayer.is_server():
		return
	
	var rand_val: float = randf()
	var enemy_instance: Node3D

	if rand_val < bone_rot_percent:
		enemy_instance = bone_rot_scene.instantiate()
	elif rand_val < bone_rot_percent + crawler_percent:
		enemy_instance = crawler_scene.instantiate()
	else:
		enemy_instance = enemy_scene.instantiate()  # normal rot

	enemy_instance.name = "Zombie_%d" % Time.get_ticks_usec()
	enemy_instance.died.connect(_on_enemy_died)

	enemy_container.add_child(enemy_instance, true)

	var spawn_point = spawn_points.pick_random() if spawn_points.size() > 0 else self
	enemy_instance.global_position = spawn_point.global_position + Vector3(randf(), 0.1, randf())


func _on_enemy_died(enemy, killer_node: Node = null):
	if killer_node and killer_node.is_in_group("players"):
		killer_node.update_currency(1)
	if randf_range(0.0, 1.0) <= 0.25:
		await do_slow_motion(0.2, 0.25)  

	enemies_alive -= 1
	print("Enemy died:", enemy, "remaining:", enemies_alive)

	if enemies_alive <= 0:
		wave_in_progress = false
		
		# Stop combat music when wave ends
		if music_player.playing:
			stop_combat_music.rpc()

		
		start_wave_countdown()

func enemy_killed(killing_player_node: Node) -> void:
	if not multiplayer.is_server():
		return

	# Trigger slow motion effect
	if randf_range(0.0, 1.0) <= 0.25:
		trigger_slow_motion.rpc(0.2, 0.25)  # 0.2x speed for 0.4 seconds

	if killing_player_node and killing_player_node.is_in_group("players"):
		killing_player_node.update_currency(1)

	if wave_ending:
		return

	wave_ending = true
	await get_tree().create_timer(0.1).timeout

	if enemy_container.get_child_count() == 0:
		print("No more enemies")
		wave_in_progress = false
		start_wave_countdown()
	else:
		wave_ending = false



func start_wave_countdown() -> void:
	var time_left := time_between_waves

	# Play countdown sound
	if countdown_sound:
		countdown_player.stream = countdown_sound
		countdown_player.play()

	while time_left > 0:
		var display_text = "Next wave in %d" % int(ceil(time_left))
		update_timer_ui.rpc(display_text, true)

		await get_tree().process_frame
		time_left -= get_process_delta_time()

	update_timer_ui.rpc("", false)

	# Stop countdown sound when timer ends
	if countdown_player.playing:
		countdown_player.stop()

	# ✅ RESET LOCKS HERE
	wave_ending = false

	start_next_wave()
func do_slow_motion(scale: float = 0.2, duration: float = 0.4) -> void:
	Engine.time_scale = scale
	var t := 0.0
	while t < duration:
		t += get_process_delta_time()
		await get_tree().process_frame
	Engine.time_scale = 1.0

@rpc("call_local", "reliable")
func play_combat_music():
	if combat_music:
		music_player.stream = combat_music
		music_player.play()
@rpc("call_local", "reliable")
func stop_combat_music():
	if music_player.playing:
		music_player.stop()
@rpc("call_local", "reliable")
func trigger_slow_motion(scale: float, duration: float):
	await do_slow_motion(scale, duration)
