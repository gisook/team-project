extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var original: Variant = ProjectSettings.get_setting("developer/login_enabled", null)
	var login: Control = load("res://scenes/login.tscn").instantiate()
	login.set_script(preload("res://tests/login_spy.gd"))
	root.add_child(login)
	await process_frame
	ProjectSettings.set_setting("developer/login_enabled", true)
	login.username_edit.text = "도지머스크"
	login.password_edit.text = "12345"
	login._on_login_pressed()
	check(login.entered_account == "도지머스크" and login.server_calls == 0, "developer credentials enter game without server")
	login.entered_account = ""
	login.password_edit.text = "wrong"
	login._on_login_pressed()
	check(login.entered_account.is_empty() and login.server_calls == 0, "wrong developer password rejected locally")
	login.password_edit.text = "12345 "
	login._on_login_pressed()
	check(login.entered_account.is_empty(), "password must match exactly")
	ProjectSettings.set_setting("developer/login_enabled", false)
	login.password_edit.text = "12345"
	login._on_login_pressed()
	check(login.entered_account.is_empty() and login.server_calls == 0, "disabled developer login cannot bypass authentication")
	check(login.status_label.text.contains("비활성화"), "disabled state explained in login screen")
	ProjectSettings.set_setting("developer/login_enabled", null)
	login._on_login_pressed()
	check(login.entered_account.is_empty(), "missing setting defaults to disabled")
	login.username_edit.text = "normal_user"
	login.password_edit.text = "normal_password"
	login._on_login_pressed()
	check(login.server_calls == 1 and login.entered_account.is_empty(), "normal accounts still require server authentication")
	ProjectSettings.set_setting("developer/login_enabled", original)
	login.queue_free()
	await process_frame
	print("DEVELOPER LOGIN RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
