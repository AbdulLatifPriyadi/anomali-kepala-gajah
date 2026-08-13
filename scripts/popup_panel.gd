extends Control
class_name PopupPanelView
## Generic popup panel used by all four popup types. Filled by
## popup_manager.setup(title, entries). When the player taps an entry,
## emits `picked(entry_data)` and the manager tears it down.

signal picked(data)

@onready var _title: Label = $Title
@onready var _entries_container: GridContainer = $EntriesContainer
@onready var _entry_button_scene: PackedScene = preload("res://scenes/popup_entry.tscn")

## Text scales propagated from CardEditorLayout.
var _title_scale_mult: float = 1.0
var _desc_scale_mult: float = 1.0

func _ready() -> void:
	if size == Vector2.ZERO:
		size = Vector2(1080, 780)
	custom_minimum_size = size

## Configure the panel: title + entries. entries is an array of dicts
## with keys:
##   label, desc, swatch_texture, hp_icon, hp_value, atk_icon, atk_value, data
##   and optionally title_scale, desc_scale.
## layout_scales (optional dict with title_scale/desc_scale) comes from CardEditorLayout.
func setup(title: String, entries: Array, layout_scales: Dictionary = {}) -> void:
	_title.text = title
	_title_scale_mult = layout_scales.get("title_scale", 1.0)
	_desc_scale_mult = layout_scales.get("desc_scale", 1.0)

	# Apply panel title scale.
	var panel_base: int = 48
	if _title.has_theme_font_size_override("font_size"):
		_title.remove_theme_font_size_override("font_size")
	_title.add_theme_font_size_override("font_size", int(panel_base * _title_scale_mult))

	# Determine columns: 2 for prize/challenge (cards side by side).
	_entries_container.columns = 2

	# Clear any existing entries.
	for child in _entries_container.get_children():
		child.queue_free()

	# Create one entry per dict.
	for e in entries:
		var entry: Control = _entry_button_scene.instantiate()
		_entries_container.add_child(entry)
		entry.set_meta("data", e.get("data"))
		if e.has("label"):
			entry.set_meta("label", e.get("label"))
		if e.has("desc"):
			entry.set_meta("desc", e.get("desc"))
		var swatch_t: Variant = e.get("swatch_texture")
		if swatch_t != null:
			entry.set_meta("swatch_texture", swatch_t)
		var hp_icon_t: Variant = e.get("hp_icon")
		if hp_icon_t != null:
			entry.set_meta("hp_icon", hp_icon_t)
		var hp_val: Variant = e.get("hp_value")
		if hp_val != null:
			entry.set_meta("hp_value", hp_val)
		var atk_icon_t: Variant = e.get("atk_icon")
		if atk_icon_t != null:
			entry.set_meta("atk_icon", atk_icon_t)
		var atk_val: Variant = e.get("atk_value")
		if atk_val != null:
			entry.set_meta("atk_value", atk_val)
		# Optional title/desc overrides.
		var override_title: Variant = e.get("override_title")
		if override_title != null:
			entry.set_meta("override_title", override_title)
		var override_desc: Variant = e.get("override_desc")
		if override_desc != null:
			entry.set_meta("override_desc", override_desc)
		# Per-entry scale multiplied by layout scale.
		var entry_t_scale: float = float(e.get("title_scale", 1.0)) * _title_scale_mult
		var entry_d_scale: float = float(e.get("desc_scale", 1.0)) * _desc_scale_mult
		entry.set_meta("title_scale", entry_t_scale)
		entry.set_meta("desc_scale", entry_d_scale)
		if entry.has_method("apply_meta"):
			entry.call("apply_meta")
		entry.pressed.connect(_on_entry_pressed.bind(e.get("data")))

func _on_entry_pressed(data) -> void:
	picked.emit(data)
