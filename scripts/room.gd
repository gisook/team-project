extends Control

const DayState = preload("res://scripts/day_state.gd")
const DialogueCatalog = preload("res://scripts/dialogue_catalog.gd")
const DESIGN_SIZE := Vector2(1100.0, 680.0)

var state: Dictionary = {}
var phone_button: Button
var bed_button: Button
var schedule_popup: PopupPanel
var schedule_items: VBoxContainer
var heading_label: Label
var manage_button: Button
var hint_label: Label


func _ready() -> void:
	state = DayState.load_state()
	DialogueCatalog.ensure_file()
	_build_interface()
	_update_room()
	# 비정상 종료 후 다시 게임을 시작하면 마지막 대화에서 이어집니다.
	if str(state.get("status", "room")) == "dialogue":
		var target := str(state.get("active_dialogue_id", ""))
		var exists := false
		for dialogue in DialogueCatalog.read_all():
			if str(dialogue.get("id", "")) == target:
				exists = true
				break
		if exists:
			call_deferred("_resume_dialogue")
		else:
			DayState.abort_schedule()
			state = DayState.load_state()
			_update_room()


func _resume_dialogue() -> void:
	get_tree().change_scene_to_file(DayState.GAME_SCENE)


func _build_interface() -> void:
	phone_button = Button.new()
	phone_button.name = "PhoneButton"
	phone_button.text = "휴대폰 열기\n오늘의 일정"
	phone_button.add_theme_font_size_override("font_size", 18)
	phone_button.pressed.connect(_on_phone_pressed)
	add_child(phone_button)

	bed_button = Button.new()
	bed_button.name = "BedButton"
	bed_button.text = "침대에서 취침\n저장하고 다음 날"
	bed_button.add_theme_font_size_override("font_size", 18)
	bed_button.pressed.connect(_on_bed_pressed)
	add_child(bed_button)

	var header := PanelContainer.new()
	header.name = "DayInfo"
	header.position = Vector2(22, 18)
	add_child(header)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 18)
	header_margin.add_theme_constant_override("margin_right", 18)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header.add_child(header_margin)
	heading_label = Label.new()
	heading_label.add_theme_font_size_override("font_size", 24)
	header_margin.add_child(heading_label)

	manage_button = Button.new()
	manage_button.name = "DialogueManageButton"
	manage_button.text = "대화 추가 · 수정 · 삭제"
	manage_button.custom_minimum_size = Vector2(194, 42)
	manage_button.pressed.connect(_on_manage_pressed)
	add_child(manage_button)

	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.add_theme_font_size_override("font_size", 19)
	hint_label.add_theme_color_override("font_color", Color("#ffffff"))
	hint_label.add_theme_color_override("font_shadow_color", Color("#303030"))
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 2)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)

	schedule_popup = PopupPanel.new()
	schedule_popup.name = "SchedulePopup"
	add_child(schedule_popup)
	var popup_margin := MarginContainer.new()
	popup_margin.add_theme_constant_override("margin_left", 20)
	popup_margin.add_theme_constant_override("margin_right", 20)
	popup_margin.add_theme_constant_override("margin_top", 18)
	popup_margin.add_theme_constant_override("margin_bottom", 18)
	schedule_popup.add_child(popup_margin)
	var popup_box := VBoxContainer.new()
	popup_box.custom_minimum_size = Vector2(490, 0)
	popup_box.add_theme_constant_override("separation", 13)
	popup_margin.add_child(popup_box)
	var popup_title := Label.new()
	popup_title.name = "PopupTitle"
	popup_title.text = "오늘의 일정 선택"
	popup_title.add_theme_font_size_override("font_size", 25)
	popup_box.add_child(popup_title)
	var sublabel := Label.new()
	sublabel.text = "일정을 하나 고르면 해당 상황의 대화 연습이 시작됩니다."
	sublabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_box.add_child(sublabel)
	schedule_items = VBoxContainer.new()
	schedule_items.add_theme_constant_override("separation", 10)
	popup_box.add_child(schedule_items)
	var close_button := Button.new()
	close_button.text = "닫기"
	close_button.pressed.connect(func() -> void: schedule_popup.hide())
	popup_box.add_child(close_button)
	resized.connect(_layout_interactions)
	_layout_interactions()


func _update_room() -> void:
	var period := str(state.get("period", "morning"))
	var period_title := "오전" if period == "morning" else ("오후" if period == "afternoon" else "밤")
	heading_label.text = "자취방  |  %d일 차  ·  %s" % [int(state.get("day", 1)), period_title]
	phone_button.visible = period != "night"
	bed_button.visible = period == "night"
	if period == "morning":
		hint_label.text = "아침이 밝았습니다. 책상 위 휴대폰을 눌러 오전 일정을 선택하세요."
	elif period == "afternoon":
		hint_label.text = "오후가 되었습니다. 휴대폰을 눌러 오후 일정을 선택하세요."
	else:
		hint_label.text = "오늘의 일과를 마쳤습니다. 침대를 누르면 저장 후 다음 날 아침이 됩니다."
	var pending_count := _count_pending_recordings()
	if pending_count > 0:
		hint_label.text += "  (미전송 녹음 %d개 보관 중)" % pending_count
	queue_redraw()
	_layout_interactions()


func _layout_interactions() -> void:
	if phone_button == null or bed_button == null or hint_label == null:
		return
	var scale_factor: float = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var offset: Vector2 = (size - DESIGN_SIZE * scale_factor) * 0.5
	phone_button.position = offset + Vector2(458, 315) * scale_factor
	phone_button.size = Vector2(165, 90) * scale_factor
	bed_button.position = offset + Vector2(745, 430) * scale_factor
	bed_button.size = Vector2(230, 100) * scale_factor
	manage_button.position = Vector2(size.x - 215, 22)
	hint_label.position = Vector2(16, size.y - 65)
	hint_label.size = Vector2(maxf(200, size.x - 32), 52)
	queue_redraw()


func _count_pending_recordings() -> int:
	var path := "user://pending_recordings.json"
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return 0
	var items: Variant = parsed.get("recordings", [])
	if not (items is Array):
		return 0
	var count := 0
	for item in items:
		if item is Dictionary and not bool(item.get("uploaded", false)):
			count += 1
	return count


func _on_phone_pressed() -> void:
	if str(state.get("period", "morning")) == "night":
		return
	for child in schedule_items.get_children():
		schedule_items.remove_child(child)
		child.queue_free()

	var possible := 0
	for dialogue in DialogueCatalog.read_all():
		if str(dialogue.get("period", "morning")) != str(state["period"]):
			continue
		if not bool(dialogue.get("schedule_start", true)):
			continue
		var id := str(dialogue.get("id", ""))
		if id.is_empty():
			continue
		var option := Button.new()
		option.text = str(dialogue.get("title", id))
		option.custom_minimum_size = Vector2(480, 52)
		option.pressed.connect(_start_dialogue.bind(id))
		schedule_items.add_child(option)
		possible += 1
	if possible == 0:
		var empty_notice := Label.new()
		empty_notice.text = "이 시간대의 일정이 없습니다. 대화 관리에서 일정을 추가하세요."
		empty_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		schedule_items.add_child(empty_notice)
	schedule_popup.popup_centered(Vector2i(560, 420))


func _start_dialogue(id: String) -> void:
	if not DayState.start_schedule(id):
		push_warning("일정 진행 상태를 저장하지 못했습니다.")
		return
	get_tree().change_scene_to_file(DayState.GAME_SCENE)


func _on_manage_pressed() -> void:
	get_tree().change_scene_to_file(DayState.GAME_SCENE)


func _on_bed_pressed() -> void:
	if not DayState.sleep_and_save():
		push_warning("취침 저장에 실패했습니다.")
		return
	state = DayState.load_state()
	_update_room()


# 이미지 리소스가 없어도 3개 시간대의 자취방을 표시할 수 있는 벡터 배경.
func _draw() -> void:
	var period := str(state.get("period", "morning"))
	var wall := Color("#f4e8d7")
	var floor_color := Color("#b68e70")
	var sky := Color("#8bcdf4")
	if period == "afternoon":
		wall = Color("#f2d1a7")
		sky = Color("#ed9e75")
	elif period == "night":
		wall = Color("#4c5576")
		floor_color = Color("#6b5260")
		sky = Color("#263a68")
	draw_rect(Rect2(Vector2.ZERO, size), Color("#20273a"))
	var s: float = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var shift: Vector2 = (size - DESIGN_SIZE * s) * 0.5
	draw_set_transform(shift, 0.0, Vector2(s, s))
	# 벽, 바닥, 창문
	draw_rect(Rect2(0, 0, 1100, 475), wall)
	draw_rect(Rect2(0, 475, 1100, 205), floor_color)
	draw_rect(Rect2(100, 98, 310, 236), Color("#ded5c6"))
	draw_rect(Rect2(115, 110, 280, 210), sky)
	if period != "night":
		draw_circle(Vector2(336, 164), 29.0, Color("#ffebad"))
		for x in [160.0, 255.0]:
			draw_circle(Vector2(x, 230), 22, Color(1, 1, 1, 0.5))
	else:
		draw_circle(Vector2(334, 170), 24, Color("#e2e9f8"))
		for p in [Vector2(165, 148), Vector2(245, 216), Vector2(285, 130)]:
			draw_circle(p, 3, Color("#f0f1d5"))
	draw_line(Vector2(255, 110), Vector2(255, 320), Color("#fff4df"), 9)
	draw_line(Vector2(114, 213), Vector2(395, 213), Color("#fff4df"), 9)
	# 벽의 포스터, 선반, 책
	draw_rect(Rect2(700, 105, 155, 135), Color("#ddc4b2"))
	draw_rect(Rect2(714, 120, 125, 104), Color("#69879a"))
	draw_rect(Rect2(745, 163, 66, 44), Color("#b6c49c"))
	draw_rect(Rect2(500, 225, 130, 12), Color("#765345"))
	for i in range(5):
		draw_rect(Rect2(512 + i * 20, 189, 13, 36), Color("#8aab8a") if i % 2 == 0 else Color("#dcac8b"))
	# 책상, 노트북, 휴대폰
	draw_rect(Rect2(215, 425, 460, 32), Color("#755442"))
	draw_rect(Rect2(252, 457, 25, 135), Color("#684b3b"))
	draw_rect(Rect2(625, 457, 25, 135), Color("#684b3b"))
	draw_rect(Rect2(296, 322, 140, 100), Color("#353b4d"))
	draw_rect(Rect2(308, 334, 116, 74), Color("#7da7be") if period != "night" else Color("#5a79b0"))
	draw_rect(Rect2(288, 420, 164, 9), Color("#a2a7ad"))
	draw_rect(Rect2(492, 368, 54, 16), Color("#262d3a"))
	draw_rect(Rect2(497, 345, 44, 25), Color("#9ec5ce"))
	# 침대, 베개, 이불, 협탁
	draw_rect(Rect2(697, 403, 347, 178), Color("#6a5047"))
	draw_rect(Rect2(714, 390, 309, 158), Color("#ece1d3"))
	draw_rect(Rect2(726, 405, 100, 57), Color("#fff6ed"))
	draw_rect(Rect2(822, 412, 189, 127), Color("#82a3b0") if period != "night" else Color("#546e97"))
	draw_rect(Rect2(709, 557, 18, 46), Color("#5a443d"))
	draw_rect(Rect2(1014, 557, 18, 46), Color("#5a443d"))
	draw_rect(Rect2(1028, 369, 55, 95), Color("#a37f68"))
	draw_circle(Vector2(1057, 352), 21, Color("#fff3c1") if period == "night" else Color("#d9d6d2"))
	if period == "night":
		draw_rect(Rect2(0, 0, 1100, 680), Color(0.04, 0.06, 0.19, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
