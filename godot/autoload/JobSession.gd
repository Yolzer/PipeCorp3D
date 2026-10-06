extends Node
## Autoload "JobSession": state of the job in progress (local, client-side).
## - job_started  -> frees the grid, enables placement, starts the clock
## - pipe_placed  -> counts installed pipes
## - intent_finish_job -> validates and emits job_completed (ApiClient sends it to the API)
## Grading itself happens in PostgreSQL (sp_complete_job), never here.

const JOB_ITEM: StringName = ItemCodes.PVC_90_DEG
const MAX_WASTED_PARTS: int = 2     ## matches the spare parts bought on accept (GameService.SPARE_PARTS)
const JOBS_PER_DAY: int = 3         ## every N graded jobs the day ends (daily upkeep

var active_ticket: TicketData = null
var placed_count: int = 0

var _started_ms: int = 0
var _jobs_today: int = 0


func _ready() -> void:
	GridManager.placement_enabled = false
	SignalBus.job_started.connect(_on_job_started)
	SignalBus.pipe_placed.connect(_on_pipe_placed)
	SignalBus.intent_finish_job.connect(_on_intent_finish_job)
	SignalBus.job_graded.connect(_on_job_graded)
	SignalBus.game_over.connect(_on_game_over)


func is_active() -> bool:
	return active_ticket != null


func elapsed_ms() -> int:
	return Time.get_ticks_msec() - _started_ms if is_active() else 0


## Starts (or resumes, when restoring a save) the job clock.
func begin(ticket: TicketData, already_elapsed_ms: int = 0, already_placed: int = 0) -> void:
	active_ticket = ticket
	placed_count = already_placed
	_started_ms = Time.get_ticks_msec() - already_elapsed_ms
	GridManager.placement_enabled = true


func _on_job_started(ticket: TicketData) -> void:
	GridManager.clear_occupancy()
	begin(ticket)


func _on_pipe_placed(_player_id: StringName, _socket_id: StringName, _cell: Vector3i, _item_code: StringName) -> void:
	if is_active():
		placed_count += 1


func _on_intent_finish_job() -> void:
	if not is_active():
		SignalBus.api_error.emit("JOB", "No hay un trabajo activo. Acepta un ticket en el teléfono.")
		return
	var needed: int = active_ticket.estimated_parts
	if placed_count < needed:
		SignalBus.api_error.emit("JOB", "Faltan %d tuberías por instalar." % (needed - placed_count))
		return
	var time_seconds: int = maxi(1, ceili(elapsed_ms() / 1000.0))
	var parts_used: int = needed
	var parts_wasted: int = mini(placed_count - needed, MAX_WASTED_PARTS)
	var ticket_id: int = active_ticket.id
	_close()
	SignalBus.job_completed.emit(ticket_id, time_seconds, JOB_ITEM, parts_used, parts_wasted)


func _on_job_graded(_result: JobResult) -> void:
	_jobs_today += 1
	if _jobs_today >= JOBS_PER_DAY:
		_jobs_today = 0
		SignalBus.intent_end_day.emit()


func _on_game_over(_reason: StringName) -> void:
	_close()


func _close() -> void:
	active_ticket = null
	GridManager.placement_enabled = false
