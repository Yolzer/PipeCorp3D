class_name ShopMenu
extends CanvasLayer
## Tienda (v1.0.4): compra de materiales y mejora de vehículo.
## Se abre con [B] o con el botón "Tienda" del teléfono. Solo EXPRESA INTENCIONES por SignalBus
## (intent_purchase / intent_upgrade_vehicle): el precio, la XP y la capacidad del vehículo
## los valida PostgreSQL. La interfaz se construye por código.

const SHOP_LAYER: int = 60          # sobre el teléfono (50), bajo el menú principal (100)
const PANEL_SIZE: Vector2 = Vector2(760, 470)
const MAX_QUANTITY: int = 20
const COLOR_OK: Color = Color(0.45, 0.9, 0.5)
const COLOR_ERROR: Color = Color(1.0, 0.45, 0.4)
const COLOR_LOCKED: Color = Color(0.65, 0.65, 0.65)

## Mensajes en español para los códigos de error de PostgreSQL (PC00x).
const ERROR_TEXT: Dictionary[String, String] = {
	"PC003": "Ese vehículo no es una mejora del actual.",
	"PC004": "Fondos insuficientes.",
	"PC005": "No cabe: la bodega del vehículo está llena. Mejora tu vehículo.",
	"PC006": "XP insuficiente para este vehículo.",
}

var _profile: PlayerProfile = null
var _stock: Dictionary[StringName, int] = {}
var _logged_in: bool = false
var _game_over: bool = false
var _pending: bool = false

var _info_label: Label = null
var _status_label: Label = null
var _items_box: VBoxContainer = null
var _vehicles_box: VBoxContainer = null
var _close_btn: Button = null
var _tabs: TabContainer = null


func _ready() -> void:
	layer = SHOP_LAYER
	visible = false
	_build_ui()
	SignalBus.intent_open_shop.connect(open_shop)
	SignalBus.login_succeeded.connect(_on_login)
	SignalBus.profile_updated.connect(_on_profile_updated)
	SignalBus.inventory_updated.connect(_on_inventory_updated)
	SignalBus.purchase_succeeded.connect(_on_purchase_succeeded)
	SignalBus.vehicle_upgraded.connect(_on_vehicle_upgraded)
	SignalBus.api_error.connect(_on_api_error)
	SignalBus.game_over.connect(func(_r: StringName) -> void:
		_game_over = true
		if visible:
			close_shop())


# ---------------- abrir / cerrar ----------------
func open_shop() -> void:
	if not _logged_in or _game_over:
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_status("", COLOR_OK)
	_refresh_all()
	SignalBus.intent_refresh_inventory.emit()
	_close_btn.grab_focus()


func close_shop() -> void:
	visible = false
	if not _game_over:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not _logged_in or _game_over:
		return
	if visible and event.is_action_pressed(&"ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_B and not get_tree().paused:
			if visible:
				close_shop()
			else:
				open_shop()
			get_viewport().set_input_as_handled()


# ---------------- señales ----------------
func _on_login(profile: PlayerProfile) -> void:
	_logged_in = true
	_game_over = false
	_profile = profile


func _on_profile_updated(profile: PlayerProfile) -> void:
	_profile = profile
	if visible:
		_refresh_all()


func _on_inventory_updated(stock: Dictionary[StringName, int]) -> void:
	_stock = stock
	if visible:
		_refresh_info()


func _on_purchase_succeeded(item_code: StringName, quantity: int) -> void:
	_pending = false
	_set_status("Compraste %d × %s." % [quantity, ShopCatalog.item_name(item_code)], COLOR_OK)


func _on_vehicle_upgraded(tier_id: int) -> void:
	_pending = false
	_set_status("¡Nuevo vehículo: %s!" % _vehicle(tier_id).get("name", "?"), COLOR_OK)


func _on_api_error(code: String, message: String) -> void:
	if not visible or not _pending:
		return
	_pending = false
	_set_status(ERROR_TEXT.get(code, message), COLOR_ERROR)


# ---------------- intenciones ----------------
func _buy(item_code: StringName, quantity_box: SpinBox) -> void:
	_pending = true
	_set_status("Comprando...", COLOR_LOCKED)
	SignalBus.intent_purchase.emit(item_code, int(quantity_box.value))


func _upgrade(tier_id: int) -> void:
	_pending = true
	_set_status("Mejorando vehículo...", COLOR_LOCKED)
	SignalBus.intent_upgrade_vehicle.emit(tier_id)


# ---------------- refresco de la vista ----------------
func _refresh_all() -> void:
	_refresh_info()
	_refresh_vehicles()


func _refresh_info() -> void:
	if _profile == null:
		_info_label.text = ""
		return
	_info_label.text = "Dinero: %s   ·   XP: %d   ·   Vehículo: %s   ·   Bodega: %d / %d" % [
		ShopCatalog.clp(_profile.money), _profile.xp, _profile.vehicle_name,
		ShopCatalog.used_volume(_stock), _profile.inventory_capacity]
	for row: Node in _items_box.get_children():
		var code: StringName = row.get_meta(&"item_code", &"")
		var stock_label: Label = row.get_node_or_null(^"Stock") as Label
		if stock_label != null:
			stock_label.text = "Tienes: %d" % _stock.get(code, 0)


func _refresh_vehicles() -> void:
	for child: Node in _vehicles_box.get_children():
		_vehicles_box.remove_child(child)   # fuera del árbol YA, así las filas nuevas conservan su nombre
		child.queue_free()
	var current_tier: int = _profile.vehicle_tier_id if _profile != null else 1
	var xp: int = _profile.xp if _profile != null else 0
	for vehicle: Dictionary in ShopCatalog.VEHICLES:
		_vehicles_box.add_child(_build_vehicle_row(vehicle, current_tier, xp))


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _vehicle(tier_id: int) -> Dictionary:
	for vehicle: Dictionary in ShopCatalog.VEHICLES:
		if int(vehicle["id"]) == tier_id:
			return vehicle
	return {}


# ---------------- construcción de la interfaz ----------------
func _build_ui() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.15, 0.97)
	style.border_color = Color(0.95, 0.65, 0.15)       # naranjo "ferretería"
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = "TIENDA PIPECORP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 14)
	root.add_child(_info_label)

	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_items_box = _new_tab("Materiales")
	for entry: Dictionary in ShopCatalog.ITEMS:
		_items_box.add_child(_build_item_row(entry))
	_vehicles_box = _new_tab("Vehículos")

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(0, 22)
	root.add_child(_status_label)

	var hint: Label = Label.new()
	hint.text = "Los precios, la XP y la capacidad los valida el servidor."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COLOR_LOCKED)
	root.add_child(hint)

	_close_btn = Button.new()
	_close_btn.name = "CloseBtn"
	_close_btn.text = "Cerrar Tienda  [B]"
	_close_btn.custom_minimum_size = Vector2(180, 36)
	_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_btn.pressed.connect(close_shop)
	root.add_child(_close_btn)


func _new_tab(tab_name: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = tab_name   # el nombre del hijo es el título de la pestaña
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	return box


func _row_container() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 40)
	return row


func _text(content: String, width: float, size: int = 15, color: Color = Color.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = content
	label.custom_minimum_size = Vector2(width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_item_row(entry: Dictionary) -> HBoxContainer:
	var code: StringName = entry["code"]
	var row: HBoxContainer = _row_container()
	row.name = String(code)
	row.set_meta(&"item_code", code)
	var name_box: VBoxContainer = VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(210, 0)
	name_box.add_child(_text(String(entry["name"]), 210))
	name_box.add_child(_text("%s · volumen %d" % [entry["category"], entry["volume"]], 210, 12, COLOR_LOCKED))
	row.add_child(name_box)
	row.add_child(_text(ShopCatalog.clp(float(entry["cost"])) + " c/u", 90))
	var stock: Label = _text("Tienes: 0", 80, 13, COLOR_LOCKED)
	stock.name = "Stock"
	row.add_child(stock)
	var quantity: SpinBox = SpinBox.new()
	quantity.name = "Quantity"
	quantity.min_value = 1
	quantity.max_value = MAX_QUANTITY
	quantity.value = 1
	row.add_child(quantity)
	var buy: Button = Button.new()
	buy.name = "BuyBtn"
	buy.text = "Comprar " + ShopCatalog.clp(float(entry["cost"]))
	buy.custom_minimum_size = Vector2(130, 0)
	quantity.value_changed.connect(func(v: float) -> void:
		buy.text = "Comprar " + ShopCatalog.clp(float(entry["cost"]) * v))
	buy.pressed.connect(_buy.bind(code, quantity))
	row.add_child(buy)
	return row


func _build_vehicle_row(vehicle: Dictionary, current_tier: int, xp: int) -> HBoxContainer:
	var tier_id: int = int(vehicle["id"])
	var required_xp: int = int(vehicle["required_xp"])
	var row: HBoxContainer = _row_container()
	row.name = "Tier%d" % tier_id
	var name_box: VBoxContainer = VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(210, 0)
	name_box.add_child(_text(String(vehicle["name"]), 210))
	name_box.add_child(_text("Bodega: %d unidades de volumen" % vehicle["capacity"], 210, 12, COLOR_LOCKED))
	row.add_child(name_box)
	row.add_child(_text(ShopCatalog.clp(float(vehicle["price"])), 90))
	row.add_child(_text("Requiere %d XP" % required_xp, 120, 13, COLOR_LOCKED))
	var action: Button = Button.new()
	action.name = "UpgradeBtn"
	action.custom_minimum_size = Vector2(150, 0)
	if tier_id == current_tier:
		action.text = "Vehículo actual"
		action.disabled = true
	elif tier_id < current_tier:
		action.text = "Ya superado"
		action.disabled = true
	elif xp < required_xp:
		action.text = "Bloqueado (%d XP)" % required_xp   # el servidor también lo rechaza (PC006)
		action.disabled = true
	else:
		action.text = "Mejorar"
		action.pressed.connect(_upgrade.bind(tier_id))
	row.add_child(action)
	return row
