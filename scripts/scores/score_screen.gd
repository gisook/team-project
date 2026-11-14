extends CanvasLayer
## 독립 실행 가능한 결과 화면. 닫을 때 기존 게임 장면을 그대로 유지합니다.

signal closed

const Card = preload("res://scenes/scores/score_card.tscn")
var is_open := true


func show_results(results: Array[Dictionary]) -> void:
	for child in $Root/Margin/Content/Scroll/Cards.get_children():
		child.free()
	var success := 0
	for entry in results:
		var card := Card.instantiate()
		$Root/Margin/Content/Scroll/Cards.add_child(card)
		card.set_result(entry)
		if entry.get("result") != null: success += 1
	$Root/Margin/Content/Summary.text = "결과가 없습니다. 녹음을 전송하면 평가 결과가 표시됩니다." if results.is_empty() else "총 %d개 · 평가 완료 %d개 · 실패 %d개" % [results.size(), success, results.size() - success]
	$Root/Margin/Content/Scroll.scroll_vertical = 0
	is_open = true
	show()
	$Root/Margin/Content/Close.grab_focus()


func close() -> void:
	if not is_open: return
	is_open = false
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
