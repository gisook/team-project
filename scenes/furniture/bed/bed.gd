@tool
extends ActFurniture

@export var day_state_script: Script

signal sleep_requested


func act() -> void:
	if day_state_script == null:
		push_warning("Day State Script에 day_state.gd를 지정하세요.")
		return

	var state: Dictionary = day_state_script.load_state()

	if str(state["status"]) != "room":
		print("진행 중인 일정을 먼저 끝내야 합니다.")
		return

	if str(state["period"]) != "night":
		print("밤에만 잘 수 있습니다.")
		return

	if not day_state_script.sleep_and_save():
		push_error("수면 상태를 저장하지 못했습니다.")
		return

	# 다음 날 아침으로 변경된 후 알림
	sleep_requested.emit()

	var next_state: Dictionary = day_state_script.load_state()
	print("잠을 잤습니다. %d일차 아침입니다." % int(next_state["day"]))
