class_name AnimationController
extends Node3D

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var parent: CharacterBody3D = get_parent() as CharacterBody3D

var is_doing_action: bool = false

func _ready() -> void:
	# 1. Listen for when an animation finishes to resume walking/idling
	anim_player.animation_finished.connect(_on_animation_finished)
	
	# 2. Listen to the SignalBus for game events
	SignalBus.intent_place_pipe.connect(_on_interact)
	SignalBus.job_graded.connect(_on_job_graded)

func _unhandled_input(event: InputEvent) -> void:
	# Bonus: Press 'B' to dance at any time
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_B:
			_play_action("Magic_Genie") # Updated to play the correct dance

func _process(_delta: float) -> void:
	if parent == null or anim_player == null:
		return
		
	# Block the idle/walk logic if we are currently interacting or dancing
	if is_doing_action:
		return
		
	var speed: float = Vector2(parent.velocity.x, parent.velocity.z).length()
	
	if speed > 0.1:
		# Changed "walk" to "Walking" to match the actual play call perfectly
		if anim_player.current_animation != "Walking":
			anim_player.play("Walking")
	else:
		# Changed "idle" to "Idle_02" to match the actual play call perfectly
		if anim_player.current_animation != "Idle_02":
			anim_player.play("Idle_02")

# Safely attempts to play an action if the animation name exists
func _play_action(anim_name: String) -> void:
	if anim_player.has_animation(anim_name):
		is_doing_action = true
		anim_player.play(anim_name)

# Triggered when placing a pipe
func _on_interact(player_id: StringName, _socket_id: StringName, _item_code: StringName) -> void:
	# Ensure the player_id belongs to the parent so we don't animate on multiplayer events
	if "player_id" in parent and parent.get("player_id") == player_id:
		_play_action("mage_soell_cast_07")

# Triggered when the result screen pops up
func _on_job_graded(result: JobResult) -> void:
	# Dance if the player achieved a high score
	if result.grade == "S" or result.grade == "A":
		_play_action("Magic_Genie")

# Resets the block once the special animation concludes
func _on_animation_finished(anim_name: StringName) -> void:
	# We now check against the EXACT names of the action animations being played
	if anim_name == &"mage_soell_cast_07" or anim_name == &"Magic_Genie":
		is_doing_action = false
