class_name VirtualPhone
extends Control
## Ticket phone. Node paths match VirtualPhone.tscn:
## VirtualPhone > Panel > VBoxContainer > Label / RefreshBtn / ScrollContainer > TicketList ; VirtualPhone > CloseBtn
## Opens with [T] after login (before, nothing ever called show()).

@onready var ticket_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/TicketList
@onready var refresh_btn: Button = $Panel/VBoxContainer/RefreshBtn
@onready var close_btn: Button = _find_button(^"CloseBtn", ^"Panel/VBoxContainer/CloseBtn")

var _logged_in: bool = false
var _game_over: bool = false


const PHONE_LAYER: int = 50


func _ready() -> void:
	hide()
	if not (get_parent() is CanvasLayer):
		_lift_to_layer.call_deferred()
	refresh_btn.pressed.connect(_on_refresh_pressed)
	close_btn.pressed.connect(close_phone)
	SignalBus.tickets_updated.connect(_on_tickets_updated)
	SignalBus.login_succeeded.connect(func(_p: PlayerProfile) -> void:
		_logged_in = true
		_game_over = false)
	SignalBus.game_over.connect(func(_r: StringName) -> void:
		_game_over = true
		hide())


func _lift_to_layer() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "PhoneLayer"
	layer.layer = PHONE_LAYER
	get_parent().add_child(layer)
	reparent(layer, false)


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


func _on_tickets_updated(tickets: Array[TicketData]) -> void:
	for child: Node in ticket_list.get_children():
		child.queue_free()
	var has_active_job: bool = false
	for ticket: TicketData in tickets:
		if ticket.status == &"ACCEPTED":
			has_active_job = true
	for ticket: TicketData in tickets:
		ticket_list.add_child(_build_row(ticket, has_active_job))


func _build_row(ticket: TicketData, has_active_job: bool) -> PanelContainer:
	var t_panel: PanelContainer = PanelContainer.new()
	var t_vbox: VBoxContainer = VBoxContainer.new()
	t_panel.add_child(t_vbox)
	var desc_label: Label = Label.new()
	desc_label.text = "%s\nPresupuesto: $%d · %d tuberías · %ds" % [
		ticket.description, roundi(ticket.budget), ticket.estimated_parts, ticket.target_seconds]
	t_vbox.add_child(desc_label)
	var hbox: HBoxContainer = HBoxContainer.new()
	t_vbox.add_child(hbox)
	var ticket_id: int = ticket.id
	if ticket.is_public():
		t_panel.modulate = Color(1.0, 0.4, 0.4)
		var derive_btn: Button = Button.new()
		derive_btn.text = "Derivar SISS (Evitar Multa)"
		derive_btn.pressed.connect(func() -> void: SignalBus.intent_derive_ticket.emit(ticket_id))
		hbox.add_child(derive_btn)
	elif ticket.status == &"ACCEPTED":
		var busy: Label = Label.new()
		busy.text = "EN CURSO — instala las tuberías y pulsa [F]"
		hbox.add_child(busy)
	else:
		var accept_btn: Button = Button.new()
		accept_btn.text = "Aceptar Trabajo"
		accept_btn.disabled = has_active_job
		accept_btn.pressed.connect(func() -> void:
			SignalBus.intent_accept_ticket.emit(ticket_id)
			close_phone())
		hbox.add_child(accept_btn)
	return t_panel
