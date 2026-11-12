extends CharacterBody2D

const SPEED = 150.0

@onready var anim = $AnimatedSprite2D
@onready var interact_area = $InteractArea

var last_direction = "down"

# [추가됨] 현재 하이라이트 된 가장 가까운 NPC를 기억해둘 변수
var current_target_npc = null 

func _physics_process(delta):
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * SPEED

	if direction != Vector2.ZERO:
		if direction.x > 0:
			anim.play("walk_right")
			last_direction = "right"
		elif direction.x < 0:
			anim.play("walk_left")
			last_direction = "left"
		elif direction.y < 0:
			anim.play("walk_up")
			last_direction = "up"
		elif direction.y > 0:
			anim.play("walk_down")
			last_direction = "down"
	else:
		anim.play("idle_" + last_direction)
		
	move_and_slide()
	
	# [추가됨] 이동할 때마다 가장 가까운 NPC가 누구인지 갱신합니다.
	update_closest_npc()

# [추가됨] 실시간으로 가장 가까운 NPC를 찾아 하이라이트를 관리하는 함수
func update_closest_npc():
	var bodies = interact_area.get_overlapping_bodies()
	var closest_npc = null
	var min_distance = INF 

	for body in bodies:
		if body.is_in_group("NPC"):
			var distance = global_position.distance_to(body.global_position)
			if distance < min_distance:
				min_distance = distance
				closest_npc = body
				
	# 만약 가장 가까운 NPC가 이전과 달라졌다면 (새로운 NPC에 다가갔거나, 범위 밖으로 벗어났다면)
	if current_target_npc != closest_npc:
		# 1. 기존에 불이 켜져 있던 NPC가 있다면 불을 끕니다.
		if current_target_npc != null:
			current_target_npc.unhighlight()
			
		# 2. 타겟을 새로운 NPC로 교체합니다. (없으면 null이 들어갑니다)
		current_target_npc = closest_npc
		
		# 3. 새로운 NPC가 있다면 불을 켭니다.
		if current_target_npc != null:
			current_target_npc.highlight()

func _unhandled_input(event):
	if event.is_action_pressed("interaction"):
		# [수정됨] 이제 매번 새로 찾을 필요 없이, 이미 불이 켜져 있는(타겟팅 된) NPC와 바로 상호작용합니다.
		if current_target_npc != null:
			current_target_npc.interact()
