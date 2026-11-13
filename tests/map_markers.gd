extends SceneTree

const DayState = preload("res://scripts/day_state.gd")
const TestWorld = preload("res://tests/test_world.gd")
const MapView = preload("res://scripts/authored_map.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if value: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func pack(scene: Node2D) -> PackedScene:
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "modified editor scene packs successfully")
	scene.free()
	return packed


func move_furniture(scene: Node2D, rect: Rect2i, offset: Vector2i) -> void:
	var layer: TileMapLayer = scene.get_node("FurnitureLayer")
	var tiles: Array[Dictionary] = []
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var cell := Vector2i(x, y)
			if layer.get_cell_source_id(cell) < 0: continue
			tiles.append({"cell": cell, "source": layer.get_cell_source_id(cell), "atlas": layer.get_cell_atlas_coords(cell), "alt": layer.get_cell_alternative_tile(cell)})
	for tile in tiles: layer.erase_cell(tile["cell"])
	for tile in tiles: layer.set_cell(tile["cell"] + offset, tile["source"], tile["atlas"], tile["alt"])


func _run() -> void:
	var account := preload("res://tests/account_fixture.gd").new()
	var original_room: Variant = ProjectSettings.get_setting("gameplay/maps/room")
	var original_store: Variant = ProjectSettings.get_setting("gameplay/maps/store")
	DayState.set_account("marker_test_%d" % Time.get_ticks_usec())
	DayState.save_state(DayState.default_state())
	# Simulate editing furniture AND its functional markers in Godot, then saving the map.
	var room: Node2D = load(original_room).instantiate()
	move_furniture(room, Rect2i(3, 4, 3, 3), Vector2i(0, 6))
	move_furniture(room, Rect2i(11, 4, 3, 2), Vector2i(-4, 6))
	room.get_node("Gameplay/Bed").position += Vector2(0, 96)
	room.get_node("Gameplay/Phone").position += Vector2(-64, 96)
	room.get_node("Gameplay/PlayerSpawn").position = Vector2(104, 184)
	room.get_node("Gameplay/Window").position.x -= 32
	var moved_room := pack(room)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	check(ResourceSaver.save(moved_room, "res://artifacts/moved_room.tscn") == OK, "edited room saved to a different map file")
	ProjectSettings.set_setting("gameplay/maps/room", "res://artifacts/moved_room.tscn")
	var world := TestWorld.new()
	root.add_child(world)
	await process_frame
	world.set_process(false)
	check(world.map.layout_errors.is_empty(), "moved room layout validates")
	check(world.player_cell == Vector2i(6, 11), "player starts at moved spawn marker")
	world.player_cell = Vector2i(8, 12)
	check(world._interaction_target() == "phone", "phone interaction follows moved desk marker")
	world.player_cell = Vector2i(12, 6)
	check(world._interaction_target() == "", "previous phone position no longer interacts")
	check(world._blocked(Vector2i(4, 11)) and not world._blocked(Vector2i(4, 5)), "bed collision follows edited furniture and footprint")
	check(world.map.layout.sleep_cell() == Vector2(4, 11), "lying position follows Bed/SleepPoint")
	check(world.map.layout.anchor("phone").global_position == world.map.field.to_global(Vector2(136, 184)), "phone visual is attached to moved marker")
	world.queue_free()
	await process_frame
	var store: Node2D = load(original_store).instantiate()
	store.get_node("Gameplay/PlayerSpawn").position = Vector2(40, 40)
	store.get_node("Gameplay/Cashier").position = Vector2(40, 40)
	store.get_node("Gameplay/CounterTarget").position = Vector2(56, 88)
	store.get_node("Gameplay/ShelfTarget").position = Vector2(168, 168)
	store.get_node("Gameplay/DrinkFridge").position += Vector2(-48, 16)
	store.get_node("Gameplay/FridgeTarget").position = Vector2(136, 232)
	store.get_node("Gameplay/CounterSpawn").position = Vector2(40, 264)
	store.get_node("Gameplay/FridgeSpawn").position = Vector2(232, 264)
	ProjectSettings.set_setting("gameplay/maps/store", pack(store))
	check(DayState.start_store_shift(), "start shift with replacement store scene")
	world = TestWorld.new()
	root.add_child(world)
	await process_frame
	world.set_process(false)
	check(world.map.layout_errors.is_empty() and world.location == "store", "replacement store markers validate")
	if not world.map.layout_errors.is_empty():
		printerr(world.map.layout_errors)
		ProjectSettings.set_setting("gameplay/maps/room", original_room)
		ProjectSettings.set_setting("gameplay/maps/store", original_store)
		account.restore()
		quit(1)
		return
	check(world.player_cell == Vector2i(2, 2), "cashier spawn comes from map")
	check(world.customers[0].get("from", world.customers[0]["cell"]) == Vector2i(2, 16), "NPC entrance comes from moved marker")
	check(world.customers[1]["target"] == Vector2i(10, 10), "shelf target comes from moved marker")
	check(world._blocked(Vector2i(9, 13)) and not world._blocked(Vector2i(13, 12)), "fridge collision follows marker footprint")
	for i in range(300): world._move_customers(0.31)
	var arrived := true
	for customer in world.customers:
		arrived = arrived and customer["cell"] == customer["target"] and not customer["moving"]
	check(arrived, "three NPCs pathfind to edited destinations")
	check(world._interaction_target() == "npc:0", "counter interaction follows moved cashier marker")
	world.queue_free()
	await process_frame
	# An incomplete map must stop with an actionable message instead of a null-node crash.
	var broken: Node2D = load(original_room).instantiate()
	broken.get_node("Gameplay/Phone").free()
	ProjectSettings.set_setting("gameplay/maps/room", pack(broken))
	DayState.save_state(DayState.default_state())
	world = TestWorld.new()
	root.add_child(world)
	await process_frame
	check(world.transition and world.feedback.text.contains("phone"), "missing required marker is reported without crashing")
	world.queue_free()
	await process_frame
	var blocked: Node2D = load(original_store).instantiate()
	blocked.get_node("Gameplay/ShelfTarget").position = blocked.get_node("Gameplay/DrinkFridge").position
	ProjectSettings.set_setting("gameplay/maps/store", pack(blocked))
	var invalid_view := MapView.new()
	root.add_child(invalid_view)
	check(not invalid_view.load_location("store") and str(invalid_view.layout_errors).contains("가구"), "NPC destination inside furniture is rejected with a useful message")
	invalid_view.queue_free()
	await process_frame
	# Changing the floor's origin and parent hierarchy must not reintroduce fixed offsets.
	var translated: Node2D = load(original_room).instantiate()
	for name in ["FloorLayer", "FurnitureLayer", "Gameplay"]:
		translated.get_node(name).position += Vector2(64, 32)
	ProjectSettings.set_setting("gameplay/maps/room", pack(translated))
	var view := MapView.new()
	root.add_child(view)
	check(view.load_location("room"), "translated tile layers and nested markers validate")
	check(view.native_point(Vector2(6, 5)) == Vector2(168, 120), "tile transforms determine rendering coordinates")
	view.queue_free()
	await process_frame
	var missing_floor: Node2D = load(original_room).instantiate()
	missing_floor.get_node("FloorLayer").free()
	ProjectSettings.set_setting("gameplay/maps/room", pack(missing_floor))
	view = MapView.new()
	root.add_child(view)
	check(not view.load_location("room") and str(view.layout_errors).contains("FloorLayer"), "missing floor layer produces a configuration message")
	view.queue_free()
	await process_frame
	var wrong_root := Control.new()
	var invalid_scene := PackedScene.new()
	invalid_scene.pack(wrong_root)
	wrong_root.free()
	ProjectSettings.set_setting("gameplay/maps/room", invalid_scene)
	view = MapView.new()
	root.add_child(view)
	check(not view.load_location("room") and str(view.layout_errors).contains("Node2D"), "invalid map root produces a configuration message")
	view.queue_free()
	await process_frame
	ProjectSettings.set_setting("gameplay/maps/room", original_room)
	ProjectSettings.set_setting("gameplay/maps/store", original_store)
	account.restore()
	print("MAP MARKERS RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
