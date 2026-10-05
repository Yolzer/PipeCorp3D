class_name PlayerController
extends Node
## The plumber's BRAIN for the local player: the ONLY script that reads Input.
## Translates keyboard/mouse into intents for the possessed PlumberEntity.
## Co-op later: a second PlumberEntity is driven by network intents instead.

@export var entity: PlumberEntity
@export var mouse_sensitivity: float = 0.002
## true: take control (and capture the mouse) only after login, so the Main Menu stays clickable.
@export var possess_on_login: bool = true

const MOVE_KEYS: Dictionary[StringName, Key] = {
	&"move_forward": KEY_W,
	&"move_back": KEY_S,
	&"move_left": KEY_A,
	&"move_right": KEY_D,
}


func _ready() -> void:
	process_physics_priority = -1   # write intents BEFORE the entity simulates this frame
	_ensure_default_actions()
	SignalBus.intent_switch_plumber.connect(switch_to_next)
	if entity == null:
		return
	if possess_on_login:
		var body: PlumberEntity = entity
		entity = null   # no control (and free mouse) until the player logs in
		SignalBus.login_succeeded.connect(func(_p: PlayerProfile) -> void: possess(body))
		SignalBus.game_over.connect(func(_r: StringName) -> void: release())
	else:
		possess(entity)


func possess(target: PlumberEntity) -> void:
	if entity != null and entity != target:
		entity.move_intent = Vector2.ZERO
	entity = target
	if entity.is_inside_tree():
		entity.camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SignalBus.control_switched.emit(entity.player_id)


## All plumbers in the scene, sorted by player_id (Player_1, Player_2...).
func plumbers() -> Array[PlumberEntity]:
	var result: Array[PlumberEntity] = []
	for node: Node in get_tree().get_nodes_in_group(PlumberEntity.GROUP):
		if node is PlumberEntity:
			result.append(node as PlumberEntity)
	result.sort_custom(func(a: PlumberEntity, b: PlumberEntity) -> bool: return String(a.player_id) < String(b.player_id))
	return result


## [C]: hand control to the next plumber. The previous one stops (its body stays in the world).
func switch_to_next() -> void:
	if entity == null:
		return
	var list: Array[PlumberEntity] = plumbers()
	if list.size() < 2:
		SignalBus.api_error.emit("CTRL", "Solo hay un gasfíter en la escena.")
		return
	var index: int = list.find(entity)
	possess(list[(index + 1) % list.size()])


func release() -> void:
	if entity != null:
		entity.move_intent = Vector2.ZERO
	entity = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		return
	if entity == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		entity.apply_look(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event.is_action_pressed(&"interact"):
		entity.request_interact()
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_C:
			switch_to_next()


func _physics_process(_delta: float) -> void:
	if entity == null:
		return
	entity.move_intent = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## Registers WASD + left click if they are missing from Project Settings > Input Map.
func _ensure_default_actions() -> void:
	for action: StringName in MOVE_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key_event: InputEventKey = InputEventKey.new()
			key_event.physical_keycode = MOVE_KEYS[action]
			InputMap.action_add_event(action, key_event)
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(&"interact", click)
