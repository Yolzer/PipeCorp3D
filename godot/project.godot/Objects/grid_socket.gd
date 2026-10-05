class_name GridSocket
extends Area3D

@export var is_occupied: bool = false
@export var socket_id: String = ""

@onready var visual_socket: Node3D = $VisualSocket
@onready var real_pipe_mesh: Node3D = $RealPipeMesh

func _ready() -> void:
	if socket_id == "":
		socket_id = name
	real_pipe_mesh.visible = false

func occupy() -> void:
	is_occupied = true
	visual_socket.visible = false
	real_pipe_mesh.visible = true
