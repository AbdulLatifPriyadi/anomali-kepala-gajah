extends Control
class_name PopupPanelView
## Generic popup panel used by all four popup types. Filled by
## popup_manager.setup(title, entries). When the player taps an entry,
## emits `picked(entry_data)` and the manager tears it down.

signal picked(data)

@onready var _title: Label = $Title
@onready var _entries_container: VBoxContainer = $EntriesContainer
@onready var _entry_button_scene: PackedScene = preload("res://scenes/popup_entry.tscn")

## Text scales propagated from CardEditorLayout / WaveOptionsDatabase.
## These multipliers are applied on top of each entry's own scale metadata.
var _title_scale_mult: float = 1.0
var _desc_scale_mult: float = 1.0

func _ready() -> void:
	if size == Vector2.ZERO:
		size = Vector2(720, 600)
	custom_minimum_size = size

## Configure the panel: title + entries. entries is an array of dicts
## with keys label/desc/tint/data and optionally swatch_texture/title_scale/desc_scale.
## layout_scales (optional dict with title_scale/desc_scale) comes from CardEditorLayout.
func setup(title: String, entries: Array, layout_scales: Dictionary = {}) -> void:
	_title.text = title
	_title_scale_mult = layout_scales.get("title_scale", 1.0)
	_desc_scale_mult = layout_scales.get("desc_scale", 1.0)

	# Apply panel title scale.
	var panel_base: int = 48
	if _title.has_theme_font_size_override("font_size"):
		# reset first
		_title.remove_theme_font_size_override("font_size")
	_title.add_theme_font_size_override("font_size", int(panel_base * _title_scale_mult))

	# Clear any existing entries.
	for child in _entries_container.get_children():
		child.queue_free()

	# Create one entry per dict.
	for e in entries:
		var entry: Control = _entry_button_scene.instantiate()
		_entries_container.add_child(entry)
		entry.set_meta("data", e.get("data"))
		entry.set_meta("label", e.get("label"))
		entry.set_meta("desc", e.get("desc"))
		entry.set_meta("tint", e.get("tint"))
		entry.set_meta("swatch_texture", e.get("swatch_texture"))
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
