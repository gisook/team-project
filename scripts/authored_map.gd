extends Control

# The authored TileMapLayers remain the visual and collision source of truth.
# Gameplay cells start at the north-west walkable floor tile (native cell 1, 2).
const CELL_ORIGIN := Vector2i(1, 2)
const TILE := 16.0
const ROOM = preload("res://scenes/field/myroom.tscn")
const STORE = preload("res://scenes/field/test1.tscn")
const NPC = preload("res://scenes/character/npc/npc1.tscn")
const FURNITURE = preload("res://assets/generated/furniture.png")
const DIRECTIONS := ["right", "up", "left", "down"]
const SHEET_OFFSETS := {"left": 0, "right": 6, "up": 12, "down": 18}
const FRIDGE := Rect2i(11, 10, 3, 3)

var location := "room"
var period := "morning"
var player := Vector2(5, 3)
var facing := 3
var moving := false
var sleeping := false
var customers: Array[Dictionary] = []
var focused_customer := -1
var highlighted_customer := -1
var field: Node2D
var floor_layer: TileMapLayer
var furniture_layer: TileMapLayer
var player_actor: CharacterBody2D
var npc_actors: Array[CharacterBody2D] = []
var loaded_location := ""
var frame_cache: Dictionary = {}
var decorations: Node2D


class Decorations extends Node2D:
	var map: Control

	func _draw() -> void:
		if map.location == "room":
			# A separate phone is placed on the existing right-hand desk.
			draw_rect(Rect2(197, 71, 6, 10), Color("32323f"))
			draw_rect(Rect2(198, 72, 4, 7), Color("bce8ce") if map.period != "night" else Color("63717e"))
			# The existing north wall receives a time-of-day window.
			draw_rect(Rect2(104, 4, 64, 24), Color("5b5364"))
			var sky := Color("a4d8de") if map.period != "night" else Color("25375d")
			draw_rect(Rect2(107, 7, 58, 18), sky)
			var sun_y := 21.0 if map.period == "morning" else 12.0
			draw_circle(Vector2(151, 15 if map.period == "night" else sun_y), 5, Color("fff0b9"))
			if map.period == "night":
				draw_circle(Vector2(154, 12), 5, sky)
				for star in [Vector2(114, 12), Vector2(136, 19), Vector2(159, 21)]:
					draw_rect(Rect2(star, Vector2.ONE), Color("fff4d6"))
			draw_rect(Rect2(134, 6, 2, 20), Color("e2dac9"))
		else:
			# The uploaded store has no drink fridge. Add it in its open south-east area.
			draw_texture_rect_region(FURNITURE, Rect2(190, 177, 52, 65), Rect2(670, 410, 510, 590))
			draw_string(ThemeDB.fallback_font, Vector2(185, 174), "음료 냉장고", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("fff1d6"))
			for i in range(map.customers.size()):
				var c: Dictionary = map.customers[i]
				if c["name"] == "노인":
					var foot: Vector2 = map.native_point(c["visual"])
					draw_rect(Rect2(foot + Vector2(-5, -23), Vector2(3, 5)), Color("d0c9c4"))
					draw_rect(Rect2(foot + Vector2(3, -23), Vector2(3, 5)), Color("d0c9c4"))
					draw_line(foot + Vector2(7, -10), foot + Vector2(8, 0), Color("ac8665"), 1.5)
				if i == map.focused_customer: continue
				var head: Vector2 = map.native_point(c["visual"]) - Vector2(0, 27)
				var done: bool = c["done"]
				var ready: bool = not c["moving"] and c["cell"] == c["target"]
				var icon := "✓" if done else ("E" if ready else "…")
				draw_circle(head, 5, Color("527872") if done else Color("c29d60"))
				draw_string(ThemeDB.fallback_font, head + Vector2(-2.5, 2.5), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("fff5df"))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	# Keep all native map layers below the sibling phone/dialogue/HUD controls.
	z_index = -200


func load_location(next: String) -> void:
	if loaded_location == next: return
	if is_instance_valid(field):
		remove_child(field)
		field.queue_free()
	npc_actors.clear()
	loaded_location = next
	location = next
	field = (ROOM if location == "room" else STORE).instantiate()
	# The shared controller owns movement/input and camera framing in the daily game.
	# Standalone scene previews retain their original scripts and camera.
	field.get_node("Camera2D").enabled = false
	player_actor = field.get_node("Maincharacter")
	player_actor.set_physics_process(false)
	player_actor.set_process_unhandled_input(false)
	for child in field.get_children():
		if child is CharacterBody2D and child != player_actor:
			field.remove_child(child)
			child.free()
	add_child(field)
	# Entering the tree enables script callbacks, so disable the standalone driver afterwards.
	player_actor.set_physics_process(false)
	player_actor.set_process_unhandled_input(false)
	floor_layer = field.get_node("FloorLayer")
	furniture_layer = field.get_node("FurnitureLayer")
	if location == "store":
		# Open one counter tile so the cashier can walk to the shelves and return.
		furniture_layer.erase_cell(Vector2i(4, 2))
	# Read tile collision data for navigation; native physics is not used to move grid actors.
	floor_layer.collision_enabled = false
	furniture_layer.collision_enabled = false
	floor_layer.z_index = 0
	furniture_layer.z_index = 1
	player_actor.collision_layer = 0
	player_actor.collision_mask = 0
	player_actor.get_node("InteractArea").monitoring = false
	if location == "store":
		for i in range(3):
			var actor: CharacterBody2D = NPC.instantiate()
			actor.name = "Customer%d" % (i + 1)
			actor.collision_layer = 0
			actor.collision_mask = 0
			field.add_child(actor)
			npc_actors.append(actor)
		var apron := Polygon2D.new()
		apron.polygon = PackedVector2Array([Vector2(-5, 4), Vector2(5, 4), Vector2(5, 14), Vector2(-5, 14)])
		apron.color = Color("3f8e8b")
		player_actor.add_child(apron)
		var cap := Polygon2D.new()
		cap.polygon = PackedVector2Array([Vector2(-5, -8), Vector2(5, -8), Vector2(5, -5), Vector2(-5, -5)])
		cap.color = Color("3f8e8b")
		player_actor.add_child(cap)
	decorations = Decorations.new()
	decorations.map = self
	decorations.z_index = 100
	field.add_child(decorations)


func native_point(cell: Vector2) -> Vector2:
	return (cell + Vector2(CELL_ORIGIN) + Vector2(0.5, 0.5)) * TILE


func map_scale() -> float:
	# Kept in 32-pixel gameplay units for the shared dialogue bubble layout.
	return minf((size.y - 150) / 608.0, (size.x - 36) / 544.0)


func field_origin() -> Vector2:
	var s := map_scale() * 2
	if focused_customer >= 0 and focused_customer < customers.size():
		return Vector2(size.x * 0.5, size.y * 0.37) - native_point(customers[focused_customer]["visual"]) * s
	return Vector2((size.x - 272 * s) * 0.5, 96)


func screen_point(cell: Vector2) -> Vector2:
	return field_origin() + native_point(cell) * map_scale() * 2


func is_blocked(cell: Vector2i) -> bool:
	var raw := cell + CELL_ORIGIN
	var data := floor_layer.get_cell_tile_data(raw)
	if data == null: return true
	if floor_layer.tile_set.get_physics_layers_count() > 0 and data.get_collision_polygons_count(0) > 0:
		return true
	if furniture_layer.get_cell_source_id(raw) != -1: return true
	return location == "store" and FRIDGE.has_point(cell)


func _frames(appearance: String) -> SpriteFrames:
	if frame_cache.has(appearance): return frame_cache[appearance]
	var texture: Texture2D = load("res://image/Characters_free/%s_run_16x16.png" % appearance)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for direction in SHEET_OFFSETS:
		for mode in ["idle", "walk"]:
			var animation := "%s_%s" % [mode, direction]
			frames.add_animation(animation)
			frames.set_animation_speed(animation, 9)
			for i in range(1 if mode == "idle" else 6):
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2((int(SHEET_OFFSETS[direction]) + i) * 16, 0, 16, 32)
				frames.add_frame(animation, atlas)
	frame_cache[appearance] = frames
	return frames


func _process(_delta: float) -> void:
	if not is_instance_valid(field): return
	field.position = field_origin()
	field.scale = Vector2.ONE * map_scale() * 2
	field.modulate = Color("8390ac") if period == "night" and location == "room" else (Color("fff1d9") if period == "afternoon" and location == "room" else Color.WHITE)
	player_actor.position = native_point(Vector2(3, 3) if sleeping else player) - Vector2(0, 16)
	player_actor.rotation = PI * 0.5 if sleeping else 0.0
	var player_sprite: AnimatedSprite2D = player_actor.get_node("AnimatedSprite2D")
	player_sprite.play(("walk_" if moving else "idle_") + DIRECTIONS[facing])
	player_actor.z_index = 2 + int(player.y * 2)
	for i in range(mini(customers.size(), npc_actors.size())):
		var c: Dictionary = customers[i]
		var actor := npc_actors[i]
		actor.position = native_point(c["visual"]) - Vector2(0, 16)
		actor.z_index = 2 + int(Vector2(c["visual"]).y * 2)
		var sprite: AnimatedSprite2D = actor.get_node("AnimatedSprite2D")
		var frames := _frames(str(c["appearance"]))
		if sprite.sprite_frames != frames: sprite.sprite_frames = frames
		sprite.play(("walk_" if c["moving"] and focused_customer < 0 else "idle_") + DIRECTIONS[int(c["facing"])])
		if i == highlighted_customer and focused_customer < 0: actor.highlight()
		else: actor.unhighlight()
		actor.get_node("Label").hide()
	decorations.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("192832"))
