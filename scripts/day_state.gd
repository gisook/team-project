extends RefCounted

const ACCOUNT_PATH := "user://active_account.json"
const ROOM_SCENE := "res://scenes/room.tscn"
const GAME_SCENE := "res://scenes/game.tscn"


static func set_account(username: String) -> void:
	# 로그인 토큰/비밀번호는 저장하지 않습니다. 로컬 세이브 구분용 식별자만 저장합니다.
	var file := FileAccess.open(ACCOUNT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("로컬 사용자 구분 파일을 저장하지 못했습니다.")
		return
	file.store_string(JSON.stringify({"username": username}))
	file.close()


static func _save_path() -> String:
	var username := "guest"
	if FileAccess.file_exists(ACCOUNT_PATH):
		var file := FileAccess.open(ACCOUNT_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				username = str(parsed.get("username", "guest"))
	return "user://day_progress_%s.json" % username.sha256_text().substr(0, 16)


static func default_state() -> Dictionary:
	return {
		"day": 1,
		"period": "morning",
		"status": "room",
		"active_dialogue_id": "",
		"schedule_start_id": ""
	}


static func load_state() -> Dictionary:
	var path := _save_path()
	if not FileAccess.file_exists(path):
		return default_state()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return default_state()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return default_state()
	var state: Dictionary = parsed as Dictionary
	var period := str(state.get("period", "morning"))
	if period not in ["morning", "afternoon", "night"]:
		period = "morning"
	var active_id := str(state.get("active_dialogue_id", ""))
	return {
		"day": maxi(1, int(state.get("day", 1))),
		"period": period,
		"status": "store" if str(state.get("status", "room")) == "store" else ("dialogue" if (str(state.get("status", "room")) == "dialogue" and not active_id.is_empty()) else "room"),
		"active_dialogue_id": active_id,
		"schedule_start_id": str(state.get("schedule_start_id", "")),
		"customers_done": state.get("customers_done", []) if state.get("customers_done", []) is Array else [],
		"shift_id": str(state.get("shift_id", ""))
	}


static func save_state(state: Dictionary) -> bool:
	var file := FileAccess.open(_save_path(), FileAccess.WRITE)
	if file == null:
		push_error("일차 저장에 실패했습니다.")
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	return true


static func start_schedule(id: String) -> bool:
	var state := load_state()
	if str(state["status"]) != "room" or str(state["period"]) == "night":
		return false
	state["status"] = "dialogue"
	state["active_dialogue_id"] = id
	state["schedule_start_id"] = id
	return save_state(state)


static func set_active_dialogue(id: String) -> bool:
	var state := load_state()
	if str(state["status"]) != "dialogue":
		return false
	state["active_dialogue_id"] = id
	return save_state(state)


static func finish_schedule() -> bool:
	var state := load_state()
	if str(state["status"]) not in ["dialogue", "store"]:
		return false
	if str(state["status"]) == "store":
		for customer in ["counter", "shelf", "fridge"]:
			if customer not in state.get("customers_done", []):
				return false
	state["status"] = "room"
	state["customers_done"] = []
	state["active_dialogue_id"] = ""
	state["schedule_start_id"] = ""
	if str(state["period"]) == "morning":
		state["period"] = "afternoon"
	elif str(state["period"]) == "afternoon":
		state["period"] = "night"
	return save_state(state)


static func sleep_and_save() -> bool:
	var state := load_state()
	if str(state["period"]) != "night" or str(state["status"]) != "room":
		return false
	state["day"] = int(state["day"]) + 1
	state["period"] = "morning"
	state["active_dialogue_id"] = ""
	state["schedule_start_id"] = ""
	return save_state(state)


static func abort_schedule() -> bool:
	var state := load_state()
	state["status"] = "room"
	state["active_dialogue_id"] = ""
	state["schedule_start_id"] = ""
	return save_state(state)


static func start_store_shift() -> bool:
	var state := load_state()
	if str(state["status"]) != "room" or str(state["period"]) == "night":
		return false
	state["status"] = "store"
	state["customers_done"] = []
	state["shift_id"] = "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	return save_state(state)


static func complete_customer(id: String) -> bool:
	var state := load_state()
	if str(state["status"]) != "store":
		return false
	var completed: Array = state.get("customers_done", [])
	if id not in completed:
		completed.append(id)
	state["customers_done"] = completed
	return save_state(state)
