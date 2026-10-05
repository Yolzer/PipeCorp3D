class_name GridSocket
extends Area3D

@export var is_occupied: bool = false
@export var socket_id: String = ""

func _ready() -> void:
	if socket_id == "":
		socket_id = name
		
	# FORCE the real AI pipe to hide when the game starts
	if has_node("RealPipeMesh"):
		$RealPipeMesh.visible = false

# Added underscore to _pipe_mesh
func occupy(_pipe_mesh: Mesh) -> void:
	is_occupied = true
	$VisualSocket.visible = false # Hides the blue hologram
	$RealPipeMesh.visible = true  # Shows our new AI 3D pipe
