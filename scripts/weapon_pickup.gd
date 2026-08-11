extends Node2D
class_name WeaponPickup
## A dropped weapon lying in the arena, waiting to be equipped.
##
## Two pickup paths:
##   1. Drag-to-equip (player): Player drags this node on top of a
##      BaseUnit; on release over a unit, equip() runs.
##   2. Enemy proximity pickup: When an enemy walks into the HitBox area,
##      if they're not confused/disabled, they auto-equip. Genius enemies
##      only equip &"advantage" weapons and avoid &"debuff" weapons.
##
## Origin tracking: `source` is one of:
##   "enemy_default" — came built-in on an enemy unit; does NOT drop on
##                    that enemy's death.
##   "player_drop"   — was dropped from a player unit's death/unequip;
##                    DOES drop again when the holding enemy dies.
##   ""              — shop/encounter origin; treats like player_drop
##                    (preserves "this weapon exists").

@export var weapon_data: Resource = null
var source: String = ""
var origin_instance_id: int = 0  # lineage tracking

## Genius AI protection window: the pickup won't auto-equip for the
## first 0.6s after spawn so the player has a brief window to grab
## their own drop before any enemy grabs it.
const GENIUS_GRACE_PERIOD: float = 0.6
var _time_alive: float = 0.0

## Launch state: when launched, the pickup flies away from the death
## position before settling. Duration in seconds.
var _launching: bool = false
var _launch_tween: Tween = null
## Target position after launch (400px away from killer).
var _launch_target: Vector2 = Vector2.ZERO

## Arena bounds for bounce (set externally if needed, else use world bounds).
var _arena_rect: Rect2 = Rect2()

@onready var _sprite: Sprite2D = $Sprite
@onready var _hit_box: Area2D = $HitBox
@onready var _label: Label = $Label

## Drag state.
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

signal picked_up(by_unit: BaseUnit)

func _ready() -> void:
	add_to_group(&"weapon_pickups")
	if _sprite and weapon_data != null:
		if weapon_data.sprite_path != "":
			_sprite.texture = load(weapon_data.sprite_path)
			# Apply per-weapon sprite scale (default 1.0).
			_sprite.scale = Vector2(weapon_data.sprite_scale, weapon_data.sprite_scale)
		else:
			_sprite.modulate = weapon_data.tint
	if _label and weapon_data != null:
		_label.text = weapon_data.display_name
		_label.modulate = Color(1, 1, 1, 0.7)

func _process(delta: float) -> void:
	_time_alive += delta

## Launch this pickup away from `launch_from` position, traveling
## `distance` pixels with an ease-out bounce after `delay` seconds.
func launch_away_from(launch_from: Vector2, distance: float = 400.0, delay: float = 0.0) -> void:
	var start_pos: Vector2 = global_position
	var dir: Vector2 = (start_pos - launch_from).normalized()
	if dir.length() < 0.1:
		dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	_launch_target = start_pos + dir * distance
	# Clamp within arena bounds if set.
	if _arena_rect.size.x > 0.0:
		var margin: float = 30.0
		_launch_target.x = clampf(_launch_target.x, _arena_rect.position.x + margin, _arena_rect.end.x - margin)
		_launch_target.y = clampf(_launch_target.y, _arena_rect.position.y + margin, _arena_rect.end.y - margin)

	_launching = true
	# Kill any existing tween.
	if _launch_tween and _launch_tween.is_valid():
		_launch_tween.kill()
	_launch_tween = create_tween()
	_launch_tween.set_parallel(true)
	# Start from current position, ease-out to target.
	_launch_tween.tween_property(self, "global_position", _launch_target, 0.5)\
		.set_delay(delay)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_launch_tween.finished.connect(_on_launch_done)

func setup(data: Resource, origin: String, instance_id: int) -> void:
	weapon_data = data
	source = origin
	origin_instance_id = instance_id
	# Apply visual updates immediately since _ready may have run already
	# (setup is called by WeaponManager right after instantiation).
	if _sprite:
		if data.sprite_path != "":
			_sprite.texture = load(data.sprite_path)
			_sprite.scale = Vector2(data.sprite_scale, data.sprite_scale)
		else:
			_sprite.modulate = data.tint
	if _label:
		_label.text = data.display_name

## Drag start (player pressed finger on this pickup).
func start_drag(global_drag_pos: Vector2) -> void:
	_is_dragging = true
	_drag_offset = global_position - global_drag_pos
	z_index = 100  # bring to front while dragging

## Drag update.
func update_drag(global_drag_pos: Vector2) -> void:
	if _is_dragging:
		global_position = global_drag_pos + _drag_offset

## Drag end. If the cursor is over a unit, equip; otherwise just stop.
func end_drag() -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	z_index = 0
	var hovered_unit: BaseUnit = _unit_under_drag()
	if hovered_unit != null:
		picked_up.emit(hovered_unit)
		hovered_unit.equip_weapon(weapon_data, source, origin_instance_id)
		queue_free()

## Returns the topmost player BaseUnit whose HitBox contains the drag point.
func _unit_under_drag() -> BaseUnit:
	# Walk in reverse z-order so the topmost unit wins.
	var drag_pos: Vector2 = global_position
	var units: Array = get_tree().get_nodes_in_group(&"player_units")
	var best: BaseUnit = null
	var best_dist: float = INF
	for u in units:
		var bu: BaseUnit = u
		if bu == null or bu.current_hp <= 0:
			continue
		var d: float = (bu.global_position - drag_pos).length()
		if d < best_dist and d <= bu.attack_range * 1.2:
			best_dist = d
			best = bu
	return best

func _on_launch_done() -> void:
	_launching = false
	global_position = _launch_target  # snap to exact target

## Called by the WeaponManager when an enemy walks into the HitBox.
## Returns true if this unit successfully picks it up.
func try_enemy_pickup(enemy: BaseUnit) -> bool:
	if enemy == null or enemy.current_hp <= 0:
		return false
	# Enemy drops (including drop_on_death with source="enemy_default") have no grace
	# period — genius units can grab them immediately.
	if _time_alive < GENIUS_GRACE_PERIOD and enemy.has_tag(&"genius") and (source == "player_drop" or source == ""):
		return false  # only protect player-origin drops
	# Confused enemies skip pickup (they can't target anything anyway).
	if enemy.equipped_weapon != null and enemy.equipped_weapon.flags.has(&"confusion"):
		return false
	# Stone Crown: ability-disabling weapon — only equip if wearer currently
	# has an ability. Enemies without abilities are skipped (no-op).
	if weapon_data != null and weapon_data.flags.has(&"ability_disabler"):
		if enemy.unit_data != null and enemy.unit_data.ability_id == 0:
			return false

	if enemy.has_tag(&"genius"):
		# Genius avoids debuff weapons, rushes advantages.
		if weapon_data != null and weapon_data.is_debuff():
			return false  # actively refuses
		# If advantage weapon, equip (overrides any existing weapon).
	enemy.equip_weapon(weapon_data, source, origin_instance_id)
	picked_up.emit(enemy)
	queue_free()
	return true
