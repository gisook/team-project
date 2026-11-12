extends SceneTree

const DayState = preload("res://scripts/day_state.gd")
const TestWorld = preload("res://tests/test_world.gd")
var world: Control
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _run() -> void:
	var account := preload("res://tests/account_fixture.gd").new()
	DayState.set_account("top_down_integration_%d" % Time.get_ticks_usec())
	check(DayState.save_state(DayState.default_state()), "isolated account save")
	world = TestWorld.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(world)
	await process_frame
	world.set_process(false)
	check(world.location == "room" and world.player_cell == Vector2i(5, 5), "start beside bed")
	check(world._blocked(Vector2i(-1, 0)) and world._blocked(Vector2i(16, 15)), "16 by 16 floor bounds")
	check(world._blocked(Vector2i(3, 4)) and world._blocked(Vector2i(11, 4)), "bed and desk collision")
	check(world._interaction_target() == "", "daytime bed cannot be used")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	world._update_movement(0)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_D
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	world._update_movement(0.2)
	check(world.player_cell == Vector2i(6, 5) and world.map.player == Vector2(6, 5), "WASD advances one cell with interpolation")
	world.player_cell = Vector2i(11, 5)
	check(world._interaction_target() == "phone", "phone proximity prompt")
	world.player_cell = Vector2i(5, 5)
	for shift in range(2):
		world._start_shift()
		await create_timer(0.7).timeout
		check(world.location == "store" and world.customers.size() == 3, "shift %d has three customers" % shift)
		check(not DayState.sleep_and_save(), "cannot sleep while working")
		check(not DayState.finish_schedule(), "cannot end shift before all customers")
		for step in range(250): world._move_customers(0.31)
		var arrived := true
		for c in world.customers:
			arrived = arrived and c["cell"] == c["target"] and not c["moving"]
		check(arrived, "all NPCs pathfind to distinct destinations")
		world.player_cell = Vector2i(4, 5)
		check(world._interaction_target() == "", "counter customer requires cashier side")
		world.player_cell = Vector2i(4, 2)
		check(world._interaction_target() == "npc:0", "cashier side interaction")
		for i in range(3):
			world._start_dialogue(i)
			check(world.recorder.state == VoiceRecordUI.RecordState.IDLE, "recording hidden before answer")
			world._choose(0)
			check(world.recorder.state == VoiceRecordUI.RecordState.READY, "answer enables recording")
			var wav := AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = 44100
			var samples := PackedByteArray()
			samples.resize(8820)
			wav.data = samples
			world.recorder._save_recording(wav)
			await create_timer(1.8).timeout
			check(FileAccess.file_exists(world.recorder.save_path), "response WAV saved")
			if i == 0:
				var resumed := DayState.load_state()
				check("counter" in resumed["customers_done"] and resumed["status"] == "store", "customer progress survives reload")
		await create_timer(0.7).timeout
		check(world.location == "room", "all three responses return home")
		check(world.state["period"] == ("afternoon" if shift == 0 else "night"), "time advances one period")
	check(world.pending.size() == 6 and world.upload_attempts == 2, "six queued WAVs and background upload per shift")
	var restored := TestWorld.new()
	root.add_child(restored)
	restored.set_process(false)
	check(restored.pending.size() == 6, "persisted recording queue readable after reopening")
	restored.queue_free()
	world.player_cell = Vector2i(5, 5)
	check(world._interaction_target() == "bed", "night bed proximity")
	world._sleep()
	await create_timer(3).timeout
	check(world.state["day"] == 2 and world.state["period"] == "morning" and world.player_cell == Vector2i(5, 5), "sleep returns to next morning beside bed")
	check(world._save_pending(), "queue supports atomic overwrite")
	world.queue_free()
	await process_frame
	print("INTEGRATION RESULT: %d failures" % failures)
	account.restore()
	quit(0 if failures == 0 else 1)
