extends Node
## Autoload "GridManager" = the local AUTHORITY ("local server") for pipe placement.
## Flow: PlumberEntity emits intent -> GridManager validates -> occupies the
## socket -> emits pipe_placed (or pipe_rejected). In multiplayer this node runs
## only on the host; clients just receive the confirmations.

const REASON_UNKNOWN_SOCKET: StringName = &"unknown_socket"
const REASON_OCCUPIED: StringName = &"occupied"
const REASON_INVALID_ITEM: StringName = &"invalid_item"
const REASON_NO_ACTIVE_JOB: StringName = &"no_active_job"

## Set by JobSession: pipes can only be installed while a job is in progress.
var placement_enabled: bool = true

var _sockets: Dictionary[StringName, GridSocket] = {}
var _cells: Dictionary[Vector3i, StringName] = {}


func _ready() -> void:
	SignalBus.intent_place_pipe.connect(_on_intent_place_pipe)


# ---------- Registry ----------
func register_socket(socket: GridSocket) -> bool:
	if _sockets.has(socket.socket_id):
		push_error("[GridManager] Duplicate socket_id '%s' — give every socket a unique id." % socket.socket_id)
		return false
	if _cells.has(socket.cell):
		push_error("[GridManager] Two sockets share cell %s ('%s' and '%s')." % [socket.cell, _cells[socket.cell], socket.socket_id])
		return false
	_sockets[socket.socket_id] = socket
	_cells[socket.cell] = socket.socket_id
	return true


func unregister_socket(socket: GridSocket) -> void:
	if _sockets.has(socket.socket_id) and _sockets[socket.socket_id] == socket:
		_sockets.erase(socket.socket_id)
		_cells.erase(socket.cell)


func get_socket(socket_id: StringName) -> GridSocket:
	if _sockets.has(socket_id):
		return _sockets[socket_id]
	return null


func socket_at(cell: Vector3i) -> GridSocket:
	if _cells.has(cell):
		return get_socket(_cells[cell])
	return null


func socket_count() -> int:
	return _sockets.size()


func occupied_count() -> int:
	var total: int = 0
	for socket: GridSocket in _sockets.values():
		if socket.is_occupied:
			total += 1
	return total


func occupied_sockets() -> Array[GridSocket]:
	var result: Array[GridSocket] = []
	for socket: GridSocket in _sockets.values():
		if socket.is_occupied:
			result.append(socket)
	return result


## Frees every socket (new job). Not an intent: only JobSession/SaveService call it.
func clear_occupancy() -> void:
	for socket: GridSocket in _sockets.values():
		if socket.is_occupied:
			socket.vacate()


## Re-applies a saved placement without emitting pipe_placed (used by SaveService).
func restore_placement(socket_id: StringName, item_code: StringName) -> bool:
	if not _sockets.has(socket_id) or not ItemCodes.is_placeable(item_code):
		return false
	_sockets[socket_id].occupy(item_code, false)
	return true


# ---------- Authority ----------
## Returns &"" when the placement is legal, otherwise a rejection reason
func validate_placement(socket_id: StringName, item_code: StringName) -> StringName:
	if not placement_enabled:
		return REASON_NO_ACTIVE_JOB
	if not _sockets.has(socket_id):
		return REASON_UNKNOWN_SOCKET
	if not ItemCodes.is_placeable(item_code):
		return REASON_INVALID_ITEM
	if _sockets[socket_id].is_occupied:
		return REASON_OCCUPIED
	return &""


func _on_intent_place_pipe(player_id: StringName, socket_id: StringName, item_code: StringName) -> void:
	var reason: StringName = validate_placement(socket_id, item_code)
	if reason != &"":
		SignalBus.pipe_rejected.emit(player_id, socket_id, reason)
		return
	var socket: GridSocket = _sockets[socket_id]
	socket.occupy(item_code)
	SignalBus.pipe_placed.emit(player_id, socket_id, socket.cell, item_code)
