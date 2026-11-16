extends Node2D

const LOADING_SCENE = "res://scenes/system/Loading.tscn"
const NEXT_SCENE = "res://scenes/field/myroom.tscn"

var is_transitioning: bool = false


func _on_button_pressed() -> void:
	if is_transitioning:
		return

	is_transitioning = true

	var target_scene: String = LOADING_SCENE

	# 전송할 녹음 데이터가 없으면 바로 다음 씬으로 이동
	if Record.session_records.is_empty():
		target_scene = NEXT_SCENE

	var err := get_tree().change_scene_to_file(target_scene)

	if err != OK:
		is_transitioning = false
		push_error("씬 전환 실패: %s / 오류: %s" % [target_scene, err])
