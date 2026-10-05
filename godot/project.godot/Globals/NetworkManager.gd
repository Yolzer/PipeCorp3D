extends Node

@onready var pipe_request: HTTPRequest = $PipeRequest

# Hardcoded for Sprint 2 testing, Claude will provide the real URL later
const API_URL: String = "http://localhost:3000/api/action/place-pipe"
var jwt_token: String = "" # Will be populated upon login in Sprint 3

func _ready() -> void:
	# Disconnect the mock GameManager and connect the real NetworkManager
	SignalBus.intent_place_pipe.connect(_on_intent_place_pipe)
	pipe_request.request_completed.connect(_on_pipe_request_completed)

func _on_intent_place_pipe(socket_id: String, pipe_type: String) -> void:
	print("[NetworkManager] Sending API request for: ", socket_id)
	
	var payload: Dictionary = {
		"socket_id": socket_id,
		"pipe_type": pipe_type,
		"player_id": "Player_1" # Hardcoded until multiplayer
	}
	
	var json_payload: String = JSON.stringify(payload)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	
	if jwt_token != "":
		headers.append("Authorization: Bearer " + jwt_token)
	
	var error: int = pipe_request.request(API_URL, headers, HTTPClient.METHOD_POST, json_payload)
	
	if error != OK:
		print("[NetworkManager] QA Error: HTTP request failed to initiate. Code: ", error)

func _on_pipe_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200 or response_code == 201:
		var response_str: String = body.get_string_from_utf8()
		var json: Variant = JSON.parse_string(response_str)
		
		if json and typeof(json) == TYPE_DICTIONARY and json.has("success") and json["success"] == true:
			print("[NetworkManager] Server confirmed! Emitting successful placement.")
			# Tell the visual world to update
			var coords: Vector3i = Vector3i(0, 0, 0) # Placeholder until backend provides real coords
			var socket_id: String = json.get("socket_id", "")
			SignalBus.pipe_placed_successfully.emit(socket_id, coords)
		else:
			print("[NetworkManager] Server rejected the action: ", response_str)
	else:
		print("[NetworkManager] Server HTTP Error: ", response_code)
