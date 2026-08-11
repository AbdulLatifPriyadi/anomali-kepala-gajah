extends Button
## A single tappable card entry inside a popup_panel. Displays the card
## background image (CardBg), a colored swatch (or image), a title, and a
## description. Tap → emits `pressed` signal.
##
## All visible elements are direct children of this Button so the user
## can select and drag any of them in the Godot editor.
##
## Metadata expected by apply_meta():
##   label, desc, tint, swatch_texture (optional Texture2D),
##   title_scale (optional float), desc_scale (optional float)

@onready var _card_bg: TextureRect = $CardBg
@onready var _swatch: TextureRect = $Swatch
@onready var _label: Label = $Title
@onready var _desc: Label = $Desc

## Base font sizes — used as multipliers for the scale overrides.
## These match the scene's theme_override_font_sizes values.
const BASE_TITLE_SIZE: int = 36
const BASE_DESC_SIZE: int = 21

func _ready() -> void:
	pass

## Fill the entry from metadata set by popup_panel.setup().
## Expected keys: label, desc, tint, swatch_texture (opt), title_scale (opt), desc_scale (opt).
func apply_meta() -> void:
	var label_text: String = get_meta("label", "?")
	var desc_text: String = get_meta("desc", "")
	var tint: Color = get_meta("tint", Color.WHITE)
	var swatch_tex: Texture2D = get_meta("swatch_texture", null)
	var t_scale: float = float(get_meta("title_scale", 1.0))
	var d_scale: float = float(get_meta("desc_scale", 1.0))

	if _swatch != null:
		if swatch_tex != null:
			_swatch.texture = swatch_tex
			_swatch.modulate = Color.WHITE
		else:
			_swatch.texture = null
			_swatch.modulate = tint

	if _label != null:
		_label.text = label_text
		var base_size: int = BASE_TITLE_SIZE
		_label.add_theme_font_size_override("font_size", int(base_size * t_scale))

	if _desc != null:
		_desc.text = desc_text
		var base_size: int = BASE_DESC_SIZE
		_desc.add_theme_font_size_override("font_size", int(base_size * d_scale))
