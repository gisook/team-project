extends Node2D

const DayState = preload("res://scripts/day_state.gd")
const DialogueCatalog = preload("res://scripts/dialogue_catalog.gd")
const ScorePresenter = preload("res://scripts/scores/score_presenter.gd")

var score_presenter: Node

signal choice_selected(index: int, text: String)

const SAVE_PATH := "user://dialogues.json"
const NEXT_DELAY := 1.5  # WAV 저장 결과 확인 후 다음 대화로 이동하기까지의 시간
const FINISH_DELAY := 2.5  # 업로드 결과 확인 후 자취방으로 복귀
const UPLOAD_QUEUE_PATH := "user://pending_recordings.json"
const RECORDINGS_DIR := "user://recordings"

@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var record_ui: VoiceRecordUI = $CanvasLayer/RecordUI
@onready var choice_ui: Control = $CanvasLayer/ChoiceUI
@onready var center_container: CenterContainer = $CanvasLayer/ChoiceUI/CenterContainer
@onready var main_box: VBoxContainer = $CanvasLayer/ChoiceUI/CenterContainer/VBoxContainer

var daily_mode: bool = false
var is_ending_schedule: bool = false
var skip_upload_button: Button
var manager_panel: PanelContainer
var period_selector: OptionButton
var schedule_start_checkbox: CheckBox

var dialogues: Array[Dictionary] = []
var next_id_number: int = 1
var current_dialogue_id: String = ""
var current_choices: Array[String] = []
var selected_index: int = -1
var turn_version: int = 0  # 이전 자동 이동 타이머를 무효화하는 번호

# 대화별 WAV는 각각 저장하며, 다음 대화가 없을 때 미전송 WAV를 일괄 처리합니다.
var session_id: String = ""
var recordings: Array[Dictionary] = []
var recording_context: Dictionary = {}
var is_uploading: bool = false
var upload_retry_needed: bool = false

var question_label: Label
var choices_container: VBoxContainer
var result_label: Label

var dialogue_selector: OptionButton
var add_button: Button
var edit_button: Button
var delete_button: Button
var retry_upload_button: Button

var editor_dialog: AcceptDialog
var delete_dialog: ConfirmationDialog
var notice_dialog: AcceptDialog
var title_edit: LineEdit
var question_edit: TextEdit
var choices_edit: TextEdit
var next_selector: OptionButton
var editing_dialogue_id: String = ""


func _ready() -> void:
	_setup_choice_ui()
	_setup_dialogue_manager()
	_setup_editor()
	DialogueCatalog.ensure_file()
	_load_dialogues()
	_load_pending_recordings()
	_refresh_dialogue_selector()
	var day_progress: Dictionary = DayState.load_state()
	var start_id: String = str(day_progress.get("active_dialogue_id", ""))
	daily_mode = str(day_progress.get("status", "room")) == "dialogue" and not start_id.is_empty()
	manager_panel.visible = not daily_mode
	if not daily_mode:
		var home_button := Button.new()
		home_button.text = "자취방으로 돌아가기"
		home_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		home_button.position = Vector2(-180, 14)
		home_button.custom_minimum_size = Vector2(165, 40)
		home_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(DayState.ROOM_SCENE))
		canvas_layer.add_child(home_button)

	record_ui.recording_saved.connect(_on_recording_saved)
	score_presenter = ScorePresenter.new()
	add_child(score_presenter)
	score_presenter.bind_uploader(record_ui)
	record_ui.file_uploaded.connect(_on_file_uploaded)
	record_ui.upload_progress.connect(_on_upload_progress)
	record_ui.upload_finished.connect(_on_upload_finished)
	record_ui.recording_failed.connect(_on_recording_failed)
	record_ui.recording_started.connect(_on_recording_started)
	record_ui.set_choice_ready(false)

	if daily_mode and _find_dialogue_index(start_id) != -1:
		_show_dialogue(start_id)
	elif not dialogues.is_empty():
		_show_dialogue(String(dialogues[0]["id"]))
	else:
		question_label.text = "저장된 대화가 없습니다. 왼쪽 위의 [추가]를 누르세요."
		result_label.text = ""

	if not recordings.is_empty():
		# 비정상 종료/연결 오류 이후에도 녹음한 WAV를 복구할 수 있습니다.
		result_label.text = "이전에 저장된 녹음 %d개가 복구되었습니다.\n대화를 이어 진행하거나 [미전송 녹음 전송]을 누르세요." % recordings.size()
		_show_upload_retry_button(true)


# ---------------- 대화 데이터(JSON) ----------------
func _load_dialogues() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_create_example_dialogues()
		_save_dialogues()
		return

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("대화 저장 파일을 열 수 없습니다: " + SAVE_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("대화 JSON 형식이 올바르지 않습니다: " + SAVE_PATH)
		return

	var source: Dictionary = parsed as Dictionary
	if not (source.get("dialogues", null) is Array):
		push_error("dialogues 목록이 없습니다: " + SAVE_PATH)
		return

	for item in source["dialogues"]:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item as Dictionary
		var id: String = str(d.get("id", "")).strip_edges()
		if id.is_empty() or _find_dialogue_index(id) != -1:
			continue
		var choices: Array[String] = []
		var raw_choices: Variant = d.get("choices", [])
		if raw_choices is Array:
			for choice in raw_choices:
				var value: String = str(choice).strip_edges()
				if not value.is_empty():
					choices.append(value)

		dialogues.append({
			"id": id,
			"title": str(d.get("title", id)),
			"question": str(d.get("question", "")),
			"choices": choices,
			"next_id": str(d.get("next_id", "")),
			"period": str(d.get("period", "morning")),
			"schedule_start": bool(d.get("schedule_start", true))
		})

		next_id_number = maxi(next_id_number, int(id.trim_prefix("dialogue_")) + 1)

	next_id_number = maxi(next_id_number, int(source.get("next_id_number", 1)))
	print("대화 %d개 로드 완료" % dialogues.size())


func _save_dialogues() -> void:
	DialogueCatalog.write_file(dialogues, next_id_number)


func _create_example_dialogues() -> void:
	dialogues = DialogueCatalog.default_dialogues()
	next_id_number = 13


func _find_dialogue_index(id: String) -> int:
	for i in range(dialogues.size()):
		if String(dialogues[i]["id"]) == id:
			return i
	return -1


func _make_new_id() -> String:
	var id: String = "dialogue_%d" % next_id_number
	while _find_dialogue_index(id) != -1:
		next_id_number += 1
		id = "dialogue_%d" % next_id_number
	next_id_number += 1
	return id


# ---------------- 화면 중앙: 대화 / 선택지 ----------------
func _setup_choice_ui() -> void:
	choice_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	choice_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_box.custom_minimum_size.x = 480
	main_box.add_theme_constant_override("separation", 20)

	question_label = main_box.get_node_or_null("QuestionLabel") as Label
	if question_label == null:
		question_label = Label.new()
		question_label.name = "QuestionLabel"
		main_box.add_child(question_label)

	choices_container = main_box.get_node_or_null("ChoicesContainer") as VBoxContainer
	if choices_container == null:
		choices_container = VBoxContainer.new()
		choices_container.name = "ChoicesContainer"
		main_box.add_child(choices_container)

	result_label = main_box.get_node_or_null("ResultLabel") as Label
	if result_label == null:
		result_label = Label.new()
		result_label.name = "ResultLabel"
		main_box.add_child(result_label)

	main_box.move_child(question_label, 0)
	main_box.move_child(choices_container, 1)
	main_box.move_child(result_label, 2)
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.custom_minimum_size.y = 50
	question_label.add_theme_font_size_override("font_size", 26)
	question_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices_container.add_theme_constant_override("separation", 12)
	choices_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _show_dialogue(id: String) -> void:
	var dialogue_index: int = _find_dialogue_index(id)
	if dialogue_index == -1:
		return

	turn_version += 1
	current_dialogue_id = id
	selected_index = -1
	var data: Dictionary = dialogues[dialogue_index]
	question_label.text = String(data["question"])
	result_label.text = ""
	current_choices.clear()
	for choice in data["choices"]:
		current_choices.append(String(choice))

	# 삭제 대기 노드를 재사용하지 않도록 부모에서 분리한 뒤 삭제합니다.
	for child in choices_container.get_children():
		choices_container.remove_child(child)
		child.queue_free()

	for i in range(current_choices.size()):
		var button := Button.new()
		button.text = current_choices[i]
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices_container.add_child(button)
		button.pressed.connect(_on_choice_pressed.bind(i))

	record_ui.set_choice_ready(false)
	_refresh_dialogue_selector()
	print("현재 대화: ", id)


func _on_choice_pressed(index: int) -> void:
	if selected_index != -1 or index < 0 or index >= current_choices.size():
		return

	selected_index = index
	for child in choices_container.get_children():
		if child is Button:
			child.disabled = true

	var text: String = current_choices[index]
	result_label.text = "선택: %s\n[녹음 시작] 버튼을 누르고 답변을 말하세요." % text
	recording_context = {
		"dialogue_id": current_dialogue_id,
		"dialogue_title": String(dialogues[_find_dialogue_index(current_dialogue_id)]["title"]),
		"choice_index": index,
		"choice_text": text
	}
	# 같은 대화를 반복해도 녹음이 덮어써지지 않도록 순서 번호를 부여합니다.
	var wav_path: String = "%s/%s/answer_%03d.wav" % [
		RECORDINGS_DIR, session_id, recordings.size() + 1
	]
	record_ui.set_save_path(wav_path)
	choice_selected.emit(index, text)
	record_ui.set_choice_ready(true)


# ---------------- 녹음 저장 / 마지막 대화에서 일괄 전송 ----------------
func _new_session_id() -> String:
	return "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]


# 각 WAV가 어느 대화/선택지에 해당하는지 같은 폴더의 manifest.json에 남깁니다.
func _save_session_manifest(finished: bool = false) -> void:
	if recordings.is_empty():
		return
	var folder: String = "%s/%s" % [RECORDINGS_DIR, session_id]
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(folder)
	)
	if mkdir_error != OK:
		push_error("녹음 메타데이터 폴더 생성 실패: %d" % mkdir_error)
		return
	var file: FileAccess = FileAccess.open(folder + "/manifest.json", FileAccess.WRITE)
	if file == null:
		push_error("녹음 메타데이터 저장 실패: " + folder)
		return
	file.store_string(JSON.stringify({
		"session_id": session_id,
		"finished": finished,
		"recordings": recordings
	}, "\t"))
	file.close()


# 업로드 대기 목록을 별도 JSON으로 저장합니다. WAV 파일은 전송 뒤에도 남습니다.
func _save_pending_recordings() -> void:
	if recordings.is_empty():
		if FileAccess.file_exists(UPLOAD_QUEUE_PATH):
			var remove_error: Error = DirAccess.remove_absolute(
				ProjectSettings.globalize_path(UPLOAD_QUEUE_PATH)
			)
			if remove_error != OK:
				push_warning("업로드 대기 목록 정리에 실패했습니다: %d" % remove_error)
		return

	var file: FileAccess = FileAccess.open(UPLOAD_QUEUE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("업로드 대기 목록 저장 실패: " + UPLOAD_QUEUE_PATH)
		return
	file.store_string(JSON.stringify({
		"session_id": session_id,
		"recordings": recordings
	}, "\t"))
	file.close()


func _load_pending_recordings() -> void:
	session_id = _new_session_id()
	if not FileAccess.file_exists(UPLOAD_QUEUE_PATH):
		return

	var file: FileAccess = FileAccess.open(UPLOAD_QUEUE_PATH, FileAccess.READ)
	if file == null:
		push_error("저장된 업로드 대기 목록을 열 수 없습니다.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("저장된 업로드 대기 목록의 JSON 형식이 잘못되었습니다.")
		return
	var data: Dictionary = parsed as Dictionary
	if not (data.get("recordings", null) is Array):
		return

	var saved_session: String = str(data.get("session_id", ""))
	if not saved_session.is_empty():
		session_id = saved_session
	for item in data["recordings"]:
		if item is Dictionary:
			var entry: Dictionary = item as Dictionary
			var path: String = str(entry.get("path", ""))
			if path.begins_with(RECORDINGS_DIR + "/") and FileAccess.file_exists(path):
				recordings.append(entry)
			else:
				push_warning("누락된 녹음 파일은 복구에서 제외합니다: " + path)
	_save_pending_recordings()


func _on_recording_started() -> void:
	_set_management_locked(true)
	result_label.text = "녹음 중입니다. 답변을 말한 뒤 [녹음 종료 및 저장]을 누르세요."


func _on_recording_saved(file_path: String) -> void:
	var entry: Dictionary = recording_context.duplicate(true)
	entry["path"] = file_path
	entry["uploaded"] = false
	recordings.append(entry)
	_save_session_manifest()
	_save_pending_recordings()
	recording_context.clear()
	_set_management_locked(false)

	var idx: int = _find_dialogue_index(current_dialogue_id)
	if idx == -1:
		result_label.text = "녹음은 저장되었지만 현재 대화를 찾을 수 없습니다."
		return

	var next_id: String = String(dialogues[idx].get("next_id", ""))
	if next_id.is_empty():
		is_ending_schedule = daily_mode
		result_label.text = "대화가 끝났습니다.\n누적된 %d개 WAV 파일을 서버로 전송합니다." % recordings.size()
		_start_batch_upload()
		return
	if _find_dialogue_index(next_id) == -1:
		result_label.text = "녹음 저장 완료: %s\n다음 대화가 존재하지 않습니다: %s\n대화 설정을 수정하세요." % [file_path, next_id]
		return

	result_label.text = "녹음 저장 완료 (%d개 누적)\n%.1f초 후 다음 대화로 자동 이동합니다." % [
		recordings.size(), NEXT_DELAY
	]
	_advance_after_delay(current_dialogue_id, next_id, turn_version)


func _on_recording_failed(message: String) -> void:
	_set_management_locked(false)
	result_label.text = "녹음 또는 저장 실패:\n%s\n[다시 녹음]을 눌러 재시도하세요." % message


func _get_unuploaded_recordings() -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for entry in recordings:
		if not bool(entry.get("uploaded", false)):
			pending.append(entry)
	return pending


func _start_batch_upload() -> void:
	if is_uploading:
		return

	var pending: Array[Dictionary] = _get_unuploaded_recordings()
	if pending.is_empty():
		# 이미 모든 파일의 서버 전송이 확인된 상태입니다.
		_finish_session("모든 녹음 파일의 전송이 완료되었습니다.")
		return

	is_uploading = true
	upload_retry_needed = false
	_show_upload_retry_button(false)
	_set_management_locked(true)
	result_label.text = "서버로 녹음 파일을 전송하고 있습니다... (0/%d)" % pending.size()
	if not record_ui.upload_recordings(pending):
		is_uploading = false
		upload_retry_needed = true
		_show_upload_retry_button(true)
		result_label.text = "전송을 시작할 수 없습니다. [미전송 녹음 전송]을 눌러 주세요."


func _on_file_uploaded(file_path: String, _response_text: String) -> void:
	for i in range(recordings.size()):
		if str(recordings[i].get("path", "")) == file_path:
			recordings[i]["uploaded"] = true
			break
	# 성공한 파일은 재시도/재실행 시 다시 보내지 않습니다.
	_save_session_manifest()
	_save_pending_recordings()


func _on_upload_progress(_completed_count: int, _total_count: int) -> void:
	var remaining: int = _get_unuploaded_recordings().size()
	result_label.text = "서버 업로드 중... %d/%d개 완료" % [
		recordings.size() - remaining, recordings.size()
	]


func _on_upload_finished(success: bool, response_text: String) -> void:
	is_uploading = false
	if not success:
		upload_retry_needed = true
		_show_upload_retry_button(true)
		# 미전송 상태를 유지하여 다시 보낼 수 있게 합니다.
		_set_management_locked(true)
		result_label.text = "서버 업로드 실패:\n%s\n\n남은 %d개 파일은 보관했습니다. 재시도하거나 전송을 나중에 할 수 있습니다." % [
			response_text, _get_unuploaded_recordings().size()
		]
		if daily_mode and is_ending_schedule:
			skip_upload_button.show()
		return

	var display_result: String = response_text.strip_edges()
	if display_result.is_empty():
		display_result = "서버가 빈 응답을 보냈습니다."
	_finish_session("총 %d개 녹음 파일 전송 완료.\n서버 응답:\n%s" % [
		recordings.size(), display_result.substr(0, 1200)
	])


func _finish_session(message: String) -> void:
	_save_session_manifest(true)
	recordings.clear()
	_save_pending_recordings()
	session_id = _new_session_id()
	upload_retry_needed = false
	_show_upload_retry_button(false)
	_set_management_locked(false)
	result_label.text = message
	if daily_mode and is_ending_schedule:
		_complete_daily_schedule(true)


func _complete_daily_schedule(show_result: bool = false) -> void:
	if not daily_mode or not is_ending_schedule:
		return
	is_ending_schedule = false
	if skip_upload_button != null:
		skip_upload_button.hide()
	if DayState.finish_schedule():
		if show_result:
			result_label.text += "\n%.1f초 뒤 자취방으로 돌아갑니다." % FINISH_DELAY
			_return_after_feedback()
		else:
			get_tree().change_scene_to_file(DayState.ROOM_SCENE)
	else:
		push_error("일정 진행 상태 저장 실패")


func _return_after_feedback() -> void:
	if score_presenter.screen.is_open:
		await score_presenter.screen.closed
	await get_tree().create_timer(FINISH_DELAY).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(DayState.ROOM_SCENE)


func _on_skip_upload_pressed() -> void:
	# pending_recordings.json에 보관된 WAV는 다음 일정에서 재전송 가능합니다.
	if is_uploading:
		return
	_complete_daily_schedule()


func _show_upload_retry_button(visible: bool) -> void:
	retry_upload_button.visible = visible
	retry_upload_button.disabled = not visible or is_uploading
	if visible:
		retry_upload_button.text = "미전송 녹음 전송 (%d개)" % _get_unuploaded_recordings().size()


func _on_retry_upload_pressed() -> void:
	_start_batch_upload()


func _advance_after_delay(from_id: String, next_id: String, expected_turn: int) -> void:
	await get_tree().create_timer(NEXT_DELAY).timeout
	# 대화를 직접 바꿨다면 예전 타이머를 무시합니다.
	if turn_version != expected_turn or current_dialogue_id != from_id:
		return
	if _find_dialogue_index(next_id) != -1:
		if daily_mode:
			DayState.set_active_dialogue(next_id)
		_show_dialogue(next_id)


# ---------------- 왼쪽 위 대화 관리 UI ----------------
func _setup_dialogue_manager() -> void:
	var panel := PanelContainer.new()
	manager_panel = panel
	panel.name = "DialogueManager"
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(280, 0)
	canvas_layer.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := Label.new()
	header.text = "대화 선택 / 관리"
	box.add_child(header)

	dialogue_selector = OptionButton.new()
	dialogue_selector.custom_minimum_size = Vector2(260, 36)
	dialogue_selector.allow_reselect = true
	dialogue_selector.item_selected.connect(_on_dialogue_selected)
	box.add_child(dialogue_selector)

	var actions := HBoxContainer.new()
	box.add_child(actions)
	add_button = Button.new()
	add_button.text = "추가"
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_button.pressed.connect(_on_add_pressed)
	actions.add_child(add_button)
	edit_button = Button.new()
	edit_button.text = "수정"
	edit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_button.pressed.connect(_on_edit_pressed)
	actions.add_child(edit_button)
	delete_button = Button.new()
	delete_button.text = "삭제"
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.pressed.connect(_on_delete_pressed)
	actions.add_child(delete_button)

	retry_upload_button = Button.new()
	retry_upload_button.text = "전송 재시도"
	retry_upload_button.visible = false
	retry_upload_button.pressed.connect(_on_retry_upload_pressed)
	box.add_child(retry_upload_button)

	# 서버가 중단되어도 WAV를 로컬에 유지한 채 다음 시간대로 진행할 수 있습니다.
	skip_upload_button = Button.new()
	skip_upload_button.text = "전송은 나중에 / 자취방으로 돌아가기"
	skip_upload_button.hide()
	skip_upload_button.pressed.connect(_on_skip_upload_pressed)
	canvas_layer.add_child(skip_upload_button)
	skip_upload_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skip_upload_button.position = Vector2(-170, -160)
	skip_upload_button.custom_minimum_size = Vector2(340, 44)
	skip_upload_button.size = Vector2(340, 44)


func _refresh_dialogue_selector() -> void:
	dialogue_selector.clear()
	var selected: int = -1
	for i in range(dialogues.size()):
		var d: Dictionary = dialogues[i]
		dialogue_selector.add_item(String(d["title"]))
		if String(d["id"]) == current_dialogue_id:
			selected = i
	if selected != -1:
		dialogue_selector.select(selected)
	elif not dialogues.is_empty():
		dialogue_selector.select(0)
	dialogue_selector.disabled = is_uploading or upload_retry_needed or dialogues.is_empty()
	add_button.disabled = is_uploading or upload_retry_needed
	edit_button.disabled = is_uploading or upload_retry_needed or dialogues.is_empty()
	delete_button.disabled = is_uploading or upload_retry_needed or dialogues.is_empty()


func _set_management_locked(locked: bool) -> void:
	var should_lock: bool = locked or is_uploading or upload_retry_needed
	dialogue_selector.disabled = should_lock or dialogues.is_empty()
	add_button.disabled = should_lock
	edit_button.disabled = should_lock or dialogues.is_empty()
	delete_button.disabled = should_lock or dialogues.is_empty()


func _on_dialogue_selected(index: int) -> void:
	if index >= 0 and index < dialogues.size():
		_show_dialogue(String(dialogues[index]["id"]))


# ---------------- 추가 / 수정 / 삭제 팝업 ----------------
func _setup_editor() -> void:
	editor_dialog = AcceptDialog.new()
	editor_dialog.title = "대화 편집"
	editor_dialog.ok_button_text = "저장"
	editor_dialog.dialog_hide_on_ok = false
	editor_dialog.confirmed.connect(_save_from_editor)
	canvas_layer.add_child(editor_dialog)

	var editor_box := VBoxContainer.new()
	editor_dialog.add_child(editor_box)
	editor_dialog.add_cancel_button("취소")
	var title_label := Label.new()
	title_label.text = "대화 이름"
	editor_box.add_child(title_label)
	title_edit = LineEdit.new()
	title_edit.placeholder_text = "예: 팀 프로젝트 회의"
	editor_box.add_child(title_edit)

	var question_label_edit := Label.new()
	question_label_edit.text = "상황 / 질문"
	editor_box.add_child(question_label_edit)
	question_edit = TextEdit.new()
	question_edit.custom_minimum_size = Vector2(520, 90)
	question_edit.placeholder_text = "팀원: 이번 주에는 어떤 일을 맡을 수 있어?"
	editor_box.add_child(question_edit)

	var choices_label := Label.new()
	choices_label.text = "답변 선택지 (한 줄에 하나씩)"
	editor_box.add_child(choices_label)
	choices_edit = TextEdit.new()
	choices_edit.custom_minimum_size = Vector2(520, 135)
	choices_edit.placeholder_text = "제가 화면을 개발할게요.\n저는 테스트를 담당할게요."
	editor_box.add_child(choices_edit)

	var period_label := Label.new()
	period_label.text = "일정을 표시할 시간대"
	editor_box.add_child(period_label)
	period_selector = OptionButton.new()
	period_selector.add_item("오전 일정")
	period_selector.add_item("오후 일정")
	editor_box.add_child(period_selector)
	schedule_start_checkbox = CheckBox.new()
	schedule_start_checkbox.text = "휴대폰 일정 목록에 표시 (일정의 첫 번째 대화)"
	schedule_start_checkbox.button_pressed = true
	editor_box.add_child(schedule_start_checkbox)

	var next_label := Label.new()
	next_label.text = "녹음 저장 후 다음 대화 (없음: 일정 종료 + 일괄 전송)"
	editor_box.add_child(next_label)
	next_selector = OptionButton.new()
	editor_box.add_child(next_selector)

	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "대화 삭제"
	delete_dialog.ok_button_text = "삭제"
	delete_dialog.confirmed.connect(_confirm_delete)
	canvas_layer.add_child(delete_dialog)

	notice_dialog = AcceptDialog.new()
	notice_dialog.title = "알림"
	canvas_layer.add_child(notice_dialog)


func _on_add_pressed() -> void:
	_open_editor("")


func _on_edit_pressed() -> void:
	if _find_dialogue_index(current_dialogue_id) != -1:
		_open_editor(current_dialogue_id)


func _open_editor(id: String) -> void:
	editing_dialogue_id = id
	var idx: int = _find_dialogue_index(id)
	title_edit.text = "" if idx == -1 else String(dialogues[idx]["title"])
	period_selector.select(1 if idx != -1 and str(dialogues[idx].get("period", "morning")) == "afternoon" else 0)
	schedule_start_checkbox.button_pressed = true if idx == -1 else bool(dialogues[idx].get("schedule_start", true))
	question_edit.text = "" if idx == -1 else String(dialogues[idx]["question"])
	choices_edit.text = ""
	if idx != -1:
		var choice_lines := PackedStringArray()
		for choice in dialogues[idx]["choices"]:
			choice_lines.append(str(choice))
		choices_edit.text = "\n".join(choice_lines)

	next_selector.clear()
	next_selector.add_item("없음 (대화 종료)")
	next_selector.set_item_metadata(0, "")
	var chosen_next_id := ""
	if idx != -1:
		chosen_next_id = String(dialogues[idx].get("next_id", ""))

	var selected_next_idx := 0
	for d in dialogues:
		var option_index: int = next_selector.item_count
		next_selector.add_item(String(d["title"]))
		next_selector.set_item_metadata(option_index, String(d["id"]))
		if String(d["id"]) == chosen_next_id:
			selected_next_idx = option_index
	next_selector.select(selected_next_idx)

	editor_dialog.title = "대화 추가" if id.is_empty() else "대화 수정"
	editor_dialog.popup_centered(Vector2i(580, 590))


func _save_from_editor() -> void:
	var title: String = title_edit.text.strip_edges()
	var question: String = question_edit.text.strip_edges()
	var choices: Array[String] = []
	for raw in choices_edit.text.split("\n", false):
		var choice: String = raw.strip_edges()
		if not choice.is_empty():
			choices.append(choice)

	if title.is_empty() or question.is_empty() or choices.is_empty():
		_show_notice("이름, 상황, 선택지를 각각 하나 이상 입력해야 합니다.")
		return

	var next_id: String = str(next_selector.get_selected_metadata())
	var period: String = "afternoon" if period_selector.selected == 1 else "morning"
	var idx: int = _find_dialogue_index(editing_dialogue_id)
	var is_schedule_start: bool = schedule_start_checkbox.button_pressed
	var new_id: String = editing_dialogue_id
	if idx == -1:
		new_id = _make_new_id()
		dialogues.append({
			"id": new_id,
			"title": title,
			"question": question,
			"choices": choices,
			"next_id": next_id,
			"period": period,
			"schedule_start": is_schedule_start
		})
	else:
		dialogues[idx] = {
			"id": new_id,
			"title": title,
			"question": question,
			"choices": choices,
			"next_id": next_id,
			"period": period,
			"schedule_start": is_schedule_start
		}

	_save_dialogues()
	editor_dialog.hide()
	_show_dialogue(new_id)


func _on_delete_pressed() -> void:
	var idx: int = _find_dialogue_index(current_dialogue_id)
	if idx == -1:
		return
	delete_dialog.dialog_text = "'%s' 대화를 삭제하시겠습니까?\n이 대화로 이동하도록 지정한 연결도 해제됩니다." % String(dialogues[idx]["title"])
	delete_dialog.popup_centered()


func _confirm_delete() -> void:
	var id: String = current_dialogue_id
	var idx: int = _find_dialogue_index(id)
	if idx == -1:
		return

	turn_version += 1
	dialogues.remove_at(idx)
	for i in range(dialogues.size()):
		if String(dialogues[i].get("next_id", "")) == id:
			dialogues[i]["next_id"] = ""

	_save_dialogues()
	current_dialogue_id = ""
	_refresh_dialogue_selector()
	if not dialogues.is_empty():
		_show_dialogue(String(dialogues[mini(idx, dialogues.size() - 1)]["id"]))
	else:
		for child in choices_container.get_children():
			choices_container.remove_child(child)
			child.queue_free()
		question_label.text = "저장된 대화가 없습니다. 왼쪽 위의 [추가]를 누르세요."
		result_label.text = ""
		record_ui.set_choice_ready(false)


func _show_notice(message: String) -> void:
	notice_dialog.dialog_text = message
	notice_dialog.popup_centered()
