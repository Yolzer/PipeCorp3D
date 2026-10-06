extends Node
## Autoload "ApiClient": the ONLY node that talks HTTP to the NestJS API.
## Listens to UI/gameplay intents on SignalBus, calls the API with the RS256
## bearer token, and re-emits typed results (profile, tickets, grades, errors).
## Network traffic is per ACTION (accept, finish job...), never per pipe placed.

const DEFAULT_BASE_URL: String = "http://127.0.0.1:3000"
const TIMEOUT_SECONDS: float = 8.0

var base_url: String = DEFAULT_BASE_URL
var profile: PlayerProfile = null
var tickets: Array[TicketData] = []

var _token: String = ""
var _base_user: String = ""
var _password: String = ""
var _career: int = 1
var _game_over_sent: bool = false
var _suppress_game_over: bool = false


class ApiResponse:
	var ok: bool = false
	var status: int = 0
	var body: Dictionary = {}

	func error_code() -> String:
		var code: String = JsonUtil.get_string(body, "code")
		return code if code != "" else str(status)

	func error_message() -> String:
		var v: Variant = body.get("message", "")
		if v is String:
			var msg: String = v
			return msg
		if v is Array:   # ValidationPipe returns an array of messages
			var parts: Array = v
			return ", ".join(PackedStringArray(parts))
		return "Error %d" % status


func _ready() -> void:
	var env_url: String = OS.get_environment("PIPECORP_API_URL")
	if env_url != "":
		base_url = env_url
	SignalBus.intent_login.connect(_on_intent_login)
	SignalBus.intent_register.connect(_on_intent_register)
	SignalBus.intent_refresh_tickets.connect(refresh_tickets)
	SignalBus.intent_accept_ticket.connect(_on_accept_ticket)
	SignalBus.intent_derive_ticket.connect(_on_derive_ticket)
	SignalBus.intent_touch_public_network.connect(_on_touch_public_network)
	SignalBus.intent_purchase.connect(_on_purchase)
	SignalBus.intent_upgrade_vehicle.connect(_on_upgrade_vehicle)
	SignalBus.intent_end_day.connect(_on_end_day)
	SignalBus.job_completed.connect(_on_job_completed)
	SignalBus.intent_new_career.connect(_on_new_career)


func is_logged_in() -> bool:
	return _token != ""


# ---------------- transport ----------------
func _request(method: HTTPClient.Method, path: String, body: Dictionary = {}) -> ApiResponse:
	var res: ApiResponse = ApiResponse.new()
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if _token != "":
		headers.append("Authorization: Bearer " + _token)
	var payload: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var err: Error = http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		res.body = {"code": "NET", "message": "No se pudo iniciar la conexión con el servidor."}
		return res

	var args: Array = await http.request_completed
	http.queue_free()
	var result: int = args[0]
	var status: int = args[1]
	var raw: PackedByteArray = args[3]
	res.status = status
	if OS.is_debug_build():
		print("[ApiClient] %s %s%s -> HTTP %d (result %d)" % [_method_name(method), base_url, path, status, result])
	if result != HTTPRequest.RESULT_SUCCESS:
		res.body = {"code": "NET", "message": "Servidor no disponible. ¿Está encendida la API?"}
		return res
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if parsed is Dictionary:
		res.body = parsed
	res.ok = status >= 200 and status < 300
	return res


static func _method_name(method: HTTPClient.Method) -> String:
	return "GET" if method == HTTPClient.METHOD_GET else "POST"


## Emits api_error for a failed response; detects Game Over (PC001) from any endpoint.
func _fail(res: ApiResponse) -> void:
	SignalBus.api_error.emit(res.error_code(), res.error_message())
	if res.error_code() == "PC001":
		await _fetch_profile()


func _apply_profile(d: Dictionary) -> void:
	if d.is_empty():
		return
	profile = PlayerProfile.from_dict(d)
	SignalBus.profile_updated.emit(profile)
	if profile.is_game_over and not _game_over_sent and not _suppress_game_over:
		_game_over_sent = true
		SignalBus.game_over.emit(profile.game_over_reason)


func _fetch_profile() -> bool:
	var res: ApiResponse = await _request(HTTPClient.METHOD_GET, "/profile")
	if not res.ok:
		return false
	_apply_profile(res.body)
	return true


# ---------------- auth ----------------
## The menu always sends the BASE user (Player_1); we log into its current career account.
func _on_intent_login(username: String, password: String) -> void:
	_base_user = username
	_password = password
	_career = CareerStore.current_career(username)
	await _authenticate(CareerStore.username_for(username, _career), password, false)


## Game Over is irreversible server-side: start career N+1 as a brand-new account.
func _on_new_career() -> void:
	if _base_user == "":
		return
	_career += 1
	CareerStore.save(_base_user, _career)
	_token = ""
	tickets = []
	await _authenticate(CareerStore.username_for(_base_user, _career), _password, true)


func current_username() -> String:
	return CareerStore.username_for(_base_user, _career)


func _on_intent_register(username: String, password: String) -> void:
	await _authenticate(username, password, true)


## Login; if the account does not exist yet (401) it is registered automatically (MVP bootstrap).
func _authenticate(username: String, password: String, register_first: bool) -> void:
	var creds: Dictionary = {"username": username, "password": password}
	if register_first:
		await _request(HTTPClient.METHOD_POST, "/auth/register", creds)
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/auth/login", creds)
	if res.status == 401 and not register_first:
		var reg: ApiResponse = await _request(HTTPClient.METHOD_POST, "/auth/register", creds)
		if not reg.ok and reg.status != 409:
			SignalBus.auth_failed.emit(reg.error_message())
			return
		res = await _request(HTTPClient.METHOD_POST, "/auth/login", creds)
	if not res.ok:
		SignalBus.auth_failed.emit(res.error_message())
		return
	_token = JsonUtil.get_string(res.body, "access_token")
	_game_over_sent = false
	_suppress_game_over = true   # announce the login first, then the Game Over (order matters for the UI)
	var loaded: bool = await _fetch_profile()
	_suppress_game_over = false
	if not loaded:
		SignalBus.auth_failed.emit("No se pudo cargar el perfil.")
		return
	SignalBus.login_succeeded.emit(profile)
	if profile.is_game_over:
		# Fired career: show the Game Over screen (with "Nueva Carrera") and skip the ticket board.
		_game_over_sent = true
		SignalBus.game_over.emit(profile.game_over_reason)
		return
	await refresh_tickets()


# ---------------- tickets ----------------
func refresh_tickets() -> void:
	if not is_logged_in():
		return
	var res: ApiResponse = await _request(HTTPClient.METHOD_GET, "/tickets")
	if not res.ok:
		await _fail(res)
		return
	var parsed: Array[TicketData] = []
	for item: Variant in JsonUtil.get_array(res.body, "tickets"):
		if item is Dictionary:
			var d: Dictionary = item
			parsed.append(TicketData.from_dict(d))
	tickets = parsed
	SignalBus.tickets_updated.emit(tickets)


func find_ticket(ticket_id: int) -> TicketData:
	for t: TicketData in tickets:
		if t.id == ticket_id:
			return t
	return null


func _on_accept_ticket(ticket_id: int) -> void:
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/tickets/%d/accept" % ticket_id)
	if not res.ok:
		await _fail(res)
		return
	_apply_profile(JsonUtil.get_dict(res.body, "profile"))
	var ticket: TicketData = TicketData.from_dict(JsonUtil.get_dict(res.body, "ticket"))
	SignalBus.ticket_accepted.emit(ticket.id)
	SignalBus.job_started.emit(ticket)
	await refresh_tickets()


func _on_derive_ticket(ticket_id: int) -> void:
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/tickets/%d/derive" % ticket_id)
	if not res.ok:
		await _fail(res)
		return
	_apply_profile(JsonUtil.get_dict(res.body, "profile"))
	await refresh_tickets()


## The player touched a SISS red zone. The fine is decided by PostgreSQL, not by the client.
func _on_touch_public_network(_player_id: StringName, zone_ticket_id: int) -> void:
	var target: TicketData = find_ticket(zone_ticket_id) if zone_ticket_id > 0 else null
	if target == null:
		for t: TicketData in tickets:
			if t.is_public() and t.status == &"OPEN":
				target = t
				break
	if target == null:
		SignalBus.api_error.emit("SISS", "Red pública: no intervenir. Deriva el problema a la SISS.")
		return
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/tickets/%d/tampering" % target.id)
	if not res.ok:
		await _fail(res)
		return
	SignalBus.api_error.emit("SISS", "¡Multa SISS por intervenir la red pública!")
	_apply_profile(JsonUtil.get_dict(res.body, "profile"))
	await refresh_tickets()


# ---------------- jobs & economy ----------------
func _on_job_completed(ticket_id: int, time_seconds: int, item_code: StringName, parts_used: int, parts_wasted: int) -> void:
	var body: Dictionary = {
		"itemCode": String(item_code),
		"timeSeconds": time_seconds,
		"partsUsed": parts_used,
		"partsWasted": parts_wasted,
	}
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/jobs/%d/complete" % ticket_id, body)
	if not res.ok:
		await _fail(res)
		return
	var result: JobResult = JobResult.from_dict(JsonUtil.get_dict(res.body, "result"))
	_apply_profile(JsonUtil.get_dict(res.body, "profile"))
	SignalBus.job_graded.emit(result)
	await refresh_tickets()


func _on_end_day() -> void:
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/day/end")
	if not res.ok:
		await _fail(res)
		return
	_apply_profile(JsonUtil.get_dict(res.body, "profile"))


func _on_purchase(item_code: StringName, quantity: int) -> void:
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/inventory/purchase",
		{"itemCode": String(item_code), "quantity": quantity})
	if not res.ok:
		await _fail(res)
		return
	_apply_profile(JsonUtil.get_dict(res.body, "profile"))


func _on_upgrade_vehicle(tier_id: int) -> void:
	var res: ApiResponse = await _request(HTTPClient.METHOD_POST, "/vehicles/upgrade", {"tierId": tier_id})
	if not res.ok:
		await _fail(res)
		return
	_apply_profile(JsonUtil.get_dict(res.body, "profile"))
