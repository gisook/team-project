extends "res://scripts/login.gd"

var entered_account := ""
var server_calls := 0

func _enter_room(username: String) -> void:
	entered_account = username

func _request_server_login(_username: String, _password: String) -> void:
	server_calls += 1
