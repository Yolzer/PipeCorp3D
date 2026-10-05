@warning_ignore_start("unsafe_call_argument", "unsafe_property_access", "unsafe_method_access", "unsafe_cast", "untyped_declaration")
extends Node
## PipeCorp3D "Doctor": finds WHY scripts are not running. Open res://tests/Doctor.tscn and press F6.
## It deliberately references NO project class, so it still works when other scripts are broken.

const REQUIRED_CLASSES: PackedStringArray = [
	"PlayerProfile", "TicketData", "JobResult", "JsonUtil", "GridMath", "ItemCodes",
	"GridSocket", "SissZone", "PlumberEntity", "PlayerController",
	"MainMenu", "HUD", "VirtualPhone", "JobResultScreen", "GameOverScreen",
]
const REQUIRED_AUTOLOADS: PackedStringArray = ["SignalBus", "GridManager", "ApiClient", "JobSession", "SaveService"]
const FORBIDDEN_AUTOLOADS: PackedStringArray = ["GameManager", "NetworkManager"]
## World child name -> [expected class_name, required node paths ("A|B" = either one)]
const WORLD_NODES: Dictionary = {
	"MainMenu": ["MainMenu", ["VBoxContainer/PlayBtn", "VBoxContainer/ExitBtn"]],
	"Hud": ["HUD", ["MarginContainer/TopBar/MoneyLabel", "MarginContainer/TopBar/XPLabel", "MarginContainer/TopBar/TimerLabel",
		"FinishJobBtn", "ToastLabel|AnimationPlayer/ToastLabel", "JobTimer|AnimationPlayer/JobTimer"]],
	"VirtualPhone": ["VirtualPhone", ["Panel/VBoxContainer/ScrollContainer/TicketList", "Panel/VBoxContainer/RefreshBtn", "CloseBtn"]],
	"JobResultScreen": ["JobResultScreen", ["PanelContainer/VBox/GradeLabel", "PanelContainer/VBox/PayoutLabel",
		"PanelContainer/VBox/XPLabel", "PanelContainer/VBox/CloseBtn"]],
	"GameOverScreen": ["GameOverScreen", ["ColorRect/VBoxContainer/ReasonLabel", "ColorRect/VBoxContainer/QuitBtn"]],
	"PlayerController": ["PlayerController", []],
	"PlumberEntity": ["PlumberEntity", ["Camera3D", "Camera3D/RayCast3D"]],
}
const REQUIRED_SIGNALS: PackedStringArray = [
	"intent_login", "login_succeeded", "auth_failed", "profile_updated", "tickets_updated", "job_started",
	"job_graded", "game_over", "api_error", "intent_finish_job", "intent_accept_ticket", "intent_derive_ticket",
	"intent_refresh_tickets", "pipe_placed", "pipe_rejected", "job_completed",
]

var _problems: int = 0


func _ready() -> void:
	print("\n========== PIPECORP3D DOCTOR ==========")
	_check_scripts_compile()
	_check_duplicate_classes()
	_check_classes()
	_check_autoloads()
	_check_signals()
	_check_main_scene()
	_check_world_wiring()
	if _problems == 0:
		print("\n✔ ALL GOOD: 0 problems. If the UI still overlaps, check the CanvasLayer note in the guide.")
	else:
		print("\n✘ %d PROBLEM(S). Fix them top to bottom: the first one usually causes the rest." % _problems)
	print("=======================================\n")


func _bad(msg: String) -> void:
	_problems += 1
	printerr("  ✘ " + msg)


func _ok(msg: String) -> void:
	print("  ✔ " + msg)


func _all_scripts(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_all_scripts(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))


func _check_scripts_compile() -> void:
	print("\n[1] Scripts that FAIL TO COMPILE (a broken script = its node does nothing, e.g. never hides):")
	var files: PackedStringArray = PackedStringArray()
	_all_scripts("res://", files)
	var broken: int = 0
	for path: String in files:
		if path.ends_with("doctor.gd"):
			continue
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var script: GDScript = res as GDScript
		if script == null or not script.can_instantiate():
			broken += 1
			_bad("%s  → open it: the red error at the bottom of the script editor tells the exact line" % path)
	if broken == 0:
		_ok("%d scripts compile" % files.size())


func _check_duplicate_classes() -> void:
	print("\n[2] Duplicate class_name (two files declaring the same class break both):")
	var files: PackedStringArray = PackedStringArray()
	_all_scripts("res://", files)
	var re: RegEx = RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	var seen: Dictionary[String, String] = {}
	var dupes: int = 0
	for path: String in files:
		var m: RegExMatch = re.search(FileAccess.get_file_as_string(path))
		if m == null:
			continue
		var cls: String = m.get_string(1)
		if seen.has(cls):
			dupes += 1
			_bad("class_name %s in BOTH %s and %s → delete the old one" % [cls, seen[cls], path])
		else:
			seen[cls] = path
	if dupes == 0:
		_ok("no duplicates")


func _check_classes() -> void:
	print("\n[3] Required classes (from godot-sprint3.zip / godot-ui-fix.zip):")
	var registered: PackedStringArray = PackedStringArray()
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls_name: String = entry.get("class", "")
		registered.append(cls_name)
	for cls: String in REQUIRED_CLASSES:
		if registered.has(cls):
			_ok(cls)
		else:
			_bad("class_name %s NOT FOUND → copy its .gd file (or the UI script is not the new version)" % cls)


func _check_autoloads() -> void:
	print("\n[4] Autoloads (Project Settings → Globals), in this order: " + ", ".join(REQUIRED_AUTOLOADS))
	var order: PackedStringArray = PackedStringArray()
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key: String = prop.get("name", "")
		if key.begins_with("autoload/"):
			order.append(key.trim_prefix("autoload/"))
	for name: String in REQUIRED_AUTOLOADS:
		if get_tree().root.has_node(NodePath(name)):
			_ok(name + " loaded")
		else:
			_bad("autoload %s missing or failed to load" % name)
	for name: String in FORBIDDEN_AUTOLOADS:
		if order.has(name):
			_bad("autoload %s must be REMOVED (replaced by GridManager/ApiClient)" % name)
	var last: int = -1
	for name: String in REQUIRED_AUTOLOADS:
		var idx: int = order.find(name)
		if idx != -1 and idx < last:
			_bad("autoload order wrong: %s must come after the previous ones. Current order: %s" % [name, ", ".join(order)])
		last = maxi(last, idx)


func _check_signals() -> void:
	print("\n[5] SignalBus contract (SignalBus.gd must be the NEW version):")
	var bus: Node = get_tree().root.get_node_or_null(^"SignalBus")
	if bus == null:
		_bad("SignalBus not loaded")
		return
	var missing: int = 0
	for sig: String in REQUIRED_SIGNALS:
		if not bus.has_signal(sig):
			missing += 1
			_bad("SignalBus has no signal '%s' → replace SignalBus.gd with the godot-sprint3 version" % sig)
	if missing == 0:
		_ok("all %d contract signals present" % REQUIRED_SIGNALS.size())


func _check_main_scene() -> void:
	print("\n[6] Main scene:")
	var main: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main.to_lower().contains("world"):
		_ok("main scene = " + main)
	else:
		_bad("main scene is '%s' → set it to World.tscn (Project Settings → Application → Run)" % main)


func _check_world_wiring() -> void:
	print("\n[7] World.tscn wiring (is the RIGHT script attached to each instance? do the node paths exist?):")
	var main: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var packed: PackedScene = load(main) as PackedScene
	if packed == null:
		_bad("cannot load main scene " + main)
		return
	var world: Node = packed.instantiate()
	for node_name: String in WORLD_NODES:
		var spec: Array = WORLD_NODES[node_name]
		var expected: String = spec[0]
		var paths: Array = spec[1]
		var node: Node = world.find_child(node_name, true, false)
		if node == null:
			_bad("World has no node named '%s' (rename the instance exactly like that)" % node_name)
			continue
		var origin: String = node.scene_file_path if node.scene_file_path != "" else "World.tscn"
		var script: Script = node.get_script() as Script
		if script == null:
			_bad("%s has NO SCRIPT attached → open %s, select its ROOT node, drag the %s script onto the Script field, save" % [node_name, origin, expected])
			continue
		var got: String = script.get_global_name()
		if got != expected:
			_bad("%s runs script %s (class '%s') but needs class %s → attach the right script in %s" % [node_name, script.resource_path, got, expected, origin])
			continue
		var missing: PackedStringArray = PackedStringArray()
		for p: Variant in paths:
			var options: PackedStringArray = String(p).split("|")
			var found: bool = false
			for option: String in options:
				if node.has_node(NodePath(option)):
					found = true
			if not found:
				missing.append(String(p))
		if missing.is_empty():
			_ok("%s → %s (%s)" % [node_name, script.resource_path, origin])
		else:
			_bad("%s: missing child node(s) %s inside %s → rename/move them exactly like that" % [node_name, ", ".join(missing), origin])
		if node_name == "PlayerController" and node.get("entity") == null:
			_bad("PlayerController.Entity is EMPTY → select PlayerController, Inspector → Entity → assign PlumberEntity")
	world.free()
