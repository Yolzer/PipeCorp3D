class_name Hotbar
extends Control
## Hotbar de 2 espacios (v1.0.5). Solo VISUAL: escucha SignalBus.hotbar_changed.
## [1] / [2] o la rueda del mouse cambian de pieza (lo lee el PlayerController, no este nodo).
## Cada espacio muestra la pieza que instala el clic y el rango de la herramienta (F–S).

const SLOT_SIZE: Vector2 = Vector2(170, 64)
const BOTTOM_GAP: float = 54.0          # deja libre la barra inferior del HUD
const COLOR_SELECTED: Color = Color(0.98, 0.76, 0.2)
const COLOR_IDLE: Color = Color(0.35, 0.38, 0.45)
const RANK_COLORS: Dictionary[String, Color] = {
	"F": Color(0.6, 0.6, 0.6), "E": Color(0.5, 0.8, 0.5), "D": Color(0.4, 0.75, 0.95),
	"C": Color(0.6, 0.55, 1.0), "B": Color(1.0, 0.6, 0.3), "A": Color(1.0, 0.4, 0.4), "S": Color(1.0, 0.85, 0.2),
}

var selected_slot: int = 0
var _slots: Array[PanelContainer] = []
var _active_player: StringName = &""


func _init() -> void:
	name = "Hotbar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Slots"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for i: int in ItemCodes.HOTBAR_SLOTS.size():
		var slot: PanelContainer = _build_slot(i, ItemCodes.HOTBAR_SLOTS[i])
		row.add_child(slot)
		_slots.append(slot)
	var width: float = SLOT_SIZE.x * _slots.size() + 10.0 * (_slots.size() - 1)
	offset_left = -width / 2.0
	offset_right = width / 2.0
	offset_top = -SLOT_SIZE.y - BOTTOM_GAP
	offset_bottom = -BOTTOM_GAP
	_highlight(0)
	SignalBus.control_switched.connect(func(id: StringName) -> void: _active_player = id)
	SignalBus.hotbar_changed.connect(_on_hotbar_changed)


func _on_hotbar_changed(player_id: StringName, slot: int, _item_code: StringName) -> void:
	if _active_player != &"" and player_id != _active_player:
		return
	_highlight(slot)


func _highlight(slot: int) -> void:
	selected_slot = slot
	for i: int in _slots.size():
		var selected: bool = i == slot
		_slots[i].add_theme_stylebox_override("panel", _slot_style(selected))
		_slots[i].modulate = Color.WHITE if selected else Color(1, 1, 1, 0.7)


func _build_slot(index: int, item_code: StringName) -> PanelContainer:
	var slot: PanelContainer = PanelContainer.new()
	slot.name = "Slot%d" % (index + 1)
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(box)
	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var key: Label = _label("[%d]" % (index + 1), 13, Color(0.8, 0.82, 0.88))
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(key)
	var rank: String = ItemCodes.STARTING_TOOL_RANK
	var rank_label: Label = _label("Rango %s" % rank, 12, RANK_COLORS.get(rank, Color.WHITE))
	rank_label.name = "Rank"
	top.add_child(rank_label)
	var item_label: Label = _label(ShopCatalog.item_name(item_code), 15, Color.WHITE)
	item_label.name = "Item"
	box.add_child(item_label)
	return slot


func _slot_style(selected: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.88) if selected else Color(0.08, 0.1, 0.14, 0.65)
	style.border_color = COLOR_SELECTED if selected else COLOR_IDLE
	style.set_border_width_all(3 if selected else 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	return label
