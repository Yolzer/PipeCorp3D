class_name OptionsMenu
extends CanvasLayer
## Menú de Opciones (v1.0.3, ALPHA): SOLO VISUAL.
## Muestra los ajustes de Audio, Video, Controles y Juego, pero todavía no los aplica
## (los valores no se guardan ni cambian el motor). Se construye por código para no
## depender de un .tscn: el MainMenu y el PauseMenu lo crean con OptionsMenu.new().
## Funciona también con el juego en pausa (PROCESS_MODE_ALWAYS).

signal closed

const OPTIONS_LAYER: int = 120   # por encima del MainMenu (100) y del PauseMenu (110)
const PANEL_SIZE: Vector2 = Vector2(560, 420)

const RESOLUTIONS: PackedStringArray = ["1280 x 720", "1600 x 900", "1920 x 1080", "2560 x 1440"]
const QUALITY_LEVELS: PackedStringArray = ["Baja", "Media", "Alta", "Ultra"]
const LANGUAGES: PackedStringArray = ["Español", "English"]

## Valores por defecto que muestra la interfaz (y que restaura "Restablecer").
const DEFAULTS: Dictionary[String, Variant] = {
	"master": 80.0, "music": 70.0, "sfx": 90.0,
	"fullscreen": false, "vsync": true, "resolution": 0, "quality": 2,
	"sensitivity": 50.0, "invert_y": false,
	"language": 0, "show_hints": true,
}

var _sliders: Dictionary[String, HSlider] = {}
var _checks: Dictionary[String, CheckButton] = {}
var _selects: Dictionary[String, OptionButton] = {}
var _back_btn: Button = null


func _init() -> void:
	name = "OptionsMenu"
	layer = OPTIONS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_build_ui()
	reset_to_defaults()


# ---------------- API pública ----------------
func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_back_btn.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Devuelve la interfaz a los valores por defecto (solo visual).
func reset_to_defaults() -> void:
	for key: String in _sliders:
		_sliders[key].value = float(DEFAULTS[key])
	for key: String in _checks:
		_checks[key].button_pressed = bool(DEFAULTS[key])
	for key: String in _selects:
		_selects[key].select(int(DEFAULTS[key]))


## [Esc] cierra el menú sin que el PlayerController alterne el mouse.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------- construcción de la interfaz ----------------
func _build_ui() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # bloquea los clics al menú de abajo
	add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.15, 0.97)       # fondo opaco: no se ve el menú de atrás
	style.border_color = Color(0.16, 0.42, 0.85)          # azul PipeCorp
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = "OPCIONES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	_build_audio_tab(tabs)
	_build_video_tab(tabs)
	_build_controls_tab(tabs)
	_build_game_tab(tabs)

	var notice: Label = Label.new()
	notice.text = "Versión ALPHA: los ajustes son solo visuales y todavía no se aplican."
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	notice.add_theme_font_size_override("font_size", 13)
	root.add_child(notice)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	root.add_child(buttons)

	var reset_btn: Button = Button.new()
	reset_btn.name = "ResetBtn"
	reset_btn.text = "Restablecer"
	reset_btn.custom_minimum_size = Vector2(140, 36)
	reset_btn.pressed.connect(reset_to_defaults)
	buttons.add_child(reset_btn)

	_back_btn = Button.new()
	_back_btn.name = "BackBtn"
	_back_btn.text = "Volver"
	_back_btn.custom_minimum_size = Vector2(140, 36)
	_back_btn.pressed.connect(close)
	buttons.add_child(_back_btn)


func _new_tab(tabs: TabContainer, tab_name: String) -> GridContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.name = tab_name   # TabContainer usa el nombre del hijo como título de la pestaña
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	tabs.add_child(margin)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	margin.add_child(grid)
	return grid


func _build_audio_tab(tabs: TabContainer) -> void:
	var grid: GridContainer = _new_tab(tabs, "Audio")
	_add_slider(grid, "master", "Volumen general")
	_add_slider(grid, "music", "Música")
	_add_slider(grid, "sfx", "Efectos de sonido")


func _build_video_tab(tabs: TabContainer) -> void:
	var grid: GridContainer = _new_tab(tabs, "Video")
	_add_check(grid, "fullscreen", "Pantalla completa")
	_add_select(grid, "resolution", "Resolución", RESOLUTIONS)
	_add_select(grid, "quality", "Calidad gráfica", QUALITY_LEVELS)
	_add_check(grid, "vsync", "Sincronización vertical (VSync)")


func _build_controls_tab(tabs: TabContainer) -> void:
	var grid: GridContainer = _new_tab(tabs, "Controles")
	_add_slider(grid, "sensitivity", "Sensibilidad del mouse")
	_add_check(grid, "invert_y", "Invertir eje Y")
	_add_label_row(grid, "Teclas", "WASD mover · Clic instalar · T teléfono · F terminar · P pausa")


func _build_game_tab(tabs: TabContainer) -> void:
	var grid: GridContainer = _new_tab(tabs, "Juego")
	_add_select(grid, "language", "Idioma", LANGUAGES)
	_add_check(grid, "show_hints", "Mostrar ayudas en pantalla")


# ---------------- filas reutilizables ----------------
func _add_caption(grid: GridContainer, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(200, 0)
	grid.add_child(label)


func _add_slider(grid: GridContainer, key: String, text: String) -> void:
	_add_caption(grid, text)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider: HSlider = HSlider.new()
	slider.name = key
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float) -> void: value_label.text = "%d%%" % roundi(v))
	row.add_child(slider)
	row.add_child(value_label)
	grid.add_child(row)
	_sliders[key] = slider


func _add_check(grid: GridContainer, key: String, text: String) -> void:
	_add_caption(grid, text)
	var check: CheckButton = CheckButton.new()
	check.name = key
	grid.add_child(check)
	_checks[key] = check


func _add_select(grid: GridContainer, key: String, text: String, items: PackedStringArray) -> void:
	_add_caption(grid, text)
	var select: OptionButton = OptionButton.new()
	select.name = key
	for item: String in items:
		select.add_item(item)
	grid.add_child(select)
	_selects[key] = select


func _add_label_row(grid: GridContainer, caption: String, text: String) -> void:
	_add_caption(grid, caption)
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(260, 0)
	label.add_theme_font_size_override("font_size", 13)
	grid.add_child(label)
