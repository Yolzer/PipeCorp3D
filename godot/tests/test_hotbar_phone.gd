extends Node
## v1.0.5 test: 2-slot hotbar + redesigned phone. No API needed:
##   open res://tests/TestHotbarPhone.tscn and press F6

var _passed: int = 0
var _failed: int = 0
var _events: Array[StringName] = []


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS [%s]" % label)
	else:
		_failed += 1
		printerr("FAIL [%s]" % label)


func _key(code: Key) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func _ready() -> void:
	await _test_hotbar()
	await _test_phone()
	print("\n=== HOTBAR + PHONE DoD: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_hotbar() -> void:
	SignalBus.hotbar_changed.connect(func(_p: StringName, _s: int, item: StringName) -> void: _events.append(item))
	var entity: PlumberEntity = PlumberEntity.new()
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	var ray: RayCast3D = RayCast3D.new()
	ray.name = "RayCast3D"
	cam.add_child(ray)
	entity.add_child(cam)
	add_child(entity)
	var bar: Hotbar = Hotbar.new()
	add_child(bar)
	var controller: PlayerController = PlayerController.new()
	controller.possess_on_login = false
	add_child(controller)
	controller.possess(entity)
	await get_tree().process_frame

	_check(ItemCodes.HOTBAR_SLOTS.size() == 2, "H01 hotbar has exactly 2 slots")
	_check(entity.selected_item == ItemCodes.PVC_90_DEG and bar.selected_slot == 0, "H02 slot [1] (elbow 90°) equipped by default")
	controller._unhandled_input(_key(KEY_2))
	_check(entity.selected_item == ItemCodes.PVC_STRAIGHT and entity.hotbar_slot == 1, "H03 [2] equips the straight pipe")
	_check(bar.selected_slot == 1, "H04 hotbar UI highlights slot 2")
	controller._unhandled_input(_key(KEY_1))
	_check(entity.selected_item == ItemCodes.PVC_90_DEG and bar.selected_slot == 0, "H05 [1] goes back to the elbow")
	entity.select_slot(5)
	_check(entity.hotbar_slot == 1, "H06 wheel-style cycling wraps around (5 -> slot 2)")
	_check(_events.has(ItemCodes.PVC_STRAIGHT), "H07 hotbar_changed reaches SignalBus")
	_check(ItemCodes.is_placeable(ItemCodes.HOTBAR_SLOTS[0]) and ItemCodes.is_placeable(ItemCodes.HOTBAR_SLOTS[1]),
		"H08 both hotbar pieces are accepted by GridManager")
	var rank: Label = bar.find_child("Rank", true, false) as Label
	_check(rank != null and rank.text == "Rango F", "H09 tool rank F shown on the slot")
	controller.release()
	for n: Node in [controller, bar, entity]:
		n.queue_free()
	await get_tree().process_frame


func _ticket(id: int, zone: StringName, status: StringName) -> TicketData:
	var t: TicketData = TicketData.new()
	t.id = id
	t.zone = zone
	t.status = status
	t.description = "Contrato %d" % id
	t.budget = 8700.0
	t.estimated_parts = 2
	t.target_seconds = 75
	return t


func _test_phone() -> void:
	var phone: VirtualPhone = load("res://UI/VirtualPhone.tscn").instantiate() as VirtualPhone
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	layer.add_child(phone)
	await get_tree().process_frame
	var panel: Panel = phone.get_node(^"Panel") as Panel
	_check(panel.get_theme_stylebox("panel") is StyleBoxFlat, "P01 phone body uses the new rounded style")
	_check(phone.get_node(^"Panel/VBoxContainer").scale == Vector2.ONE and panel.scale == Vector2.ONE,
		"P02 old stretched scales removed (panel 1.4×1.16, list 0.91)")
	var tickets: Array[TicketData] = [_ticket(1, &"PRIVATE", &"OPEN"), _ticket(2, &"PUBLIC", &"OPEN")]
	SignalBus.tickets_updated.emit(tickets)
	await get_tree().process_frame
	_check(phone.ticket_list.get_child_count() == 2, "P03 one card per contract")
	var texts: PackedStringArray = PackedStringArray()
	for b: Node in phone.ticket_list.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	_check(texts.has("Aceptar Trabajo"), "P04 private card keeps 'Aceptar Trabajo'")
	_check(" ".join(texts).contains("Derivar"), "P05 public card offers 'Derivar a la SISS'")
	var meta_found: bool = false
	for l: Node in phone.ticket_list.find_children("*", "Label", true, false):
		if (l as Label).text.contains("$8.700"):
			meta_found = true
	_check(meta_found, "P06 budget shown in CLP format ($8.700)")
	var empty: Array[TicketData] = []
	SignalBus.tickets_updated.emit(empty)
	await get_tree().process_frame
	_check(phone.ticket_list.get_child_count() == 1, "P07 empty state message when there are no contracts")
	layer.queue_free()
	await get_tree().process_frame
