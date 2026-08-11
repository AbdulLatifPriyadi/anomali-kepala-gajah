extends Sprite2D
## Mobile mock-up enemy. Wanders randomly like an NPC, picking new
## directions periodically and never crossing the Arena rectangle (which is
## treated only as a boundary reference -- the enemy is not parented to it).
##
## The animation is intentionally subtle so the enemy reads as a casual
## NPC walker rather than a frantic sprite:
##   * The sprite rotates gently back and forth between -5 and +5 degrees
##     (about 0.087 rad). No snappy rotation towards the move direction.
##   * A slow squash/stretch pulse gives a hint of stepping.
##   * The enemy moves in straight lines, then picks a fresh random
##     direction on a timer (so it looks like it's choosing where to go).

## How fast the enemy walks in pixels per second.
@export var walk_speed: float = 25.0

## Minimum seconds before picking a new direction.
@export var min_dir_change_interval: float = 1.5
## Maximum seconds before picking a new direction.
@export var max_dir_change_interval: float = 3.5

## Radius in viewport pixels that the enemy's outer bounds extend from its
## origin. Keeps the sprite fully inside the arena even when it is large.
@export var enemy_radius: float = 40.0

## Maximum HP for this enemy.
@export var max_hp: int = 10

## Reference to the Arena rectangle. The enemy reads its size and global
## rect to decide where it can walk, but is NOT a child of the Arena.
@export var arena_path: NodePath

## Rotation amplitude in degrees. The sprite oscillates from -amplitude to
## +amplitude around 0.
@export var rotation_amplitude_deg: float = 5.0
## How fast the rotation oscillates (Hz). Lower = more subtle.
@export var rotation_frequency: float = 0.6
## How fast the squash/stretch pulse runs (Hz).
@export var pulse_frequency: float = 2.2
## Strength of the squash/stretch pulse. 0.05 is a subtle hint of stepping.
@export var pulse_amount: float = 0.05

var _arena_rect: Rect2 = Rect2()
var _dir: Vector2 = Vector2.ZERO
var _next_dir_time: float = 0.0
var _walk_phase: float = 0.0
var _rot_phase: float = 0.0
var _base_scale: Vector2 = Vector2.ONE
var _hp: int = 0

signal died

func _ready() -> void:
	_hp = max_hp
	_pick_arena()
	_pick_random_direction()
	_next_dir_time = _new_next_dir_time()
	_base_scale = scale
	# Stagger the rotation phase so two enemies don't bob in unison.
	_rot_phase = randf_range(0.0, TAU)
	_walk_phase = randf_range(0.0, TAU)

func _process(delta: float) -> void:
	# Advance oscillation phases (50% slower than a typical pulse -- the
	# whole walk reads as casual rather than frantic).
	_walk_phase += delta * pulse_frequency * TAU * 0.5
	_rot_phase += delta * rotation_frequency * TAU * 0.5

	# Move in a straight line in the current direction.
	position += _dir * walk_speed * delta

	# Clamp position so the enemy stays inside the arena rectangle. The
	# enemy and the arena share the same world coordinates (both are
	# children of the MobileScene Control), so we can compare positions
	# directly.
	if _arena_rect.size.x > 0.0 and _arena_rect.size.y > 0.0:
		var half := Vector2(enemy_radius, enemy_radius)
		position = position.clamp(
			_arena_rect.position + half,
			_arena_rect.end - half
		)

	# Subtle squash-and-stretch pulse: scale.x and scale.y oscillate around
	# the base scale so the body hints at stepping.
	var pulse: float = sin(_walk_phase) * pulse_amount
	scale = Vector2(
		_base_scale.x * (1.0 + pulse),
		_base_scale.y * (1.0 - pulse)
	)

	# Gentle rotation oscillation from -rotation_amplitude_deg to
	# +rotation_amplitude_deg around 0. Uses a sine wave so it smoothly
	# glides between the two extremes -- never snaps.
	var deg: float = sin(_rot_phase) * rotation_amplitude_deg
	rotation = deg * PI / 180.0

	# Time to choose a new direction?
	_next_dir_time -= delta
	if _next_dir_time <= 0.0:
		_pick_random_direction()
		_next_dir_time = _new_next_dir_time()

func _pick_arena() -> void:
	# Try the exported NodePath first.
	var n: Node = get_node_or_null(arena_path)
	# Fall back to sibling search via parent if the NodePath didn't resolve.
	if n == null and get_parent() != null:
		n = get_parent().get_node_or_null("Arena")
	if n == null:
		push_warning("ArenaEnemy: arena_path is unset or invalid")
		return
	# Read the arena's global rect. The enemy is a sibling of the arena
	# (both children of MobileScene), so its position is in the same world
	# coordinates and we can compare positions directly.
	_arena_rect = n.get_global_rect()
	if _arena_rect.size.x <= 0.0 or _arena_rect.size.y <= 0.0:
		push_warning("ArenaEnemy: arena rect has zero size: %s" % str(_arena_rect))

func _pick_random_direction() -> void:
	# Pick a fully random direction. This makes the enemy feel like an NPC
	# wandering without intent rather than a target-seeker.
	var angle: float = randf_range(0.0, TAU)
	_dir = Vector2(cos(angle), sin(angle)).normalized()

func _new_next_dir_time() -> float:
	return randf_range(min_dir_change_interval, max_dir_change_interval)

## Called by Army units to deal damage.
func take_damage(amount: int) -> void:
	_hp -= amount
	# Red flash on hit.
	modulate = Color(2.0, 0.5, 0.5, 1.0)
	var t := create_tween()
	t.tween_property(self, "modulate", Color.WHITE, 0.2)
	if _hp <= 0:
		_die()

## Returns true when the enemy's HP has dropped to zero or below.
func is_dead() -> bool:
	return _hp <= 0

func _die() -> void:
	died.emit()
	# Collapse and fade out.
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_property(self, "scale", scale * Vector2(0.5, 0.5), 0.5)
	t.finished.connect(queue_free)
