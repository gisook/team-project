extends CanvasLayer

signal choice_selected(choice_text: String)
signal message_closed

@onready var dialog_box = $DialogBox
@onready var text_label = $DialogBox/TextLabel
@onready var vbox_container = $DialogBox/VBoxContainer

# 1. 분리해둔 버튼 씬 파일을 메모리에 미리 불러옵니다(preload).
# (괄호 안의 경로는 실제 choice_button.tscn을 저장한 경로로 정확히 맞춰주세요)
var choice_button_scene = preload("res://scenes/system/choice_button.tscn")

func _ready():
	dialog_box.visible = false

func show_message(text: String):
	text_label.text = text
	clear_choices()
	dialog_box.visible = true

func show_choices(text: String, choices: Array):
	text_label.text = text
	clear_choices()
	dialog_box.visible = true
	
	for choice_text in choices:
		# 2. 씬 파일(PackedScene)로부터 새로운 버튼 노드를 생성(instantiate)합니다.
		var new_btn = choice_button_scene.instantiate()
		new_btn.text = choice_text
		
		new_btn.pressed.connect(func(): on_choice_clicked(choice_text))
		vbox_container.add_child(new_btn)

func clear_choices():
	# 3. VBoxContainer 안에는 이제 우리가 코드로 추가한 버튼들만 존재하므로,
	# 예외 없이(if문 없이) 전부 지워주면 됩니다.
	for child in vbox_container.get_children():
		child.queue_free()

func on_choice_clicked(choice_text: String):
	print("플레이어 선택: " + choice_text)
	
	# 1. 클릭하는 순간 기존 대화 상자를 화면에서 숨깁니다.
	dialog_box.visible = false
	
	# 2. Autoload에 등록된 RecordUi를 불러와서, 방금 누른 텍스트를 넘겨주고 창을 띄웁니다.
	Record.show_record_ui(choice_text)
	
	# 3. 플레이어가 녹음 창에서 녹음을 마치고 창이 닫힐 때(record_finished)까지 여기서 코드를 일시 정지하고 기다립니다.
	await Record.record_finished
	
	# 4. 녹음 및 파일 저장이 모두 무사히 끝났으므로, 원래 기다리고 있던 NPC 스크립트 쪽으로 신호를 보냅니다.
	choice_selected.emit(choice_text)

func _input(event):
	if dialog_box.visible and event.is_action_pressed("interaction"):
		dialog_box.visible = false
		get_viewport().set_input_as_handled()
