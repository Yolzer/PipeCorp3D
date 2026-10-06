class_name CareerStore
extends RefCounted
## Remembers which career (account) the local player is on, in a tiny BINARY file.
## Game Over is irreversible in PostgreSQL; "Nueva Carrera" registers a fresh account
## (Player_1_c2, Player_1_c3...) and the fired career stays in the DB as audited history.
## Layout: [4] "PCCR" | [2] version u16 | [2] career number u16 | [2] len u16 + utf8 base username

## Tests point this to a separate file so they never touch the real career.
static var path: String = "user://career.bin"
const MAGIC: PackedByteArray = [0x50, 0x43, 0x43, 0x52]   # "PCCR"
const VERSION: int = 1


## Account name for a base user + career number (career 1 keeps the original name).
static func username_for(base: String, career: int) -> String:
	return base if career <= 1 else "%s_c%d" % [base, career]


static func current_career(base: String) -> int:
	if not FileAccess.file_exists(path):
		return 1
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = FileAccess.get_file_as_bytes(path)
	if buf.data_array.size() < 10 or buf.data_array.slice(0, 4) != MAGIC:
		return 1
	buf.seek(4)
	if buf.get_u16() != VERSION:
		return 1
	var career: int = buf.get_u16()
	var size: int = buf.get_u16()
	var result: Array = buf.get_data(size)
	var bytes: PackedByteArray = result[1]
	return career if bytes.get_string_from_utf8() == base else 1


static func save(base: String, career: int) -> bool:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_data(MAGIC)
	buf.put_u16(VERSION)
	buf.put_u16(career)
	var bytes: PackedByteArray = base.to_utf8_buffer()
	buf.put_u16(bytes.size())
	buf.put_data(bytes)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(buf.data_array)
	file.close()
	return true


static func reset() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
