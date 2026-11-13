extends RefCounted

const DayState = preload("res://scripts/day_state.gd")

static func ready_shift() -> void:
	DayState.save_state(DayState.default_state())
	DayState.start_store_shift()
	for id in ["counter", "shelf", "fridge"]: DayState.complete_customer(id)

static func add_recordings(world: Control) -> void:
	var folder := "user://recordings/" + str(world.state["shift_id"])
	DirAccess.make_dir_recursive_absolute(folder)
	for id in ["counter", "shelf", "fridge"]:
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 44100
		var bytes := PackedByteArray()
		bytes.resize(8820)
		wav.data = bytes
		var path: String = folder + "/" + str(id) + ".wav"
		assert(wav.save_to_wav(path) == OK)
		world.pending.append({"path": path, "shift_id": world.state["shift_id"], "dialogue_id": id, "uploaded": false})
	assert(world._save_pending())
