extends Node
class_name TouchInputHandler
## Captures screen touch / mouse input and routes it to weapon pickups
## (drag-to-equip) and units (tap to show HP bar, double-tap to unequip).
##
## Mounted at /root/TouchInputHandler via autoload. Listens to
## InputEventScreenTouch, InputEventScreenDrag, and InputEventMouseButton
## / InputEventMouseMotion (so the same logic works on touch and in the
## editor with a mouse).

## Distance threshold below which a tap counts as a "second tap" for
## double-tap detection (per spec: negligible drag distance between taps).
const DOUBLE_TAP_MAX_DIST: float = 50.0
## Time window for two taps to count as a double-tap.
const DOUBLE_TAP_WINDOW: float = 0.35

## Active drag state (per finger / mouse button index).
class DragState:
	var pickup: WeaponPickup = null
	var pos: Vector2 = Vector2.ZERO
	var pressed_at: float = 0.0

var _drags: Dictionary = {}  # int (button index) -> DragState
## Last tap on a unit (for double-tap detection).
var _last_unit_tap_time: float = 0.0
var _last_unit_tap_unit: BaseUnit = null
var _last_unit_tap_screen_pos: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# 'H' key toggles HP snapshot overview.
		if event.keycode == KEY_H:
			_show_all_hp_snapshots()
			return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		_start_drag(ev.index, ev.position)
	else:
		_end_drag(ev.index, ev.position)

func _handle_drag(ev: InputEventScreenDrag) -> void:
	_update_drag(ev.index, ev.position)

func _handle_mouse_button(ev: InputEventMouseButton) -> void:
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_start_drag(0, ev.position)
		else:
			_end_drag(0, ev.position)

func _handle_mouse_motion(ev: InputEventMouseMotion) -> void:
	_update_drag(0, ev.position)

func _start_drag(idx: int, screen_pos: Vector2) -> void:
	# Look for a weapon pickup under the tap point (screen space distance).
	var pickup: WeaponPickup = _pickup_at(screen_pos)
	if pickup != null:
		var st := DragState.new()
		st.pickup = pickup
		st.pos = screen_pos
		st.pressed_at = Time.get_ticks_msec() / 1000.0
		_drags[idx] = st
		pickup.start_drag(screen_pos)
		return

	# Check if it's a unit (for tap-to-show-HP and double-tap unequip).
	var unit: BaseUnit = _unit_at(screen_pos)
	if unit != null:
		var now: float = Time.get_ticks_msec() / 1000.0
		var screen_dist: float = (screen_pos - _last_unit_tap_screen_pos).length()
		if (now - _last_unit_tap_time) < DOUBLE_TAP_WINDOW \
				and _last_unit_tap_unit == unit \
				and screen_dist < DOUBLE_TAP_MAX_DIST:
			# Double tap → unequip.
			unit.unequip_weapon()
			_last_unit_tap_unit = null
			return

		_last_unit_tap_time = now
		_last_unit_tap_unit = unit
		_last_unit_tap_screen_pos = screen_pos

		# Single tap: show the unit's HP bar above it.
		if unit.has_method("show_hp_on_tap"):
			unit.show_hp_on_tap()
		return

	# No pickup and no unit tapped — check if touch is outside arena during combat.
	var outside: bool = _is_outside_arena(screen_pos)
	var combat: bool = _is_in_combat()
	if outside and combat:
		_show_all_hp_snapshots()

func _update_drag(idx: int, pos: Vector2) -> void:
	if _drags.has(idx):
		var st: DragState = _drags[idx]
		if st.pickup != null:
			st.pickup.update_drag(pos)

func _end_drag(idx: int, pos: Vector2) -> void:
	if _drags.has(idx):
		var st: DragState = _drags[idx]
		if st.pickup != null:
			# Final position before release.
			st.pickup.update_drag(pos)
			st.pickup.end_drag()
		_drags.erase(idx)

## Returns true if screen_pos is outside the arena rectangle.
func _is_outside_arena(screen_pos: Vector2) -> bool:
	# Try to get arena bounds from a player's arena_rect (set by Arena on spawn).
	for n in get_tree().get_nodes_in_group(&"player_units"):
		var u: BaseUnit = n as BaseUnit
		if u == null:
			continue
		# Check if arena_rect property exists and is non-null.
		var arena_rect_val = u.get(&"arena_rect")
		if arena_rect_val != null:
			var arena_rect: Rect2 = arena_rect_val
			return not arena_rect.has_point(screen_pos)

	# Fallback: check if within safe margin from viewport edges (~50px margin).
	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	var margin: float = 50.0
	var safe_rect := Rect2(
		vp_rect.position + Vector2(margin, margin),
		vp_rect.size - Vector2(margin * 2, margin * 2)
	)
	return not safe_rect.has_point(screen_pos)

## Returns true if the game is currently in combat.
func _is_in_combat() -> bool:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null:
		return gs.phase == 4  # Phase.COMBAT
	return false

## Show HP snapshots on all alive player and enemy units when touching outside the arena.
func _show_all_hp_snapshots() -> void:
	# Show HP snapshot on all player units.
	for n in get_tree().get_nodes_in_group(&"player_units"):
		var u: BaseUnit = n as BaseUnit
		if u != null and u.current_hp > 0 and u.has_method("show_hp_snapshot"):
			u.show_hp_snapshot()
	# Show HP snapshot on all enemy units.
	for n in get_tree().get_nodes_in_group(&"enemy_units"):
		var u: BaseUnit = n as BaseUnit
		if u != null and u.current_hp > 0 and u.has_method("show_hp_snapshot"):
			u.show_hp_snapshot()

## Find the topmost WeaponPickup whose HitBox contains screen-space `pos`.
func _pickup_at(screen_pos: Vector2) -> WeaponPickup:
	# Convert screen pos to world space for accurate distance.
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	for n in get_tree().get_nodes_in_group(&"weapon_pickups"):
		var p: WeaponPickup = n
		if p == null:
			continue
		if (p.global_position - world_pos).length() <= 40.0:
			return p
	return null

## Find the topmost player BaseUnit under screen-space `pos`.
## Converts screen pos to world space before distance check.
func _unit_at(screen_pos: Vector2) -> BaseUnit:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var nearest: BaseUnit = null
	var best_dist: float = INF
	for n in get_tree().get_nodes_in_group(&"player_units"):
		var u: BaseUnit = n as BaseUnit
		if u == null or u.current_hp <= 0:
			continue
		var d: float = (u.global_position - world_pos).length()
		if d < best_dist:
			best_dist = d
			nearest = u
	# Hit threshold: ~50px world-space radius (half a unit's visual width).
	if best_dist <= 60.0:
		return nearest
	return null

## Convert a screen-space position to world-space using the active camera.
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		return cam.get_global_mouse_position()
	# Fallback: assume screen_pos is already world-space.
	return screen_pos
