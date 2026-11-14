extends CharacterBody2D

@onready var anim = $AnimatedSprite2D
# 방금 추가한 Label 노드를 가져옵니다.

@export var current_direction: String = "down"


func _ready():
	anim.play("idle_" + current_direction)
	
func interact():
	# 1. show_message 대신 show_choices를 호출하고, 두 번째 인자로 선택지 배열을 넘깁니다.
	DialogUi.show_choices(
		"과자는 어딨나요?", 
		["두번째 진열대에 있습니다.", "그냥 지나가기"]
	)
	
	# 2. 플레이어가 버튼을 누를 때까지 기다립니다.
	var chosen_text = await DialogUi.choice_selected
	
	# 3. 선택한 결과에 따른 분기 처리
	if chosen_text == "상점 둘러보기":
		DialogUi.show_message("아직 물건이 들어오지 않았습니다.")
		
	elif chosen_text == "그냥 지나가기":
		# 아무것도 안 하면 창이 닫힌 상태로 대화가 종료됩니다.
		pass

func highlight():
	anim.modulate = Color(1.5, 1.5, 1.5) 

func unhighlight():
	anim.modulate = Color(1.0, 1.0, 1.0)
	# 캐릭터에게서 멀어져서 하이라이트가 꺼질 때, 말풍선도 같이 숨깁니다.
