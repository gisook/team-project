extends CanvasLayer

# 이미지의 노드 구조에 맞게 경로를 가져옵니다.
@onready var phone_panel = $Panel
@onready var vbox_container = $Panel/VBoxContainer
@onready var base_button = $Panel/VBoxContainer/todoButton
@onready var anim_player = $AnimationPlayer

var target_scene = "res://scenes/field/test1.tscn"
var is_phone_open: bool = false

# 임시 할 일 데이터 리스트
# todo : { "text", target_scene }
var task_list = {
	"오전 10시: 편의점 알바" : "res://scenes/field/test1.tscn"
	}


func _ready():
	# 게임 시작 시 폰 화면과 원본 버튼을 숨겨둡니다.
	phone_panel.visible = false
	base_button.visible = false 
	
	# 리스트 생성 함수 호출
	populate_tasks()

func populate_tasks():
	# 배열의 데이터를 돌면서 버튼을 복제해 목록을 만듭니다.
	for task_name in task_list:
		var new_btn = base_button.duplicate()
		new_btn.text = task_name
		new_btn.visible = true
		
		# 버튼이 클릭되었을 때 실행될 함수(이벤트)를 연결합니다.
		new_btn.pressed.connect(func(): on_task_clicked(task_name))
		
		# VBoxContainer 안에 새 버튼을 자식으로 집어넣습니다.
		vbox_container.add_child(new_btn)

func on_task_clicked(task_name: String):
	# 어떤 버튼이 눌렸는지 하단 출력(Output) 창에 띄워줍니다.
	get_tree().change_scene_to_file(task_list[task_name])
	# (나중에 여기에 화면이 넘어가거나 팝업이 뜨는 코드를 추가하시면 됩니다.)

func _input(event):
	# Q 키(open_phone)를 누르면 스마트폰 화면을 켜고 끕니다.
	if event.is_action_pressed("open_phone"):
		if anim_player.is_playing():
			return  # 애니메이션 도중 중복 입력 방지

		if is_phone_open:
			anim_player.play("close")
		else:
			phone_panel.visible = true
			anim_player.play("open")

		is_phone_open = not is_phone_open
