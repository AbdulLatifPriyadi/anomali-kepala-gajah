extends CanvasLayer
## Manages spawning recruit cards and spawning Army units when options are chosen.
##
## Cards appear one at a time. Each card has two options. When the player
## taps an option, the card dismisses and the corresponding Army unit spawns
## at a fixed position near the bottom of the arena.
##
## Card definitions are stored in `_card_library`. Add new entries to extend
## the variety of recruits.

## Signal emitted when an army unit is spawned. Passes the option Dictionary
## so callers can react (e.g. sound effects, score).
signal army_spawned(option: Dictionary)

## PackedScene for the card UI. Must have a `Control` root with the
## `option_chosen` signal wired internally by card.gd.
@export var card_scene: PackedScene

## PackedScene for the Army character. Must be a CharacterBody2D with
## the `enemy_path` export and `take_damage` method.
@export var army_scene: PackedScene

## Path to the Enemy node (used to pass to spawned armies).
@export var enemy_path: NodePath

## Where to spawn each new army unit (world position inside the arena).
@export var spawn_anchor: Vector2 = Vector2(200, 300)

## Horizontal offset per spawn so multiple armies spread out.
@export var spawn_stride: float = 80.0

## How many armies have been spawned this session (used for spread offset).
var _spawn_count: int = 0

## Currently active card instance. Prevents stacking multiple cards.
var _active_card: Control = null

## Card library: each entry describes one card type with two recruit options.
## Options should include at minimum: `type`, `label`, `speed`, `hp`,
## `attack_damage`, `attack_cooldown`, and `color`.
var _card_library: Array[Dictionary] = [
	{
		"id": "soldier",
		"title": "Soldier",
		"option_a": {
			"type": "soldier_speed",
			"label": "Runner",
			"desc": "Fast but fragile",
			"speed": 90.0,
			"hp": 2,
			"attack_damage": 1,
			"attack_cooldown": 0.45,
			"color": Color(0.4, 0.7, 1.0, 1.0),  # light blue
		},
		"option_b": {
			"type": "soldier_power",
			"label": "Brute",
			"desc": "Slow but tanky",
			"speed": 40.0,
			"hp": 7,
			"attack_damage": 3,
			"attack_cooldown": 0.8,
			"color": Color(1.0, 0.35, 0.35, 1.0),  # red
		},
	},
	{
		"id": "archer",
		"title": "Archer",
		"option_a": {
			"type": "archer_rapid",
			"label": "Ranger",
			"desc": "Quick shots",
			"speed": 70.0,
			"hp": 3,
			"attack_damage": 1,
			"attack_cooldown": 0.25,
			"color": Color(0.4, 1.0, 0.55, 1.0),  # green
		},
		"option_b": {
			"type": "archer_heavy",
			"label": "Crossbow",
			"desc": "Heavy hits",
			"speed": 35.0,
			"hp": 5,
			"attack_damage": 4,
			"attack_cooldown": 1.1,
			"color": Color(1.0, 0.85, 0.3, 1.0),  # gold
		},
	},
	{
		"id": "tank",
		"title": "Tank",
		"option_a": {
			"type": "tank_shield",
			"label": "Guardian",
			"desc": "High HP",
			"speed": 30.0,
			"hp": 12,
			"attack_damage": 2,
			"attack_cooldown": 0.9,
			"color": Color(0.55, 0.55, 0.9, 1.0),  # periwinkle
		},
		"option_b": {
			"type": "tank_bruiser",
			"label": "Crusher",
			"desc": "Balanced",
			"speed": 55.0,
			"hp": 8,
			"attack_damage": 3,
			"attack_cooldown": 0.6,
			"color": Color(0.9, 0.55, 1.0, 1.0),  # lavender
		},
	},
]

## Index into _card_library. Cycles through all card types then repeats.
var _card_index: int = 0

func _ready() -> void:
	# Show the first card after a short delay.
	await get_tree().create_timer(1.0).timeout
	_show_next_card()

## Returns the next card definition from the library, cycling back to the
## start when the end is reached.
func _next_card_data() -> Dictionary:
	var data: Dictionary = _card_library[_card_index % _card_library.size()]
	_card_index += 1
	return data

## Spawns a card UI and waits for the player to pick an option.
func _show_next_card() -> void:
	if _active_card != null:
		return  # Already showing a card.
	if card_scene == null:
		push_warning("CardManager: card_scene is null")
		return

	var card: Control = card_scene.instantiate()
	add_child(card)

	# Center the card on screen.
	var vp: Viewport = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size
	card.position = (vp_size - card.size) * 0.5

	var data: Dictionary = _next_card_data()
	card.option_a_data = data.get("option_a", {})
	card.option_b_data = data.get("option_b", {})
	if card.has_method("set_card_title"):
		card.call("set_card_title", data.get("title", ""))
	if card.has_method("apply_option_data"):
		card.call("apply_option_data")

	card.option_chosen.connect(_on_card_option_chosen)
	_active_card = card

## Called when the player taps an option button on the card.
func _on_card_option_chosen(option: Dictionary) -> void:
	_active_card = null
	_spawn_army(option)
	army_spawned.emit(option)

	# Show the next card after a short cooldown.
	await get_tree().create_timer(1.2).timeout
	_show_next_card()

## Spawns an Army unit configured from the chosen option.
func _spawn_army(option: Dictionary) -> void:
	if army_scene == null:
		push_warning("CardManager: army_scene is null")
		return

	var army: CharacterBody2D = army_scene.instantiate()

	# Place the army near the bottom of the arena, spread horizontally.
	var spawn_pos := spawn_anchor + Vector2(_spawn_count * spawn_stride, 0.0)
	army.global_position = spawn_pos
	_spawn_count += 1

	# Apply option stats to the army using set() for export properties.
	army.set("army_type", option.get("type", "unknown"))
	army.set("max_hp", option.get("hp", 2))
	army.set("walk_speed", option.get("speed", 60.0))
	army.set("attack_damage", option.get("attack_damage", 1))
	army.set("attack_cooldown", option.get("attack_cooldown", 0.55))
	army.set("tint", option.get("color", Color.WHITE))
	army.set("enemy_path", enemy_path)

	get_tree().root.add_child(army)

## Public method to force a card to appear immediately.
func summon_card() -> void:
	if _active_card != null:
		return
	_show_next_card()
