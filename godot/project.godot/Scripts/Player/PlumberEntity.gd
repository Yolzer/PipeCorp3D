class_name PlumberEntity
extends CharacterBody3D
## The plumber's BODY: pure simulation, zero input reading.
## It is "possessed" by a PlayerController (local keyboard/mouse today, a network
## peer tomorrow) that writes intents: move_intent, apply_look(), request_interact().
## Required children: Camera3D (named "Camera3D") > RayCast3D (named "RayCast3D").

@export var player_id: StringName = &"Player_1"
@export var move_speed: float = 4.5
@export var acceleration: float = 12.0
@export var pitch_limit_deg: float = 85.0

## Same convention as Input.get_vector(): x = strafe (+right), y = forward (-) / back (+).
var move_intent: Vector2 = Vector2.ZERO
var selected_item: StringName = ItemCodes.PVC_90_DEG

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var camera: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D

const GROUP: StringName = &"plumber_entities"


func _ready() -> void:
	add_to_group(GROUP)   # lets SaveService find the body without a hard reference


func apply_look(yaw_delta: float, pitch_delta: float) -> void:
	rotate_y(yaw_delta)
	camera.rotate_x(pitch_delta)
	var limit: float = deg_to_rad(pitch_limit_deg)
	camera.rotation.x = clampf(camera.rotation.x, -limit, limit)


## Asks the authority to act on whatever the ray is aiming at. Never mutates the world itself.
func request_interact() -> void:
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return
	var collider: Object = raycast.get_collider()
	if collider is GridSocket:
		var socket: GridSocket = collider as GridSocket
		SignalBus.intent_place_pipe.emit(player_id, socket.socket_id, selected_item)
	elif collider is SissZone:
		var zone: SissZone = collider as SissZone
		SignalBus.intent_touch_public_network.emit(player_id, zone.ticket_id)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var direction: Vector3 = transform.basis * Vector3(move_intent.x, 0.0, move_intent.y)
	direction.y = 0.0
	direction = direction.normalized()

	var weight: float = minf(acceleration * delta, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * move_speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * move_speed, weight)
	move_and_slide()
