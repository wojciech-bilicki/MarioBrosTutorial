extends Area2D

class_name Shroom

@export var horizontal_speed = 20
@export var max_vertical_speed = 120
@export var vertical_velocity_gain = .1
@onready var shape_cast_2d = $ShapeCast2D

var allow_horizontal_movement = false
var vertical_speed = 0

func _ready():
	var spawn_tween = get_tree().create_tween()
	spawn_tween.tween_property(self, "position", position + Vector2(0, -16), .4)
	spawn_tween.tween_callback(func (): allow_horizontal_movement = true)
	
func _process(delta):
	if allow_horizontal_movement:
		position.x += delta * horizontal_speed
	
	if !shape_cast_2d.is_colliding() && allow_horizontal_movement:
		vertical_speed = lerpf(vertical_speed, max_vertical_speed, vertical_velocity_gain)
		position.y += delta * vertical_speed
	else: 
		vertical_speed = 0	
	
