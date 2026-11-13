extends SceneTree

const DayState = preload("res://scripts/day_state.gd")
const TestWorld = preload("res://tests/test_world.gd")
const Fixture = preload("res://tests/schedule_fixture.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var account := preload("res://tests/account_fixture.gd").new()
	DayState.set_account("submission_%d" % Time.get_ticks_usec())
	Fixture.ready_shift()
	var world := TestWorld.new()
	root.add_child(world)
	world.set_process(false)
	Fixture.add_recordings(world)
	world.pending.append({"path": "user://older_shift.wav", "shift_id": "older_shift"})
	world._save_pending()
	check(world.upload_attempts == 0 and not world.end_schedule_button.disabled, "reopened finished shift waits for explicit submission")
	world._finish_shift()
	check(world.sent_entries.size() == 3, "only this shift is included in result submission")
	world._on_continue_pressed()
	check(DayState.load_state()["period"] == "morning", "cannot advance period while waiting for response")
	var first: String = world.sent_entries[0]["path"]
	world.uploader.file_uploaded.emit(first, "{\"message\":\"first received\"}")
	world.uploader.state = VoiceRecordUI.RecordState.IDLE
	world.uploader.upload_finished.emit(false, "simulated failure")
	check(world.submission_phase == "failed" and not world.continue_button.disabled, "failed upload offers retry or return")
	check(world._current_shift_pending().size() == 2 and world.current_responses.size() == 1, "successful file retained separately for retry")
	world.queue_free()
	await process_frame
	world = TestWorld.new()
	root.add_child(world)
	world.set_process(false)
	check(world.current_responses.size() == 1 and world._current_shift_pending().size() == 2, "partial server results and remaining WAVs survive restart")
	world._finish_shift()
	check(world.sent_entries.size() == 2, "retry sends only files without successful responses")
	world.complete_test_upload()
	check(world.submission_phase == "result" and world.pending.size() == 1, "old shift remains queued without affecting current results")
	check(world.set_schedule_score(92.5), "future score integration can update and persist score")
	world.queue_free()
	await process_frame
	world = TestWorld.new()
	root.add_child(world)
	world.set_process(false)
	check(world.result_panel.visible and world.score_label.text == "점수: 92.5점", "result screen and score survive restart before returning")
	check(world.upload_attempts == 0 and world.current_responses.size() == 3, "restored results do not resend recordings")
	world._on_continue_pressed()
	world._on_continue_pressed()
	await create_timer(0.7).timeout
	check(world.location == "room" and world.state["period"] == "afternoon", "double return click advances time only once")
	world._start_shift()
	await create_timer(0.7).timeout
	check(world.continue_button.visible and world.end_schedule_button.disabled, "skip is available during an unfinished schedule")
	world.recorder.state = VoiceRecordUI.RecordState.RECORDING
	world._update_schedule_buttons()
	world._on_continue_pressed()
	check(world.continue_button.disabled and DayState.load_state()["status"] == "store", "recording cannot be interrupted by return")
	world.recorder.state = VoiceRecordUI.RecordState.IDLE
	world._on_continue_pressed()
	await create_timer(0.7).timeout
	check(world.location == "room" and world.state["period"] == "night", "skip returns home and advances to next period")
	check(world.pending.size() == 1, "skip preserves untransmitted files")
	world.queue_free()
	await process_frame
	account.restore()
	print("SCHEDULE SUBMISSION RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
