class_name VirtualPhone
extends Control
## Ticket phone. Node paths match VirtualPhone.tscn:
## VirtualPhone > Panel > VBoxContainer > Label / RefreshBtn / ScrollContainer > TicketList ; VirtualPhone > CloseBtn
## Opens with [T] after login (before, nothing ever called show()).
## v1.0.5: rediseño visual por código (forma de teléfono, tarjetas por contrato). Los nodos
## del .tscn y sus rutas NO cambian, así el Doctor y las pruebas siguen funcionando.

@onready var ticket_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/TicketList
@onready var refresh_btn: Button = $Panel/VBoxContainer/RefreshBtn
@onready var close_btn: Button = _find_button(^"CloseBtn", ^"Panel/VBoxContainer/CloseBtn")

var _logged_in: bool = false
var _game_over: bool = false
var _status_money: Label = null


const PHONE_LAYER: int = 50
const PHONE_SIZE: Vector2 = Vector2(330, 580)
const MARGIN_LEFT: float = 42.0   # teléfono a la izquierda (mismo lugar en cualquier resolución)

const COLOR_BODY: Color = Color(0.06, 0.07, 0.1, 0.98)
const COLOR_BEZEL: Color = Color(0.22, 0.24, 0.3)
const COLOR_CARD: Color = Color(0.12, 0.14, 0.19)
const COLOR_TEXT_DIM: Color = Color(0.68, 0.71, 0.78)
const COLOR_PRIVATE: Color = Color(0.25, 0.56, 1.0)
const COLOR_PUBLIC: Color = Color(0.95, 0.33, 0.3)
const COLOR_ACTIVE: Color = Color(0.35, 0.82, 0.45)
const COLOR_BUTTON: Color = Color(0.18, 0.21, 0.28)


func _ready() -> void:
	hide()
	if not (get_parent() is CanvasLayer):
		_lift_to_layer.call_deferred()
	refresh_btn.pressed.connect(_on_refresh_pressed)
	_add_shop_button()
	close_btn.pressed.connect(close_phone)
	_apply_phone_style()
	SignalBus.tickets_updated.connect(_on_tickets_updated)
	SignalBus.profile_updated.connect(_on_profile_updated)
	SignalBus.login_succeeded.connect(func(_p: PlayerProfile) -> void:
		_logged_in = true
		_game_over = false)
	SignalBus.game_over.connect(func(_r: StringName) -> void:
		_game_over = true
		hide())


## v1.0.4: botón "Tienda" bajo "Actualizar Red" (creado por código, sin tocar el .tscn).
func _add_shop_button() -> void:
	var shop_btn: Button = Button.new()
	shop_btn.name = "ShopBtn"
	shop_btn.text = "Tienda  [B]"
	refresh_btn.get_parent().add_child(shop_btn)
	refresh_btn.get_parent().move_child(shop_btn, refresh_btn.get_index() + 1)
	shop_btn.pressed.connect(func() -> void:
		close_phone()
		SignalBus.intent_open_shop.emit())


func _lift_to_layer() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "PhoneLayer"
	layer.layer = PHONE_LAYER
	get_parent().add_child(layer)
	reparent(layer, false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _unhandled_input(event: InputEvent) -> void:
	if not _logged_in or _game_over or not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_T:
		if visible:
			close_phone()
		else:
			open_phone()
		get_viewport().set_input_as_handled()


## The close button may sit at the root or inside the panel's VBox (both layouts are supported).
func _find_button(primary: NodePath, fallback: NodePath) -> Button:
	var node: Node = get_node_or_null(primary)
	if node == null:
		node = get_node_or_null(fallback)
	return node as Button


func open_phone() -> void:
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SignalBus.intent_refresh_tickets.emit()


func close_phone() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_refresh_pressed() -> void:
	SignalBus.intent_refresh_tickets.emit()


func _on_profile_updated(profile: PlayerProfile) -> void:
	if _status_money != null:
		_status_money.text = "%s  ·  Día %d" % [ShopCatalog.clp(profile.money), profile.game_day]


func _on_tickets_updated(tickets: Array[TicketData]) -> void:
	for child: Node in ticket_list.get_children():
		ticket_list.remove_child(child)
		child.queue_free()
	var has_active_job: bool = false
	for ticket: TicketData in tickets:
		if ticket.status == &"ACCEPTED":
			has_active_job = true
	for ticket: TicketData in tickets:
		ticket_list.add_child(_build_row(ticket, has_active_job))
	if tickets.is_empty():
		var empty: Label = _label("No hay contratos por ahora.\nPulsa «Actualizar contratos».", 14, COLOR_TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ticket_list.add_child(empty)


# ---------------- tarjeta de contrato ----------------
func _build_row(ticket: TicketData, has_active_job: bool) -> PanelContainer:
	var accent: Color = COLOR_PRIVATE
	var tag: String = "PRIVADO  ·  DIFICULTAD %d" % ticket.difficulty
	if ticket.is_public():
		accent = COLOR_PUBLIC
		tag = "RED PÚBLICA  ·  JURISDICCIÓN SISS"
	elif ticket.status == &"ACCEPTED":
		accent = COLOR_ACTIVE
		tag = "EN CURSO"

	var t_panel: PanelContainer = PanelContainer.new()
	t_panel.name = "Ticket%d" % ticket.id
	t_panel.add_theme_stylebox_override("panel", _card_style(accent))
	var t_vbox: VBoxContainer = VBoxContainer.new()
	t_vbox.add_theme_constant_override("separation", 4)
	t_panel.add_child(t_vbox)

	t_vbox.add_child(_label(tag, 11, accent))
	t_vbox.add_child(_label(ticket.description, 16, Color.WHITE))
	var meta: String = "%s  ·  %d tuberías  ·  %d:%02d min" % [
		ShopCatalog.clp(ticket.budget), ticket.estimated_parts, ticket.target_seconds / 60, ticket.target_seconds % 60]
	t_vbox.add_child(_label(meta, 13, COLOR_TEXT_DIM))
	var expires_in: int = ticket.expires_at_unix - int(Time.get_unix_time_from_system())
	if ticket.status == &"OPEN" and expires_in > 0:
		t_vbox.add_child(_label("Expira en %d min" % ceili(expires_in / 60.0), 12, COLOR_TEXT_DIM))

	var hbox: HBoxContainer = HBoxContainer.new()
	t_vbox.add_child(hbox)
	var ticket_id: int = ticket.id
	if ticket.is_public():
		var derive_btn: Button = Button.new()
		derive_btn.text = "Derivar a la SISS (evita la multa)"
		derive_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(derive_btn, COLOR_PUBLIC.darkened(0.35))
		derive_btn.pressed.connect(func() -> void: SignalBus.intent_derive_ticket.emit(ticket_id))
		hbox.add_child(derive_btn)
	elif ticket.status == &"ACCEPTED":
		hbox.add_child(_label("Instala las tuberías y pulsa [F]", 13, COLOR_ACTIVE))
	else:
		var accept_btn: Button = Button.new()
		accept_btn.text = "Aceptar Trabajo"
		accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accept_btn.disabled = has_active_job
		if has_active_job:
			accept_btn.tooltip_text = "Termina el trabajo en curso primero."
		_style_button(accept_btn, COLOR_PRIVATE.darkened(0.3))
		accept_btn.pressed.connect(func() -> void:
			SignalBus.intent_accept_ticket.emit(ticket_id)
			close_phone())
		hbox.add_child(accept_btn)
	return t_panel


# ---------------- estilo (v1.0.5) ----------------
func _apply_phone_style() -> void:
	var panel: Panel = get_node_or_null(^"Panel") as Panel
	var vbox: VBoxContainer = get_node_or_null(^"Panel/VBoxContainer") as VBoxContainer
	if panel == null or vbox == null:
		return
	# Cuerpo del teléfono: anclado a la IZQUIERDA y centrado en vertical.
	panel.scale = Vector2.ONE   # el .tscn antiguo lo estiraba 1.4 × 1.16 y se salía de la pantalla
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # solo el cuerpo del teléfono recibe clics
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = MARGIN_LEFT
	panel.offset_right = MARGIN_LEFT + PHONE_SIZE.x
	panel.offset_top = -PHONE_SIZE.y / 2.0
	panel.offset_bottom = PHONE_SIZE.y / 2.0
	var body: StyleBoxFlat = StyleBoxFlat.new()
	body.bg_color = COLOR_BODY
	body.border_color = COLOR_BEZEL
	body.set_border_width_all(4)
	body.set_corner_radius_all(30)
	body.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	body.shadow_size = 14
	panel.add_theme_stylebox_override("panel", body)

	vbox.scale = Vector2.ONE
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18.0
	vbox.offset_right = -18.0
	vbox.offset_top = 14.0
	vbox.offset_bottom = -20.0
	vbox.add_theme_constant_override("separation", 8)

	# Barra de estado y "notch".
	var status: HBoxContainer = HBoxContainer.new()
	status.name = "StatusBar"
	var carrier: Label = _label("PipeCorp Móvil", 12, COLOR_TEXT_DIM)
	carrier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(carrier)
	_status_money = _label("", 12, COLOR_TEXT_DIM)
	_status_money.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.add_child(_status_money)
	vbox.add_child(status)
	vbox.move_child(status, 0)
	var notch: ColorRect = ColorRect.new()
	notch.color = COLOR_BEZEL
	notch.custom_minimum_size = Vector2(90, 5)
	notch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(notch)
	vbox.move_child(notch, 0)

	var title: Label = get_node_or_null(^"Panel/VBoxContainer/Label") as Label
	if title != null:
		title.text = "Contratos disponibles"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 21)

	refresh_btn.text = "Actualizar contratos"
	refresh_btn.remove_theme_font_size_override("font_size")
	_style_button(refresh_btn, COLOR_BUTTON)
	var shop_btn: Button = vbox.get_node_or_null(^"ShopBtn") as Button
	if shop_btn != null:
		_style_button(shop_btn, Color(0.45, 0.3, 0.08))

	var scroll: ScrollContainer = get_node_or_null(^"Panel/VBoxContainer/ScrollContainer") as ScrollContainer
	if scroll != null:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ticket_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ticket_list.add_theme_constant_override("separation", 10)

	if close_btn != null and close_btn.get_parent() == vbox:
		close_btn.text = "Cerrar teléfono  [T]"
		close_btn.remove_theme_font_size_override("font_size")
		_style_button(close_btn, COLOR_BUTTON)


func _label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _card_style(accent: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_CARD
	style.border_color = accent
	style.border_width_left = 4
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	return style


func _style_button(button: Button, color: Color) -> void:
	button.custom_minimum_size.y = 34.0
	var states: Dictionary[String, Color] = {
		"normal": color, "hover": color.lightened(0.15), "pressed": color.darkened(0.2),
		"focus": color, "disabled": Color(0.2, 0.2, 0.22),
	}
	for state: String in states:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = states[state]
		style.set_corner_radius_all(8)
		style.content_margin_left = 10.0
		style.content_margin_right = 10.0
		if state == "focus":
			style.draw_center = false
			style.border_color = Color(1, 1, 1, 0.5)
			style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
