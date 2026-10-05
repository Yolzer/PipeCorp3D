class_name PlayerController
extends Node
## The plumber's BRAIN for the local player: the ONLY script that reads Input.
## Translates keyboard/mouse into intents for the possessed PlumberEntity.
## Co-op later: a second PlumberEntity is driven by network intents instead.

@export var entity: PlumberEntity
@export var mouse_sensitivity: float = 0.002

const MOVE_KEYS: Dictionary[StringName, Key] = {
	&"move_forward": KEY_W,
	&"move_back": KEY_S,
	&"move_left": KEY_A,
	&"move_right": KEY_D,
}


func _ready() -> void:
	process_physics_priority = -1   # write intents BEFORE the entity simulates this frame
	_ensure_default_actions()
	if entity != null:
		possess(entity)


func possess(target: PlumberEntity) -> void:
	if entity != null and entity != target:
		entity.move_intent = Vector2.ZERO
	entity = target
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
