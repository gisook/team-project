extends "res://tests/test_world.gd"

# Use the production HTTPRequest path against a loopback server in the protocol test.
func _send_recordings(entries: Array[Dictionary]) -> bool:
	return uploader.upload_recordings(entries)
