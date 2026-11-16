extends Node

# PC에서 Godot와 서버를 함께 실행할 때 사용합니다.
# 휴대폰 등 실기기에서는 서버 PC의 LAN IP로 변경하세요.
const SERVER_URL: String = \
	"http://127.0.0.1:8000/api/pronunciation/assess"

const RESULT_SCENE: String = \
	"res://scenes/field/print_score.tscn"

const NEXT_SCENE: String = \
	"res://scenes/field/myroom.tscn"

const REQUEST_TIMEOUT: float = 60.0

var pending_count: int = 0
var total_count: int = 0

var results: Array = []

# 실패한 항목은 Record.session_records에 남겨 재시도할 수 있게 합니다.
var failed_records: Array = []

var upload_started: bool = false
var all_requests_finished: bool = false

var loading_label: Label = null


func _ready() -> void:
	# LoadingLabel이 컨테이너 아래에 있어도 찾습니다.
	loading_label = find_child(
		"LoadingLabel",
		true,
		false
	) as Label

	print("")
	print("========== [Loading] 로딩 씬 진입 ==========")
	print("[Loading] 노드 경로: ", get_path())
	print(
		"[Loading] 연결된 스크립트: ",
		get_script().resource_path
	)
	print(
		"[Loading] 녹음 데이터 개수: ",
		Record.session_records.size()
	)
	print(
		"[Loading] 녹음 데이터: ",
		Record.session_records
	)

	if loading_label == null:
		push_warning(
			"[Loading] LoadingLabel을 찾지 못했습니다. "
			+ "Label 이름을 LoadingLabel로 지정하세요. "
			+ "전송 작업은 계속 진행합니다."
		)

	_update_loading_text()

	# 씬 초기화가 끝난 후 전송을 시작합니다.
	call_deferred("_start_upload")


func _start_upload() -> void:
	print("[Loading] _start_upload() 실행")

	if upload_started:
		print("[Loading] 중복 전송 시작을 무시합니다.")
		return

	upload_started = true

	var records: Array = Record.session_records.duplicate(true)

	print("[Loading] 전송 대상 개수: ", records.size())

	if records.is_empty():
		print("[Loading] 전송할 녹음 데이터가 없습니다.")
		_go_next_scene()
		return

	results.clear()
	failed_records.clear()

	total_count = records.size()
	pending_count = total_count

	_update_loading_text()

	for index in range(records.size()):
		var record_data: Variant = records[index]

		print(
			"[Loading] 전송 준비 ",
			index + 1,
			"/",
			total_count,
			": ",
			record_data
		)

		if record_data is Dictionary:
			send_audio_to_server(record_data)
		else:
			push_error(
				"[Loading] 잘못된 녹음 데이터입니다. "
				+ "Dictionary 형식이 필요합니다."
			)

			_on_one_request_done(
				null,
				"잘못된 데이터",
				record_data
			)


func _update_loading_text() -> void:
	if loading_label == null:
		return

	loading_label.visible = true

	if total_count <= 0:
		loading_label.text = "발음 평가를 준비하고 있습니다..."
		return

	var completed_count: int = total_count - pending_count

	loading_label.text = (
		"발음 평가 중입니다...\n"
		+ "%d / %d\n"
		+ "성공: %d / 실패: %d"
	) % [
		completed_count,
		total_count,
		results.size(),
		failed_records.size()
	]


func send_audio_to_server(data: Dictionary) -> void:
	print("[HTTP] send_audio_to_server() 실행")
	print("[HTTP] 서버 주소: ", SERVER_URL)

	var file_path: String = str(data.get("file_path", ""))
	var file_name: String = file_path.get_file()

	# 1. 파일 경로 확인
	if file_path.is_empty():
		push_error("[HTTP] 녹음 파일 경로가 없습니다.")

		_on_one_request_done(
			null,
			"경로 없음",
			data
		)
		return

	print("[HTTP] 파일 경로: ", file_path)

	# 2. 파일 존재 여부 확인
	if not FileAccess.file_exists(file_path):
		push_error(
			"[HTTP] 파일이 존재하지 않습니다: " + file_path
		)

		_on_one_request_done(
			null,
			file_name,
			data
		)
		return

	# 3. 파일 읽기
	var file_bytes: PackedByteArray = \
		FileAccess.get_file_as_bytes(file_path)

	if file_bytes.is_empty():
		push_error(
			"[HTTP] 파일을 읽을 수 없거나 비어 있습니다: "
			+ file_path
		)

		_on_one_request_done(
			null,
			file_name,
			data
		)
		return

	# 4. multipart/form-data 생성
	var boundary: String = (
		"GodotUploadBoundary"
		+ str(Time.get_ticks_usec())
	)

	var body := PackedByteArray()

	# reference_text
	body.append_array(
		("--" + boundary + "\r\n").to_utf8_buffer()
	)

	body.append_array(
		(
			"Content-Disposition: form-data; "
			+ "name=\"reference_text\"\r\n\r\n"
		).to_utf8_buffer()
	)

	body.append_array(
		(
			str(data.get("text", "")) + "\r\n"
		).to_utf8_buffer()
	)

	# locale
	body.append_array(
		("--" + boundary + "\r\n").to_utf8_buffer()
	)

	body.append_array(
		(
			"Content-Disposition: form-data; "
			+ "name=\"locale\"\r\n\r\n"
		).to_utf8_buffer()
	)

	body.append_array(
		(
			str(data.get("locale", "ko-KR")) + "\r\n"
		).to_utf8_buffer()
	)

	# 파일명의 따옴표와 개행을 제거합니다.
	var safe_file_name: String = file_name.replace("\"", "_")
	safe_file_name = safe_file_name.replace("\r", "_")
	safe_file_name = safe_file_name.replace("\n", "_")

	# audio
	body.append_array(
		("--" + boundary + "\r\n").to_utf8_buffer()
	)

	body.append_array(
		(
			"Content-Disposition: form-data; "
			+ "name=\"audio\"; filename=\""
			+ safe_file_name
			+ "\"\r\n"
		).to_utf8_buffer()
	)

	body.append_array(
		"Content-Type: audio/wav\r\n\r\n".to_utf8_buffer()
	)

	body.append_array(file_bytes)

	body.append_array(
		(
			"\r\n--" + boundary + "--\r\n"
		).to_utf8_buffer()
	)

	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=" + boundary
	])

	# 5. HTTPRequest 생성
	# 녹음 파일마다 별도의 HTTPRequest를 사용합니다.
	var http_request := HTTPRequest.new()
	http_request.timeout = REQUEST_TIMEOUT

	add_child(http_request)

	# 6. 응답 콜백 연결
	http_request.request_completed.connect(
		func(
			request_result: int,
			response_code: int,
			_response_headers: PackedStringArray,
			response_body: PackedByteArray
		) -> void:
			print(
				"[HTTP] 응답 콜백 실행 / 파일: ",
				file_name,
				" / 통신 결과: ",
				request_result,
				" / HTTP 상태 코드: ",
				response_code
			)

			http_request.queue_free()

			var response_text: String = \
				response_body.get_string_from_utf8()

			print(
				"[HTTP] 응답 본문 [",
				file_name,
				"]: ",
				response_text
			)

			# 네트워크 통신 실패
			if request_result != HTTPRequest.RESULT_SUCCESS:
				push_error(
					"[HTTP] 네트워크 요청 실패: %s / 결과: %s"
					% [file_name, request_result]
				)

				_on_one_request_done(
					null,
					file_name,
					data
				)
				return

			# 서버가 성공 이외의 상태 코드를 반환
			if response_code < 200 or response_code >= 300:
				push_error(
					"[HTTP] 서버 응답 오류: %s / HTTP %s"
					% [file_name, response_code]
				)

				_on_one_request_done(
					null,
					file_name,
					data
				)
				return

			# JSON 응답 파싱
			var json := JSON.new()
			var parse_error: Error = json.parse(response_text)

			if parse_error != OK:
				push_error(
					"[HTTP] JSON 파싱 실패: %s / %s"
					% [
						file_name,
						json.get_error_message()
					]
				)

				_on_one_request_done(
					null,
					file_name,
					data
				)
				return

			var parsed: Variant = json.data

			if not (parsed is Dictionary):
				push_error(
					"[HTTP] 응답이 JSON 객체 형식이 아닙니다: "
					+ file_name
				)

				_on_one_request_done(
					null,
					file_name,
					data
				)
				return

			# 기존 결과 화면이 사용하는 점수 항목 확인
			var required_keys: Array = [
				"accuracy_score",
				"fluency_score",
				"completeness_score",
				"pron_score"
			]

			for key in required_keys:
				if not parsed.has(key):
					push_error(
						"[HTTP] 응답에 점수 항목이 없습니다: %s / %s"
						% [file_name, key]
					)

					_on_one_request_done(
						null,
						file_name,
						data
					)
					return

			_on_one_request_done(
				parsed,
				file_name,
				data
			),
		CONNECT_ONE_SHOT
	)

	# 7. 요청 시작
	print("[HTTP] 요청 직전 / 파일: ", file_name)
	print("[HTTP] 오디오 크기: ", file_bytes.size(), " bytes")
	print("[HTTP] 전송 본문 크기: ", body.size(), " bytes")

	var err: Error = http_request.request_raw(
		SERVER_URL,
		headers,
		HTTPClient.METHOD_POST,
		body
	)

	print(
		"[HTTP] 요청 시작 반환값: ",
		err,
		" / ",
		error_string(err)
	)

	if err != OK:
		push_error(
			"[HTTP] 요청 시작 실패: %s / %s"
			% [file_name, error_string(err)]
		)

		http_request.queue_free()

		_on_one_request_done(
			null,
			file_name,
			data
		)


# 요청 한 개의 처리가 끝날 때 호출됩니다.
func _on_one_request_done(
	res: Variant,
	file_name: String,
	record_data: Variant
) -> void:
	if res is Dictionary:
		results.append({
			"file": file_name,
			"result": res
		})

		print(
			"[평가 성공] ",
			file_name,
			" / 정확도: ",
			res.get("accuracy_score", "-"),
			" / 유창성: ",
			res.get("fluency_score", "-"),
			" / 완전성: ",
			res.get("completeness_score", "-"),
			" / 종합: ",
			res.get("pron_score", "-")
		)

		# 평가에 성공한 파일만 삭제합니다.
		if record_data is Dictionary:
			_delete_local_file(
				str(record_data.get("file_path", ""))
			)
	else:
		failed_records.append(record_data)

		print(
			"[평가 실패] ",
			file_name,
			" / 녹음 파일과 목록을 유지합니다."
		)

	pending_count -= 1

	print(
		"[Loading] 남은 요청 수: ",
		pending_count
	)

	_update_loading_text()

	if pending_count <= 0:
		_on_all_requests_done()


func _delete_local_file(path: String) -> void:
	if path.is_empty():
		return

	if not FileAccess.file_exists(path):
		return

	var absolute_path: String = path

	if path.begins_with("user://") or path.begins_with("res://"):
		absolute_path = ProjectSettings.globalize_path(path)

	var err: Error = DirAccess.remove_absolute(absolute_path)

	if err != OK:
		push_warning(
			"[파일] 삭제 실패: %s / %s"
			% [path, error_string(err)]
		)
	else:
		print("[파일] 삭제 완료: ", path)


func _on_all_requests_done() -> void:
	if all_requests_finished:
		return

	all_requests_finished = true

	print("========== [Loading] 전체 요청 처리 완료 ==========")
	print("[Loading] 성공: ", results.size())
	print("[Loading] 실패: ", failed_records.size())

	# 이번 전송에서 성공한 결과를 저장합니다.
	Record.evaluation_results = results.duplicate(true)

	# 실패한 항목만 다음 재시도를 위해 남깁니다.
	Record.session_records = failed_records.duplicate(true)

	if failed_records.is_empty():
		Record.record_counter = 0

	if loading_label:
		loading_label.text = (
			"평가 요청 처리 완료\n"
			+ "성공: %d / 실패: %d"
		) % [
			results.size(),
			failed_records.size()
		]

	# 마지막 콜백이 끝난 후 결과 씬으로 이동합니다.
	call_deferred("_open_result_scene")


func _open_result_scene() -> void:
	print("[Loading] 결과 씬으로 이동: ", RESULT_SCENE)

	var err: Error = get_tree().change_scene_to_file(RESULT_SCENE)

	if err != OK:
		push_error(
			"[Loading] 결과 씬 전환 실패: %s / %s"
			% [RESULT_SCENE, error_string(err)]
		)

		if loading_label:
			loading_label.text = (
				"결과 화면으로 이동하지 못했습니다.\n"
				+ error_string(err)
			)


func _go_next_scene() -> void:
	print("[Loading] 녹음 데이터가 없어 다음 씬으로 이동합니다.")

	var err: Error = get_tree().change_scene_to_file(NEXT_SCENE)

	if err != OK:
		push_error(
			"[Loading] 다음 씬 전환 실패: %s / %s"
			% [NEXT_SCENE, error_string(err)]
		)

		if loading_label:
			loading_label.text = (
				"다음 화면으로 이동하지 못했습니다.\n"
				+ error_string(err)
			)
