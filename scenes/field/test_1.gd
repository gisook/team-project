extends Node2D

const SERVER_URL = "http://127.0.0.1:8000/api/pronunciation/assess"  # 실기기 테스트 시 PC의 IP로 변경
const NEXT_SCENE = "res://scenes/field/myroom.tscn"

var pending_count: int = 0      # 아직 응답을 받지 못한 요청 수
var results: Array = []         # 받은 평가 결과 모음

@onready var loading_label = get_node_or_null("LoadingLabel")  # 선택: 로딩 문구용 Label
@onready var send_button = get_node_or_null("Button")          # 선택: 중복 클릭 방지용

func _ready() -> void:
	if loading_label:
		loading_label.visible = false


func _on_button_pressed() -> void:
	if pending_count > 0:
		return  # 전송 중 중복 클릭 방지

	var records: Array = Record.session_records.duplicate()
	if records.is_empty():
		_go_next_scene()
		return

	print("일정 종료! 누적된 음성 데이터를 서버로 전송합니다...")
	_set_loading(true)
	pending_count = records.size()
	results.clear()

	for record_data in records:
		send_audio_to_server(record_data)


func _set_loading(is_loading: bool) -> void:
	if send_button:
		send_button.disabled = is_loading
	if loading_label:
		loading_label.visible = is_loading
		loading_label.text = "발음 평가 중입니다..."


# 요청 하나가 끝날 때마다 호출됨. 결과가 없으면 res는 null
func _on_one_request_done(res, file_name: String) -> void:
	if res != null:
		results.append({"file": file_name, "result": res})
		print("[", file_name, "] 정확도: ", res["accuracy_score"],
			" / 유창성: ", res["fluency_score"],
			" / 완전성: ", res["completeness_score"],
			" / 종합: ", res["pron_score"])
	else:
		print("[", file_name, "] 평가 실패")

	pending_count -= 1
	if pending_count <= 0:
		_on_all_requests_done()


func _on_all_requests_done() -> void:
	print("모든 발음 평가 완료. 결과 개수: ", results.size())

	# 결과를 Autoload(Record)에 넘겨 다음 씬에서 쓸 수 있게 합니다.
	Record.evaluation_results = results  # Record에 var evaluation_results: Array = [] 선언 필요
	Record.session_records.clear()
	Record.record_counter = 0

	load("res://scenes/field/print_score.gd").set_results(results)
	get_tree().change_scene_to_file("res://scenes/field/print_score.tscn")


func _go_next_scene() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE)


# 단일 음성 파일과 문장, 언어 코드를 서버로 전송. 완료 시 on_done(res, file_name) 호출
func send_audio_to_server(data: Dictionary) -> void:
	var file_name: String = data["file_path"].get_file()
	var file_bytes = FileAccess.get_file_as_bytes(data["file_path"])
	if file_bytes.size() == 0:
		print("파일을 읽을 수 없습니다: ", data["file_path"])
		_on_one_request_done(null, file_name)
		return

	var boundary = "GodotUploadBoundary7MA4YWxk"
	var body = PackedByteArray()

	# -- reference_text --
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"reference_text\"\r\n\r\n".to_utf8_buffer())
	body.append_array((str(data["text"]) + "\r\n").to_utf8_buffer())

	# -- locale --
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"locale\"\r\n\r\n".to_utf8_buffer())
	body.append_array((str(data.get("locale", "en-US")) + "\r\n").to_utf8_buffer())

	# -- audio --
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"audio\"; filename=\"" + file_name + "\"\r\n").to_utf8_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())

	var headers = ["Content-Type: multipart/form-data; boundary=" + boundary]

	var http_request = HTTPRequest.new()
	http_request.timeout = 60.0  # 응답이 없어도 로딩이 영원히 멈추지 않도록 제한 시간 설정
	Record.add_child(http_request)

	# 람다는 이 씬이 살아 있는 동안 실행된다. 응답이 올 때까지 씬을 유지하므로 안전하다.
	http_request.request_completed.connect(
		func(result, response_code, _headers, resp_body):
			http_request.queue_free()
			if not is_inside_tree():
				return  # 씬이 이미 사라진 예외 상황 방어
			var text = resp_body.get_string_from_utf8()
			if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
				print("전송 실패: ", file_name, " / 결과: ", result, " / 코드: ", response_code, " / 응답: ", text)
				_on_one_request_done(null, file_name)
				return
			var res = JSON.parse_string(text)
			if res == null:
				print("응답 JSON 파싱 실패: ", text)
				_on_one_request_done(null, file_name)
				return
			_on_one_request_done(res, file_name)
	)

	var err = http_request.request_raw(SERVER_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("요청 시작 실패: ", err, " / ", file_name)
		http_request.queue_free()
		_on_one_request_done(null, file_name)
