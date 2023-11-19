extends Area2D

class_name FallDownArea



func _on_body_entered(body):
	if (body is Player):
		body.die()
