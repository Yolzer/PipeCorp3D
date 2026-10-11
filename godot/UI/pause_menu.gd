class_name PauseMenu
extends CanvasLayer
## Menú de pausa básico: [P] pausa y reanuda el juego.
## Solo se activa mientras se juega (mouse capturado), así no interfiere con el menú principal,
## el teléfono ni la pantalla de Game Over. Salir es seguro: SaveService guarda en cada tubería.

@onready var resume_btn: Button = $CenterContainer/PanelContainer/VBoxContainer/ResumeBtn
@onready var quit_btn: Button = $CenterContainer/PanelContainer/VBoxContainer/QuitBtn

var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _options_btn: Button = null
var _options: OptionsMenu = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # sigue recibiendo teclas aunque el juego esté pausado
	layer = 110  # por encima del MainMenu (100)
	visible = false
	resume_btn.pressed.connect(_resume)
	quit_btn.pressed.connect(_quit)
	_add_options_button()


## v1.0.3: "Opciones" entre "Reanudar" y "Salir del juego" (creado por código, sin tocar el .tscn).
func _add_options_button() -> void:
	_options_btn = Button.new()
	_options_btn.name = "OptionsBtn"
	_options_btn.text = "Opciones"
	resume_btn.get_parent().add_child(_options_btn)
	resume_btn.get_parent().move_child(_options_btn, quit_btn.get_index())
	_options = OptionsMenu.new()
	add_child(_options)
	_options_btn.pressed.connect(_options.open)
	_options.closed.connect(func() -> void: _options_btn.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if _options != null and _options.is_open():
		return   # con Opciones abierto, [P] no reanuda (primero "Volver" o [Esc])
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
