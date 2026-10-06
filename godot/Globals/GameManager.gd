extends Node

# Added underscore to _pipe_type
func _on_player_intent_received(socket_id: String, _pipe_type: String) -> void:
	print("[GameManager] Intent received for ", socket_id, ". Validating inventory and space...")
	print("[GameManager] Validation passed. Telling the world to place the pipe.")
	SignalBus.pipe_placed_successfully.emit(socket_id, Vector3i(1, 0, 0))
