@tool
extends StaticBody2D

@export var block: Vector2i = Vector2i(1, 1):
	set(value):
		block = Vector2i(
			maxi(value.x, 1),
			maxi(value.y, 1)
		)

		if is_node_ready():
			update_shapes()


func _ready() -> void:
	update_shapes()


func update_shapes() -> void:
	var body_size := Vector2(block) * 16.0

	var body_shape := RectangleShape2D.new()
	body_shape.size = body_size
	$CollisionShape2D.shape = body_shape
