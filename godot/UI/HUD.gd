class_name HUD
extends CanvasLayer
## Top bar + job timer + toasts. Node paths match HUD.tscn:
## Hud > MarginContainer > TopBar > MoneyLabel / XPLabel / TimerLabel ; Hud > FinishJobBtn
## ToastLabel and JobTimer are found whether they sit under Hud or under AnimationPlayer.
## Keys (UI layer): [F] finish job. The mouse is captured while playing, so the button alone is not enough.

@onready var money_label: Label = $MarginContainer/TopBar/MoneyLabel
@onready var xp_label: Label = $MarginContainer/TopBar/XPLabel
@onready var timer_label: Label = $MarginContainer/TopBar/TimerLabel
@onready var finish_job_btn: Button = $FinishJobBtn
@onready var toast_label: Label = _find_node(^"ToastLabel", ^"AnimationPlayer/ToastLabel") as Label
@onready var job_timer: Timer = _find_node(^"JobTimer", ^"AnimationPlayer/JobTimer") as Timer
@onready var error_sfx: AudioStreamPlayer = get_node_or_null(^"ErrorSFX") as AudioStreamPlayer

var current_job_seconds: int = 0
var _hint_label: Label = null


func _ready() -> void:
	visible = false   # the HUD appears only after login (it used to cover the main menu)
	_make_click_through(self)
	SignalBus.login_succeeded.connect(func(_p: PlayerProfile) -> void: visible = true)
	toast_label.hide()
	job_timer.timeout.connect(_on_timer_tick)
	finish_job_btn.pressed.connect(_emit_finish)
	finish_job_btn.hide()
	_hint_label = Label.new()
	_hint_label.text = "   [T] Teléfono   [F] Terminar   [C] Cambiar gasfíter   [Esc] Mouse"
	$MarginContainer/TopBar.add_child(_hint_label)
	timer_label.text = "Sin trabajo activo"
	SignalBus.profile_updated.connect(_on_profile_updated)
	SignalBus.job_started.connect(_on_job_started)
	SignalBus.job_graded.connect(_on_job_graded)
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.pipe_rejected.connect(_on_pipe_rejected)
	SignalBus.api_error.connect(_on_api_error)
	SignalBus.control_switched.connect(_on_control_switched)


## Labels/containers must never eat mouse clicks meant for the 3D world or other menus.
func _make_click_through(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control and not (child is BaseButton):
			var control: Control = child as Control
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_click_through(child)


func _find_node(primary: NodePath, fallback: NodePath) -> Node:
	var node: Node = get_node_or_null(primary)
	return node if node != null else get_node_or_null(fallback)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_F:
			_emit_finish()


func _emit_finish() -> void:
	SignalBus.intent_finish_job.emit()


func _on_profile_updated(profile: PlayerProfile) -> void:
	money_label.text = "CLP: $%d" % roundi(profile.money)
	xp_label.text = "   XP: %d | Día: %d | %s   " % [profile.xp, profile.game_day, profile.vehicle_name]


func _on_job_started(ticket: TicketData) -> void:
	current_job_seconds = ticket.target_seconds
	_update_timer_display()
	job_timer.start(1.0)
	finish_job_btn.show()
	_show_toast("Trabajo: %s — instala %d tuberías" % [ticket.description, ticket.estimated_parts])


func _on_job_graded(_result: JobResult) -> void:
	job_timer.stop()
	finish_job_btn.hide()
	timer_label.text = "Sin trabajo activo"


func _on_game_over(_reason: StringName) -> void:
	job_timer.stop()
	finish_job_btn.hide()


func _on_timer_tick() -> void:
	if current_job_seconds > 0:
		current_job_seconds -= 1
		_update_timer_display()
	else:
		timer_label.text = "Tiempo: ¡AGOTADO! (baja la nota)"


func _update_timer_display() -> void:
	timer_label.text = "Tiempo: %02d:%02d" % [current_job_seconds / 60, current_job_seconds % 60]


func _on_pipe_rejected(_player_id: StringName, _socket_id: StringName, reason: StringName) -> void:
	var msg: String = "Acción inválida"
	if reason == &"occupied":
		msg = "Socket ocupado"
	elif reason == &"invalid_item":
		msg = "Herramienta inválida"
	elif reason == &"no_active_job":
		msg = "Primero acepta un trabajo en el teléfono [T]"
	_show_toast(msg)
	if error_sfx != null:
		error_sfx.play()


func _on_control_switched(player_id: StringName) -> void:
	_show_toast("Controlando: %s" % player_id)
	_hint_label.text = "   [%s]   [T] Teléfono   [F] Terminar   [C] Cambiar gasfíter   [Esc] Mouse" % player_id


func _on_api_error(_code: String, message: String) -> void:
	_show_toast(message)


func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.show()
	get_tree().create_timer(3.0).timeout.connect(func() -> void: toast_label.hide())
