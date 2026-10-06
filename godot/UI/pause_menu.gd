class_name PauseMenu
extends CanvasLayer
## Menú de pausa básico: [P] pausa y reanuda el juego.
## Solo se activa mientras se juega (mouse capturado), así no interfiere con el menú principal,
## el teléfono ni la pantalla de Game Over. Salir es seguro: SaveService guarda en cada tubería.

@onready var resume_btn: Button = $CenterContainer/PanelContainer/VBoxContainer/ResumeBtn
@onready var quit_btn: Button = $CenterContainer/PanelContainer/VBoxContainer/QuitBtn

var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # sigue recibiendo teclas aunque el juego esté pausado
	layer = 110  # por encima del MainMenu (100)
	visible = false
	resume_btn.pressed.connect(_resume)
	quit_btn.pressed.connect(_quit)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if get_tree().paused:
		_resume()
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pause()
	else:
		return
	get_viewport().set_input_as_handled()


func _pause() -> void:
	_mouse_before = Input.mouse_mode
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_btn.grab_focus()


func _resume() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = _mouse_before


func _quit() -> void:
	get_tree().paused = false
	get_tree().quit()
