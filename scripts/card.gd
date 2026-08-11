extends Control
## A recruit card with 2 options. The player taps one of the options to
## spawn an Army of that type. Once chosen, the card animates away.
##
## Each option is a sub-Control with metadata describing the army stats
## to spawn. The CardManager reads option metadata when this card emits
## option_chosen().

## Emitted when the player picks an option. The argument is a Dictionary
## with the option's data (e.g. { "type": "speed", "speed": 80, "hp": 1 }).
signal option_chosen(option: Dictionary)

## Two slots for option metadata. Set these in the scene so the
## CardManager knows what to spawn when an option is picked.
@export var option_a_data: Dictionary = {
	"type": "speed",
	"label": "Speed",
	"desc": "Fast but fragile",
	"speed": 90.0,
	"hp": 2,
	"attack_damage": 1,
	"attack_cooldown": 0.45,
	"color": Color(0.4, 0.7, 1.0, 1.0),
}
@export var option_b_data: Dictionary = {
	"type": "power",
	"label": "Power",
	"desc": "Slow but tanky",
	"speed": 45.0,
	"hp": 6,
	"attack_damage": 3,
	"attack_cooldown": 0.8,
	"color": Color(1.0, 0.4, 0.4, 1.0),
}

@onready var _option_a_button: Button = $OptionsContainer/OptionA
@onready var _option_b_button: Button = $OptionsContainer/OptionB
@onready var _option_a_label: Label = $OptionsContainer/OptionA/VBox/Label
@onready var _option_b_label: Label = $OptionsContainer/OptionB/VBox/Label
@onready var _option_a_desc: Label = $OptionsContainer/OptionA/VBox/Desc
@onready var _option_b_desc: Label = $OptionsContainer/OptionB/VBox/Desc
@onready var _option_a_swatch: ColorRect = $OptionsContainer/OptionA/Swatch
@onready var _option_b_swatch: ColorRect = $OptionsContainer/OptionB/Swatch
@onready var _card_title: Label = $CardTitle

# Slide/fade animation duration.
@export var dismiss_duration: float = 0.25

var _dismissed: bool = false

func _ready() -> void:
	if _option_a_button:
		_option_a_button.pressed.connect(_on_option_a_pressed)
	if _option_b_button:
		_option_b_button.pressed.connect(_on_option_b_pressed)

## Called by CardManager AFTER setting option_a_data / option_b_data.
## Populates labels, colors, and descriptions from the current export data.
func apply_option_data() -> void:
	if _option_a_label:
		_option_a_label.text = option_a_data.get("label", "Runner")
	if _option_b_label:
		_option_b_label.text = option_b_data.get("label", "Brute")
	if _option_a_swatch:
		_option_a_swatch.color = option_a_data.get("color", Color.WHITE)
	if _option_b_swatch:
		_option_b_swatch.color = option_b_data.get("color", Color.WHITE)
	if _option_a_desc:
		_option_a_desc.text = option_a_data.get("desc", "")
	if _option_b_desc:
		_option_b_desc.text = option_b_data.get("desc", "")

## Called by CardManager to set the card title text.
func set_card_title(title: String) -> void:
	if _card_title:
		_card_title.text = title

func _on_option_a_pressed() -> void:
	if _dismissed:
		return
	option_chosen.emit(option_a_data)
	_dismiss()

func _on_option_b_pressed() -> void:
	if _dismissed:
		return
	option_chosen.emit(option_b_data)
	_dismiss()

func _dismiss() -> void:
	_dismissed = true
	# Disable buttons so further taps do nothing while we animate out.
	if _option_a_button:
		_option_a_button.disabled = true
	if _option_b_button:
		_option_b_button.disabled = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, dismiss_duration)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), dismiss_duration)
	tween.tween_property(self, "position:y", position.y - 40.0, dismiss_duration)
	tween.finished.connect(queue_free)
