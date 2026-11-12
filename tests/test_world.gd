extends "res://scripts/top_down_world.gd"

var upload_attempts := 0

# Exercise local save/recording logic without microphone access or network traffic.
func _build_recorder(_capture: bool) -> VoiceRecordUI:
	var ui := super._build_recorder(false)
	ui.record_effect = AudioEffectRecord.new()
	return ui


func _upload_pending() -> void:
	upload_attempts += 1
