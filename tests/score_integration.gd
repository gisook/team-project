extends SceneTree

const Result = preload("res://scripts/scores/score_result.gd")
const Presenter = preload("res://scripts/scores/score_presenter.gd")
const RecordUI = preload("res://scripts/record_ui.gd")
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
	var score := {"accuracy_score": 0, "fluency_score": 83.25, "completeness_score": "100", "pron_score": 76.5}
	check(Result.is_valid(score), "zero and numeric strings are valid")
	check(Result.from_response("not json") == null, "malformed JSON rejected")
	check(Result.from_response('{"accuracy_score": 90}') == null, "incomplete scores rejected")
	var invalid := score.duplicate()
	invalid["pron_score"] = true
	check(not Result.is_valid(invalid), "boolean score rejected")
	invalid["pron_score"] = INF
	check(not Result.is_valid(invalid), "nonfinite score rejected")
	var ui := RecordUI.new()
	ui.capture_enabled = false
	var button := Button.new()
	button.name = "RecordButton"
	ui.add_child(button)
	var mic := AudioStreamPlayer.new()
	mic.name = "Microphone"
	ui.add_child(mic)
	var http := HTTPRequest.new()
	http.name = "HTTPRequest"
	ui.add_child(http)
	root.add_child(ui)
	var presenter := Presenter.new()
	root.add_child(presenter)
	presenter.bind_uploader(ui)
	ui.upload_started.emit()
	ui.upload_queue = [{"path": "user://sample.wav"}, {"path": "user://failed.wav"}]
	ui.state = VoiceRecordUI.RecordState.UPLOADING
	var accepted: Array[String] = []
	ui.file_uploaded.connect(func(path: String, _text: String) -> void: accepted.append(path))
	ui._on_upload_completed(HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify(score).to_utf8_buffer())
	check(accepted.size() == 1 and presenter.results.size() == 1, "valid response reaches presenter and confirms upload")
	# No deferred next request is run: all network responses are fixtures.
	ui._on_upload_completed(HTTPRequest.RESULT_SUCCESS, 200, [], "{}".to_utf8_buffer())
	check(accepted.size() == 1 and ui.upload_index == 1, "invalid evaluation remains pending for retry")
	check(presenter.screen.is_open and presenter.results.size() == 2, "partial failure opens results screen")
	var cards := presenter.screen.get_node("Root/Margin/Content/Scroll/Cards")
	check(cards.get_child_count() == 2, "one card per evaluated file")
	check(cards.get_child(0).get_node("Content/Metrics").get_child(0).get_node("Value").text == "0", "zero displayed without substitution")
	check(cards.get_child(1).get_node("Content/Metrics").get_child(3).get_node("Value").text == "—", "failure has no invented score")
	await process_frame
	if "--preview" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/score_results.png")
		root.size = Vector2i(480, 640)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/score_results_narrow.png")
	presenter.screen.close()
	check(not presenter.screen.is_open, "close restores game access")
	ui.upload_started.emit()
	check(presenter.results.is_empty(), "new batch clears previous results")
	presenter.show_results()
	check(cards.get_child_count() == 0, "empty result state has no stale cards")
	presenter.free()
	ui.free()
	print("SCORE INTEGRATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
