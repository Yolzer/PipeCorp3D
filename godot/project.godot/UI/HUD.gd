class_name HUD
extends CanvasLayer

@onready var money_label: Label = $MarginContainer/HBoxContainer/MoneyLabel
@onready var xp_label: Label = $MarginContainer/HBoxContainer/XPLabel
@onready var timer_label: Label = $MarginContainer/HBoxContainer/TimerLabel
@onready var toast_label: Label = $ToastLabel
@onready var job_timer: Timer = $JobTimer
@onready var finish_job_btn: Button = $FinishJobBtn

var current_job_seconds: int = 0

func _ready() -> void:
	toast_label.hide()
	job_timer.timeout.connect(_on_timer_tick)
	
	# Connect to Claude's contract signals
	SignalBus.profile_updated.connect(_on_profile_updated)
	SignalBus.job_started.connect(_on_job_started)
	SignalBus.pipe_rejected.connect(_on_pipe_rejected)
	SignalBus.api_error.connect(_on_api_error)
	
	finish_job_btn.pressed.connect(func() -> void: SignalBus.intent_finish_job.emit())

func _on_profile_updated(profile: PlayerProfile) -> void:
	money_label.text = "CLP: $" + str(profile.money)
	xp_label.text = "XP: " + str(profile.xp) + " | Día: " + str(profile.game_day)

func _on_job_started(ticket: TicketData) -> void:
	current_job_seconds = ticket.target_seconds
	_update_timer_display()
	job_timer.start(1.0) # Tick every 1 second

func _on_timer_tick() -> void:
	if current_job_seconds > 0:
		current_job_seconds -= 1
		_update_timer_display()
	else:
		job_timer.stop()
		# Timer hit 0; grading logic is handled by backend, we just stop visually.

func _update_timer_display() -> void:
	var minutes: int = current_job_seconds / 60
	var seconds: int = current_job_seconds % 60
	timer_label.text = "Tiempo: %02d:%02d" % [minutes, seconds]

func _on_pipe_rejected(_player_id: StringName, _socket_id: StringName, reason: StringName) -> void:
	# Convert reason to player-facing text
	var msg: String = "Acción inválida"
	if reason == &"occupied":
		msg = "Socket ocupado"
	elif reason == &"invalid_item":
		msg = "Herramienta inválida"
		
	_show_toast(msg)
	# TODO: Trigger Buzz SFX here later

func _on_api_error(_code: String, message: String) -> void:
	_show_toast("API Error: " + message)

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.show()
	# Simple manual timer to hide it, or use AnimationPlayer
	get_tree().create_timer(3.0).timeout.connect(func() -> void: toast_label.hide())
