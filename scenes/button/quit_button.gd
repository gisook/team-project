extends Button

@export var quit_dialog: ConfirmationDialog

func _ready() -> void:
	pressed.connect(_on_pressed)
	quit_dialog.confirmed.connect(_on_quit_confirmed)

func _on_pressed() -> void:
	quit_dialog.popup_centered()

func _on_quit_confirmed() -> void:
	get_tree().quit()
