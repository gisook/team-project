extends Control

const ROOM_SCENE_PATH: String = "res://scenes/field/myroom.tscn"

func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file(ROOM_SCENE_PATH)


func _on_quit_button_pressed() -> void:
	pass # Replace with function body.
