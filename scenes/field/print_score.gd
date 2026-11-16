extends Control

const NEXT_SCENE: String = "res://scenes/field/myroom.tscn"

var evaluation_results: Array = []
var is_transitioning: bool = false

@onready var results_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/ScrollContainer/ResultsList
)

@onready var confirm_button: Button = (
	$MarginContainer/VBoxContainer/ConfirmButton
)

@onready var scroll_container: ScrollContainer = (
	$MarginContainer/VBoxContainer/ScrollContainer
)


func _ready() -> void:
	print("")
	print("========== [Score] 결과 씬 진입 ==========")

	# 결과 목록이 스크롤 영역의 가로 폭을 채우도록 합니다.
	results_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_list.add_theme_constant_override("separation", 16)

	# 스크롤 영역이 남는 세로 공간을 사용하도록 합니다.
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 같은 함수가 연결되어 있다면 중복 연결하지 않습니다.
	if not confirm_button.pressed.is_connected(
		_on_confirm_button_pressed
	):
		confirm_button.pressed.connect(
			_on_confirm_button_pressed
		)

	# Loading.gd에서 저장한 평가 결과를 가져옵니다.
	set_results(Record.evaluation_results)


func set_results(new_results: Array) -> void:
	evaluation_results = new_results.duplicate(true)

	print(
		"[Score] 평가 결과 개수: ",
		evaluation_results.size()
	)
	print(
		"[Score] 평가 결과 데이터: ",
		JSON.stringify(evaluation_results)
	)

	if is_node_ready():
		_show_results()


func _show_results() -> void:
	_clear_results_list()

	if evaluation_results.is_empty():
		_add_text(
			"발음 평가 결과가 없습니다.\n"
			+ "서버 연결 상태와 Loading 씬의 로그를 확인해주세요.",
			20
		)
		return

	_add_text(
		"총 %d개의 평가 결과" % evaluation_results.size(),
		22
	)

	for index in range(evaluation_results.size()):
		var entry_value: Variant = evaluation_results[index]

		if not (entry_value is Dictionary):
			_add_text(
				"%d. 결과 데이터 형식이 올바르지 않습니다."
				% [index + 1],
				18
			)
			continue

		var entry: Dictionary = entry_value
		var file_name: String = str(
			entry.get("file", "알 수 없는 파일")
		)

		var score_value: Variant = entry.get("result", null)

		# 평가 항목별로 묶어서 표시합니다.
		var item := VBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_theme_constant_override("separation", 8)

		results_list.add_child(item)

		_add_text_to(
			item,
			"%d. %s" % [index + 1, file_name],
			20
		)

		if score_value is Dictionary:
			var score: Dictionary = score_value

			var lines := PackedStringArray()

			lines.append(
				"정확도: %s"
				% _format_score(score.get("accuracy_score", null))
			)
			lines.append(
				"유창성: %s"
				% _format_score(score.get("fluency_score", null))
			)
			lines.append(
				"완전성: %s"
				% _format_score(score.get("completeness_score", null))
			)
			lines.append(
				"종합 점수: %s"
				% _format_score(score.get("pron_score", null))
			)

			_add_text_to(
				item,
				"\n".join(lines),
				18
			)
		else:
			_add_text_to(
				item,
				"점수 데이터를 찾을 수 없습니다.",
				18
			)

		# 항목 사이 구분선
		if index < evaluation_results.size() - 1:
			var separator := HSeparator.new()
			separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			results_list.add_child(separator)

	scroll_container.scroll_vertical = 0

	print("[Score] 결과 목록 표시 완료")


func _clear_results_list() -> void:
	# 씬에 미리 넣어둔 예시 항목이나 이전 결과를 제거합니다.
	for child in results_list.get_children():
		results_list.remove_child(child)
		child.queue_free()


func _add_text(
	value: String,
	font_size: int = 18
) -> void:
	_add_text_to(results_list, value, font_size)


func _add_text_to(
	parent: Node,
	value: String,
	font_size: int = 18
) -> void:
	var label := Label.new()

	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 파일명이 길어도 가로로 넘치지 않도록 줄바꿈합니다.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	label.add_theme_font_size_override(
		"font_size",
		font_size
	)

	parent.add_child(label)


func _format_score(value: Variant) -> String:
	if value == null:
		return "-"

	if value is float or value is int:
		return "%.1f" % float(value)

	return str(value)


func _on_confirm_button_pressed() -> void:
	if is_transitioning:
		return

	is_transitioning = true
	confirm_button.disabled = true

	var err := get_tree().change_scene_to_file(NEXT_SCENE)

	if err != OK:
		is_transitioning = false
		confirm_button.disabled = false

		push_error(
			"[Score] 다음 씬 전환 실패: %s / 오류: %s"
			% [NEXT_SCENE, err]
		)


# 기존 pressed 시그널이 이 이름으로 연결되어 있어도 동작합니다.
func _on_next_button_pressed() -> void:
	_on_confirm_button_pressed()
