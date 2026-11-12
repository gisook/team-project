extends RefCounted

const DayState = preload("res://scripts/day_state.gd")
var original: String
var existed: bool

func _init() -> void:
	existed = FileAccess.file_exists(DayState.ACCOUNT_PATH)
	if existed: original = FileAccess.get_file_as_string(DayState.ACCOUNT_PATH)

func restore() -> void:
	if existed:
		var file := FileAccess.open(DayState.ACCOUNT_PATH, FileAccess.WRITE)
		if file != null: file.store_string(original)
	else:
		DirAccess.remove_absolute(DayState.ACCOUNT_PATH)
