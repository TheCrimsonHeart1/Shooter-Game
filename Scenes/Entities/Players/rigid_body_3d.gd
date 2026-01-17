extends RigidBody3D

@export var fuse_time := 2.5
@export var damage := 200

func _ready() -> void:
	await get_tree().create_timer(fuse_time).timeout
	explode()

func explode():
	$Area3D.monitoring = true
	await get_tree().physics_frame

	# Damage enemies
	for body in $Area3D.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			if body.has_method("take_damage"):
				body.take_damage(damage)


	# Optional: explosion effects
	# spawn_particles()
	# play_sound()

	queue_free()
