extends CharacterBody2D

class_name Player

signal points_scored(points: int)
signal castle_entered

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

enum PlayerMode {
	SMALL,
	BIG,
	SHOOTING
}

const PIPE_ENTER_THRESHOLD = 10

#On ready
const POINTS_LABEL_SCENE = preload("res://Scenes/points_label.tscn")
const SMALL_MARIO_COLLISION_SHAPE = preload("res://Resources/CollisionShapes/small_mario_collision_shape.tres")
const BIG_MARIO_COLLISION_SHAPE = preload("res://Resources/CollisionShapes/big_mario_collision_shape.tres")
const FIREBALL_SCENE = preload("res://Scenes/fireball.tscn")
# References
@onready var animated_sprite_2d = $AnimatedSprite2D as PlayerAnimatedSprite
@onready var area_2d = $Area2D
@onready var area_collision_shape = $Area2D/AreaCollisionShape
@onready var body_collision_shape = $BodyCollisionShape
@onready var shooting_point = $ShootingPoint
@onready var slide_down_finished_position = $"../slide_down_finished_position"
@onready var land_down_marker = $"../LandDownMarker" as Marker2D


@export_group("Locomotion")
@export var run_speed_damping = 0.5
@export var speed = 200.0
@export var jump_velocity = -350
@export_group("")


@export_group("Stomping enemies")
@export var min_stomp_degree = 35
@export var max_stomp_degree = 145
@export var stomp_y_velocity = -150
@export_group("")

@export_group("Camera sync")
@export var camera_sync: Camera2D
@export var should_camera_sync: bool = true
@export_group("")

@export var castle_path: PathFollow2D
var player_mode = PlayerMode.SMALL


# Player state flags
var is_dead = false
var is_on_path = false

func _ready():
	if SceneData.return_point != null && SceneData.return_point != Vector2.ZERO:
		global_position = SceneData.return_point

func _physics_process(delta):
	
	var camera_left_bound = camera_sync.global_position.x - camera_sync.get_viewport_rect().size.x / 2 / camera_sync.zoom.x
	
	# Apply gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	if global_position.x < camera_left_bound + 8 && sign(velocity.x) == -1:
		velocity = Vector2.ZERO
		return

	# Handle jumps
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	
	if Input.is_action_just_released("jump") and velocity.y < 0:
		velocity.y *= 0.5
		
	
	#Handle axis movement
	var direction = Input.get_axis("left", "right")
	
	if direction:
		velocity.x = lerpf(velocity.x, speed * direction, run_speed_damping * delta)
	else: 
		velocity.x = move_toward(velocity.x, 0, speed * delta)
	
	if Input.is_action_just_pressed("shoot") && player_mode == PlayerMode.SHOOTING:
		shoot()
	else:
		animated_sprite_2d.trigger_animation(velocity, direction, player_mode)
	
	var collision = get_last_slide_collision()
	if collision != null:
		handle_movement_collision(collision)

	move_and_slide()

func _process(delta):
	if global_position.x > camera_sync.global_position.x && should_camera_sync:
		camera_sync.global_position.x = global_position.x
	
	if is_on_path:
		castle_path.progress += delta * speed / 2
		if castle_path.progress_ratio > 0.97:
			is_on_path = false
			land_down()

func _on_area_2d_area_entered(area):
	if area is Enemy:
		handle_enemy_collision(area)
	if area is Shroom:
		handle_shroom_collision(area)
		area.queue_free()
	if area is ShootingFlower:
		handle_flower_collision()
		area.queue_free()

func handle_enemy_collision(enemy: Enemy):
	if enemy == null && is_dead:
		return
	var level_manager = get_tree().get_first_node_in_group("level_manager")
	if is_instance_of(enemy, Koopa) and (enemy as Koopa).in_a_shell:
		(enemy as Koopa).on_stomp(global_position)
		spawn_points_label(enemy)
		level_manager.on_points_scored(100)
	else:
		var angle_of_collision = rad_to_deg(position.angle_to_point(enemy.position))
		
		if angle_of_collision > min_stomp_degree && max_stomp_degree > angle_of_collision:
			enemy.die()
			on_enemy_stomped()
			spawn_points_label(enemy)
			level_manager.on_points_scored(100)
		else:
			die()
			
func handle_shroom_collision(area: Node2D):
	if player_mode == PlayerMode.SMALL:
		set_physics_process(false)
		animated_sprite_2d.play("small_to_big")	
		set_collision_shapes(false)

func handle_flower_collision():
	set_physics_process(false)
	var animation_name = "small_to_shooting" if player_mode == PlayerMode.SMALL else "big_to_shooting"
	animated_sprite_2d.play(animation_name)
	set_collision_shapes(false)

func spawn_points_label(enemy):
	var points_label = POINTS_LABEL_SCENE.instantiate()
	points_label.position = enemy.position + Vector2(-20, -20)
	get_tree().root.add_child(points_label)
	points_scored.emit(100)

func on_enemy_stomped():
	velocity.y = stomp_y_velocity

func die():
	if player_mode == PlayerMode.SMALL:
		is_dead = true
		animated_sprite_2d.play("death")

		area_2d.set_collision_mask_value(3, false)
		set_collision_layer_value(1, false)

		set_physics_process(false)
		
		var death_tween = get_tree().create_tween()
		death_tween.tween_property(self, "position", position + Vector2(0, -48), .5)
		death_tween.chain().tween_property(self, "position", position + Vector2(0, 256), 1)
		death_tween.tween_callback(func (): get_tree().reload_current_scene())
		
	else:
		big_to_small()
	
func handle_movement_collision(collision: KinematicCollision2D):
	if collision.get_collider() is Block:
		var collision_angle = rad_to_deg(collision.get_angle())
		if roundf(collision_angle) == 180:
			(collision.get_collider() as Block).bump(player_mode)
	
	if collision.get_collider() is Pipe:
		var collision_angle = rad_to_deg(collision.get_angle())
		if roundf(collision_angle) == 0 && Input.is_action_just_pressed("down") && absf(collision.get_collider().position.x - position.x < PIPE_ENTER_THRESHOLD && collision.get_collider().is_traversable):
			print("GO DOWN")
			handle_pipe_collision()
			
func set_collision_shapes(is_small: bool):
	var collision_shape = SMALL_MARIO_COLLISION_SHAPE if is_small else BIG_MARIO_COLLISION_SHAPE
	area_collision_shape.set_deferred("shape", collision_shape)
	body_collision_shape.set_deferred("shape", collision_shape)

func big_to_small():
	set_collision_layer_value(1, false)
	set_physics_process(false)
	var animation_name = "small_to_big" if player_mode == PlayerMode.BIG else "small_to_shooting"
	animated_sprite_2d.play(animation_name, 1.0, true)
	set_collision_shapes(true)

func shoot():
	animated_sprite_2d.play("shoot")
	set_physics_process(false)
	
	var fireball = FIREBALL_SCENE.instantiate()
	fireball.direction = sign(animated_sprite_2d.scale.x)
	fireball.global_position = shooting_point.global_position
	get_tree().root.add_child(fireball)

func handle_pipe_collision():
	set_physics_process(false)
	z_index = -3
	var pipe_tween = get_tree().create_tween()
	pipe_tween.tween_property(self, "position", position + Vector2(0, 32), 1)
	pipe_tween.tween_callback(switch_to_underground)
	
func switch_to_underground():
	var level_manager = get_tree().get_first_node_in_group("level_manager")
	SceneData.player_mode = player_mode
	SceneData.coins = level_manager.coins
	SceneData.points = level_manager.points 
	get_tree().change_scene_to_file("res://Scenes/underground.tscn")
	
	

func handle_pipe_connector_entrance_collision():
	set_physics_process(false)
	var pipe_tween = get_tree().create_tween()
	pipe_tween.tween_property(self, "position", position + Vector2(32, 0), 1)
	pipe_tween.tween_callback(switch_to_main)

func switch_to_main():
	var level_manager = get_tree().get_first_node_in_group("level_manager")
	SceneData.player_mode = player_mode
	SceneData.coins = level_manager.coins
	SceneData.points = level_manager.points 
	get_tree().change_scene_to_file("res://Scenes/main.tscn")

func on_pole_hit():
	set_physics_process(false)
	velocity = Vector2.ZERO
	if is_on_path:
		return
	
	animated_sprite_2d.on_pole(player_mode)
	
	var slide_down_tween = get_tree().create_tween()
	var slide_down_position = slide_down_finished_position.position
	slide_down_tween.tween_property(self, "position", slide_down_position, 2)
	slide_down_tween.tween_callback(slide_down_finished)
	
func slide_down_finished():
	var animation_prefix = Player.PlayerMode.keys()[player_mode].to_snake_case()
	is_on_path = true
	animated_sprite_2d.play("%s_jump" % animation_prefix)
	reparent(castle_path)

func land_down():
	reparent(get_tree().root.get_node("main"))
	var distance_to_marker = (land_down_marker.position - position).y
	var land_tween = get_tree().create_tween()
	land_tween.tween_property(self, "position", position + Vector2(0, distance_to_marker - get_half_sprite_size()), .5)
	land_tween.tween_callback(go_to_castle)

func go_to_castle():
	var animation_prefix = Player.PlayerMode.keys()[player_mode].to_snake_case()
	animated_sprite_2d.play("%s_run" % animation_prefix)
	
	var run_to_castle_tween = get_tree().create_tween()
	run_to_castle_tween.tween_property(self, "position", position + Vector2(75, 0), .5)
	run_to_castle_tween.tween_callback(finish)

func finish():
	queue_free()
	castle_entered.emit()

func get_half_sprite_size():
	return 8 if player_mode == PlayerMode.SMALL else 16
