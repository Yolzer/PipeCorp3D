extends Node
## Autoload "SaveService": binary snapshot of the job IN PROGRESS (FileAccess, no JSON).
## PostgreSQL stays the authority for money/XP/inventory; this file only holds what the
## server does not know yet: installed sockets, elapsed time and the player's position.
##
## Binary layout (little-endian), version 1:
##   [4]  magic "PC3D"          [2]  version (u16)       [8]  ticket_id (u64)
##   [4]  elapsed_ms (u32)      [1]  has_transform (u8)  [16] pos.x,pos.y,pos.z,yaw (f32 x4)
##   [2]  socket count (u16)    then per socket: pascal string socket_id + pascal string item_code
##   [4]  checksum (u32) = sum of every previous byte, mod 2^32

const SAVE_PATH: String = "user://pipecorp_session.sav"
const TMP_PATH: String = "user://pipecorp_session.tmp"
const MAGIC: PackedByteArray = [0x50, 0x43, 0x33, 0x44]   # "PC3D"
const VERSION: int = 1
const AUTOSAVE_SECONDS: float = 5.0

## Tests point this to a separate file so they never touch the real save.
var save_path: String = SAVE_PATH

var _restoring: bool = false
var _autosave: Timer = null


class Snapshot:
	var ticket_id: int = 0
	var elapsed_ms: int = 0
	var has_transform: bool = false
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var sockets: Array[StringName] = []
	var items: Array[StringName] = []


func _ready() -> void:
	SignalBus.job_started.connect(_on_job_started)
	SignalBus.pipe_placed.connect(_on_pipe_placed)
	SignalBus.job_completed.connect(_on_job_finished)
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.tickets_updated.connect(_on_tickets_updated)
	_autosave = Timer.new()
	_autosave.wait_time = AUTOSAVE_SECONDS
	_autosave.timeout.connect(save_snapshot)
	add_child(_autosave)
	_autosave.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_snapshot()


func has_snapshot() -> bool:
	return FileAccess.file_exists(save_path)


func delete_snapshot() -> void:
	if has_snapshot():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# ---------------- write ----------------
func save_snapshot() -> bool:
	if _restoring or not JobSession.is_active():
		return false
	var snap: Snapshot = Snapshot.new()
	snap.ticket_id = JobSession.active_ticket.id
	snap.elapsed_ms = JobSession.elapsed_ms()
	var body: PlumberEntity = get_tree().get_first_node_in_group(PlumberEntity.GROUP) as PlumberEntity
	if body != null:
		snap.has_transform = true
		snap.position = body.global_position
		snap.yaw = body.rotation.y
	for socket: GridSocket in GridManager.occupied_sockets():
		snap.sockets.append(socket.socket_id)
		snap.items.append(socket.occupied_by)
	return write_file(snap, save_path)


func write_file(snap: Snapshot, path: String) -> bool:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_data(MAGIC)
	buf.put_u16(VERSION)
	buf.put_u64(snap.ticket_id)
	buf.put_u32(snap.elapsed_ms)
	buf.put_u8(1 if snap.has_transform else 0)
	buf.put_float(snap.position.x)
	buf.put_float(snap.position.y)
	buf.put_float(snap.position.z)
	buf.put_float(snap.yaw)
	buf.put_u16(snap.sockets.size())
	for i: int in snap.sockets.size():
		_put_string(buf, String(snap.sockets[i]))
		_put_string(buf, String(snap.items[i]))
	var data: PackedByteArray = buf.data_array
	buf.put_u32(_checksum(data))

	# Atomic write: temp file + rename, so a crash never leaves a half-written save.
	var tmp: String = TMP_PATH if path == SAVE_PATH else path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("[SaveService] Cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_buffer(buf.data_array)
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


# ---------------- read ----------------
## Returns null if the file is missing, truncated, from another version or corrupted.
func read_file(path: String) -> Snapshot:
	if not FileAccess.file_exists(path):
		return null
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if raw.size() < 41 or raw.slice(0, 4) != MAGIC:
		return null
	var payload: PackedByteArray = raw.slice(0, raw.size() - 4)
	var tail: StreamPeerBuffer = StreamPeerBuffer.new()
	tail.data_array = raw.slice(raw.size() - 4)
	if tail.get_u32() != _checksum(payload):
		return null
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = payload
	buf.seek(4)
	if buf.get_u16() != VERSION:
		return null
	var snap: Snapshot = Snapshot.new()
	snap.ticket_id = buf.get_u64()
	snap.elapsed_ms = buf.get_u32()
	snap.has_transform = buf.get_u8() == 1
	snap.position = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	snap.yaw = buf.get_float()
	var count: int = buf.get_u16()
	for i: int in count:
		snap.sockets.append(StringName(_get_string(buf)))
		snap.items.append(StringName(_get_string(buf)))
	return snap


# ---------------- restore ----------------
## After login the API sends the ticket list; if our saved ticket is still ACCEPTED, resume it.
func _on_tickets_updated(tickets: Array[TicketData]) -> void:
	if JobSession.is_active() or not has_snapshot():
		return
	var snap: Snapshot = read_file(save_path)
	if snap == null:
		delete_snapshot()
		return
	for t: TicketData in tickets:
		if t.id == snap.ticket_id and t.status == &"ACCEPTED":
			restore(snap, t)
			return
	delete_snapshot()   # ticket no longer active on the server -> snapshot is stale


func restore(snap: Snapshot, ticket: TicketData) -> void:
	_restoring = true
	SignalBus.job_started.emit(ticket)   # HUD timer + JobSession.begin (clears grid)
	var restored: int = 0
	for i: int in snap.sockets.size():
		if GridManager.restore_placement(snap.sockets[i], snap.items[i]):
			restored += 1
	JobSession.begin(ticket, snap.elapsed_ms, restored)
	var body: PlumberEntity = get_tree().get_first_node_in_group(PlumberEntity.GROUP) as PlumberEntity
	if body != null and snap.has_transform:
		body.global_position = snap.position
		body.rotation.y = snap.yaw
	_restoring = false


# ---------------- signal hooks ----------------
func _on_job_started(_ticket: TicketData) -> void:
	if not _restoring:
		save_snapshot.call_deferred()


func _on_pipe_placed(_p: StringName, _s: StringName, _c: Vector3i, _i: StringName) -> void:
	save_snapshot()


func _on_job_finished(_t: int, _s: int, _i: StringName, _u: int, _w: int) -> void:
	delete_snapshot()


func _on_game_over(_reason: StringName) -> void:
	delete_snapshot()


# ---------------- helpers ----------------
static func _put_string(buf: StreamPeerBuffer, text: String) -> void:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	buf.put_u16(bytes.size())
	buf.put_data(bytes)


static func _get_string(buf: StreamPeerBuffer) -> String:
	var size: int = buf.get_u16()
	var result: Array = buf.get_data(size)
	var bytes: PackedByteArray = result[1]
	return bytes.get_string_from_utf8()


static func _checksum(data: PackedByteArray) -> int:
	var sum: int = 0
	for b: int in data:
		sum = (sum + b) & 0xFFFFFFFF
	return sum
