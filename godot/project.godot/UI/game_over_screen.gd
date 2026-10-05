class_name GameOverScreen
extends CanvasLayer
## GameOverScreen > ColorRect > VBoxContainer > Title / ReasonLabel / QuitBtn

@onready var reason_label: Label = $ColorRect/VBoxContainer/ReasonLabel
@onready var quit_btn: Button = $ColorRect/VBoxContainer/QuitBtn


var new_career_btn: Button = null


func _ready() -> void:
	hide()
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.login_succeeded.connect(func(p: PlayerProfile) -> void:
		if not p.is_game_over:
			hide())
	# Built in code so GameOverScreen.tscn needs no editing.
	new_career_btn = Button.new()
	new_career_btn.name = "NewCareerBtn"
	new_career_btn.text = "Nueva Carrera [N]"
	quit_btn.add_sibling(new_career_btn)
	quit_btn.get_parent().move_child(new_career_btn, quit_btn.get_index())
	new_career_btn.pressed.connect(_on_new_career_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_N:
		_on_new_career_pressed()


func _on_new_career_pressed() -> void:
	new_career_btn.disabled = true
	new_career_btn.text = "Creando nueva carrera..."
	SignalBus.intent_new_career.emit()


func _on_game_over(reason: StringName) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if reason == &"BANKRUPTCY":
		reason_label.text = "Razón: Bancarrota. No puedes pagar tus costos operativos diarios."
	elif reason == &"SISS_TAMPERING":
		reason_label.text = "Razón: Intervención ilegal en la red pública SISS. Licencia revocada."
	else:
		reason_label.text = "Razón: Terminación de contrato."
	reason_label.text += "\nEl despido queda registrado. Puedes iniciar una nueva carrera."
	new_career_btn.disabled = false
	new_career_btn.text = "Nueva Carrera [N]"
	show()
