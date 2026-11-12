extends SceneTree

const DayState = preload("res://scripts/day_state.gd")
const TestWorld = preload("res://tests/test_world.gd")

func _initialize() -> void:
	_run.call_deferred()

func _capture(path: String) -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _run() -> void:
	var account := preload("res://tests/account_fixture.gd").new()
	root.size = Vector2i(1094, 730)
	DayState.set_account("visual_review")
	DayState.save_state(DayState.default_state())
	var world := TestWorld.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(world)
	await process_frame
	world.set_process(false)
	await _capture("res://artifacts/room_morning.png")
	world.phone.show()
	await _capture("res://artifacts/phone.png")
	world.phone.hide()
	DayState.start_store_shift()
	world._enter_location("store")
	for i in range(250): world._move_customers(0.31)
	await _capture("res://artifacts/store.png")
	world._start_dialogue(0)
	await _capture("res://artifacts/dialogue.png")
	world._choose(0)
	await _capture("res://artifacts/recording_ready.png")
	world._close_dialogue()
	var state := DayState.load_state()
	state["status"] = "room"
	state["period"] = "night"
	DayState.save_state(state)
	world._enter_location("room")
	await _capture("res://artifacts/room_night.png")
	world.queue_free()
	await process_frame
	account.restore()
	quit()
