class_name VirtualPhone
extends Control

@onready var ticket_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/TicketList
@onready var refresh_btn: Button = $Panel/VBoxContainer/RefreshBtn
@onready var close_btn: Button = $Panel/VBoxContainer/CloseBtn

func _ready() -> void:
	hide()
	refresh_btn.pressed.connect(_on_refresh_pressed)
	close_btn.pressed.connect(hide)
	
	# Connect to Claude's contract signals
	SignalBus.tickets_updated.connect(_on_tickets_updated)

func _on_refresh_pressed() -> void:
	SignalBus.intent_refresh_tickets.emit()

# Uses Claude's upcoming TicketData class
func _on_tickets_updated(tickets: Array[TicketData]) -> void:
	# Clear the existing list visually
	for child in ticket_list.get_children():
		child.queue_free()

	# Dynamically populate the list
	for ticket in tickets:
		var t_panel: PanelContainer = PanelContainer.new()
		var t_vbox: VBoxContainer = VBoxContainer.new()
		t_panel.add_child(t_vbox)

		var desc_label: Label = Label.new()
		desc_label.text = ticket.description + " (Presupuesto: $" + str(ticket.budget) + ")"
		t_vbox.add_child(desc_label)

		var hbox: HBoxContainer = HBoxContainer.new()
		t_vbox.add_child(hbox)

		if ticket.zone == &"PUBLIC":
			t_panel.modulate = Color(1.0, 0.4, 0.4) # Red tint for SISS jurisdiction
			var derive_btn: Button = Button.new()
			derive_btn.text = "Derivar SISS (Evitar Multa)"
			derive_btn.pressed.connect(func() -> void: _on_derive_pressed(ticket.id))
			hbox.add_child(derive_btn)
		else:
			var accept_btn: Button = Button.new()
			accept_btn.text = "Aceptar Trabajo"
			accept_btn.pressed.connect(func() -> void: _on_accept_pressed(ticket.id))
			hbox.add_child(accept_btn)

		ticket_list.add_child(t_panel)

func _on_accept_pressed(t_id: int) -> void:
	SignalBus.intent_accept_ticket.emit(t_id)
	hide() # Put phone away to start working

func _on_derive_pressed(t_id: int) -> void:
	SignalBus.intent_derive_ticket.emit(t_id)
