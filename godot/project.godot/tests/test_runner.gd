extends Node3D
## Headless DoD test suite for the MP-Ready core (grid authority + input/logic split).
## Run:  godot --headless --path <project> res://tests/TestRunner.tscn
## Exit code 0 = all passed, 1 = failure (usable in CI).

const SOCKET_LAYER: int = 1 << 2      # layer 3 "Sockets"
const SISS_LAYER: int = 1 << 3        # layer 4 "SISSZone"
const RAY_MASK: int = 1 | SOCKET_LAYER | SISS_LAYER

var _passed: int = 0
var _failed: int = 0
var _placed: Array[PlacedEvent] = []
var _rejected: Array[RejectedEvent] = []


class PlacedEvent:
	var player: StringName
	var socket: StringName
	var cell: Vector3i
	var item: StringName


class RejectedEvent:
	var player: StringName
	var socket: StringName
	var reason: StringName
var _siss_touches: Array[int] = []


func _ready() -> void:
	SignalBus.pipe_placed.connect(_on_pipe_placed)
	SignalBus.pipe_rejected.connect(_on_pipe_rejected)
	SignalBus.intent_touch_public_network.connect(_on_siss_touch)
	await _run_all()
	print("\n=== GODOT DoD: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _run_all() -> void:
	_test_grid_math()
	_test_item_codes()
	_test_registry_and_duplicates()
	_test_authority_accepts_and_blocks_double_occupation()
	_test_authority_rejects_unknown_and_invalid()
	await _test_entity_moves_only_by_intent()
	await _test_raycast_interaction_end_to_end()
	await _test_raycast_siss_zone()
	_test_controller_possession()
	_test_architecture_entity_never_reads_input()


# ---------------- helpers ----------------
func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS [%s]" % label)
	else:
		_failed += 1
		printerr("FAIL [%s]" % label)


func _make_socket(id: StringName, pos: Vector3) -> GridSocket:
	var socket: GridSocket = GridSocket.new()
	socket.name = String(id)
	socket.socket_id = id
	socket.collision_layer = SOCKET_LAYER
	socket.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	socket.add_child(shape)
	socket.position = pos
	add_child(socket)
	return socket


func _make_entity(pos: Vector3) -> PlumberEntity:
	var entity: PlumberEntity = PlumberEntity.new()
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	var ray: RayCast3D = RayCast3D.new()
	ray.name = "RayCast3D"
	ray.target_position = Vector3(0.0, 0.0, -3.0)
	ray.collide_with_areas = true
	ray.collision_mask = RAY_MASK
	cam.add_child(ray)
	entity.add_child(cam)
	entity.position = pos
	add_child(entity)
	return entity


func _on_pipe_placed(player_id: StringName, socket_id: StringName, cell: Vector3i, item_code: StringName) -> void:
	var ev: PlacedEvent = PlacedEvent.new()
	ev.player = player_id
	ev.socket = socket_id
	ev.cell = cell
	ev.item = item_code
	_placed.append(ev)


func _on_pipe_rejected(player_id: StringName, socket_id: StringName, reason: StringName) -> void:
	var ev: RejectedEvent = RejectedEvent.new()
	ev.player = player_id
	ev.socket = socket_id
	ev.reason = reason
	_rejected.append(ev)


func _on_siss_touch(_player_id: StringName, ticket_id: int) -> void:
	_siss_touches.append(ticket_id)


# ---------------- tests ----------------
func _test_grid_math() -> void:
	_check(GridMath.world_to_cell(Vector3(0.4, 0.0, 1.6)) == Vector3i(0, 0, 2), "G01 world_to_cell rounds to nearest cell")
	_check(GridMath.world_to_cell(Vector3(-0.6, 2.49, -3.5)) == Vector3i(-1, 2, -4), "G01 negative coords deterministic")
	_check(GridMath.cell_to_world(Vector3i(3, 0, -2)) == Vector3(3.0, 0.0, -2.0), "G01 cell_to_world inverse")


func _test_item_codes() -> void:
	_check(ItemCodes.is_placeable(&"pvc_90_deg"), "G02 DB item code accepted")
	_check(not ItemCodes.is_placeable(&"teflon_tape"), "G02 sealant is not a placeable pipe")


func _test_registry_and_duplicates() -> void:
	var before: int = GridManager.socket_count()
	var a: GridSocket = _make_socket(&"S_A", Vector3(0.0, 1.0, -2.0))
	_check(GridManager.socket_count() == before + 1 and a.cell == Vector3i(0, 1, -2), "G03 socket self-registers with its cell")
	print("   (next 2 ERROR lines are EXPECTED: duplicate detection)")
	var dup_id: GridSocket = _make_socket(&"S_A", Vector3(5.0, 1.0, 5.0))
	var dup_cell: GridSocket = _make_socket(&"S_DUP_CELL", Vector3(0.2, 1.1, -1.9))
	_check(GridManager.get_socket(&"S_A") == a, "G03 duplicate socket_id rejected")
	_check(GridManager.get_socket(&"S_DUP_CELL") == null, "G03 two sockets in one cell rejected")
	_check(GridManager.socket_at(Vector3i(0, 1, -2)) == a, "G03 socket_at(cell) lookup")
	dup_id.queue_free()
	dup_cell.queue_free()


func _test_authority_accepts_and_blocks_double_occupation() -> void:
	_placed.clear()
	_rejected.clear()
	var b: GridSocket = _make_socket(&"S_B", Vector3(4.0, 0.0, 4.0))
	SignalBus.intent_place_pipe.emit(&"Player_1", &"S_B", ItemCodes.PVC_STRAIGHT)
	_check(_placed.size() == 1 and _placed[0].cell == Vector3i(4, 0, 4), "G04 valid intent -> pipe_placed with cell")
	_check(b.is_occupied and b.occupied_by == ItemCodes.PVC_STRAIGHT, "G04 authority occupied the socket")
	SignalBus.intent_place_pipe.emit(&"Player_2", &"S_B", ItemCodes.PVC_TEE)
	_check(_placed.size() == 1 and _rejected.size() == 1 and _rejected[0].reason == GridManager.REASON_OCCUPIED,
		"G04 double occupation blocked (co-op race safe)")
	_check(b.occupied_by == ItemCodes.PVC_STRAIGHT, "G04 first placement preserved")


func _test_authority_rejects_unknown_and_invalid() -> void:
	_rejected.clear()
	_make_socket(&"S_C", Vector3(6.0, 0.0, 6.0))
	SignalBus.intent_place_pipe.emit(&"Player_1", &"NOPE", ItemCodes.PVC_TEE)
	SignalBus.intent_place_pipe.emit(&"Player_1", &"S_C", &"golden_pipe")
	_check(_rejected.size() == 2, "G05 two rejections emitted")
	_check(_rejected[0].reason == GridManager.REASON_UNKNOWN_SOCKET, "G05 unknown socket rejected")
	_check(_rejected[1].reason == GridManager.REASON_INVALID_ITEM, "G05 item not in DB catalog rejected")
	_check(not GridManager.get_socket(&"S_C").is_occupied, "G05 rejected intent leaves state untouched")


func _test_entity_moves_only_by_intent() -> void:
	var e: PlumberEntity = _make_entity(Vector3(50.0, 0.0, 50.0))
	await get_tree().physics_frame
	var start: Vector3 = e.global_position
	for i: int in 10:
		await get_tree().physics_frame
	_check(is_equal_approx(e.global_position.x, start.x) and is_equal_approx(e.global_position.z, start.z),
		"G06 entity stays still with no intent (no hidden input reading)")
	e.move_intent = Vector2(0.0, -1.0)
	for i: int in 20:
		await get_tree().physics_frame
	_check(e.global_position.z < start.z - 0.5, "G06 move_intent forward moves entity along -Z")
	e.apply_look(0.0, deg_to_rad(170.0))
	_check(e.camera.rotation.x <= deg_to_rad(85.0) + 0.001, "G06 pitch clamped to 85 degrees")
	e.queue_free()


func _test_raycast_interaction_end_to_end() -> void:
	_placed.clear()
	var target: GridSocket = _make_socket(&"S_RAY", Vector3(20.0, 0.0, 18.0))
	var e: PlumberEntity = _make_entity(Vector3(20.0, 0.0, 20.0))   # 2 m in front of the socket
	e.player_id = &"Player_1"
	await get_tree().physics_frame
	await get_tree().physics_frame
	e.request_interact()
	_check(_placed.size() == 1 and _placed[0].socket == &"S_RAY" and target.is_occupied,
		"G07 ray -> intent -> authority -> pipe_placed (end-to-end)")
	e.request_interact()
	_check(_placed.size() == 1, "G07 second click on same socket does not place again")
	e.queue_free()


func _test_raycast_siss_zone() -> void:
	_siss_touches.clear()
	var zone: SissZone = SissZone.new()
	zone.ticket_id = 77
	zone.collision_layer = SISS_LAYER
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	zone.add_child(shape)
	zone.position = Vector3(30.0, 0.0, 28.0)
	add_child(zone)
	var e: PlumberEntity = _make_entity(Vector3(30.0, 0.0, 30.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	e.request_interact()
	_check(_siss_touches == [77], "G08 touching SISS red zone emits intent_touch_public_network(ticket)")
	e.queue_free()


func _test_controller_possession() -> void:
	var c: PlayerController = PlayerController.new()
	add_child(c)
	_check(c.entity == null, "G09 controller can exist without a body")
	_check(InputMap.has_action(&"move_forward") and InputMap.has_action(&"interact"), "G09 default actions registered")
	var e1: PlumberEntity = _make_entity(Vector3(-50.0, 0.0, 0.0))
	var e2: PlumberEntity = _make_entity(Vector3(-60.0, 0.0, 0.0))
	e2.player_id = &"Player_2"
	c.possess(e1)
	e1.move_intent = Vector2(1.0, 0.0)
	c.possess(e2)
	_check(c.entity == e2 and e1.move_intent == Vector2.ZERO, "G09 re-possession transfers control and halts previous body")
	c.release()
	_check(c.entity == null, "G09 release() detaches control")
	c.queue_free()
	e1.queue_free()
	e2.queue_free()


func _test_architecture_entity_never_reads_input() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/player/PlumberEntity.gd")
	var code_only: PackedStringArray = PackedStringArray()
	for line: String in src.split("\n"):
		code_only.append(line.split("#")[0])
	var code: String = "\n".join(code_only)
	var re: RegEx = RegEx.create_from_string("\\bInput\\.|func _input\\(|func _unhandled_input\\(")
	_check(src.length() > 0 and re.search(code) == null, "G10 ARCHITECTURE: PlumberEntity contains no Input access")
