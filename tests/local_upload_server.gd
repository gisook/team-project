extends Node

var tcp := TCPServer.new()
var connections: Array[Dictionary] = []
var requests: Array[Dictionary] = []

func start() -> int:
	var error := tcp.listen(0, "127.0.0.1")
	return tcp.get_local_port() if error == OK else -1

func _process(_delta: float) -> void:
	while tcp.is_connection_available():
		connections.append({"peer": tcp.take_connection(), "bytes": PackedByteArray(), "ready": false})
	for connection in connections:
		if connection["ready"]: continue
		var peer: StreamPeerTCP = connection["peer"]
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			var data: Array = peer.get_data(available)
			if data[0] == OK: connection["bytes"].append_array(data[1])
		var bytes: PackedByteArray = connection["bytes"]
		var header_end := -1
		for i in range(maxi(0, bytes.size() - 3)):
			if bytes[i] == 13 and bytes[i + 1] == 10 and bytes[i + 2] == 13 and bytes[i + 3] == 10:
				header_end = i + 4
				break
		if header_end < 0: continue
		var headers := bytes.slice(0, header_end).get_string_from_utf8()
		var length := 0
		for line in headers.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.get_slice(":", 1).strip_edges())
		if bytes.size() < header_end + length: continue
		connection["ready"] = true
		var body := bytes.slice(header_end)
		var riff := -1
		for i in range(maxi(0, body.size() - 3)):
			if body[i] == 82 and body[i + 1] == 73 and body[i + 2] == 70 and body[i + 3] == 70:
				riff = i
				break
		connection["part_headers"] = body.slice(0, riff if riff >= 0 else 0).get_string_from_utf8()
		connection["has_wav"] = riff >= 0
		requests.append(connection)

func respond(index: int, status: int, text: String) -> void:
	var body := text.to_utf8_buffer()
	var reason := "OK" if status == 200 else "Internal Server Error"
	var headers := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, body.size()]
	var bytes := headers.to_utf8_buffer()
	bytes.append_array(body)
	var peer: StreamPeerTCP = requests[index]["peer"]
	peer.put_data(bytes)

func _exit_tree() -> void:
	for connection in connections:
		connection["peer"].disconnect_from_host()
	tcp.stop()
