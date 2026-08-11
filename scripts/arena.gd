extends ColorRect
class_name Arena
## Central arena controller. Owns the gameplay loop within the arena:
##   - Spawns player units and enemy waves from data resources.
##   - Drives combat tick (resolves enemy-vs-player collisions).
##   - Manages weapon pickup proximity for enemies.
##   - Creates Graves when units die.
##   - Detects round-end (all enemies dead) and signals MobileScene.
##
## This is a single node that lives at /MobileScene/Arena. It listens to
## GameState phase transitions to know when to spawn waves, etc.

## PackedScene to instantiate for any BaseUnit (player + enemy).
@export var base_unit_scene: PackedScene

## PackedScene for the Grave marker.
@export var grave_scene: PackedScene

## Per-spawn horizontal stride so multiple spawns spread out.
@export var spawn_stride: float = 70.0

## How many units deep the spawn row goes (vertical offset multiplier).
@export var spawn_vertical_step: float = 50.0

## Liveset: every BaseUnit alive in the arena. Refreshed each frame.
var _units: Array[BaseUnit] = []
## Row counters for spread-spawning.
var _spawn_count: int = 0
## Per-row vertical slot counter.
var _row_count: int = 0
## Position of the last enemy death — used as the epicenter for the
## victory knockback burst when the wave clears.
var _last_enemy_death_pos: Vector2 = Vector2.ZERO
## Guard: victory knockback fires once per combat session. Reset when
## a new wave is spawned to ensure it triggers again on the next wave.
var _victory_knockback_fired: bool = false

## Signal: a player unit died (arena drops a Grave, MobileScene removes
## from roster).
signal player_unit_died(unit: BaseUnit, grave_pos: Vector2)
## Signal: an enemy died.
signal enemy_unit_died(unit: BaseUnit)
## Signal: all enemies in the wave are dead — round ends.
signal wave_cleared()
## Signal: a Grave was created (for UI/debug).
signal grave_created(grave: Node)

func _ready() -> void:
	add_to_group(&"arena")
	# Subscribe to GameState phase changes. Use /root/GameState instead
	# of the bare `GameState` identifier so we don't depend on the
	# autoload-identifier cache being warm at compile time.
	get_node("/root/GameState").combat_ended.connect(_on_combat_ended)
	# Connect unit died signals: handled per-spawn below.

## Spawn a BaseUnit from a UnitData resource. Returns the unit (already
## added to the scene tree). faction is taken from unit_data.
## spawn_index is unused (kept for API compat) — position is random.
func spawn_unit(unit_data: Resource, _spawn_index: int) -> BaseUnit:
	if unit_data == null:
		push_warning("Arena: spawn_unit called with null unit_data")
		return null
	if base_unit_scene == null:
		base_unit_scene = preload("res://scenes/base_unit.tscn")
	var u: BaseUnit = base_unit_scene.instantiate()
	u.unit_data = unit_data
	# Double HP for longer games. Must call _apply_data_to_self() after
	# setting _hp_scale because _ready() already ran during instantiate()
	# with the default _hp_scale=1.0.
	u._hp_scale = 2.0
	u.apply_data_to_self()
	# Place the unit at a random position inside the arena. The inner
	# margin matches the unit's clamp radius in base_unit.gd so the
	# visible sprite can't poke outside the arena edge.
	u.position = _random_arena_position(u.unit_data.faction)
	# arena_rect is in GLOBAL coordinates so the unit's clamp check
	# (which uses global_position) actually matches the arena's
	# position on screen.
	u.arena_rect = Rect2(global_position, size)
	add_child(u)
	u.died.connect(_on_unit_died)
	_units.append(u)
	return u

## Compute a random spawn position inside the arena.
## Faction-aware margin: players have ~80px clamp radius (4x Anomali),
## enemies have ~70px clamp radius (4x Player.png).
func _random_arena_position(faction: int) -> Vector2:
	var margin: float = 80.0 if faction == 0 else 70.0
	var sx: float = randf_range(margin, size.x - margin)
	var sy: float = randf_range(margin, size.y - margin)
	return Vector2(sx, sy)

## Spawn an entire enemy wave (array of UnitData). Returns the units.
## Each enemy spawns at a random arena position.
func spawn_wave(enemy_data: Array) -> Array[BaseUnit]:
	var spawned: Array[BaseUnit] = []
	_spawn_count = 0
	_row_count = 0
	# Reset victory knockback guard so the burst fires for this new wave.
	_victory_knockback_fired = false
	_last_enemy_death_pos = Vector2.ZERO
	for data in enemy_data:
		var u: BaseUnit = spawn_unit(data, _spawn_count)
		_spawn_count += 1
		if u:
			spawned.append(u)
	return spawned

## Spawn a player unit from a prize pick. Returns the unit.
## Player units spawn at a random arena position.
func spawn_player_unit(unit_data: Resource, spawn_index: int) -> BaseUnit:
	_spawn_count = spawn_index
	return spawn_unit(unit_data, spawn_index)

## Drop a weapon pickup into the arena. Origin flags are tracked.
func drop_weapon(weapon: Resource, pos: Vector2, origin: String, instance_id: int) -> void:
	if weapon == null:
		return
	# Convert local pos if needed (callers pass global pos).
	# Use /root/WeaponManager (autoload path) instead of the bare
	# identifier to avoid depending on autoload-identifier cache.
	var wm: Node = get_node_or_null("/root/WeaponManager")
	if wm:
		wm.call("drop_weapon", weapon, pos, origin, instance_id)

## Per-frame combat tick. Drives all units' _physics_process (already
## called automatically by Godot) — we just check for wave-cleared.
func _process(_delta: float) -> void:
	# Tick weapon pickups (enemy proximity).
	var wm: Node = get_node_or_null("/root/WeaponManager")
	if wm:
		wm.call("tick_pickups")
		# Tick Genius targeting (rush advantage weapons, avoid debuffs).
		wm.call("apply_genius_targeting")
	# Clear stale genius targets.
	for u in _units:
		if u != null and is_instance_valid(u):
			u.clear_genius_target()
	# Check if the current wave is cleared (only during combat).
	# Use /root/GameState (autoload path) instead of the bare identifier
	# — avoids depending on the autoload-identifier cache being warm.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs and gs.phase == gs.Phase.COMBAT:
		var enemy_count: int = 0
		for u in _units:
			if u != null and is_instance_valid(u) and u.unit_data != null:
				if u.unit_data.faction == 1 and u.current_hp > 0:
					enemy_count += 1
		if enemy_count == 0:
			# Fire victory knockback exactly once per wave.
			if not _victory_knockback_fired:
				_trigger_victory_knockback()
				_victory_knockback_fired = true
			wave_cleared.emit()

## Called by each BaseUnit's died signal.
func _on_unit_died(unit: BaseUnit) -> void:
	if unit == null:
		return
	# Only spawn Graves for player unit deaths. Enemy deaths simply
	# vanish — the enemy faction isn't tracked as a persistent entity
	# in the arena state, so leaving a grave would just clutter the
	# scene without supporting any future mechanic.
	var is_player: bool = unit.unit_data != null and unit.unit_data.faction == 0
	if is_player:
		var grave: Node = null
		if grave_scene == null:
			grave_scene = preload("res://scenes/grave.tscn")
		grave = grave_scene.instantiate()
		grave.unit_data = unit.unit_data
		var gs: Node = get_node_or_null("/root/GameState")
		grave.death_round = int(gs.rounds_completed) if gs else 0
		if unit.unit_data != null:
			grave.tint = unit.unit_data.tint
		grave.position = unit.position
		add_child(grave)
		grave_created.emit(grave)

	# Branch on faction.
	if is_player:
		player_unit_died.emit(unit, unit.position)
	else:
		# Track last enemy death position for victory knockback epicenter.
		_last_enemy_death_pos = unit.global_position
		enemy_unit_died.emit(unit)
	# Remove from _units list (we don't free here — the unit frees itself).
	_units.erase(unit)

## Combat-end hook: healing is handled by mobile_scene._on_wave_cleared()
## after a 2-second delay. This function is intentionally empty to avoid
## double-healing.
func _on_combat_ended() -> void:
	pass
	# GameState's on_combat_ended already incremented rounds_completed.
	# It will transition to ROUND_END, then the mobile scene drives the
	# next phase.

## Get all currently alive player units.
func get_player_units() -> Array[BaseUnit]:
	var out: Array[BaseUnit] = []
	for u in _units:
		if u != null and is_instance_valid(u) and u.current_hp > 0:
			if u.unit_data != null and u.unit_data.faction == 0:
				out.append(u)
	return out

## Get all currently alive enemy units.
func get_enemy_units() -> Array[BaseUnit]:
	var out: Array[BaseUnit] = []
	for u in _units:
		if u != null and is_instance_valid(u) and u.current_hp > 0:
			if u.unit_data != null and u.unit_data.faction == 1:
				out.append(u)
	return out

## Clear all units (used by Reset/New Game).
func clear_all() -> void:
	for u in _units:
		if u != null and is_instance_valid(u):
			u.queue_free()
	_units.clear()
	# Clear graves too.
	for g in get_tree().get_nodes_in_group(&"graves"):
		if g != null and is_instance_valid(g):
			g.queue_free()
	_victory_knockback_fired = false
	_last_enemy_death_pos = Vector2.ZERO

## Victory knockback burst — fires when the last enemy in a wave is defeated.
## Every living player unit is knocked back radially away from the last
## enemy's death position. Force is 20x the normal knockback (strength=20).
## Each unit also flashes white on the knockback frame.
func _trigger_victory_knockback() -> void:
	if _last_enemy_death_pos == Vector2.ZERO:
		# Fallback: use arena center if no enemy death position is recorded.
		_last_enemy_death_pos = global_position + size * 0.5
	for u in _units:
		if u == null or not is_instance_valid(u) or u.current_hp <= 0:
			continue
		if u.unit_data == null or u.unit_data.faction != 0:
			continue
		# Direction: from the epicenter outward toward the unit.
		var dir: Vector2 = (u.global_position - _last_enemy_death_pos).normalized()
		if dir.length() < 0.1:
			# Degenerate case: unit is at the same spot. Push toward arena center.
			var arena_center: Vector2 = global_position + size * 0.5
			dir = (u.global_position - arena_center).normalized()
			if dir.length() < 0.1:
				dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		# Strength 20 = 20x the normal knockback force.
		# impulse = eff_knockback * VICTORY_KNOCKBACK_MULTIPLIER (e.g. 5 * 112 = 560 px/sec)
		u.apply_victory_knockback(dir * u.eff_knockback * u.VICTORY_KNOCKBACK_MULTIPLIER)
