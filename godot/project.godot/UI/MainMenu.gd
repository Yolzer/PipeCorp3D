class_name MainMenu
extends Control

@onready var play_btn: Button = $VBoxContainer/PlayBtn
@onready var exit_btn: Button = $VBoxContainer/ExitBtn

func _ready() -> void:
	play_btn.pressed.connect(_on_play_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)
	
	# Listen for successful background login to start the game loop
	SignalBus.login_succeeded.connect(_on_login_succeeded)
	
	# Ensure the mouse is free to click the UI
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_play_pressed() -> void:
	play_btn.disabled = true
	play_btn.text = "Conectando SISS..."
	
	# Bypass the login screen by sending a default player credential directly to Claude's API
	SignalBus.intent_login.emit("Player_1", "mvp_password_123")

func _on_login_succeeded(_profile: PlayerProfile) -> void:
	hide()
	# Lock the mouse back to the center of the screen for the FPS controller
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_exit_pressed() -> void:
	get_tree().quit()
