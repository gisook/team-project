@tool
class_name ActFurniture
extends StaticBody2D

@export var block: Vector2i = Vector2i(1, 1):
	set(value):
		block = Vector2i(
			maxi(value.x, 1),
			maxi(value.y, 1)
		)

		if is_node_ready():
			update_shapes()

@onready var action_area: Area2D = $Area2D


func _ready() -> void:
	update_shapes()

	if Engine.is_editor_hint():
		return

	add_to_group("act_furniture")


func update_shapes() -> void:
	var body_size := Vector2(block) * 16.0

	var body_shape := RectangleShape2D.new()
	body_shape.size = body_size
	$CollisionShape2D.shape = body_shape

	var area_shape := RectangleShape2D.new()
	area_shape.size = body_size + Vector2(32.0, 32.0)
	$Area2D/CollisionShape2D.shape = area_shape


# 해당 캐릭터가 이 가구의 상호작용 범위 안에 있는지 확인
func can_interact(character: CharacterBody2D) -> bool:
	return action_area.overlaps_body(character)


# 자식 가구에서 재정의할 함수
func act() -> void:
	push_warning("자식 가구에서 act()를 구현해야 합니다.")


# 기존 씬에 연결된 신호를 유지하기 위한 함수
func _on_area_2d_area_entered(_area: Area2D) -> void:
	pass
