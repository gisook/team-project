extends SceneTree

const DayState = preload("res://scripts/day_state.gd")
const HttpWorld = preload("res://tests/http_world.gd")
const Fixture = preload("res://tests/schedule_fixture.gd")
var failures := 0
var server: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func wait_requests(count: int) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while server.requests.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame
	check(server.requests.size() >= count, "received HTTP upload %d" % count)
	if server.requests.size() < count:
		for connection in server.connections:
			print("HTTP diagnostic: bytes=", connection["bytes"].size(), " peer_status=", connection["peer"].get_status())
		print("HTTP diagnostic: connections=", server.connections.size())
	return server.requests.size() >= count

func wait_phase(world: Control, phase: String) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while world.submission_phase != phase and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.submission_phase == phase, "HTTP response leads to phase: " + phase)

func _run() -> void:
	var account := preload("res://tests/account_fixture.gd").new()
	DayState.set_account("http_submission_%d" % Time.get_ticks_usec())
	Fixture.ready_shift()
	server = preload("res://tests/local_upload_server.gd").new()
	root.add_child(server)
	var port: int = server.start()
	check(port > 0, "loopback upload server starts")
	if port <= 0:
		account.restore()
		quit(1)
		return
	var world := HttpWorld.new()
	root.add_child(world)
	world.set_process(false)
	Fixture.add_recordings(world)
	world.uploader.upload_url = "http://127.0.0.1:%d/upload" % port
	check(server.requests.is_empty(), "saving WAVs does not submit automatically")
	world._finish_shift()
	if not await wait_requests(1):
		account.restore()
		quit(1)
		return
	var request: Dictionary = server.requests[0]
	check(request["part_headers"].contains('name="file"') and request["has_wav"], "production request carries a WAV in multipart file field")
	await create_timer(0.15).timeout
	check(world.submission_phase == "uploading" and world.continue_button.disabled, "UI waits for delayed real HTTP response")
	server.respond(0, 200, '{"message":"first received"}')
	await wait_requests(2)
	check(world.current_responses.size() == 1, "raw server response retained after first WAV")
	server.respond(1, 500, '{"error":"simulated failure"}')
	await wait_phase(world, "failed")
	check(world._current_shift_pending().size() == 2, "HTTP failure keeps unacknowledged recordings")
	world._finish_shift()
	await wait_requests(3)
	var failed_name: String = server.requests[1]["part_headers"].get_slice('filename="', 1).get_slice('"', 0)
	var retry_name: String = server.requests[2]["part_headers"].get_slice('filename="', 1).get_slice('"', 0)
	check(failed_name == retry_name and retry_name.ends_with("shelf.wav"), "retry starts with failed WAV rather than the successful one")
	server.respond(2, 200, '{"message":"second received"}')
	await wait_requests(4)
	server.respond(3, 200, '{"message":"third received"}')
	await wait_phase(world, "result")
	check(world.location == "store" and world._current_shift_pending().is_empty(), "all real HTTP responses show results without automatic return")
	check(world.score_label.text == "점수: 0점", "result has the score display placeholder")
	world._on_continue_pressed()
	await create_timer(0.7).timeout
	check(world.location == "room" and world.state["period"] == "afternoon", "continue returns home after real uploads")
	# A timeout is also a failure, never a fake score or automatic return.
	world._start_shift()
	await create_timer(0.7).timeout
	for id in ["counter", "shelf", "fridge"]: DayState.complete_customer(id)
	world._enter_location("store")
	Fixture.add_recordings(world)
	world.uploader.http_request.timeout = 0.2
	world._finish_shift()
	await wait_requests(5)
	await wait_phase(world, "failed")
	check(world._current_shift_pending().size() == 3 and world.score_label.text == "점수: —", "timeout preserves WAVs without fabricating a result")
	world.queue_free()
	server.queue_free()
	await process_frame
	account.restore()
	print("UPLOAD PROTOCOL RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
