extends Node
## 편의점 평가 콜백을 결과 데이터와 독립 화면에 연결합니다.

const Screen = preload("res://scenes/scores/print_score_scene.tscn")
const ScoreResult = preload("res://scripts/scores/score_result.gd")
var results: Array[Dictionary] = []
var screen: CanvasLayer
var auto_show := true
var pending_display := false


func _ready() -> void:
	screen = Screen.instantiate()
	add_child(screen)
	screen.close()


func _on_upload_started() -> void:
	results.clear()
	pending_display = false


func _on_one_request_done(res: Variant, file_name: String) -> void:
	var result: Variant = res.duplicate(true) if ScoreResult.is_valid(res) else null
	results.append({"file": file_name, "result": result})
	if result != null:
		print("[", file_name, "] 정확도: ", result["accuracy_score"],
			" / 유창성: ", result["fluency_score"], " / 완전성: ", result["completeness_score"],
			" / 종합: ", result["pron_score"])
	else:
		print("[", file_name, "] 평가 실패")


func _on_upload_finished(_success: bool, _text: String) -> void:
	pending_display = true
	if auto_show: show_results()


func show_results() -> void:
	pending_display = false
	screen.show_results(results)
