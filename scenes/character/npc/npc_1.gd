extends CharacterBody2D

@onready var anim = $AnimatedSprite2D
# 방금 추가한 Label 노드를 가져옵니다.
@onready var speech_bubble = $Label

@export var current_direction: String = "down"

# 인스펙터 창에서 NPC마다 다른 대사를 입력할 수 있게 만듭니다.
@export var dialogue_text: String = "안녕! 나는 NPC야." 

func _ready():
	anim.play("idle_" + current_direction)
	
	# 게임 시작 시 말풍선에 설정된 대사를 넣고 숨겨둡니다.
	speech_bubble.text = dialogue_text
	speech_bubble.visible = false
	
func interact():
	# 메인 캐릭터가 E 키를 눌러 상호작용하면 말풍선을 보여줍니다.
	speech_bubble.visible = true

func highlight():
	anim.modulate = Color(1.5, 1.5, 1.5) 

func unhighlight():
	anim.modulate = Color(1.0, 1.0, 1.0)
	# 캐릭터에게서 멀어져서 하이라이트가 꺼질 때, 말풍선도 같이 숨깁니다.
	speech_bubble.visible = false
