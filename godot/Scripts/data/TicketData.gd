class_name TicketData
extends RefCounted
## One work order from the living economy (GET /tickets).

var id: int = 0
var zone: StringName = &"PRIVATE"   ## &"PRIVATE" | &"PUBLIC" (SISS red zone)
var description: String = ""
var difficulty: int = 1
var estimated_parts: int = 1          ## pipes the job needs (JobSession requires at least this many
var budget: float = 0.0
var target_seconds: int = 60
var status: StringName = &"OPEN"      ## OPEN | ACCEPTED | COMPLETED | EXPIRED | DERIVED | FAILED
var expires_at_unix: int = 0


func is_public() -> bool:
	return zone == &"PUBLIC"


static func from_dict(d: Dictionary) -> TicketData:
	var t: TicketData = TicketData.new()
	t.id = JsonUtil.get_int(d, "id")
	t.zone = StringName(JsonUtil.get_string(d, "zone", "PRIVATE"))
	t.description = JsonUtil.get_string(d, "description")
	t.difficulty = JsonUtil.get_int(d, "difficulty", 1)
	t.estimated_parts = JsonUtil.get_int(d, "estimatedParts", 1)
	t.budget = JsonUtil.get_float(d, "budget")
	t.target_seconds = JsonUtil.get_int(d, "targetSeconds", 60)
	t.status = StringName(JsonUtil.get_string(d, "status", "OPEN"))
	t.expires_at_unix = JsonUtil.get_int(d, "expiresAtUnix")
	return t
