@tool
extends Marker2D

## 맵에 배치하는 기능 표시점. 위치와 범위를 인스펙터에서 수정합니다.
@export_enum("player_spawn", "bed", "phone", "npc_spawn", "npc_target", "cashier", "window", "fridge", "passage", "view_bounds") var role := "player_spawn":
	set(value):
		role = value
		queue_redraw()
## 손님 관련 표시점은 counter / shelf / fridge 중 해당 손님 ID를 사용합니다.
@export var customer_id: StringName = &""
## 표시점이 있는 칸부터 오른쪽·아래로 차지하는 타일 수입니다.
@export var footprint := Vector2i.ONE:
	set(value):
		footprint = Vector2i(maxi(1, value.x), maxi(1, value.y))
		queue_redraw()
@export_range(0, 8) var interaction_distance := 1
@export var blocks_movement := false
## 직접 Sprite2D 등으로 표현한 물체는 이 옵션을 끄세요.
@export var render_visual := true:
	set(value):
		render_visual = value
		queue_redraw()
@export var visual_offset := Vector2.ZERO:
	set(value):
		visual_offset = value
		queue_redraw()
@export var visual_size := Vector2(16, 16):
	set(value):
		visual_size = value
		queue_redraw()
@export var cell_size := 16
var period := "morning":
	set(value):
		if period != value:
			period = value
			queue_redraw()

const FURNITURE = preload("res://assets/generated/furniture.png")


func _draw() -> void:
	if render_visual:
		draw_set_transform(visual_offset)
		match role:
			"phone":
				draw_rect(Rect2(-3, -5, 6, 10), Color("32323f"))
				draw_rect(Rect2(-2, -4, 4, 7), Color("bce8ce") if period != "night" else Color("63717e"))
			"window":
				draw_rect(Rect2(-32, -12, 64, 24), Color("5b5364"))
				var sky := Color("a4d8de") if period != "night" else Color("25375d")
				draw_rect(Rect2(-29, -9, 58, 18), sky)
				draw_circle(Vector2(15, -1 if period == "night" else (5 if period == "morning" else -4)), 5, Color("fff0b9"))
				if period == "night":
					draw_circle(Vector2(18, -4), 5, sky)
					for star in [Vector2(-22, -4), Vector2(0, 3), Vector2(23, 5)]:
						draw_rect(Rect2(star, Vector2.ONE), Color("fff4d6"))
				draw_rect(Rect2(-2, -10, 2, 20), Color("e2dac9"))
			"fridge":
				draw_texture_rect_region(FURNITURE, Rect2(Vector2.ZERO, visual_size), Rect2(670, 410, 510, 590))
				draw_string(ThemeDB.fallback_font, Vector2(-5, -3), "음료 냉장고", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("fff1d6"))
		draw_set_transform(Vector2.ZERO)
	if Engine.is_editor_hint():
		var color := Color("66d6bd") if role not in ["bed", "phone", "fridge"] else Color("f3c06a")
		draw_line(Vector2(-5, 0), Vector2(5, 0), color, 1)
		draw_line(Vector2(0, -5), Vector2(0, 5), color, 1)
		if footprint != Vector2i.ONE or blocks_movement:
			draw_rect(Rect2(Vector2.ZERO, Vector2(footprint) * cell_size), color, false, 1)
		draw_string(ThemeDB.fallback_font, Vector2(5, -6), role + (":" + str(customer_id) if customer_id != &"" else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
