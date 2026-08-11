extends Control
class_name CardEditorLayout
## Configurable layout controller for the popup card panel.
## Attach to the CardEditor node in mobile_scene.tscn to expose
## popup position, size, and text scales as @export properties
## in the Inspector.
##
## Position & Size:
##   pos_x / pos_y — pixel offset from viewport top-left.
##   popup_width / popup_height — pixel dimensions of the popup panel.
##
## Text Scales:
##   title_scale — multiplier applied to entry title font size (default 1.0).
##   desc_scale  — multiplier applied to entry description font size (default 1.0).
##
## The PopupManager reads these values via _get_layout_rect() to
## position and size the active popup panel.

## Width of the popup panel in pixels.
@export var popup_width: float = 1080.0:
	set(v):
		popup_width = v
		_update_size_label()
		_update_layout()

## Height of the popup panel in pixels.
@export var popup_height: float = 780.0:
	set(v):
		popup_height = v
		_update_size_label()
		_update_layout()

## X pixel offset from viewport left edge.
@export var pos_x: float = 0.0:
	set(v):
		pos_x = v
		_update_pos_label()
		_update_layout()

## Y pixel offset from viewport top edge.
@export var pos_y: float = 640.0:
	set(v):
		pos_y = v
		_update_pos_label()
		_update_layout()

## Scale multiplier for entry title font size (1.0 = default).
@export_range(0.3, 3.0, 0.05) var title_scale: float = 1.0:
	set(v):
		title_scale = v
		_update_scale_label()

## Scale multiplier for entry description font size (1.0 = default).
@export_range(0.3, 3.0, 0.05) var desc_scale: float = 1.0:
	set(v):
		desc_scale = v
		_update_scale_label()

## Reference labels inside this node (set from _ready if they exist).
var _pos_label: Label
var _size_label: Label
var _scale_label: Label

func _ready() -> void:
	# Cache label children for fast updates.
	_pos_label = get_node_or_null("PositionLabel")
	_size_label = get_node_or_null("SizeLabel")
	_scale_label = get_node_or_null("ScaleLabel")
	_update_pos_label()
	_update_size_label()
	_update_scale_label()

func _update_pos_label() -> void:
	if _pos_label != null:
		_pos_label.text = "offset: %.0f, %.0f" % [pos_x, pos_y]

func _update_size_label() -> void:
	if _size_label != null:
		_size_label.text = "size: %.0f x %.0f" % [popup_width, popup_height]

func _update_scale_label() -> void:
	if _scale_label != null:
		_scale_label.text = "title: %.2f | desc: %.2f" % [title_scale, desc_scale]

func _update_layout() -> void:
	# Keep the node's size in sync with popup_width/popup_height.
	size = Vector2(popup_width, popup_height)

func _get_layout_rect() -> Rect2:
	return Rect2(pos_x, pos_y, popup_width, popup_height)

func _get_text_scales() -> Dictionary:
	return {"title_scale": title_scale, "desc_scale": desc_scale}
