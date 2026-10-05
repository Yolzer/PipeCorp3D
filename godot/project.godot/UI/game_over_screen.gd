class_name GameOverScreen
extends CanvasLayer

@onready var reason_label: Label = $ColorRect/VBoxContainer/ReasonLabel
@onready var quit_btn: Button = $ColorRect/VBoxContainer/QuitBtn

func _ready() -> void:
	hide()
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	SignalBus.game_over.connect(_on_game_over)

func _on_game_over(reason: StringName) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if reason == &"BANKRUPTCY":
		reason_label.text = "Razón: Bancarrota. No puedes pagar tus costos operativos diarios."
	elif reason == &"SISS_TAMPERING":
		reason_label.text = "Razón: Intervención ilegal en la red pública SISS. Licencia revocada."
	else:
		reason_label.text = "Razón: Terminación de contrato."
		
	show()
