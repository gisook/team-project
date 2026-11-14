extends Control

const DayState = preload("res://scripts/day_state.gd")
const MapView = preload("res://scripts/authored_map.gd")
const StoreDialogues = preload("res://scripts/store_dialogues.gd")
const RecordUI = preload("res://scripts/record_ui.gd")
const ScorePresenter = preload("res://scripts/scores/score_presenter.gd")
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN]
const BED := Rect2i(2, 2, 3, 3)
const ROOM_SPAWN := Vector2i(5, 3)
const CASHIER_SPOT := Vector2i(1, 1)
const CUSTOMER_SPAWNS := [Vector2i(1, 13), Vector2i(5, 13), Vector2i(10, 13)]
const STEP_SECONDS := 0.16

var state: Dictionary
var map: Control
var player_cell := ROOM_SPAWN
var player_from := Vector2(ROOM_SPAWN)
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
var score_presenter: Node
var score_button: Button


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
	score_presenter = ScorePresenter.new()
	score_presenter.auto_show = false
	add_child(score_presenter)
	score_presenter.bind_uploader(uploader)
	score_button = _button("평가 결과 보기", score_presenter.show_results)
	add_child(score_button)
	uploader.file_uploaded.connect(_on_uploaded)
	uploader.upload_finished.connect(_on_upload_finished)
	retry_save = _button("저장 다시 시도", _retry_progress_save)
	add_child(retry_save)
	retry_save.hide()
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade)


func _layout() -> void:
	if heading == null: return
	heading.position = Vector2(24, 16)
	hint.position = Vector2(12, size.y - 44)
	hint.size = Vector2(size.x - 24, 42)
	feedback.position = Vector2(24, 52)
	feedback.size = Vector2(size.x - 250, 45)
	retry_upload.position = Vector2(size.x - 212, 16)
	retry_upload.size = Vector2(190, 40)
	score_button.position = Vector2(size.x - 212, 64)
	score_button.size = Vector2(190, 40)
	phone.position = Vector2((size.x - 440) * 0.5, maxf(95, (size.y - 330) * 0.5))
	phone.size = Vector2(440, 300)
	dialogue.position = Vector2(maxf(16, (size.x - 780) * 0.5), size.y * 0.51)
	dialogue.size = Vector2(minf(size.x - 32, 780), size.y * 0.49 - 48)
	recorder.record_button.position = Vector2(size.x * 0.5 - 130, size.y - 108)
	recorder.record_button.size = Vector2(260, 44)
	retry_save.position = Vector2(size.x * 0.5 - 120, size.y - 108)
	retry_save.size = Vector2(240, 44)
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
	map.load_location(location)
	map.period = str(state["period"])
	map.focused_customer = -1
	map.sleeping = false
	active_customer = -1
	step_active = false
	map.moving = false
	customers.clear()
	if location == "store":
		player_cell = CASHIER_SPOT
		var completed: Array = state.get("customers_done", [])
		var data: Array[Dictionary] = StoreDialogues.customers(int(state["day"]), str(state["period"]))
		for i in range(data.size()):
			var c: Dictionary = data[i]
			c["done"] = c["id"] in completed
			c["cell"] = c["target"] if c["done"] else CUSTOMER_SPAWNS[i]
			c["visual"] = Vector2(c["cell"])
			c["moving"] = false
			c["facing"] = 1
			customers.append(c)
	else:
		player_cell = ROOM_SPAWN
	map.player = Vector2(player_cell)
	map.customers = customers
	_update_hud()
	if location == "store" and _all_done(): _finish_shift.call_deferred()


func _update_hud() -> void:
	var titles := {"morning": "오전", "afternoon": "오후", "night": "밤"}
	heading.text = "%d일 차 · %s  |  %s" % [int(state["day"]), titles[state["period"]], "내 방" if location == "room" else "편의점 알바 · %d/3명 응대" % _completed_count()]
	retry_upload.visible = not pending.is_empty() and active_customer < 0
	retry_upload.disabled = uploader.state == VoiceRecordUI.RecordState.UPLOADING


func _process(delta: float) -> void:
	if score_presenter.screen.is_open: return
	if score_presenter.pending_display and active_customer < 0 and not transition:
		score_presenter.show_results()
		return
	if transition: return
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
	if score_presenter.screen.is_open: return
	if not (event is InputEventKey) or not event.pressed or event.echo or transition: return
	if event.physical_keycode == KEY_ESCAPE:
		if phone.visible: phone.hide()
		elif active_customer >= 0 and selected_choice == -1: _close_dialogue()
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_E and active_customer == -1 and not phone.visible and not step_active:
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


func _near_rect(rect: Rect2i) -> bool:
	var nearest := Vector2i(clampi(player_cell.x, rect.position.x, rect.end.x - 1), clampi(player_cell.y, rect.position.y, rect.end.y - 1))
	var diff := nearest - player_cell
	return absi(diff.x) + absi(diff.y) <= 1


func _interaction_target() -> String:
	if location == "room":
		if state["period"] == "night" and _near_rect(BED): return "bed"
		if state["period"] != "night" and _near_rect(Rect2i(11, 3, 1, 1)): return "phone"
	else:
		for i in range(customers.size()):
			var c: Dictionary = customers[i]
			if c["done"] or c["moving"] or c["cell"] != c["target"]: continue
			if c["id"] == "counter":
				if player_cell == CASHIER_SPOT: return "npc:%d" % i
			else:
				var diff: Vector2i = c["cell"] - player_cell
				if absi(diff.x) + absi(diff.y) == 1: return "npc:%d" % i
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
	transition = false


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
		_finish_shift()


func _finish_conversation() -> void:
	conversation_finishing = true
	customers[active_customer]["done"] = true
	bubble_text.text = "%s\n%s" % [customers[active_customer]["name"], customers[active_customer]["reply"]]
	response.text = "녹음 저장 완료 · 응대를 마쳤습니다."
	await get_tree().create_timer(1.6).timeout
	_close_dialogue()
	if _all_done(): _finish_shift()


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


func _finish_shift() -> void:
	if not DayState.finish_schedule():
		feedback.text = "근무 완료 상태 저장에 실패했습니다. 저장을 다시 시도해 주세요."
		retry_save.show()
		return
	feedback.text = "근무를 마치고 내 방으로 돌아왔습니다."
	_change_location("room")
	_upload_pending()


func _sleep() -> void:
	transition = true
	map.sleeping = true
	map.player = Vector2(3, 3)
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
	transition = false


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


func _on_upload_finished(success: bool, _text: String) -> void:
	feedback.text = "녹음 전송 완료" if success else "서버 연결 실패 · 녹음은 보관 중입니다. [미전송 녹음 전송]으로 재시도할 수 있습니다."
	_update_hud()
