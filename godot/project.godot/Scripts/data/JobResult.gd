class_name JobResult
extends RefCounted
## Grading returned by POST /jobs/:id/complete (computed by sp_complete_job in PostgreSQL

var ticket_id: int = 0
var grade: String = "F"   ## "S" | "A" | "B" | "C" | "D" | "F"
var payout: float = 0.0
var xp_gained: int = 0


static func from_dict(d: Dictionary) -> JobResult:
	var r: JobResult = JobResult.new()
	r.ticket_id = JsonUtil.get_int(d, "ticketId")
	r.grade = JsonUtil.get_string(d, "grade", "F")
	r.payout = JsonUtil.get_float(d, "payout")
	r.xp_gained = JsonUtil.get_int(d, "xpGained")
	return r
