extends Resource
class_name RoadData
## Represents a connection between two map nodes and its road type.

## Road types matching §3 of the map spec.
enum RoadType {
	PLAIN,   ## 1% ambush — default/common road
	FOREST,   ## 10% ambush — common road
	STONE,    ## 5% ambush, tagged "Hard"
	ABYSS,    ## 50% ambush — rare high-risk shortcut
	BRIDGE,   ## 1% ambush, tagged "Hard"
	SPIKE,    ## 0% ambush, guaranteed -2 HP to all units
	MARKET,   ## 10% ambush + guarantees Shop after
}

## Ambush chance for each road type.
const AMBUSH_CHANCE := {
	RoadType.PLAIN:  0.01,
	RoadType.FOREST: 0.10,
	RoadType.STONE:  0.05,
	RoadType.ABYSS:  0.50,
	RoadType.BRIDGE: 0.01,
	RoadType.SPIKE:  0.00,
	RoadType.MARKET: 0.10,
}

## Whether the road is tagged "Hard".
const IS_HARD := {
	RoadType.PLAIN:  false,
	RoadType.FOREST: false,
	RoadType.STONE:  true,
	RoadType.ABYSS:  false,
	RoadType.BRIDGE: true,
	RoadType.SPIKE:  false,
	RoadType.MARKET: false,
}

## Whether the road guarantees a Shop after (regardless of ambush).
const GUARANTEES_SHOP := {
	RoadType.PLAIN:  false,
	RoadType.FOREST: false,
	RoadType.STONE:  false,
	RoadType.ABYSS:  false,
	RoadType.BRIDGE: false,
	RoadType.SPIKE:  false,
	RoadType.MARKET: true,
}

## Display labels for road types.
const TYPE_LABELS := {
	RoadType.PLAIN:  "Plain",
	RoadType.FOREST: "Forest",
	RoadType.STONE:  "Stone [HARD]",
	RoadType.ABYSS:  "Abyss",
	RoadType.BRIDGE: "Bridge [HARD]",
	RoadType.SPIKE:  "Spike Trail",
	RoadType.MARKET: "Market Road",
}

## Tint colors per road type for UI.
const TYPE_TINTS := {
	RoadType.PLAIN:  Color(0.6, 0.5, 0.4, 0.6),
	RoadType.FOREST: Color(0.2, 0.5, 0.2, 0.6),
	RoadType.STONE:  Color(0.5, 0.5, 0.5, 0.6),
	RoadType.ABYSS:  Color(0.1, 0.05, 0.2, 0.6),
	RoadType.BRIDGE: Color(0.4, 0.4, 0.6, 0.6),
	RoadType.SPIKE:  Color(0.7, 0.3, 0.3, 0.6),
	RoadType.MARKET: Color(0.8, 0.6, 0.2, 0.6),
}

## The road type enum.
var road_type: RoadType = RoadType.PLAIN

## Source node index in the map's node array.
var from_node: int = -1

## Destination node index.
var to_node: int = -1

## Whether an ambush was triggered on this road (set at travel time).
var ambush_triggered: bool = false

## Whether the spike damage (-2 HP) was applied.
var spike_damage_applied: bool = false

## Whether the guaranteed shop was triggered (for MARKET road).
var guaranteed_shop: bool = false

## Returns the ambush chance, modified by weather (Rain doubles it).
func get_ambush_chance(weather_active: bool = false) -> float:
	var base: float = AMBUSH_CHANCE.get(road_type, 0.0)
	if weather_active:
		return base * 2.0  # Rain doubles ambush chance
	return base

## Returns true if the spike damage penalty applies.
func has_spike_damage() -> bool:
	return road_type == RoadType.SPIKE and not spike_damage_applied

## Returns true if Shop is guaranteed after traversing this road.
func has_guaranteed_shop() -> bool:
	return GUARANTEES_SHOP.get(road_type, false)

## Static helper: check if a road type guarantees a shop.
## Use this when you don't have a RoadData instance.
static func type_guarantees_shop(rt: int) -> bool:
	var map := {
		0: false,   # PLAIN
		1: false,   # FOREST
		2: false,   # STONE
		3: false,   # ABYSS
		4: false,   # BRIDGE
		5: false,   # SPIKE
		6: true,    # MARKET
	}
	return map.get(rt, false)

func _to_string() -> String:
	return "<Road %s (%s)>" % [TYPE_LABELS.get(road_type, "?"), str(from_node) + "->" + str(to_node)]
