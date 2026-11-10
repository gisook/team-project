extends Control

const SERVER_URL: String = "http://121.188.96.177:8000"
# 실제 서버에서 요구하는 JSON 필드명
const USERNAME_FIELD: String = "username"
const LOGIN_SCENE_PATH: String = "res://scenes/login.tscn"

@onready var username_edit: LineEdit = $CenterContainer/Panel/Margin/Content/FormRow/Fields/UsernameEdit
@onready var password_edit: LineEdit = $CenterContainer/Panel/Margin/Content/FormRow/Fields/PasswordEdit
@onready var complete_button: Button = $CenterContainer/Panel/Margin/Content/FormRow/CompleteButton
@onready var back_button: Button = $CenterContainer/Panel/Margin/Content/BackRow/BackButton
@onready var status_label: Label = $CenterContainer/Panel/Margin/Content/StatusLabel
@onready var http_request: HTTPRequest = $HTTPRequest

var is_requesting: bool = false


func _ready() -> void:
	http_request.timeout = 15.0
	http_request.request_completed.connect(_on_request_completed)
	complete_button.pressed.connect(_on_complete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	username_edit.text_submitted.connect(_on_username_submitted)
	password_edit.text_submitted.connect(_on_password_submitted)
	username_edit.grab_focus()


func _on_username_submitted(_text: String) -> void:
	password_edit.grab_focus()


func _on_password_submitted(_text: String) -> void:
	_on_complete_pressed()


func _on_back_pressed() -> void:
	if is_requesting:
		return
	get_tree().change_scene_to_file(LOGIN_SCENE_PATH)


func _on_complete_pressed() -> void:
	if is_requesting:
		return

	var username: String = username_edit.text.strip_edges()
	var password: String = password_edit.text
	if username.is_empty() or password.is_empty():
		status_label.text = "아이디와 비밀번호를 모두 입력해 주세요."
		return

	# 서버의 요청 스키마에 맞는 username/password 전송
	var payload: Dictionary = {"password": password}
	payload[USERNAME_FIELD] = username
	var headers := PackedStringArray(["Content-Type: application/json"])
	_set_requesting(true)
	status_label.text = "회원가입 요청 중..."

	var request_error: Error = http_request.request(
		SERVER_URL + "/register",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if request_error != OK:
		_set_requesting(false)
		status_label.text = "요청 시작에 실패했습니다. (오류: %d)" % request_error


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_set_requesting(false)

	if result != HTTPRequest.RESULT_SUCCESS:
		status_label.text = "서버에 연결할 수 없습니다. (통신 오류: %d)" % result
		return

	if response_code >= 200 and response_code < 300:
		# 실패 응답일 때는 화면을 유지하여 오류를 확인할 수 있게 합니다.
		var scene_error: Error = get_tree().change_scene_to_file(LOGIN_SCENE_PATH)
		if scene_error != OK:
			status_label.text = "회원가입 성공, 로그인 화면 열기 실패 (오류: %d)" % scene_error
		return

	var server_message: String = _read_server_error(body)
	print("REGISTER HTTP ", response_code, ": ", server_message)
	if response_code == 409:
		status_label.text = "이미 사용 중인 아이디입니다."
	elif server_message.is_empty():
		status_label.text = "회원가입에 실패했습니다. (HTTP %d)" % response_code
	else:
		status_label.text = "회원가입 실패 (HTTP %d): %s" % [response_code, server_message]


func _set_requesting(busy: bool) -> void:
	is_requesting = busy
	complete_button.disabled = busy
	back_button.disabled = busy
	username_edit.editable = not busy
	password_edit.editable = not busy


# 서버의 검증 오류 메시지에서 필드명과 이유만 추출합니다.
# FastAPI의 detail 배열 내부 input 항목은 비밀번호를 포함할 수 있어 로그에 출력하지 않습니다.
func _read_server_error(body: PackedByteArray) -> String:
	var response_text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if not (parsed is Dictionary):
		return "서버 응답 내용을 확인할 수 없습니다."

	var response: Dictionary = parsed as Dictionary
	for key in ["detail", "message", "error"]:
		if not response.has(key):
			continue
		var item: Variant = response[key]
		if item is String:
			return String(item).substr(0, 250)
		if item is Array:
			var parts: PackedStringArray = PackedStringArray()
			for issue in item:
				if issue is Dictionary:
					var field_name: String = ""
					var location: Variant = issue.get("loc", [])
					if location is Array:
						var path_parts: PackedStringArray = PackedStringArray()
						for loc_part in location:
							path_parts.append(str(loc_part))
						field_name = ".".join(path_parts)
					var reason: String = str(issue.get("msg", "입력값 오류"))
					parts.append((field_name + ": " if not field_name.is_empty() else "") + reason)
				if parts.size() >= 3:
					break
			if not parts.is_empty():
				return " / ".join(parts).substr(0, 250)
		if item is Dictionary:
			return str(item.get("message", item.get("msg", "서버가 요청을 거부했습니다."))).substr(0, 250)
	return "서버가 요청을 거부했지만 오류 설명을 보내지 않았습니다."
