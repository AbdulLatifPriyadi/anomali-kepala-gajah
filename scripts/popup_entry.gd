extends Button
## A single tappable card entry inside a popup_panel. Displays:
##   - Full card background (card.png)
##   - Unit swatch/image in top area
##   - HP icon + value overlaid at bottom of swatch
##   - ATK icon + value overlaid at bottom of swatch
##   - Title + Description text (below swatch)
## Tap -> emits `pressed` signal.
##
## Metadata expected by apply_meta():
##   label       — fallback title text (used if override_title not set)
##   override_title (opt) — card title (takes precedence over label)
##   desc        — fallback description text
##   override_desc (opt) — card description (takes precedence over desc)
##   swatch_texture    — unit image (CompressedTexture2D, optional)
##   hp_icon     — HP stat icon (CompressedTexture2D, optional)
##   hp_value    — HP number (int or String, optional)
##   atk_icon    — ATK stat icon (CompressedTexture2D, optional)
##   atk_value   — ATK number (int or String, optional)
##   title_scale (opt)  — multiplier for title font size
##   desc_scale  (opt)  — multiplier for desc font size

@onready var _card_bg: TextureRect = $CardBg
@onready var _swatch: TextureRect = $Swatch
@onready var _hp_icon: TextureRect = $HPContainer/HPFrame/HPIcon
@onready var _hp_value: Label = $HPContainer/HPFrame/HPValue
@onready var _atk_icon: TextureRect = $HPContainer/AtkFrame/AtkIcon
@onready var _atk_value: Label = $HPContainer/AtkFrame/AtkValue
@onready var _title_label: Label = $TitleLabel
@onready var _desc_label: Label = $DescLabel

## Base font sizes.
const BASE_TITLE_SIZE: int = 52
const BASE_DESC_SIZE: int = 36

func _ready() -> void:
	pass

## Helper: get a meta value, returning null if the key doesn't exist.
func _get_meta(key: String) -> Variant:
	if has_meta(key):
		return get_meta(key)
	return null

## Fill the entry from metadata set by popup_panel.setup().
func apply_meta() -> void:
	# --- Swatch ---
	var swatch_tex: CompressedTexture2D = _get_meta("swatch_texture")
	if _swatch != null:
		if swatch_tex != null:
			_swatch.texture = swatch_tex
			_swatch.modulate = Color.WHITE
		else:
			_swatch.texture = null
			_swatch.modulate = Color.WHITE

	# --- HP stat (overlaid on swatch) ---
	var hp_icon_tex: CompressedTexture2D = _get_meta("hp_icon")
	var hp_val: Variant = _get_meta("hp_value")
	if _hp_icon != null:
		if hp_icon_tex != null:
			_hp_icon.texture = hp_icon_tex
			_hp_icon.visible = true
		else:
			_hp_icon.visible = false
	if _hp_value != null:
		if hp_val != null:
			_hp_value.text = str(hp_val)
			_hp_value.visible = true
		else:
			_hp_value.visible = false

	# --- ATK stat (overlaid on swatch) ---
	var atk_icon_tex: CompressedTexture2D = _get_meta("atk_icon")
	var atk_val: Variant = _get_meta("atk_value")
	if _atk_icon != null:
		if atk_icon_tex != null:
			_atk_icon.texture = atk_icon_tex
			_atk_icon.visible = true
		else:
			_atk_icon.visible = false
	if _atk_value != null:
		if atk_val != null:
			_atk_value.text = str(atk_val)
			_atk_value.visible = true
		else:
			_atk_value.visible = false

	# --- Title: override_title takes precedence, then label, then "?" ---
	var title_text: String = str(_get_meta("override_title") if has_meta("override_title") else _get_meta("label") if has_meta("label") else "?")
	var t_scale: float = float(_get_meta("title_scale") if has_meta("title_scale") else 1.0)
	if _title_label != null:
		_title_label.text = title_text
		_title_label.add_theme_font_size_override("font_size", int(BASE_TITLE_SIZE * t_scale))

	# --- Description: override_desc takes precedence, then desc, then "" ---
	var desc_text: String = str(_get_meta("override_desc") if has_meta("override_desc") else _get_meta("desc") if has_meta("desc") else "")
	var d_scale: float = float(_get_meta("desc_scale") if has_meta("desc_scale") else 1.0)
	if _desc_label != null:
		_desc_label.text = desc_text
		_desc_label.add_theme_font_size_override("font_size", int(BASE_DESC_SIZE * d_scale))
