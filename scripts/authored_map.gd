extends Control

# The authored TileMapLayers remain the visual and collision source of truth.
const MapLayout = preload("res://scripts/map_layout.gd")
const NPC = preload("res://scenes/character/npc/npc1.tscn")
const DIRECTIONS := ["right", "up", "left", "down"]
const SHEET_OFFSETS := {"left": 0, "right": 6, "up": 12, "down": 18}

var location := "room"
var period := "morning"
var player := Vector2.ZERO
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
var layout: RefCounted
var layout_errors: Array[String] = []


class Decorations extends Node2D:
	var map: Control

	func _draw() -> void:
		if map.location != "store": return
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


func load_location(next: String) -> bool:
	if loaded_location == next: return layout_errors.is_empty()
	if is_instance_valid(field):
		remove_child(field)
		field.queue_free()
	npc_actors.clear()
	loaded_location = ""
	location = next
	layout_errors.clear()
	var source: Variant = ProjectSettings.get_setting("gameplay/maps/" + location)
	var packed: PackedScene
	if source is PackedScene:
		packed = source
	elif source is String and ResourceLoader.exists(source):
		packed = load(source) as PackedScene
	if packed == null:
		layout_errors.append("프로젝트 설정 gameplay/maps/%s에 맵 장면을 지정해 주세요." % location)
		return false
	var instance := packed.instantiate()
	if not (instance is Node2D):
		layout_errors.append("맵 장면의 루트는 Node2D여야 합니다.")
		instance.free()
		return false
	field = instance
	# The shared controller owns movement/input and camera framing in the daily game.
	# Standalone scene previews retain their original scripts and camera.
	var camera := field.get_node_or_null("Camera2D") as Camera2D
	if camera != null: camera.enabled = false
	player_actor = field.get_node_or_null("Maincharacter") as CharacterBody2D
	if player_actor == null:
		layout_errors.append("맵에 Maincharacter 캐릭터가 필요합니다.")
		field.free()
		return false
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
	floor_layer = field.get_node_or_null("FloorLayer") as TileMapLayer
	furniture_layer = field.get_node_or_null("FurnitureLayer") as TileMapLayer
	layout = MapLayout.new(field, location)
	layout_errors.assign(layout.errors)
	if not layout_errors.is_empty(): return false
	loaded_location = next
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
	return true


func native_point(cell: Vector2) -> Vector2:
	return layout.native_point(cell)


func map_scale() -> float:
	# Kept in 32-pixel gameplay units for the shared dialogue bubble layout.
	var bounds: Rect2 = layout.view_rect()
	return minf((size.y - 150) / maxf(1, bounds.size.y), (size.x - 36) / maxf(1, bounds.size.x)) * 0.5


func field_origin() -> Vector2:
	var s := map_scale() * 2
	if focused_customer >= 0 and focused_customer < customers.size():
		return Vector2(size.x * 0.5, size.y * 0.37) - native_point(customers[focused_customer]["visual"]) * s
	var bounds: Rect2 = layout.view_rect()
	return Vector2((size.x - bounds.size.x * s) * 0.5, 96) - bounds.position * s


func screen_point(cell: Vector2) -> Vector2:
	return field_origin() + native_point(cell) * map_scale() * 2


func is_blocked(cell: Vector2i) -> bool:
	return layout.blocked(cell)


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
	if not is_instance_valid(field) or not layout_errors.is_empty(): return
	field.position = field_origin()
	field.scale = Vector2.ONE * map_scale() * 2
	field.modulate = Color("8390ac") if period == "night" and location == "room" else (Color("fff1d9") if period == "afternoon" and location == "room" else Color.WHITE)
	player_actor.position = native_point(layout.sleep_cell() if sleeping else player) - Vector2(0, 16)
	for marker in layout.markers: marker.period = period
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
