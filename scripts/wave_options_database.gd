extends Resource
class_name WaveOptionsDatabase
## Central database for all wave option display metadata.
## Use the Inspector to edit title, description, tint, swatch image,
## and text scale for each wave number and difficulty tier.
##
## Enemy composition is defined in mobile_scene.gd:_build_wave_options_for().
## This database only controls the popup card appearance.

## Scale applied to the popup panel's overall size relative to the CardEditor rect.
## 1.0 = full size of CardEditor, 0.5 = half, 2.0 = double.
@export var popup_scale: float = 1.0
## Scale multiplier for the popup panel title (the "Choose a challenge" header).
@export var panel_title_scale: float = 1.0

## Per-wave entries keyed by wave_number. Each entry is a Dictionary with
## "easy" and "hard" sub-dictionaries of WaveOptionDisplay.
## Access pattern: entries[1]["easy"].title
@export var entries: Dictionary = {}

func _get_or_create_wave(wave_num: int) -> Dictionary:
	if not entries.has(wave_num):
		entries[wave_num] = {"easy": _make_entry(), "hard": _make_entry()}
	return entries[wave_num]

func get_entry(wave_num: int, difficulty: String) -> Dictionary:
	# difficulty: "easy" or "hard"
	var wave: Dictionary = _get_or_create_wave(wave_num)
	if difficulty == "hard":
		return wave.get("hard", _make_entry())
	return wave.get("easy", _make_entry())

func _make_entry() -> Dictionary:
	return {
		"title": "",
		"description": "",
		"tint_color": Color(0.5, 0.5, 0.5, 1.0),
		"swatch_texture": null,
		"title_scale": 1.0,
		"desc_scale": 1.0,
	}
