@tool
extends ActFurniture

@export var phone_screen: CanvasLayer


func act() -> void:
	if not is_instance_valid(phone_screen):
		push_warning("Phone Screen에 방의 Phone 노드를 지정하세요.")
		return

	phone_screen.call("open_phone")
