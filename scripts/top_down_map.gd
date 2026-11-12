extends Control

const TILE := 32.0
const FLOOR_SIZE := 16
const INTERIORS = preload("res://assets/modern/interiors.png")
const BUILDER = preload("res://assets/modern/room_builder.png")
const PEOPLE := {
	"Adam": preload("res://assets/modern/Adam_run_16x16.png"),
	"Alex": preload("res://assets/modern/Alex_run_16x16.png"),
	"Amelia": preload("res://assets/modern/Amelia_run_16x16.png"),
	"Bob": preload("res://assets/modern/Bob_run_16x16.png")
}

var location := "room"
var period := "morning"
var player := Vector2(5, 5)
var facing := 0
var moving := false
var sleeping := false
var customers: Array[Dictionary] = []
var focused_customer := -1
var elapsed := 0.0
var furniture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists("res://assets/generated/furniture.png"):
		furniture = load("res://assets/generated/furniture.png")


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func map_scale() -> float:
	return minf((size.y - 136.0) / 576.0, (size.x - 36.0) / 576.0)


func map_origin() -> Vector2:
	var s := map_scale()
	if focused_customer >= 0 and focused_customer < customers.size():
		var npc: Vector2 = customers[focused_customer]["visual"]
		return Vector2(size.x * 0.5, size.y * 0.30) - (npc + Vector2(0.5, 0)) * TILE * s
	return Vector2((size.x - 512.0 * s) * 0.5, 94.0 + 32.0 * s)


func screen_point(cell: Vector2) -> Vector2:
	return map_origin() + (cell + Vector2(0.5, 0.5)) * TILE * map_scale()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("192832"))
	var s := map_scale()
	if s <= 0:
		return
	draw_set_transform(map_origin(), 0, Vector2(s, s))
	# Walls are outside the 16 by 16 floor; furniture occupies floor cells.
	draw_rect(Rect2(-32, -32, 576, 576), Color("333446"))
	draw_rect(Rect2(-24, -32, 560, 544), Color("b8aaa3") if period != "night" else Color("62667f"))
	for y in range(16):
		for x in range(16):
			var source := Rect2(80, 176, 16, 16) if location == "room" else Rect2(80, 304, 16, 16)
			draw_texture_rect_region(BUILDER, Rect2(x * TILE, y * TILE, TILE, TILE), source)
			draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), Color(0, 0, 0, 0.045), false, 1)
	if location == "room":
		_draw_room()
	else:
		_draw_store()
	# Draw people in foot position order so the person below appears in front.
	var actors: Array[Dictionary] = []
	for i in range(customers.size()):
		var c: Dictionary = customers[i]
		actors.append({"pos": c["visual"], "who": c["appearance"], "dir": c["facing"], "walk": c["moving"], "npc": i})
	actors.append({"pos": Vector2(3, 3) if sleeping else player, "who": "Adam", "dir": facing, "walk": moving, "npc": -1})
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pos"].y < b["pos"].y)
	for actor in actors:
		_draw_person(actor)
	if location == "room" and period == "night":
		draw_rect(Rect2(0, 0, 512, 512), Color(0.07, 0.09, 0.24, 0.28))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _sprite(source: Rect2, target: Rect2) -> void:
	draw_texture_rect_region(INTERIORS, target, source)


func _draw_room() -> void:
	# A window attached to the north wall, with different sun elevation by period.
	draw_rect(Rect2(192, -30, 128, 30), Color("5f576b"))
	var sky := Color("a3d8dc") if period != "night" else Color("303e6b")
	draw_rect(Rect2(198, -27, 116, 23), sky)
	var sun_y := -8.0 if period == "morning" else -20.0
	draw_circle(Vector2(280, -17 if period == "night" else sun_y), 8, Color("fff0b2"))
	if period == "night":
		draw_circle(Vector2(284, -20), 7, sky)
		for star in [Vector2(211, -21), Vector2(245, -12), Vector2(302, -20)]:
			draw_rect(Rect2(star, Vector2(2, 2)), Color("fff4d6"))
	draw_rect(Rect2(253, -28, 5, 26), Color("eee4d1"))
	# Bed: generated asset when available; code-native fallback also works offline.
	if furniture != null:
		_draw_generated(0, Rect2(54, 46, 116, 156))
	else:
		draw_rect(Rect2(64, 64, 96, 128), Color("625663"))
		draw_rect(Rect2(69, 68, 86, 118), Color("ca9f78"))
		draw_rect(Rect2(73, 76, 78, 31), Color("eee3cb"))
		draw_rect(Rect2(73, 111, 78, 73), Color("76a4a5"))
	draw_rect(Rect2(320, 96, 128, 64), Color("575062"))
	draw_rect(Rect2(324, 98, 120, 54), Color("c09266"))
	draw_rect(Rect2(329, 101, 110, 3), Color("e2bd8b"))
	draw_line(Vector2(328, 136), Vector2(438, 136), Color("b2835d"), 2)
	draw_rect(Rect2(333, 110, 20, 26), Color("eee3cb"))
	draw_rect(Rect2(342, 110, 2, 26), Color("bcae9c"))
	# Phone stays on the desk and its glow indicates an available schedule.
	draw_rect(Rect2(366, 120, 16, 26), Color("333446"))
	draw_rect(Rect2(369, 123, 10, 17), Color("b7ebce") if period != "night" else Color("60717a"))
	# Room furnishings stay deliberately sparse: bed, desk, phone and window.


func _draw_store() -> void:
	# Register counter; the cashier interacts from the north side, across the desk.
	for x in range(2, 6):
		draw_rect(Rect2(x * 32, 96, 32, 32), Color("665766"))
		draw_rect(Rect2(x * 32 + 2, 98, 28, 23), Color("cbb096"))
	_sprite(Rect2(0, 576, 32, 32), Rect2(89, 71, 48, 48))
	# Stocked shelves use the supplied tiles.
	for y in range(5, 8):
		_sprite(Rect2(160, 1104, 32, 32), Rect2(224, y * 32, 64, 32))
	if furniture != null:
		_draw_generated(1, Rect2(375, 0, 112, 100))
	else:
		draw_rect(Rect2(384, 32, 96, 64), Color("626b80"))
		for door in range(3):
			draw_rect(Rect2(388 + door * 30, 36, 25, 55), Color("a5d6d5"))
			for row in range(3):
				for bottle in range(3):
					draw_rect(Rect2(391 + door * 30 + bottle * 6, 43 + row * 14, 4, 9), Color("d6a171") if bottle % 2 == 0 else Color("7c9e94"))
	# Welcome mat marks the customer entrance.
	_sprite(Rect2(0, 672, 48, 32), Rect2(224, 464, 96, 48))
	_draw_caption(Vector2(64, 59), "계산대")
	_draw_caption(Vector2(220, 148), "진열대")
	_draw_caption(Vector2(379, -7), "음료 냉장고")


func _draw_generated(index: int, target: Rect2) -> void:
	var source := Rect2(150, 400, 340, 600) if index == 0 else Rect2(670, 410, 510, 590)
	draw_texture_rect_region(furniture, target, source)


func _draw_caption(at: Vector2, text: String) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f3e5cd"))


func _draw_person(actor: Dictionary) -> void:
	var pos: Vector2 = actor["pos"]
	var foot := (pos + Vector2(0.5, 0.8)) * TILE
	draw_ellipse_shadow(foot)
	var dir: int = actor["dir"]
	var frame := int(elapsed * 9) % 6 if actor["walk"] else 0
	# Spritesheet order: right, up, left, down; six frames for each direction.
	var col := dir * 6 + frame
	var texture: Texture2D = PEOPLE[actor["who"]]
	if sleeping and int(actor["npc"]) == -1:
		draw_set_transform(map_origin() + Vector2(112, 120) * map_scale(), PI * 0.5, Vector2(map_scale(), map_scale()))
		draw_texture_rect_region(texture, Rect2(-16, -32, 32, 64), Rect2(18 * 16, 0, 16, 32))
		draw_set_transform(map_origin(), 0, Vector2(map_scale(), map_scale()))
		return
	draw_texture_rect_region(texture, Rect2(foot - Vector2(16, 64), Vector2(32, 64)), Rect2(col * 16, 0, 16, 32))
	if int(actor["npc"]) >= 0 and customers[int(actor["npc"])]["name"] == "노인":
		# Grey side hair and a walking cane distinguish the elder from the young adult.
		draw_rect(Rect2(foot + Vector2(-10, -42), Vector2(5, 12)), Color("d0c9c4"))
		draw_rect(Rect2(foot + Vector2(6, -42), Vector2(5, 12)), Color("d0c9c4"))
		draw_line(foot + Vector2(12, -18), foot + Vector2(14, 1), Color("ac8665"), 3)
	if int(actor["npc"]) == -1 and location == "store":
		# Work uniform: teal apron, white name tag, and cap over the base character.
		draw_rect(Rect2(foot + Vector2(-9, -13), Vector2(18, 12)), Color("3f8e8b"))
		draw_rect(Rect2(foot + Vector2(3, -11), Vector2(5, 3)), Color("fff0cd"))
		draw_rect(Rect2(foot + Vector2(-10, -44), Vector2(20, 5)), Color("3f8e8b"))
	var index: int = actor["npc"]
	if index >= 0:
		var c: Dictionary = customers[index]
		var icon := "✓" if c["done"] else ("…" if c["cell"] != c["target"] else "E")
		draw_circle(foot + Vector2(0, -58), 10, Color("385a59") if c["done"] else Color("d1ae73"))
		draw_string(ThemeDB.fallback_font, foot + Vector2(-5, -53), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff4d7"))


func draw_ellipse_shadow(at: Vector2) -> void:
	draw_set_transform(map_origin() + at * map_scale(), 0, Vector2(map_scale(), map_scale() * 0.35))
	draw_circle(Vector2.ZERO, 12, Color(0.12, 0.12, 0.18, 0.25))
	draw_set_transform(map_origin(), 0, Vector2(map_scale(), map_scale()))
