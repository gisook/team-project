extends PanelContainer

const ScoreResult = preload("res://scripts/scores/score_result.gd")
const Metric = preload("res://scenes/scores/score_metric.tscn")


func set_result(entry: Dictionary) -> void:
	$Content/FileName.text = str(entry.get("file", "")).get_file()
	$Content/FileName.tooltip_text = str(entry.get("file", ""))
	var result: Variant = entry.get("result")
	var valid := ScoreResult.is_valid(result)
	$Content/Status.text = "평가 완료" if valid else "평가 실패 · 녹음을 보관했습니다. 다시 전송해 주세요."
	for child in $Content/Metrics.get_children():
		child.free()
	for key in ScoreResult.FIELDS:
		var metric := Metric.instantiate()
		$Content/Metrics.add_child(metric)
		metric.set_metric(ScoreResult.FIELDS[key], ScoreResult.format_score(result[key]) if valid else "—")
