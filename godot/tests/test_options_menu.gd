extends Node
## Options menu test (v1.0.3). No API needed:
##   godot --headless --path . res://tests/TestOptionsMenu.tscn

var _passed: int = 0
var _failed: int = 0


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS [%s]" % label)
	else:
		_failed += 1
		printerr("FAIL [%s]" % label)


func _ready() -> void:
	await _test_main_menu()
	await _test_pause_menu()
	print("\n=== OPTIONS MENU DoD: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_main_menu() -> void:
	var menu: Control = load("res://UI/main_menu.tscn").instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var main_menu: MainMenu = menu as MainMenu
	var box: Node = main_menu.play_btn.get_parent()
	var options_btn: Button = box.get_node_or_null(^"OptionsBtn") as Button
	_check(options_btn != null, "O01 main menu has an Opciones button")
	_check(options_btn != null and options_btn.get_index() == main_menu.exit_btn.get_index() - 1,
		"O02 Opciones sits between Iniciar Turno and Salir")
	var options: OptionsMenu = main_menu.options_menu
	_check(options != null and not options.is_open(), "O03 options menu starts hidden")
	options_btn.pressed.emit()
	_check(options.is_open(), "O04 pressing Opciones opens the options menu")
	_check(options.layer > 100, "O05 options layer is above the main menu")
	var tabs: TabContainer = options.find_children("*", "TabContainer", true, false)[0] as TabContainer
	_check(tabs.get_tab_count() == 4, "O06 four tabs: Audio, Video, Controles, Juego")
	var slider: HSlider = options.find_child("master", true, false) as HSlider
	slider.value = 10.0
	(options.find_child("ResetBtn", true, false) as Button).pressed.emit()
	_check(is_equal_approx(slider.value, 80.0), "O07 Restablecer restores the default values")
	(options.find_child("BackBtn", true, false) as Button).pressed.emit()
	_check(not options.is_open(), "O08 Volver closes the options menu")
	var version_label: Label = main_menu.get_node_or_null(^"VersionLabel") as Label
	_check(version_label != null and version_label.text.contains("1.0.3"), "O09 version label shows v1.0.3")
	menu.queue_free()
	await get_tree().process_frame


func _test_pause_menu() -> void:
	var pause: PauseMenu = load("res://UI/PauseMenu.tscn").instantiate() as PauseMenu
	add_child(pause)
	await get_tree().process_frame
	var options_btn: Button = pause.find_child("OptionsBtn", true, false) as Button
	_check(options_btn != null, "O10 pause menu has an Opciones button")
	var options: OptionsMenu = pause.find_child("OptionsMenu", true, false) as OptionsMenu
	options_btn.pressed.emit()
	_check(options.is_open() and options.process_mode == Node.PROCESS_MODE_ALWAYS,
		"O11 options opens from pause and keeps working while paused")
	options.close()
	pause.queue_free()
	await get_tree().process_frame
