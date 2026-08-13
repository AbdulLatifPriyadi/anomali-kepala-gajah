extends Control
class_name MapUI
## Visual map display with tappable nodes and road lines.
## Controls the MAP_PICK phase of the game.

signal node_selected(node_index: int)
signal map_regenerated()

const MapNode = preload("res://scripts/map_node.gd")
const RoadData = preload("res://scripts/road_data.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")

@export var node_button_scene: PackedScene

## The map generator instance.
var _generator: MapGenerator = null

## Currently generated nodes/roads.
var _nodes: Array[MapNode] = []
var _roads: Array[RoadData] = []

## Visual node buttons keyed by node index.
var _node_buttons: Dictionary = {}

## Weather manager reference.
var _weather: Node = null

## Whether Mist is active (hide future nodes).
var _mist_visible: bool = false

## Current node index.
var _current_idx: int = 0

## Weather indicator label.
var _weather_label: Label = null

func _ready() -> void:
	_generator = MapGenerator.new()
	_weather = get_node_or_null("/root/WeatherManager")
	if _weather:
		_weather.weather_started.connect(_on_weather_started)
		_weather.weather_ended.connect(_on_weather_ended)
		_weather.weather_updated.connect(_on_weather_updated)

## Generate and display the map.
func show_map() -> void:
	visible = true
	_generator.generate(_generator._rng.randi())
	_nodes = _generator.get_nodes()
	_roads = _generator.get_roads()
	_current_idx = 0
	_draw_map()

## Hide the map.
func hide_map() -> void:
	visible = false
	_clear_map()

func _clear_map() -> void:
	for child in get_children():
		if child is Control:
			child.queue_free()
	_node_buttons.clear()

func _draw_map() -> void:
	_clear_map()

	# Draw road lines first (underneath nodes).
	for road in _roads:
		_draw_road(road)

	# Create node buttons.
	for i in range(_nodes.size()):
		var n: MapNode = _nodes[i]
		_create_node_button(n, i)

	_update_weather_display()
	_apply_mist_visibility()

func _draw_road(road: RoadData) -> void:
	var from_node: MapNode = _nodes[road.from_node]
	var to_node: MapNode = _nodes[road.to_node]
	if from_node == null or to_node == null:
		return

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = RoadData.TYPE_TINTS.get(road.road_type, Color.WHITE)
	line.begin_cap_mode = 2  # LINE_CAP_ROUND
	line.end_cap_mode = 2    # LINE_CAP_ROUND
	line.antialiased = true
	line.add_point(from_node.position)
	line.add_point(to_node.position)
	add_child(line)
	line.z_index = -1

func _create_node_button(n: MapNode, idx: int) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 50)
	btn.text = MapNode.TYPE_LABELS.get(n.node_type, "?")
	btn.position = n.position - Vector2(40, 25)

	# Tint the button by node type.
	var tint: Color = Color.GRAY
	match n.node_type:
		0: tint = Color(0.3, 0.8, 0.3, 1.0)   # PRIZE
		1: tint = Color(0.4, 0.6, 0.8, 1.0)   # CHALLENGE
		2: tint = Color(0.8, 0.4, 0.3, 1.0)   # CHALLENGE_HARD
		3: tint = Color(0.7, 0.3, 0.7, 1.0)   # ELITE
		4: tint = Color(0.8, 0.1, 0.1, 1.0)   # BOSS
		5: tint = Color(0.3, 0.7, 0.5, 1.0)   # REST
		6: tint = Color(0.8, 0.6, 0.2, 1.0)   # SHOP
		7: tint = Color(0.5, 0.3, 0.7, 1.0)   # ADVENTURE
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	# Create a stylebox with the tint color.
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = tint
	style_normal.set_corner_radius_all(8)
	style_normal.set_border_width_all(2)
	style_normal.border_color = Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 1.0)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(tint.r * 1.2, tint.g * 1.2, tint.b * 1.2, 1.0)
	style_hover.set_corner_radius_all(8)
	style_hover.set_border_width_all(3)
	style_hover.border_color = Color.WHITE

	var style_disabled := StyleBoxFlat.new()
	style_disabled.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style_disabled.set_corner_radius_all(8)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("disabled", style_disabled)

	# Add a sub-label for the column number.
	var sub_label := Label.new()
	sub_label.text = "[%d]" % n.col
	sub_label.add_theme_font_size_override("font_size", 18)
	sub_label.add_theme_color_override("font_color", Color(tint.r * 0.8, tint.g * 0.8, tint.b * 0.8, 1.0))
	sub_label.position = Vector2(0, -16)
	btn.add_child(sub_label)

	# Boss node gets special treatment.
	if n.node_type == MapNode.Type.BOSS:
		var style_boss := StyleBoxFlat.new()
		style_boss.bg_color = Color(0.8, 0.1, 0.1, 1.0)
		style_boss.set_corner_radius_all(8)
		style_boss.set_border_width_all(3)
		style_boss.border_color = Color(1.0, 0.5, 0.0, 1.0)
		btn.add_theme_stylebox_override("normal", style_boss)

	btn.pressed.connect(_on_node_button_pressed.bind(idx))
	add_child(btn)
	_node_buttons[idx] = btn

	# Tooltip with description.
	btn.tooltip_text = "%s\n%s" % [n.label, n.description]

func _on_node_button_pressed(idx: int) -> void:
	if idx < 0 or idx >= _nodes.size():
		return
	var n: MapNode = _nodes[idx]
	if n.locked:
		return
	if idx != _current_idx:
		# Can only move to directly connected nodes.
		var road: RoadData = _generator.get_road(_current_idx, idx)
		if road == null:
			# Try reverse.
			road = _generator.get_road(idx, _current_idx)
		if road == null:
			return
	node_selected.emit(idx)

## Move the player to a node (called after node selection).
func move_to_node(idx: int) -> void:
	# Clear old current.
	for i in range(_nodes.size()):
		_nodes[i].is_current = false
		if _node_buttons.has(i):
			var btn: Button = _node_buttons[i]
			btn.disabled = true

	# Set new current.
	if idx < _nodes.size():
		_nodes[idx].is_current = true
		_nodes[idx].locked = false
		_nodes[idx].visited = true
		_nodes[idx].completed = true
	_current_idx = idx

	# Lock nodes before current column.
	_generator.lock_nodes_beyond(_nodes[idx].col)
	_current_idx = idx

	# Update button states.
	_update_button_states()
	_apply_mist_visibility()
	queue_redraw()

func _update_button_states() -> void:
	for i in range(_nodes.size()):
		if not _node_buttons.has(i):
			continue
		var btn: Button = _node_buttons[i]
		var n: MapNode = _nodes[i]
		btn.disabled = n.locked or n.is_current
		# Highlight current node.
		if n.is_current:
			btn.text = ">>>"
		else:
			btn.text = MapNode.TYPE_LABELS.get(n.node_type, "?")

func _apply_mist_visibility() -> void:
	_mist_visible = _weather and _weather.has_method("is_mist_active") and _weather.call("is_mist_active")
	for i in range(_nodes.size()):
		if not _node_buttons.has(i):
			continue
		var btn: Control = _node_buttons[i]
		var n: MapNode = _nodes[i]
		if _mist_visible and n.col > _current_idx:
			btn.modulate.a = 0.2
		else:
			btn.modulate.a = 1.0

func _update_weather_display() -> void:
	if _weather_label != null:
		_weather_label.queue_free()
		_weather_label = null
	if _weather == null:
		return
	var active: Array = []
	if _weather.has_method("get_active_event_types"):
		active = _weather.call("get_active_event_types")
	if active.is_empty():
		return
	_weather_label = Label.new()
	_weather_label.text = "Weather: " + ", ".join(active)
	_weather_label.add_theme_font_size_override("font_size", 20)
	_weather_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.9))
	_weather_label.position = Vector2(10, 10)
	add_child(_weather_label)

func _on_weather_started(event_type: String, nodes_remaining: int) -> void:
	_update_weather_display()
	if event_type == "EVENT":  # Earthquake
		_generator.regenerate_map()
		_nodes = _generator.get_nodes()
		_roads = _generator.get_roads()
		_draw_map()
		map_regenerated.emit()

func _on_weather_ended(event_type: String) -> void:
	_update_weather_display()
	_apply_mist_visibility()

func _on_weather_updated(active_events: Array) -> void:
	_update_weather_display()
	_apply_mist_visibility()
