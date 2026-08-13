extends CanvasLayer
class_name PopupManager
## Owns the four popup types: Prize, Challenge, Checkpoint, Encounter.
## Slides each one up from the bottom of the screen, plays a single
## tween, and tears down on selection or dismiss.
##
## The MobileScene drives the popup lifecycle by calling:
##   show_prize(opts: Array, on_pick: Callable)
##   show_challenge(easy_wave: Array, hard_wave: Array, on_pick: Callable)
##   show_checkpoint(on_choice: Callable)
##   show_encounter(encounter_id: String, on_resolve: Callable)
##   show_wave_options(options: Array, on_pick: Callable)
##
## The CardEditor / CardEditorLayout node in the scene graph controls where
## the popup appears (position + size) and text scales.

const AbilityIds = preload("res://scripts/ability_ids.gd")
const WaveOptionData = preload("res://scripts/wave_option_data.gd")

## Preload stat icons so they can be passed to card entries.
const CARD_HEART_TEX: CompressedTexture2D = preload("res://assets/card_heart.png")
const CARD_ATTACK_TEX: CompressedTexture2D = preload("res://assets/card_attack.png")

@export var popup_panel_scene: PackedScene
## NodePath to the CardEditor Control node (child of PopupManager in the scene).
@export var card_editor_path: NodePath

const SLIDE_DURATION: float = 0.35

var _current_panel: Control = null
var _on_dismiss: Callable = Callable()
var _hiding: bool = false
var _card_editor: Control = null

func _ready() -> void:
	add_to_group(&"popup_manager")
	if popup_panel_scene == null:
		popup_panel_scene = preload("res://scenes/popup_panel.tscn")
	visible = false
	if card_editor_path.is_empty():
		_card_editor = get_node_or_null("CardEditor")
	else:
		_card_editor = get_node_or_null(card_editor_path)
	if _card_editor != null:
		_card_editor.visible = true

## Reads position/size from the CardEditor node.
## Falls back to CardEditorLayout if it has _get_layout_rect().
func _get_card_editor_rect() -> Rect2:
	if _card_editor != null and _card_editor.has_method("_get_layout_rect"):
		return _card_editor.call("_get_layout_rect")
	if _card_editor != null:
		var pos: Vector2 = _card_editor.global_position
		var sz: Vector2 = _card_editor.size
		if sz != Vector2.ZERO:
			return Rect2(pos, sz)
	# Fallback: bottom 60% of viewport.
	var vp: Rect2 = get_viewport().get_visible_rect()
	return Rect2(0, vp.size.y * 0.4, vp.size.x, vp.size.y * 0.6)

## Reads text scales from the CardEditor node.
func _get_card_editor_scales() -> Dictionary:
	if _card_editor != null and _card_editor.has_method("_get_text_scales"):
		return _card_editor.call("_get_text_scales")
	return {"title_scale": 1.0, "desc_scale": 1.0}

func _show_panel(title: String, entries: Array, on_pick: Callable) -> void:
	hide_panel()
	_hiding = false
	_current_panel = popup_panel_scene.instantiate()
	add_child(_current_panel)

	var layout_scales: Dictionary = _get_card_editor_scales()
	if _current_panel.has_method("setup"):
		_current_panel.call("setup", title, entries, layout_scales)
	if _current_panel.has_signal("picked"):
		_current_panel.connect("picked", _on_panel_picked)
	_on_dismiss = Callable()
	_pending_pick_callable = on_pick
	visible = true

	var target_rect: Rect2 = _get_card_editor_rect()
	_current_panel.size = target_rect.size

	_current_panel.modulate.a = 0.0
	_current_panel.position = Vector2(target_rect.position.x, get_viewport().get_visible_rect().size.y)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_current_panel, "modulate:a", 1.0, SLIDE_DURATION)
	tw.tween_property(_current_panel, "position:y", target_rect.position.y, SLIDE_DURATION)

var _pending_pick_callable: Callable = Callable()

func _on_panel_picked(data) -> void:
	var cb: Callable = _pending_pick_callable
	_hide_panel_animated()
	if cb.is_valid():
		cb.call(data)

func _hide_panel_animated() -> void:
	if _current_panel == null:
		return
	var panel: Control = _current_panel
	_current_panel = null
	_hiding = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 0.0, SLIDE_DURATION)
	tw.tween_property(panel, "position:y", get_viewport().get_visible_rect().size.y, SLIDE_DURATION)
	tw.finished.connect(_on_hide_tween_finished.bind(panel))

func _on_hide_tween_finished(panel: Control) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	_hiding = false
	if _current_panel == null:
		visible = false

func hide_panel() -> void:
	if _current_panel != null:
		_current_panel.queue_free()
		_current_panel = null
	visible = false

## ----- Public show_* API -----

func show_prize(opts: Array, on_pick: Callable) -> void:
	var entries: Array = []
	for d in opts:
		if d == null:
			continue
		var ud: UnitData = d as UnitData
		entries.append({
			"label": ud.display_name if ud else "?",
			"desc": ud.description if ud else "",
			"tint": ud.tint if ud else Color.WHITE,
			"swatch_texture": null,  # Use tint if no swatch
			"hp_icon": CARD_HEART_TEX,
			"hp_value": ud.max_hp if ud else 0,
			"atk_icon": CARD_ATTACK_TEX,
			"atk_value": ud.attack if ud else 0,
			"data": d,
		})
	_show_panel("Pick a unit to recruit", entries, on_pick)

func show_challenge(easy_wave: Array, hard_wave: Array, on_pick: Callable) -> void:
	var entries: Array = []
	# Summarize wave stats for display.
	var easy_hp: int = _sum_hp(easy_wave)
	var easy_atk: int = _sum_atk(easy_wave)
	var hard_hp: int = _sum_hp(hard_wave)
	var hard_atk: int = _sum_atk(hard_wave)
	entries.append({
		"label": "Easy Wave",
		"desc": "Civilians, no equipment.",
		"tint": Color(0.4, 0.8, 0.4, 1.0),
		"swatch_texture": null,
		"hp_icon": CARD_HEART_TEX,
		"hp_value": easy_hp,
		"atk_icon": CARD_ATTACK_TEX,
		"atk_value": easy_atk,
		"data": easy_wave,
	})
	entries.append({
		"label": "Hard Wave",
		"desc": "Knife-equipped civilians.",
		"tint": Color(0.8, 0.4, 0.4, 1.0),
		"swatch_texture": null,
		"hp_icon": CARD_HEART_TEX,
		"hp_value": hard_hp,
		"atk_icon": CARD_ATTACK_TEX,
		"atk_value": hard_atk,
		"data": hard_wave,
	})
	_show_panel("Choose a challenge", entries, on_pick)

func show_checkpoint(on_choice: Callable) -> void:
	var entries: Array = []
	entries.append({
		"label": "Shop",
		"desc": "(Coming soon)",
		"tint": Color(0.7, 0.5, 0.2, 1.0),
		"swatch_texture": null,
		"hp_icon": null,
		"hp_value": null,
		"atk_icon": null,
		"atk_value": null,
		"data": "shop",
	})
	entries.append({
		"label": "Explore",
		"desc": "Roll a random encounter.",
		"tint": Color(0.3, 0.5, 0.8, 1.0),
		"swatch_texture": null,
		"hp_icon": null,
		"hp_value": null,
		"atk_icon": null,
		"atk_value": null,
		"data": "explore",
	})
	entries.append({
		"label": "Rest",
		"desc": "Heal all units 20% max HP.",
		"tint": Color(0.4, 0.7, 0.5, 1.0),
		"swatch_texture": null,
		"hp_icon": null,
		"hp_value": null,
		"atk_icon": null,
		"atk_value": null,
		"data": "rest",
	})
	_show_panel("Checkpoint", entries, on_choice)

func show_encounter(encounter_id: String, on_resolve: Callable) -> void:
	var entries: Array = []
	var entry_label: String = ""
	var entry_desc: String = ""
	match encounter_id:
		"dark_forest":
			entry_label = "Dark Forest"
			entry_desc = "Fight 2 Wolves. Victory -> Sword."
		"statue":
			entry_label = "Statue of Anomali"
			entry_desc = "All units sacrifice 20% HP. One random gains Dracula."
		"mancing":
			entry_label = "Mancing (Fishing)"
			entry_desc = "Sacrifice 1 random unit. Gain 1 random unit."
		_:
			entry_label = "Unknown"
			entry_desc = ""
	entries.append({
		"label": entry_label,
		"desc": entry_desc,
		"tint": Color(0.5, 0.3, 0.7, 1.0),
		"swatch_texture": null,
		"hp_icon": null,
		"hp_value": null,
		"atk_icon": null,
		"atk_value": null,
		"data": encounter_id,
	})
	_show_panel("Encounter: " + entry_label, entries, on_resolve)

func show_wave_options(options: Array, on_pick: Callable) -> void:
	var entries: Array = []
	for opt in options:
		if opt is WaveOptionData:
			var wave_units: Array = []
			# Load UnitData from enemy_paths strings.
			for path in opt.enemy_paths:
				if path is String and not path.is_empty():
					var ud: UnitData = load(path) as UnitData
					if ud != null:
						wave_units.append(ud)
			entries.append({
				"label": opt.label,
				"desc": opt.description,
				"tint": opt.tint_color,
				"swatch_texture": opt.swatch_texture,
				"hp_icon": CARD_HEART_TEX,
				"hp_value": _sum_hp(wave_units),
				"atk_icon": CARD_ATTACK_TEX,
				"atk_value": _sum_atk(wave_units),
				"title_scale": opt.title_scale,
				"desc_scale": opt.desc_scale,
				"data": opt,
			})
	if entries.is_empty():
		return
	_show_panel("Choose a challenge", entries, on_pick)

## Helper: sum max_hp from a list of UnitData.
func _sum_hp(unit_list: Array) -> int:
	var total: int = 0
	for u in unit_list:
		if u is UnitData:
			total += u.max_hp
	return total

## Helper: sum attack from a list of UnitData.
func _sum_atk(unit_list: Array) -> int:
	var total: int = 0
	for u in unit_list:
		if u is UnitData:
			total += u.attack
	return total
