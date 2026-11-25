extends TextureProgressBar

const SILENCE_DB: float = -55.0
const FULL_DB: float = -12.0
const RELEASE_PER_SECOND: float = 3.0

var capture: AudioEffectCapture


func _ready() -> void:
	set_process(false)


func set_recording_active(active: bool) -> void:
	value = 0.0
	var can_monitor := active and capture != null
	if can_monitor:
		capture.clear_buffer()
	set_process(can_monitor)


func _process(delta: float) -> void:
	var peak := 0.0
	var frames := capture.get_frames_available()
	if frames > 0:
		for sample in capture.get_buffer(frames):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))

	var level := 0.0
	if peak > 0.0:
		level = clampf(inverse_lerp(SILENCE_DB, FULL_DB, linear_to_db(peak)), 0.0, 1.0)
	value = maxf(level, move_toward(value, 0.0, RELEASE_PER_SECOND * delta))
