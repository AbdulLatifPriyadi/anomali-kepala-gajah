extends Node
## Procedural roguelike map generator. Creates a branching node graph
## from start (node 0) to Boss (last node), with weighted node types,
## varied road types, and proper convergence to the final Boss node.
##
## Usage:
##   var gen := MapGenerator.new()
##   gen.generate(seed_value)  # optionally pass an int seed
##   var nodes := gen.get_nodes()
##   var roads := gen.get_roads()

const MapNode = preload("res://scripts/map_node.gd")
const RoadData = preload("res://scripts/road_data.gd")

## Number of columns (depth levels) in the map. Start -> Boss = TOTAL_COLS steps.
const TOTAL_COLS: int = 10

## How many rows (vertical branching) the map has.
const ROWS: int = 5

## Visual spacing between nodes (in arbitrary units, scaled by UI).
const NODE_SPACING_X: float = 150.0
const NODE_SPACING_Y: float = 100.0

## Node arrays and road arrays.
var _nodes: Array[MapNode] = []
var _roads: Array[RoadData] = []

## RNG for deterministic generation.
var _rng: RandomNumberGenerator

## Wave generator reference for combat node wave building.
var _wave_gen: Node = null

## ---- Public API ----

## Generate a new map. Pass an optional int seed for determinism.
func generate(seed_value: int = 0) -> void:
	_nodes.clear()
	_roads.clear()
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value if seed_value != 0 else _rng.randi()

	# Build the node grid.
	_build_nodes()
	# Connect nodes with roads.
	_build_roads()
	# Set starting state: node 0 is current and unlocked.
	if _nodes.size() > 0:
		_nodes[0].is_current = true
		_nodes[0].locked = false

## Return all generated nodes.
func get_nodes() -> Array[MapNode]:
	return _nodes

## Return all generated roads.
func get_roads() -> Array[RoadData]:
	return _roads

## Get the current player node.
func get_current_node() -> MapNode:
	for n in _nodes:
		if n.is_current:
			return n
	return null

## Get reachable nodes from the current position.
func get_reachable_nodes() -> Array[MapNode]:
	var result: Array[MapNode] = []
	for n in _nodes:
		if not n.locked:
			result.append(n)
	return result

## Get the road connecting two adjacent nodes (by index).
func get_road(from_idx: int, to_idx: int) -> RoadData:
	for r in _roads:
		if r.from_node == from_idx and r.to_node == to_idx:
			return r
	return null

## Teleport the player to a different row on the same column (Hurricane effect).
func hurricane_move(target_col: int, target_row: int) -> MapNode:
	# Clear current.
	for n in _nodes:
		if n.is_current:
			n.is_current = false
	# Find and set new current.
	for n in _nodes:
		if n.col == target_col and n.row == target_row:
			n.is_current = true
			n.locked = false
			return n
	return null

## Lock all nodes beyond the current position. Called when player advances.
func lock_nodes_beyond(col: int) -> void:
	for n in _nodes:
		if n.col <= col:
			n.locked = false
		else:
			n.locked = true

## Regenerate the map after Earthquake. Replaces all routes.
func regenerate_map() -> void:
	generate(_rng.randi())

## ---- Private helpers ----

func _build_nodes() -> void:
	# Column 0: Start node (always Prize, no combat attached).
	var start: MapNode = _make_node(MapNode.Type.PRIZE, 0, ROWS / 2)
	start.label = "Start"
	start.description = "A safe beginning. Choose your first prize."
	start.locked = false
	_nodes.append(start)

	# Columns 1 through TOTAL_COLS-1: procedural nodes.
	for col in range(1, TOTAL_COLS):
		# Boss is always at the last column.
		if col == TOTAL_COLS - 1:
			var boss: MapNode = _make_node(MapNode.Type.BOSS, col, ROWS / 2)
			boss.label = "Boss"
			boss.description = "The final gate. Defeat the Boss to win."
			_nodes.append(boss)
			continue

		# Regular columns: generate one node per row.
		for row in range(ROWS):
			var node_type: MapNode.Type = _roll_node_type(col, row)
			var n: MapNode = _make_node(node_type, col, row)
			# Configure node content based on type.
			_configure_node(n, col, row, node_type)
			_nodes.append(n)

func _make_node(node_type: MapNode.Type, col: int, row: int) -> MapNode:
	var n := MapNode.new()
	n.node_type = node_type
	n.col = col
	n.row = row
	# Position in a left-to-right horizontal layout.
	# Row 0 is top, ROWS-1 is bottom.
	n.position = Vector2(
		50.0 + float(col) * NODE_SPACING_X,
		100.0 + float(row) * NODE_SPACING_Y
	)
	return n

func _configure_node(n: MapNode, col: int, row: int, node_type: MapNode.Type) -> void:
	match node_type:
		MapNode.Type.PRIZE:
			n.label = "Prize"
			n.description = "Choose a unit to recruit."
			n.wave_difficulty = ""
		MapNode.Type.CHALLENGE:
			n.label = "Combat"
			n.description = "A standard fight."
			n.wave_difficulty = "easy"
		MapNode.Type.CHALLENGE_HARD:
			n.label = "Combat+"
			n.description = "A harder fight."
			n.wave_difficulty = "hard"
		MapNode.Type.ELITE:
			n.label = "Elite"
			n.description = "A dangerous elite enemy awaits."
			n.wave_difficulty = "elite"
		MapNode.Type.BOSS:
			n.label = "Boss"
			n.description = "The final battle."
			n.wave_difficulty = "boss"
		MapNode.Type.REST:
			n.label = "Rest"
			n.description = "Heal your army. Upgrade a unit."
			n.wave_difficulty = ""
		MapNode.Type.SHOP:
			n.label = "Shop"
			n.description = "Spend gold on upgrades."
			n.wave_difficulty = ""
		MapNode.Type.ADVENTURE:
			n.label = "Event"
			n.description = _roll_adventure_description()
			n.wave_difficulty = ""

func _roll_adventure_description() -> String:
	var descs: Array = [
		"A distorted recording plays. Something shifts in the shadows.",
		"An abandoned campfire. The ashes are still warm.",
		"A child's drawing on the wall. The eyes follow you.",
		"A radio crackles. It knows your name.",
		"An empty room. The floor is wet.",
		"A mirror reflects someone else.",
		"Tape reels spin on their own. Rewind or fast-forward?",
		"An old photograph. A familiar face you don't recognize.",
	]
	return descs[_rng.randi() % descs.size()]

func _roll_node_type(col: int, row: int) -> MapNode.Type:
	# Column 0 is the start node — handled before this loop.
	# Boss column is handled before this loop.
	# Special structural gates:
	#   Row 0: path convergence near boss (3 boss-adjacent nodes).
	#   Elite gate around col 5-6 (always at least one elite on any path).
	#   Prize appears every 2-3 columns on average.

	var depth_fraction := float(col) / float(TOTAL_COLS)

	# Always converge rows toward the center as we approach the boss.
	var convergence: float = abs(float(row) - float(ROWS) / 2.0) / float(ROWS)
	if depth_fraction > 0.8 and convergence > 0.5:
		# Dead-end nodes near boss convergence: lighter types only.
		return _weighted_pick({
			MapNode.Type.CHALLENGE: 3,
			MapNode.Type.REST: 1,
			MapNode.Type.ADVENTURE: 1,
		})

	# Elite gate: col 5-6, roughly 1-2 elites visible.
	if col >= 4 and col <= 7 and row == ROWS / 2:
		return _weighted_pick({
			MapNode.Type.ELITE: 2,
			MapNode.Type.CHALLENGE_HARD: 2,
			MapNode.Type.CHALLENGE: 1,
		})

	# Prize every ~2 columns.
	if col % 2 == 0:
		return _weighted_pick({
			MapNode.Type.PRIZE: 3,
			MapNode.Type.CHALLENGE: 1,
			MapNode.Type.REST: 1,
		})

	# Standard column: weighted mix.
	return _weighted_pick({
		MapNode.Type.CHALLENGE: 3,
		MapNode.Type.CHALLENGE_HARD: 2,
		MapNode.Type.ELITE: 1,
		MapNode.Type.REST: 2,
		MapNode.Type.SHOP: 1,
		MapNode.Type.ADVENTURE: 2,
	})

## Weighted pick: keys are enum values, values are weights.
func _weighted_pick(weights: Dictionary) -> MapNode.Type:
	var total: int = 0
	for w in weights.values():
		total += w as int
	var roll: int = _rng.randi() % total
	var cumulative: int = 0
	for key in weights.keys():
		cumulative += weights[key] as int
		if roll < cumulative:
			return key as MapNode.Type
	return MapNode.Type.CHALLENGE

func _build_roads() -> void:
	# For each non-last column, connect row-level nodes to the next column.
	for col in range(TOTAL_COLS - 1):
		var from_nodes: Array = _get_nodes_in_col(col)
		var to_nodes: Array = _get_nodes_in_col(col + 1)

		for fn in from_nodes:
			# Each from-node connects to up to 2 to-nodes (nearby rows).
			var candidates: Array = []
			for tn in to_nodes:
				if abs(tn.row - fn.row) <= 1:
					candidates.append(tn)
			# Always connect at least to the aligned row.
			for tn in to_nodes:
				if tn.row == fn.row:
					candidates.append(tn)
			# Deduplicate and pick up to 2.
			var seen: Dictionary = {}
			var unique: Array = []
			for c in candidates:
				if not seen.get(c.row, false):
					seen[c.row] = true
					unique.append(c)
			unique.sort_custom(func(a, b): return abs(a.row - fn.row) < abs(b.row - fn.row))
			var limit: int = 2 if unique.size() > 1 else 1
			for i in range(mini(limit, unique.size())):
				var tn: MapNode = unique[i] as MapNode
				var road: RoadData = RoadData.new()
				road.from_node = _nodes.find(fn)
				road.to_node = _nodes.find(tn)
				road.road_type = _roll_road_type(fn, tn)
				_roads.append(road)

func _get_nodes_in_col(col: int) -> Array[MapNode]:
	var result: Array[MapNode] = []
	for n in _nodes:
		if n.col == col:
			result.append(n)
	return result

func _roll_road_type(from: MapNode, to: MapNode) -> RoadData.RoadType:
	# Majority of roads are Plain or Forest.
	var roll: float = _rng.randf()
	if roll < 0.40:
		return RoadData.RoadType.PLAIN
	if roll < 0.75:
		return RoadData.RoadType.FOREST
	if roll < 0.83:
		return RoadData.RoadType.STONE
	if roll < 0.88:
		return RoadData.RoadType.ABYSS
	if roll < 0.92:
		return RoadData.RoadType.BRIDGE
	if roll < 0.96:
		return RoadData.RoadType.SPIKE
	return RoadData.RoadType.MARKET
