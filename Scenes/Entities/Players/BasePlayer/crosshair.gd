
extends Control

@export var base_gap := 6.0
@export var move_gap := 14.0
@export var shoot_kick := 10.0
@export var lerp_speed := 18.0

var current_gap := 0.0
var target_gap := 0.0
var shoot_offset := 0.0

@onready var up    = $Up
@onready var down  = $Down
@onready var left  = $Left
@onready var right = $Right

func _ready():
	current_gap = base_gap

func _process(delta):
	# Smooth interpolation
	current_gap = lerp(current_gap, target_gap + shoot_offset, delta * lerp_speed)
	shoot_offset = lerp(shoot_offset, 0.0, delta * lerp_speed * 1.5)

	# Apply offsets
	up.position    = Vector2(0, -current_gap)
	down.position  = Vector2(0,  current_gap)
	left.position  = Vector2(-current_gap, 0)
	right.position = Vector2( current_gap, 0)
