extends CanvasLayer

# 녹음이 완료되어 창이 닫혔음을 DialogUi 등에 알립니다.
signal record_finished

const SAVE_DIR: String = "user://recorded"
const RECORD_BUS_NAME: String = "Record"
const RECORD_EFFECT_INDEX: int = 0
const METER_EFFECT_INDEX: int = 1
const DEFAULT_LOCALE: String = "ko-KR"

@onready var panel = $Panel
@onready var target_text_label = $Panel/TargetTextLabel
@onready var record_button = $Panel/Button
@onready var mic_player = $MicPlayer
@onready var audio_check = $Panel/AudioCheck

var effect_record: AudioEffectRecord

var is_recording: bool = false

# Loading.gd에서 서버로 전송할 녹음 목록입니다.
# {
#     "file_path": "user://recorded/speech_....wav",
#     "text": "평가할 문장",
#     "locale": "ko-KR"
# }
var session_records: Array = []

# Loading.gd에서 저장하고 print_score.gd에서 읽습니다.
var evaluation_results: Array = []

var record_counter: int = 0


func _ready() -> void:
	panel.visible = false
	_reset_record_button()

	# Record 버스 확인
	var bus_idx: int = AudioServer.get_bus_index(RECORD_BUS_NAME)

	if bus_idx == -1:
		_disable_recording(
			"'%s' 오디오 버스를 찾을 수 없습니다."
			% RECORD_BUS_NAME
		)
		return

	# 녹음 이펙트 존재 여부 확인
	if AudioServer.get_bus_effect_count(bus_idx) <= RECORD_EFFECT_INDEX:
		_disable_recording(
			"'%s' 버스에 AudioEffectRecord를 추가해주세요."
			% RECORD_BUS_NAME
		)
		return

	effect_record = AudioServer.get_bus_effect(
		bus_idx,
		RECORD_EFFECT_INDEX
	) as AudioEffectRecord

	if effect_record == null:
		_disable_recording(
			"'%s' 버스의 첫 번째 이펙트가 AudioEffectRecord가 아닙니다."
			% RECORD_BUS_NAME
		)
		return

	effect_record.set_recording_active(false)
	if AudioServer.get_bus_effect_count(bus_idx) > METER_EFFECT_INDEX:
		audio_check.capture = AudioServer.get_bus_effect(bus_idx, METER_EFFECT_INDEX) as AudioEffectCapture

	if not _ensure_save_directory():
		_disable_recording("녹음 저장 폴더를 만들 수 없습니다.")


# 외부 대화창 등에서 호출합니다.
func show_record_ui(target_text: String) -> void:
	# 이미 녹음 중이면 새 문장으로 덮어쓰지 않습니다.
	if is_recording:
		push_warning("이미 녹음 중입니다.")
		return

	target_text_label.text = target_text

	_reset_record_button()

	if effect_record == null:
		record_button.disabled = true
		record_button.text = "녹음 설정을 확인해주세요"

	panel.visible = true


# 버튼의 pressed 시그널에 연결합니다.
func _on_button_pressed() -> void:
	if effect_record == null:
		push_error("녹음 이펙트가 준비되지 않았습니다.")
		return

	if is_recording:
		_stop_recording_and_save()
	else:
		_start_recording()


func _start_recording() -> void:
	if not _ensure_save_directory():
		record_button.text = "저장 폴더 생성 실패 · 다시 시도"
		return

	is_recording = true

	record_button.text = "녹음 중... (완료하려면 다시 클릭)"
	record_button.modulate = Color(1.0, 0.5, 0.5)

	effect_record.set_recording_active(true)
	audio_check.set_recording_active(true)
	mic_player.play()

	print("녹음 시작됨!")


func _stop_recording_and_save() -> void:
	is_recording = false

	effect_record.set_recording_active(false)
	mic_player.stop()
	audio_check.set_recording_active(false)

	_reset_record_button()

	var recording: AudioStreamWAV = effect_record.get_recording()

	if recording == null:
		_show_recording_error("녹음 데이터를 가져오지 못했습니다.")
		return

	if recording.data.is_empty():
		_show_recording_error(
			"녹음 데이터가 비어 있습니다. 마이크 설정을 확인해주세요."
		)
		return

	if not _ensure_save_directory():
		_show_recording_error("녹음 저장 폴더를 만들 수 없습니다.")
		return

	record_counter += 1

	# 카운터가 초기화되거나 게임을 다시 실행해도
	# 기존 파일과 이름이 겹칠 가능성을 줄입니다.
	var unique_id: String = (
		str(Time.get_unix_time_from_system()).replace(".", "_")
		+ "_"
		+ str(Time.get_ticks_usec())
	)

	var save_path: String = (
		SAVE_DIR
		+ "/speech_"
		+ unique_id
		+ "_"
		+ str(record_counter)
		+ ".wav"
	)

	var err: Error = recording.save_to_wav(save_path)

	if err != OK:
		_show_recording_error(
			"녹음 파일 저장 실패: %s / 오류: %s"
			% [save_path, err]
		)
		return

	# 저장에 성공한 파일만 서버 전송 목록에 추가합니다.
	session_records.append({
		"file_path": save_path,
		"text": target_text_label.text,
		"locale": DEFAULT_LOCALE
	})

	print("녹음 파일 저장 완료: ", save_path)
	print(
		"현재까지 누적된 파일 수: ",
		session_records.size()
	)

	panel.visible = false
	record_finished.emit()


func _ensure_save_directory() -> bool:
	var absolute_dir: String = ProjectSettings.globalize_path(SAVE_DIR)

	if DirAccess.dir_exists_absolute(absolute_dir):
		return true

	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)

	if err != OK:
		push_error(
			"녹음 저장 폴더 생성 실패: %s / 오류: %s"
			% [absolute_dir, err]
		)
		return false

	return true


func _reset_record_button() -> void:
	record_button.text = "녹음 시작"
	record_button.modulate = Color.WHITE
	record_button.disabled = false


func _disable_recording(message: String) -> void:
	push_error(message)

	record_button.disabled = true
	record_button.text = "녹음 설정을 확인해주세요"


func _show_recording_error(message: String) -> void:
	push_error(message)

	# 저장 실패 시 창을 닫거나 완료 시그널을 보내지 않고
	# 다시 녹음할 수 있도록 유지합니다.
	record_button.text = "녹음 실패 · 다시 녹음"
	record_button.modulate = Color.WHITE
	panel.visible = true
