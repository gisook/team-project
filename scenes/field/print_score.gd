extends Control
## 파일별 서버 평가 결과를 표시합니다. 서버 요청은 기존 씬에서 처리합니다.

static var _pending_results: Array = []

@onready var results_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ResultsList


static func set_results(values: Array) -> void:
	_pending_results = values.duplicate(true)


func _ready() -> void:
	show_results(_pending_results)
	_pending_results = []


func show_results(values: Array) -> void:
	for child in results_list.get_children():
		results_list.remove_child(child)
		child.queue_free()

	if values.is_empty():
		_add_label(results_list, "표시할 평가 결과가 없습니다.")
		return

	for entry in values:
		if not entry is Dictionary:
			continue

		var group := VBoxContainer.new()
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_theme_constant_override("separation", 8)
		results_list.add_child(group)

		var file_name := str(entry.get("file", "파일명 없음"))
		_add_label(group, file_name, 24)

		var result = entry.get("result")
		if not result is Dictionary:
			_add_label(group, "평가 실패")
			continue

		_add_label(group, "정확도: " + _score_text(result, "accuracy_score"))
		_add_label(group, "유창성: " + _score_text(result, "fluency_score"))
		_add_label(group, "완전성: " + _score_text(result, "completeness_score"))
		_add_label(group, "종합: " + _score_text(result, "pron_score"))


func _score_text(result: Dictionary, key: String) -> String:
	var value = result.get(key)
	return "값 없음" if value == null else str(value)


func _add_label(parent: Control, text: String, font_size: int = 20) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
