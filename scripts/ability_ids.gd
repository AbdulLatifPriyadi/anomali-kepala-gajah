class_name AbilityIds
extends RefCounted

## Central registry of ability IDs. Each ability is a small integer so
## UnitData can reference it cheaply. New abilities: append a new
## constant, add a handler in base_unit.gd's _apply_ability / _tick_ability.

const NONE: int = 0
const FLEE: int = 1     ## Run from nearest enemy. Cannot counter-attack.
const DRACULA: int = 2  ## Lifesteal: heal 50% of damage dealt on attack.
const FAST: int = 3     ## Movement speed is doubled (2x).

static func name_of(id: int) -> String:
	match id:
		0: return "None"
		1: return "Flee"
		2: return "Dracula"
		3: return "Fast"
		_: return "Unknown(%d)" % id
