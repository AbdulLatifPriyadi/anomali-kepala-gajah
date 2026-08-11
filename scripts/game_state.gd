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

enum Phase {
	EMPTY,         ## Idle, arena visible, no combat, waiting for Prize popup.
	PRIZE_PICK,    ## Prize popup is up. Player picks 1 of 2 army options.
	CHALLENGE_PICK,## Challenge popup is up. Player picks Easy/Hard wave.
	CHECKPOINT,    ## Checkpoint popup (Shop/Explore/Rest). Triggers every 3 picks.
	COMBAT,        ## Combat is auto-running. No player input.
	ROUND_END,     ## Brief beat after combat: apply heals, create graves.
	GAME_OVER,     ## All units dead. Show game over.
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

## Current selected enemy wave data (set when Challenge popup picks a wave).
var pending_wave: Array = []

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
	if should_trigger_checkpoint():
		set_phase(Phase.CHECKPOINT)
	else:
		set_phase(Phase.CHALLENGE_PICK)

## Called when the player picks a Challenge card. Begins combat.
func on_challenge_picked(enemy_data: Array) -> void:
	pending_wave = enemy_data
	set_phase(Phase.COMBAT)
	combat_started.emit()

## Called by the combat system when all enemies in the wave are dead.
## Note: per spec, a round ends when all enemies are DEAD — surviving
## fleeing enemies that the player can't catch will block the round
## indefinitely. This is intentional for Wave 1.
## Phase transition to ROUND_END is deferred to mobile_scene so it can
## wait for the 2-second heal delay first.
func on_combat_ended() -> void:
	rounds_completed += 1
	round_count_changed.emit(rounds_completed)
	combat_ended.emit()

## Called after the round-end healing/grave pass completes.
func on_round_end_processed() -> void:
	if should_trigger_checkpoint():
		set_phase(Phase.CHECKPOINT)
	else:
		set_phase(Phase.EMPTY)

## Checkpoint fires when BOTH counters are at multiples of CHECKPOINT_INTERVAL.
func should_trigger_checkpoint() -> bool:
	return (
		prize_picks_total > 0
		and prize_picks_total % CHECKPOINT_INTERVAL == 0
		and rounds_completed > 0
		and rounds_completed % CHECKPOINT_INTERVAL == 0
	)

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
	pending_wave.clear()
	set_phase(Phase.EMPTY)
	unit_count_changed.emit(0)
	round_count_changed.emit(0)
	prize_pick_count_changed.emit(0)
