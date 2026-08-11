extends Node2D
class_name Grave
## Persistent marker at a unit's death location. Tracks the dead unit's
## identity so future resurrection mechanics can query and target it.
## Has no HP, can't be attacked, no AI — it's a static visual + data.

## UnitData reference of the dead unit. Null if data was freed.
var unit_data: Resource = null
## Death round (GameState.rounds_completed at time of death).
var death_round: int = 0
## Optional display tint inherited from the dead unit.
var tint: Color = Color(0.3, 0.3, 0.35, 1.0)

@onready var _sprite: ColorRect = $Sprite
@onready var _label: Label = $Label

func _ready() -> void:
	add_to_group(&"graves")
	if _sprite:
		_sprite.color = tint
	if _label:
		_label.text = unit_data.display_name if unit_data != null else "Grave"
		_label.modulate = Color(1, 1, 1, 0.5)

## Returns the unit_data_id (or display_name as a fallback) for queries.
func get_unit_id() -> StringName:
	if unit_data != null:
		return unit_data.id
	return &""