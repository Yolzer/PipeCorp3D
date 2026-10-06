class_name JobResultScreen
extends CanvasLayer
## JobResultScreen > ColorRect ; PanelContainer > VBox > Label / GradeLabel / PayoutLabel / XPLabel / CloseBtn

@onready var grade_label: Label = $PanelContainer/VBox/GradeLabel
@onready var payout_label: Label = $PanelContainer/VBox/PayoutLabel
@onready var xp_label: Label = $PanelContainer/VBox/XPLabel
@onready var close_btn: Button = $PanelContainer/VBox/CloseBtn


func _ready() -> void:
	hide()
	close_btn.pressed.connect(_on_close_pressed)
	SignalBus.job_graded.connect(_on_job_graded)


func _on_job_graded(result: JobResult) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	grade_label.text = "Rango: " + result.grade
	payout_label.text = "Pago: $%d" % roundi(result.payout)
	xp_label.text = "Experiencia: +%d" % result.xp_gained
	match result.grade:
		"S":
			grade_label.modulate = Color(1.0, 0.84, 0.0)
		"F":
			grade_label.modulate = Color(1.0, 0.2, 0.2)
		_:
			grade_label.modulate = Color(1.0, 1.0, 1.0)
	show()


func _on_close_pressed() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
