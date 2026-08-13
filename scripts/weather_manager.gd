extends Node
## Central weather event manager. Manages active weather effects that
## modify road ambushes, combat encounters, and map visibility.
##
## Weather events last for 3 node transitions and can stack.
## Each event type has a distinct effect on travel or combat.

signal weather_started(event_type: String, nodes_remaining: int)
signal weather_ended(event_type: String, nodes_remaining: int)
signal weather_updated(active_events: Array)
## Emitted when a combat encounter spawns during active weather,
## so arena/combat system can react to spawn modifiers.
signal weather_combat_modifier(combo_type: String, extra_enemies: Array)

## Weather event types.
enum WeatherType {
	MIST,       ## Travel: only next node is visible
	RAIN,       ## Travel: doubles ambush chance on roads
	FLOOD,      ## Combat: spawns 1 additional Fish enemy
	STORM,      ## Combat: combat becomes harder (not yet spec'd — +20% enemy stats)
	METEOR,      ## Combat: Meteor strike in fight, -5 damage to unit in impact zone
	EVENT,       ## Event: Earthquake — regenerates map routes, one-time per run
	HURRICANE,   ## Event: repositions player, one-time per run
}

const TYPE_LABELS := {
	WeatherType.MIST:      "Mist",
	WeatherType.RAIN:      "Rain",
	WeatherType.FLOOD:     "Flood",
	WeatherType.STORM:     "Storm",
	WeatherType.METEOR:    "Meteor",
	WeatherType.EVENT:     "Earthquake",
	WeatherType.HURRICANE: "Hurricane",
}

const TYPE_TINTS := {
	WeatherType.MIST:      Color(0.7, 0.7, 0.8, 0.8),
	WeatherType.RAIN:      Color(0.3, 0.4, 0.7, 0.8),
	WeatherType.FLOOD:     Color(0.2, 0.5, 0.8, 0.8),
	WeatherType.STORM:      Color(0.5, 0.3, 0.7, 0.8),
	WeatherType.METEOR:    Color(0.9, 0.4, 0.2, 0.8),
	WeatherType.EVENT:      Color(0.7, 0.5, 0.3, 0.8),
	WeatherType.HURRICANE:  Color(0.3, 0.7, 0.9, 0.8),
}

## Trigger chance per node transition (per weather type).
const TRIGGER_CHANCE := {
	WeatherType.MIST:      0.035,
	WeatherType.RAIN:      0.022,
	WeatherType.FLOOD:     0.020,
	WeatherType.STORM:      0.015,
	WeatherType.METEOR:    0.010,
	WeatherType.EVENT:     0.003,
	WeatherType.HURRICANE: 0.003,
}

## How many node transitions this weather lasts.
const DURATION_NODES: int = 3

## Active weather entries. Each entry: {type: WeatherType, remaining: int}.
var _active_events: Array[Dictionary] = []

## One-time flags (not reset until run reset).
var _earthquake_used: bool = false
var _hurricane_used: bool = false

## Mutual exclusion: Rain and Storm cannot both be active.
func _can_trigger(type: WeatherType) -> bool:
	if type == WeatherType.RAIN:
		return not _has_type(WeatherType.STORM)
	if type == WeatherType.STORM:
		return not _has_type(WeatherType.RAIN)
	return true

func _has_type(type: WeatherType) -> bool:
	for ev in _active_events:
		if ev.get("type") == type:
			return true
	return false

func _get_by_type(type: WeatherType) -> Dictionary:
	for ev in _active_events:
		if ev.get("type") == type:
			return ev
	return {}

## Called when the player moves to the next node (decrements all counters).
func on_node_traversed() -> void:
	var expired: Array = []
	for ev in _active_events:
		ev["remaining"] -= 1
		if ev["remaining"] <= 0:
			expired.append(ev)
	for ev in expired:
		_active_events.erase(ev)
		weather_ended.emit(TYPE_LABELS.get(ev.get("type", 0), "?"), int(ev.get("remaining", 0)))
	weather_updated.emit(get_active_event_types())

## Roll for a new weather event. Call this at the start of each node transition.
## If one triggers, it replaces the "new" event in _active_events and starts its 3-node duration.
func roll_new_weather() -> void:
	var rng := RandomNumberGenerator.new()
	for type_val in WeatherType.keys():
		var type: WeatherType = WeatherType.get(type_val)
		# Skip already-active events.
		if _has_type(type):
			continue
		# Skip one-time events that have been used.
		if type == WeatherType.EVENT and _earthquake_used:
			continue
		if type == WeatherType.HURRICANE and _hurricane_used:
			continue
		# Check trigger chance.
		var chance: float = TRIGGER_CHANCE.get(type, 0.0)
		if rng.randf() < chance:
			if not _can_trigger(type):
				continue
			# Activate this weather.
			_active_events.append({
				"type": type,
				"remaining": DURATION_NODES,
			})
			if type == WeatherType.EVENT:
				_earthquake_used = true
			if type == WeatherType.HURRICANE:
				_hurricane_used = true
			weather_started.emit(type_val, DURATION_NODES)
			weather_updated.emit(get_active_event_types())
			break  # Only one new event per transition.

## Returns true if Rain is currently active.
func is_rain_active() -> bool:
	return _has_type(WeatherType.RAIN)

## Returns true if Mist is currently active.
func is_mist_active() -> bool:
	return _has_type(WeatherType.MIST)

## Returns the number of nodes remaining for active weather (0 if not active).
func get_weather_remaining(type: WeatherType) -> int:
	var ev := _get_by_type(type)
	return ev.get("remaining", 0)

## Returns a list of active event type names (strings).
func get_active_event_types() -> Array:
	var result: Array = []
	for ev in _active_events:
		var type_val = ev.get("type", 0)
		var label = TYPE_LABELS.get(type_val, "?")
		result.append(label)
	return result

## Returns true if any combat-relevant weather is active.
func has_combat_weather() -> bool:
	return _has_type(WeatherType.STORM) or _has_type(WeatherType.FLOOD) or _has_type(WeatherType.METEOR)

## Called by the combat system to get weather spawn modifiers.
## Returns extra enemy UnitData to add to the encounter.
func get_combat_extra_enemies() -> Array:
	var extra: Array = []
	var flood_active: bool = _has_type(WeatherType.FLOOD)
	var mist_active: bool  = _has_type(WeatherType.MIST)
	var storm_active: bool = _has_type(WeatherType.STORM)
	var rain_active: bool  = _has_type(WeatherType.RAIN)

	if not flood_active:
		return extra

	# Combo resolution: determine the Fish type from stacking events.
	var combo: String = ""
	if rain_active and flood_active:
		combo = "fish"
	elif storm_active and flood_active:
		combo = "big_fish"
	elif mist_active and flood_active:
		combo = "projectile_fish"
	elif mist_active and storm_active:
		combo = "swarm_fish"
	elif flood_active:
		combo = "fish"

	# Emit modifier signal so arena can react.
	weather_combat_modifier.emit(combo, extra)
	return extra

## Returns the Storm damage multiplier for combat.
func get_storm_multiplier() -> float:
	if _has_type(WeatherType.STORM):
		return 1.2  # +20% enemy damage
	return 1.0

## Resets all weather state for a new run.
func reset_run() -> void:
	_active_events.clear()
	_earthquake_used = false
	_hurricane_used = false
	weather_updated.emit([])
