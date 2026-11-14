extends CanvasLayer

# 녹음이 완료되어 창이 닫혔음을 다른 스크립트(DialogUi)에 알리는 시그널
signal record_finished 

@onready var panel = $Panel
@onready var target_text_label = $Panel/TargetTextLabel
@onready var record_button = $Panel/Button
@onready var mic_player = $MicPlayer

var effect_record: AudioEffectRecord
var is_recording: bool = false # 현재 녹음 중인지 상태를 추적하는 변수

var session_records: Array = []
var evaluation_results: Array = []
var record_counter: int = 0

func _ready():
	panel.visible = false
	
	# 하단 패널에서 설정했던 Record 버스의 녹음 이펙트를 가져옵니다.
	var bus_idx = AudioServer.get_bus_index("Record")
	effect_record = AudioServer.get_bus_effect(bus_idx, 0)

# 외부(대화창 등)에서 녹음 창을 띄울 때 부르는 함수
func show_record_ui(target_text: String):
	target_text_label.text = target_text
	record_button.text = "녹음 시작" # 처음 열릴 때는 버튼 텍스트를 초기화
	is_recording = false
	panel.visible = true

# 버튼을 눌렀을 때 실행되는 함수 (토글 로직)
func _on_button_pressed():
	if not is_recording:
		# --- [ 1번째 클릭: 녹음 시작 ] ---
		is_recording = true
		record_button.text = "녹음 중... (완료하려면 다시 클릭)"
		record_button.modulate = Color(1, 0.5, 0.5) # 녹음 중 시각적 효과 (붉은색 톤)
		
		effect_record.set_recording_active(true)
		mic_player.play()
		print("녹음 시작됨!")
		
	else:
		# --- [ 녹음 종료 및 고유한 파일명으로 저장 ] ---
		is_recording = false
		record_button.modulate = Color(1, 1, 1)
		effect_record.set_recording_active(false)
		mic_player.stop()
		
		var recording = effect_record.get_recording()
		if recording:
			var save_dir = "res://recorded"
			if not DirAccess.dir_exists_absolute(save_dir):
				DirAccess.make_dir_recursive_absolute(save_dir)
				
			# 2. 파일명이 겹치지 않게 숫자를 증가시켜 저장합니다 (예: speech_1.wav, speech_2.wav)
			record_counter += 1
			var save_path = save_dir + "/speech_" + str(record_counter) + ".wav"
			recording.save_to_wav(save_path)
			
			# 3. 서버에 보낼 데이터를 딕셔너리 형태로 배열에 저장해 둡니다.
			session_records.append({
				"file_path": save_path,
				"text": target_text_label.text,
				"locale": "ko-KR" # 필요한 특정 코드값을 여기에 넣으세요
			})
			print("녹음 완료. 현재까지 누적된 파일 수: ", session_records.size())
			
		panel.visible = false
		record_finished.emit()
