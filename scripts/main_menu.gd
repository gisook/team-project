extends Control

const ROOM_SCENE_PATH: String = "res://scenes/room.tscn"

func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file(ROOM_SCENE_PATH)
