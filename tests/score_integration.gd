extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func _run() -> void:
	var record := root.get_node("Record")
	var saved_records: Array = record.session_records.duplicate(true)
	var saved_results: Array = record.evaluation_results.duplicate(true)
	var saved_counter: int = record.record_counter
	var field: Node2D = load("res://scenes/field/test_1.gd").new()
	root.add_child(field)
	current_scene = field
	field.pending_count = 3
	var score := {"accuracy_score": 0, "fluency_score": 83.25, "completeness_score": 100, "pron_score": 76.5}
	field._on_one_request_done(score, "speech_1.wav")
	check(not field.score_presenter.screen.is_open, "wait for all assessment responses")
	field._on_one_request_done(null, "speech_2.wav")
	field._on_one_request_done({"accuracy_score": 90}, "speech_3.wav")
	check(field.score_presenter.screen.is_open, "actual field callback opens result screen")
	check(current_scene == field, "stay in market until result screen closes")
	check(field.process_mode == Node.PROCESS_MODE_DISABLED, "market movement blocked during results")
	check(record.evaluation_results.size() == 3, "success and failure results passed to Record")
	var cards: Node = field.score_presenter.screen.get_node("Root/Margin/Content/Scroll/Cards")
	check(cards.get_child_count() == 3, "three file cards")
	check(cards.get_child(0).get_node("Content/Metrics").get_child(0).get_node("Value").text == "0", "actual zero score displayed")
	check(cards.get_child(2).get_node("Content/Metrics").get_child(0).get_node("Value").text == "—", "invalid response treated as failure")
	field.score_presenter.screen.close()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/field/myroom.tscn", "close returns to original myroom scene")
	record.session_records = saved_records
	record.evaluation_results = saved_results
	record.record_counter = saved_counter
	print("SCORE INTEGRATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
