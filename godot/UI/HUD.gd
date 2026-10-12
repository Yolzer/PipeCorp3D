class_name HUD
extends CanvasLayer
## Bottom bar + job timer + toasts. Node paths match HUD.tscn:
## Hud > MarginContainer > TopBar > MoneyLabel / XPLabel / TimerLabel ; Hud > FinishJobBtn
## ToastLabel and JobTimer are found whether they sit under Hud or under AnimationPlayer.
## Keys (UI layer): [F] finish job. The mouse is captured while playing, so the button alone is not enough.
## v1.1.0-alpha: rediseño por código con "chips" (mismo estilo que Opciones, Tienda y Teléfono).
## Las rutas del .tscn no cambian: el Doctor y las pruebas siguen funcionando.

@onready var money_label: Label = $MarginContainer/TopBar/MoneyLabel
@onready var xp_label: Label = $MarginContainer/TopBar/XPLabel
@onready var timer_label: Label = $MarginContainer/TopBar/TimerLabel
@onready var finish_job_btn: Button = $FinishJobBtn
@onready var toast_label: Label = _find_node(^"ToastLabel", ^"AnimationPlayer/ToastLabel") as Label
@onready var job_timer: Timer = _find_node(^"JobTimer", ^"AnimationPlayer/JobTimer") as Timer
@onready var error_sfx: AudioStreamPlayer = get_node_or_null(^"ErrorSFX") as AudioStreamPlayer

const COLOR_CHIP: Color = Color(0.07, 0.08, 0.11, 0.88)
const COLOR_DIM: Color = Color(0.68, 0.71, 0.78)
const COLOR_MONEY: Color = Color(0.35, 0.82, 0.45)
const COLOR_XP: Color = Color(0.6, 0.55, 1.0)
const COLOR_DAY: Color = Color(0.25, 0.56, 1.0)
const COLOR_VEHICLE: Color = Color(0.95, 0.65, 0.15)
const COLOR_TIMER: Color = Color(0.98, 0.76, 0.2)
const COLOR_ALERT: Color = Color(0.95, 0.33, 0.3)
const KEY_HINTS: Dictionary[String, String] = {
	"1 2": "Pieza", "T": "Teléfono", "B": "Tienda", "F": "Terminar", "C": "Cambiar", "P": "Pausa",
}

var current_job_seconds: int = 0
var hotbar: Hotbar = null
var _equipped: Dictionary[StringName, StringName] = {}   # player_id -> pieza equipada
var _day_label: Label = null
var _vehicle_label: Label = null
var _player_label: Label = null
var _toast_serial: int = 0


func _ready() -> void:
	visible = false   # the HUD appears only after login (it used to cover the main menu)
	SignalBus.login_succeeded.connect(func(_p: PlayerProfile) -> void: visible = true)
	toast_label.hide()
	job_timer.timeout.connect(_on_timer_tick)
	finish_job_btn.pressed.connect(_emit_finish)
	finish_job_btn.hide()
	hotbar = Hotbar.new()   # v1.0.5: 2 espacios, [1]/[2] o rueda del mouse
	add_child(hotbar)
	_apply_style()
	_make_click_through(self)
	timer_label.text = "Sin trabajo activo"
	SignalBus.profile_updated.connect(_on_profile_updated)
	SignalBus.job_started.connect(_on_job_started)
	SignalBus.job_graded.connect(_on_job_graded)
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.pipe_rejected.connect(_on_pipe_rejected)
	SignalBus.api_error.connect(_on_api_error)
	SignalBus.control_switched.connect(_on_control_switched)
	SignalBus.hotbar_changed.connect(_on_hotbar_changed)


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
	money_label.text = "CLP: %s" % ShopCatalog.clp(profile.money)
	xp_label.text = "XP: %d" % profile.xp
	if _day_label != null:
		_day_label.text = "Día %d" % profile.game_day
		_vehicle_label.text = profile.vehicle_name


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
	_set_chip_accent(timer_label, COLOR_DIM)


func _on_game_over(_reason: StringName) -> void:
	job_timer.stop()
	finish_job_btn.hide()


func _on_timer_tick() -> void:
	if current_job_seconds > 0:
		current_job_seconds -= 1
		_update_timer_display()
	else:
		timer_label.text = "Tiempo: ¡AGOTADO! (baja la nota)"
		_set_chip_accent(timer_label, COLOR_ALERT)


func _update_timer_display() -> void:
	timer_label.text = "Tiempo: %02d:%02d" % [current_job_seconds / 60, current_job_seconds % 60]
	_set_chip_accent(timer_label, COLOR_ALERT if current_job_seconds <= 15 else COLOR_TIMER)


func _on_pipe_rejected(_player_id: StringName, _socket_id: StringName, reason: StringName) -> void:
	var msg: String = "Acción inválida"
	if reason == &"occupied":
		msg = "Socket ocupado"
	elif reason == &"invalid_item":
		msg = "Herramienta inválida"
	elif reason == &"no_active_job":
		msg = "Primero acepta un trabajo en el teléfono [T]"
	_show_toast(msg, true)
	if error_sfx != null:
		error_sfx.play()


func _on_control_switched(player_id: StringName) -> void:
	_show_toast("Controlando: %s" % player_id)
	if _player_label != null:
		_player_label.text = String(player_id)


## Aviso solo cuando ESE gasfíter cambia de pieza (no al tomar el control).
func _on_hotbar_changed(player_id: StringName, _slot: int, item_code: StringName) -> void:
	var previous: StringName = _equipped.get(player_id, item_code)
	_equipped[player_id] = item_code
	if previous != item_code:
		_show_toast("Pieza: %s" % ShopCatalog.item_name(item_code))


func _on_api_error(_code: String, message: String) -> void:
	_show_toast(message, true)


func _show_toast(msg: String, is_error: bool = false) -> void:
	toast_label.text = msg
	_set_chip_accent(toast_label, COLOR_ALERT if is_error else COLOR_TIMER, true)
	toast_label.show()
	_toast_serial += 1
	var serial: int = _toast_serial   # un aviso nuevo no se oculta por el temporizador del anterior
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if serial == _toast_serial:
			toast_label.hide())


# ---------------- estilo (v1.1.0-alpha) ----------------
func _apply_style() -> void:
	# Barra inferior a todo el ancho, con chips a la izquierda y teclas a la derecha.
	var margin: MarginContainer = $MarginContainer
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_left = 0.0
	margin.offset_right = 0.0
	margin.offset_top = -48.0
	margin.offset_bottom = 0.0
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for side: String in ["margin_left", "margin_right", "margin_bottom", "margin_top"]:
		margin.add_theme_constant_override(side, 8)

	var bar: HBoxContainer = $MarginContainer/TopBar
	bar.add_theme_constant_override("separation", 8)
	_make_chip(money_label, COLOR_MONEY)
	_make_chip(xp_label, COLOR_XP)
	_day_label = _new_chip("DayLabel", "Día 1", COLOR_DAY)
	bar.add_child(_day_label)
	bar.move_child(_day_label, xp_label.get_index() + 1)
	_vehicle_label = _new_chip("VehicleLabel", "", COLOR_VEHICLE)
	bar.add_child(_vehicle_label)
	bar.move_child(_vehicle_label, _day_label.get_index() + 1)
	_make_chip(timer_label, COLOR_DIM)
	_player_label = _new_chip("PlayerLabel", "Player_1", COLOR_DIM)
	bar.add_child(_player_label)

	var spacer: Control = Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var hints: HBoxContainer = HBoxContainer.new()
	hints.name = "KeyHints"
	hints.add_theme_constant_override("separation", 10)
	for keys: String in KEY_HINTS:
		hints.add_child(_key_hint(keys, KEY_HINTS[keys]))
	bar.add_child(hints)

	# Aviso (toast): píldora centrada arriba.
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -320.0
	toast_label.offset_right = 320.0
	toast_label.offset_top = 18.0
	toast_label.offset_bottom = 54.0
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", Color.WHITE)
	toast_label.add_theme_font_size_override("font_size", 16)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_set_chip_accent(toast_label, COLOR_TIMER, true)

	# Botón "Terminar": verde, a la izquierda.
	finish_job_btn.text = "Terminar trabajo  [F]"
	finish_job_btn.offset_left = 16.0
	finish_job_btn.offset_right = 226.0
	finish_job_btn.offset_top = -20.0
	finish_job_btn.offset_bottom = 20.0
	var states: Dictionary[String, Color] = {
		"normal": Color(0.2, 0.55, 0.3), "hover": Color(0.25, 0.65, 0.36), "pressed": Color(0.16, 0.45, 0.24),
		"focus": Color(0.2, 0.55, 0.3),
	}
	for state: String in states:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = states[state]
		style.set_corner_radius_all(8)
		finish_job_btn.add_theme_stylebox_override(state, style)


func _chip_style(accent: Color, pill: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_CHIP
	style.border_color = accent
	if pill:
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
	else:
		style.border_width_left = 3
		style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _make_chip(label: Label, accent: Color) -> void:
	label.add_theme_stylebox_override("normal", _chip_style(accent))
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _set_chip_accent(label: Label, accent: Color, pill: bool = false) -> void:
	label.add_theme_stylebox_override("normal", _chip_style(accent, pill))


func _new_chip(node_name: String, text: String, accent: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	_make_chip(label, accent)
	return label


func _key_hint(keys: String, action: String) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap: Label = Label.new()
	cap.text = keys
	var cap_style: StyleBoxFlat = StyleBoxFlat.new()
	cap_style.bg_color = Color(0.9, 0.92, 0.96)
	cap_style.set_corner_radius_all(5)
	cap_style.border_width_bottom = 3
	cap_style.border_color = Color(0.55, 0.58, 0.65)
	cap_style.content_margin_left = 7.0
	cap_style.content_margin_right = 7.0
	cap_style.content_margin_top = 1.0
	cap_style.content_margin_bottom = 2.0
	cap.add_theme_stylebox_override("normal", cap_style)
	cap.add_theme_color_override("font_color", Color(0.08, 0.09, 0.12))
	cap.add_theme_font_size_override("font_size", 13)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(cap)
	var text: Label = Label.new()
	text.text = action
	text.add_theme_color_override("font_color", Color.WHITE)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.add_theme_constant_override("outline_size", 4)
	text.add_theme_font_size_override("font_size", 13)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(text)
	return box
