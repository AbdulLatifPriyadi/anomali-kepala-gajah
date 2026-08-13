extends Node
## Central game state singleton. Tracks the state machine phase, the
## current wave, the player's army roster, gold, and round/checkpoint
## counters. Every other system reads from / writes to this.
##
## This is registered as a project autoload (see project.godot).

signal phase_changed(new_phase: int, prev_phase: int)
signal unit_count_changed(player_count: int)
signal round_count_changed(rounds: int)
signal prize_pick_count_changed(picks: int)
signal checkpoint_triggered()
signal combat_started()
signal combat_ended()
signal map_node_traveled(node_index: int, road_type: int)
signal gold_changed(amount: int)
signal rerolls_changed(remaining: int)
signal rest_node_reached()

const RoadData = preload("res://scripts/road_data.gd")

enum Phase {
	EMPTY,         ## Idle — waiting for the next phase.
	PRIZE_PICK,    ## Prize popup is up. Player picks 1 of 2 army options.
	MAP_PICK,      ## Map is visible. Player selects the next node to travel to.
	COMBAT,        ## Combat is auto-running. No player input.
	ROUND_END,     ## Brief beat after combat: apply heals, create graves.
	GAME_OVER,     ## All units dead. Show game over.
	SHOP,          ## Shop is open. Player spends gold.
	AMBUSH,        ## Mid-road ambush combat triggered.
}

var phase: int = Phase.EMPTY

## Player's additive army roster. Stores UnitData refs in spawn order.
## The Arena holds the live BaseUnit nodes in parallel.
var army_data: Array[Resource] = []

## Round + prize-pick counters for checkpoint triggers.
var rounds_completed: int = 0
var prize_picks_total: int = 0

## Threshold for checkpoint trigger.
const CHECKPOINT_INTERVAL: int = 3

## Gold currency (placeholder for Shop).
var gold: int = 0

## Prize reroll counter — shared pool for the whole run.
var rerolls_remaining: int = 3

## Current selected enemy wave data (set when Challenge popup picks a wave).
var pending_wave: Array = []

## Map state: current node index on the roguelike map.
var map_node_index: int = 0

## Map seed for deterministic generation (shared so WeatherManager can regenerate).
var map_seed: int = 0

## Pending shop visit triggered by a MARKET road.
var pending_shop_after_combat: bool = false

## Current road type index for the active road.
var current_road_type: int = 0

## Ambush wave data (set when ambush triggers mid-road).
var ambush_wave: Array = []

## Storm damage multiplier from active weather.
var storm_damage_mult: float = 1.0

func _ready() -> void:
	# Start in EMPTY phase. The mobile scene drives the loop.
	phase = Phase.EMPTY

## Change phase and emit signal. Listeners can react to transitions.
func set_phase(new_phase: int) -> void:
	var prev: int = phase
	if new_phase == prev:
		return
	phase = new_phase
	phase_changed.emit(new_phase, prev)

## Called when the player picks a Prize card. Adds the unit to roster
## and increments the counter; triggers Checkpoint when threshold reached.
func on_prize_picked(unit_data: Resource) -> void:
	army_data.append(unit_data)
	prize_picks_total += 1
	prize_pick_count_changed.emit(prize_picks_total)
	unit_count_changed.emit(army_data.size())
	# After a prize pick, return to map to choose the next node.
	set_phase(Phase.MAP_PICK)

## Called when the player picks a Challenge card. Begins combat.
func on_challenge_picked(enemy_data: Array) -> void:
	pending_wave = enemy_data
	set_phase(Phase.COMBAT)
	combat_started.emit()

## Called when the player selects a node on the map and travels there.
## Handles road events (ambush, spike damage, guaranteed shop) and
## triggers the appropriate next phase.
func on_node_traveled(node_index: int, road_type: int) -> void:
	map_node_index = node_index
	current_road_type = road_type
	map_node_traveled.emit(node_index, road_type)
	# ROUND_END now represents the travel/road resolution phase.
	# Spike road: apply -2 HP to all units immediately.
	# MARKET road (type 6) guarantees a shop after.
	if road_type == 6:  # RoadData.RoadType.MARKET
		pending_shop_after_combat = true
	# Gold source: award some gold for completing a node.
	gold += 1
	gold_changed.emit(gold)

## Called after road resolution completes to trigger the node's effect.
func on_reached_node(node_type: int, node_index: int) -> void:
	match node_type:
		0:  # PRIZE
			set_phase(Phase.PRIZE_PICK)
		1:  # CHALLENGE
			# Build the wave and start combat.
			set_phase(Phase.COMBAT)
			combat_started.emit()
		2:  # CHALLENGE_HARD
			set_phase(Phase.COMBAT)
			combat_started.emit()
		3:  # ELITE
			set_phase(Phase.COMBAT)
			combat_started.emit()
		4:  # BOSS
			set_phase(Phase.COMBAT)
			combat_started.emit()
		5:  # REST
			rest_node_reached.emit()
			gold += 3
			gold_changed.emit(gold)
			set_phase(Phase.MAP_PICK)
		6:  # SHOP
			set_phase(Phase.SHOP)
		7:  # ADVENTURE
			# Adventure is resolved immediately — pick a random outcome.
			_resolve_adventure()
			set_phase(Phase.MAP_PICK)

## Resolve an Adventure event with a random outcome.
func _resolve_adventure() -> void:
	var outcomes: Array = [
		"gain_gold",
		"lose_gold",
		"gain_unit",
		"heal_all",
		"nothing",
	]
	var rng := RandomNumberGenerator.new()
	var pick: String = outcomes[rng.randi() % outcomes.size()]
	match pick:
		"gain_gold":
			gold += 5
			gold_changed.emit(gold)
		"lose_gold":
			gold = maxi(0, gold - 3)
			gold_changed.emit(gold)
		"heal_all":
			# Handled by mobile_scene calling round_end_heal on all units.
			pass
		"gain_unit":
			# Grant a free prize pick — handled by showing a prize popup.
			set_phase(Phase.PRIZE_PICK)
		# "nothing": no effect.

## Called by the combat system when all enemies in the wave are dead.
func on_combat_ended() -> void:
	rounds_completed += 1
	round_count_changed.emit(rounds_completed)
	combat_ended.emit()
	pending_wave.clear()
	ambush_wave.clear()
	# Check if a shop was queued by a MARKET road.
	if pending_shop_after_combat:
		pending_shop_after_combat = false
		set_phase(Phase.SHOP)
	else:
		set_phase(Phase.ROUND_END)

## Called after the round-end healing/grave pass completes.
func on_round_end_processed() -> void:
	set_phase(Phase.MAP_PICK)

## Use a reroll on the prize popup. Returns true if rerolls were available.
func use_reroll() -> bool:
	if rerolls_remaining <= 0:
		return false
	rerolls_remaining -= 1
	rerolls_changed.emit(rerolls_remaining)
	return true

## Add gold (e.g., from shop purchase or enemy drop).
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

## Spend gold (e.g., shop purchase). Returns true if successful.
func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

## Called when a player unit dies. Replaces it with a Grave and removes
## from the active roster. Triggers game over if army is empty.
func on_player_unit_died(unit_data: Resource) -> void:
	var idx: int = army_data.find(unit_data)
	if idx >= 0:
		army_data.remove_at(idx)
	unit_count_changed.emit(army_data.size())
	if army_data.is_empty():
		set_phase(Phase.GAME_OVER)

## Resets the run (for testing / new game button).
func reset_run() -> void:
	army_data.clear()
	rounds_completed = 0
	prize_picks_total = 0
	gold = 0
	rerolls_remaining = 3
	pending_wave.clear()
	ambush_wave.clear()
	pending_shop_after_combat = false
	map_node_index = 0
	map_seed = 0
	storm_damage_mult = 1.0
	set_phase(Phase.EMPTY)
	unit_count_changed.emit(0)
	round_count_changed.emit(0)
	prize_pick_count_changed.emit(0)
	gold_changed.emit(0)
	rerolls_changed.emit(rerolls_remaining)
