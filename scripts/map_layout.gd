extends RefCounted

const MarkerScript = preload("res://scripts/gameplay_marker.gd")
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const CUSTOMER_IDS := [&"counter", &"shelf", &"fridge"]
var field: Node2D
var floor_layer: TileMapLayer
var furniture_layer: TileMapLayer
var markers: Array[Marker2D] = []
var anchors: Dictionary = {}
var errors: Array[String] = []


func _init(scene: Node2D, location: String) -> void:
	field = scene
	floor_layer = field.get_node_or_null("FloorLayer") as TileMapLayer
	furniture_layer = field.get_node_or_null("FurnitureLayer") as TileMapLayer
	if floor_layer == null or furniture_layer == null:
		errors.append("FloorLayer와 FurnitureLayer가 필요합니다.")
		return
	_collect(field)
	for marker in markers:
		if marker.role == "passage":
			for x in range(marker.footprint.x):
				for y in range(marker.footprint.y):
					var native := native_point(cell_at(marker) + Vector2i(x, y))
					var tile := furniture_layer.local_to_map(furniture_layer.to_local(field.to_global(native)))
					furniture_layer.erase_cell(tile)
	_validate(location)


func _collect(node: Node) -> void:
	if node is Marker2D and node.get_script() == MarkerScript:
		markers.append(node)
		var key := "%s:%s" % [node.role, node.customer_id]
		if anchors.has(key) and node.role != "passage":
			errors.append("표시점 중복: " + key)
		else:
			anchors[key] = node
	for child in node.get_children(): _collect(child)


func anchor(role: String, id: StringName = &"") -> Marker2D:
	return anchors.get("%s:%s" % [role, id])


func cell_at(node: Node2D) -> Vector2i:
	return floor_layer.local_to_map(floor_layer.to_local(node.global_position))


func cell(role: String, id: StringName = &"") -> Vector2i:
	return cell_at(anchor(role, id))


func native_point(value: Vector2) -> Vector2:
	var local := floor_layer.map_to_local(Vector2i.ZERO) + value * Vector2(floor_layer.tile_set.tile_size)
	return field.to_local(floor_layer.to_global(local))


func rect_for(marker: Marker2D) -> Rect2i:
	return Rect2i(cell_at(marker), marker.footprint)


func near(role: String, player: Vector2i, id: StringName = &"") -> bool:
	var marker := anchor(role, id)
	if marker == null: return false
	var rect := rect_for(marker)
	var nearest := Vector2i(clampi(player.x, rect.position.x, rect.end.x - 1), clampi(player.y, rect.position.y, rect.end.y - 1))
	return absi(nearest.x - player.x) + absi(nearest.y - player.y) <= marker.interaction_distance


func sleep_cell() -> Vector2:
	var bed := anchor("bed")
	var point := bed.get_node_or_null("SleepPoint") as Node2D
	if point != null:
		var local := floor_layer.to_local(point.global_position)
		return (local - floor_layer.map_to_local(Vector2i.ZERO)) / Vector2(floor_layer.tile_set.tile_size)
	return Vector2(rect_for(bed).position) + (Vector2(bed.footprint) - Vector2.ONE) * 0.5


func view_rect() -> Rect2:
	var bounds := anchor("view_bounds")
	if bounds != null:
		return Rect2(field.to_local(bounds.global_position), Vector2(bounds.footprint) * Vector2(floor_layer.tile_set.tile_size))
	var walkable := Rect2i()
	for value in floor_layer.get_used_cells():
		if not _floor_blocked(value):
			walkable = walkable.merge(Rect2i(value, Vector2i.ONE)) if walkable.has_area() else Rect2i(value, Vector2i.ONE)
	var padded := walkable.grow(1)
	return Rect2(native_point(Vector2(padded.position) - Vector2(0.5, 1.5)), Vector2(padded.size + Vector2i(0, 1)) * Vector2(floor_layer.tile_set.tile_size))


func _floor_blocked(value: Vector2i) -> bool:
	var data := floor_layer.get_cell_tile_data(value)
	return data == null or (floor_layer.tile_set.get_physics_layers_count() > 0 and data.get_collision_polygons_count(0) > 0)


func blocked(value: Vector2i) -> bool:
	if _floor_blocked(value): return true
	var native := native_point(value)
	var furniture_cell := furniture_layer.local_to_map(furniture_layer.to_local(field.to_global(native)))
	if furniture_layer.get_cell_source_id(furniture_cell) != -1: return true
	for marker in markers:
		if marker.blocks_movement and rect_for(marker).has_point(value): return true
	return false


func _reachable(start: Vector2i) -> Dictionary:
	var found: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if found.has(next) or blocked(next): continue
			found[next] = true
			queue.append(next)
	return found


func _validate(location: String) -> void:
	var required := ["player_spawn:"]
	if location == "room": required.append_array(["bed:", "phone:"])
	else:
		required.append("cashier:counter")
		for id in CUSTOMER_IDS:
			required.append("npc_spawn:" + str(id))
			required.append("npc_target:" + str(id))
	for key in required:
		if not anchors.has(key): errors.append("필수 표시점이 없습니다: " + key)
	if not errors.is_empty(): return
	for marker in markers:
		if marker.role in ["player_spawn", "npc_spawn", "npc_target", "cashier"] and blocked(cell_at(marker)):
			errors.append("벽이나 가구 위에 있는 표시점: " + marker.name)
	if not errors.is_empty(): return
	var reachable := _reachable(cell("player_spawn"))
	if location == "room":
		for role in ["bed", "phone"]:
			var accessible := false
			for value in reachable:
				if near(role, value):
					accessible = true
					break
			if not accessible: errors.append("접근할 수 없는 가구: " + role)
	else:
		var targets: Array[Vector2i] = []
		var spawns: Array[Vector2i] = []
		if not reachable.has(cell("cashier", &"counter")): errors.append("계산원 자리에 접근할 수 없습니다.")
		for id in CUSTOMER_IDS:
			var target := cell("npc_target", id)
			var spawn := cell("npc_spawn", id)
			if target in targets or spawn in spawns: errors.append("손님 위치가 겹칩니다: " + str(id))
			targets.append(target)
			spawns.append(spawn)
			if not _reachable(spawn).has(target): errors.append("손님 목적지까지 길이 없습니다: " + str(id))
			if id != &"counter":
				var accessible := false
				for value in reachable:
					if value != target and near("npc_target", value, id):
						accessible = true
						break
				if not accessible: errors.append("손님을 응대할 자리가 없습니다: " + str(id))
