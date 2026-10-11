class_name MainMenu
extends Control
## Start screen. Talks ONLY through SignalBus. Shows the real error if login fails
## (before, the button stayed in "Conectando..." forever with no feedback).

const MVP_USER: String = "Player_1"
const MVP_PASSWORD: String = "mvp_password_123"

@onready var play_btn: Button = $VBoxContainer/PlayBtn
@onready var exit_btn: Button = $VBoxContainer/ExitBtn

var options_btn: Button = null
var options_menu: OptionsMenu = null


const MENU_LAYER: int = 100


func _ready() -> void:
	# A plain Control draws UNDER every CanvasLayer (HUD, result, game over), so their
	# full-screen containers swallowed the click on "Iniciar Turno". Lift the menu on top.
	if not (get_parent() is CanvasLayer):
		_lift_to_layer.call_deferred()
	play_btn.pressed.connect(_on_play_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)
	_add_options_button()
	_add_version_label()
	SignalBus.login_succeeded.connect(_on_login_succeeded)
	SignalBus.auth_failed.connect(_on_login_failed)
	SignalBus.api_error.connect(_on_api_error)
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _lift_to_layer() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "MenuLayer"
	layer.layer = MENU_LAYER
	get_parent().add_child(layer)
	reparent(layer, false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	print("[MainMenu] ready on CanvasLayer %d" % MENU_LAYER)


## v1.0.3: botón "Opciones" entre "Iniciar Turno" y "Salir" (creado por código, sin tocar el .tscn).
func _add_options_button() -> void:
	options_btn = Button.new()
	options_btn.name = "OptionsBtn"
	options_btn.text = "Opciones"
	play_btn.get_parent().add_child(options_btn)
	play_btn.get_parent().move_child(options_btn, exit_btn.get_index())
	options_btn.pressed.connect(_on_options_pressed)
	options_menu = OptionsMenu.new()
	add_child(options_menu)
	options_menu.closed.connect(func() -> void: options_btn.grab_focus())


func _on_options_pressed() -> void:
	options_menu.open()


## Versión visible en la esquina inferior derecha (Project Settings > Application > Config > Version).
func _add_version_label() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if version == "":
		return
	var label: Label = Label.new()
	label.name = "VersionLabel"
	label.text = "PipeCorp3D v" + version
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_left = -260.0
	label.offset_top = -32.0
	label.offset_right = -12.0
	label.offset_bottom = -8.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)


func _on_play_pressed() -> void:
	print("[MainMenu] Iniciar Turno pressed -> intent_login")
	play_btn.disabled = true
	play_btn.text = "Conectando SISS..."
	SignalBus.intent_login.emit(MVP_USER, MVP_PASSWORD)


func _on_login_succeeded(_profile: PlayerProfile) -> void:
	hide()   # PlayerController captures the mouse when it receives login_succeeded


func _on_login_failed(message: String) -> void:
	_reset_button(message)


func _on_api_error(_code: String, message: String) -> void:
	if visible and play_btn.disabled:
		_reset_button(message)


func _reset_button(message: String) -> void:
	play_btn.disabled = false
	play_btn.text = "Reintentar (%s)" % message
	push_warning("[MainMenu] Login failed: " + message)


func _on_exit_pressed() -> void:
	get_tree().quit()
