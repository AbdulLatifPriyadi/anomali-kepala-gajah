extends Resource
class_name MapNode
## Represents a single node on the roguelike map.

## Node types matching §2 of the map spec.
enum Type {
	PRIZE,        ## Grants a prize pick. No bundled combat.
	CHALLENGE,    ## Standard difficulty combat wave.
	CHALLENGE_HARD, ## Harder combat wave — distinct visible node type.
	ELITE,        ## Meaningfully harder, unique enemy abilities.
	BOSS,         ## Mandatory end-of-act gate.
	REST,         ## Heal army / upgrade.
	SHOP,         ## Spend gold.
	ADVENTURE,    ## Event/lore node.
}

## Visual icons for each node type (text label fallback).
## In a full implementation these would be textures; using string IDs for now.
const TYPE_LABELS := {
	Type.PRIZE:        "PRIZE",
	Type.CHALLENGE:    "COMBAT",
	Type.CHALLENGE_HARD: "COMBAT+",
	Type.ELITE:        "ELITE",
	Type.BOSS:         "BOSS",
	Type.REST:         "REST",
	Type.SHOP:         "SHOP",
	Type.ADVENTURE:    "EVENT",
}

## Tint colors per node type for UI display.
const TYPE_TINTS := {
	Type.PRIZE:        Color(0.3, 0.8, 0.3, 1.0),
	Type.CHALLENGE:     Color(0.4, 0.6, 0.8, 1.0),
	Type.CHALLENGE_HARD: Color(0.8, 0.4, 0.3, 1.0),
	Type.ELITE:         Color(0.7, 0.3, 0.7, 1.0),
	Type.BOSS:          Color(0.8, 0.1, 0.1, 1.0),
	Type.REST:          Color(0.3, 0.7, 0.5, 1.0),
	Type.SHOP:          Color(0.8, 0.6, 0.2, 1.0),
	Type.ADVENTURE:     Color(0.5, 0.3, 0.7, 1.0),
}

## Screen position for UI rendering.
var position: Vector2 = Vector2.ZERO

## Logical column/row index in the map grid.
var col: int = 0
var row: int = 0

## Whether this node has been visited.
var visited: bool = false

## Whether this node is the current player position.
var is_current: bool = false

## Whether all paths to this node have been explored.
var locked: bool = true

## Node type enum value.
var node_type: Type = Type.CHALLENGE

## Human-readable label for this node.
var label: String = ""

## Longer description shown when the node is highlighted.
var description: String = ""

## The wave difficulty for combat nodes.
## "easy", "hard", "elite", or "" for non-combat.
var wave_difficulty: String = ""

## For Elite nodes: the elite enemy data array.
var elite_wave: Array = []

## Whether this node has been completed in the current run.
var completed: bool = false

## Whether the prize was stolen (surprise combat on prize node).
var prize_stolen: bool = false

func _to_string() -> String:
	return "<MapNode %s (%s) col=%d row=%d>" % [label, TYPE_LABELS.get(node_type, "?"), col, row]
