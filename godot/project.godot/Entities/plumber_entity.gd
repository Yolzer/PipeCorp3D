class_name PlumberEntity
extends CharacterBody3D

# --- CONFIGURATION & TUNING ---
@export var player_id: String = "Player_1"
@export var move_speed: float = 4.5
@export var acceleration: float = 12.0
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 9.8

# --- NODE REFERENCES ---
@onready var camera: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D

func _ready() -> void:
	print("[PlumberEntity] Initialized with ID: ", player_id)
	SignalBus.pipe_placed_successfully.connect(_on_pipe_placed_successfully)
	# Capture the mouse cursor inside the game window
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# 1. Escape key restores normal desktop mouse cursor
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# 2. First-person mouse look (Yaw on Body, Pitch on Camera)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		# Clamp pitch between ~ -85 and +85 degrees to avoid camera flips
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

	# 3. Raycast interaction triggers (SPACE or ENTER)
	if event.is_action_pressed("interact"):
		_handle_interaction_attempt()

func _physics_process(delta: float) -> void:
	# Apply gravity if in the air
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Read WASD directly via hardware keys (zero project settings setup needed)
	var raw_input: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		raw_input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		raw_input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		raw_input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		raw_input.x += 1.0

	var input_dir: Vector2 = raw_input.normalized()
	# Calculate move direction aligned with the character's facing direction
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var direction: Vector3 = (forward * -input_dir.y + right * input_dir.x).normalized()

	if direction != Vector3.ZERO:
		velocity.x = lerpf(velocity.x, direction.x * move_speed, acceleration * delta)
		velocity.z = lerpf(velocity.z, direction.z * move_speed, acceleration * delta)
	else:
		velocity.x = lerpf(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerpf(velocity.z, 0.0, acceleration * delta)

	move_and_slide()

func _handle_interaction_attempt() -> void:
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return
	var socket: GridSocket = raycast.get_collider() as GridSocket
	if socket == null:
		return
	if socket.is_occupied:
		print("[QA] Socket occupied: ", socket.socket_id)
		return
	SignalBus.intent_place_pipe.emit(socket.socket_id, "pvc_90_deg")

func _on_pipe_placed_successfully(confirmed_socket_id: String, coordinates: Vector3i) -> void:
	print("[PlumberEntity] Visual update received for: ", confirmed_socket_id, " at coords: ", coordinates)
