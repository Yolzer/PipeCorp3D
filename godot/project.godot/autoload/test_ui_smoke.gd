extends Node3D
## UI smoke test: rebuilds the EXACT node trees of Gemini's 5 scenes (from the editor
## screenshots), attaches the corrected scripts and plays the MVP loop against the API/mock.
##   PIPECORP_API_URL=http://127.0.0.1:3999 godot --headless --path . res://tests/TestUISmoke.tscn

var _passed: int = 0
var _failed: int = 0


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS [%s]" % label)
	else:
		_failed += 1
		printerr("FAIL [%s]" % label)


func _until(condition: Callable, timeout_s: float = 6.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var done: bool = condition.call()
		if done:
			return true
		await get_tree().process_frame
	return false


## Builds "Parent/Child" trees: spec = [[path, ClassName], ...] relative to root.
func _build(root_class: String, root_name: String, script_path: String, spec: Array) -> Node:
	var root: Node = ClassDB.instantiate(root_class)
	root.name = root_name
	if script_path != "":
		root.set_script(load(script_path))
	for entry: Variant in spec:
		var pair: Array = entry
		var path: String = pair[0]
		var cls: String = pair[1]
		var parent_path: String = path.get_base_dir()
		var parent: Node = root if parent_path == "" else root.get_node(NodePath(parent_path))
		var child: Node = ClassDB.instantiate(cls)
		child.name = path.get_file()
		parent.add_child(child)
	return root


func _press_key(code: Key) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	if not TestEnv.isolate(self):
		get_tree().quit(1)
		return
	if not await TestEnv.mock_is_up(self):
		return
	# World pieces: entity + controller + 3 sockets
	var entity: PlumberEntity = PlumberEntity.new()
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	var ray: RayCast3D = RayCast3D.new()
	ray.name = "RayCast3D"
	cam.add_child(ray)
	entity.add_child(cam)
	add_child(entity)
	var entity2: PlumberEntity = PlumberEntity.new()
	entity2.player_id = &"Player_2"
	var cam2: Camera3D = Camera3D.new()
	cam2.name = "Camera3D"
	var ray2: RayCast3D = RayCast3D.new()
	ray2.name = "RayCast3D"
	cam2.add_child(ray2)
	entity2.add_child(cam2)
	entity2.position = Vector3(3.0, 0.0, 0.0)
	add_child(entity2)
	var switched: Array[StringName] = []
	SignalBus.control_switched.connect(func(id: StringName) -> void: switched.append(id))
	var controller: PlayerController = PlayerController.new()
	controller.entity = entity
	add_child(controller)
	for i: int in 3:
		var s: GridSocket = GridSocket.new()
		s.socket_id = StringName("UI_S%d" % i)
		s.position = Vector3(200.0 + i, 0.0, 0.0)
		add_child(s)

	var hud: Node = _build("CanvasLayer", "Hud", "res://UI/HUD.gd", [
		["MarginContainer", "MarginContainer"], ["MarginContainer/TopBar", "HBoxContainer"],
		["MarginContainer/TopBar/MoneyLabel", "Label"], ["MarginContainer/TopBar/XPLabel", "Label"],
		["MarginContainer/TopBar/TimerLabel", "Label"], ["AnimationPlayer", "AnimationPlayer"],
		["AnimationPlayer/ToastLabel", "Label"], ["AnimationPlayer/JobTimer", "Timer"], ["FinishJobBtn", "Button"]])
	var phone: Node = _build("Control", "VirtualPhone", "res://UI/virtual_phone.gd", [
		["Panel", "Panel"], ["Panel/VBoxContainer", "VBoxContainer"], ["Panel/VBoxContainer/Label", "Label"],
		["Panel/VBoxContainer/RefreshBtn", "Button"], ["Panel/VBoxContainer/ScrollContainer", "ScrollContainer"],
		["Panel/VBoxContainer/ScrollContainer/TicketList", "VBoxContainer"], ["CloseBtn", "Button"]])
	var result_screen: Node = _build("CanvasLayer", "JobResultScreen", "res://UI/job_result_screen.gd", [
		["ColorRect", "ColorRect"], ["PanelContainer", "PanelContainer"], ["PanelContainer/VBox", "VBoxContainer"],
		["PanelContainer/VBox/Label", "Label"], ["PanelContainer/VBox/GradeLabel", "Label"],
		["PanelContainer/VBox/PayoutLabel", "Label"], ["PanelContainer/VBox/XPLabel", "Label"],
		["PanelContainer/VBox/CloseBtn", "Button"]])
	var over_screen: Node = _build("CanvasLayer", "GameOverScreen", "res://UI/game_over_screen.gd", [
		["ColorRect", "ColorRect"], ["ColorRect/VBoxContainer", "VBoxContainer"],
		["ColorRect/VBoxContainer/Title", "Label"], ["ColorRect/VBoxContainer/ReasonLabel", "Label"],
		["ColorRect/VBoxContainer/QuitBtn", "Button"]])
	var menu: Node = _build("Control", "MainMenu", "res://UI/MainMenu.gd", [
		["TextureRect", "TextureRect"], ["VBoxContainer", "VBoxContainer"], ["VBoxContainer/Title", "Label"],
		["VBoxContainer/PlayBtn", "Button"], ["VBoxContainer/ExitBtn", "Button"]])
	for n: Node in [hud, phone, result_screen, over_screen, menu]:
		add_child(n)
	await get_tree().process_frame

	var menu_ui: MainMenu = menu as MainMenu
	var hud_ui: HUD = hud as HUD
	var phone_ui: VirtualPhone = phone as VirtualPhone
	var result_ui: JobResultScreen = result_screen as JobResultScreen

	_check(menu_ui.visible and controller.entity == null, "U01 menu visible, controller waits for login (mouse free)")
	menu_ui.play_btn.pressed.emit()
	_check(await _until(func() -> bool: return not menu_ui.visible), "U02 'Iniciar Turno' -> login -> menu hidden")
	_check(controller.entity == entity, "U02 controller possessed the plumber after login")
	_check(await _until(func() -> bool: return hud_ui.money_label.text.begins_with("CLP: $")), "U03 HUD shows money from the API")

	await _press_key(KEY_T)
	_check(phone_ui.visible, "U04 [T] opens the phone")
	_check(await _until(func() -> bool: return phone_ui.ticket_list.get_child_count() >= 3), "U04 phone lists the tickets")
	var accept: Button = null
	for row: Node in phone_ui.ticket_list.get_children():
		for b: Node in row.find_children("*", "Button", true, false):
			var btn: Button = b as Button
			if btn.text == "Aceptar Trabajo" and accept == null:
				accept = btn
	_check(accept != null, "U05 PRIVATE ticket has 'Aceptar Trabajo', PUBLIC has 'Derivar'")
	accept.pressed.emit()
	_check(await _until(func() -> bool: return hud_ui.timer_label.text.begins_with("Tiempo:")), "U05 accept -> HUD timer running")
	_check(not phone_ui.visible, "U05 phone closes after accepting")

	for i: int in 3:
		SignalBus.intent_place_pipe.emit(&"Player_1", StringName("UI_S%d" % i), ItemCodes.PVC_90_DEG)
	await _press_key(KEY_F)
	_check(await _until(func() -> bool: return result_ui.visible), "U06 [F] finishes the job -> result screen visible")
	_check(result_ui.grade_label.text.begins_with("Rango: "), "U06 grade shown")
	result_ui.close_btn.pressed.emit()
	_check(not result_ui.visible, "U07 result screen closes")

	# --- Multi-plumber: [C] cycles possession and camera ---
	await _press_key(KEY_C)
	_check(controller.entity == entity2 and cam2.current, "U08 [C] switches control (and camera) to Player_2")
	_check(switched.size() >= 2 and switched[switched.size() - 1] == &"Player_2", "U08 control_switched(Player_2) emitted for the HUD")
	SignalBus.intent_place_pipe.emit(entity2.player_id, &"UI_S0", ItemCodes.PVC_90_DEG)
	await _press_key(KEY_C)
	_check(controller.entity == entity and cam.current, "U08 [C] again returns to Player_1")

	# --- Game Over -> [N] Nueva Carrera -> fresh account, UI back to play ---
	var over_ui: GameOverScreen = over_screen as GameOverScreen
	SignalBus.intent_touch_public_network.emit(&"Player_1", 0)
	_check(await _until(func() -> bool: return over_ui.visible), "U09 SISS tampering -> Game Over screen")
	_check(controller.entity == null, "U09 control released on Game Over")
	# Relaunch on the FIRED career (what happened in the real play-test): must stay on Game Over
	SignalBus.intent_login.emit("Player_1", "mvp_password_123")
	await _until(func() -> bool: return false, 1.0)
	_check(over_ui.visible and controller.entity == null, "U09 login into a fired career -> Game Over screen stays, no control")
	await _press_key(KEY_N)
	_check(await _until(func() -> bool: return not over_ui.visible), "U10 [N] Nueva Carrera -> new login, Game Over screen hides")
	_check(ApiClient.current_username() == "Player_1_c2" and CareerStore.current_career("Player_1") == 2, "U10 career 2 account in use and saved (binary)")
	_check(ApiClient.profile != null and not ApiClient.profile.is_game_over and is_equal_approx(ApiClient.profile.money, 50000.0), "U10 fresh profile: $50,000, not game over")
	_check(controller.entity != null, "U10 control given back after new career")

	print("\n=== UI SMOKE: %d passed, %d failed ===" % [_passed, _failed])
	SaveService.delete_snapshot()
	CareerStore.reset()
	get_tree().quit(0 if _failed == 0 else 1)
