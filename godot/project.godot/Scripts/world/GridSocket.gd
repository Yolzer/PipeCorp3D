class_name GridSocket
extends Area3D
## A fixed anchor point where a pipe can be installed. Collision layer 3 (Sockets).
## It self-registers with GridManager; ONLY GridManager may call occupy().

enum Facing { NORTH, EAST, SOUTH, WEST, UP, DOWN }

@export var socket_id: StringName = &""
@export var facing: Facing = Facing.NORTH

var cell: Vector3i = Vector3i.ZERO
var occupied_by: StringName = &""   ## item code installed here; empty = free
var is_occupied: bool:
	get:
		return occupied_by != &""

@onready var _visual_socket: Node3D = get_node_or_null(^"VisualSocket") as Node3D
@onready var _real_pipe: Node3D = get_node_or_null(^"RealPipeMesh") as Node3D
# Safely typed SFX reference to match Claude's architecture
@onready var _placement_sfx: AudioStreamPlayer3D = get_node_or_null(^"PlacementSFX") as AudioStreamPlayer3D


func _ready() -> void:
	if socket_id == &"":
		socket_id = StringName(name)
	cell = GridMath.world_to_cell(global_position)
	if _real_pipe != null:
		_real_pipe.visible = false
	GridManager.register_socket(self)


func _exit_tree() -> void:
	GridManager.unregister_socket(self)


## Called by GridManager after it validated the placement.
func occupy(item_code: StringName) -> void:
	occupied_by = item_code
	if _visual_socket != null:
		_visual_socket.visible = false
	if _real_pipe != null:
		_real_pipe.visible = true
	# Play the spatial sound if the node exists
	if _placement_sfx != null:
		_placement_sfx.play()
