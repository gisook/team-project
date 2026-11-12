extends Control

const DayState = preload("res://scripts/day_state.gd")

# 기존 녹음 업로드 서버와 동일한 주소입니다.
const SERVER_URL: String = "http://121.188.96.177:8000"
# 실제 서버에서 요구하는 JSON 필드명
const USERNAME_FIELD: String = "username"
const REGISTER_SCENE_PATH: String = "res://scenes/register.tscn"
const ROOM_SCENE_PATH: String = "res://scenes/room.tscn"

@onready var username_edit: LineEdit = $CenterContainer/Panel/Margin/Content/FormRow/Fields/UsernameEdit
@onready var password_edit: LineEdit = $CenterContainer/Panel/Margin/Content/FormRow/Fields/PasswordEdit
@onready var login_button: Button = $CenterContainer/Panel/Margin/Content/FormRow/LoginButton
@onready var register_button: Button = $CenterContainer/Panel/Margin/Content/RegisterRow/RegisterButton
@onready var status_label: Label = $CenterContainer/Panel/Margin/Content/StatusLabel
@onready var http_request: HTTPRequest = $HTTPRequest

var is_requesting: bool = false
var submitted_username: String = ""


func _ready() -> void:
	http_request.timeout = 15.0
	http_request.request_completed.connect(_on_request_completed)
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	username_edit.text_submitted.connect(_on_username_submitted)
	password_edit.text_submitted.connect(_on_password_submitted)
	username_edit.grab_focus()


func _on_username_submitted(_text: String) -> void:
	password_edit.grab_focus()


func _on_password_submitted(_text: String) -> void:
	_on_login_pressed()


func _on_register_pressed() -> void:
	if is_requesting:
		return
	get_tree().change_scene_to_file(REGISTER_SCENE_PATH)


func _on_login_pressed() -> void:
	if is_requesting:
		return

	var username: String = username_edit.text.strip_edges()
	var password: String = password_edit.text
	if username.is_empty() or password.is_empty():
		status_label.text = "아이디와 비밀번호를 모두 입력해 주세요."
		return

	# 서버의 요청 스키마에 맞는 username/password 전송
	submitted_username = username
	var payload: Dictionary = {"password": password}
	payload[USERNAME_FIELD] = username
	var headers := PackedStringArray(["Content-Type: application/json"])
	_set_requesting(true)
	status_label.text = "로그인 요청 중..."

	var request_error: Error = http_request.request(
		SERVER_URL + "/login",
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
		# HTTP 2xx만으로는 인증 완료를 판정하지 않습니다.
		# 서버가 약속한 JSON 필드와 아이디까지 확인합니다.
		var response_text: String = body.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(response_text)
		if not (parsed is Dictionary):
			status_label.text = "로그인 확인 실패: 서버 응답이 JSON 객체가 아닙니다."
			print("LOGIN VALIDATION FAILED: invalid JSON object")
			return

		var response: Dictionary = parsed as Dictionary
		var message: Variant = response.get("message")
		var user_id: Variant = response.get("user_id")
		var server_username: Variant = response.get("username")

		if message != "로그인 성공":
			status_label.text = "로그인 확인 실패: 성공 메시지가 일치하지 않습니다."
			print("LOGIN VALIDATION FAILED: unexpected message")
			return

		# Godot JSON.parse_string()은 JSON 숫자를 float으로 읽습니다.
		# 예: 서버 {"user_id": 1} -> Godot의 user_id는 1.0 (float)
		var id_valid: bool = false
		if user_id is int or user_id is float:
			var numeric_id: float = float(user_id)
			id_valid = numeric_id > 0.0 and numeric_id == floor(numeric_id)
		elif user_id is String:
			var id_text: String = String(user_id).strip_edges()
			id_valid = id_text.is_valid_int() and id_text.to_int() > 0

		if not id_valid:
			status_label.text = "로그인 확인 실패: 서버의 user_id 값이 올바르지 않습니다."
			print("LOGIN VALIDATION FAILED: invalid user_id type=", typeof(user_id), ", value=", user_id)
			return

		if not (server_username is String) or server_username != submitted_username:
			status_label.text = "로그인 확인 실패: 서버의 username이 일치하지 않습니다."
			print("LOGIN VALIDATION FAILED: mismatched username")
			return

		# 서버의 로그인 승인 응답을 검증했습니다. 비밀번호는 로그에 남기지 않습니다.
		print("LOGIN VERIFIED: user_id=", user_id, ", username=", server_username)
		status_label.text = "로그인 성공: %s" % server_username
		DayState.set_account(server_username)

		var scene_error: Error = get_tree().change_scene_to_file(ROOM_SCENE_PATH)
		if scene_error != OK:
			status_label.text = "로그인 확인 완료, 내 방 열기 실패 (오류: %d)" % scene_error
		return

	var server_message: String = _read_server_error(body)
	print("LOGIN HTTP ", response_code, ": ", server_message)
	if response_code == 401 or response_code == 403:
		status_label.text = "아이디 또는 비밀번호를 확인해 주세요."
	elif server_message.is_empty():
		status_label.text = "로그인에 실패했습니다. (HTTP %d)" % response_code
	else:
		status_label.text = "로그인 실패 (HTTP %d): %s" % [response_code, server_message]


func _set_requesting(busy: bool) -> void:
	is_requesting = busy
	login_button.disabled = busy
	register_button.disabled = busy
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
