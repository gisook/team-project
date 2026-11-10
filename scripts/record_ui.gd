extends Control
class_name VoiceRecordUI

signal recording_started
signal recording_saved(file_path: String)
signal recording_failed(message: String)
signal file_uploaded(file_path: String, response_text: String)
signal upload_progress(completed_count: int, total_count: int)
signal upload_finished(success: bool, response_text: String)

# 기존 서버는 WAV 파일 1개를 multipart/form-data의 file 필드로 받습니다.
# 녹음은 각 대화에서 로컬 파일로 저장하고, 마지막 대화에서 이 API로 순차 전송합니다.
const SERVER_URL := "http://121.188.96.177:8000/upload"

enum RecordState { IDLE, READY, RECORDING, SAVING, UPLOADING }

@onready var record_button: Button = $RecordButton
@onready var microphone: AudioStreamPlayer = $Microphone
@onready var http_request: HTTPRequest = $HTTPRequest

var record_effect: AudioEffectRecord
var state: RecordState = RecordState.IDLE
var save_path: String = ""

var upload_queue: Array[Dictionary] = []
var upload_index: int = 0
var upload_responses: Array[String] = []


func _ready() -> void:
	# 접속 불가 서버 때문에 마지막 대화 완료 화면이 무기한 멈추지 않게 합니다.
	http_request.timeout = 12.0
	record_button.hide()
	record_button.disabled = true

	var bus_index: int = AudioServer.get_bus_index("Record")
	if bus_index == -1:
		push_error("오디오 버스 'Record'가 없습니다.")
		return

	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectRecord:
			record_effect = effect as AudioEffectRecord
			break

	if record_effect == null:
		push_error("Record 버스에 AudioEffectRecord 효과가 없습니다.")
		return

	record_effect.format = AudioStreamWAV.FORMAT_16_BITS
	record_effect.set_recording_active(false)
	microphone.stream = AudioStreamMicrophone.new()
	microphone.bus = &"Record"
	microphone.play()

	http_request.request_completed.connect(_on_upload_completed)
	print("마이크 녹음 준비 완료")


# game.gd에서 선택지에 맞는 고유한 WAV 저장 경로를 지정합니다.
func set_save_path(path: String) -> void:
	save_path = path


# 선택지를 고른 경우에만 녹음 버튼을 표시합니다.
func set_choice_ready(enabled: bool) -> void:
	if state == RecordState.RECORDING or state == RecordState.SAVING or state == RecordState.UPLOADING:
		return

	if not enabled:
		state = RecordState.IDLE
		record_button.hide()
		record_button.disabled = true
		return

	record_button.show()
	if record_effect == null or save_path.is_empty():
		record_button.text = "마이크/저장 경로 확인"
		record_button.disabled = true
		return

	state = RecordState.READY
	record_button.text = "녹음 시작"
	record_button.disabled = false


func _on_record_button_pressed() -> void:
	if record_effect == null:
		return

	match state:
		RecordState.READY:
			record_effect.set_recording_active(true)
			state = RecordState.RECORDING
			record_button.text = "녹음 종료 및 저장"
			recording_started.emit()
		RecordState.RECORDING:
			# 기존 코드처럼 데이터를 먼저 얻은 다음 녹음 효과를 비활성화합니다.
			var recording: AudioStreamWAV = record_effect.get_recording()
			record_effect.set_recording_active(false)
			state = RecordState.SAVING
			record_button.disabled = true
			record_button.text = "WAV 저장 중..."
			_save_recording(recording)


func _save_recording(recording: AudioStreamWAV) -> void:
	if recording == null or recording.get_data().is_empty():
		_fail_recording("녹음된 음성 데이터가 없습니다.")
		return
	if save_path.is_empty():
		_fail_recording("녹음 저장 경로가 지정되지 않았습니다.")
		return

	var folder_path: String = save_path.get_base_dir()
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(folder_path)
	)
	if mkdir_error != OK:
		_fail_recording("녹음 폴더 생성 실패 (오류 %d)" % mkdir_error)
		return

	var save_error: Error = recording.save_to_wav(save_path)
	if save_error != OK:
		_fail_recording("WAV 저장 실패 (오류 %d)" % save_error)
		return
	if not FileAccess.file_exists(save_path):
		_fail_recording("저장된 WAV 파일을 찾을 수 없습니다.")
		return

	var saved_path: String = save_path
	state = RecordState.IDLE
	record_button.hide()
	record_button.disabled = true
	print("녹음 저장 완료: ", ProjectSettings.globalize_path(saved_path))
	recording_saved.emit(saved_path)


# 저장된 WAV 목록을 받아 서버에 하나씩 전송합니다.
# 성공한 녹음은 game.gd에서 파일별로 기록하므로 재시도 시 제외됩니다.
func upload_recordings(recordings: Array[Dictionary]) -> bool:
	if state == RecordState.RECORDING or state == RecordState.SAVING or state == RecordState.UPLOADING:
		return false
	if recordings.is_empty():
		return false

	upload_queue = recordings.duplicate(true)
	upload_index = 0
	upload_responses.clear()
	state = RecordState.UPLOADING
	record_button.hide()
	record_button.disabled = true
	_upload_next()
	return true


func _upload_next() -> void:
	if state != RecordState.UPLOADING:
		return
	if upload_index >= upload_queue.size():
		var summary: String = "\n".join(upload_responses)
		state = RecordState.IDLE
		upload_finished.emit(true, summary)
		return

	var entry: Dictionary = upload_queue[upload_index]
	var path: String = str(entry.get("path", ""))
	if not FileAccess.file_exists(path):
		_fail_upload("WAV 파일이 존재하지 않습니다: " + path)
		return
	var wav_data: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if wav_data.is_empty():
		_fail_upload("WAV 파일이 비어 있거나 읽을 수 없습니다: " + path)
		return

	# 기존 서버의 file 필드를 유지합니다. 파일 이름에 순서가 기록됩니다.
	var filename: String = "%s_%s" % [path.get_base_dir().get_file(), path.get_file()]
	var boundary: String = "----GodotAudioBatch_%d_%d" % [Time.get_ticks_usec(), upload_index]
	var body := PackedByteArray()
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array((
		"Content-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n" % filename
	).to_utf8_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
	body.append_array(wav_data)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())

	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=%s" % boundary
	])
	var request_error: Error = http_request.request_raw(
		SERVER_URL, headers, HTTPClient.METHOD_POST, body
	)
	if request_error != OK:
		_fail_upload("업로드 요청 실패 (오류 %d): %s" % [request_error, filename])


func _on_upload_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if state != RecordState.UPLOADING or upload_index >= upload_queue.size():
		return

	var entry: Dictionary = upload_queue[upload_index]
	var path: String = str(entry.get("path", ""))
	var response_text: String = body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_fail_upload("서버 통신 실패 (%s, result=%d, HTTP=%d)\n%s" % [
			path.get_file(), result, response_code, response_text
		])
		return

	upload_responses.append("%d. %s: %s" % [
		upload_index + 1, path.get_file(), response_text.substr(0, 350)
	])
	upload_index += 1
	# 한 파일이 성공한 즉시 game.gd에서 미전송 목록을 저장합니다.
	file_uploaded.emit(path, response_text)
	upload_progress.emit(upload_index, upload_queue.size())
	# HTTPRequest는 완료 콜백을 빠져나오기 전에 바로 재요청하면 ERR_BUSY가 날 수 있습니다.
	call_deferred("_upload_next")


func _fail_recording(message: String) -> void:
	push_error(message)
	state = RecordState.READY
	record_button.show()
	record_button.disabled = record_effect == null
	record_button.text = "다시 녹음"
	recording_failed.emit(message)


func _fail_upload(message: String) -> void:
	push_error(message)
	state = RecordState.IDLE
	upload_finished.emit(false, message)
