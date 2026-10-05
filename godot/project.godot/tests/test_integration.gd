extends Node3D
## Integration DoD: ApiClient + JobSession + SaveService against a running API.
## Run with the API (or mock) up:
##   PIPECORP_API_URL=http://127.0.0.1:3000 godot --headless --path . res://tests/TestIntegration.tscn
## Uses the same login the MainMenu sends ("Player_1" / "mvp_password_123").

const SOCKET_LAYER: int = 1 << 2
const TEST_SAVE: String = "user://test_snapshot.sav"

var _passed: int = 0
var _failed: int = 0
var _profile: PlayerProfile = null
var _tickets: Array[TicketData] = []
var _started: TicketData = null
var _graded: JobResult = null
var _errors: Array[String] = []
var _game_over_reason: StringName = &""
var _end_day_count: int = 0


func _ready() -> void:
	SignalBus.login_succeeded.connect(func(p: PlayerProfile) -> void: _profile = p)
	SignalBus.profile_updated.connect(func(p: PlayerProfile) -> void: _profile = p)
	SignalBus.tickets_updated.connect(func(t: Array[TicketData]) -> void: _tickets = t)
	SignalBus.job_started.connect(func(t: TicketData) -> void: _started = t)
	SignalBus.job_graded.connect(func(r: JobResult) -> void: _graded = r)
	SignalBus.api_error.connect(func(code: String, _m: String) -> void: _errors.append(code))
	SignalBus.game_over.connect(func(reason: StringName) -> void: _game_over_reason = reason)
	SignalBus.intent_end_day.connect(func() -> void: _end_day_count += 1)
	TestEnv.isolate()
	if not await TestEnv.mock_is_up(self):
		return
	await _run()
	SaveService.delete_snapshot()
	print("\n=== INTEGRATION DoD: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS [%s]" % label)
	else:
		_failed += 1
		printerr("FAIL [%s]" % label)


func _until(condition: Callable, timeout_s: float = 6.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var done: bool = condition.call()
		if done:
			return true
		await get_tree().process_frame
	return false


func _make_socket(id: StringName, pos: Vector3) -> GridSocket:
	var socket: GridSocket = GridSocket.new()
	socket.name = String(id)
	socket.socket_id = id
	socket.collision_layer = SOCKET_LAYER
	socket.position = pos
	add_child(socket)
	return socket


func _run() -> void:
	# I01 data classes from JSON (numbers arrive as float, null reason)
	var parsed: Variant = JSON.parse_string('{"money": 45200.5, "xp": 30.0, "isGameOver": false, "gameOverReason": null, "vehicleTierId": 1}')
	var d: Dictionary = parsed
	var p: PlayerProfile = PlayerProfile.from_dict(d)
	_check(is_equal_approx(p.money, 45200.5) and p.xp == 30 and p.game_over_reason == &"", "I01 PlayerProfile parses JSON floats/null safely")

	# I02 MainMenu bootstrap login: 401 -> auto-register -> login -> profile -> tickets
	SignalBus.intent_login.emit("Player_1", "mvp_password_123")
	_check(await _until(func() -> bool: return _profile != null and _tickets.size() >= 3), "I02 intent_login -> login_succeeded + tickets_updated")
	_check(_profile != null and is_equal_approx(_profile.money, 50000.0), "I02 profile starts with 50000")
	var public_count: int = 0
	for t: TicketData in _tickets:
		if t.is_public():
			public_count += 1
	_check(public_count >= 1, "I02 board contains a PUBLIC (SISS) ticket")
	_check(not GridManager.placement_enabled, "I02 placement locked until a job is accepted")

	# I03 accept first PRIVATE ticket -> job_started, placement unlocked
	var job: TicketData = null
	for t: TicketData in _tickets:
		if not t.is_public():
			job = t
			break
	SignalBus.intent_accept_ticket.emit(job.id)
	_check(await _until(func() -> bool: return _started != null), "I03 accept -> job_started")
	_check(JobSession.is_active() and GridManager.placement_enabled, "I03 JobSession active and placement unlocked")

	# I04 finishing too early is rejected locally
	_errors.clear()
	SignalBus.intent_finish_job.emit()
	_check(_errors.has("JOB") and JobSession.is_active(), "I04 finish with missing pipes -> JOB error, job still active")

	# I05 place 3 pipes (job needs 2 -> 1 wasted); snapshot written in binary
	var ids: Array[StringName] = [&"IT_A", &"IT_B", &"IT_C"]
	for i: int in ids.size():
		_make_socket(ids[i], Vector3(100.0 + i, 0.0, 0.0))
	for id: StringName in ids:
		SignalBus.intent_place_pipe.emit(&"Player_1", id, ItemCodes.PVC_90_DEG)
	_check(JobSession.placed_count == 3, "I05 JobSession counted 3 placements")
	_check(SaveService.has_snapshot(), "I05 snapshot autosaved on pipe_placed")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.save_path)
	_check(bytes.slice(0, 4) == SaveService.MAGIC and bytes[0] != 0x7B, "I05 file is binary 'PC3D' (not JSON)")
	var snap: SaveService.Snapshot = SaveService.read_file(SaveService.save_path)
	_check(snap != null and snap.ticket_id == job.id and snap.sockets.size() == 3, "I05 snapshot round-trips ticket + 3 sockets")

	# I06 simulate a restart: lose local state, then the server ticket list triggers resume
	var elapsed_before: int = snap.elapsed_ms
	JobSession._close()
	GridManager.clear_occupancy()
	var resumed: TicketData = TicketData.new()
	resumed.id = job.id
	resumed.estimated_parts = job.estimated_parts
	resumed.status = &"ACCEPTED"
	var list: Array[TicketData] = [resumed]
	SignalBus.tickets_updated.emit(list)
	_check(JobSession.is_active() and JobSession.placed_count == 3 and GridManager.occupied_count() >= 3,
		"I06 restore: job resumed with 3 installed pipes")
	_check(JobSession.elapsed_ms() >= elapsed_before, "I06 restore: timer resumes from saved elapsed time")

	# I07 corrupted / foreign files are rejected
	var f: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string('{"json": "not allowed"}')
	f.close()
	_check(SaveService.read_file(TEST_SAVE) == null, "I07 JSON/garbage file rejected")
	var good: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.save_path)
	good[20] = good[20] ^ 0xFF
	var g: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	g.store_buffer(good)
	g.close()
	_check(SaveService.read_file(TEST_SAVE) == null, "I07 flipped byte detected by checksum")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

	# I08 finish -> API grades -> job_graded, snapshot deleted
	SignalBus.intent_finish_job.emit()
	_check(await _until(func() -> bool: return _graded != null), "I08 finish -> job_graded from API")
	_check(_graded != null and _graded.grade == "A" and _graded.ticket_id == job.id, "I08 result carries grade and ticket")
	_check(not SaveService.has_snapshot() and not JobSession.is_active(), "I08 snapshot deleted and placement locked after grading")
	var log_res: ApiClient.ApiResponse = await ApiClient._request(HTTPClient.METHOD_GET, "/__log")
	var sent: Dictionary = {}
	for entry: Variant in JsonUtil.get_array(log_res.body, "requests"):
		if entry is Dictionary:
			var e: Dictionary = entry
			if JsonUtil.get_string(e, "path").begins_with("/jobs/"):
				sent = JsonUtil.get_dict(e, "body")
	_check(JsonUtil.get_string(sent, "itemCode") == "pvc_90_deg" and JsonUtil.get_int(sent, "partsUsed") == 2
		and JsonUtil.get_int(sent, "partsWasted") == 1, "I08 job summary sent once: used=2, wasted=1")

	# I09 every 3 graded jobs ends the day (daily upkeep)
	SignalBus.job_graded.emit(_graded)
	SignalBus.job_graded.emit(_graded)
	_check(_end_day_count == 1, "I09 3 graded jobs -> intent_end_day")
	_check(await _until(func() -> bool: return _profile != null and _profile.game_day == 2), "I09 /day/end applied (day 2)")

	# I10 touching the SISS red zone -> server fine -> Game Over
	SignalBus.intent_touch_public_network.emit(&"Player_1", 0)
	_check(await _until(func() -> bool: return _game_over_reason == &"SISS_TAMPERING"), "I10 SISS tampering -> game_over(SISS_TAMPERING)")

	# I11 API down -> friendly NET error, no crash
	_errors.clear()
	ApiClient.base_url = "http://127.0.0.1:9"
	SignalBus.intent_refresh_tickets.emit()
	_check(await _until(func() -> bool: return _errors.has("NET")), "I11 API offline -> api_error NET")
