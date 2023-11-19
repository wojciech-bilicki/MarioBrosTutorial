extends Area2D

class_name CollectableCoin

func _on_body_entered(body):
	if (body is Player):
		queue_free()
		get_tree().get_first_node_in_group("level_manager").on_coin_collected()
		
