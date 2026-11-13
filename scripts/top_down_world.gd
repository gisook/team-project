extends Control

const DayState = preload("res://scripts/day_state.gd")
const MapView = preload("res://scripts/authored_map.gd")
const StoreDialogues = preload("res://scripts/store_dialogues.gd")
const RecordUI = preload("res://scripts/record_ui.gd")
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN]
const STEP_SECONDS := 0.16

var state: Dictionary
var map: Control
var player_cell := Vector2i.ZERO
var player_from := Vector2.ZERO
var step_time := 0.0
var step_active := false
var customers: Array[Dictionary] = []
var active_customer := -1
var selected_choice := -1
var conversation_finishing := false
var transition := false
var location := "room"
var pending: Array[Dictionary] = []
var recording_context: Dictionary = {}
var queue_path := ""
var heading: Label
var hint: Label
var feedback: Label
var phone: PanelContainer
var dialogue: PanelContainer
var choices: VBoxContainer
var response: Label
var bubble: PanelContainer
var bubble_text: Label
var fade: ColorRect
var retry_upload: Button
var retry_save: Button
var recorder: VoiceRecordUI
var uploader: VoiceRecordUI
var end_schedule_button: Button
var continue_button: Button
var result_panel: PanelContainer
var submission_label: Label
var score_label: Label
var score_note: Label
var retry_submission: Button
var submission_phase := "playing"
var submission_upload := false
var current_responses: Array[Dictionary] = []
var schedule_score: Variant = null


func _ready() -> void:
	state = DayState.load_state()
	queue_path = DayState._save_path().replace("day_progress_", "map_recordings_")
	_load_pending()
	map = MapView.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(map)
	_build_ui()
	if str(state["status"]) == "dialogue":
		# Existing saves may still be in a legacy dialogue schedule.
		get_tree().change_scene_to_file.call_deferred(DayState.GAME_SCENE)
		return
	_enter_location("store" if state["status"] == "store" else "room")
	resized.connect(_layout)
	_layout()


func _label(text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f1e7d5"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("243a43")
	style.border_color = Color("ac9277")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	return button


func _build_recorder(capture: bool) -> VoiceRecordUI:
	var ui := RecordUI.new()
	ui.capture_enabled = capture
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var button := Button.new()
	button.name = "RecordButton"
	button.custom_minimum_size = Vector2(260, 44)
	button.pressed.connect(ui._on_record_button_pressed)
	ui.add_child(button)
	var mic := AudioStreamPlayer.new()
	mic.name = "Microphone"
	ui.add_child(mic)
	var request := HTTPRequest.new()
	request.name = "HTTPRequest"
	ui.add_child(request)
	add_child(ui)
	return ui


func _build_ui() -> void:
	heading = _label("", 23)
	add_child(heading)
	hint = _label("", 17)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	feedback = _label("", 16)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(feedback)
	retry_upload = _button("미전송 녹음 전송", _upload_pending)
	add_child(retry_upload)
	phone = _panel()
	phone.size = Vector2(440, 300)
	add_child(phone)
	var phone_box := VBoxContainer.new()
	phone_box.add_theme_constant_override("separation", 18)
	phone.add_child(phone_box)
	phone_box.add_child(_label("오늘의 일정", 27))
	phone_box.add_child(_label("편의점에서 손님 세 분을 응대해 보세요."))
	phone_box.add_child(_button("편의점 알바 · 출근하기", _start_shift))
	phone_box.add_child(_button("휴대폰 닫기 · Esc", func() -> void: phone.hide()))
	phone.hide()
	bubble = _panel()
	bubble.size = Vector2(490, 120)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bubble)
	bubble_text = _label("", 19)
	bubble_text.custom_minimum_size.x = 454
	bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(bubble_text)
	bubble.hide()
	dialogue = _panel()
	dialogue.size = Vector2(780, 300)
	add_child(dialogue)
	var dialogue_box := VBoxContainer.new()
	dialogue_box.add_theme_constant_override("separation", 12)
	dialogue.add_child(dialogue_box)
	dialogue_box.add_child(_label("어떻게 말씀드릴까요?", 21))
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	dialogue_box.add_child(choices)
	response = _label("")
	response.custom_minimum_size.x = 720
	response.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_box.add_child(response)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 48
	dialogue_box.add_child(spacer)
	dialogue.hide()
	recorder = _build_recorder(true)
	recorder.recording_saved.connect(_on_recorded)
	recorder.recording_started.connect(func() -> void: response.text = "녹음 중 · 답변을 말하고 종료 버튼을 누르세요.")
	recorder.recording_failed.connect(func(message: String) -> void: response.text = message)
	uploader = _build_recorder(false)
	uploader.file_uploaded.connect(_on_uploaded)
	uploader.upload_finished.connect(_on_upload_finished)
	uploader.upload_progress.connect(_on_submission_progress)
	retry_save = _button("저장 다시 시도", _retry_progress_save)
	add_child(retry_save)
	retry_save.hide()
	_build_schedule_ui()
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade)


func _build_schedule_ui() -> void:
	end_schedule_button = _button("일정 종료", _finish_shift)
	add_child(end_schedule_button)
	continue_button = _button("넘어가기", _on_continue_pressed)
	add_child(continue_button)
	result_panel = _panel()
	result_panel.size = Vector2(620, 330)
	add_child(result_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	result_panel.add_child(box)
	box.add_child(_label("일정 결과", 28))
	submission_label = _label("")
	submission_label.custom_minimum_size.x = 560
	submission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(submission_label)
	score_label = _label("점수: —", 42)
	box.add_child(score_label)
	score_note = _label("서버 응답을 기다리고 있습니다.", 16)
	score_note.custom_minimum_size.x = 560
	score_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(score_note)
	retry_submission = _button("전송 재시도", _finish_shift)
	box.add_child(retry_submission)
	result_panel.hide()


func _layout() -> void:
	if heading == null: return
	heading.position = Vector2(24, 16)
	hint.position = Vector2(12, size.y - 44)
	hint.size = Vector2(size.x - 24, 42)
	feedback.position = Vector2(24, 52)
	feedback.size = Vector2(size.x - 250, 45)
	retry_upload.position = Vector2(size.x - 212, 16)
	retry_upload.size = Vector2(190, 40)
	phone.position = Vector2((size.x - 440) * 0.5, maxf(95, (size.y - 330) * 0.5))
	phone.size = Vector2(440, 300)
	dialogue.position = Vector2(maxf(16, (size.x - 780) * 0.5), size.y * 0.51)
	dialogue.size = Vector2(minf(size.x - 32, 780), size.y * 0.49 - 48)
	recorder.record_button.position = Vector2(size.x * 0.5 - 130, size.y - 108)
	recorder.record_button.size = Vector2(260, 44)
	retry_save.position = Vector2(size.x * 0.5 - 120, size.y - 108)
	retry_save.size = Vector2(240, 44)
	end_schedule_button.position = Vector2(size.x - 320, 16)
	end_schedule_button.size = Vector2(145, 44)
	continue_button.position = Vector2(size.x - 164, 16)
	continue_button.size = Vector2(140, 44)
	result_panel.position = Vector2((size.x - 620) * 0.5, maxf(106, (size.y - 330) * 0.5))
	result_panel.size = Vector2(620, 330)
	_layout_bubble()


func _layout_bubble() -> void:
	if active_customer < 0: return
	var head: Vector2 = map.screen_point(customers[active_customer]["visual"]) - Vector2(0, 70 * map.map_scale())
	var width := minf(490, size.x - 36)
	bubble_text.custom_minimum_size.x = width - 36
	bubble.size = Vector2(width, 110)
	bubble.position = Vector2(clampf(head.x - width * 0.5, 18, size.x - width - 18), maxf(90, head.y - bubble.size.y - 12))


func _enter_location(next: String) -> void:
	location = next
	state = DayState.load_state()
	map.location = location
	if not map.load_location(location):
		transition = true
		feedback.text = "맵 설정 오류: " + "; ".join(map.layout_errors)
		hint.text = "맵 장면의 기능 표시점을 확인해 주세요."
		return
	map.period = str(state["period"])
	map.focused_customer = -1
	map.sleeping = false
	active_customer = -1
	step_active = false
	map.moving = false
	result_panel.hide()
	submission_phase = "playing"
	current_responses.clear()
	schedule_score = null
	customers.clear()
	if location == "store":
		player_cell = map.layout.cell("player_spawn")
		var completed: Array = state.get("customers_done", [])
		var data: Array[Dictionary] = StoreDialogues.customers(int(state["day"]), str(state["period"]))
		for i in range(data.size()):
			var c: Dictionary = data[i]
			c["target"] = map.layout.cell("npc_target", StringName(c["id"]))
			c["done"] = c["id"] in completed
			c["cell"] = c["target"] if c["done"] else map.layout.cell("npc_spawn", StringName(c["id"]))
			c["visual"] = Vector2(c["cell"])
			c["moving"] = false
			c["facing"] = 1
			customers.append(c)
	else:
		player_cell = map.layout.cell("player_spawn")
	map.player = Vector2(player_cell)
	map.customers = customers
	_update_hud()
	if location == "store":
		_restore_submission()


func _update_hud() -> void:
	var titles := {"morning": "오전", "afternoon": "오후", "night": "밤"}
	heading.text = "%d일 차 · %s  |  %s" % [int(state["day"]), titles[state["period"]], "내 방" if location == "room" else "편의점 알바 · %d/3명 응대" % _completed_count()]
	retry_upload.visible = location == "room" and not pending.is_empty() and active_customer < 0
	retry_upload.disabled = uploader.state == VoiceRecordUI.RecordState.UPLOADING
	_update_schedule_buttons()


func _capture_busy() -> bool:
	return recorder.state in [VoiceRecordUI.RecordState.RECORDING, VoiceRecordUI.RecordState.SAVING]


func _update_schedule_buttons() -> void:
	var in_store := location == "store"
	var uploading := uploader.state == VoiceRecordUI.RecordState.UPLOADING or submission_phase == "uploading"
	end_schedule_button.visible = in_store
	continue_button.visible = in_store
	end_schedule_button.disabled = not _all_done() or active_customer >= 0 or uploading or submission_phase == "result" or retry_save.visible or transition
	end_schedule_button.text = "전송 재시도" if submission_phase == "failed" else "일정 종료"
	continue_button.disabled = uploading or _capture_busy() or retry_save.visible or transition
	retry_submission.visible = submission_phase == "failed"
	retry_submission.disabled = uploading or transition


func _process(delta: float) -> void:
	if transition: return
	_update_schedule_buttons()
	if result_panel.visible: return
	if active_customer >= 0:
		_layout_bubble()
		return
	if phone.visible: return
	_update_movement(delta)
	_move_customers(delta)
	var target := _interaction_target()
	map.highlighted_customer = int(target.get_slice(":", 1)) if target.begins_with("npc:") else -1
	if target == "phone":
		hint.text = "E · 휴대폰으로 %s 일정 선택" % ("오전" if state["period"] == "morning" else "오후")
	elif target == "bed": hint.text = "E · 침대에 누워 다음 날까지 자기"
	elif target.begins_with("npc:"):
		hint.text = "E · %s 응대하기" % customers[int(target.get_slice(":", 1))]["name"]
	else:
		hint.text = "W A S D · 이동   |   %s" % ("밤에는 침대 근처에서 E · 취침" if state["period"] == "night" else ("책상 위 휴대폰 근처에서 E · 일정 선택" if location == "room" else "손님 가까이에서 E · 대화 / 계산대는 계산원 자리에서 응대"))


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or transition: return
	if event.physical_keycode == KEY_ESCAPE:
		if phone.visible: phone.hide()
		elif active_customer >= 0 and selected_choice == -1: _close_dialogue()
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_E and active_customer == -1 and not phone.visible and not result_panel.visible and not step_active:
		var target := _interaction_target()
		if target == "phone": phone.show()
		elif target == "bed": _sleep()
		elif target.begins_with("npc:"): _start_dialogue(int(target.get_slice(":", 1)))
		get_viewport().set_input_as_handled()


func _update_movement(delta: float) -> void:
	if step_active:
		step_time = minf(STEP_SECONDS, step_time + delta)
		map.player = player_from.lerp(Vector2(player_cell), step_time / STEP_SECONDS)
		if step_time < STEP_SECONDS: return
		step_active = false
		map.moving = false
	var dir := Vector2i.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir = Vector2i.UP
	elif Input.is_physical_key_pressed(KEY_S): dir = Vector2i.DOWN
	elif Input.is_physical_key_pressed(KEY_A): dir = Vector2i.LEFT
	elif Input.is_physical_key_pressed(KEY_D): dir = Vector2i.RIGHT
	if dir == Vector2i.ZERO: return
	map.facing = DIRECTIONS.find(dir)
	var next := player_cell + dir
	if _blocked(next) or _occupied(next): return
	player_from = Vector2(player_cell)
	player_cell = next
	step_time = 0
	step_active = true
	map.moving = true


func _blocked(cell: Vector2i) -> bool:
	return map.is_blocked(cell)


func _occupied(cell: Vector2i, except_index: int = -1) -> bool:
	for i in range(customers.size()):
		if i == except_index: continue
		if customers[i]["cell"] == cell: return true
		if customers[i]["moving"] and Vector2i(customers[i]["from"]) == cell: return true
	return false


func _move_customers(delta: float) -> void:
	for i in range(customers.size()):
		var c: Dictionary = customers[i]
		if c["moving"]:
			c["time"] = minf(0.30, float(c["time"]) + delta)
			c["visual"] = Vector2(c["from"]).lerp(Vector2(c["cell"]), float(c["time"]) / 0.30)
			if float(c["time"]) >= 0.30: c["moving"] = false
			continue
		if c["cell"] == c["target"] or c["done"]: continue
		var next := _path_step(c["cell"], c["target"], i)
		if next == c["cell"]: continue
		c["facing"] = DIRECTIONS.find(next - Vector2i(c["cell"]))
		c["from"] = c["cell"]
		c["cell"] = next
		c["time"] = 0.0
		c["moving"] = true


func _path_step(start: Vector2i, target: Vector2i, index: int) -> Vector2i:
	var frontier: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var cursor := 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		if current == target:
			while previous[current] != start: current = previous[current]
			return current
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if previous.has(next) or _blocked(next) or _occupied(next, index) or next == player_cell or (step_active and next == Vector2i(player_from)): continue
			previous[next] = current
			frontier.append(next)
	return start


func _interaction_target() -> String:
	if location == "room":
		if state["period"] == "night" and map.layout.near("bed", player_cell): return "bed"
		if state["period"] != "night" and map.layout.near("phone", player_cell): return "phone"
	else:
		for i in range(customers.size()):
			var c: Dictionary = customers[i]
			if c["done"] or c["moving"] or c["cell"] != c["target"]: continue
			if c["id"] == "counter":
				if map.layout.near("cashier", player_cell, &"counter"): return "npc:%d" % i
			else:
				if map.layout.near("npc_target", player_cell, StringName(c["id"])): return "npc:%d" % i
	return ""


func _start_shift() -> void:
	if not DayState.start_store_shift():
		feedback.text = "일정을 저장하지 못했습니다. 다시 출근 버튼을 눌러 주세요."
		return
	phone.hide()
	_change_location("store")


func _change_location(next: String) -> void:
	transition = true
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.25)
	await tween.finished
	_enter_location(next)
	var reveal := create_tween()
	reveal.tween_property(fade, "color:a", 0.0, 0.3)
	await reveal.finished
	transition = not map.layout_errors.is_empty()
	_update_schedule_buttons()


func _start_dialogue(index: int) -> void:
	active_customer = index
	selected_choice = -1
	conversation_finishing = false
	map.focused_customer = index
	map.moving = false
	bubble_text.text = "%s\n%s" % [customers[index]["name"], customers[index]["question"]]
	bubble.show()
	dialogue.show()
	response.text = "답변을 선택한 뒤 녹음해 주세요.  ·  Esc: 대화 닫기"
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	var lines: Array = customers[index]["choices"]
	for i in range(lines.size()):
		var button := _button(str(lines[i]), _choose.bind(i))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choices.add_child(button)
	recorder.set_choice_ready(false)
	hint.text = "선택한 문장을 직접 말해 보세요. 녹음을 저장하면 응대가 완료됩니다."
	_update_hud()
	_layout()


func _choose(index: int) -> void:
	if selected_choice >= 0: return
	selected_choice = index
	for child in choices.get_children(): child.disabled = true
	var c: Dictionary = customers[active_customer]
	var path := "user://recordings/%s/%s_%d.wav" % [state["shift_id"], c["id"], Time.get_ticks_usec()]
	recording_context = {"dialogue_id": "store_" + str(c["id"]), "dialogue_title": str(c["name"]) + " 응대", "choice_index": index, "choice_text": c["choices"][index], "day": state["day"], "period": state["period"], "shift_id": state["shift_id"]}
	recorder.set_save_path(path)
	recorder.set_choice_ready(true)
	response.text = "선택: %s\n[녹음 시작]을 누르고 답변을 말하세요." % c["choices"][index]


func _on_recorded(path: String) -> void:
	if active_customer < 0 or conversation_finishing: return
	var entry := recording_context.duplicate(true)
	entry["path"] = path
	entry["uploaded"] = false
	pending.append(entry)
	_retry_progress_save()


func _retry_progress_save() -> void:
	if not _save_pending():
		response.text = "음성은 저장했지만 목록 저장에 실패했습니다. [저장 다시 시도]를 눌러 주세요."
		retry_save.show()
		return
	if active_customer >= 0:
		if not DayState.complete_customer(str(customers[active_customer]["id"])):
			response.text = "진행 저장에 실패했습니다. [저장 다시 시도]를 눌러 주세요."
			retry_save.show()
			return
		retry_save.hide()
		_finish_conversation()
	elif location == "store" and _all_done():
		retry_save.hide()
		_on_shift_ready()


func _finish_conversation() -> void:
	conversation_finishing = true
	var expected_shift: String = state.get("shift_id", "")
	var expected_customer := active_customer
	customers[active_customer]["done"] = true
	bubble_text.text = "%s\n%s" % [customers[active_customer]["name"], customers[active_customer]["reply"]]
	response.text = "녹음 저장 완료 · 응대를 마쳤습니다."
	await get_tree().create_timer(1.6).timeout
	if location != "store" or state.get("shift_id", "") != expected_shift or active_customer != expected_customer:
		return
	_close_dialogue()
	if _all_done(): _on_shift_ready()


func _close_dialogue() -> void:
	active_customer = -1
	map.focused_customer = -1
	conversation_finishing = false
	bubble.hide()
	dialogue.hide()
	recorder.set_choice_ready(false)
	_update_hud()


func _completed_count() -> int:
	var count := 0
	for c in customers:
		if c["done"]: count += 1
	return count


func _all_done() -> bool:
	return customers.size() == 3 and _completed_count() == 3


func _on_shift_ready() -> void:
	if submission_phase == "playing": submission_phase = "ready"
	feedback.text = "모든 응대를 마쳤습니다. [일정 종료]를 눌러 녹음을 전송하세요."
	hint.text = "일정 종료 · 서버 전송 및 결과 확인   |   넘어가기 · 자취방으로 귀가"
	_update_hud()


func _restore_submission() -> void:
	var saved: Dictionary = state.get("store_result", {})
	var responses: Variant = saved.get("responses", [])
	if responses is Array:
		for entry in responses:
			if entry is Dictionary: current_responses.append(entry)
	schedule_score = saved.get("score")
	if _all_done():
		if saved.get("received", false): _show_schedule_result()
		else: _on_shift_ready()


func _persist_submission(received: bool) -> bool:
	return DayState.save_store_result({"received": received, "responses": current_responses, "score": schedule_score})


func _current_shift_pending() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in pending:
		if entry.get("shift_id", "") == state.get("shift_id", ""):
			entries.append(entry)
	return entries


func _send_recordings(entries: Array[Dictionary]) -> bool:
	return uploader.upload_recordings(entries)


func _finish_shift() -> void:
	if location != "store" or not _all_done() or active_customer >= 0 or transition or retry_save.visible:
		return
	if submission_phase in ["uploading", "result"] or uploader.state == VoiceRecordUI.RecordState.UPLOADING:
		return
	var entries := _current_shift_pending()
	result_panel.show()
	if entries.is_empty():
		if current_responses.size() == customers.size():
			if _persist_submission(true): _show_schedule_result()
			else: _submission_failed("응답 결과 저장에 실패했습니다. 다시 시도해 주세요.")
		else:
			_submission_failed("이번 일정에서 전송할 녹음을 찾지 못했습니다. [넘어가기]로 귀가할 수 있습니다.")
		return
	submission_phase = "uploading"
	submission_upload = true
	submission_label.text = "녹음을 메인 서버로 전송하고 응답을 기다리고 있습니다."
	score_label.text = "점수: —"
	score_note.text = "응답을 받을 때까지 잠시 기다려 주세요."
	feedback.text = "파일 전송 및 서버 응답 대기 중…"
	_update_schedule_buttons()
	if not _send_recordings(entries):
		submission_upload = false
		_submission_failed("전송을 시작하지 못했습니다. 잠시 후 다시 시도해 주세요.")


func _on_submission_progress(completed: int, total: int) -> void:
	if submission_upload:
		submission_label.text = "녹음 %d/%d개 전송 및 응답 확인 완료" % [completed, total]


func _submission_failed(message: String) -> void:
	submission_phase = "failed"
	result_panel.show()
	submission_label.text = message
	score_label.text = "점수: —"
	score_note.text = "미전송 파일은 보관 중입니다. 전송을 재시도하거나 [넘어가기]로 귀가할 수 있습니다."
	feedback.text = "서버 응답을 확인하지 못했습니다."
	_update_schedule_buttons()


func _show_schedule_result() -> void:
	submission_phase = "result"
	result_panel.show()
	submission_label.text = "모든 녹음에 대한 서버 응답을 받았습니다."
	if schedule_score is int or schedule_score is float:
		score_label.text = "점수: %s점" % str(schedule_score)
		score_note.text = "결과 확인 후 [넘어가기]를 누르면 자취방으로 돌아갑니다."
	else:
		score_label.text = "점수: 0점"
		score_note.text = "임시 표시 · 서버 응답 기반 점수 연동 전입니다.\n[넘어가기]를 누르면 자취방으로 돌아갑니다."
	feedback.text = "일정 결과를 확인해 주세요."
	_update_schedule_buttons()


# Future response parsing can call this without changing the score screen.
func set_schedule_score(value: float) -> bool:
	if location != "store" or submission_phase != "result" or not is_finite(value): return false
	schedule_score = value
	var saved := _persist_submission(true)
	_show_schedule_result()
	if not saved: feedback.text = "점수는 표시했지만 저장하지 못했습니다."
	return saved


func _on_continue_pressed() -> void:
	if location != "store" or transition or _capture_busy() or retry_save.visible:
		return
	if submission_phase == "uploading" or uploader.state == VoiceRecordUI.RecordState.UPLOADING:
		return
	var saved := DayState.finish_schedule() if submission_phase == "result" else DayState.skip_store_schedule()
	if not saved:
		feedback.text = "귀가 상태를 저장하지 못했습니다. [넘어가기]를 다시 눌러 주세요."
		return
	_close_dialogue()
	result_panel.hide()
	feedback.text = "자취방으로 돌아왔습니다."
	_change_location("room")


func _sleep() -> void:
	transition = true
	map.sleeping = true
	map.player = map.layout.sleep_cell()
	hint.text = "침대에 누웠습니다. 푹 쉬세요…"
	await get_tree().create_timer(0.7).timeout
	var darken := create_tween()
	darken.tween_property(fade, "color:a", 1.0, 0.65)
	await darken.finished
	await get_tree().create_timer(0.65).timeout
	if not DayState.sleep_and_save(): feedback.text = "취침 저장에 실패했습니다. 침대에서 다시 시도해 주세요."
	_enter_location("room")
	var dawn := create_tween()
	dawn.tween_property(fade, "color:a", 0.0, 0.65)
	await dawn.finished
	transition = not map.layout_errors.is_empty()


func _load_pending() -> void:
	if not FileAccess.file_exists(queue_path): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(queue_path))
	if parsed is Dictionary and parsed.get("recordings") is Array:
		for entry in parsed["recordings"]:
			if entry is Dictionary and not entry.get("uploaded", false): pending.append(entry)


func _save_pending() -> bool:
	var file := FileAccess.open(queue_path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"recordings": pending}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	return DirAccess.rename_absolute(queue_path + ".tmp", queue_path) == OK


func _upload_pending() -> void:
	if pending.is_empty() or uploader.state == VoiceRecordUI.RecordState.UPLOADING: return
	if uploader.upload_recordings(pending):
		feedback.text = "저장된 녹음을 전송 중입니다. 이동과 일정 진행을 계속할 수 있습니다."
	_update_hud()


func _on_uploaded(path: String, _response_text: String) -> void:
	for i in range(pending.size() - 1, -1, -1):
		if pending[i].get("path") == path: pending.remove_at(i)
	if not _save_pending(): feedback.text = "전송은 완료했지만 전송 목록을 저장하지 못했습니다."
	if submission_upload:
		var exists := false
		for entry in current_responses:
			if entry.get("path") == path: exists = true
		if not exists: current_responses.append({"path": path, "response": _response_text})
		if not _persist_submission(false): feedback.text = "서버 응답을 저장하지 못했습니다."


func _on_upload_finished(success: bool, _text: String) -> void:
	if submission_upload:
		submission_upload = false
		if success:
			if _persist_submission(true): _show_schedule_result()
			else: _submission_failed("서버 응답은 받았지만 결과 저장에 실패했습니다. 전송 재시도로 저장을 다시 시도해 주세요.")
		else:
			_submission_failed("서버 연결 또는 응답 확인에 실패했습니다.")
		return
	feedback.text = "녹음 전송 완료" if success else "서버 연결 실패 · 녹음은 보관 중입니다. [미전송 녹음 전송]으로 재시도할 수 있습니다."
	_update_hud()
