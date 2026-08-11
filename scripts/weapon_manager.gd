extends Node
## Manages weapon pickups in the arena: spawning new pickups (from
## death drops, unequips, Shop, or Explore) and resolving enemy
## proximity-pickups each tick.
##
## Registered as autoload at /root/WeaponManager. Other systems call
## spawn_pickup(weapon, position, origin, instance_id) to drop a
## weapon into the arena.

@export var pickup_scene: PackedScene

## Active Genius-tagged units (both players and enemies). Cached for
## fast iteration; refreshed each tick.
func _ready() -> void:
	# Try to load pickup scene lazily if not assigned in editor.
	if pickup_scene == null:
		pickup_scene = preload("res://scenes/weapon_pickup.tscn")

## Spawn a weapon pickup in the arena at the given position. origin is
## "enemy_default" / "player_drop" / "" (shop/encounter origin).
## `launch_from`: if set, the pickup flies 400px away from that position
## after `delay` seconds (ease-out tween).
func spawn_pickup(weapon_data: Resource, pos: Vector2, origin: String, instance_id: int, launch_from: Vector2 = Vector2(-99999.0, -99999.0), launch_delay: float = 0.0) -> void:
	if weapon_data == null:
		return
	var p: WeaponPickup = pickup_scene.instantiate()
	p.weapon_data = weapon_data
	p.source = origin
	p.origin_instance_id = instance_id
	p.global_position = pos
	# Add to the Arena node so positioning/world-space matches units.
	var arena: Node = get_tree().root.get_node_or_null("MobileScene/Arena")
	if arena != null:
		arena.add_child(p)
		# Pass arena bounds so the pickup can clamp its landing position.
		if arena is ColorRect:
			var cr: ColorRect = arena as ColorRect
			p._arena_rect = Rect2(arena.global_position, cr.size)
	else:
		get_tree().root.add_child(p)
	# Run setup AFTER adding to tree so _ready + children are valid.
	p.setup(weapon_data, origin, instance_id)
	# If launch_from is valid, animate the pickup flying away from that point.
	if launch_from.x > -90000.0:
		p.launch_away_from(launch_from, 400.0, launch_delay)

## Resolve enemy proximity pickups. Called each physics tick by the Arena.
func tick_pickups() -> void:
	# Iterate over all pickup HitBoxes and check for enemy overlap.
	for pickup in get_tree().get_nodes_in_group(&"weapon_pickups"):
		var p: WeaponPickup = pickup
		if p == null:
			continue
		for body in p._hit_box.get_overlapping_bodies():
			var u: BaseUnit = body as BaseUnit
			if u == null:
				continue
			if u.is_in_group(&"enemy_units") and p.try_enemy_pickup(u):
				break

## Apply Genius AI rush/avoid priority: if any Genius unit exists and
## a pickup in the arena is an &"advantage" weapon, Genius units
## path-find toward it. Called by Arena each tick.
func apply_genius_targeting() -> void:
	var genius_units: Array = []
	for n in get_tree().get_nodes_in_group(&"units"):
		var u: BaseUnit = n as BaseUnit
		if u != null and u.has_tag(&"genius"):
			genius_units.append(u)
	if genius_units.is_empty():
		return
	# Find best advantage pickup per genius.
	for u in genius_units:
		var best: WeaponPickup = null
		var best_d: float = INF
		for p in get_tree().get_nodes_in_group(&"weapon_pickups"):
			var wp: WeaponPickup = p
			if wp == null or wp.weapon_data == null:
				continue
			if not wp.weapon_data.is_advantage():
				continue  # genius ignores non-advantages
			var d: float = (wp.global_position - u.global_position).length()
			if d < best_d:
				best_d = d
				best = wp
		if best != null:
			# Override unit's target: chase the pickup until in HitBox, where
			# tick_pickups handles the actual equip. We do this by
			# exposing _target_override on the unit.
			u._genius_target = best
			u._genius_has_target = true

## Spawn a weapon for shop/explore (not dropped, freshly generated).
func spawn_new(weapon_data: Resource, pos: Vector2) -> void:
	spawn_pickup(weapon_data, pos, "", randi())

## Public helper to drop a weapon at a position (player unequip/replace).
func drop_weapon(weapon_data: Resource, pos: Vector2, origin: String, instance_id: int) -> void:
	spawn_pickup(weapon_data, pos, origin, instance_id)
