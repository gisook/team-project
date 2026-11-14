extends HBoxContainer


func set_metric(caption: String, value: String) -> void:
	$Caption.text = caption
	$Value.text = value
