extends Control
## Game Over overlay. Shown when player_died fires.

@onready var _title: Label = $Title
@onready var _try_button: Button = $TryAgainButton
@onready var _background: ColorRect = $Background

func _ready() -> void:
	_try_button.pressed.connect(_on_try_again_pressed)
	hide()

func show_overlay() -> void:
	show()
	get_tree().paused = true

func _on_try_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()