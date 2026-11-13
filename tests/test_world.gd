extends "res://scripts/top_down_world.gd"

var upload_attempts := 0
var sent_entries: Array[Dictionary] = []
var uploaded_paths: Array[String] = []

# Exercise local save/recording logic without microphone access or network traffic.
func _build_recorder(_capture: bool) -> VoiceRecordUI:
	var ui := super._build_recorder(false)
	ui.record_effect = AudioEffectRecord.new()
	return ui


func _upload_pending() -> void:
	upload_attempts += 1


func _send_recordings(entries: Array[Dictionary]) -> bool:
	upload_attempts += 1
	sent_entries = entries.duplicate(true)
	uploader.state = VoiceRecordUI.RecordState.UPLOADING
	return true


func complete_test_upload() -> void:
	for entry in sent_entries:
		var path: String = entry["path"]
		uploaded_paths.append(path)
		uploader.file_uploaded.emit(path, "{\"status\":\"received\"}")
	uploader.state = VoiceRecordUI.RecordState.IDLE
	uploader.upload_finished.emit(true, "received")
