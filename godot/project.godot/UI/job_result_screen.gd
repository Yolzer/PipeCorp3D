class_name JobResultScreen
extends CanvasLayer

@onready var grade_label: Label = $PanelContainer/VBox/GradeLabel
@onready var payout_label: Label = $PanelContainer/VBox/PayoutLabel
@onready var xp_label: Label = $PanelContainer/VBox/XPLabel
@onready var close_btn: Button = $PanelContainer/VBox/CloseBtn

func _ready() -> void:
	hide()
	close_btn.pressed.connect(_on_close_pressed)
	
	# Connect to Claude's contract signals
	SignalBus.job_graded.connect(_on_job_graded)

# Uses Claude's upcoming JobResult class
func _on_job_graded(result: JobResult) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Free the mouse so they can click 'Aceptar'
	
	grade_label.text = "Rango: " + result.grade
	payout_label.text = "Pago: $" + str(result.payout)
	xp_label.text = "Experiencia: +" + str(result.xp_gained)
	
	# Dynamic color grading
	match result.grade:
		"S":
			grade_label.modulate = Color(1.0, 0.84, 0.0) # Gold
		"F":
			grade_label.modulate = Color(1.0, 0.2, 0.2) # Red
		_:
			grade_label.modulate = Color(1.0, 1.0, 1.0) # White
			
	show()

func _on_close_pressed() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Lock mouse back to gameplay
