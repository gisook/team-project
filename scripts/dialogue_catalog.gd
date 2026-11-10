extends RefCounted

# 예시 대화만 교체합니다. 사용자가 수정/추가한 대화는 그대로 보존합니다.
const FILE_PATH := "user://dialogues.json"


static func default_dialogues() -> Array[Dictionary]:
	return [
		{
			"id": "morning_class_1", "period": "morning", "schedule_start": true,
			"title": "09:00 전공 수업에서 발표하기",
			"question": "전공 수업 시간입니다. 교수님이 묻습니다.\n\"이번 팀 프로젝트가 어떤 프로젝트인지 소개해 볼까요?\"",
			"choices": [
				"저희 팀은 말하기 연습을 돕는 게임을 만들고 있습니다.",
				"마이크를 이용해 대화 연습을 할 수 있는 게임을 개발하고 있습니다."
			], "next_id": "morning_class_2"
		},
		{
			"id": "morning_class_2", "period": "morning", "schedule_start": false,
			"title": "전공 수업: 질문에 답하기",
			"question": "교수님이 이어서 질문합니다.\n\"그 게임을 통해 무엇을 확인할 수 있나요?\"",
			"choices": [
				"발화를 녹음해 말하기 연습 결과를 확인할 수 있습니다.",
				"연습한 내용을 저장하고 이전 기록과 비교할 수 있습니다."
			], "next_id": ""
		},
		{
			"id": "morning_cafe_1", "period": "morning", "schedule_start": true,
			"title": "09:30 학교 앞 카페에서 주문하기",
			"question": "등교길에 카페에 들렀습니다. 직원이 말합니다.\n\"어서 오세요. 어떤 음료로 드릴까요?\"",
			"choices": [
				"아이스 아메리카노 한 잔 주세요.",
				"따뜻한 카페라테 한 잔 부탁드립니다."
			], "next_id": "morning_cafe_2"
		},
		{
			"id": "morning_cafe_2", "period": "morning", "schedule_start": false,
			"title": "카페에서 주문 마무리하기",
			"question": "직원이 다시 묻습니다.\n\"매장에서 드시나요, 포장해 드릴까요?\"",
			"choices": [
				"포장해 주세요. 지금 학교에 가야 해서요.",
				"매장에서 마시고 갈게요. 감사합니다."
			], "next_id": ""
		},
		{
			"id": "morning_house_1", "period": "morning", "schedule_start": true,
			"title": "10:30 집주인에게 수리 문의하기",
			"question": "자취방 싱크대에서 물이 조금씩 새고 있습니다. 집주인이 전화를 받습니다.\n\"네, 무슨 일로 연락하셨나요?\"",
			"choices": [
				"안녕하세요. 싱크대 아래에서 물이 새서 연락드렸습니다.",
				"안녕하세요. 주방 수도를 점검받을 수 있을까요?"
			], "next_id": "morning_house_2"
		},
		{
			"id": "morning_house_2", "period": "morning", "schedule_start": false,
			"title": "집주인과 방문 시간 정하기",
			"question": "집주인이 묻습니다.\n\"확인하러 가려고 하는데, 언제 집에 계시나요?\"",
			"choices": [
				"오늘 오후 여섯 시 이후에는 집에 있습니다.",
				"내일 오전에 방문해 주실 수 있을까요?"
			], "next_id": ""
		},
		{
			"id": "afternoon_team_1", "period": "afternoon", "schedule_start": true,
			"title": "14:00 팀 프로젝트 회의",
			"question": "학교 회의실에서 팀원이 묻습니다.\n\"이번 주까지 어떤 부분을 맡아서 할 수 있어?\"",
			"choices": [
				"제가 게임의 대화 선택 화면을 구현할게요.",
				"저는 녹음 데이터를 저장하는 부분을 확인해 볼게요."
			], "next_id": "afternoon_team_2"
		},
		{
			"id": "afternoon_team_2", "period": "afternoon", "schedule_start": false,
			"title": "팀 프로젝트: 의견 설명하기",
			"question": "팀원이 덧붙입니다.\n\"테스트는 어떤 순서로 진행하는 게 좋을까?\"",
			"choices": [
				"먼저 녹음 기능을 확인하고, 그다음 결과 화면을 점검하자.",
				"각자 만든 기능을 합친 뒤 전체 흐름을 테스트해 보자."
			], "next_id": ""
		},
		{
			"id": "afternoon_market_1", "period": "afternoon", "schedule_start": true,
			"title": "17:00 저녁거리 장보기",
			"question": "자취방에 돌아가는 길, 마트에 들렀습니다. 직원이 묻습니다.\n\"찾으시는 상품이 있으신가요?\"",
			"choices": [
				"계란이랑 우유가 어디에 있는지 알려주실 수 있나요?",
				"혼자 먹을 저녁을 준비하려는데, 작은 채소 포장이 있을까요?"
			], "next_id": "afternoon_market_2"
		},
		{
			"id": "afternoon_market_2", "period": "afternoon", "schedule_start": false,
			"title": "마트에서 계산하기",
			"question": "계산대 직원이 말합니다.\n\"봉투 필요하세요? 영수증도 드릴까요?\"",
			"choices": [
				"봉투는 괜찮고 영수증만 주세요.",
				"봉투 하나 부탁드립니다. 영수증은 괜찮습니다."
			], "next_id": ""
		},
		{
			"id": "afternoon_library_1", "period": "afternoon", "schedule_start": true,
			"title": "15:00 도서관에서 스터디 약속",
			"question": "도서관에서 같은 수업을 듣는 친구를 만났습니다. 친구가 묻습니다.\n\"이번 시험 공부는 어떻게 하고 있어?\"",
			"choices": [
				"강의자료를 먼저 정리하고 기출문제를 풀고 있어.",
				"잘 모르는 부분을 표시해 두고 다시 공부하고 있어."
			], "next_id": "afternoon_library_2"
		},
		{
			"id": "afternoon_library_2", "period": "afternoon", "schedule_start": false,
			"title": "도서관에서 다음 스터디 정하기",
			"question": "친구가 제안합니다.\n\"그럼 다음 주에 같이 공부할까? 언제 시간이 돼?\"",
			"choices": [
				"다음 주 화요일 오후 두 시에 시간 괜찮아.",
				"수요일 수업 끝나고 도서관에서 만나자."
			], "next_id": ""
		}
	]


static func ensure_file() -> void:
	if not FileAccess.file_exists(FILE_PATH):
		write_file(default_dialogues(), 13)
		return
	var file := FileAccess.open(FILE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var items: Variant = parsed.get("dialogues", [])
	if not (items is Array) or items.size() != 3:
		return
	# 이전 샘플 3개가 그대로 남은 경우에만 새로운 기본 일정으로 교체합니다.
	var old_titles := ["1. 식량 위기", "2. 백성의 청원", "3. 마지막 보고"]
	var old_questions := [
		"폐하, 식량이 부족합니다. 어떻게 하시겠습니까?",
		"폐하, 백성들이 세금 감면을 요청합니다.",
		"폐하, 오늘의 마지막 보고입니다."
	]
	for i in range(3):
		if not (items[i] is Dictionary):
			return
		if str(items[i].get("title", "")) != old_titles[i]:
			return
		if str(items[i].get("question", "")) != old_questions[i]:
			return
	write_file(default_dialogues(), 13)


static func read_all() -> Array[Dictionary]:
	ensure_file()
	var result: Array[Dictionary] = []
	var file := FileAccess.open(FILE_PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return result
	var items: Variant = parsed.get("dialogues", [])
	if not (items is Array):
		return result
	for raw in items:
		if raw is Dictionary:
			result.append(raw as Dictionary)
	return result


static func write_file(items: Array[Dictionary], next_id: int) -> bool:
	var file := FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("대화 파일 저장 실패: " + FILE_PATH)
		return false
	file.store_string(JSON.stringify({
		"version": 2,
		"next_id_number": next_id,
		"dialogues": items
	}, "\t"))
	file.close()
	return true
